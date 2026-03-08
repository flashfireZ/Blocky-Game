extends Node2D

@onready var lbl_opponent = $HUD/TopBar/HBox/OpponentStats/OpponentLabel
@onready var grid = $GridMultiplayer

# --- Références aux barres et labels ---
@onready var hp_bar_player = $HUD/BottomBar/PlayerStats/HPBarPlayer
@onready var hp_label_player = hp_bar_player.get_node("HealthLabelPlayer")
@onready var shield_bar_player = $HUD/BottomBar/PlayerStats/ShieldBarPlayer
@onready var shield_label_player = shield_bar_player.get_node("ShieldLabelPlayer")

@onready var hp_bar_opp = $HUD/TopBar/HBox/OpponentStats/HPBarOpponent
@onready var hp_label_opp = hp_bar_opp.get_node("HealthLabelOpponent")
@onready var shield_bar_opp = $HUD/TopBar/HBox/OpponentStats/ShieldBarOpponent
@onready var shield_label_opp = shield_bar_opp.get_node("ShieldLabelOpponent")

# --- Mémoire des valeurs pour les animations ---
var _last_hp_player    : int  = 3000
var _last_shield_player: int  = 0
var _last_hp_opp       : int  = 3000
var _last_shield_opp   : int  = 0

var _game_ended : bool = false   # ← Verrou : empêche tout double-traitement de fin

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	FirebaseManager.setup_scene_refs()
	FirebaseManager.game_finished.connect(_on_game_finished)

	if lbl_opponent and FirebaseManager.opp_pid != "":
		lbl_opponent.text = "ID: " + FirebaseManager.opp_pid

	_setup_bars()

	if grid:
		grid.stats_updated.connect(_update_ui_animated)
		_update_ui_instant()

		# ── Connexion du signal game_over de la grille vers Firebase ──────────
		# "player"   → HP joueur local tombés à 0  → adversaire gagne
		# "opponent" → HP adversaire tombés à 0    → joueur local gagne
		# On passe par declare_winner_and_finish pour que les DEUX clients
		# reçoivent le résultat (via l'écriture Firebase).
		grid.game_over.connect(func(winner: String):
			if _game_ended: return
			var winner_pid = FirebaseManager.my_pid if winner == "player" else FirebaseManager.opp_pid
			FirebaseManager.declare_winner_and_finish(winner_pid)
		)

	# ── Bouton Quitter (nœud optionnel dans la scène) ─────────────────────────
	var btn_quit = get_node_or_null("HUD/TopBar/HBox/QuitBtn")
	if btn_quit and not btn_quit.pressed.is_connected(_on_quit_pressed):
		btn_quit.pressed.connect(_on_quit_pressed)

# Appelé si le joueur appuie sur Quitter pendant le match
func _on_quit_pressed():
	if _game_ended: return
	print("[Game] Joueur a appuyé sur Quitter — défaite par abandon")
	FirebaseManager.notify_player_quit()
	get_tree().change_scene_to_file("res://scenes/minigames/BlockGame_Multiplayer/Lobby.tscn")

# Fermeture de la fenêtre pendant une partie = forfait
func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _game_ended:
		FirebaseManager.notify_player_quit()

# ══════════════════════════════════════════════════════════════════════════════
#  FIN DE PARTIE — Point d'arrivée unique (connecté à FirebaseManager.game_finished)
# ══════════════════════════════════════════════════════════════════════════════
func _on_game_finished(winner_id: String):
	if _game_ended: return
	_game_ended = true

	print("[Game] Partie terminée — vainqueur : ", winner_id)

	# 1. Arrêter les systèmes
	if grid:
		grid.set_process(false)
		grid.set_physics_process(false)
	
	var piece_mgr = get_node_or_null("PieceManagerMultiplayer")
	if piece_mgr:
		piece_mgr.set_process(false)
		piece_mgr.set_physics_process(false)

	var gsm = get_node_or_null("GameStateManager")
	if gsm and gsm.has_method("stop_timer"):
		gsm.stop_timer()

	# 2. Calcul du gain/perte
	var is_winner = (winner_id == FirebaseManager.my_pid)
	var delta = 2 if is_winner else -1
	
	# Mise à jour Firebase (on récupère le pseudo depuis le config file local)
	var config = ConfigFile.new()
	var pseudo = "Joueur"
	if config.load("user://player.cfg") == OK:
		pseudo = config.get_value("player", "pseudo", "Joueur")
	
	FirebaseManager.leaderboard_update(pseudo, delta)

	# 3. Affichage et mise à jour de l'UI
	var ui = get_tree().root.find_child("GameOverUI", true, false)
	if ui:
		# Correction des chemins (NodePath) car les labels sont dans des containers
		var container = "CenterContainer/MainPanel/MarginContainer/VBoxContainer/"
		var status_lbl = ui.get_node_or_null(container + "StatusLabel")
		var score_lbl  = ui.get_node_or_null(container + "ScoreContainer/ScoreMargin/ScoreVBox/FinalScoreLabel")
		var score_header = ui.get_node_or_null(container + "ScoreContainer/ScoreMargin/ScoreVBox/ScoreHeaderLabel")

		# Mise à jour du texte de Victoire / Défaite
		if status_lbl:
			status_lbl.text = "VICTOIRE 🏆" if is_winner else "DÉFAITE 💀"
			# Optionnel : changer la couleur du texte
			status_lbl.add_theme_color_override("font_color", Color.YELLOW if is_winner else Color.INDIAN_RED)

		# Mise à jour du nombre de trophées (FinalScoreLabel)
		if score_lbl:
			var prefix = "+" if delta > 0 else ""
			score_lbl.text = prefix + str(delta)
			score_lbl.add_theme_color_override("font_color", Color.GREEN if is_winner else Color.RED)
		
		if score_header:
			score_header.text = "TROPHÉES"

		ui.visible = true
# ══════════════════════════════════════════════════════════════════════════════
#  SETUP BARRES
# ══════════════════════════════════════════════════════════════════════════════
func _setup_bars():
	var max_hp     = 3000
	var max_shield = 1000

	hp_bar_player.max_value    = max_hp
	hp_bar_opp.max_value       = max_hp
	shield_bar_player.max_value = max_shield
	shield_bar_opp.max_value   = max_shield

	hp_label_player.pivot_offset     = hp_label_player.size     / 2.0
	shield_label_player.pivot_offset  = shield_label_player.size / 2.0
	hp_label_opp.pivot_offset        = hp_label_opp.size        / 2.0
	shield_label_opp.pivot_offset    = shield_label_opp.size    / 2.0

func _update_ui_instant():
	if not grid: return

	hp_bar_player.value      = grid.player_hp
	hp_label_player.text     = str(grid.player_hp)
	_last_hp_player          = grid.player_hp

	shield_bar_player.value  = grid.player_shield
	shield_label_player.text = str(grid.player_shield)
	_last_shield_player      = grid.player_shield

	hp_bar_opp.value         = grid.opponent_hp
	hp_label_opp.text        = str(grid.opponent_hp)
	_last_hp_opp             = grid.opponent_hp

	shield_bar_opp.value     = grid.opponent_shield
	shield_label_opp.text    = str(grid.opponent_shield)
	_last_shield_opp         = grid.opponent_shield

func _update_ui_animated():
	if not grid: return

	_animate_bar(hp_bar_player, hp_label_player, _last_hp_player, grid.player_hp)
	if grid.player_hp < _last_hp_player: _shake_node(hp_bar_player)
	_last_hp_player = grid.player_hp

	_animate_bar(shield_bar_player, shield_label_player, _last_shield_player, grid.player_shield)
	_last_shield_player = grid.player_shield

	_animate_bar(hp_bar_opp, hp_label_opp, _last_hp_opp, grid.opponent_hp)
	if grid.opponent_hp < _last_hp_opp: _shake_node(hp_bar_opp)
	_last_hp_opp = grid.opponent_hp

	_animate_bar(shield_bar_opp, shield_label_opp, _last_shield_opp, grid.opponent_shield)
	_last_shield_opp = grid.opponent_shield

# ══════════════════════════════════════════════════════════════════════════════
#  EFFETS VISUELS (TWEENS)
# ══════════════════════════════════════════════════════════════════════════════
func _animate_bar(bar: Range, label: Label, old_val: int, new_val: int):
	if old_val == new_val: return
	label.text = str(new_val)
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bar, "value", float(new_val), 0.4)
	var text_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	label.scale = Vector2(1.3, 1.3)
	text_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.3)

func _shake_node(node: Control):
	var original_pos = node.position
	var t = create_tween()
	t.tween_property(node, "position", original_pos + Vector2(12, 0),  0.04)
	t.tween_property(node, "position", original_pos + Vector2(-12, 0), 0.04)
	t.tween_property(node, "position", original_pos + Vector2(6, 0),   0.04)
	t.tween_property(node, "position", original_pos,                   0.04)
