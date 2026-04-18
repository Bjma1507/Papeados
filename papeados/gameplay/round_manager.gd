extends Node
class_name RoundManager

# Signals
signal round_started(round_number: int, rounds_to_win: int)
signal round_ended(survivor_peer_id: int)
signal round_ready_to_spawn
signal all_rounds_completed(winner_peer_id: int)

# Config variables
@export var rounds_to_win: int = 3
@export var round_end_delay: float = 3.0
@export var respawn_delay: float = 0.5

# Internal variables
var round_number: int = 0
var round_in_progress: bool = false
var players_dead_this_round: Array[int] = []


'''
Manages the flow of the starting rounds, used to respawn players at the beginning of each round

Args:
	player_manager (PlayerManager): The PlayerManager instance to manage player states and respawns.

Emits:
	round_started(round_number: int, rounds_to_win: int): 
		(RPC) Emitted at the start of each round with the current round number and rounds needed to win.
	round_ready_to_spawn: Emitted when the round is ready for potatoes to start spawning.

'''
func start_round(player_manager: PlayerManager) -> void:
	if not Validator.ensure_server(self):
		return
 
	if round_in_progress:
		push_warning("[RoundManager] Intento de iniciar ronda mientras una ya está en progreso.")
		return
 
	var arena = _get_arena()
	if arena:
		arena.regenerate_for_round()
 
	for peer_id in players_dead_this_round.duplicate():
		player_manager.respawn_player(peer_id)
	players_dead_this_round.clear()
 
	await get_tree().create_timer(respawn_delay).timeout
 
	round_number += 1
	round_in_progress = true
 
	for peer_id in player_manager.get_all_peer_ids():
		player_manager.mark_player_alive(peer_id)
 
	print("[RoundManager] === Comenzando Ronda %d ===" % round_number)
	_announce_round_start.rpc(round_number, rounds_to_win)
	round_ready_to_spawn.emit()

@rpc("authority", "reliable", "call_local")
func _announce_round_start(number: int, to_win: int) -> void:
	round_started.emit(number, to_win)

'''
Checks if the round has ended by counting alive players. 
If only one or zero players are alive, it finishes the round and awards points.

Args:
	player_manager (PlayerManager): The PlayerManager instance to check player states.
	score_manager (ScoreManager): The ScoreManager instance to award points.
	potato_manager (PotatoManager): The PotatoManager instance to stop spawning potatoes if the round ends.

'''
func check_round_end(player_manager: PlayerManager, score_manager: ScoreManager, potato_manager: PotatoManager) -> void:
	if not Validator.ensure_server(self):
		return
 
	var alive = player_manager.get_alive_peer_ids()
	print("[RoundManager] Jugadores vivos: %d" % alive.size())
 
	if alive.size() <= 1:
		var survivor_id = alive[0] if alive.size() == 1 else -1
		await _finish_round(survivor_id, player_manager, score_manager, potato_manager)
	else:
		await get_tree().create_timer(1.0).timeout
		var target = player_manager.get_random_alive_player()
		if target:
			potato_manager.spawn_potato_on_player(target, player_manager)
			potato_manager.start_spawn_timer()

'''
Manages the finish of a round, awarding points to the survivor and checking for game end conditions.
This is called by the server when a round ends to handle the logic of awarding points, checking for winners, and starting the next round.

Args:
	survivor_peer_id (int): The network peer ID of the survivor of the round, or -1 if there are no survivors.
	player_manager (PlayerManager): The PlayerManager instance to manage player states and respawns.
	score_manager (ScoreManager): The ScoreManager instance to award points.
	potato_manager (PotatoManager): The PotatoManager instance to stop spawning potatoes if the round ends.

'''
func _finish_round(survivor_peer_id: int, player_manager: PlayerManager, score_manager: ScoreManager, potato_manager: PotatoManager) -> void:
	round_in_progress = false
	potato_manager.stop_spawn_timer()
 
	print("[RoundManager] === FIN DE RONDA %d ===" % round_number)
	_announce_round_end.rpc(survivor_peer_id)
 
	await get_tree().create_timer(round_end_delay).timeout
 
	if survivor_peer_id != -1 and score_manager.has_won(survivor_peer_id, rounds_to_win):
		all_rounds_completed.emit(survivor_peer_id)
		return
 
	start_round(player_manager)


'''
Used to announce the end of a round to all clients. 
This is called by the server when a round ends to notify clients of the survivor.

Args:
	survivor_peer_id (int): The network peer ID of the survivor of the round, or -1 if there are no survivors.
'''
@rpc("authority", "reliable", "call_local")
func _announce_round_end(survivor_peer_id: int) -> void:
	print("[RoundManager] Ronda terminada. Superviviente: %d" % survivor_peer_id)
	round_ended.emit(survivor_peer_id)

'''
Used by the PotatoManager to mark a player as dead when they are hit by an explosion.
This is called by the PotatoManager when a player is affected by an explosion to update their state
in the PlayerManager and to track which players have died in the current round.
Args:
	peer_id (int): The network peer ID of the player to mark as dead.
	player_manager (PlayerManager): The PlayerManager instance to update the player's state.
'''
func register_death(peer_id: int, player_manager: PlayerManager) -> void:
	player_manager.mark_player_dead(peer_id)
	if peer_id not in players_dead_this_round:
		players_dead_this_round.append(peer_id)

func _get_arena():
	return get_parent().get_node_or_null("Platforms")
