extends Control

class Jugador:
	var peer_id: int
	var name: String
	var avatar_idx: int
	
	func _init(p_id: int, p_name: String, p_avatar: int):
		self.peer_id = p_id
		self.name = p_name
		self.avatar_idx = p_avatar

var Jugadores: Array[Jugador] = []
var soy_anfitrion: bool = false

@onready var network_manager = get_node("/root/NetworkManager")
@onready var iniciar_btn: Button = $IniciarPartidaBtn
@onready var salir_btn: Button = $SalirSalaBtn
@onready var status_label: Label = $StatusLabel
@onready var codigo_label: Label = $CodigoSalaLabel
@onready var ip_input: LineEdit = $IPInput

var fila_jugador_scene = preload("res://multiplayer/lobby/fila_jugador.tscn")

var avatares = [
	preload("res://scenes/P1.png"),
	preload("res://scenes/P2.png"),
	preload("res://scenes/P3.png"),
	preload("res://scenes/P4.png"),
	preload("res://scenes/P5.png"),
	preload("res://scenes/P6.png")
]

func _ready():
	iniciar_btn.text = ""
	salir_btn.text = ""
	
	iniciar_btn.pressed.connect(_on_iniciar_pressed)
	salir_btn.pressed.connect(_on_salir_pressed)
	network_manager.servidor_creado.connect(_on_server_created)
	network_manager.unido_a_servidor.connect(_on_joined_server)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	soy_anfitrion = network_manager.get_meta("modo_host", false)
	
	if soy_anfitrion:
		ip_input.hide()
		codigo_label.show()
		status_label.text = "Iniciando servidor..."
		network_manager.crear_servidor()
	else:
		codigo_label.text = "CÓDIGO DE SALA:"
		ip_input.show()
		status_label.text = "Escribe el código y presiona el botón verde"
		iniciar_btn.disabled = false

func _obtener_ip_local() -> String:
	var ip = "127.0.0.1"
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			ip = address
			break
	return ip

func _on_iniciar_pressed():
	if soy_anfitrion:
		if Jugadores.size() > 1:
			_change_scene_to_main_clients.rpc()
			_change_scene_to_main_server()
		else:
			status_label.text = "ERROR: Espera a que entre un invitado."
	else:
		var ip = ip_input.text.strip_edges()
		if ip.is_empty():
			status_label.text = "Por favor, escribe una IP válida."
		else:
			status_label.text = "Conectando a " + ip + "..."
			iniciar_btn.disabled = true
			network_manager.unirse_servidor(ip)

func _on_server_created():
	var mi_ip = _obtener_ip_local()
	codigo_label.text = "CÓDIGO DE Sala: #" + mi_ip
	status_label.text = "Esperando jugadores..."
	var mi_id = multiplayer.get_unique_id()
	Jugadores.append(Jugador.new(mi_id, "Jugador", 0))
	_actualizar_lista_visual()

func _on_joined_server():
	ip_input.hide()
	codigo_label.text = "CÓDIGO DE SALA: #" + ip_input.text
	status_label.text = "¡Conectado! Esperando a que el Host inicie..."
	iniciar_btn.disabled = true
	var mi_id = multiplayer.get_unique_id()
	Jugadores.append(Jugador.new(mi_id, "Jugador", mi_id % 6))
	_actualizar_lista_visual()

func _on_peer_connected(id):
	Jugadores.append(Jugador.new(id, "Jugador", id % 6))
	if soy_anfitrion:
		status_label.text = "¡Jugadores conectados! Vuelve a presionar INICIAR."
		iniciar_btn.disabled = false
	_actualizar_lista_visual()

func _on_peer_disconnected(id):
	for i in range(Jugadores.size() - 1, -1, -1):
		if Jugadores[i].peer_id == id:
			Jugadores.remove_at(i)
	if soy_anfitrion and Jugadores.size() < 2:
		status_label.text = "Faltan jugadores. Esperando..."
		iniciar_btn.disabled = true
	_actualizar_lista_visual()

func _on_salir_pressed():
	multiplayer.multiplayer_peer = null
	Jugadores.clear()
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")

func _change_scene_to_main_server():
	LoadingScreenScript.load_scene("res://scenes/main.tscn")

@rpc("authority", "reliable", "call_local")
func _change_scene_to_main_clients():
	if not multiplayer.is_server():
		LoadingScreenScript.load_scene("res://scenes/main.tscn")

func _actualizar_lista_visual():
	for hijo in $ListaJugadores.get_children():
		hijo.queue_free()
		
	var contador_invitados = 2
	for jugador in Jugadores:
		var nueva_fila = fila_jugador_scene.instantiate()
		
		if jugador.peer_id == 1:
			nueva_fila.get_node("NombreLabel").text = "Jugador 1"
		else:
			nueva_fila.get_node("NombreLabel").text = "Jugador " + str(contador_invitados)
			contador_invitados += 1
			
		nueva_fila.get_node("AvatarTexture").texture = avatares[jugador.avatar_idx]
		$ListaJugadores.add_child(nueva_fila)
