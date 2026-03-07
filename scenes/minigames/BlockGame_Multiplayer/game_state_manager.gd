# game_state_manager.gd — Timer et gestion des tours
# Compatible Godot 4.x
extends Node

enum TurnPhase  { PLAYER_TURN, OPPONENT_TURN, RESOLVING }
enum TimerPhase { NORMAL, LAST_MINUTE }

signal turn_changed(phase)
signal timer_tick(seconds_left: int)
signal phase_changed(new_phase)

const GAME_DURATION          : float = 180.0   # 3 minutes max
const LAST_MINUTE            : float = 60.0
const LAST_MINUTE_MULTIPLIER : float = 2.0
const PIECES_PER_TURN        : int   = 1

var current_phase : int   = TurnPhase.PLAYER_TURN
var timer_phase   : int   = TimerPhase.NORMAL
var time_left     : float = GAME_DURATION
var _timer_ended  : bool  = false              # ← Verrou pour éviter le double-déclenchement

var pieces_placed_this_turn : int = 0

var _grid : Node = null

# ══════════════════════════════════════════════════════════════════════════════
func _ready():
	_grid = get_tree().root.find_child("GridMultiplayer", true, false)

func _process(delta):
	if current_phase == TurnPhase.RESOLVING: return
	if _timer_ended: return

	time_left -= delta
	emit_signal("timer_tick", int(time_left))

	if time_left <= LAST_MINUTE and timer_phase == TimerPhase.NORMAL:
		timer_phase = TimerPhase.LAST_MINUTE
		emit_signal("phase_changed", timer_phase)
		print("⚠️  DERNIÈRE MINUTE — dégâts x2 !")

	if time_left <= 0.0:
		_timer_ended = true
		_end_game_by_timer()

func get_damage_multiplier() -> float:
	return LAST_MINUTE_MULTIPLIER if timer_phase == TimerPhase.LAST_MINUTE else 1.0

func on_piece_placed():
	pieces_placed_this_turn += 1
	if pieces_placed_this_turn >= PIECES_PER_TURN:
		_end_turn()

func _end_turn():
	pieces_placed_this_turn = 0
	if current_phase == TurnPhase.PLAYER_TURN:
		current_phase = TurnPhase.OPPONENT_TURN
	else:
		current_phase = TurnPhase.PLAYER_TURN
	emit_signal("turn_changed", current_phase)

func is_player_turn() -> bool:
	return current_phase == TurnPhase.PLAYER_TURN

## Appelé par _on_game_finished dans MainBlockGame pour stopper le timer
## proprement depuis l'extérieur (ex : fin par HP, forfait, quit).
func stop_timer():
	_timer_ended = true

func _end_game_by_timer():
	if not _grid: return
	print("[GameState] Temps écoulé — fin de partie par timer")

	# Passe par FirebaseManager pour déclarer le vainqueur de façon cohérente
	# entre les deux clients (HP local comparés, résultat écrit sur Firebase).
	var fm = get_tree().root.get_node_or_null("FirebaseManager")
	if fm and fm.has_method("declare_winner_by_hp"):
		fm.declare_winner_by_hp(_grid.player_hp, _grid.opponent_hp)
	else:
		# Fallback sans Firebase (mode solo / test)
		var winner = "player" if _grid.player_hp > _grid.opponent_hp else "opponent"
		_grid.emit_signal("game_over", winner)
