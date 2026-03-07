# leaderboard_screen.gd
extends Control

const MAX_ENTRIES : int   = 100
const ROW_HEIGHT  : float = 82.0

const FONT_LUCKY = preload("res://assets/fonts/LuckiestGuy-Regular.ttf")

# ── Palette ───────────────────────────────────────────────────────────────────
const COL_BG        = Color(0.04,  0.04,  0.10,  1.0)
const COL_GOLD      = Color(1.0,   0.84,  0.0,   1.0)
const COL_SILVER    = Color(0.78,  0.84,  0.90,  1.0)
const COL_BRONZE    = Color(0.80,  0.50,  0.20,  1.0)
const COL_ACCENT    = Color(0.49,  0.30,  1.0,   1.0)
const COL_TEXT      = Color(0.91,  0.91,  0.94,  1.0)
const COL_SUBTEXT   = Color(0.42,  0.42,  0.60,  1.0)
const COL_ME_BG     = Color(0.09,  0.06,  0.22,  1.0)
const COL_ME_BORDER = Color(1.0,   0.84,  0.0,   1.0)
const COL_ROW_ODD   = Color(0.07,  0.07,  0.16,  1.0)
const COL_ROW_EVEN  = Color(0.05,  0.05,  0.13,  1.0)
const COL_TOP3_BG   = Color(0.10,  0.05,  0.20,  1.0)
const COL_DIVIDER   = Color(0.17,  0.17,  0.30,  1.0)

# ── Refs ──────────────────────────────────────────────────────────────────────
@onready var entries_list  : VBoxContainer   = $MainMargin/MainVBox/ScrollContainer/EntriesList
@onready var scroll        : ScrollContainer = $MainMargin/MainVBox/ScrollContainer
@onready var my_rank_row   : PanelContainer  = $MainMargin/MainVBox/MyRankRow
@onready var my_rank_lbl   : Label           = $MainMargin/MainVBox/MyRankRow/MyRankHBox/MyRankLbl
@onready var my_name_lbl   : Label           = $MainMargin/MainVBox/MyRankRow/MyRankHBox/MyNameLbl
@onready var my_trophy_lbl : Label           = $MainMargin/MainVBox/MyRankRow/MyRankHBox/MyTrophyLbl
@onready var loading_lbl   : Label           = $LoadingLabel
@onready var back_btn      : Button          = $MainMargin/MainVBox/Header/BackBtn

var _player_id     : String = ""
var _player_pseudo : String = ""
var _pulse_tween   : Tween  = null
var _load_tween    : Tween  = null
var _dot_count     : int    = 0

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	_load_local_player()
	_style_my_rank_row()
	_style_you_badge()
	back_btn.pressed.connect(_on_back_pressed)
	_start_loading_anim()
	_fetch_leaderboard()

# ══════════════════════════════════════════════════════════════════════════════
#  DONNÉES LOCALES
# ══════════════════════════════════════════════════════════════════════════════
func _load_local_player():
	var config = ConfigFile.new()
	if config.load("user://player.cfg") == OK:
		_player_id     = config.get_value("player", "id",     "")
		_player_pseudo = config.get_value("player", "pseudo", "Moi")

# ══════════════════════════════════════════════════════════════════════════════
#  LOADING ANIMATION
# ══════════════════════════════════════════════════════════════════════════════
func _start_loading_anim():
	loading_lbl.visible = true
	_load_tween = create_tween().set_loops(0)
	_load_tween.tween_callback(_tick_loading_dots).set_delay(0.5)

func _tick_loading_dots():
	_dot_count = (_dot_count + 1) % 4
	loading_lbl.text = "Chargement" + ".".repeat(_dot_count)

func _stop_loading_anim():
	if _load_tween:
		_load_tween.kill()
		_load_tween = null
	loading_lbl.visible = false

# ══════════════════════════════════════════════════════════════════════════════
#  FETCH FIREBASE
# ══════════════════════════════════════════════════════════════════════════════
func _fetch_leaderboard():
	my_rank_row.visible = false

	FirebaseManager.fb_get("/leaderboard.json", func(data):
		_stop_loading_anim()

		if typeof(data) != TYPE_DICTIONARY:
			loading_lbl.text    = "⚠  Impossible de charger le classement."
			loading_lbl.visible = true
			return

		var entries : Array = []
		for pid in data.keys():
			var e = data[pid]
			if typeof(e) != TYPE_DICTIONARY: continue
			entries.append({
				"pid":      pid,
				"pseudo":   e.get("pseudo",   "???"),
				"trophies": int(e.get("trophies", 0))
			})
		entries.sort_custom(func(a, b): return a["trophies"] > b["trophies"])

		_build_podium(entries)
		_build_list(entries)
		_build_my_rank(entries)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  PODIUM TOP 3
# ══════════════════════════════════════════════════════════════════════════════
func _build_podium(entries: Array):
	var section = get_node_or_null("MainMargin/MainVBox/PodiumSection")
	if not section: return
	for c in section.get_children(): c.queue_free()
	if entries.is_empty(): return

	# Ordre podium : 2e | 1er | 3e
	var order = [
		{ "idx": 1, "rank": 2, "medal": "🥈", "color": COL_SILVER, "size": 0.82, "block_h": 44.0, "delay": 0.15 },
		{ "idx": 0, "rank": 1, "medal": "🥇", "color": COL_GOLD,   "size": 1.0,  "block_h": 70.0, "delay": 0.0  },
		{ "idx": 2, "rank": 3, "medal": "🥉", "color": COL_BRONZE, "size": 0.75, "block_h": 28.0, "delay": 0.25 },
	]

	for o in order:
		if o["idx"] >= entries.size():
			var spacer = Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			section.add_child(spacer)
			continue

		var e     = entries[o["idx"]]
		var is_me = (e["pid"] == _player_id)
		var card  = _make_podium_card(e, o["rank"], o["medal"], o["color"], o["size"], o["block_h"], is_me)
		section.add_child(card)

		# Animation pop-in
		card.scale     = Vector2(0.55, 0.55)
		card.modulate.a = 0.0
		var d = o["delay"]
		get_tree().create_timer(d).timeout.connect(func():
			if not is_instance_valid(card): return
			var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			t.tween_property(card, "scale",       Vector2(1.0, 1.0), 0.45)
			t.parallel().tween_property(card, "modulate:a", 1.0,     0.30)
		)

		# Shimmer continu sur le #1
		if o["rank"] == 1:
			get_tree().create_timer(0.5).timeout.connect(func():
				if not is_instance_valid(card): return
				var s = create_tween().set_loops(0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				s.tween_property(card, "modulate", Color(1.1, 1.1, 0.85, 1.0), 1.2)
				s.tween_property(card, "modulate", Color(1.0, 1.0, 1.0,  1.0), 1.2)
			)

func _make_podium_card(entry: Dictionary, rank: int, medal: String, color: Color, size_factor: float, block_h: float, is_me: bool) -> Control:
	var wrapper = VBoxContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.alignment = BoxContainer.ALIGNMENT_END
	wrapper.add_theme_constant_override("separation", 0)
	wrapper.pivot_offset = Vector2(150, 130)

	# ── Carte info ──────────────────────────────────────────────────────────
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style = StyleBoxFlat.new()
	style.bg_color               = color.lerp(Color(0.05, 0.04, 0.14), 0.72)
	style.border_color           = color
	style.border_width_left      = 2
	style.border_width_top       = 2 if rank != 1 else 3
	style.border_width_right     = 2
	style.border_width_bottom    = 0
	style.corner_radius_top_left     = 14
	style.corner_radius_top_right    = 14
	style.corner_radius_bottom_left  = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left   = 10
	style.content_margin_right  = 10
	style.content_margin_top    = 10
	style.content_margin_bottom = 10
	if rank == 1:
		style.shadow_color = color
		style.shadow_color.a = 0.45
		style.shadow_size   = 20
	panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Couronne #1
	if rank == 1:
		var crown = Label.new()
		crown.text = "👑"
		crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crown.add_theme_font_size_override("font_size", 30)
		vbox.add_child(crown)

	# Médaille
	var medal_lbl = Label.new()
	medal_lbl.text = medal
	medal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal_lbl.add_theme_font_size_override("font_size", int(30 * size_factor))
	vbox.add_child(medal_lbl)

	# Pseudo
	var name_lbl = Label.new()
	var display_name = entry["pseudo"].left(9)
	name_lbl.text = display_name + (" 👤" if is_me else "")
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", FONT_LUCKY)
	name_lbl.add_theme_font_size_override("font_size", int(18 * size_factor))
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.add_theme_constant_override("outline_size", 1)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	vbox.add_child(name_lbl)

	# Trophées
	var trophy_lbl = Label.new()
	trophy_lbl.text = "🏆 %d" % entry["trophies"]
	trophy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trophy_lbl.add_theme_font_override("font", FONT_LUCKY)
	trophy_lbl.add_theme_font_size_override("font_size", int(16 * size_factor))
	trophy_lbl.add_theme_color_override("font_color", color)
	vbox.add_child(trophy_lbl)

	wrapper.add_child(panel)

	# ── Bloc podium (pied coloré) ────────────────────────────────────────────
	var block = ColorRect.new()
	block.color = color.lerp(Color(0.04, 0.04, 0.10), 0.55)
	block.custom_minimum_size = Vector2(0, block_h)
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(block)

	# Rang sur le bloc
	var rank_on_block = Label.new()
	rank_on_block.text = "#%d" % rank
	rank_on_block.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_on_block.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	rank_on_block.add_theme_font_override("font", FONT_LUCKY)
	rank_on_block.add_theme_font_size_override("font_size", int(20 * size_factor))
	rank_on_block.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.55))
	rank_on_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_on_block.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	block.add_child(rank_on_block)
	rank_on_block.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	return wrapper

# ══════════════════════════════════════════════════════════════════════════════
#  LISTE (rang 4+)
# ══════════════════════════════════════════════════════════════════════════════
func _build_list(entries: Array):
	for child in entries_list.get_children():
		child.queue_free()

	# On skip les 3 premiers (déjà dans le podium)
	var start = min(3, entries.size())
	var limit = min(entries.size(), MAX_ENTRIES)

	for i in range(start, limit):
		var e     = entries[i]
		var rank  = i + 1
		var is_me = (e["pid"] == _player_id)
		entries_list.add_child(_make_row(rank, e["pseudo"], e["trophies"], is_me))

func _make_row(rank: int, pseudo: String, trophies: int, is_me: bool) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	# ── Fond ──────────────────────────────────────────────────────────────────
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left     = 12
	style.corner_radius_top_right    = 12
	style.corner_radius_bottom_left  = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left   = 0
	style.content_margin_right  = 16
	style.content_margin_top    = 0
	style.content_margin_bottom = 0

	if is_me:
		style.bg_color          = COL_ME_BG
		style.border_color      = COL_ME_BORDER
		style.border_width_left = 4
		style.border_width_top  = 1; style.border_width_bottom = 1; style.border_width_right = 1
		style.shadow_color      = COL_ME_BORDER
		style.shadow_color.a    = 0.25
		style.shadow_size       = 14
	else:
		style.bg_color          = COL_ROW_ODD if rank % 2 == 1 else COL_ROW_EVEN
		style.border_color      = COL_DIVIDER
		style.border_width_left = 3
		style.border_color      = _rank_color(rank).lerp(COL_DIVIDER, 0.6)
	panel.add_theme_stylebox_override("panel", style)

	# ── Contenu ───────────────────────────────────────────────────────────────
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# Rang
	var rank_lbl = Label.new()
	rank_lbl.custom_minimum_size     = Vector2(64, 0)
	rank_lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	rank_lbl.add_theme_font_override("font", FONT_LUCKY)
	rank_lbl.text = "#%d" % rank
	rank_lbl.add_theme_font_size_override("font_size", 20)
	var rc = COL_ACCENT if is_me else COL_SUBTEXT
	rank_lbl.add_theme_color_override("font_color", rc)
	hbox.add_child(rank_lbl)

	# Pseudo
	var name_lbl = Label.new()
	name_lbl.text                  = pseudo
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", FONT_LUCKY)
	name_lbl.add_theme_font_size_override("font_size", 21)
	var nc = COL_ME_BORDER if is_me else _rank_color(rank)
	name_lbl.add_theme_color_override("font_color", nc)
	if is_me:
		name_lbl.add_theme_constant_override("outline_size", 1)
		name_lbl.add_theme_color_override("font_outline_color", Color(0.5, 0.3, 0, 0.4))
	hbox.add_child(name_lbl)

	# Trophées
	var trophy_lbl = Label.new()
	trophy_lbl.custom_minimum_size  = Vector2(110, 0)
	trophy_lbl.text                 = "🏆 %d" % trophies
	trophy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trophy_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	trophy_lbl.add_theme_font_override("font", FONT_LUCKY)
	trophy_lbl.add_theme_font_size_override("font_size", 20)
	trophy_lbl.add_theme_color_override("font_color", _rank_color(rank) if not is_me else COL_GOLD)
	hbox.add_child(trophy_lbl)

	# ── Animation : slide depuis la droite ────────────────────────────────────
	panel.modulate.a      = 0.0
	panel.position.x     = 80.0
	var delay = (rank - 4) * 0.022
	get_tree().create_timer(max(0.0, delay)).timeout.connect(func():
		if not is_instance_valid(panel): return
		var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(panel, "modulate:a",  1.0,  0.28)
		t.parallel().tween_property(panel, "position:x", 0.0, 0.28)
	)

	return panel

func _rank_color(rank: int) -> Color:
	match rank:
		1: return COL_GOLD
		2: return COL_SILVER
		3: return COL_BRONZE
		_: return COL_TEXT

# ══════════════════════════════════════════════════════════════════════════════
#  MA POSITION — BANDE FIXE EN BAS
# ══════════════════════════════════════════════════════════════════════════════
func _build_my_rank(entries: Array):
	var my_rank    : int = -1
	var my_trophies: int = 0

	for i in range(entries.size()):
		if entries[i]["pid"] == _player_id:
			my_rank     = i + 1
			my_trophies = entries[i]["trophies"]
			break

	if my_rank == -1:
		my_rank_row.visible = false
		return

	my_rank_lbl.text   = "#%d" % my_rank
	my_name_lbl.text   = _player_pseudo
	my_trophy_lbl.text = "🏆 %d" % my_trophies
	my_rank_row.visible = true

	_animate_my_rank_row()

	# Scroll auto si hors du top 10
	if my_rank > 10:
		await get_tree().create_timer(0.5).timeout
		scroll.scroll_vertical = int((my_rank - 5) * ROW_HEIGHT)

func _animate_my_rank_row():
	# Apparition
	my_rank_row.modulate.a  = 0.0
	my_rank_row.position.y += 20.0
	var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(my_rank_row, "modulate:a",  1.0, 0.4)
	t.parallel().tween_property(my_rank_row, "position:y", 0.0, 0.4)

	# Pulsation border dorée continue
	await get_tree().create_timer(0.5).timeout
	if not is_instance_valid(my_rank_row): return
	_pulse_tween = create_tween().set_loops(0).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_method(_set_my_rank_border_alpha, 1.0, 0.35, 1.1)
	_pulse_tween.tween_method(_set_my_rank_border_alpha, 0.35, 1.0, 1.1)

func _set_my_rank_border_alpha(a: float):
	if not is_instance_valid(my_rank_row): return
	var style = StyleBoxFlat.new()
	style.bg_color               = COL_ME_BG
	style.border_color           = Color(COL_ME_BORDER.r, COL_ME_BORDER.g, COL_ME_BORDER.b, a)
	style.border_width_left      = 2
	style.border_width_top       = 2
	style.border_width_right     = 2
	style.border_width_bottom    = 2
	style.corner_radius_top_left     = 16
	style.corner_radius_top_right    = 16
	style.corner_radius_bottom_left  = 16
	style.corner_radius_bottom_right = 16
	style.shadow_color = Color(COL_ME_BORDER.r, COL_ME_BORDER.g, COL_ME_BORDER.b, a * 0.35)
	style.shadow_size  = 18
	my_rank_row.add_theme_stylebox_override("panel", style)

# ══════════════════════════════════════════════════════════════════════════════
#  STYLES SCÈNE
# ══════════════════════════════════════════════════════════════════════════════
func _style_my_rank_row():
	my_rank_row.visible = false

	my_rank_lbl.add_theme_font_override("font", FONT_LUCKY)
	my_rank_lbl.add_theme_font_size_override("font_size", 26)
	my_rank_lbl.add_theme_color_override("font_color", COL_ACCENT)
	my_rank_lbl.custom_minimum_size      = Vector2(68, 0)
	my_rank_lbl.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
	my_rank_lbl.vertical_alignment       = VERTICAL_ALIGNMENT_CENTER

	my_name_lbl.add_theme_font_override("font", FONT_LUCKY)
	my_name_lbl.add_theme_font_size_override("font_size", 24)
	my_name_lbl.add_theme_color_override("font_color", COL_TEXT)
	my_name_lbl.vertical_alignment       = VERTICAL_ALIGNMENT_CENTER

	my_trophy_lbl.add_theme_font_override("font", FONT_LUCKY)
	my_trophy_lbl.add_theme_font_size_override("font_size", 24)
	my_trophy_lbl.add_theme_color_override("font_color", COL_GOLD)
	my_trophy_lbl.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER

func _style_you_badge():
	var badge = get_node_or_null("MainMargin/MainVBox/MyRankRow/MyRankHBox/YouBadge")
	if not badge: return

	badge.add_theme_font_override("font", FONT_LUCKY)
	badge.add_theme_font_size_override("font_size", 13)
	badge.add_theme_color_override("font_color", Color(0.04, 0.04, 0.10, 1.0))
	badge.custom_minimum_size         = Vector2(48, 24)
	badge.horizontal_alignment        = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment          = VERTICAL_ALIGNMENT_CENTER

	# Fond doré pour le badge
	var s = StyleBoxFlat.new()
	s.bg_color               = COL_GOLD
	s.corner_radius_top_left     = 8
	s.corner_radius_top_right    = 8
	s.corner_radius_bottom_left  = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left   = 6
	s.content_margin_right  = 6
	s.content_margin_top    = 3
	s.content_margin_bottom = 3

	# Badge via PanelContainer wrappé — on stylise directement le label
	# via une inner StyleBox n'existe pas sur Label, donc on met juste
	# la couleur de fond en override via un parent Panel si besoin.
	# Ici on garde le label stylisé avec couleur de texte sombre sur fond doré
	# en utilisant le fond du MyRankRow.
	badge.add_theme_color_override("font_color", COL_GOLD)
	badge.add_theme_font_size_override("font_size", 14)
	badge.text = "👤 VOUS"

# ══════════════════════════════════════════════════════════════════════════════
#  NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════
func _on_back_pressed():
	queue_free()

func _on_back_btn_pressed():
	get_tree().change_scene_to_file("res://scenes/minigames/BlockGame_Multiplayer/Lobby.tscn")
