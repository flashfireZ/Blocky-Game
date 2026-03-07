# lobby.gd — Matchmaking automatique
# Compatible Godot 4.x
extends Control

const GAME_SCENE    : String = "res://scenes/minigames/BlockGame_Multiplayer/MainBlockGameMultiplayer.tscn"
const POLL_RATE     : float  = 1.5
const QUEUE_TIMEOUT : float  = 45.0

@onready var btn_battle : Button = $BattleBtn
@onready var btn_cancel : Button = $CancelBtn
@onready var lbl_status : Label  = $StatusLabel

var _player_id     : String = ""
var _in_queue      : bool   = false
var _poll_timer    : float  = 0.0
var _queue_timer   : float  = 0.0
var _match_started : bool   = false

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	randomize()
	_player_id = _generate_id()

	if OS.has_feature("debug"):
			_player_id += "_" + str(randi() % 9999)
	_set_ui_idle()

	if not btn_battle.pressed.is_connected(_on_battle_btn_pressed):
		btn_battle.pressed.connect(_on_battle_btn_pressed)
	if not btn_cancel.pressed.is_connected(_on_cancel_btn_pressed):
		btn_cancel.pressed.connect(_on_cancel_btn_pressed)

	print("[Lobby] Démarré — player_id : ", _player_id)

# ══════════════════════════════════════════════════════════════════════════════
# Si le joueur n'a pas encore de pseudo → ouvrir le popup avant de lancer.
func _on_battle_btn_pressed():
	var pseudo : String = _get_saved_pseudo()
	if pseudo == "":
		_open_pseudo_popup()
	else:
		_join_queue()

func _on_cancel_btn_pressed(): _leave_queue()
const PSEUDO_POPUP_SCENE : String = "res://scenes/ui/PseudoPopup.tscn"

func _open_pseudo_popup():
	var popup = load(PSEUDO_POPUP_SCENE).instantiate()
	popup.setup(_player_id)
	popup.pseudo_confirmed.connect(func(_pseudo: String):
		_join_queue()   # popup se supprime tout seul → lancer la recherche
	)
	add_child(popup)
# ══════════════════════════════════════════════════════════════════════════════
#  QUEUE
# ══════════════════════════════════════════════════════════════════════════════
func _join_queue():
	if _in_queue: return
	_in_queue      = true
	_match_started = false
	_queue_timer   = 0.0
	_poll_timer    = 0.0
	_set_ui_searching()

	var payload = JSON.stringify({"ts": Time.get_unix_time_from_system()})
	FirebaseManager.fb_patch("/matchmaking/queue/%s.json" % _player_id, payload)
	print("[Lobby] Inscrit — id: ", _player_id)

func _leave_queue():
	if not _in_queue: return
	_in_queue = false
	_set_ui_idle()
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)
	print("[Lobby] Retiré de la queue")

# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS
# ══════════════════════════════════════════════════════════════════════════════
func _process(delta):
	if not _in_queue or _match_started: return

	_queue_timer += delta
	if _queue_timer >= QUEUE_TIMEOUT:
		_leave_queue()
		lbl_status.text = "Aucun adversaire trouvé.\nRéessaie !"
		return

	var dots = ".".repeat(int(_queue_timer * 2.0) % 4)
	lbl_status.text = "Recherche" + dots

	_poll_timer += delta
	if _poll_timer >= POLL_RATE:
		_poll_timer = 0.0
		_poll()

# ══════════════════════════════════════════════════════════════════════════════
#  POLL
#
#  Architecture du matchmaking :
#
#  P2 (joueur arrivé en dernier) écrit dans /player_matches/{p1_id} UN SEUL
#  document contenant TOUT ce dont P1 a besoin pour lancer la partie :
#    { "gid": "ABCD1234", "opp": "p2_id" }
#
#  P1 ne lit QUE CE DOCUMENT — une seule requête, pas de second read.
#  Comme tout est dans un seul PATCH atomique, il n'y a aucune dépendance
#  sur l'ordre d'arrivée des écritures Firebase.
#
#  P2 lance directement depuis _create_match() — il n'a pas besoin de polling.
#
#  Lectures par poll :
#    P1 → 1 GET ciblé (/player_matches/{p1})
#    P2 → 1 GET ciblé (/player_matches/{p2}) + 1 GET queue si rien trouvé
# ══════════════════════════════════════════════════════════════════════════════
func _poll():

	# ── Lecture ciblée : est-ce que P2 m'a notifié ? ─────────────────────────
	FirebaseManager.fb_get("/player_matches/%s.json" % _player_id, func(data):
		if _match_started or not _in_queue: return

		# P2 a écrit {"gid": game_id, "opp": opponent_id} → on a tout pour lancer
		if typeof(data) == TYPE_DICTIONARY and data.has("gid") and data.has("opp"):
			var game_id     : String = data["gid"]
			var opponent_id : String = data["opp"]
			if game_id != "" and opponent_id != "":
				_launch(game_id, true, opponent_id)
				return

		# ── Rien trouvé : scanner la queue pour créer un match (rôle P2) ─────
		FirebaseManager.fb_get("/matchmaking/queue.json", func(queue):
			if _match_started or not _in_queue: return
			if typeof(queue) != TYPE_DICTIONARY: return

			var opponent_id : String = ""
			var oldest_ts   : float  = INF

			for pid in queue.keys():
				if pid == _player_id: continue
				var entry = queue[pid]
				if typeof(entry) != TYPE_DICTIONARY: continue
				# Ignorer les entrées déjà claimées par quelqu'un d'autre
				var claimed = entry.get("claimed_by", "")
				if claimed != "" and claimed != _player_id: continue
				var ts = float(entry.get("ts", 0))
				if ts < oldest_ts:
					oldest_ts   = ts
					opponent_id = pid

			if opponent_id == "": return

			var my_entry = queue.get(_player_id, null)
			var my_ts    = float(my_entry.get("ts", 0)) if typeof(my_entry) == TYPE_DICTIONARY else 0.0

			# Seul le joueur arrivé LE PLUS TARD crée la partie
			if my_ts > oldest_ts or (my_ts == oldest_ts and _player_id > opponent_id):
				_claim_and_create(opponent_id)
		)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  CLAIM — verrou optimiste anti double-create
# ══════════════════════════════════════════════════════════════════════════════
func _claim_and_create(opponent_id: String):
	if _match_started: return

	FirebaseManager.fb_patch("/matchmaking/queue/%s.json" % opponent_id,
		JSON.stringify({"claimed_by": _player_id}))
	print("[Lobby] Claim posé sur %s" % opponent_id)

	await get_tree().create_timer(0.4).timeout
	if _match_started or not _in_queue: return

	FirebaseManager.fb_get("/matchmaking/queue/%s.json" % opponent_id, func(entry):
		if _match_started or not _in_queue: return
		if typeof(entry) != TYPE_DICTIONARY: return
		if entry.get("claimed_by", "") != _player_id:
			print("[Lobby] Claim perdu sur %s — abandon" % opponent_id)
			return
		_create_match(opponent_id)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  CRÉATION DU MATCH  (exécuté uniquement par P2 après claim confirmé)
# ══════════════════════════════════════════════════════════════════════════════
func _create_match(opponent_id: String):
	if _match_started: return
	_match_started = true

	var game_id : String = _generate_game_id()
	var p1      : String = opponent_id   # plus ancien = p1
	var p2      : String = _player_id    # créateur    = p2

	# ── Écriture principale : tout en UN SEUL document pour P1 ───────────────
	# P1 lira /player_matches/{p1} et aura game_id + opponent_id
	# en une seule requête, sans dépendance sur l'ordre des écritures.
	var notif_p1 = JSON.stringify({"gid": game_id, "opp": p2})
	FirebaseManager.fb_patch("/player_matches/%s.json" % p1, notif_p1)

	# ── Document match (debug / référence) ───────────────────────────────────
	var match_payload = JSON.stringify({
		"p1": p1, "p2": p2,
		"status": "ready",
		"ts": Time.get_unix_time_from_system()
	})
	FirebaseManager.fb_patch("/matchmaking/matches/%s.json" % game_id, match_payload)

	# Retirer les deux joueurs de la queue publique
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % p1)
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % p2)

	print("[Lobby] Match créé — game: %s | p1: %s | p2: %s" % [game_id, p1, p2])
	_launch(game_id, false, p1)   # P2 lance directement

# ══════════════════════════════════════════════════════════════════════════════
#  LANCEMENT
# ══════════════════════════════════════════════════════════════════════════════
func _launch(game_id: String, is_p1: bool, opponent_pid: String):
	_match_started = true
	_in_queue      = false

	FirebaseManager.init(game_id, is_p1)
	FirebaseManager.set_player_ids(_player_id, opponent_pid)

	btn_battle.visible = false
	btn_cancel.visible = false
	lbl_status.text    = "Adversaire trouvé !\nLancement..."
	print("[Lobby] Lancement — game: %s | is_p1: %s | opp: %s" % [game_id, is_p1, opponent_pid])

	# Nettoyage après changement de scène.
	# IMPORTANT : capturer dans des variables locales — le nœud lobby sera
	# libéré après change_scene_to_file, les membres (self._player_id etc.)
	# ne seront plus accessibles depuis la lambda.
	var my_id  : String = _player_id
	var gid    : String = game_id
	var p1_role: bool   = is_p1

	get_tree().create_timer(5.0).timeout.connect(func():
		# Chaque joueur supprime uniquement sa propre notification
		FirebaseManager.fb_delete("/player_matches/%s.json" % my_id)
		# P1 supprime aussi le document match (dernier lecteur)
		if p1_role:
			FirebaseManager.fb_delete("/matchmaking/matches/%s.json" % gid)
	)

	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file(GAME_SCENE)

# ══════════════════════════════════════════════════════════════════════════════
#  UI
# ══════════════════════════════════════════════════════════════════════════════
func _set_ui_idle():
	btn_battle.visible  = true
	btn_battle.disabled = false
	btn_cancel.visible  = false
	lbl_status.text     = "Appuie sur Battle pour jouer !"

func _set_ui_searching():
	btn_battle.visible = false
	btn_cancel.visible = true
	lbl_status.text    = "Recherche..."

# ══════════════════════════════════════════════════════════════════════════════
#  IDs
# ══════════════════════════════════════════════════════════════════════════════

# Persiste l'ID dans user://player.cfg (généré une seule fois)
func _generate_id() -> String:
	var config = ConfigFile.new()
	var path   = "user://player.cfg"

	if config.load(path) == OK:
		var saved = config.get_value("player", "id", "")
		if saved != "": return saved

	const CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = ""
	for _i in range(12): id += CHARS[randi() % CHARS.length()]

	config.set_value("player", "id", id)
	config.save(path)
	return id

# ── 2. Ajoute cette fonction — lit le pseudo sauvegardé localement ───────────
func _get_saved_pseudo() -> String:
	var config = ConfigFile.new()
	if config.load("user://player.cfg") == OK:
		return config.get_value("player", "pseudo", "")
	return ""


func _generate_game_id() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var id = ""
	for _i in range(8): id += CHARS[randi() % CHARS.length()]
	return id

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _in_queue:
			FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)
			print("[Lobby] Nettoyage queue (fermeture)")

const LEADERBOARD_SCENE : String = "res://scenes/ui/LeaderboardScreen.tscn"

func _on_leaderboard_btn_pressed():
	var screen = load(LEADERBOARD_SCENE).instantiate()
	get_tree().root.add_child(screen)    # par-dessus le lobby, pas de changement de scène
