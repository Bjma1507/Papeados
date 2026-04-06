extends Control

@onready var network_manager = get_node("/root/NetworkManager")
@onready var ip_input: LineEdit = $VBoxContainer/IPInput
@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var status_label: Label = $VBoxContainer/StatusLabel

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	# Conectar señales del network manager
	network_manager.servidor_creado.connect(_on_server_created)
	network_manager.unido_a_servidor.connect(_on_joined_server)

func _on_host_pressed():
	status_label.text = "Creando servidor..."
	var result = network_manager.crear_servidor()
	if result == OK:
		status_label.text = "Servidor creado! Esperando jugadores..."

func _on_join_pressed():
	var ip = ip_input.text
	if ip.is_empty():
		status_label.text = "Por favor ingresa una IP"
		return
	
	status_label.text = "Conectando a " + ip + "..."
	var result = network_manager.unirse_servidor(ip)
	if result == OK:
		status_label.text = "Conectando..."

func _on_server_created():
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_joined_server():
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")
