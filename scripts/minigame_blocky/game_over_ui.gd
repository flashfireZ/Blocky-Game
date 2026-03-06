extends CanvasLayer

var current_score: int = 0

@onready var final_score_label = find_child("FinalScoreLabel", true, false)

func _ready():
	visible = false

# Cette fonction est appelée par le piece_manager
func setup_game_over(score: int):
	current_score = score
	
	# Mise à jour visuelle
	if final_score_label:
		final_score_label.text = "Score Final: " + str(score)
		
	visible = true
	
	# Optionnel : Animation d'apparition
	

func _on_restart_button_pressed():
	# Si on redémarre, on ne sauvegarde pas forcément les points maintenant
	# (Ou alors tu peux décider de les sauvegarder quand même)
	save_rewards() 
	get_tree().reload_current_scene()

func _on_quit_button_pressed():
	# 1. Sauvegarder les gains
	save_rewards()
	
	# 2. Retourner au village
	# Assure-toi que le chemin est correct vers ta scène Village
	get_tree().change_scene_to_file("res://scenes/village/VillageWorld.tscn")

func save_rewards():
	# On ajoute le score actuel au stock global d'étoiles
	if current_score > 0:
		GameData.add_stars(current_score)
		print("Gains sauvegardés : ", current_score, " étoiles.")
		current_score = 0 # On remet à 0 pour ne pas les ajouter deux fois
