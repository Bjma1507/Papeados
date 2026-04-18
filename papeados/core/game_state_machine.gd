extends Node
class_name GameStateMachine

enum GameState {
	WAITING,
	STARTING,
	IN_ROUND,
	ROUND_OVER,
	GAME_OVER
}

signal state_changed(old_state: GameState, new_state: GameState)
signal state_entered(state: GameState)
signal state_exited(state: GameState)

@export var initial_state: GameState = GameState.WAITING
@export var round_start_delay: float = 3.0

var current_state: GameState
var _game_manager: GameManager

func _ready() -> void:
	current_state = initial_state
	_game_manager = get_parent() as GameManager
	if not _game_manager:
		push_error("[GameStateMachine] No se encontró GameManager como padre.")

func setup(game_manager: GameManager) -> void:
	_game_manager = game_manager
	_enter_state(current_state)

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return

	var old_state = current_state
	print("[GameStateMachine] %s → %s" % [
		GameState.keys()[old_state],
		GameState.keys()[new_state]
	])

	_exit_state(current_state)
	current_state = new_state
	_enter_state(new_state)

	state_changed.emit(old_state, new_state)

func _enter_state(state: GameState) -> void:
	match state:
		GameState.WAITING:
			pass
		GameState.STARTING:
			pass
		GameState.IN_ROUND:
			pass
		GameState.ROUND_OVER:
			pass
		GameState.GAME_OVER:
			pass

	state_entered.emit(state)


func _exit_state(state: GameState) -> void:
	match state:
		GameState.WAITING:
			pass
		GameState.STARTING:
			pass
		GameState.IN_ROUND:
			pass
		GameState.ROUND_OVER:
			pass
		GameState.GAME_OVER:
			pass

	state_exited.emit(state)

func is_in_state(state: GameState) -> bool:
	return current_state == state

func get_current_state() -> GameState:
	return current_state

func on_game_started() -> void:
	change_state(GameState.STARTING)

func on_round_started() -> void:
	change_state(GameState.IN_ROUND)

func on_round_ended() -> void:
	change_state(GameState.ROUND_OVER)

func on_game_over() -> void:
	change_state(GameState.GAME_OVER)

func on_restart() -> void:
	change_state(GameState.WAITING)
