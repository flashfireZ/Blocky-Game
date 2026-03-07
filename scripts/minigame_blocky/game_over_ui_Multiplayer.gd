extends CanvasLayer

var current_score: int = 0

@onready var final_score_label  = find_child("FinalScoreLabel",  true, false)
@onready var status_label       = find_child("StatusLabel",       true, false)
@onready var title_label        = find_child("TitleLabel",        true, false)
@onready var restart_button     = find_child("RestartButton",     true, false)
@onready var quit_button        = find_child("QuitButton",        true, false)

func _ready():
	visible = false

# ─── Appelée par piece_manager_multiplayer (accepte int ou String) ───────────
func setup(score) -> void:
	setup_game_over(int(str(score)))

# ─── Version complète avec statut victoire / défaite ─────────────────────────
func setup_game_over(score: int, is_winner: bool = true):
	current_score = score

	if final_score_label:
		final_score_label.text = "Score Final : " + str(score)

	if status_label:
		if is_winner:
			status_label.text = "VICTOIRE 🏆"
			status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		else:
			status_label.text = "DÉFAITE 💀"
			status_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))

	visible = true
	_play_intro_animation()

# ─── Animation d'apparition ──────────────────────────────────────────────────
func _play_intro_animation():
	var panel = find_child("MainPanel", true, false)
	if not panel:
		return

	panel.modulate.a = 0.0
	panel.scale      = Vector2(0.75, 0.75)

	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "scale",        Vector2(1.0, 1.0), 0.45)
	tween.parallel().tween_property(panel, "modulate:a", 1.0,          0.35)

	# Légère pulsation sur le StatusLabel
	if status_label:
		var st = create_tween().set_loops(0)
		st.tween_property(status_label, "scale", Vector2(1.05, 1.05), 0.7) \
		  .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		st.tween_property(status_label, "scale", Vector2(1.0,  1.0),  0.7) \
		  .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

# ─── Boutons ─────────────────────────────────────────────────────────────────
func _on_restart_button_pressed():
	save_rewards()
	get_tree().reload_current_scene()

func _on_quit_button_pressed():
	save_rewards()
	get_tree().change_scene_to_file("res://scenes/minigames/BlockGame_Multiplayer/Lobby.tscn")

# ─── Sauvegarde des gains ─────────────────────────────────────────────────────
func save_rewards():
	if current_score > 0:
		GameData.add_stars(current_score)
		print("Gains sauvegardés : ", current_score, " étoiles.")
		current_score = 0
