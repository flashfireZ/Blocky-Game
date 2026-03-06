extends Node2D

@export var cell_scene : PackedScene = preload("res://scenes/minigames/BlockGame/Cell.tscn")

var grid_size = 8
var cell_dim  = 120
var grid_positions = []
var grid_data      = []
var score          = 0

@onready var score_label    = get_tree().root.find_child("ScoreLabel",        true, false)
@onready var particles_base = get_tree().root.find_child("ExplosionParticles", true, false)
@onready var combo_label    = get_tree().root.find_child("ComboLabel",         true, false)

# ─── Combo ────────────────────────────────────────────────────────────────────
var combo_streak: int = 0
var _combo_tween: Tween = null
var _combo_timer: SceneTreeTimer = null

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

# ─── Setup visuel du Score ────────────────────────────────────────────────────
func _setup_score_label():
	if not score_label:
		return
	# Taille et position — haut droite, imposant
	score_label.add_theme_font_size_override("font_size", 72)
	score_label.add_theme_color_override("font_color",        Color.WHITE)
	score_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	score_label.add_theme_constant_override("shadow_offset_x", 4)
	score_label.add_theme_constant_override("shadow_offset_y", 4)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Position haut-droit (ajuste si ton anchor est déjà bon dans l'éditeur)
	score_label.global_position = Vector2(700 - 320, 150)
	score_label.size            = Vector2(300, 90)
	score_label.text            = "Score: 0"

# ─── Setup visuel du Combo ───────────────────────────────────────────────────
func _setup_combo_label():
	if not combo_label:
		return
	combo_label.add_theme_font_size_override("font_size", 110)
	combo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	combo_label.add_theme_constant_override("shadow_offset_x", 6)
	combo_label.add_theme_constant_override("shadow_offset_y", 6)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Centré horizontalement, milieu écran (zone visible au-dessus de la grille)
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

	# Pop punch
	if _combo_tween and _combo_tween.is_running():
		pass  # ne pas interrompre l'anim combo
	var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(score_label, "scale", Vector2(1.18, 1.18), 0.07)
	t.tween_property(score_label, "scale", Vector2(1.0,  1.0),  0.12)

# ══════════════════════════════════════════════════════════════════════════════
#  COMBO DISPLAY  — le cœur du juice
# ══════════════════════════════════════════════════════════════════════════════
# Palette pop selon l'intensité
const COMBO_COLORS = [
	Color("8AC926"),   # x2  vert
	Color("FFCA3A"),   # x3  jaune
	Color("FF924C"),   # x4  orange
	Color("FF595E"),   # x5  rouge-rose
	Color("C77DFF"),   # x6  violet
	Color("00F5FF"),   # x7+ cyan néon
]

func show_combo_label(total_multi: int):
	if not combo_label:
		print("COMBO x", total_multi, " !")
		return

	# Choisir la couleur selon l'intensité
	var color_idx  = clamp(total_multi - 2, 0, COMBO_COLORS.size() - 1)
	var clr        = COMBO_COLORS[color_idx]

	# Texte avec émoji selon l'intensité
	var emoji = ""
	if   total_multi >= 7: emoji = " 🔥🔥🔥"
	elif total_multi >= 5: emoji = " 🔥🔥"
	elif total_multi >= 3: emoji = " 🔥"
	combo_label.text = "COMBO x" + str(total_multi) + emoji

	combo_label.add_theme_color_override("font_color", clr)
	combo_label.modulate = Color(clr.r, clr.g, clr.b, 1.0)
	combo_label.scale    = Vector2(0.3, 0.3)
	combo_label.visible  = true

	# Tuer l'animation précédente proprement
	if _combo_tween:
		_combo_tween.kill()

	_combo_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

	# 1) POP : agrandit au-delà de 1 puis revient
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.15, 1.15), 0.35)

	# 2) Léger rebond vers 1.0
	_combo_tween.set_ease(Tween.EASE_IN_OUT)
	_combo_tween.set_trans(Tween.TRANS_BOUNCE)
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.2)

	# 3) Wobble gauche-droite (rotation)
	_combo_tween.set_trans(Tween.TRANS_SINE)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees", -6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  3.0, 0.05)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  0.0, 0.05)

	# Timer de disparition (reset si un nouveau combo arrive avant)
	if _combo_timer:
		_combo_timer = null
	_combo_timer = get_tree().create_timer(1.6)
	_combo_timer.timeout.connect(_fade_out_combo)

func _fade_out_combo():
	if not combo_label or not combo_label.visible:
		return
	var t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(combo_label, "modulate:a", 0.0, 0.35)
	t.tween_callback(func():
		combo_label.visible         = false
		combo_label.modulate.a      = 1.0
		combo_label.rotation_degrees = 0.0
	)

# ══════════════════════════════════════════════════════════════════════════════
#  GRILLE
# ══════════════════════════════════════════════════════════════════════════════
func center_and_generate_grid():
	var total_grid_width = cell_dim * grid_size
	var start_x = (1080 - total_grid_width) / 2
	var start_y = 500

	for y in range(grid_size):
		grid_positions.append([])
		grid_data.append([])
		for x in range(grid_size):
			var cell  = cell_scene.instantiate()
			cell.position = Vector2(start_x + (x * cell_dim), start_y + (y * cell_dim))
			cell.name = "Cell_" + str(x) + "_" + str(y)
			add_child(cell)

			grid_positions[y].append(cell.global_position)
			grid_data[y].append(0)

			var rect = cell.get_node_or_null("cell")
			if rect:
				rect.color = Color(0.1, 0.1, 0.1, 0.5)

# ─── Snap / coordonnées ───────────────────────────────────────────────────────
func get_cell_coordinates(target_pos: Vector2):
	var best_coords = null
	var best_dist   = 85.0

	for y in range(grid_size):
		for x in range(grid_size):
			var d = target_pos.distance_to(grid_positions[y][x])
			if d < best_dist:
				best_dist   = d
				best_coords = Vector2(x, y)

	return best_coords

func get_snapped_position(target_pos: Vector2) -> Vector2:
	var coords = get_cell_coordinates(target_pos)
	if coords != null:
		return grid_positions[coords.y][coords.x]
	return Vector2.ZERO

# ─── Preview ──────────────────────────────────────────────────────────────────
func _clear_preview_nodes():
	# Supprime tous les nœuds preview existants et vide le tableau
	for node in preview_nodes:
		node.queue_free()
	preview_nodes.clear()

func show_preview(block_top_left_positions: Array, piece_color: Color, source_color_rect: ColorRect):
	if piece_color != _preview_last_color:
		_clear_preview_nodes()
		_preview_last_color = piece_color

	# Création des blocs fantômes
	while preview_nodes.size() < block_top_left_positions.size():
		var dup: ColorRect = source_color_rect.duplicate()
		# On s'assure que le material est unique pour ne pas impacter la pièce originale
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
		if coords == null or grid_data[int(coords.y)][int(coords.x)] != 0:
			valid = false
			break
		snapped_coords.append(coords)

	# Affichage avec transparence forcée (0.2 = 20% d'opacité)
	for i in range(block_top_left_positions.size()):
		var node = preview_nodes[i]
		node.visible = true
		if valid and i < snapped_coords.size():
			node.global_position = grid_positions[int(snapped_coords[i].y)][int(snapped_coords[i].x)]
			node.modulate = Color(1, 1, 1, 0.40) # Blanc transparent
		else:
			node.global_position = block_top_left_positions[i]
			node.modulate = Color(1.5, 0.2, 0.2, 0.45) # Rouge transparent


func hide_preview():
	# On purge à chaque relâchement : la prochaine pièce aura une couleur différente
	_clear_preview_nodes()
	_preview_last_color = Color(-1, -1, -1)  # reset sentinelle

# ══════════════════════════════════════════════════════════════════════════════
#  LIGNES & COMBO
# ══════════════════════════════════════════════════════════════════════════════
func check_lines():
	var lines_to_clear = []

	for y in range(grid_size):
		var full = true
		for x in range(grid_size):
			if grid_data[y][x] == 0: full = false; break
		if full: lines_to_clear.append({"type": "row", "index": y})

	for x in range(grid_size):
		var full = true
		for y in range(grid_size):
			if grid_data[y][x] == 0: full = false; break
		if full: lines_to_clear.append({"type": "col", "index": x})

	var nb_lines = lines_to_clear.size()

	if nb_lines > 0:
		var multi_simultane = nb_lines          # x2 si 2 lignes en même temps, etc.
		var multi_serie     = combo_streak       # 0 au premier coup, +1 à chaque coup suivant
		var total_multi     = multi_simultane + multi_serie

		combo_streak += 1

		var points = nb_lines * 100 * total_multi
		update_score(points)

		# Afficher si combo réel (≥ 2)
		if total_multi >= 2:
			show_combo_label(total_multi)

		print("Lignes: %d | Série: %d | x%d | +%d pts" % [nb_lines, multi_serie, total_multi, points])
	else:
		if combo_streak > 0:
			print("Combo brisé (était x%d)" % combo_streak)
		combo_streak = 0

	for line in lines_to_clear:
		clear_line(line.type, line.index)

func clear_line(type, index):
	for i in range(grid_size):
		var x = i if type == "row" else index
		var y = index if type == "row" else i
		var cell = get_node("Cell_" + str(x) + "_" + str(y))
		
		grid_data[y][x] = 0
		spawn_particles(cell.global_position)

		for child in cell.get_children():
			# On ne détruit que les blocs posés, pas le fond "cell"
			if child.name != "Cell" and not child is Line2D:
				var t = create_tween().set_parallel(true)
				t.tween_property(child, "scale", Vector2.ZERO, 0.15)
				t.tween_property(child, "modulate:a", 0.0, 0.15)
				t.chain().step_finished.connect(child.queue_free)


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
	var blocks        = []
	for child in piece_node.get_children():
		if child is Node2D: blocks.append(child)
	if blocks.is_empty(): return false

	var first_pos = blocks[0].position
	for block in blocks:
		block_offsets.append(block.position - first_pos)

	for y in range(grid_size):
		for x in range(grid_size):
			if _can_place_at_coords(x, y, block_offsets):
				return true
	return false

func _can_place_at_coords(start_x: int, start_y: int, offsets: Array) -> bool:
	for offset in offsets:
		var tx = start_x + int(round(offset.x / cell_dim))
		var ty = start_y + int(round(offset.y / cell_dim))
		if tx < 0 or tx >= grid_size or ty < 0 or ty >= grid_size: return false
		if grid_data[ty][tx] == 1: return false
	return true
