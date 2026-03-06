# lobby.gd — Matchmaking automatique
# Compatible Godot 4.x
extends Control

const GAME_SCENE    : String = "res://scenes/minigames/BlockGame_Multiplayer/MainBlockGameMultiplayer.tscn"
const POLL_RATE     : float  = 1.5
const QUEUE_TIMEOUT : float  = 60.0

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
	_set_ui_idle()

	if not btn_battle.pressed.is_connected(_on_battle_btn_pressed):
		btn_battle.pressed.connect(_on_battle_btn_pressed)
	if not btn_cancel.pressed.is_connected(_on_cancel_btn_pressed):
		btn_cancel.pressed.connect(_on_cancel_btn_pressed)

	print("[Lobby] Démarré — player_id : ", _player_id)

# ══════════════════════════════════════════════════════════════════════════════
#  BOUTONS
# ══════════════════════════════════════════════════════════════════════════════
func _on_battle_btn_pressed(): _join_queue()
func _on_cancel_btn_pressed(): _leave_queue()

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

	var payload = JSON.stringify({"pid": _player_id, "ts": Time.get_unix_time_from_system()})
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
# ══════════════════════════════════════════════════════════════════════════════
func _poll():
	FirebaseManager.fb_get("/matchmaking/matches.json", func(matches):
		if _match_started or not _in_queue: return
		if typeof(matches) == TYPE_DICTIONARY:
			for gid in matches.keys():
				var m = matches[gid]
				if typeof(m) != TYPE_DICTIONARY: continue
				if m.get("p1", "") == _player_id and m.get("status", "") == "ready":
					_launch(gid, true, m.get("p2", "?")); return
				if m.get("p2", "") == _player_id and m.get("status", "") == "ready":
					_launch(gid, false, m.get("p1", "?")); return

		FirebaseManager.fb_get("/matchmaking/queue.json", func(queue):
			if _match_started or not _in_queue: return
			if typeof(queue) != TYPE_DICTIONARY: return

			var opponent_id : String = ""
			var oldest_ts   : float  = INF

			for pid in queue.keys():
				if pid == _player_id: continue
				var entry = queue[pid]
				if typeof(entry) != TYPE_DICTIONARY: continue
				var ts = float(entry.get("ts", 0))
				if ts < oldest_ts:
					oldest_ts   = ts
					opponent_id = pid

			if opponent_id == "": return

			var my_entry = queue.get(_player_id, null)
			var my_ts    = float(my_entry.get("ts", 0)) if typeof(my_entry) == TYPE_DICTIONARY else 0.0

			if my_ts > oldest_ts:
				_create_match(opponent_id)
			elif my_ts == oldest_ts and _player_id > opponent_id:
				_create_match(opponent_id)
		)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  CRÉATION DU MATCH
# ══════════════════════════════════════════════════════════════════════════════
func _create_match(opponent_id: String):
	if _match_started: return
	_match_started = true

	var game_id = _generate_game_id()
	var p1      = opponent_id
	var p2      = _player_id

	var payload = JSON.stringify({
		"p1":     p1,
		"p2":     p2,
		"status": "ready",
		"ts":     Time.get_unix_time_from_system()
	})
	FirebaseManager.fb_patch("/matchmaking/matches/%s.json" % game_id, payload)
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % opponent_id)

	print("[Lobby] Match créé — game: %s | p1: %s | p2: %s" % [game_id, p1, p2])
	_launch(game_id, false, opponent_id)

# ══════════════════════════════════════════════════════════════════════════════
#  LANCEMENT
# ══════════════════════════════════════════════════════════════════════════════
func _launch(game_id: String, is_p1: bool, opponent_pid: String):
	_match_started = true
	_in_queue      = false

	FirebaseManager.init(game_id, is_p1)
	FirebaseManager.set_player_ids(_player_id, opponent_pid)   # ← transmet les IDs

	btn_battle.visible = false
	btn_cancel.visible = false
	lbl_status.text    = "Adversaire trouvé !\nLancement..."
	print("[Lobby] Lancement — game: %s | is_player1: %s | opp: %s" % [game_id, is_p1, opponent_pid])
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
func _generate_id() -> String:
	const CHARS = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = ""
	for _i in range(12): id += CHARS[randi() % CHARS.length()]
	return id

func _generate_game_id() -> String:
	const CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var id = ""
	for _i in range(8): id += CHARS[randi() % CHARS.length()]
	return id
