# pseudo_popup.gd
# À attacher sur un nœud CanvasLayer ou Control nommé "PseudoPopup"
# Structure de scène attendue :
#   PseudoPopup (Control)
#     └─ Panel
#          ├─ TitleLabel
#          ├─ PseudoInput   (LineEdit)
#          ├─ ConfirmBtn    (Button)
#          ├─ StatusLabel   (Label)
#          └─ LoadingSpinner (optionnel, AnimatedSprite2D ou simple Label)
extends Control

signal pseudo_confirmed(pseudo: String)

const MIN_LEN : int = 3
const MAX_LEN : int = 16

@onready var input         : LineEdit = $Panel/PseudoInput
@onready var confirm_btn   : Button   = $Panel/ConfirmBtn
@onready var status_lbl    : Label    = $Panel/StatusLabel

var _player_id : String = ""
var _checking  : bool   = false

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	confirm_btn.pressed.connect(_on_confirm_pressed)
	input.text_submitted.connect(func(_t): _on_confirm_pressed())
	input.grab_focus()

func setup(player_id: String):
	_player_id = player_id

# ══════════════════════════════════════════════════════════════════════════════
#  VALIDATION LOCALE
# ══════════════════════════════════════════════════════════════════════════════
func _on_confirm_pressed():
	if _checking: return

	var raw    : String = input.text.strip_edges()
	var pseudo : String = raw

	# Contraintes
	if pseudo.length() < MIN_LEN:
		_set_status("Au moins %d caractères." % MIN_LEN, false)
		return
	if pseudo.length() > MAX_LEN:
		_set_status("Maximum %d caractères." % MAX_LEN, false)
		return
	if not pseudo.is_valid_identifier() and not _is_valid_pseudo(pseudo):
		_set_status("Lettres, chiffres et _ uniquement.", false)
		return

	_start_check(pseudo)

func _is_valid_pseudo(s: String) -> bool:
	for c in s:
		if not (c.is_valid_identifier() or c == "_"):
			return false
	return true

# ══════════════════════════════════════════════════════════════════════════════
#  VÉRIFICATION FIREBASE
# ══════════════════════════════════════════════════════════════════════════════
func _start_check(pseudo: String):
	_checking = true
	_set_status("Vérification...", true)
	confirm_btn.disabled = true

	var key : String = pseudo.to_lower()   # insensible à la casse

	FirebaseManager.fb_get("/pseudos/%s.json" % key, func(data):
		if data == null or (typeof(data) == TYPE_BOOL and data == false):
			# Pseudo libre → tenter le claim
			_claim_pseudo(pseudo, key)
			return

		if typeof(data) == TYPE_DICTIONARY:
			var owner_id : String = data.get("id", "")

			if owner_id == _player_id:
				# C'est notre pseudo sur un autre appareil → OK directement
				_confirm_success(pseudo)
				return

			# Pseudo pris par quelqu'un d'autre
			_set_status("Pseudo déjà pris, choisis-en un autre.", false)
			_reset_ui()
			return

		_set_status("Erreur réseau, réessaie.", false)
		_reset_ui()
	)

# ── Pattern claim anti race-condition ────────────────────────────────────────
# Même logique que le matchmaking : écrire, attendre, relire.
func _claim_pseudo(pseudo: String, key: String):
	var payload = JSON.stringify({"id": _player_id, "pseudo": pseudo})
	FirebaseManager.fb_patch("/pseudos/%s.json" % key, payload)

	await get_tree().create_timer(0.4).timeout

	FirebaseManager.fb_get("/pseudos/%s.json" % key, func(data):
		if typeof(data) != TYPE_DICTIONARY:
			_set_status("Erreur réseau, réessaie.", false)
			_reset_ui()
			return

		if data.get("id", "") != _player_id:
			# Quelqu'un d'autre a claimé pendant les 400ms
			_set_status("Pseudo déjà pris, choisis-en un autre.", false)
			_reset_ui()
			return

		# Claim confirmé
		_confirm_success(pseudo)
	)

# ══════════════════════════════════════════════════════════════════════════════
#  SUCCÈS
# ══════════════════════════════════════════════════════════════════════════════
func _confirm_success(pseudo: String):
	# 1. Sauvegarder localement
	var config = ConfigFile.new()
	config.load("user://player.cfg")
	config.set_value("player", "pseudo", pseudo)
	config.save("user://player.cfg")

	# 2. Créer/mettre à jour l'entrée leaderboard
	var lb_payload = JSON.stringify({
		"pseudo":   pseudo,
		"trophies": 0        # sera ignoré si l'entrée existe déjà (PATCH = merge)
	})
	FirebaseManager.fb_patch("/leaderboard/%s.json" % _player_id, lb_payload)

	print("[Pseudo] Enregistré : ", pseudo)
	_set_status("Bienvenue, %s !" % pseudo, true)

	await get_tree().create_timer(0.6).timeout
	pseudo_confirmed.emit(pseudo)
	queue_free()

# ══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ══════════════════════════════════════════════════════════════════════════════
func _set_status(msg: String, ok: bool):
	status_lbl.text = msg
	status_lbl.modulate = Color.GREEN if ok else Color.RED

func _reset_ui():
	_checking            = false
	confirm_btn.disabled = false
	input.grab_focus()
