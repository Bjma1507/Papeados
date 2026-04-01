extends Node
class_name GameManager

signal game_started
signal game_ended
signal player_spawned(player: Player)
signal potato_spawned(potato: ExplosivePotato)

@export var player_scene: PackedScene
@export var explosive_potato_scene: PackedScene
@export var spawn_positions: Array[Vector2] = [Vector2(-200, 0), Vector2(200, 0)]
@export var floating_text_scene: PackedScene

@export_group("Potato Settings")
@export var potato_spawn_interval := 15.0
@export var potato_auto_spawn := true
@export var potato_spawn_on_ready := true
@export var potato_attach_delay := 1.0

var players: Array[Player] = []
var active_potatoes: Array[ExplosivePotato] = []
var potato_spawn_timer: Timer
var potato_attach_timer: Timer
var state_machine: StateMachine

func _ready() -> void:
	_initialize()

func _initialize() -> void:

	state_machine = StateMachine.new()
	state_machine.initial_state = StateMachine.GameState.IN_GAME
	add_child(state_machine)

	potato_attach_timer = Timer.new()
	potato_attach_timer.wait_time = potato_attach_delay
	add_child(potato_attach_timer)

	_spawn_all_players()
	_setup_potato_spawner()
	
	if potato_spawn_on_ready:
		spawn_potato_on_random_player()

	game_started.emit()

func _spawn_all_players() -> void:
	for i in spawn_positions.size():
		var player = player_scene.instantiate()
		player.position = spawn_positions[i]
		player.player_id = i + 1
		add_child(player)
		players.append(player)
		player_spawned.emit(player)

func _setup_potato_spawner() -> void:
	if not potato_auto_spawn:
		return
	
	potato_spawn_timer = Timer.new()
	potato_spawn_timer.wait_time = potato_spawn_interval
	potato_spawn_timer.timeout.connect(_on_potato_timer_timeout)
	add_child(potato_spawn_timer)
	potato_spawn_timer.start()

func _on_potato_timer_timeout() -> void:
	spawn_potato_on_random_player()

func spawn_potato_on_random_player() -> ExplosivePotato:
	if players.is_empty():
		return null
	
	var target_player = players.pick_random()
	return spawn_potato_on_player(target_player)

func spawn_potato_on_player(player: Player) -> ExplosivePotato:
	if not explosive_potato_scene or not is_instance_valid(player):
		return null
	
	var potato: ExplosivePotato = explosive_potato_scene.instantiate()
	add_child(potato)
	potato.attach_to_player(player)
	potato.exploding.connect(_on_potato_exploding.bind(potato))
	active_potatoes.append(potato)
	potato_spawned.emit(potato)
	return potato

func attach_potato_to_player(potato: ExplosivePotato, player: Player) -> void:
	if not is_instance_valid(potato) or not is_instance_valid(player):
		return
	potato.attach_to_player(player)

func _on_potato_exploding(players_in_range: Array[Player], potato: ExplosivePotato) -> void:
	for p in players_in_range:
		if is_instance_valid(p):
			var text := floating_text_scene.instantiate()
			text.global_position = p.global_position + Vector2(0, -40)
			add_child(text)
			players.erase(p)
			p.queue_free()


	await potato.audio.finished	
	active_potatoes.erase(potato)

	if players.size() == 0:
		print("Tie game!")
		game_ended.emit()
	elif win_condition_met():
		_end_game()

func _end_game() -> void:
	print("Game Over! Player %d wins!" % players[0].player_id)
	
	potato_spawn_on_ready = false
	
	if potato_spawn_timer:
		potato_spawn_timer.stop()
	

	game_ended.emit()

func get_player_with_potato() -> Player:
	for potato in active_potatoes:
		if is_instance_valid(potato) and is_instance_valid(potato.attached_player):
			return potato.attached_player
	return null

func win_condition_met() -> bool:
	return players.size() == 1

func get_player_by_id(player_id: int) -> Player:
	for player in players:
		if player.player_id == player_id:
			return player
	return null

func get_player_count() -> int:
	return players.size()

func get_active_potato_count() -> int:
	return active_potatoes.size()
