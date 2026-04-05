extends Node
class_name ScoreManager

# Signals
signal score_updated(peer_id: int, new_score: int)

# Internal variables
var scores: Dictionary = {}  # peer_id -> int


# Initialization
func initialize(peer_ids: Array) -> void:
	scores.clear()
	for peer_id in peer_ids:
		scores[peer_id] = 0
	print("[ScoreManager] Marcador inicializado para %d jugadores." % peer_ids.size())

'''
Used to register a new player in the score manager. 
This should be called by the GameManager when a new player joins the game to ensure they are tracked in the scores.

Args:
    peer_id (int): The network peer ID of the player to register.
'''
func register_player(peer_id: int) -> void:
	if not scores.has(peer_id):
		scores[peer_id] = 0


'''
Adds a point to the player's score. 
Only runs on the server. 
After updating the score, it calls an RPC to sync it on all clients.

Args:
	peer_id (int): The network peer ID of the player to add a point to.
'''
func add_score(peer_id: int) -> void:
	if not Validator.ensure_server(self):
		return

	if not scores.has(peer_id):
		push_warning("[ScoreManager] Jugador %d no registrado en el marcador." % peer_id)
		return

	scores[peer_id] += 1
	_sync_score.rpc(peer_id, scores[peer_id])
	print("[ScoreManager] Jugador %d → %d puntos" % [peer_id, scores[peer_id]])


'''
Used to replicate (sync) a player's score on all clients.
This is called by the server after updating a player's score to ensure all clients have the correct score

Args:
	peer_id (int): The network peer ID of the player whose score is being synced.
	new_score (int): The new score value to set for the player.
'''
@rpc("authority", "reliable", "call_local")
func _sync_score(peer_id: int, new_score: int) -> void:
	scores[peer_id] = new_score
	score_updated.emit(peer_id, new_score)


'''
Helper methods for game logic, such as checking if a player has won, getting scores, etc.
'''
func has_won(peer_id: int, rounds_to_win: int) -> bool:
	return scores.get(peer_id, 0) >= rounds_to_win

func get_score(peer_id: int) -> int:
	return scores.get(peer_id, 0)

func get_all_scores() -> Dictionary:
	return scores.duplicate()

func remove_player(peer_id: int) -> void:
	scores.erase(peer_id)
