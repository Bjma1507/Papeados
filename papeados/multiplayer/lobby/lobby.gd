extends Control

@onready var network_manager = get_node("/root/NetworkManager")
@onready var host_button: Button = $IniciarPartidaBtn
@onready var join_button: Button = $SalirSalaBtn
@onready var status_label: Label = $StatusLabel
@onready var codigo_label: Label = $CodigoSalaLabel

func _ready():
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_salir_pressed)
	
	network_manager.servidor_creado.connect(_on_server_created)
	network_manager.unido_a_servidor.connect(_on_joined_server)

func _on_host_pressed():
	status_label.text = "Iniciando servidor..."
	var result = network_manager.crear_servidor()
	if result == OK:
		codigo_label.text = "CÓDIGO DE SALA: LOCALHOST"
		status_label.text = "Esperando a la papa rival..."

func _on_salir_pressed():
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func _on_server_created():
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_joined_server():
	status_label.text = "¡Conectado!"
	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/main.tscn")
