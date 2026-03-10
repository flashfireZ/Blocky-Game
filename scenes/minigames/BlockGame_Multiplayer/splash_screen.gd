extends Node2D

const NEXT_SCENE := "res://scenes/minigames/BlockGame_Multiplayer/Lobby.tscn"
const FADE_OUT_DUR : float = 0.50

@onready var logo_label    : Label       = $LogoContainer/LogoLabel
@onready var by_label      : Label       = $LogoContainer/ByLabel
@onready var progress_bar  : ProgressBar = $LoadSection/LoadBar
@onready var loading_label : Label       = $LoadSection/LoadingLabel
@onready var percent_label : Label       = $LoadSection/PercentLabel
@onready var overlay       : ColorRect   = $FadeOverlay

const LOADING_TEXTS := [
	"INITIALISATION...",
	"CHARGEMENT DES RESSOURCES...",
	"CONNEXION AUX SERVEURS...",
	"PRÉPARATION DE LA GRILLE...",
	"C'EST PRESQUE PRÊT..."
]

var _text_idx := 0
var _text_timer := 0.0
const TEXT_INTERVAL := 0.52

var _loading := false
var _progress := []
var _done := false


func _ready():

	overlay.modulate.a = 1.0
	logo_label.modulate.a = 0.0
	by_label.modulate.a = 0.0
	$LoadSection.modulate.a = 0.0

	progress_bar.value = 0
	percent_label.text = "0%"
	loading_label.text = LOADING_TEXTS[0]

	_fade_in()


func _fade_in():

	var t := create_tween()
	t.tween_property(overlay, "modulate:a", 0.0, 0.55)
	t.tween_callback(_show_logo)


func _show_logo():

	logo_label.scale = Vector2(0.78,0.78)
	logo_label.pivot_offset = logo_label.size * 0.5

	var t := create_tween().set_parallel(true)

	t.tween_property(logo_label,"modulate:a",1.0,0.55)
	t.tween_property(logo_label,"scale",Vector2.ONE,0.55).set_trans(Tween.TRANS_BACK)
	t.tween_property(by_label,"modulate:a",1.0,0.55).set_delay(0.30)

	await t.finished

	var t2 := create_tween()
	t2.tween_property($LoadSection,"modulate:a",1.0,0.40)
	t2.tween_callback(_start_load)


func _start_load():

	ResourceLoader.load_threaded_request(NEXT_SCENE)

	_loading = true


func _process(delta):

	_update_loading(delta)
	_rotate_loading_text(delta)


func _update_loading(delta):

	if !_loading:
		return

	var status = ResourceLoader.load_threaded_get_status(NEXT_SCENE,_progress)

	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:

		var p = _progress[0] * 100

		progress_bar.value = lerp(progress_bar.value,p,delta*8)
		percent_label.text = "%d%%" % int(progress_bar.value)

	elif status == ResourceLoader.THREAD_LOAD_LOADED:

		_loading = false
		progress_bar.value = 100
		percent_label.text = "100%"
		_done = true

		await get_tree().create_timer(0.4).timeout
		_fade_out()


func _fade_out():
	# 1. On utilise le Singleton global qui NE SERA PAS détruit au changement de scène
	await Transition.fade_out()

	# 2. On récupère la scène chargée
	var scene = ResourceLoader.load_threaded_get(NEXT_SCENE)
	
	# 3. On change la scène
	get_tree().change_scene_to_packed(scene)
	
	# 4. On demande au Singleton de refaire apparaître l'écran
	Transition.fade_in()

func _rotate_loading_text(delta):

	if _done:
		return

	_text_timer += delta

	if _text_timer >= TEXT_INTERVAL and progress_bar.value < 96:

		_text_timer = 0
		_text_idx = (_text_idx + 1) % LOADING_TEXTS.size()
		loading_label.text = LOADING_TEXTS[_text_idx]
