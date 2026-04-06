extends Node2D
class_name UIManager

@export var round_label: Label
@export var players_label: Label


func _ready() -> void:

	var game_manager = get_node("/root/GameManager")

	print("UI Manager ready")
	game_manager.round_started.connect(on_round_started)
	game_manager.players_list.connect(on_players_list)

func on_round_started(round_number: int, rounds_to_win: int) -> void:
	round_label.text = "Round %d - First to %d wins" % [round_number, rounds_to_win]

func on_players_list(players: Dictionary[int, Player]) -> void:
	var player_info = "Players:\n"
	for player in players.values():
		player_info += "- %s (ID: %d)\n" % [player.name, player.get_network_id()]
	players_label.text = player_info
