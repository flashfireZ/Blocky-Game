# lobby.gd — Matchmaking & Interface Premium
extends Control

# ── Configuration ────────────────────────────────────────────────────────────
const GAME_SCENE         : String = "res://scenes/minigames/BlockGame_Multiplayer/MainBlockGameMultiplayer.tscn"
const PSEUDO_POPUP_SCENE : String = "res://scenes/ui/PseudoPopup.tscn"
const POLL_RATE          : float  = 1.5
const QUEUE_TIMEOUT      : float  = 45.0

# ── Références UI (Chemins basés sur le nouveau TSCN) ────────────────────────
@onready var lbl_pseudo      : Label = %PseudoLabel
@onready var lbl_id          : Label = %IDLabel
@onready var lbl_trophies    : Label = %TrophyLabel
@onready var logo            : Label = $MainContent/VBox/LogoContainer/GameTitle

@onready var btn_battle      : Button = $MainContent/VBox/Buttons/BattleBtn
@onready var btn_cancel      : Button = $MainContent/VBox/Buttons/CancelBtn
@onready var lbl_status      : Label  = $MainContent/VBox/Buttons/StatusLabel

# ── Variables de contrôle ────────────────────────────────────────────────────
var _player_id     : String = ""
var _in_queue      : bool   = false
var _poll_timer    : float  = 0.0
var _queue_timer   : float  = 0.0
var _match_started : bool   = false
var _tween_pulse   : Tween  = null
var _current_displayed_trophies : int = 0
var _debug_save_path : String = "user://player.cfg"

# ══════════════════════════════════════════════════════════════════════════════
#  INITIALISATION
# ══════════════════════════════════════════════════════════════════════════════

func _ready():
	randomize()
	
	# --- LOGIQUE DE PERSISTANCE DEBUG ---
	if OS.has_feature("debug"):
		# On crée un chemin de sauvegarde unique pour cette fenêtre (ex: player_1234.cfg)
		# Le PID ne change pas tant que tu ne fermes pas l'instance.
		var pid = OS.get_process_id()
		_debug_save_path = "user://player_debug_%d.cfg" % pid
		
		# On génère un ID unique basé sur le PID pour que l'ID reste le même
		# quand on revient du match au lobby.
		_player_id = "dbg_%d" % pid
	else:
		# En version réelle, on génère/charge l'ID normalement
		_player_id = _generate_id()
	# ------------------------------------

	_update_player_stats() 
	_animate_logo()        
	_set_ui_idle()         

	btn_battle.pressed.connect(_on_battle_btn_pressed)
	btn_cancel.pressed.connect(_on_cancel_btn_pressed)

func _update_player_stats():
	var config = ConfigFile.new()
	# On charge le fichier spécifique à cette instance
	var err = config.load(_debug_save_path)
	
	var pseudo = "JOUEUR"
	var trophies = 0
	
	if err == OK:
		pseudo = config.get_value("player", "pseudo", "JOUEUR")
		trophies = config.get_value("player", "trophies", 0)
	else:
		# Si le fichier n'existe pas (premier lancement de cette instance)
		# On initialise des trophées différents pour tester si on veut
		pseudo = "JOUEUR_" + str(OS.get_process_id()).right(3)
		trophies = 500 # Score de départ pour test
		
		config.set_value("player", "pseudo", pseudo)
		config.set_value("player", "trophies", trophies)
		config.set_value("player", "id", _player_id)
		config.save(_debug_save_path)
	
	lbl_pseudo.text = pseudo.to_upper()
	lbl_id.text = "ID: #" + _player_id.to_upper()
	
	# On anime les trophées (le compteur ne repartira plus de 0 car 
	# _current_displayed_trophies sera mis à jour correctement)
	_animate_trophy_counter(trophies)

func _animate_trophy_counter(target_value: int):
	# On s'assure que l'animation de scale part bien du centre du label
	lbl_trophies.pivot_offset = lbl_trophies.size / 2
	
	# 1. Animation des chiffres (le compteur qui défile)
	# CORRECTION : set_trans utilise TRANS_QUINT et set_ease utilise EASE_OUT
	var tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	
	tween.tween_method(func(val: int): 
		lbl_trophies.text = "🏆 " + str(val)
	, _current_displayed_trophies, target_value, 2.0) 
	
	# 2. Animation de "Pulse" (le texte grossit et rétrécit)
	# CORRECTION : set_trans utilise TRANS_ELASTIC et set_ease utilise EASE_OUT
	var pulse = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	pulse.tween_property(lbl_trophies, "scale", Vector2(1.2, 1.2), 0.2)
	pulse.tween_property(lbl_trophies, "scale", Vector2(1.0, 1.0), 0.4)
	
	# Mise à jour de la variable de suivi
	_current_displayed_trophies = target_value
# ══════════════════════════════════════════════════════════════════════════════
#  ANIMATIONS VISUELLES
# ══════════════════════════════════════════════════════════════════════════════

func _animate_logo():
	if not logo: return
	
	# On attend une frame pour être sûr que le Container a bien positionné le logo au centre
	await get_tree().process_frame
	
	# On mémorise la position centrale de départ exacte
	var center_y = logo.position.y
	
	# On crée un tween qui boucle à l'infini
	var t = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# PHASE 1 : Monte à (Centre - 20)
	t.tween_property(logo, "position:y", center_y - 20, 2.0)
	t.parallel().tween_property(logo, "rotation_degrees", 2.0, 2.0)
	
	# PHASE 2 : Descend à (Centre + 20)
	t.tween_property(logo, "position:y", center_y + 20, 2.0)
	t.parallel().tween_property(logo, "rotation_degrees", -2.0, 2.0)

func _start_pulse():
	_stop_pulse()
	_tween_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_tween_pulse.tween_property(lbl_status, "modulate:a", 0.3, 0.7)
	_tween_pulse.tween_property(lbl_status, "modulate:a", 1.0, 0.7)

func _stop_pulse():
	if _tween_pulse and _tween_pulse.is_valid():
		_tween_pulse.kill()
	lbl_status.modulate.a = 1.0

# ══════════════════════════════════════════════════════════════════════════════
#  LOGIQUE DE RECHERCHE (MATCHMAKING)
# ══════════════════════════════════════════════════════════════════════════════

func _on_battle_btn_pressed():
	# Si pas de pseudo, on force l'ouverture du popup
	var pseudo = _get_saved_pseudo()
	if pseudo == "" or pseudo == "JOUEUR":
		_open_pseudo_popup()
	else:
		_join_queue()

func _open_pseudo_popup():
	var popup = load(PSEUDO_POPUP_SCENE).instantiate()
	popup.setup(_player_id)
	popup.pseudo_confirmed.connect(func(_p):
		_update_player_stats() # Rafraîchit l'UI avec le nouveau pseudo
		_join_queue()
	)
	add_child(popup)

func _join_queue():
	if _in_queue: return
	_in_queue = true
	_match_started = false
	_queue_timer = 0.0
	_poll_timer = 0.0
	_set_ui_searching()

	# ---> AJOUT : On supprime les vieux résidus éventuels avant de chercher
	FirebaseManager.fb_delete("/player_matches/%s.json" % _player_id)

	var payload = JSON.stringify({"ts": Time.get_unix_time_from_system()})
	FirebaseManager.fb_patch("/matchmaking/queue/%s.json" % _player_id, payload)

func _leave_queue():
	if not _in_queue: return
	_in_queue = false
	_set_ui_idle()
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)

func _process(delta):
	if not _in_queue or _match_started: return

	_queue_timer += delta
	if _queue_timer >= QUEUE_TIMEOUT:
		_leave_queue()
		lbl_status.text = "PERSONNE DE DISPONIBLE..."
		return

	# Animation des petits points
	var dots = ".".repeat(int(_queue_timer * 2.0) % 4)
	lbl_status.text = "RECHERCHE" + dots

	_poll_timer += delta
	if _poll_timer >= POLL_RATE:
		_poll_timer = 0.0
		_poll()

func _poll():
	# 1. Vérifier si quelqu'un a créé un match pour nous
	FirebaseManager.fb_get("/player_matches/%s.json" % _player_id, func(data):
		if _match_started or not _in_queue: return
		if typeof(data) == TYPE_DICTIONARY and data.has("gid"):
			# ---> AJOUT : Supprimer la notification Firebase après l'avoir lue
			FirebaseManager.fb_delete("/player_matches/%s.json" % _player_id)
			
			_launch(data["gid"], true, data["opp"])
			return

		# 2. Sinon, scanner la queue pour voir si on peut créer un match
		FirebaseManager.fb_get("/matchmaking/queue.json", func(queue):
			if _match_started or not _in_queue or typeof(queue) != TYPE_DICTIONARY: return

			var opponent_id = ""
			var oldest_ts = INF

			for pid in queue.keys():
				if pid == _player_id: continue
				var entry = queue[pid]
				if entry.get("claimed_by", "") != "": continue # Déjà pris
				
				var ts = float(entry.get("ts", 0))
				if ts < oldest_ts:
					oldest_ts = ts
					opponent_id = pid

			if opponent_id != "":
				# On tente de claim l'adversaire (rôle du 2ème joueur arrivé)
				_claim_and_create(opponent_id)
		)
	)

func _claim_and_create(opponent_id: String):
	FirebaseManager.fb_patch("/matchmaking/queue/%s.json" % opponent_id, 
		JSON.stringify({"claimed_by": _player_id}))
	
	await get_tree().create_timer(0.4).timeout
	
	FirebaseManager.fb_get("/matchmaking/queue/%s.json" % opponent_id, func(entry):
		if typeof(entry) == TYPE_DICTIONARY and entry.get("claimed_by", "") == _player_id:
			_create_match(opponent_id)
	)

func _create_match(opponent_id: String):
	_match_started = true
	var game_id = _generate_game_id()
	
	# Notifier l'adversaire
	var notif = JSON.stringify({"gid": game_id, "opp": _player_id})
	FirebaseManager.fb_patch("/player_matches/%s.json" % opponent_id, notif)
	
	# Nettoyer la queue
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % opponent_id)
	FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)
	
	_launch(game_id, false, opponent_id)

func _launch(game_id: String, is_p1: bool, opponent_pid: String):
	_match_started = true
	_in_queue = false
	
	FirebaseManager.init(game_id, is_p1)
	FirebaseManager.set_player_ids(_player_id, opponent_pid)
	
	btn_battle.visible = false
	btn_cancel.visible = false
	lbl_status.text = "ADVERSAIRE TROUVÉ !"
	lbl_status.modulate = Color.GREEN
	
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file(GAME_SCENE)

# ══════════════════════════════════════════════════════════════════════════════
#  UI & HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _set_ui_idle():
	_stop_pulse()
	btn_battle.show()
	btn_cancel.hide()
	lbl_status.text = "PRET AU COMBAT"
	lbl_status.modulate = Color(0.74, 0.84, 0.95)

func _set_ui_searching():
	btn_battle.hide()
	btn_cancel.show()
	_start_pulse()

func _on_leaderboard_btn_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/LeaderboardScreen.tscn")

func _on_cancel_btn_pressed():
	_leave_queue()

func _generate_id() -> String:
	var config = ConfigFile.new()
	if config.load("user://player.cfg") == OK:
		var saved = config.get_value("player", "id", "")
		if saved != "": return saved
	
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = ""
	for _i in range(12): id += chars[randi() % chars.length()]
	config.set_value("player", "id", id)
	config.save("user://player.cfg")
	return id

func _get_saved_pseudo() -> String:
	var config = ConfigFile.new()
	if config.load("user://player.cfg") == OK:
		return config.get_value("player", "pseudo", "")
	return ""

func _generate_game_id() -> String:
	var chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var id = ""
	for _i in range(8): id += chars[randi() % chars.length()]
	return id

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _in_queue:
			FirebaseManager.fb_delete("/matchmaking/queue/%s.json" % _player_id)
		
		# ---> AJOUT : On nettoie d'éventuels matchs non consommés à la fermeture
		FirebaseManager.fb_delete("/player_matches/%s.json" % _player_id)
