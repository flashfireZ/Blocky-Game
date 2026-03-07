# leaderboard_screen.gd
# À attacher sur la racine de la scène LeaderboardScreen.tscn
#
# ── Structure de scène à créer ──────────────────────────────────────────────
#  LeaderboardScreen (Control, full rect)
#    ├─ BG (ColorRect)                        # fond sombre
#    ├─ GlowTop (ColorRect)                   # lueur déco en haut
#    ├─ Header (HBoxContainer)
#    │    ├─ BackBtn (Button)                 # "←"
#    │    └─ TitleLabel (Label)               # "CLASSEMENT"
#    ├─ ScrollContainer
#    │    └─ EntriesList (VBoxContainer)      # rempli dynamiquement
#    ├─ Divider (ColorRect)                   # ligne séparatrice
#    ├─ MyRankRow (PanelContainer)            # position du joueur (fixée en bas)
#    │    └─ MyRankHBox (HBoxContainer)
#    │         ├─ MyRankLbl  (Label)          # "#42"
#    │         ├─ MyNameLbl  (Label)          # "Shadow"
#    │         └─ MyTrophyLbl (Label)         # "🏆 14"
#    └─ LoadingLabel (Label)                  # "Chargement..." (masqué après)
# ─────────────────────────────────────────────────────────────────────────────

extends Control

const MAX_ENTRIES   : int   = 100
const ROW_HEIGHT    : float = 72.0

# ── Couleurs & styles ─────────────────────────────────────────────────────────
const COL_BG        : Color = Color("0d0d1a")
const COL_GLOW      : Color = Color("5c2be2", 0.35)
const COL_GOLD      : Color = Color("ffd700")
const COL_SILVER    : Color = Color("c0c0c0")
const COL_BRONZE    : Color = Color("cd7f32")
const COL_ACCENT    : Color = Color("7c4dff")
const COL_TEXT      : Color = Color("e8e8f0")
const COL_SUBTEXT   : Color = Color("7a7a99")
const COL_ME_BG     : Color = Color("1e1040")
const COL_ME_BORDER : Color = Color("7c4dff")
const COL_ROW_ODD   : Color = Color("12122a")
const COL_ROW_EVEN  : Color = Color("0d0d1e")
const COL_TOP3_BG   : Color = Color("1a0a3a")
const COL_DIVIDER   : Color = Color("2a2a4a")

@onready var entries_list  : VBoxContainer   = $ScrollContainer/EntriesList
@onready var scroll        : ScrollContainer = $ScrollContainer
@onready var my_rank_row   : PanelContainer  = $MyRankRow
@onready var my_rank_lbl   : Label           = $MyRankRow/MyRankHBox/MyRankLbl
@onready var my_name_lbl   : Label           = $MyRankRow/MyRankHBox/MyNameLbl
@onready var my_trophy_lbl : Label           = $MyRankRow/MyRankHBox/MyTrophyLbl
@onready var loading_lbl   : Label           = $LoadingLabel
@onready var back_btn      : Button          = $Header/BackBtn

var _player_id     : String = ""
var _player_pseudo : String = ""

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	_load_local_player()
	_style_scene()
	back_btn.pressed.connect(_on_back_pressed)
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
#  FETCH FIREBASE
# ══════════════════════════════════════════════════════════════════════════════
func _fetch_leaderboard():
	loading_lbl.visible   = true
	my_rank_row.visible   = false

	FirebaseManager.fb_get("/leaderboard.json", func(data):
		loading_lbl.visible = false

		if typeof(data) != TYPE_DICTIONARY:
			loading_lbl.text    = "Impossible de charger le classement."
			loading_lbl.visible = true
			return

		# Trier les entrées par trophées décroissants
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

		_build_list(entries)
		_build_my_rank(entries)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  CONSTRUCTION DE LA LISTE
# ══════════════════════════════════════════════════════════════════════════════
func _build_list(entries: Array):
	for child in entries_list.get_children():
		child.queue_free()

	var limit = min(entries.size(), MAX_ENTRIES)
	for i in range(limit):
		var e    = entries[i]
		var rank = i + 1
		var is_me = (e["pid"] == _player_id)
		entries_list.add_child(_make_row(rank, e["pseudo"], e["trophies"], is_me))

func _make_row(rank: int, pseudo: String, trophies: int, is_me: bool) -> PanelContainer:
	# ── Conteneur ─────────────────────────────────────────────────────────────
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var style = StyleBoxFlat.new()
	style.corner_radius_top_left     = 10
	style.corner_radius_top_right    = 10
	style.corner_radius_bottom_left  = 10
	style.corner_radius_bottom_right = 10

	if is_me:
		style.bg_color         = COL_ME_BG
		style.border_color     = COL_ME_BORDER
		style.border_width_top = 2; style.border_width_bottom = 2
		style.border_width_left = 2; style.border_width_right = 2
	elif rank <= 3:
		style.bg_color = COL_TOP3_BG
	else:
		style.bg_color = COL_ROW_ODD if rank % 2 == 1 else COL_ROW_EVEN

	style.content_margin_left   = 16
	style.content_margin_right  = 16
	style.content_margin_top    = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	# ── Layout horizontal ──────────────────────────────────────────────────────
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)

	# Médaille / rang
	var rank_lbl = Label.new()
	rank_lbl.custom_minimum_size = Vector2(52, 0)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match rank:
		1: rank_lbl.text = "🥇"; rank_lbl.add_theme_font_size_override("font_size", 28)
		2: rank_lbl.text = "🥈"; rank_lbl.add_theme_font_size_override("font_size", 26)
		3: rank_lbl.text = "🥉"; rank_lbl.add_theme_font_size_override("font_size", 24)
		_:
			rank_lbl.text = "#%d" % rank
			rank_lbl.add_theme_font_size_override("font_size", 17)
			var col = COL_ACCENT if is_me else COL_SUBTEXT
			rank_lbl.add_theme_color_override("font_color", col)
	hbox.add_child(rank_lbl)

	# Séparateur
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 0)
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = COL_DIVIDER
	sep.add_theme_stylebox_override("separator", sep_style)
	hbox.add_child(sep)

	# Pseudo
	var name_lbl = Label.new()
	name_lbl.text                   = pseudo + (" ← toi" if is_me else "")
	name_lbl.size_flags_horizontal  = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 19)
	var name_col = COL_ME_BORDER if is_me else _rank_color(rank)
	name_lbl.add_theme_color_override("font_color", name_col)
	hbox.add_child(name_lbl)

	# Trophées
	var trophy_lbl = Label.new()
	trophy_lbl.text = "🏆 %d" % trophies
	trophy_lbl.add_theme_font_size_override("font_size", 18)
	trophy_lbl.add_theme_color_override("font_color", _rank_color(rank))
	hbox.add_child(trophy_lbl)

	# Animation d'entrée décalée
	panel.modulate.a = 0.0
	var delay = rank * 0.018
	get_tree().create_timer(delay).timeout.connect(func():
		if not is_instance_valid(panel): return
		var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(panel, "modulate:a", 1.0, 0.25)
	)

	return panel

func _rank_color(rank: int) -> Color:
	match rank:
		1: return COL_GOLD
		2: return COL_SILVER
		3: return COL_BRONZE
		_: return COL_TEXT

# ══════════════════════════════════════════════════════════════════════════════
#  BANDE "MA POSITION" FIXÉE EN BAS
# ══════════════════════════════════════════════════════════════════════════════
func _build_my_rank(entries: Array):
	var my_rank : int = -1
	var my_trophies : int = 0

	for i in range(entries.size()):
		if entries[i]["pid"] == _player_id:
			my_rank    = i + 1
			my_trophies = entries[i]["trophies"]
			break

	if my_rank == -1:
		my_rank_row.visible = false
		return

	my_rank_lbl.text   = "#%d" % my_rank
	my_name_lbl.text   = _player_pseudo
	my_trophy_lbl.text = "🏆 %d" % my_trophies
	my_rank_row.visible = true

	# Scroll automatique vers notre position si on est en dehors des 10 premiers
	if my_rank > 10:
		await get_tree().create_timer(0.5).timeout
		scroll.scroll_vertical = int((my_rank - 5) * ROW_HEIGHT)

# ══════════════════════════════════════════════════════════════════════════════
#  STYLES PROCÉDURAUX
# ══════════════════════════════════════════════════════════════════════════════
func _style_scene():
	# Fond
	var bg = get_node_or_null("BG")
	if bg:
		bg.color = COL_BG

	# Lueur violette en haut
	var glow = get_node_or_null("GlowTop")
	if glow:
		glow.color = COL_GLOW

	# StyleBox de "Ma position"
	var my_style = StyleBoxFlat.new()
	my_style.bg_color             = COL_ME_BG
	my_style.border_color         = COL_ME_BORDER
	my_style.border_width_top     = 2
	my_style.content_margin_left  = 20
	my_style.content_margin_right = 20
	my_style.content_margin_top   = 12
	my_style.content_margin_bottom = 12
	my_rank_row.add_theme_stylebox_override("panel", my_style)

	# Labels "Ma position"
	my_rank_lbl.add_theme_font_size_override("font_size", 22)
	my_rank_lbl.add_theme_color_override("font_color", COL_ACCENT)
	my_rank_lbl.custom_minimum_size = Vector2(60, 0)
	my_rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	my_name_lbl.add_theme_font_size_override("font_size", 20)
	my_name_lbl.add_theme_color_override("font_color", COL_TEXT)
	my_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	my_trophy_lbl.add_theme_font_size_override("font_size", 20)
	my_trophy_lbl.add_theme_color_override("font_color", COL_GOLD)

	# Titre
	var title = get_node_or_null("Header/TitleLabel")
	if title:
		title.add_theme_font_size_override("font_size", 30)
		title.add_theme_color_override("font_color", COL_TEXT)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Bouton retour
	back_btn.add_theme_font_size_override("font_size", 22)
	back_btn.add_theme_color_override("font_color", COL_ACCENT)

	# Divider
	var div = get_node_or_null("Divider")
	if div: div.color = COL_ME_BORDER

	# Loading label
	loading_lbl.add_theme_font_size_override("font_size", 20)
	loading_lbl.add_theme_color_override("font_color", COL_SUBTEXT)
	loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

# ══════════════════════════════════════════════════════════════════════════════
#  NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════
func _on_back_pressed():
	queue_free()
