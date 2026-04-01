extends Node


# ========================================
# SEÑALES
# ========================================
signal game_started
signal game_ended
signal player_spawned(player: Player)
signal potato_spawned(potato: ExplosivePotato)

# ========================================
# ESCENAS
# ========================================
@export var player_scene: PackedScene
@export var explosive_potato_scene: PackedScene
@export var floating_text_scene: PackedScene

# ========================================
# CONFIGURACIÓN DE SPAWN
# ========================================
@export var spawn_positions: Array[Vector2] = [
	Vector2(-200, 0), 
	Vector2(200, 0),
	Vector2(-200, -100),
	Vector2(200, -100)
]

# ========================================
# CONFIGURACIÓN DE PAPAS
# ========================================
@export_group("Potato Settings")
@export var potato_spawn_interval := 15.0
@export var potato_auto_spawn := true
@export var potato_spawn_on_ready := true
@export var potato_attach_delay := 1.0

# ========================================
# VARIABLES DE JUEGO
# ========================================
var players: Dictionary = {}  # peer_id -> Player
var active_potatoes: Array[ExplosivePotato] = []
var potato_spawn_timer: Timer
var potato_attach_timer: Timer
var state_machine: StateMachine

# Contador de spawn positions
var next_spawn_index := 0

# ========================================
# INICIALIZACIÓN
# ========================================
func _ready() -> void:
	# Solo el servidor inicializa el juego
	if multiplayer.is_server():
		_initialize_server()
	else:
		_initialize_client()

func _initialize_server() -> void:
	print("=== Inicializando GameManager en SERVIDOR ===")
	
	# Configurar state machine
	state_machine = StateMachine.new()
	state_machine.initial_state = StateMachine.GameState.IN_GAME
	add_child(state_machine)
	
	# Timer para adjuntar papas
	potato_attach_timer = Timer.new()
	potato_attach_timer.wait_time = potato_attach_delay
	add_child(potato_attach_timer)
	
	# Conectar señales de red
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	
	# Spawn del jugador del servidor
	_spawn_player_for_peer(1)
	
	# Configurar spawner de papas
	_setup_potato_spawner()
	
	# NO spawnear papa aquí - se spawneará cuando el segundo jugador llegue
	game_started.emit()

func _initialize_client() -> void:
	print("=== Inicializando GameManager en CLIENTE ===")
	# Avisar al servidor que estamos listos para recibir el estado
	call_deferred("_request_game_state")

func _request_game_state() -> void:
	_client_ready_rpc.rpc_id(1)

@rpc("any_peer", "reliable")
func _client_ready_rpc() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	print("Cliente %d listo, enviando jugadores existentes..." % peer_id)
	for existing_id in players:
		_spawn_player_on_clients.rpc_id(peer_id, existing_id, players[existing_id].global_position)
	# Esperar a que el cliente procese los jugadores y luego spawnear papa si hace falta
	if potato_spawn_on_ready and active_potatoes.is_empty():
		await get_tree().create_timer(2.0).timeout
		spawn_potato_on_random_player()

# ========================================
# CONEXIÓN DE JUGADORES
# ========================================
func _on_player_connected(peer_id: int) -> void:
	print("Nuevo jugador conectado: ", peer_id)
	
	# Esperar un frame para que la conexión se estabilice
	await get_tree().process_frame
	
	# Spawn del jugador para el nuevo peer
	_spawn_player_for_peer(peer_id)
	
	# Notificar a todos los clientes existentes sobre el nuevo jugador
	for existing_peer_id in players:
		if existing_peer_id != peer_id:
			_sync_player_to_client.rpc_id(peer_id, existing_peer_id, players[existing_peer_id].global_position)

func _on_player_disconnected(peer_id: int) -> void:
	print("Jugador desconectado: ", peer_id)
	
	# Remover jugador
	if players.has(peer_id):
		var player = players[peer_id]
		
		# Verificar si tenía la papa
		var had_potato = _player_has_potato(player)
		
		players.erase(peer_id)
		player.queue_free()
		
		# Notificar a todos los clientes
		_remove_player_from_clients.rpc(peer_id)
		
		# Si tenía la papa, spawnear una nueva
		if had_potato:
			await get_tree().create_timer(1.0).timeout
			spawn_potato_on_random_player()

# ========================================
# SPAWN DE JUGADORES
# ========================================
func _spawn_player_for_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return  # Solo el servidor puede spawnear
	
	if players.has(peer_id):
		print("El jugador %d ya existe" % peer_id)
		return
	
	print("Spawneando jugador para peer: ", peer_id)
	
	# Obtener posición de spawn
	var spawn_pos = spawn_positions[next_spawn_index % spawn_positions.size()]
	next_spawn_index += 1
	
	# Notificar a TODOS los clientes (incluido el nuevo) que spawnen el jugador
	_spawn_player_on_clients.rpc(peer_id, spawn_pos)
	
	# Spawnear en el servidor también
	_create_player_instance(peer_id, spawn_pos)

@rpc("authority", "reliable", "call_local")
func _spawn_player_on_clients(peer_id: int, spawn_pos: Vector2) -> void:
	_create_player_instance(peer_id, spawn_pos)

func _create_player_instance(peer_id: int, spawn_pos: Vector2) -> void:
	if players.has(peer_id):
		return  # Ya existe
	
	var player: Player = player_scene.instantiate()
	player.global_position = spawn_pos
	player.player_id = peer_id
	player.name = "Player_%d" % peer_id
	
	# Configurar autoridad de red
	player.set_multiplayer_authority(peer_id)
	
	add_child(player)
	players[peer_id] = player
	
	print("Jugador %d creado en posición %v" % [peer_id, spawn_pos])
	player_spawned.emit(player)

@rpc("authority", "reliable")
func _sync_player_to_client(peer_id: int, position: Vector2) -> void:
	if not players.has(peer_id):
		_create_player_instance(peer_id, position)

@rpc("authority", "reliable", "call_local")
func _remove_player_from_clients(peer_id: int) -> void:
	if players.has(peer_id):
		var player = players[peer_id]
		players.erase(peer_id)
		player.queue_free()

# ========================================
# SISTEMA DE PAPAS
# ========================================
func _setup_potato_spawner() -> void:
	if not potato_auto_spawn:
		return
	
	potato_spawn_timer = Timer.new()
	potato_spawn_timer.wait_time = potato_spawn_interval
	potato_spawn_timer.timeout.connect(_on_potato_timer_timeout)
	add_child(potato_spawn_timer)
	potato_spawn_timer.start()

func _on_potato_timer_timeout() -> void:
	if multiplayer.is_server():
		spawn_potato_on_random_player()

func spawn_potato_on_random_player() -> void:
	if not multiplayer.is_server():
		return  # Solo el servidor puede spawnear papas
	
	if players.is_empty():
		print("No hay jugadores para spawnear papa")
		return
	
	# Elegir jugador aleatorio
	var player_ids = players.keys()
	var random_peer_id = player_ids.pick_random()
	
	print("Spawneando papa en jugador: ", random_peer_id)
	
	# Notificar a todos los clientes
	_spawn_potato_on_clients.rpc(random_peer_id)

@rpc("authority", "reliable", "call_local")
func _spawn_potato_on_clients(target_peer_id: int) -> void:
	if not players.has(target_peer_id):
		print("Error: Jugador %d no existe para spawnear papa" % target_peer_id)
		return
	
	var target_player = players[target_peer_id]
	
	var potato: ExplosivePotato = explosive_potato_scene.instantiate()
	add_child(potato)
	potato.attach_to_player(target_player)
	potato.exploding.connect(_on_potato_exploding.bind(potato))
	active_potatoes.append(potato)
	
	print("Papa spawneada en jugador %d" % target_peer_id)
	potato_spawned.emit(potato)

# ========================================
# TRANSFERENCIA DE PAPA
# ========================================
func transfer_potato_network(from_player: Player, to_player: Player) -> void:
	if not multiplayer.is_server():
		return  # Solo el servidor puede transferir
	
	# Buscar la papa activa
	for potato in active_potatoes:
		if is_instance_valid(potato) and potato.attached_player == from_player:
			print("Transfiriendo papa de %d a %d" % [from_player.player_id, to_player.player_id])
			
			# Notificar a todos los clientes
			_transfer_potato_on_clients.rpc(
				players.find_key(from_player),
				players.find_key(to_player)
			)
			return

@rpc("authority", "reliable", "call_local")
func _transfer_potato_on_clients(from_peer_id: int, to_peer_id: int) -> void:
	if not players.has(from_peer_id) or not players.has(to_peer_id):
		return
	
	var from_player = players[from_peer_id]
	var to_player = players[to_peer_id]
	
	# Buscar papa del jugador origen
	for potato in active_potatoes:
		if is_instance_valid(potato) and potato.attached_player == from_player:
			potato.attach_to_player(to_player)
			break

# ========================================
# EXPLOSIÓN DE PAPA
# ========================================
func _on_potato_exploding(players_in_range: Array[Player], potato: ExplosivePotato) -> void:
	if not multiplayer.is_server():
		return  # Solo el servidor procesa explosiones
	
	print("Papa explotando! Jugadores afectados: ", players_in_range.size())
	
	# Recolectar IDs de jugadores afectados
	var affected_peer_ids: Array[int] = []
	for p in players_in_range:
		if is_instance_valid(p):
			var peer_id = players.find_key(p)
			if peer_id != null:
				affected_peer_ids.append(peer_id)
	
	# Notificar a todos los clientes (muestra animación/texto y elimina jugadores)
	_handle_explosion_on_clients.rpc(affected_peer_ids)
	
	# Esperar que termine el audio
	await potato.audio.finished
	active_potatoes.erase(potato)
	
	# Esperar un momento y hacer respawn de los jugadores eliminados + nueva papa
	await get_tree().create_timer(2.0).timeout
	
	for peer_id in affected_peer_ids:
		_respawn_player(peer_id)
	
	await get_tree().create_timer(1.0).timeout
	spawn_potato_on_random_player()

func _respawn_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Limpiar entrada vieja si quedó
	if players.has(peer_id):
		players.erase(peer_id)
	# Spawnear de nuevo en posición aleatoria
	var spawn_pos = spawn_positions[next_spawn_index % spawn_positions.size()]
	next_spawn_index += 1
	_spawn_player_on_clients.rpc(peer_id, spawn_pos)
	_create_player_instance(peer_id, spawn_pos)

@rpc("authority", "reliable", "call_local")
func _handle_explosion_on_clients(affected_peer_ids: Array[int]) -> void:
	for peer_id in affected_peer_ids:
		if players.has(peer_id):
			var player = players[peer_id]
			
			# Mostrar texto flotante
			if floating_text_scene:
				var text := floating_text_scene.instantiate()
				text.global_position = player.global_position + Vector2(0, -40)
				add_child(text)
			
			# Remover jugador
			players.erase(peer_id)
			player.queue_free()

# ========================================
# FIN DE JUEGO
# ========================================
func _end_game() -> void:
	if not multiplayer.is_server():
		return
	
	var winner_peer_id = players.keys()[0]
	print("¡Juego terminado! Ganador: Jugador %d" % winner_peer_id)
	
	potato_spawn_on_ready = false
	
	if potato_spawn_timer:
		potato_spawn_timer.stop()
	
	_announce_winner.rpc(winner_peer_id)

@rpc("authority", "reliable", "call_local")
func _announce_winner(winner_peer_id: int) -> void:
	print("¡El ganador es el Jugador %d!" % winner_peer_id)
	game_ended.emit()

# ========================================
# UTILIDADES
# ========================================
func get_player_with_potato() -> Player:
	for potato in active_potatoes:
		if is_instance_valid(potato) and is_instance_valid(potato.attached_player):
			return potato.attached_player
	return null

func _player_has_potato(player: Player) -> bool:
	for potato in active_potatoes:
		if is_instance_valid(potato) and potato.attached_player == player:
			return true
	return false

func win_condition_met() -> bool:
	return players.size() == 1

func get_player_by_id(peer_id: int) -> Player:
	return players.get(peer_id, null)

func get_player_count() -> int:
	return players.size()

func get_active_potato_count() -> int:
	return active_potatoes.size()

# ========================================
# DEBUG
# ========================================
func print_game_state() -> void:
	print("\n=== ESTADO DEL JUEGO ===")
	print("Jugadores activos: ", players.size())
	for peer_id in players:
		print("  - Jugador %d en posición %v" % [peer_id, players[peer_id].global_position])
	print("Papas activas: ", active_potatoes.size())
	print("========================\n")
