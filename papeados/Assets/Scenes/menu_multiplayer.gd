# MenuMultiplayer.gd
extends Control

@onready var entrada_ip = $VBoxContainer/EntradaIP
@onready var boton_crear = $VBoxContainer/BotonCrearServidor
@onready var boton_unirse = $VBoxContainer/BotonUnirse

func _ready():
	boton_crear.pressed.connect(_on_boton_crear_pressed)
	boton_unirse.pressed.connect(_on_boton_unirse_pressed)

func _on_boton_crear_pressed():
	NetworkManager.crear_servidor()
	NetworkManager.servidor_creado.connect(_on_servidor_creado)

func _on_boton_unirse_pressed():
	var ip = entrada_ip.text
	if ip == "":
		ip = "127.0.0.1"  # localhost por defecto
	NetworkManager.unirse_servidor(ip)

func _on_servidor_creado():
	print("Servidor creado, listo para jugar...")
	# get_tree().change_scene_to_file("res://escena_juego.tscn")
