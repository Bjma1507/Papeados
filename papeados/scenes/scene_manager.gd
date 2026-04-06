extends Node
class_name SceneManager

func load_menu() -> void:
	get_tree().change_scene_to_file("res://Assets/Scenes/main_menu.tscn")

func load_lobby() -> void:
	get_tree().change_scene_to_file("res://Assets/Scenes/lobby.tscn")

func load_game() -> void:
	get_tree().change_scene_to_file("res://Assets/Scenes/game.tscn")

func load_game_over() -> void:
	get_tree().change_scene_to_file("res://Assets/Scenes/game_over.tscn")
