# firebase_manager.gd — Gestion Firebase (HTTP REST)
# Compatible Godot 4.x
extends Node

@export var firebase_url  : String = "https://blocky-battle-default-rtdb.europe-west1.firebasedatabase.app/"
@export var firebase_auth : String = ""

var game_id      : String = ""
var player_key   : String = "player1"
var opp_key      : String = "player2"

# ─── IDs lisibles des joueurs (remplis par le lobby) ─────────────────────────
var my_pid  : String = ""
var opp_pid : String = ""

var _poll_timer     : float = 0.0
const POLL_INTERVAL : float = 1.2

# ─── Gestion du temps & inactivité ───────────────────────────────────────────
const INACTIVITY_TIMEOUT : float = 40.0   # ← 40s sans jouer = forfait
const GRACE_PERIOD       : float = 5.0    # ← délai avant d'activer les timers

var _last_move_ts         : float = 0.0   # Dernier timestamp de mouvement adversaire (Firebase)
var _last_opp_activity_ts : float = 0.0   # Quand on a reçu un nouveau coup adversaire
var _local_last_action_ts : float = 0.0   # Quand le joueur local a posé sa dernière pièce
var _game_start_ts        : float = 0.0   # Timestamp Unix du début de partie

var _is_connected   : bool = false
var _game_over_sent : bool = false         # ← Verrou anti double-envoi de fin de partie

var _grid  : Node = null
var _timer : Node = null

signal opponent_move_received(move: Dictionary)
signal connection_error(message: String)
signal game_finished(winner_id: String)

# ══════════════════════════════════════════════════════════════════════════════
#  INITIALISATION
# ══════════════════════════════════════════════════════════════════════════════
func init(p_game_id: String, is_player1: bool):
	game_id         = p_game_id
	player_key      = "player1" if is_player1 else "player2"
	opp_key         = "player2" if is_player1 else "player1"
	_is_connected   = true
	_game_over_sent = false
	_last_move_ts   = 0.0

	var now               = Time.get_unix_time_from_system()
	_game_start_ts        = now
	_last_opp_activity_ts = now
	_local_last_action_ts = now

	print("[Firebase] Init — game: %s | joueur: %s" % [game_id, player_key])

func set_player_ids(my_id: String, opponent_id: String):
	my_pid  = my_id
	opp_pid = opponent_id

func setup_scene_refs():
	_grid  = get_tree().root.find_child("GridMultiplayer",  true, false)
	_timer = get_tree().root.find_child("GameStateManager", true, false)

# ══════════════════════════════════════════════════════════════════════════════
#  POLLING & PROCESS
# ══════════════════════════════════════════════════════════════════════════════
func _process(delta):
	if not _is_connected or game_id.is_empty(): return

	var now     = Time.get_unix_time_from_system()
	var elapsed = now - _game_start_ts

	# ── Détection inactivité (uniquement après la période de grâce) ───────────
	if elapsed > GRACE_PERIOD:

		# Adversaire inactif depuis INACTIVITY_TIMEOUT secondes
		if now - _last_opp_activity_ts > INACTIVITY_TIMEOUT:
			_handle_opponent_abandoned()
			return

		# Joueur local inactif depuis INACTIVITY_TIMEOUT secondes
		if now - _local_last_action_ts > INACTIVITY_TIMEOUT:
			_handle_local_abandoned()
			return

	# ── Poll Firebase ─────────────────────────────────────────────────────────
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_poll_game_data()

func _poll_game_data():
	# Toutes les infos de la partie en une seule requête (optimisation réseau)
	fb_get("/games/%s.json" % game_id, _on_game_data_received)

func _on_game_data_received(data):
	if typeof(data) != TYPE_DICTIONARY or data.is_empty(): return

	# 1. Vérifier si la partie est terminée
	if data.get("status") == "finished":
		var winner = data.get("winner", "")
		_is_connected = false
		if not _game_over_sent:
			_game_over_sent = true
			game_finished.emit(winner)
		return

	# 2. Traiter les données de l'adversaire
	var opp_data = data.get(opp_key, {})
	if typeof(opp_data) == TYPE_DICTIONARY and not opp_data.is_empty():
		_process_opponent_state(opp_data)

func _process_opponent_state(data: Dictionary):
	var ts = float(data.get("last_move_ts", 0.0))
	if ts > _last_move_ts:
		_last_move_ts         = ts
		_last_opp_activity_ts = Time.get_unix_time_from_system()   # ← Reset inactivité adversaire

		var move = data.get("last_move", {})
		if typeof(move) == TYPE_DICTIONARY and not move.is_empty():
			opponent_move_received.emit(move)
			_apply_opponent_move(move)

	if _grid and _grid.has_method("sync_opponent_stats"):
		_grid.sync_opponent_stats(int(data.get("hp", 3000)), int(data.get("shield", 0)))

func _apply_opponent_move(move: Dictionary):
	if not _grid: return

	var coords_data = move.get("coords", [])
	var color_hex   = move.get("color", "#ffffff")
	var color       = Color(color_hex)
	var is_atk      = move.get("is_attack", false)
	var multi       = float(move.get("dmg_multi", 1.0))
	var damage      = int(move.get("damage", 0))

	var mirrored : Array = []
	var cols = 8
	var rows = 12

	for c in coords_data:
		var mirrored_x = (cols - 1) - int(c.x)
		var mirrored_y = (rows - 1) - int(c.y)
		mirrored.append(Vector2(mirrored_x, mirrored_y))

	_grid.place_piece(mirrored, color, is_atk, multi, false, damage)

# ══════════════════════════════════════════════════════════════════════════════
#  GESTION DES FIN DE PARTIE — Point d'entrée unique
# ══════════════════════════════════════════════════════════════════════════════

## Source unique pour déclarer la fin : écrit sur Firebase ET émet le signal local.
## Le flag _game_over_sent empêche tout double-déclenchement.
func declare_winner_and_finish(winner_pid: String):
	if _game_over_sent: return
	_game_over_sent = true
	_is_connected   = false
	notify_game_over(winner_pid)         # ← Écriture Firebase (async)
	game_finished.emit(winner_pid)       # ← Signal local immédiat
	print("[Firebase] Fin de partie — vainqueur : ", winner_pid)

## Appelé quand le joueur local appuie sur Quitter ou ferme l'app.
func notify_player_quit():
	print("[Firebase] Joueur local a quitté — défaite par abandon")
	declare_winner_and_finish(opp_pid)

## Fin par dépassement du timer (appelé par GameStateManager).
## Compare les HP pour désigner le vainqueur.
func declare_winner_by_hp(my_hp: int, opp_hp: int):
	var winner_pid : String
	if my_hp > opp_hp:
		winner_pid = my_pid
	else:
		winner_pid = opp_pid   # Égalité → l'adversaire gagne (avantage défensif)
	print("[Firebase] Fin par timer — HP joueur: %d | HP adverse: %d" % [my_hp, opp_hp])
	declare_winner_and_finish(winner_pid)

# ─── Cas de forfait par inactivité ───────────────────────────────────────────
func _handle_opponent_abandoned():
	print("[Firebase] Adversaire inactif (%.0fs) — victoire par forfait" % INACTIVITY_TIMEOUT)
	declare_winner_and_finish(my_pid)

func _handle_local_abandoned():
	print("[Firebase] Joueur local inactif (%.0fs) — défaite par forfait" % INACTIVITY_TIMEOUT)
	declare_winner_and_finish(opp_pid)

## Écriture brute du résultat sur Firebase (utilisé en interne).
func notify_game_over(winner_id: String):
	var data = {"status": "finished", "winner": winner_id}
	fb_patch("/games/%s.json" % game_id, JSON.stringify(data))

# ══════════════════════════════════════════════════════════════════════════════
#  ÉCRITURE (PUSH)
# ══════════════════════════════════════════════════════════════════════════════
func push_move(coords_list: Array, piece_color: Color, is_attack: bool, damage: int = 0):
	if not _is_connected or game_id.is_empty() or not _grid: return

	_local_last_action_ts = Time.get_unix_time_from_system()   # ← Reset inactivité locale

	var dmg_multi = float(_timer.get_damage_multiplier()) if _timer and _timer.has_method("get_damage_multiplier") else 1.0

	var coords_serial = []
	for c in coords_list:
		coords_serial.append({"x": int(c.x), "y": int(c.y)})

	var payload = _grid.serialize_player_state()
	payload["last_move"] = {
		"coords":    coords_serial,
		"is_attack": is_attack,
		"color":     _color_to_hex(piece_color),
		"dmg_multi": dmg_multi,
		"damage":    damage
	}
	payload["last_move_ts"] = Time.get_unix_time_from_system()

	fb_patch("/games/%s/%s.json" % [game_id, player_key], JSON.stringify(payload))

func push_stats_only():
	if not _is_connected or game_id.is_empty() or not _grid: return
	var payload = {"hp": _grid.player_hp, "shield": _grid.player_shield}
	fb_patch("/games/%s/%s.json" % [game_id, player_key], JSON.stringify(payload))

# ══════════════════════════════════════════════════════════════════════════════
#  HTTP HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func fb_get(path: String, callback: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	var url = firebase_url.rstrip("/") + "/" + path.lstrip("/")
	if firebase_auth != "": url += "?auth=" + firebase_auth

	http.request_completed.connect(func(_r, code, _h, body):
		http.queue_free()
		if code == 200:
			var json = JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				callback.call(json.get_data())
	)
	http.request(url)

func fb_patch(path: String, body: String):
	var http = HTTPRequest.new()
	add_child(http)
	var url = firebase_url.rstrip("/") + "/" + path.lstrip("/")
	if firebase_auth != "": url += "?auth=" + firebase_auth

	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PATCH, body)

func fb_delete(path: String):
	var http = HTTPRequest.new()
	add_child(http)
	var url = firebase_url.rstrip("/") + "/" + path.lstrip("/")
	if firebase_auth != "": url += "?auth=" + firebase_auth

	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(url, [], HTTPClient.METHOD_DELETE)

# ══════════════════════════════════════════════════════════════════════════════
#  UTILITAIRES
# ══════════════════════════════════════════════════════════════════════════════
func _color_to_hex(c: Color) -> String:
	return "#%02X%02X%02X" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]

func _hex_to_color(h: String) -> Color:
	return Color(h) if h.begins_with("#") else Color.WHITE
