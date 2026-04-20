extends Node
class_name GameManager

# Signals
signal game_started
signal game_ended

# Modules
@onready var player_manager: PlayerManager = $PlayerManager
@onready var potato_manager: PotatoManager = $PotatoManager
@onready var round_manager: RoundManager = $RoundManager
@onready var score_manager: ScoreManager = $ScoreManager

# Game state machine
@onready var state_machine: GameStateMachine = $StateMachine

# Initialization
func _ready() -> void:
	if multiplayer.is_server():
		_initialize_server()
	else:
		_initialize_client()

'''
Initializes the game state on the server, sets up signal connections, and starts the first round.
'''
func _initialize_server() -> void:
	print("[GameManager] === Inicializando SERVIDOR ===")
 
	_connect_signals()
 
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	state_machine.setup(self)

	player_manager.spawn_player(1)
	score_manager.initialize(player_manager.get_all_peer_ids())

	state_machine.on_game_started()
	round_manager.start_round(player_manager)
 
	game_started.emit()


'''
Initializes the client state and requests the current game state from the server.
'''
func _initialize_client() -> void:
	print("[GameManager] === Inicializando CLIENTE ===")
	state_machine.setup(self)
	call_deferred("_request_game_state")

'''
Helper method to connect signals from the PotatoManager and RoundManager to the GameManager's handlers.
'''
func _connect_signals() -> void:
	potato_manager.players_affected_by_explosion.connect(_on_players_affected_by_explosion)
	
	round_manager.all_rounds_completed.connect(_on_all_rounds_completed)
	round_manager.round_ready_to_spawn.connect(_on_round_ready_to_spawn)
	
	round_manager.round_started.connect(_on_round_started)
	round_manager.round_ended.connect(_on_round_ended)
	
	state_machine.state_changed.connect(_on_state_changed)
	
func _on_state_changed(_old_state: GameStateMachine.GameState, new_state: GameStateMachine.GameState) -> void:
	if multiplayer.is_server():
		_sync_state.rpc(new_state)

@rpc("authority", "reliable")
func _sync_state(new_state: GameStateMachine.GameState) -> void:
	if multiplayer.is_server():
		return
	state_machine.change_state(new_state)
  
func _on_round_started(_round_number: int, _rounds_to_win: int) -> void:
	state_machine.on_round_started()
 
func _on_round_ended(_survivor: int) -> void:
	state_machine.on_round_ended()

func _request_game_state() -> void:
	_client_ready_rpc.rpc_id(1)

@rpc("any_peer", "reliable")
func _client_ready_rpc() -> void:
	if not multiplayer.is_server():
		return
 
	var new_peer_id = multiplayer.get_remote_sender_id()
	print("[GameManager] Cliente %d listo en escena." % new_peer_id)
 
	for existing_id in player_manager.get_all_peer_ids():
		player_manager._spawn_player_on_clients.rpc_id(
			new_peer_id, existing_id, player_manager.get_player_position(existing_id)
		)
 
	player_manager.spawn_player(new_peer_id)
	score_manager.register_player(new_peer_id)
 
	_sync_state.rpc_id(new_peer_id, state_machine.get_current_state())

func _on_peer_connected(peer_id: int) -> void:
	print("[GameManager] Nuevo jugador conectado: %d" % peer_id)
	await get_tree().process_frame
	player_manager.spawn_player(peer_id)
	score_manager.register_player(peer_id)

	# Informar al nuevo cliente de los jugadores ya existentes
	for existing_id in player_manager.get_all_peer_ids():
		if existing_id != peer_id:
			player_manager._spawn_player_on_clients.rpc_id(
				peer_id, existing_id, player_manager.get_player_position(existing_id)
			)

func _on_peer_disconnected(peer_id: int) -> void:
	print("[GameManager] Jugador desconectado: %d" % peer_id)

	var player = player_manager.get_player(peer_id)
	var had_potato = player != null and potato_manager.player_has_potato(player)

	player_manager.remove_player(peer_id)
	score_manager.remove_player(peer_id)

	if had_potato:
		await get_tree().create_timer(1.0).timeout
		var target = player_manager.get_random_alive_player()
		if target:
			potato_manager.spawn_potato_on_player(target, player_manager)

func _on_players_affected_by_explosion(affected_peer_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
 
	print("[GameManager] Procesando explosión. Afectados: %s" % str(affected_peer_ids))
 
	for peer_id in affected_peer_ids:
		round_manager.register_death(peer_id, player_manager)
 
	for peer_id in player_manager.get_alive_peer_ids():
		score_manager.add_score(peer_id) 

	_handle_explosion_on_clients.rpc(affected_peer_ids)
 
	await get_tree().create_timer(1.0).timeout
	round_manager.check_round_end(player_manager, score_manager, potato_manager)

@rpc("authority", "reliable", "call_local")
func _handle_explosion_on_clients(affected_peer_ids: Array[int]) -> void:
	for peer_id in affected_peer_ids:
		var player = player_manager.get_player(peer_id)
		if not is_instance_valid(player):
			continue

		# Texto flotante
		if potato_manager.floating_text_scene:
			var text = potato_manager.floating_text_scene.instantiate()
			text.global_position = player.global_position + Vector2(0, -40)
			add_child(text)
			text._create_text("PAPEADO")

		player_manager.remove_player(peer_id)

func _on_all_rounds_completed(winner_peer_id: int) -> void:
	print("[GameManager] ¡JUEGO TERMINADO! Ganador: Jugador %d con %d puntos" % [
		winner_peer_id, score_manager.get_score(winner_peer_id)
	])

	potato_manager.stop_all_potatoes()
	state_machine.on_game_over()
	_announce_winner.rpc(winner_peer_id, score_manager.get_score(winner_peer_id))

func _on_round_ready_to_spawn() -> void:
	if not multiplayer.is_server():
		return
 
	var target = player_manager.get_random_alive_player()
	if target:
		potato_manager.spawn_potato_on_player(target, player_manager)
		potato_manager.start_spawn_timer()
	else:
		push_warning("[GameManager] No hay jugadores vivos al intentar spawnear papa.")

@rpc("authority", "reliable", "call_local")
func _announce_winner(winner_peer_id: int, final_score: int) -> void:
	print("[GameManager] ¡El ganador es Jugador %d con %d puntos!" % [winner_peer_id, final_score])
	game_ended.emit()

func request_restart() -> void:
	if not multiplayer.is_server():
		_request_restart_rpc.rpc_id(1)
	else:
		_do_restart()
 
 
@rpc("any_peer", "reliable")
func _request_restart_rpc() -> void:
	if not multiplayer.is_server():
		return
	_do_restart()
 
 
func _do_restart() -> void:
	print("[GameManager] Reiniciando partida...")

	potato_manager.stop_all_potatoes()

	round_manager.round_number = 0
	round_manager.round_in_progress = false
	round_manager.players_dead_this_round.clear()

	_restart_on_clients.rpc()

	await get_tree().process_frame

	for peer_id in player_manager.get_all_peer_ids():
		player_manager.remove_player(peer_id)

	await get_tree().process_frame

	for peer_id in multiplayer.get_peers():
		player_manager.spawn_player(peer_id)

	player_manager.spawn_player(1)

	score_manager.initialize(player_manager.get_all_peer_ids())
	
	state_machine.on_game_started()
	round_manager.start_round(player_manager)

@rpc("authority", "reliable", "call_local")
func _restart_on_clients() -> void:
	print("[GameManager] Reinicio recibido en cliente")

	potato_manager.stop_all_potatoes()

	round_manager.round_number = 0
	round_manager.round_in_progress = false
	round_manager.players_dead_this_round.clear()

	for peer_id in player_manager.get_all_peer_ids():
		player_manager.remove_player(peer_id)

	score_manager.initialize([])

	state_machine.on_game_started()

func _sync_players_to_all():
	for target_peer in multiplayer.get_peers():
		for existing_id in player_manager.get_all_peer_ids():
			player_manager._spawn_player_on_clients.rpc_id(
				target_peer,
				existing_id,
				player_manager.get_player_position(existing_id)
			)

func get_player_with_potato() -> Player:
	return potato_manager.get_player_with_potato()

func get_player_by_id(peer_id: int) -> Player:
	return player_manager.get_player(peer_id)

func transfer_potato_network(from_player: Player, to_player: Player) -> void:
	potato_manager.transfer_potato(from_player, to_player, player_manager)

func _spawn_first_potato() -> void:
	await get_tree().create_timer(1.0).timeout
	var target = player_manager.get_random_alive_player()
	if target:
		potato_manager.spawn_potato_on_player(target, player_manager)
	potato_manager.start_spawn_timer()
