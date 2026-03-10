extends Node2D

# --- Configuration ---
@export var idle_scale:    float = 0.6
@export var drag_offset_y: float = -150.0   # décalage visuel : la pièce flotte AU-DESSUS du curseur
@export var tween_speed:   float = 0.15
@export var cell_size:     int   = 110  # !! CORRECTION : mis à jour de 120 → 110

var dragging:     bool    = false
var offset:       Vector2 = Vector2.ZERO
var start_pos:    Vector2 = Vector2.ZERO
var active_tween: Tween
var piece_color:  Color   = Color.WHITE

var COLORS: Array[Color] = [
	Color("FF595E"), Color("FFCA3A"), Color("8AC926"),
	Color("1982C4"), Color("6A4C93")
]

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	print("[PIECE] _ready() — nœud=", name, " parent=", get_parent().name)
	randomize()
	piece_color = COLORS.pick_random()
	apply_color_to_blocks(piece_color)

	await get_tree().process_frame
	start_pos = global_position
	scale     = Vector2(idle_scale, idle_scale)
	print("[PIECE] prêt — start_pos=", start_pos, " blocs=", _count_blocks())

func _count_blocks() -> int:
	var c = 0
	for ch in get_children():
		if ch is Node2D: c += 1
	return c

func apply_color_to_blocks(c: Color):
	for child in get_children():
		if child.has_method("set_color"):
			child.set_color(c)

# ══════════════════════════════════════════════════════════════════════════════
#  INPUT  (_input pour ignorer les nœuds Control qui bloquent _unhandled_input)
# ══════════════════════════════════════════════════════════════════════════════
func _input(event: InputEvent):
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return

	var mouse = get_global_mouse_position()
	var rect  = get_rect_global()

	if event.pressed:
		print("[PIECE] clic — mouse=", mouse, " rect=", rect, " hit=", rect.has_point(mouse))
		if rect.has_point(mouse):
			get_viewport().set_input_as_handled()
			start_dragging(mouse)
	else:
		if dragging:
			get_viewport().set_input_as_handled()
			stop_dragging()

func start_dragging(mouse_pos: Vector2):
	print("[PIECE] start_dragging")
	dragging = true
	# offset positionne la pièce drag_offset_y pixels AU-DESSUS du curseur (effet visuel)
	offset   = (global_position - mouse_pos) + Vector2(0, drag_offset_y)
	z_index  = 100
	if active_tween: active_tween.kill()
	active_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	active_tween.tween_property(self, "scale", Vector2.ONE, tween_speed)

func stop_dragging():
	print("[PIECE] stop_dragging — global_pos=", global_position)
	dragging = false
	z_index  = 0
	var grid = _find_grid()
	if grid and grid.has_method("hide_preview"):
		grid.hide_preview()
	check_placement()

# ══════════════════════════════════════════════════════════════════════════════
#  PROCESS — drag visuel + preview
# ══════════════════════════════════════════════════════════════════════════════
func _process(_delta):
	if not dragging: return

	global_position = get_global_mouse_position() + offset

	var grid = _find_grid()
	if not grid or not grid.has_method("show_preview"): return

	var top_left_positions: Array = []
	var source_cr: ColorRect       = null

	# ── CORRECTION (même logique que check_placement) ───────────────────────
	# On utilise la position de l'ancre + offsets locaux pour calculer les
	# positions de preview, évitant ainsi les erreurs d'arrondi cumulées
	# qui faisaient "sauter" les blocs des grosses pièces.
	var children_blocks: Array = []
	for child in get_children():
		if child is Node2D:
			children_blocks.append(child)
			if source_cr == null:
				source_cr = child.get_node_or_null("ColorRect")

	if not children_blocks.is_empty():
		var anchor = children_blocks[0]
		var anchor_placement = anchor.global_position - Vector2(0, drag_offset_y)
		top_left_positions.append(anchor_placement)
		for i in range(1, children_blocks.size()):
			var block = children_blocks[i]
			var local_offset = block.position - anchor.position
			var delta_x = int(round(local_offset.x / float(cell_size)))
			var delta_y = int(round(local_offset.y / float(cell_size)))
			# On reconstitue la position preview à partir de l'ancre + delta en pixels (cell_size)
			top_left_positions.append(anchor_placement + Vector2(delta_x * cell_size, delta_y * cell_size))

	if source_cr != null and not top_left_positions.is_empty():
		grid.show_preview(top_left_positions, piece_color, source_cr)

# ══════════════════════════════════════════════════════════════════════════════
#  BOUNDING RECT GLOBAL
# ══════════════════════════════════════════════════════════════════════════════
func get_rect_global() -> Rect2:
	var positions: Array = []
	for child in get_children():
		if child is Node2D:
			positions.append(child.global_position)

	if positions.is_empty():
		var s = cell_size * scale.x
		return Rect2(global_position - Vector2(s, s) * 0.5, Vector2(s, s))

	var min_x = positions[0].x; var max_x = positions[0].x
	var min_y = positions[0].y; var max_y = positions[0].y
	for p in positions:
		min_x = min(min_x, p.x); max_x = max(max_x, p.x)
		min_y = min(min_y, p.y); max_y = max(max_y, p.y)

	var bs = cell_size * scale.x
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x + bs, max_y - min_y + bs))

# ══════════════════════════════════════════════════════════════════════════════
#  PLACEMENT
# ══════════════════════════════════════════════════════════════════════════════
func check_placement():
	print("[PIECE] check_placement START")
	var grid = _find_grid()
	if not grid:
		print("[PIECE] ERREUR : GridMultiplayer introuvable")
		return_to_start(); return

	var blocks: Array = []
	for child in get_children():
		if child is Node2D:
			blocks.append(child)

	print("[PIECE] nb blocs = ", blocks.size())
	if blocks.is_empty():
		return_to_start(); return


	var placement_data: Array = []
	var coords_only:    Array = []

	# ── CORRECTION BUG "PIÈCES QUI SE DIVISENT" ─────────────────────────────
	# AVANT : get_cell_coordinates() appelé indépendamment pour chaque bloc.
	#   → position_globale / cell_dim (110) accumulait des erreurs d'arrondi.
	#   → Exemple : offset 720px → 720/110 = 6.545 → round() = 7 au lieu de 6
	#     → un bloc "saute" une case → GAP visible dans la grille.
	#
	# APRÈS : on ancre sur le 1er bloc (1 seul appel get_cell_coordinates),
	#   puis on dérive toutes les autres cases via les positions LOCALES
	#   de la pièce divisées par cell_size (110).
	#   → Arrondi exact et indépendant pour chaque bloc, sans accumulation.

	# 1. Coordonnée de référence via le premier bloc
	var anchor_block    = blocks[0]
	var anchor_adjusted = anchor_block.global_position - Vector2(0, drag_offset_y)
	var anchor_coords   = grid.get_cell_coordinates(anchor_adjusted)

	print("[PIECE]   ancre phys=", anchor_block.global_position,
		  " → ajusté=", anchor_adjusted,
		  " → coords=", anchor_coords)

	if anchor_coords == null:
		print("[PIECE] ancre hors grille → retour start")
		_shake_feedback(); return_to_start(); return

	# 2. Chaque bloc → delta en cellules depuis l'ancre (positions locales)
	for block in blocks:
		var local_offset = block.position - anchor_block.position
		var delta_x = int(round(local_offset.x / float(cell_size)))
		var delta_y = int(round(local_offset.y / float(cell_size)))
		var coords  = anchor_coords + Vector2(delta_x, delta_y)

		print("[PIECE]   bloc local=", block.position,
			  " → delta=(", delta_x, ",", delta_y, ")",
			  " → coords=", coords)

		placement_data.append({"coords": coords, "node": block})
		coords_only.append(coords)

	print("[PIECE] coords_only = ", coords_only)

	var valid = grid.is_placement_valid(coords_only)
	print("[PIECE] is_placement_valid = ", valid)

	if not valid:
		print("[PIECE] invalide → retour start")
		_shake_feedback(); return_to_start(); return

	# ── Application ──────────────────────────────────────────────────────────
	for item in placement_data:
		var cx = int(item.coords.x)
		var cy = int(item.coords.y)
		grid.grid_data[cy][cx] = 1

		var cell_name   = "Cell_%d_%d" % [cx, cy]
		var target_cell = grid.get_node_or_null(cell_name)
		if target_cell == null:
			print("[PIECE] ERREUR cellule introuvable : ", cell_name)
			continue

		print("[PIECE]   → ", cell_name)

		# keep_global_transform = false : le bloc se place en (0,0) dans la cellule
		item.node.reparent(target_cell, false)
		item.node.position = Vector2.ZERO
		item.node.scale    = Vector2.ONE
		# Le fond de la cellule reste visible intentionnellement

	print("[PIECE] ✓ posée avec succès !")
	finalize_move(grid, blocks.size(), placement_data)

func finalize_move(grid, block_count: int, placement_data: Array = []):
	if grid.has_method("update_score"): grid.update_score(block_count * 10)
	
	var damage = 0
	if grid.has_method("check_lines"):  
		damage = grid.check_lines() # On récupère les dégâts calculés

	var coords_list: Array = []
	for item in placement_data:
		coords_list.append(item.coords)

	var fm = get_tree().root.get_node_or_null("FirebaseManager")
	if fm and fm.has_method("push_move"):
		var is_attack = damage > 0
		fm.push_move(coords_list, piece_color, is_attack, damage) # Ajout du paramètre

	var manager = get_parent()
	if manager and manager.has_method("check_game_over"):
		manager.call_deferred("check_game_over")

	queue_free()

func return_to_start():
	if active_tween: active_tween.kill()
	active_tween = create_tween().set_parallel(true) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	active_tween.tween_property(self, "global_position", start_pos, 0.2)
	active_tween.tween_property(self, "scale", Vector2(idle_scale, idle_scale), 0.2)

func _shake_feedback():
	var o = global_position
	var t = create_tween()
	t.tween_property(self, "global_position", o + Vector2(8,  0), 0.04)
	t.tween_property(self, "global_position", o + Vector2(-8, 0), 0.04)
	t.tween_property(self, "global_position", o + Vector2(6,  0), 0.03)
	t.tween_property(self, "global_position", o,                   0.03)

func _find_grid() -> Node:
	return get_tree().root.find_child("GridMultiplayer", true, false)
