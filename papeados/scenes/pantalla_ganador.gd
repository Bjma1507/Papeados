extends Control

@onready var avatar_imagen = $AvatarTexture
@onready var nombre_label = $NombreLabel
@onready var btn_continuar = $BtnContinuar

func _ready():
	btn_continuar.pressed.connect(_on_btn_continuar_pressed)
	_cargar_datos_reales()

func _cargar_datos_reales():
	var mi_id = multiplayer.get_unique_id()
	var net = get_node("/root/NetworkManager")
	
	if net.jugadores_activos.has(mi_id):
		var datos = net.jugadores_activos[mi_id]
		nombre_label.text = datos["nombre"]
		avatar_imagen.texture = net.avatares_globales[datos["avatar_idx"]]
	else:
		nombre_label.text = "ID: " + str(mi_id)

func _on_btn_continuar_pressed():
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://ui/menus/main_menu.tscn")
