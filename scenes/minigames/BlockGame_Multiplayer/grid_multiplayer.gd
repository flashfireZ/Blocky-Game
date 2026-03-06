extends Node2D

@export var cell_scene : PackedScene = preload("res://scenes/minigames/BlockGame/Cell.tscn")

var grid_rows = 12   # nombre de lignes
var grid_cols = 8    # nombre de colonnes
var cell_dim  = 120
var grid_positions = []
var grid_data      = []
var score          = 0

# Stockage de l'origine de la grille pour les calculs optimisés
var grid_start_pos : Vector2 

@onready var score_label    = get_tree().root.find_child("ScoreLabel",        true, false)
@onready var particles_base = get_tree().root.find_child("ExplosionParticles", true, false)
@onready var combo_label    = get_tree().root.find_child("ComboLabel",         true, false)

# ─── Tweens & Combo ───────────────────────────────────────────────────────────
var combo_streak: int = 0
var _combo_tween: Tween = null
var _score_tween: Tween = null # Ajout pour éviter les conflits d'animation du score

# ─── Preview ──────────────────────────────────────────────────────────────────
var preview_nodes: Array = []
var _preview_last_color: Color = Color(-1, -1, -1)  # sentinelle

# ══════════════════════════════════════════════════════════════════════════════
#  READY
# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	center_and_generate_grid()
	_setup_score_label()
	_setup_combo_label()

func _setup_score_label():
	if not score_label: return
	score_label.add_theme_font_size_override("font_size", 72)
	score_label.add_theme_color_override("font_color",        Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	score_label.add_theme_constant_override("shadow_offset_x", 4)
	score_label.add_theme_constant_override("shadow_offset_y", 4)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.global_position = Vector2(700 - 320, 100)
	score_label.size            = Vector2(300, 90)
	score_label.text            = "Score: 0"

func _setup_combo_label():
	if not combo_label: return
	combo_label.add_theme_font_size_override("font_size", 110)
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	combo_label.add_theme_constant_override("shadow_offset_x", 6)
	combo_label.add_theme_constant_override("shadow_offset_y", 6)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.size            = Vector2(900, 160)
	combo_label.global_position = Vector2((1080 - 900) / 2, 290)
	combo_label.pivot_offset    = combo_label.size / 2.0
	combo_label.visible         = false

# ══════════════════════════════════════════════════════════════════════════════
#  SCORE
# ══════════════════════════════════════════════════════════════════════════════
func update_score(amount: int):
	score += amount
	if not score_label:
		print("Score: ", score)
		return

	score_label.text = "Score: " + str(score)

	# Tuer proprement l'animation de score précédente
	if _score_tween and _score_tween.is_running():
		_score_tween.kill()
		
	_score_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_score_tween.tween_property(score_label, "scale", Vector2(1.18, 1.18), 0.07)
	_score_tween.tween_property(score_label, "scale", Vector2(1.0,  1.0),  0.12)

# ══════════════════════════════════════════════════════════════════════════════
#  COMBO DISPLAY
# ══════════════════════════════════════════════════════════════════════════════
const COMBO_COLORS = [
	Color("8AC926"),   # x2  vert
	Color("FFCA3A"),   # x3  jaune
	Color("FF924C"),   # x4  orange
	Color("FF595E"),   # x5  rouge-rose
	Color("C77DFF"),   # x6  violet
	Color("00F5FF"),   # x7+ cyan néon
]

func show_combo_label(total_multi: int):
	if not combo_label: return

	var color_idx  = clamp(total_multi - 2, 0, COMBO_COLORS.size() - 1)
	var clr        = COMBO_COLORS[color_idx]

	var emoji = ""
	if   total_multi >= 7: emoji = " 🔥🔥🔥"
	elif total_multi >= 5: emoji = " 🔥🔥"
	elif total_multi >= 3: emoji = " 🔥"
	combo_label.text = "COMBO x" + str(total_multi) + emoji

	combo_label.add_theme_color_override("font_color", clr)
	combo_label.modulate = Color(clr.r, clr.g, clr.b, 1.0)
	combo_label.scale    = Vector2(0.3, 0.3)
	combo_label.visible  = true

	if _combo_tween:
		_combo_tween.kill()

	_combo_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

	# 1) POP
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.15, 1.15), 0.35)

	# 2) Rebond
	_combo_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BOUNCE)
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.2)

	# 3) Wobble
	_combo_tween.set_trans(Tween.TRANS_SINE)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees", -6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  3.0, 0.05)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  0.0, 0.05)

	# 4) Pause puis Disparition (Fade out) directement dans le même tween (Évite le Timer buggé !)
	_combo_tween.tween_interval(1.6)
	_combo_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.35)
	_combo_tween.tween_callback(func():
		combo_label.visible          = false
		combo_label.modulate.a       = 1.0
		combo_label.rotation_degrees = 0.0
	)

# ══════════════════════════════════════════════════════════════════════════════
#  GRILLE
# ══════════════════════════════════════════════════════════════════════════════
func center_and_generate_grid():
	var total_grid_width = cell_dim * grid_cols
	grid_start_pos = Vector2((1080 - total_grid_width) / 2.0, 300)

	for y in range(grid_rows):
		grid_positions.append([])
		grid_data.append([])

		for x in range(grid_cols):
			var cell = cell_scene.instantiate()
			cell.position = grid_start_pos + Vector2(x * cell_dim, y * cell_dim)
			cell.name = "Cell_" + str(x) + "_" + str(y)
			add_child(cell)

			grid_positions[y].append(cell.global_position)
			grid_data[y].append(0)

			var rect = cell.get_node_or_null("Cell")
			if rect and rect.material:
				rect.material = rect.material.duplicate()
				if y < 6:
					rect.material.set_shader_parameter("fill_color",   Color(0.4, 0.051, 0.051, 0.871))
					rect.material.set_shader_parameter("border_color", Color(0.2, 0.02, 0.02, 1.0))
				else:
					rect.material.set_shader_parameter("fill_color",   Color(0.4, 0.051, 0.894, 0.867))
					rect.material.set_shader_parameter("border_color", Color(0.2, 0.02, 0.831, 1.0))

# ─── Snap / coordonnées ───────────────────────────────────────────────────────
func get_cell_coordinates(target_pos: Vector2):
	# OPTIMISATION : Calcul mathématique O(1) au lieu de boucler sur toute la grille O(N)
	var local_pos = target_pos - grid_start_pos
	
	# On évite les erreurs de signe en bloquant les valeurs hors-champ avant de diviser
	if local_pos.x < -cell_dim / 2.0 or local_pos.y < -cell_dim / 2.0:
		return null
		
	var grid_x = int(round(local_pos.x / cell_dim))
	var grid_y = int(round(local_pos.y / cell_dim))

	if grid_x >= 0 and grid_x < grid_cols and grid_y >= 0 and grid_y < grid_rows:
		return Vector2(grid_x, grid_y)
		
	return null

func get_snapped_position(target_pos: Vector2) -> Vector2:
	var coords = get_cell_coordinates(target_pos)
	if coords != null:
		return grid_positions[int(coords.y)][int(coords.x)]
	return Vector2.ZERO

# ─── Preview ──────────────────────────────────────────────────────────────────
func _clear_preview_nodes():
	for node in preview_nodes:
		node.queue_free()
	preview_nodes.clear()

func show_preview(block_top_left_positions: Array, piece_color: Color, source_color_rect: ColorRect):
	if piece_color != _preview_last_color:
		_clear_preview_nodes()
		_preview_last_color = piece_color

	while preview_nodes.size() < block_top_left_positions.size():
		var dup: ColorRect = source_color_rect.duplicate()
		if dup.material:
			dup.material = dup.material.duplicate()
		
		dup.z_index = 50
		add_child(dup)
		preview_nodes.append(dup)

	for node in preview_nodes: node.visible = false

	var snapped_coords = []
	var valid = true

	for top_left in block_top_left_positions:
		var center = top_left + Vector2(cell_dim, cell_dim) * 0.5
		var coords = get_cell_coordinates(center)
		if coords == null:
			valid = false
			break
		snapped_coords.append(coords)

	# On utilise notre super validateur !
	if valid:
		valid = is_placement_valid(snapped_coords)

	for i in range(block_top_left_positions.size()):
		var node = preview_nodes[i]
		node.visible = true
		if valid and i < snapped_coords.size():
			node.global_position = grid_positions[int(snapped_coords[i].y)][int(snapped_coords[i].x)]
			node.modulate = Color(1, 1, 1, 0.40) 
		else:
			node.global_position = block_top_left_positions[i]
			node.modulate = Color(1.5, 0.199, 0.199, 0.408) 

func hide_preview():
	_clear_preview_nodes()
	_preview_last_color = Color(-1, -1, -1) 

# ══════════════════════════════════════════════════════════════════════════════
#  LIGNES & COMBO
# ══════════════════════════════════════════════════════════════════════════════
func check_lines():
	var lines_to_clear = []

	for y in range(grid_rows):
		var full = true
		for x in range(grid_cols):
			if grid_data[y][x] == 0:
				full = false
				break
		if full:
			lines_to_clear.append({"type": "row", "index": y})

	for x in range(grid_cols):
		var full = true
		for y in range(grid_rows):
			if grid_data[y][x] == 0:
				full = false
				break
		if full:
			lines_to_clear.append({"type": "col", "index": x})

	var nb_lines = lines_to_clear.size()

	if nb_lines > 0:
		var multi_simultane = nb_lines
		var multi_serie     = combo_streak
		var total_multi     = multi_simultane + multi_serie

		combo_streak += 1

		var points = nb_lines * 100 * total_multi
		update_score(points)

		if total_multi >= 2:
			show_combo_label(total_multi)
	else:
		if combo_streak > 0:
			print("Combo brisé (était x%d)" % combo_streak)
		combo_streak = 0

	for line in lines_to_clear:
		clear_line(line.type, line.index)

func clear_line(type, index):
	var count = grid_cols if type == "row" else grid_rows

	for i in range(count):
		var x = i if type == "row" else index
		var y = index if type == "row" else i

		var cell = get_node("Cell_" + str(x) + "_" + str(y))

		grid_data[y][x] = 0
		spawn_particles(cell.global_position)

		for child in cell.get_children():
			if child.name != "Cell" and not child is Line2D:
				var t = create_tween().set_parallel(true)
				t.tween_property(child, "scale", Vector2.ZERO, 0.15)
				t.tween_property(child, "modulate:a", 0.0, 0.15)
				# CORRECTION DU BUG DE CRASH ICI :
				t.chain().tween_callback(child.queue_free)

# ══════════════════════════════════════════════════════════════════════════════
#  UTILITAIRES
# ══════════════════════════════════════════════════════════════════════════════
func spawn_particles(pos: Vector2):
	if particles_base:
		var p = particles_base.duplicate()
		add_child(p)
		p.global_position = pos
		p.emitting = true
		get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func can_fit_piece(piece_node: Node2D) -> bool:
	var block_offsets = []
	var blocks = []

	for child in piece_node.get_children():
		if child is Node2D:
			blocks.append(child)
	if blocks.is_empty():
		return false

	var first_pos = blocks[0].position
	for block in blocks:
		block_offsets.append(block.position - first_pos)

	for y in range(grid_rows):
		for x in range(grid_cols):
			if _can_place_at_coords(x, y, block_offsets):
				return true

	return false

func is_placement_valid(coords: Array) -> bool:
	if coords.is_empty(): return false
	
	var is_top = false
	var is_bottom = false
	
	# 1. Vérifier les limites et dans quelle(s) zone(s) on se trouve
	for c in coords:
		if c.x < 0 or c.x >= grid_cols or c.y < 0 or c.y >= grid_rows:
			return false # Hors de la grille
			
		if c.y < 6: is_top = true
		else:       is_bottom = true
			
	# Interdit de placer une pièce à cheval entre les deux zones
	if is_top and is_bottom:
		return false
		
	# 2. RÈGLE ZONE JOUEUR (Bas) : Toutes les cases doivent être VIDES (0)
	if is_bottom:
		for c in coords:
			if grid_data[int(c.y)][int(c.x)] != 0:
				return false
		return true
		
	# 3. RÈGLE ZONE D'ATTAQUE (Haut) : Doit recouvrir PARFAITEMENT une pièce ennemie (2)
	if is_top:
		for c in coords:
			if grid_data[int(c.y)][int(c.x)] != 2:
				return false # Ne touche pas un bloc ennemi
				
		# On récupère la forme entière de l'ennemi en ciblant le premier bloc de notre pièce
		var enemy_shape = _get_connected_opponent_cells(int(coords[0].x), int(coords[0].y))
		
		# Si notre pièce n'a pas exactement le même nombre de blocs que la forme ennemie,
		# ça veut dire qu'elle est trop petite (ex: I sur un L) ou trop grande.
		if coords.size() != enemy_shape.size():
			return false
			
		return true

	return false

# On met à jour l'ancienne fonction pour qu'elle utilise notre nouveau validateur
func _can_place_at_coords(start_x: int, start_y: int, offsets: Array) -> bool:
	var coords = []
	for offset in offsets:
		var tx = start_x + int(round(offset.x / cell_dim))
		var ty = start_y + int(round(offset.y / cell_dim))
		coords.append(Vector2(tx, ty))
		
	return is_placement_valid(coords)
	


# ══════════════════════════════════════════════════════════════════════════════
#  MÉCANIQUE D'ATTAQUE (ZONE Y < 6)
# ══════════════════════════════════════════════════════════════════════════════

func _get_connected_opponent_cells(start_x: int, start_y: int) -> Array:
	var visited = {} # Dictionnaire pour des performances ultra-rapides O(1)
	var queue = [Vector2(start_x, start_y)]
	var connected_shape = []
	
	while queue.size() > 0:
		var current = queue.pop_front()
		
		# Si on a déjà vérifié cette case, on passe
		if visited.has(current): continue
		visited[current] = true
		
		# On s'assure de ne pas sortir de la grille ni de la zone d'attaque (y < 6)
		if current.x < 0 or current.x >= grid_cols or current.y < 0 or current.y >= 6:
			continue
			
		# Si c'est un bloc adverse, on l'ajoute à la forme et on check ses voisins
		if grid_data[int(current.y)][int(current.x)] == 2:
			connected_shape.append(current)
			
			queue.append(Vector2(current.x + 1, current.y)) # Droite
			queue.append(Vector2(current.x - 1, current.y)) # Gauche
			queue.append(Vector2(current.x, current.y + 1)) # Bas
			queue.append(Vector2(current.x, current.y - 1)) # Haut
			
	return connected_shape
	
func deal_damage(amount: int):
	print("Dégâts infligés à l'adversaire : ", amount)
