extends Node
class_name StateMachine 

enum GameState{
	MENU,
	LOBBY,
	IN_GAME,
	GAME_OVER
}

signal state_changed(old_state: GameState, new_state: GameState)
signal state_entered(state: GameState)
signal state_exited(state: GameState)

@export var initial_state: GameState = GameState.MENU
@export var pause_on_game_over := true

var current_state: GameState
var game_manager: GameManager

func _ready() -> void:
	current_state = initial_state
	_connect_game_manager()
	_enter_state(current_state)

func _connect_game_manager() -> void:
	if get_parent() is GameManager:
		game_manager = get_parent()
		game_manager.game_started.connect(_on_game_started)
		game_manager.game_ended.connect(_on_game_ended)

func _enter_state(state: GameState) -> void:
	match state:
		GameState.MENU:
			print("Entering MENU state")
			get_tree().paused = false
			if is_node_ready():
				get_tree().call_deferred("change_scene_to_file", "res://Assets/Scenes/main_menu.tscn")
		GameState.LOBBY:
			print("Entering LOBBY state")
			get_tree().paused = false
			if is_node_ready():
				get_tree().call_deferred("change_scene_to_file", "res://Assets/Scenes/lobby.tscn")
		GameState.IN_GAME:
			print("Entering IN_GAME state")
			get_tree().paused = false 
			# Since we're loading the game scene for testing, we don't have to change the scene here.
			# Remove once testing of the game flow is complete.
			#if is_node_ready():
				#get_tree().call_deferred("change_scene_to_file", "res://Assets/Scenes/game.tscn")
		GameState.GAME_OVER:
			print("Entering GAME_OVER state")
			if pause_on_game_over:
				get_tree().paused = true
	
	state_entered.emit(state)

func _exit_state(state: GameState) -> void:
	match state:
		GameState.MENU:
			print("Exiting MENU state")
		GameState.LOBBY:
			print("Exiting LOBBY state")
		GameState.IN_GAME:
			print("Exiting IN_GAME state")
		GameState.GAME_OVER:
			print("Exiting GAME_OVER state")
			get_tree().paused = false
	
	state_exited.emit(state)

func change_state(new_state: GameState) -> void:
	if new_state == current_state:
		return
	
	var old_state = current_state
	print("Transitioning from %s to %s" % [GameState.keys()[old_state], GameState.keys()[new_state]])
	
	_exit_state(current_state)
	current_state = new_state
	_enter_state(current_state)
	
	state_changed.emit(old_state, new_state)

func _on_game_started() -> void:
	if current_state != GameState.IN_GAME:
		change_state(GameState.IN_GAME)

func _on_game_ended() -> void:
	if current_state == GameState.IN_GAME:
		change_state(GameState.GAME_OVER)

func start_game() -> void:
	change_state(GameState.IN_GAME)

func return_to_menu() -> void:
	change_state(GameState.MENU)

func restart_game() -> void:
	if game_manager:
		get_tree().reload_current_scene()
	else:
		change_state(GameState.IN_GAME)

func get_current_state() -> GameState:
	return current_state

func is_in_state(state: GameState) -> bool:
	return current_state == state
