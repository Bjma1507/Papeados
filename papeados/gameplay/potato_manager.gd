extends Node
class_name PotatoManager

# Signals
signal potato_spawned(potato: ExplosivePotato)
signal players_affected_by_explosion(affected_peer_ids: Array[int])

# Scenes
@export var explosive_potato_scene: PackedScene
@export var floating_text_scene: PackedScene

# Config variables
@export_group("Potato Settings")
@export var potato_spawn_interval: float = 15.0
@export var potato_attach_delay: float = 1.0
@export var auto_spawn: bool = true

# Internal variables
var active_potatoes: Array[ExplosivePotato] = []
var _spawn_timer: Timer


func _ready() -> void:
	if multiplayer.is_server() and auto_spawn:
		_setup_spawn_timer()


func _setup_spawn_timer() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.wait_time = potato_spawn_interval
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(_spawn_timer)


func start_spawn_timer() -> void:
	if _spawn_timer and _spawn_timer.is_stopped():
		_spawn_timer.start()


func stop_spawn_timer() -> void:
	if _spawn_timer:
		_spawn_timer.stop()


'''
Used to spawn a potato on a specific player. 
Server only. Uses peer_id for safe RPC transport instead of Player references.

Args:
	target_player (Player): The player instance to attach the potato to.
	player_manager (PlayerManager): Used to resolve the peer_id of the target player.
'''
func spawn_potato_on_player(target_player: Player, player_manager: PlayerManager) -> void:
	if not Validator.ensure_server(self):
		return

	if not is_instance_valid(target_player):
		push_warning("[PotatoManager] Target player inválido.")
		return

	var peer_id = player_manager.get_peer_id_of(target_player)
	if peer_id == -1:
		push_warning("[PotatoManager] No se encontró peer_id para el jugador.")
		return

	print("[PotatoManager] Spawneando papa en jugador %d" % peer_id)
	_spawn_potato_on_clients.rpc(peer_id)


@rpc("authority", "reliable", "call_local")
func _spawn_potato_on_clients(target_peer_id: int) -> void:
	var player_manager: PlayerManager = _get_player_manager()
	if not player_manager:
		push_error("[PotatoManager] No se encontró PlayerManager.")
		return

	var target_player = player_manager.get_player(target_peer_id)
	if not is_instance_valid(target_player):
		push_warning("[PotatoManager] Jugador %d no encontrado para spawnear papa." % target_peer_id)
		return

	_create_potato(target_player)


'''
Creates the potato instance, configures it, and connects the explosion signal.

Args:
	target_player (Player): The player to attach the potato to.
'''
func _create_potato(target_player: Player) -> void:
	var potato: ExplosivePotato = explosive_potato_scene.instantiate()
	
	potato.attach_delay = potato_attach_delay
	add_child(potato)
	potato.attach_to_player(target_player)
	potato.exploding.connect(_on_potato_exploded.bind(potato))
	active_potatoes.append(potato)

	print("[PotatoManager] Papa creada y adjuntada.")
	potato_spawned.emit(potato)


'''
Transfers the potato from one player to another. Server only.

Args:
	from_player (Player): Player currently holding the potato.
	to_player (Player): Player that will receive the potato.
	player_manager (PlayerManager): Used to resolve peer IDs.
'''
func transfer_potato(from_player: Player, to_player: Player, player_manager: PlayerManager) -> void:
	if not Validator.ensure_server(self):
		return

	var from_id = player_manager.get_peer_id_of(from_player)
	var to_id = player_manager.get_peer_id_of(to_player)

	if from_id == -1 or to_id == -1:
		push_warning("[PotatoManager] Jugadores inválidos para transferencia.")
		return

	print("[PotatoManager] Transfiriendo papa de %d a %d" % [from_id, to_id])
	_transfer_potato_on_clients.rpc(from_id, to_id)


@rpc("authority", "reliable", "call_local")
func _transfer_potato_on_clients(from_peer_id: int, to_peer_id: int) -> void:
	var player_manager: PlayerManager = _get_player_manager()
	if not player_manager:
		return

	var from_player = player_manager.get_player(from_peer_id)
	var to_player = player_manager.get_player(to_peer_id)

	if not is_instance_valid(from_player) or not is_instance_valid(to_player):
		return

	for potato in active_potatoes:
		if is_instance_valid(potato) and potato.attached_player == from_player:
			potato.attach_to_player(to_player)
			break
	
	var text = floating_text_scene.instantiate()

	text.global_position = to_player.global_position + Vector2(0, -40)
	
	add_child(text)	
	text._create_text("TIENES LA PAPA!")

'''
Called when a potato explodes. Determines affected players and emits signal for the GameManager.

Args:
	players_in_range (Array[Player]): Players within explosion radius.
	potato (ExplosivePotato): The potato that exploded.
'''
func _on_potato_exploded(players_in_range: Array[Player], potato: ExplosivePotato) -> void:
	if not Validator.ensure_server(self):
		return

	stop_spawn_timer()

	var player_manager: PlayerManager = _get_player_manager()
	if not player_manager:
		return

	var affected_peer_ids: Array[int] = []
	for p in players_in_range:
		if is_instance_valid(p):
			var peer_id = player_manager.get_peer_id_of(p)
			if peer_id != -1 and peer_id not in affected_peer_ids:
				affected_peer_ids.append(peer_id)

	print("[PotatoManager] Papa explotó. Afectados: %d" % affected_peer_ids.size())

	await potato.audio.finished
	active_potatoes.erase(potato)

	players_affected_by_explosion.emit(affected_peer_ids)


# Utilities

func get_player_with_potato() -> Player:
	for potato in active_potatoes:
		if is_instance_valid(potato) and is_instance_valid(potato.attached_player):
			return potato.attached_player
	return null

func player_has_potato(player: Player) -> bool:
	for potato in active_potatoes:
		if is_instance_valid(potato) and potato.attached_player == player:
			return true
	return false

func has_active_potato() -> bool:
	return not active_potatoes.is_empty()

func stop_all_potatoes() -> void:
	stop_spawn_timer()
	for potato in active_potatoes:
		if is_instance_valid(potato):
			potato.queue_free()
	active_potatoes.clear()

func _on_spawn_timer_timeout() -> void:
	if multiplayer.is_server():
		var player_manager: PlayerManager = _get_player_manager()
		if not player_manager:
			return
		var target = player_manager.get_random_alive_player()
		if target:
			spawn_potato_on_player(target, player_manager)

func _get_player_manager() -> PlayerManager:
	return get_parent().get_node_or_null("PlayerManager")
