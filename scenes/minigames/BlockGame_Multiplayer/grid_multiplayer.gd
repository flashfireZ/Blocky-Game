extends Node2D

@export var cell_scene  : PackedScene = preload("res://scenes/minigames/BlockGame/Cell.tscn")
@export var block_scene : PackedScene = preload("res://scenes/minigames/BlockGame_Multiplayer/BlockMultiplayer.tscn")

var grid_rows = 12   # nombre de lignes
var grid_cols = 8    # nombre de colonnes
var cell_dim  = 110
var grid_positions = []
var grid_data      = []
var score          = 0

# ─── Stats multijoueur ────────────────────────────────────────────────────────
var player_hp      : int = 1500
var player_shield  : int = 0
var opponent_hp    : int = 1500
var opponent_shield: int = 0

signal game_over(winner: String)
signal stats_updated()

# !! CORRECTION BUG CRITIQUE !!
# On stocke l'origine GLOBALE de la grille (coin haut-gauche de la cellule 0,0).
# L'ancienne variable grid_start_pos était une coordonnée LOCALE à GridMultiplayer.
# Si GridMultiplayer n'est pas à (0,0) dans la scène, get_cell_coordinates() calculait
# de mauvaises cases → les pièces draguées vers la zone bleue arrivaient en zone rouge.
var grid_global_origin : Vector2
var grid_start_pos     : Vector2   # conservé pour la génération (position locale)

@onready var score_label    = get_tree().root.find_child("ScoreLabel",        true, false)
@onready var particles_base = get_tree().root.find_child("ExplosionParticles", true, false)
@onready var combo_label    = get_tree().root.find_child("ComboLabel",         true, false)

# ─── Tweens & Combo ───────────────────────────────────────────────────────────
var combo_streak: int = 0
var _combo_tween: Tween = null
var _score_tween: Tween = null

# ─── Preview ──────────────────────────────────────────────────────────────────
var preview_nodes: Array = []
var _preview_last_color: Color = Color(-1, -1, -1)

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
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.15, 1.15), 0.35)
	_combo_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_BOUNCE)
	_combo_tween.tween_property(combo_label, "scale", Vector2(1.0, 1.0), 0.2)
	_combo_tween.set_trans(Tween.TRANS_SINE)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees", -6.0, 0.06)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  3.0, 0.05)
	_combo_tween.tween_property(combo_label, "rotation_degrees",  0.0, 0.05)
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
	grid_start_pos = Vector2((1080 - total_grid_width) / 2.0, 150)

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

	# !! CORRECTION BUG CRITIQUE !!
	# On capture l'origine GLOBALE de la grille APRÈS que toutes les cellules
	# ont été ajoutées à la scène (global_position est fiable à ce stade).
	grid_global_origin = grid_positions[0][0]
	print("[Grid] Origine globale : ", grid_global_origin, " | GridMultiplayer.global_pos : ", global_position)

# ─── Snap / coordonnées ───────────────────────────────────────────────────────
func get_cell_coordinates(target_pos: Vector2):
	# !! CORRECTION BUG CRITIQUE !!
	# AVANT : var local_pos = target_pos - grid_start_pos
	#   → grid_start_pos est une coordonnée LOCALE à GridMultiplayer.
	#   → Si GridMultiplayer est décalé dans la scène, le calcul est FAUX.
	#
	# APRÈS : var local_pos = target_pos - grid_global_origin
	#   → grid_global_origin est la position GLOBALE réelle de la cellule (0,0).
	#   → Correct quel que soit le placement de GridMultiplayer dans la scène.
	var local_pos = target_pos - grid_global_origin

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

	for node in preview_nodes:
		node.visible = false

	var snapped_coords = []
	var valid = true

	for top_left in block_top_left_positions:
		var coords = get_cell_coordinates(top_left)
		if coords == null:
			valid = false
			break
		snapped_coords.append(coords)

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
func check_lines() -> int:
	var lines_to_clear = []
	# ... (Garde ta logique existante de détection des lignes pleines ici) ...
	
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
	var damage_dealt = 0 # On stocke les dégâts à envoyer

	if nb_lines > 0:
		var multi_simultane = nb_lines
		var multi_serie     = combo_streak
		var total_multi     = multi_simultane + multi_serie

		combo_streak += 1
		var points = nb_lines * 100 * total_multi
		update_score(points)

		# --- NOUVELLE LOGIQUE DE DÉGÂTS ET SHIELD ---
		for line in lines_to_clear:
			if line.type == "row":
				# Ligne horizontale = 8 cases (exemple : 2 points de shield par case x combo)
				var shield_gain = 8 * 2 * total_multi
				player_shield += shield_gain
				if player_shield > 1000: player_shield = 1000 # Cap maximum de bouclier
				# ── Animation shield ──────────────────────────────────────────
				animate_shield_gain(line.index, shield_gain)
			elif line.type == "col":
				# Ligne verticale = 12 cases (exemple : 5 points de dégâts par case x combo)
				var dmg = 12 * 5 * total_multi
				damage_dealt += dmg
				# ── Animation attaque ─────────────────────────────────────────
				animate_attack_launch(line.index, dmg)
		
		# On met à jour l'UI locale et on informe Firebase de nos propres stats
		emit_signal("stats_updated")
		var fm = get_tree().root.get_node_or_null("FirebaseManager")
		if fm and fm.has_method("push_stats_only"): fm.push_stats_only()

		if total_multi >= 2:
			show_combo_label(total_multi)
	else:
		if combo_streak > 0:
			print("Combo brisé (était x%d)" % combo_streak)
		combo_streak = 0

	for line in lines_to_clear:
		clear_line(line.type, line.index)

	return damage_dealt # On retourne les dégâts pour que la pièce puisse les envoyer

func clear_line(type, index):
	# ── Délai de stagger entre chaque bloc (effet de vague directionnelle) ────
	# ROW : gauche → droite  |  COL : haut → bas
	var STAGGER    : float = 0.055
	var FLASH_DUR  : float = 0.06
	var SHRINK_DUR : float = 0.13

	var count = grid_cols if type == "row" else grid_rows

	for i in range(count):
		var x = i if type == "row" else index
		var y = index if type == "row" else i

		var cell = get_node("Cell_" + str(x) + "_" + str(y))
		grid_data[y][x] = 0
		spawn_particles(cell.global_position)

		var delay : float = i * STAGGER

		for child in cell.get_children():
			if child.name != "Cell" and not child is Line2D:
				# 1. Flash blanc instantané
				var t = create_tween().set_parallel(true)
				t.tween_interval(delay)
				t.chain()
				t.set_parallel(true)
				t.tween_property(child, "modulate", Color(2.5, 2.5, 2.5, 1.0), FLASH_DUR)
				t.chain()
				t.set_parallel(true)
				t.tween_property(child, "scale",      Vector2.ZERO,             SHRINK_DUR)
				t.tween_property(child, "modulate:a", 0.0,                      SHRINK_DUR)
				t.chain().tween_callback(child.queue_free)

		# Restauration du fond de cellule après la fin de l'animation
		var bg = cell.get_node_or_null("Cell")
		if bg:
			var restore_tween = create_tween()
			restore_tween.tween_interval(delay + FLASH_DUR + SHRINK_DUR)
			restore_tween.tween_callback(func():
				bg.visible  = true
				bg.modulate = Color.WHITE
			)

# ══════════════════════════════════════════════════════════════════════════════
#  ANIMATIONS DE FEEDBACK : SHIELD & ATTAQUE
# ══════════════════════════════════════════════════════════════════════════════

# ─── Délai de base avant d'afficher le feedback (le temps que les blocs flash) ─
const FEEDBACK_DELAY := 0.35

func animate_shield_gain(row_index: int, shield_amount: int) -> void:
	# Centre horizontal de la grille, hauteur de la ligne effacée
	var row_center_x : float = grid_global_origin.x + float(grid_cols * cell_dim) / 2.0
	var row_center_y : float = grid_global_origin.y + float(row_index * cell_dim) + float(cell_dim) / 2.0
	var origin       : Vector2 = Vector2(row_center_x, row_center_y)

	await get_tree().create_timer(FEEDBACK_DELAY).timeout

	# ── Sweep lumineux horizontal (ligne qui traverse la rangée) ───────────────
	var sweep := ColorRect.new()
	sweep.color            = Color(0.0, 0.78, 1.0, 0.55)
	sweep.size             = Vector2(0, cell_dim * 0.85)
	sweep.global_position  = Vector2(grid_global_origin.x, row_center_y - cell_dim * 0.425)
	sweep.z_index          = 60
	add_child(sweep)

	var sweep_t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	sweep_t.tween_property(sweep, "size:x",     grid_cols * cell_dim, 0.18)
	sweep_t.tween_property(sweep, "modulate:a", 0.0,                  0.22)
	sweep_t.tween_callback(sweep.queue_free)

	# ── Icône 🛡 + valeur : pop élastique au centre ────────────────────────────
	var lbl := Label.new()
	lbl.text                    = "🛡  +%d" % shield_amount
	lbl.add_theme_font_size_override("font_size", 54)
	lbl.add_theme_color_override("font_color",        Color("00D4FF"))
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0.08, 0.25, 0.85))
	lbl.add_theme_constant_override("shadow_offset_x", 3)
	lbl.add_theme_constant_override("shadow_offset_y", 3)
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	lbl.size                    = Vector2(340, 80)
	lbl.pivot_offset            = lbl.size / 2.0
	lbl.global_position         = origin - lbl.size / 2.0
	lbl.scale                   = Vector2(0.0, 0.0)
	lbl.z_index                 = 80
	add_child(lbl)

	# Elastic scale-in  →  pause  →  float up + fade
	var lbl_t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	lbl_t.tween_property(lbl, "scale", Vector2(1.1, 1.1), 0.42)
	lbl_t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	lbl_t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.12)
	lbl_t.tween_interval(0.55)
	lbl_t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	lbl_t.set_parallel(true)
	lbl_t.tween_property(lbl, "global_position:y", lbl.global_position.y - 90.0, 0.45)
	lbl_t.tween_property(lbl, "modulate:a",        0.0,                           0.45)
	lbl_t.tween_callback(lbl.queue_free)


func animate_attack_launch(col_index: int, damage: int) -> void:
	var col_x     : float = grid_global_origin.x + float(col_index * cell_dim) + float(cell_dim) / 2.0
	var col_top_y : float = grid_global_origin.y
	var col_bot_y : float = grid_global_origin.y + float(grid_rows * cell_dim)

	await get_tree().create_timer(FEEDBACK_DELAY).timeout

	# ── Beam d'énergie : part du haut de la colonne et descend vers le bas ─────
	# Représente visuellement la trajectoire de l'attaque vers l'adversaire.
	var BEAM_W   : float = float(cell_dim) * 0.55
	var BEAM_CLR : Color = Color("FF5A1A")

	var beam := ColorRect.new()
	beam.color           = Color(BEAM_CLR.r, BEAM_CLR.g, BEAM_CLR.b, 0.80)
	beam.size            = Vector2(BEAM_W, 0)
	beam.global_position = Vector2(col_x - BEAM_W / 2.0, col_top_y)
	beam.z_index         = 70
	add_child(beam)

	# Lueur extérieure (halo plus large et transparent)
	var glow := ColorRect.new()
	glow.color           = Color(BEAM_CLR.r, BEAM_CLR.g, BEAM_CLR.b, 0.25)
	glow.size            = Vector2(BEAM_W * 2.6, 0)
	glow.global_position = Vector2(col_x - BEAM_W * 1.3, col_top_y)
	glow.z_index         = 69
	add_child(glow)

	# Phase 1 : le beam s'étend vers le bas (durée proportionnelle à la longueur)
	var GROW_DUR : float = 0.22
	var total_h  : float = col_bot_y - col_top_y + 200.0   # dépasse l'écran
	var beam_t     := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	beam_t.set_parallel(true)
	beam_t.tween_property(beam, "size:y", total_h, GROW_DUR)
	beam_t.tween_property(glow, "size:y", total_h, GROW_DUR)
	# Phase 2 : fade rapide
	beam_t.chain().set_parallel(true)
	beam_t.tween_property(beam, "modulate:a", 0.0, 0.18)
	beam_t.tween_property(glow, "modulate:a", 0.0, 0.18)
	beam_t.tween_callback(beam.queue_free)
	beam_t.tween_callback(glow.queue_free)

	# ── Petites particules rapides qui filent vers le bas ─────────────────────
	for k in range(5):
		var spark := ColorRect.new()
		var spark_w : float = randf_range(4.0, 9.0)
		var spark_h : float = randf_range(14.0, 28.0)
		spark.color           = Color(1.0, randf_range(0.4, 0.9), 0.1, 1.0)
		spark.size            = Vector2(spark_w, spark_h)
		spark.global_position = Vector2(
			col_x + randf_range(-BEAM_W * 0.6, BEAM_W * 0.6) - spark_w / 2.0,
			col_top_y + k * (grid_rows * cell_dim / 5.0)
		)
		spark.z_index = 71
		add_child(spark)
		var s_t := create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		s_t.set_parallel(true)
		var travel : float = col_bot_y - spark.global_position.y + 180.0
		s_t.tween_property(spark, "global_position:y", spark.global_position.y + travel, GROW_DUR + 0.05)
		s_t.tween_property(spark, "modulate:a", 0.0, GROW_DUR + 0.05)
		s_t.tween_callback(spark.queue_free)

	# ── Texte de dégâts : pop en haut de la colonne ───────────────────────────
	var dmg_lbl := Label.new()
	dmg_lbl.text = "⚔  -%d" % damage
	dmg_lbl.add_theme_font_size_override("font_size", 52)
	dmg_lbl.add_theme_color_override("font_color",        Color("FF5A1A"))
	dmg_lbl.add_theme_color_override("font_shadow_color", Color(0.25, 0.04, 0, 0.9))
	dmg_lbl.add_theme_constant_override("shadow_offset_x", 3)
	dmg_lbl.add_theme_constant_override("shadow_offset_y", 3)
	dmg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	dmg_lbl.size                 = Vector2(240, 72)
	dmg_lbl.pivot_offset         = dmg_lbl.size / 2.0
	# Positionné à gauche ou droite du beam selon la position dans la grille
	var lbl_offset_x : float = 130.0 if col_index < grid_cols / 2 else -130.0
	dmg_lbl.global_position      = Vector2(col_x + lbl_offset_x - 120.0, col_top_y - 10.0)
	dmg_lbl.scale                = Vector2(0.0, 0.0)
	dmg_lbl.z_index              = 80
	add_child(dmg_lbl)

	var dlbl_t := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	dlbl_t.tween_property(dmg_lbl, "scale", Vector2(1.15, 1.15), 0.20)
	dlbl_t.set_trans(Tween.TRANS_SINE)
	dlbl_t.tween_property(dmg_lbl, "scale", Vector2(1.0, 1.0),   0.10)
	dlbl_t.tween_interval(0.50)
	dlbl_t.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	dlbl_t.set_parallel(true)
	dlbl_t.tween_property(dmg_lbl, "global_position:y", dmg_lbl.global_position.y + 70.0, 0.40)
	dlbl_t.tween_property(dmg_lbl, "modulate:a",        0.0,                               0.40)
	dlbl_t.tween_callback(dmg_lbl.queue_free)

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
	var blocks = []
	for child in piece_node.get_children():
		if child is Node2D:
			blocks.append(child)
	if blocks.is_empty():
		return false

	var first_pos = blocks[0].position
	var raw_offsets = []
	for block in blocks:
		raw_offsets.append(block.position - first_pos)

	# !! CORRECTION : Normalisation des offsets en Y !!
	# Sans ça, si le premier bloc n'est pas celui le plus haut dans la pièce,
	# les offsets négatifs font croire que la pièce chevauche zones rouge et bleue
	# → is_placement_valid() retourne false → faux game-over dès le début.
	var min_y_cells = 0
	for off in raw_offsets:
		var oy = int(round(off.y / cell_dim))
		if oy < min_y_cells:
			min_y_cells = oy

	var normalized_offsets = []
	for off in raw_offsets:
		normalized_offsets.append(Vector2(off.x, off.y - min_y_cells * float(cell_dim)))

	# On teste uniquement la zone bleue (y >= 6) : zone du joueur local
	for y in range(6, grid_rows):
		for x in range(grid_cols):
			if _can_place_at_coords(x, y, normalized_offsets):
				return true

	return false

func is_placement_valid(coords: Array) -> bool:
	if coords.is_empty():
		print("[DEBUG] is_placement_valid: coords VIDE")
		return false

	var is_top    = false
	var is_bottom = false

	# 1. Vérifier les limites et dans quelle(s) zone(s) on se trouve
	for c in coords:
		if c.x < 0 or c.x >= grid_cols or c.y < 0 or c.y >= grid_rows:
			print("[DEBUG] is_placement_valid: hors grille -> ", c)
			return false

		if c.y < 6: is_top    = true
		else:       is_bottom = true

	print("[DEBUG] is_placement_valid: is_top=", is_top, " is_bottom=", is_bottom)

	# Interdit de placer une pièce à cheval entre les deux zones
	if is_top and is_bottom:
		print("[DEBUG] is_placement_valid: cheval entre les deux zones")
		return false

	# 2. RÈGLE ZONE JOUEUR (Bas, zone bleue) : Toutes les cases doivent être VIDES (0)
	if is_bottom:
		for c in coords:
			var val = grid_data[int(c.y)][int(c.x)]
			if val != 0:
				print("[DEBUG] is_placement_valid: case occupée en bas coords=", c, " val=", val)
				return false
		return true

	# 3. RÈGLE ZONE D'ATTAQUE (Haut, zone rouge) : Doit recouvrir PARFAITEMENT une pièce ennemie (2)
	if is_top:
		for c in coords:
			if grid_data[int(c.y)][int(c.x)] != 2:
				print("[DEBUG] is_placement_valid: case haut pas ennemie coords=", c, " val=", grid_data[int(c.y)][int(c.x)])
				return false

		var enemy_shape = _get_connected_opponent_cells(int(coords[0].x), int(coords[0].y))

		if coords.size() != enemy_shape.size():
			print("[DEBUG] is_placement_valid: taille pièce=", coords.size(), " != ennemi=", enemy_shape.size())
			return false

		return true

	print("[DEBUG] is_placement_valid: aucune zone détectée (ne devrait pas arriver)")
	return false

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
	var visited = {}
	var queue   = [Vector2(start_x, start_y)]
	var connected_shape = []

	while queue.size() > 0:
		var current = queue.pop_front()

		if visited.has(current): continue
		visited[current] = true

		if current.x < 0 or current.x >= grid_cols or current.y < 0 or current.y >= 6:
			continue

		if grid_data[int(current.y)][int(current.x)] == 2:
			connected_shape.append(current)
			queue.append(Vector2(current.x + 1, current.y))
			queue.append(Vector2(current.x - 1, current.y))
			queue.append(Vector2(current.x, current.y + 1))
			queue.append(Vector2(current.x, current.y - 1))

	return connected_shape

func deal_damage(amount: int):
	print("Dégâts infligés à l'adversaire : ", amount)

# ══════════════════════════════════════════════════════════════════════════════
#  MULTIJOUEUR
# ══════════════════════════════════════════════════════════════════════════════
func serialize_player_state() -> Dictionary:
	return {"hp": player_hp, "shield": player_shield}


func place_piece(coords: Array, color: Color, is_attack: bool, dmg_multi: float, _is_local: bool, damage_amount: int = 0):
	for c in coords:
		var cx = int(c.x); var cy = int(c.y)
		if cx < 0 or cx >= grid_cols or cy < 0 or cy >= grid_rows: continue
		grid_data[cy][cx] = 2
		var cell = get_node_or_null("Cell_" + str(cx) + "_" + str(cy))
		if cell:
			var block: Node2D
			if block_scene: block = block_scene.instantiate()
			if block.has_method("set_color"): block.set_color(color)
			block.z_index = 10
			cell.add_child(block)
			
	check_lines()
	
	if is_attack and not _is_local:
		var final_dmg = int(damage_amount * dmg_multi)
		
		# Le shield prend les dégâts en premier
		if player_shield > 0:
			if final_dmg >= player_shield:
				final_dmg -= player_shield
				player_shield = 0
			else:
				player_shield -= final_dmg
				final_dmg = 0
		
		# Le reste touche les HP
		player_hp -= final_dmg
		if player_hp < 0: player_hp = 0
		
		print("Dégâts reçus ! HP restants : ", player_hp, " | Shield : ", player_shield)
		emit_signal("stats_updated")
		
		# On informe Firebase qu'on a pris des dégâts
		var fm = get_tree().root.get_node_or_null("FirebaseManager")
		if fm and fm.has_method("push_stats_only"): fm.push_stats_only()

		if player_hp <= 0:
			emit_signal("game_over", "opponent")

# On s'assure que Firebase met à jour l'UI quand l'adversaire gagne/perd du shield
func sync_opponent_stats(hp: int, shield: int):
	opponent_hp     = hp
	opponent_shield = shield
	emit_signal("stats_updated")

# ══════════════════════════════════════════════════════════════════════════════
