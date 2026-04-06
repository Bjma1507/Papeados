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

# Initialization
func _ready() -> void:
	if multiplayer.is_server():
		_initialize_server()
	else:
		_initialize_client()

'''
Initializes the game state on the server, sets up signal connections, and starts the first round.
This is called in the _ready function if the instance is running as a server. 
It connects necessary signals, spawns the host player, initializes the score manager, starts the first round, and spawns the first potato.
'''
func _initialize_server() -> void:
	print("[GameManager] === Inicializando SERVIDOR ===")

	_connect_signals()

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Host spawn
	player_manager.spawn_player(1)

	score_manager.initialize(player_manager.get_all_peer_ids())
	round_manager.start_round(player_manager)

	game_started.emit()



'''
Initializes the client state and requests the current game state from the server.
This is called in the _ready function if the instance is running as a client.
It connects necessary signals and sends an RPC to the server to 
indicate that the client is ready to receive the current game state, including existing players and the active potato.
'''
func _initialize_client() -> void:
	print("[GameManager] === Inicializando CLIENTE ===")
	call_deferred("_request_game_state")

'''
Helper method to connect signals from the PotatoManager and RoundManager to the GameManager's handlers.
'''
func _connect_signals() -> void:
	potato_manager.players_affected_by_explosion.connect(_on_players_affected_by_explosion)
	round_manager.all_rounds_completed.connect(_on_all_rounds_completed)
	round_manager.round_ready_to_spawn.connect(_on_round_ready_to_spawn)

func _request_game_state() -> void:
	_client_ready_rpc.rpc_id(1)

'''
This is called by the client to notify the server that it is ready to receive the current game state. 
Only runs on the server. 
After receiving this RPC, the server will send the current game state to the new client, 
including existing players and the active potato if there is one.
'''
@rpc("any_peer", "reliable")
func _client_ready_rpc() -> void:
	if not multiplayer.is_server():
		return

	var peer_id = multiplayer.get_remote_sender_id()
	print("[GameManager] Cliente %d listo." % peer_id)

	for existing_id in player_manager.get_all_peer_ids():
		player_manager._spawn_player_on_clients.rpc_id(
			peer_id, existing_id, player_manager.get_player_position(existing_id)
		)

	if not potato_manager.has_active_potato():
		await get_tree().create_timer(2.0).timeout
		var target = player_manager.get_random_alive_player()
		if target:
			potato_manager.spawn_potato_on_player(target, player_manager)


'''
Connects a new player to the game by spawning their player instance and registering them in the score manager.
This is called by the server when a new player connects to the game. 
It spawns the new player's character, registers them in the score manager, and informs the new client of all existing players so they can be displayed correctly.

Args:
	peer_id (int): The network peer ID of the newly connected player.
'''
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

'''
Unregisters a player from the game when they disconnect by removing their player instance and score entry.
This is called by the server when a player disconnects from the game. 
It removes the player's character, unregisters them from the score manager,
and if they had the potato, it spawns a new potato on a random alive player after a short delay to keep the game flowing.

Args:
	peer_id (int): The network peer ID of the disconnected player.
'''
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

'''
Handles the explosion event by marking affected players as dead, 
awarding points to survivors, and checking for round end conditions.

Args:
	affected_peer_ids (Array[int]): An array of network peer IDs of the players affected by the explosion.
'''
func _on_players_affected_by_explosion(affected_peer_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return

	print("[GameManager] Procesando explosión. Afectados: %s" % str(affected_peer_ids))

	_handle_explosion_on_clients.rpc(affected_peer_ids)

	for peer_id in affected_peer_ids:
		round_manager.register_death(peer_id, player_manager)

	for peer_id in player_manager.get_alive_peer_ids():
		score_manager.add_score(peer_id)

	await get_tree().create_timer(1.0).timeout
	round_manager.check_round_end(player_manager, score_manager, potato_manager)


'''
Also handles the explosion event, but on client-side by showing floating text and removing affected players.
This is called by the server after processing an explosion to update all clients with the affected players,
show floating text, and remove the affected players from the game.

Args:
	affected_peer_ids (Array[int]): An array of network peer IDs of the players affected by the explosion.
'''
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

		player_manager.remove_player(peer_id)


'''
Finishes the game when a player wins by announcing the winner and stopping all game activity.
This is called by the RoundManager when a player reaches the required points to win the game.
It announces the winner to all clients and emits the game_ended signal to trigger any end-ofgame logic or UI.

Args:
	winner_peer_id (int): The network peer ID of the winning player.
'''
func _on_all_rounds_completed(winner_peer_id: int) -> void:
	print("[GameManager] ¡JUEGO TERMINADO! Ganador: Jugador %d con %d puntos" % [
		winner_peer_id, score_manager.get_score(winner_peer_id)
	])

	potato_manager.stop_all_potatoes()

	_announce_winner.rpc(winner_peer_id, score_manager.get_score(winner_peer_id))


'''
Handles the event when the round is ready to spawn a new potato.
This is called by the RoundManager when a new round starts and it's time to spawn the first potato.
It selects a random alive player and spawns a potato on them to kick off the round.
'''
func _on_round_ready_to_spawn() -> void:
	if not multiplayer.is_server():
		return
 
	var target = player_manager.get_random_alive_player()
	if target:
		potato_manager.spawn_potato_on_player(target, player_manager)
		potato_manager.start_spawn_timer()
	else:
		push_warning("[GameManager] No hay jugadores vivos al intentar spawnear papa.")

'''
RPC function to announce the winner of the game on all clients.
This is called by the server when the game ends to notify all clients of the winner and their final score.

args:
	winner_peer_id (int): The network peer ID of the winning player.
	final_score (int): The final score of the winning player to display in the announcement.
'''
@rpc("authority", "reliable", "call_local")
func _announce_winner(winner_peer_id: int, final_score: int) -> void:
	print("[GameManager] ¡El ganador es Jugador %d con %d puntos!" % [winner_peer_id, final_score])
	game_ended.emit()


'''
Helper methods to get player instances, transfer the potato, and other game-related queries.
'''
func get_player_with_potato() -> Player:
	return potato_manager.get_player_with_potato()

func get_player_by_id(peer_id: int) -> Player:
	return player_manager.get_player(peer_id)

func transfer_potato_network(from_player: Player, to_player: Player) -> void:
	potato_manager.transfer_potato(from_player, to_player, player_manager)



'''
Helper method to spawn the first potato at the beginning of the game on a random alive player.
'''
func _spawn_first_potato() -> void:
	await get_tree().create_timer(1.0).timeout
	var target = player_manager.get_random_alive_player()
	if target:
		potato_manager.spawn_potato_on_player(target, player_manager)
	potato_manager.start_spawn_timer()
