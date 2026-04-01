# NetworkManager.gd
extends Node

const PORT = 7000
const MAX_PLAYERS = 4

var peer = ENetMultiplayerPeer.new()

signal jugador_conectado(peer_id)
signal jugador_desconectado(peer_id)
signal servidor_creado
signal unido_a_servidor

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func crear_servidor():
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		print("Error al crear servidor: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Servidor creado en puerto ", PORT)
	servidor_creado.emit()
	return OK

func unirse_servidor(direccion_ip: String):
	var error = peer.create_client(direccion_ip, PORT)
	if error != OK:
		print("Error al conectar al servidor: ", error)
		return error
	
	multiplayer.multiplayer_peer = peer
	print("Intentando conectar a ", direccion_ip, ":", PORT)
	return OK

func obtener_id_jugador() -> int:
	return multiplayer.get_unique_id()

func es_servidor() -> bool:
	return multiplayer.is_server()

func obtener_todos_los_peers() -> Array:
	return multiplayer.get_peers()

# Callbacks de señales
func _on_peer_connected(id):
	print("Jugador conectado: ", id)
	jugador_conectado.emit(id)

func _on_peer_disconnected(id):
	print("Jugador desconectado: ", id)
	jugador_desconectado.emit(id)

func _on_connected_to_server():
	print("Conectado al servidor exitosamente")
	unido_a_servidor.emit()

func _on_connection_failed():
	print("Falló la conexión al servidor")

func _on_server_disconnected():
	print("Servidor desconectado")
