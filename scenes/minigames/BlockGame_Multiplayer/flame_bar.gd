# flame_bar.gd
# À attacher sur un Node2D ou CanvasLayer dans ta scène de jeu.
# Ce nœud dessine lui-même les icônes de flammes — pas besoin de sprites externes.
# Les flammes pleines = disponibles, les flammes vides = dépensées.
# La dernière flamme en cours de recharge se remplit progressivement.

extends Node2D

# ── Paramètres ajustables dans l'Inspector ────────────────────────────────────
@export var flame_size     : float = 48.0     # taille d'une flamme en pixels
@export var flame_spacing  : float = 8.0      # espace entre deux flammes
@export var bar_position   : Vector2 = Vector2(60, 1780)  # position à l'écran
@export var color_full     : Color = Color("FF6B00")       # flamme pleine
@export var color_empty    : Color = Color(0.3, 0.3, 0.3, 0.5)  # flamme vide
@export var color_filling  : Color = Color("FFAA44")       # flamme en regen

# ── Références ────────────────────────────────────────────────────────────────
var _grid : Node = null

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	# Cherche la grille et connecte le signal flames_changed
	await get_tree().process_frame
	_grid = get_tree().root.find_child("GridMultiplayer", true, false)
	if _grid and _grid.has_signal("flames_changed"):
		_grid.flames_changed.connect(_on_flames_changed)
	else:
		push_error("[FlameBar] GridMultiplayer ou signal 'flames_changed' introuvable !")
	queue_redraw()

func _on_flames_changed(_current: int, _maximum: int):
	queue_redraw()   # redessine à chaque changement

func _process(_delta):
	# Redessine chaque frame pour animer la flamme en cours de regen (remplissage lisse)
	queue_redraw()

# ══════════════════════════════════════════════════════════════════════════════
#  DESSIN
# ══════════════════════════════════════════════════════════════════════════════
func _draw():
	if not _grid:
		return

	var exact   : float = _grid.get_flames_exact()        # ex: 4.73
	var full    : int   = int(exact)                       # flammes entières pleines
	var partial : float = exact - float(full)              # fraction de la flamme en regen
	var maximum : int   = _grid.FLAME_MAX

	var total_width = maximum * (flame_size + flame_spacing) - flame_spacing
	var origin = bar_position - Vector2(total_width * 0.5, 0)

	for i in range(maximum):
		var center = origin + Vector2(i * (flame_size + flame_spacing) + flame_size * 0.5, 0)

		if i < full:
			# Flamme pleine
			_draw_flame(center, flame_size, color_full, 1.0)
		elif i == full and partial > 0.01:
			# Flamme en cours de recharge (partiellement remplie)
			_draw_flame(center, flame_size, color_filling, partial)
			# Fond vide derrière
			_draw_flame_outline(center, flame_size, color_empty)
		else:
			# Flamme vide
			_draw_flame(center, flame_size, color_empty, 1.0)

	# Texte : nb flammes disponibles / max
	draw_string(ThemeDB.fallback_font,
		origin + Vector2(total_width * 0.5 - 20, flame_size + 20),
		"%d / %d" % [full, maximum],
		HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color.WHITE)

# ── Dessine une flamme simplifiée via des polygones ───────────────────────────
func _draw_flame(center: Vector2, size: float, color: Color, fill: float):
	var h  = size
	var w  = size * 0.6
	var clr = Color(color.r, color.g, color.b, color.a * fill)

	# Corps principal (pentagone arrondi approximé avec 5 points)
	var pts = PackedVector2Array([
		center + Vector2(0,        -h * 0.5),   # pointe haute
		center + Vector2( w * 0.5, -h * 0.1),   # droite haute
		center + Vector2( w * 0.45, h * 0.5),   # droite bas
		center + Vector2(-w * 0.45, h * 0.5),   # gauche bas
		center + Vector2(-w * 0.5, -h * 0.1),   # gauche haute
	])
	draw_colored_polygon(pts, clr)

	# Petite flamme intérieure (highlight) uniquement si fill > 0.3
	if fill > 0.3:
		var inner_clr = Color(1.0, 1.0, 0.6, clr.a * 0.6)
		var inner = PackedVector2Array([
			center + Vector2(0,        -h * 0.28),
			center + Vector2( w * 0.22, h * 0.05),
			center + Vector2( 0,        h * 0.25),
			center + Vector2(-w * 0.22, h * 0.05),
		])
		draw_colored_polygon(inner, inner_clr)

func _draw_flame_outline(center: Vector2, size: float, color: Color):
	var h = size
	var w = size * 0.6
	var pts = PackedVector2Array([
		center + Vector2(0,        -h * 0.5),
		center + Vector2( w * 0.5, -h * 0.1),
		center + Vector2( w * 0.45, h * 0.5),
		center + Vector2(-w * 0.45, h * 0.5),
		center + Vector2(-w * 0.5, -h * 0.1),
	])
	draw_colored_polygon(pts, color)
