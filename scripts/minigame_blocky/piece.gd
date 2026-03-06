extends Node2D

# --- Configuration ---
@export var idle_scale: float = 0.6
@export var drag_offset_y: float = -150.0
@export var tween_speed: float = 0.15
@export var cell_size: int = 120

var dragging: bool = false
var offset: Vector2 = Vector2.ZERO
var start_pos: Vector2 = Vector2.ZERO
var active_tween: Tween
var piece_color: Color = Color.WHITE # stockée pour la preview

var COLORS: Array[Color] = [
	Color("FF595E"), Color("FFCA3A"), Color("8AC926"),
	Color("1982C4"), Color("6A4C93")
]

func _ready():
	randomize()
	piece_color = COLORS.pick_random()
	apply_color_to_blocks(piece_color)

	await get_tree().process_frame
	start_pos = global_position
	scale = Vector2(idle_scale, idle_scale)

func apply_color_to_blocks(c: Color):
	for child in get_children():
		if child.has_method("set_color"):
			child.set_color(c)

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if get_rect_global().has_point(event.global_position):
				start_dragging(event.global_position)
		elif dragging:
			stop_dragging()

func start_dragging(mouse_pos: Vector2):
	dragging = true
	offset = (global_position - mouse_pos) + Vector2(0, drag_offset_y)
	z_index = 100

	if active_tween:
		active_tween.kill()
	active_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	active_tween.tween_property(self, "scale", Vector2.ONE, tween_speed)

func stop_dragging():
	dragging = false
	z_index = 0
	var grid = get_tree().root.find_child("Grid", true, false)
	if grid and grid.has_method("hide_preview"):
		grid.hide_preview()
	check_placement()

# ─── Process : drag + mise à jour preview ─────────────────────────────────────
func _process(_delta):
	if not dragging:
		return

	global_position = get_global_mouse_position() + offset

	var grid = get_tree().root.find_child("Grid", true, false)
	if not grid or not grid.has_method("show_preview"):
		return

	# Positions haut-gauche de chaque bloc + récup du ColorRect source (1er bloc)
	var top_left_positions: Array = []
	var source_cr: ColorRect = null

	for child in get_children():
		if child is Node2D:
			# global_position du bloc = haut-gauche (pivot confirmé haut-gauche)
			top_left_positions.append(child.global_position)
			if source_cr == null:
				source_cr = child.get_node_or_null("ColorRect")

	if source_cr != null:
		grid.show_preview(top_left_positions, piece_color, source_cr)

# ─── Bounding rect global ─────────────────────────────────────────────────────
func get_rect_global() -> Rect2:
	var rect = Rect2()
	var first = true

	for child in get_children():
		if child is Node2D:
			var visual = child.get_node_or_null("ColorRect")
			if not visual:
				visual = child

			var child_rect: Rect2
			if visual.has_method("get_global_rect"):
				child_rect = visual.get_global_rect()
			else:
				child_rect = Rect2(child.global_position, Vector2(cell_size, cell_size))

			if first:
				rect = child_rect
				first = false
			else:
				rect = rect.merge(child_rect)

	return rect

# ─── Placement ────────────────────────────────────────────────────────────────
func check_placement():
	var grid = get_tree().root.find_child("Grid", true, false)
	if not grid:
		return_to_start()
		return

	var placement_data = []
	var can_place = true
	var blocks = []

	for child in get_children():
		if child is Node2D:
			blocks.append(child)

	# 1. Vérification — centre du bloc = top_left + demi-cellule
	for block in blocks:
		var center_pos = block.global_position + Vector2(cell_size, cell_size) * 0.5
		var coords = grid.get_cell_coordinates(center_pos)

		if coords == null or grid.grid_data[int(coords.y)][int(coords.x)] != 0:
			can_place = false
			break

		placement_data.append({"coords": coords, "node": block})

	# Vérification des doublons dans placement_data
	if can_place:
		var seen = []
		for item in placement_data:
			var key = str(int(item.coords.x)) + "_" + str(int(item.coords.y))
			if key in seen:
				can_place = false
				break
			seen.append(key)

	# 2. Application
	if can_place and placement_data.size() == blocks.size() and blocks.size() > 0:
		for item in placement_data:
			var cx = int(item.coords.x)
			var cy = int(item.coords.y)

			grid.grid_data[cy][cx] = 1
			var target_cell = grid.get_node("Cell_" + str(cx) + "_" + str(cy))

			item.node.reparent(target_cell)
			item.node.position = Vector2.ZERO
			item.node.scale = Vector2.ONE

			var bg = target_cell.get_node_or_null("cell")
			if bg:
				bg.visible = false

		finalize_move(grid, blocks.size())
	else:
		_shake_feedback()
		return_to_start()

func finalize_move(grid, block_count: int):
	var score = block_count * 10
	if grid.has_method("update_score"):
		grid.update_score(score)
	if grid.has_method("check_lines"):
		grid.check_lines()

	var manager = get_parent()
	if manager and manager.has_method("check_game_over"):
		manager.call_deferred("check_game_over")

	queue_free()

func return_to_start():
	if active_tween:
		active_tween.kill()
	active_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	active_tween.tween_property(self, "global_position", start_pos, 0.2)
	active_tween.tween_property(self, "scale", Vector2(idle_scale, idle_scale), 0.2)

# ─── Feedback visuel quand le placement échoue ────────────────────────────────
func _shake_feedback():
	var origin = global_position
	var tween = create_tween()
	tween.tween_property(self, "global_position", origin + Vector2(8, 0), 0.04)
	tween.tween_property(self, "global_position", origin + Vector2(-8, 0), 0.04)
	tween.tween_property(self, "global_position", origin + Vector2(6, 0), 0.03)
	tween.tween_property(self, "global_position", origin, 0.03)
