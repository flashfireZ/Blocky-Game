extends Control

signal pseudo_confirmed(pseudo: String)

const MIN_LEN : int = 3
const MAX_LEN : int = 16

# Couleurs Palette
const COL_SUCCESS = Color(0.0, 1.0, 0.5)
const COL_ERROR   = Color(1.0, 0.3, 0.3)
const COL_NEUTRAL = Color(0.42, 0.42, 0.6)

@onready var main_panel  : PanelContainer = $Center/MainPanel
@onready var input       : LineEdit       = $Center/MainPanel/Margin/VBox/PseudoInput
@onready var confirm_btn : Button         = $Center/MainPanel/Margin/VBox/ConfirmBtn
@onready var status_lbl  : Label          = $Center/MainPanel/Margin/VBox/StatusLabel

var _player_id : String = ""
var _checking  : bool   = false

func _ready():
	confirm_btn.pressed.connect(_on_confirm_pressed)
	input.text_submitted.connect(func(_t): _on_confirm_pressed())
	
	# Initialisation visuelle
	status_lbl.text = ""
	_animate_entrance()
	input.grab_focus()

func setup(player_id: String):
	_player_id = player_id

# ── Animations ──────────────────────────────────────────────────────────────

func _animate_entrance():
	main_panel.scale = Vector2.ZERO
	main_panel.pivot_offset = main_panel.custom_minimum_size / 2
	var t = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(main_panel, "scale", Vector2.ONE, 0.5)

func _shake_ui():
	var t = create_tween().set_loops(4)
	var original_pos = main_panel.position
	t.tween_property(main_panel, "position:x", original_pos.x + 10, 0.05)
	t.tween_property(main_panel, "position:x", original_pos.x - 10, 0.05)
	t.chain().tween_property(main_panel, "position:x", original_pos.x, 0.05)

# ── Logique Métier (Inchangée mais visuellement liée) ───────────────────────

func _on_confirm_pressed():
	if _checking: return

	var pseudo : String = input.text.strip_edges()

	if pseudo.length() < MIN_LEN:
		_set_status("C'est trop court ! (min %d)" % MIN_LEN, false)
		_shake_ui()
		return
	if pseudo.length() > MAX_LEN:
		_set_status("C'est trop long ! (max %d)" % MAX_LEN, false)
		_shake_ui()
		return
	
	if not _is_valid_pseudo(pseudo):
		_set_status("Lettres, chiffres et _ uniquement.", false)
		_shake_ui()
		return

	_start_check(pseudo)

func _is_valid_pseudo(s: String) -> bool:
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	return regex.search(s) != null

func _start_check(pseudo: String):
	_checking = true
	_set_status("Vérification en cours...", true, true)
	confirm_btn.disabled = true

	var key : String = pseudo.to_lower()

	FirebaseManager.fb_get("/pseudos/%s.json" % key, func(data):
		if data == null or (typeof(data) == TYPE_BOOL and data == false):
			_claim_pseudo(pseudo, key)
			return

		if typeof(data) == TYPE_DICTIONARY:
			var owner_id : String = data.get("id", "")
			if owner_id == _player_id:
				_confirm_success(pseudo)
				return

			_set_status("Désolé, ce pseudo est déjà pris !", false)
			_shake_ui()
			_reset_ui()
			return

		_set_status("Erreur de connexion...", false)
		_reset_ui()
	)

func _claim_pseudo(pseudo: String, key: String):
	var payload = JSON.stringify({"id": _player_id, "pseudo": pseudo})
	FirebaseManager.fb_patch("/pseudos/%s.json" % key, payload)

	await get_tree().create_timer(0.4).timeout

	FirebaseManager.fb_get("/pseudos/%s.json" % key, func(data):
		if typeof(data) == TYPE_DICTIONARY and data.get("id", "") == _player_id:
			_confirm_success(pseudo)
		else:
			_set_status("Zut ! Quelqu'un l'a pris juste avant.", false)
			_shake_ui()
			_reset_ui()
	)

func _confirm_success(pseudo: String):
	# Sauvegarde locale
	var config = ConfigFile.new()
	config.load("user://player.cfg")
	config.set_value("player", "pseudo", pseudo)
	config.save("user://player.cfg")

	# Update Leaderboard
	var lb_payload = JSON.stringify({"pseudo": pseudo, "trophies": 0})
	FirebaseManager.fb_patch("/leaderboard/%s.json" % _player_id, lb_payload)

	_set_status("Parfait, bienvenue " + pseudo + " !", true)
	
	# Animation de sortie
	var t = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	t.tween_property(main_panel, "scale", Vector2.ZERO, 0.4).set_delay(0.5)
	await t.finished
	
	pseudo_confirmed.emit(pseudo)
	queue_free()

func _set_status(msg: String, ok: bool, pulse: bool = false):
	status_lbl.text = msg
	status_lbl.modulate = COL_SUCCESS if ok else COL_ERROR
	
	if pulse:
		var t = create_tween().set_loops()
		t.tween_property(status_lbl, "modulate:a", 0.4, 0.5)
		t.tween_property(status_lbl, "modulate:a", 1.0, 0.5)

func _reset_ui():
	_checking = false
	confirm_btn.disabled = false
	input.grab_focus()
