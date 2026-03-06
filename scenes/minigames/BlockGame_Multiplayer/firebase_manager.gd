# firebase_manager.gd — Gestion Firebase (HTTP REST)
# Compatible Godot 4.x
extends Node

@export var firebase_url  : String = "https://blocky-battle-default-rtdb.europe-west1.firebasedatabase.app/"
@export var firebase_auth : String = ""

var game_id      : String = ""
var player_key   : String = "player1"
var opp_key      : String = "player2"

# ─── IDs lisibles des joueurs (remplis par le lobby) ─────────────────────────
var my_pid  : String = ""   # ex: "xk92ma3bqf1z"
var opp_pid : String = ""   # ex: "r7tn40wlc8dv"

var _poll_timer     : float = 0.0
const POLL_INTERVAL : float = 1.2

var _last_move_ts : float = 0.0
var _is_connected : bool  = false

var _grid  : Node = null
var _timer : Node = null

signal opponent_move_received(move: Dictionary)
signal connection_error(message: String)

# ══════════════════════════════════════════════════════════════════════════════
func init(p_game_id: String, is_player1: bool):
	game_id       = p_game_id
	player_key    = "player1" if is_player1 else "player2"
	opp_key       = "player2" if is_player1 else "player1"
	_is_connected = true
	print("[Firebase] Init — game: %s | joueur: %s" % [game_id, player_key])

# Appelé par le lobby juste avant le changement de scène
func set_player_ids(my_id: String, opponent_id: String):
	my_pid  = my_id
	opp_pid = opponent_id

func setup_scene_refs():
	_grid  = get_tree().root.find_child("GridMultiplayer",  true, false)
	_timer = get_tree().root.find_child("GameStateManager", true, false)

# ══════════════════════════════════════════════════════════════════════════════
#  POLLING
# ══════════════════════════════════════════════════════════════════════════════
func _process(delta):
	if not _is_connected or game_id.is_empty(): return
	_poll_timer += delta
	if _poll_timer >= POLL_INTERVAL:
		_poll_timer = 0.0
		_fetch_opponent_state()

func _fetch_opponent_state():
	fb_get("/games/%s/%s.json" % [game_id, opp_key], _on_opponent_state)

func _on_opponent_state(data):
	if typeof(data) != TYPE_DICTIONARY or data.is_empty(): return

	var ts = float(data.get("last_move_ts", 0.0))
	if ts > _last_move_ts:
		_last_move_ts = ts
		var move = data.get("last_move", {})
		if typeof(move) == TYPE_DICTIONARY and not move.is_empty():
			emit_signal("opponent_move_received", move)
			_apply_opponent_move(move)

	if _grid and _grid.has_method("sync_opponent_stats"):
		_grid.sync_opponent_stats(int(data.get("hp", 3000)), int(data.get("shield", 0)))

func _apply_opponent_move(move: Dictionary):
	if not _grid: return

	var raw_coords = move.get("coords", [])
	var is_atk     = bool(move.get("is_attack", false))
	var color      = _hex_to_color(str(move.get("color", "#FF4444")))
	var multi      = float(move.get("dmg_multi", 1.0))

	var mirrored : Array = []
	for c in raw_coords:
		var raw = c if typeof(c) == TYPE_VECTOR2 else Vector2(int(c.get("x", 0)), int(c.get("y", 0)))
		mirrored.append(Vector2(int(raw.x), (int(raw.y) + 6) % 12))

	_grid.place_piece(mirrored, color, is_atk, multi, false)

# ══════════════════════════════════════════════════════════════════════════════
#  PUSH
# ══════════════════════════════════════════════════════════════════════════════
func push_move(coords_list: Array, piece_color: Color, is_attack: bool):
	if not _is_connected or game_id.is_empty() or not _grid: return

	var dmg_multi = float(_timer.get_damage_multiplier()) if _timer and _timer.has_method("get_damage_multiplier") else 1.0

	var coords_serial = []
	for c in coords_list:
		coords_serial.append({"x": int(c.x), "y": int(c.y)})

	var payload = _grid.serialize_player_state()
	payload["last_move"] = {
		"coords":    coords_serial,
		"is_attack": is_attack,
		"color":     _color_to_hex(piece_color),
		"dmg_multi": dmg_multi
	}
	payload["last_move_ts"] = Time.get_unix_time_from_system()

	fb_patch("/games/%s/%s.json" % [game_id, player_key], JSON.stringify(payload))

func push_stats_only():
	if not _is_connected or game_id.is_empty() or not _grid: return
	fb_patch("/games/%s/%s.json" % [game_id, player_key],
		JSON.stringify({"hp": _grid.player_hp, "shield": _grid.player_shield}))

# ══════════════════════════════════════════════════════════════════════════════
#  HTTP
# ══════════════════════════════════════════════════════════════════════════════
func fb_get(path: String, callback: Callable):
	var http = HTTPRequest.new()
	add_child(http)
	var url = firebase_url.rstrip("/") + path
	if firebase_auth != "":
		url += "?auth=" + firebase_auth
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
	var url = firebase_url.rstrip("/") + path
	if firebase_auth != "":
		url += "?auth=" + firebase_auth
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_PATCH, body)

func fb_delete(path: String):
	var http = HTTPRequest.new()
	add_child(http)
	var url = firebase_url.rstrip("/") + path
	if firebase_auth != "":
		url += "?auth=" + firebase_auth
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	http.request(url, [], HTTPClient.METHOD_DELETE)

# ══════════════════════════════════════════════════════════════════════════════
#  UTILITAIRES
# ══════════════════════════════════════════════════════════════════════════════
func _color_to_hex(c: Color) -> String:
	return "#%02X%02X%02X" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]

func _hex_to_color(h: String) -> Color:
	return Color(h) if h.begins_with("#") else Color.WHITE
