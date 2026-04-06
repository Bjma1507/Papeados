extends Node
class_name GameStateMachine


# Game flow states

enum GameState{
	WAITING,
	STARTING,
	IN_ROUND,
	ROUND_OVER,
	GAME_OVER
}

# Signals for state changes

signal state_changed(old_state: GameState, new_state: GameState)
signal state_entered(state: GameState)
signal state_exited(state: GameState)


# Exported variables for configuration

@export var initial_state: GameState = GameState.WAITING
@export var round_start_delay: float = 3.0
@export var game_manager_path: NodePath


# Internal variables

var current_state: GameState
var game_manager: GameManager



func _ready() -> void:
	current_state = initial_state
	game_manager = get_node_or_null(game_manager_path)
