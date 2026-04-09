extends Node2D

@onready var crear_partida_btn = $CrearPartidaBtn
@onready var unirse_btn = $UnirseBtn
@onready var salir_btn = $SalirBtn

func _ready():
	crear_partida_btn.pressed.connect(_on_crear_pressed)
	unirse_btn.pressed.connect(_on_unirse_pressed)
	salir_btn.pressed.connect(_on_salir_pressed)

func _on_crear_pressed():
	get_tree().change_scene_to_file("res://multiplayer/lobby/lobby.tscn")

func _on_unirse_pressed():
	get_tree().change_scene_to_file("res://multiplayer/lobby/lobby.tscn")

func _on_salir_pressed():
	get_tree().quit()
