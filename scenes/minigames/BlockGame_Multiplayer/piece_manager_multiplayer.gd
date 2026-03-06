# script pece_manager.gd (toutjour garader le titre du script)
extends Node2D

@export var piece_templates : Array[PackedScene] = []
var spawn_positions = [Vector2(100, 0), Vector2(440, 0), Vector2(780, 0)]
var is_spawning = false # Nouveau : pour éviter de vérifier pendant le spawn

func _ready():
	randomize()
	spawn_new_set()

func spawn_new_set():
	is_spawning = true # On bloque la détection
	if piece_templates.is_empty(): return

	for i in range(3):
		var random_index = randi() % piece_templates.size()
		var new_piece = piece_templates[random_index].instantiate()
		new_piece.position = spawn_positions[i]
		add_child(new_piece)
		if new_piece.has_method("update_start_pos"):
			new_piece.update_start_pos()
	
	# On attend un peu que tout soit prêt avant de réautoriser la détection
	await get_tree().process_frame
	is_spawning = false
	check_game_over() # On vérifie si les nouvelles pièces sont jouables

func _process(_delta):
	var active_pieces = 0
	for child in get_children():
		if not child.is_queued_for_deletion():
			active_pieces += 1
	
	# On ne spawn que si on n'est pas déjà en train de le faire
	if active_pieces == 0 and not is_spawning:
		spawn_new_set()

func check_game_over():
	# Si on est en train de spawn, on ne fait rien
	if is_spawning: return
	
	var grid = get_tree().root.find_child("GridMultiplayer", true, false)
	if not grid: return

	var pieces_remaining = []
	for child in get_children():
		if not child.is_queued_for_deletion():
			pieces_remaining.append(child)

	# TRÈS IMPORTANT : Si plus de pièces, on ne perd pas, on attend le spawn
	if pieces_remaining.is_empty(): return

	var at_least_one_possible = false
	for piece in pieces_remaining:
		if grid.can_fit_piece(piece):
			at_least_one_possible = true
			piece.modulate.a = 1.0 
		else:
			piece.modulate.a = 0.3 

	if not at_least_one_possible:
		await get_tree().create_timer(0.5).timeout
		trigger_game_over(grid.score)

func trigger_game_over(final_score):
	# On cherche le menu
	var ui = get_tree().root.find_child("GameOverUI", true, false)
	
	if ui:
		# ON APPELLE UNE FONCTION DÉDIÉE DANS L'UI (voir étape 3)
		if ui.has_method("setup_game_over"):
			ui.setup_game_over(final_score)
		else:
			# Fallback si tu n'as pas encore mis à jour l'UI
			ui.visible = true
			var score_label = ui.find_child("FinalScoreLabel", true, false)
			if score_label: score_label.text = "Score: " + str(final_score)
	else:
		print("ERREUR : GameOverUI non trouvé !")
