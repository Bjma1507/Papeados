extends Node
class_name UIManager

@export var round_label: Label
@export var players_label: Label

@export var game_over_panel : Panel
@export var winner_label: Label
@export var play_again_button: Button

var _player_manager: PlayerManager
var _score_manager: ScoreManager
var _state_machine: GameStateMachine
var _game_manager: GameManager

func _ready() -> void:
	print("[UIManager] Ready")
 
	_game_manager = get_tree().current_scene as GameManager
	if not _game_manager:
		push_error("[UIManager] No se encontró GameManager.")
		return
 
	_player_manager = _game_manager.get_node_or_null("PlayerManager")
	_score_manager = _game_manager.get_node_or_null("ScoreManager")
	_state_machine = _game_manager.get_node_or_null("StateMachine")
	var round_manager: RoundManager = _game_manager.get_node_or_null("RoundManager")
 
	if round_manager:
		round_manager.round_started.connect(_on_round_started)
		round_manager.round_ended.connect(_on_round_ended)
 
	if _player_manager:
		_player_manager.player_spawned.connect(_on_roster_changed)
		_player_manager.player_removed.connect(_on_roster_changed)
 
	if _score_manager:
		_score_manager.score_updated.connect(_on_score_updated)
 
	if _state_machine:
		_state_machine.state_entered.connect(_on_state_entered)
 
	if _game_manager:
		_game_manager.game_ended.connect(_on_game_ended)
 
	if play_again_button:
		play_again_button.pressed.connect(_on_play_again_pressed)
		# Solo el host puede reiniciar
		play_again_button.visible = multiplayer.is_server()
 
	_set_game_over_visible(false)
 
func _on_state_entered(state: GameStateMachine.GameState) -> void:
	match state:
		GameStateMachine.GameState.WAITING, \
		GameStateMachine.GameState.STARTING, \
		GameStateMachine.GameState.IN_ROUND:
			_set_game_over_visible(false)
		GameStateMachine.GameState.GAME_OVER:
			_set_game_over_visible(true)
 
func _on_round_started(round_number: int, rounds_to_win: int) -> void:
	if round_label:
		round_label.text = "Ronda %d — Primero en %d gana" % [round_number, rounds_to_win]
	_rebuild_players_label()
 
 
func _on_round_ended(survivor_peer_id: int) -> void:
	if round_label:
		if survivor_peer_id == -1:
			round_label.text = "¡Empate!"
		else:
			round_label.text = "¡Jugador %d sobrevivió!" % survivor_peer_id
 
func _on_roster_changed(_ignored) -> void:
	_rebuild_players_label()
 
 
func _on_score_updated(_peer_id: int, _score: int) -> void:
	_rebuild_players_label()
 
 
func _rebuild_players_label() -> void:
	if not players_label or not _player_manager:
		return
 
	var alive_ids = _player_manager.get_alive_peer_ids()
	var text = ""
 
	for peer_id in _player_manager.get_all_peer_ids():
		var score = _score_manager.get_score(peer_id) if _score_manager else 0
		var alive = peer_id in alive_ids
		var status = "" if alive else " 💀"
		text += "Jugador %d — %d pts%s\n" % [peer_id, score, status]
 
	players_label.text = text.strip_edges()
 
func _on_game_ended() -> void:
	if not _score_manager or not _player_manager:
		return
 
	var scores = _score_manager.get_all_scores()
	var winner_id = -1
	var highest = -1
 
	for peer_id in scores:
		if scores[peer_id] > highest:
			highest = scores[peer_id]
			winner_id = peer_id
 
	if winner_label:
		if winner_id != -1:
			winner_label.text = "¡Jugador %d ganó con %d puntos!" % [winner_id, highest]
		else:
			winner_label.text = "¡Empate!"
 
	_set_game_over_visible(true)
 
 
func _set_game_over_visible(visible: bool) -> void:
	if game_over_panel:
		game_over_panel.visible = visible
 
 
func _on_play_again_pressed() -> void:
	if _game_manager:
		_game_manager.request_restart()
