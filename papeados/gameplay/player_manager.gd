extends Node
class_name PlayerManager

# Internal class
class PlayerData:
	var peer_id: int
	var player_instance: Player
	var alive: bool = true
 
	func _init(id: int, instance: Player) -> void:
		peer_id = id
		player_instance = instance

# Signals
signal player_spawned(player: Player)
signal player_removed(peer_id: int)

# Scenes
@export var player_scene: PackedScene
@export var spawn_positions: Array[Vector2] = [
	Vector2(-200, 0),
	Vector2(200, 0),
	Vector2(-200, -100),
	Vector2(200, -100)
]

# Internal variables
var players: Dictionary = {}         # peer_id -> PlayerData
var _player_to_id: Dictionary = {}   # Player -> peer_id
var _next_spawn_index := 0


'''
Spawns a new player with the given peer_id. Only runs on the server. 
After creating the player instance, it calls an RPC to spawn it on all clients.

Args:
	peer_id (int): The network peer ID of the player to spawn.
'''
func spawn_player(peer_id: int) -> void:
	if not Validator.ensure_server(self):
		return

	if players.has(peer_id):
		push_warning("[PlayerManager] El jugador %d ya existe." % peer_id)
		return

	var pos = _get_next_spawn_pos()
	_create_player(peer_id, pos)
	_spawn_player_on_clients.rpc(peer_id, pos)


'''
Spawns a new player on all clients. 
This is called by the server after creating the player instance.

Args:
	peer_id (int): The network peer ID of the player to spawn.
	pos (Vector2): The position where the player should be spawned.
'''
@rpc("authority", "reliable")
func _spawn_player_on_clients(peer_id: int, pos: Vector2) -> void:
	if multiplayer.is_server():
		return
	_create_player(peer_id, pos)


'''
Instantiates a player at the given position and adds it to the scene and data structures.
This is an internal method and should not be called directly from outside.

Args:
	peer_id (int): The network peer ID of the player.
	pos (Vector2): The position where the player should be spawned.

Emits:
	player_spawned(player: Player): Emitted after the player instance is created and added to the scene.
'''
func _create_player(peer_id: int, pos: Vector2) -> void:
	if players.has(peer_id):
		return
 
	var player: Player = player_scene.instantiate()
 
	player.player_id = peer_id
	player.name = "Player_%d" % peer_id
	player.set_multiplayer_authority(peer_id)
 
	add_child(player)
 
	player.global_position = pos
 
	var data := PlayerData.new(peer_id, player)
	players[peer_id] = data
	_player_to_id[player] = peer_id
 
	print("[PlayerManager] Jugador %d creado en %v" % [peer_id, pos])
	player_spawned.emit(player)

'''
Respawns a player with the given peer_id. 
Only runs on the server.
Uses the same logic as spawn_player but first checks if the player already exists and removes it if necessary.

Args:
	peer_id (int): The network peer ID of the player to respawn.
'''
func respawn_player(peer_id: int) -> void:
	if not Validator.ensure_server(self):
		return

	# Limpiar instancia vieja si aún existe
	if players.has(peer_id):
		var old_data: PlayerData = players[peer_id]
		if is_instance_valid(old_data.player_instance):
			_player_to_id.erase(old_data.player_instance)
			old_data.player_instance.queue_free()
		players.erase(peer_id)

	var pos = _get_next_spawn_pos()
	_create_player(peer_id, pos)
	_spawn_player_on_clients.rpc(peer_id, pos)

	print("[PlayerManager] Jugador %d respawneado en %v" % [peer_id, pos])


'''
Deletes the player with the given peer_id.
Only runs on the server. After removing the player instance, it calls an RPC to remove it on all clients.

Args:
	peer_id (int): The network peer ID of the player to remove.
'''
func remove_player(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	_remove_player_on_clients.rpc(peer_id)


'''
Used by the server to remove a player on all clients.
This is called by the server after a player is removed from the data structures.

Args:
	peer_id (int): The network peer ID of the player to remove.
'''
@rpc("authority", "reliable", "call_local")
func _remove_player_on_clients(peer_id: int) -> void:
	if not players.has(peer_id):
		return

	var data: PlayerData = players[peer_id]
	if is_instance_valid(data.player_instance):
		_player_to_id.erase(data.player_instance)
		data.player_instance.queue_free()

	players.erase(peer_id)
	player_removed.emit(peer_id)
	print("[PlayerManager] Jugador %d removido." % peer_id)


'''
Marks a player as dead or alive. 
This is used by the RoundManager to track which players are still alive in the current round.

Args:
	peer_id (int): The network peer ID of the player to mark.
'''
func mark_player_dead(peer_id: int) -> void:
	var data: PlayerData = players.get(peer_id)
	if data:
		data.alive = false

'''
Marks a player as alive. This is used by the RoundManager to respawn players at the beginning of a new round.

Args:
	peer_id (int): The network peer ID of the player to mark as alive.
'''
func mark_player_alive(peer_id: int) -> void:
	var data: PlayerData = players.get(peer_id)
	if data:
		data.alive = true

func get_alive_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for peer_id in players:
		if players[peer_id].alive:
			result.append(peer_id)
	return result


'''
From now on, utility methods to get player instances, peer IDs, positions, etc.
These can be used by other managers, the UI, etc. to query player information.
'''
func get_player(peer_id: int) -> Player:
	var data: PlayerData = players.get(peer_id)
	return data.player_instance if data else null

func get_peer_id_of(player: Player) -> int:
	return _player_to_id.get(player, -1)

func get_random_alive_player() -> Player:
	var alive = get_alive_peer_ids()
	if alive.is_empty():
		return null
	return get_player(alive.pick_random())

func get_player_position(peer_id: int) -> Vector2:
	var player = get_player(peer_id)
	return player.global_position if player else Vector2.ZERO

func has_player(peer_id: int) -> bool:
	return players.has(peer_id)

func get_all_peer_ids() -> Array:
	return players.keys()

func count() -> int:
	return players.size()


'''
Helper method used to get the next spawn position in order to cycle through them when spawning or respawning players.

Returns:
	Vector2: The next spawn position for a player.
'''
func _get_next_spawn_pos() -> Vector2:
	var pos = spawn_positions[_next_spawn_index % spawn_positions.size()]
	_next_spawn_index += 1
	return pos
