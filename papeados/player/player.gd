extends CharacterBody2D
class_name Player

# ========================================
# CONSTANTES DE MOVIMIENTO
# ========================================
const SPEED := 300.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 900.0 #TODO: Añadir el gravitymanager
const MAX_FALL_SPEED := 900.0
const ACCELERATION := 800.0
const FRICTION := 600.0

# ========================================
# CONFIGURACIÓN DE DASH
# ========================================
@export_group("Dash Settings")
@export var dash_speed := 1200.0
@export var dash_duration := 0.2
@export var dash_cooldown := 1.5

# ========================================
# CONFIGURACIÓN DE JUGADOR
# ========================================
@export_group("Player Configuration")
@export var player_id := 1
@export var use_custom_controls := false
@export var player_name := "Player%d" % player_id

# ========================================
# CONFIGURACIÓN DE RED
# ========================================
@export_group("Network Settings")
@export var network_update_rate := 20.0  # Hz (actualizaciones por segundo)
@export var interpolation_speed := 15.0  # Velocidad de interpolación
@export var position_threshold := 2.0    # Threshold para enviar posición (pixels)
@export var velocity_threshold := 10.0   # Threshold para enviar velocidad

# ========================================
# NODOS
# ========================================
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_area: Area2D = $Area2D
@onready var audio = $AudioStreamPlayer2D
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

# ========================================
# AUDIO
# ========================================
@export_group("Audio Settings")
@export var jump_audio : AudioStreamWAV
@export var collision_sound : AudioStreamWAV

# ========================================
# VARIABLES DE GAMEPLAY
# ========================================
var can_double_jump := true
var can_dash := true
var is_dashing := false
var can_transfer_potato := false

# ========================================
# VARIABLES DE RED
# ========================================
# Para envío de datos
var network_update_timer := 0.0
var last_sent_position := Vector2.ZERO
var last_sent_velocity := Vector2.ZERO

# Para interpolación (solo clientes remotos)
var target_position := Vector2.ZERO
var target_velocity := Vector2.ZERO

# Buffer de posiciones para interpolación avanzada
var position_buffer: Array[Dictionary] = []
const BUFFER_SIZE := 3

# ========================================
# CONTROLES
# ========================================
var action_left: String
var action_right: String
var action_jump: String
var action_dash: String

# ========================================
# INICIALIZACIÓN
# ========================================
func _ready() -> void:
	add_to_group("players")

	_setup_input_actions()
	_setup_network()
	collision_area.body_entered.connect(_on_area_2d_body_entered)
	
	target_position = global_position
	target_velocity = velocity

func _setup_network() -> void:
	if sync:
		sync.set_multiplayer_authority(get_multiplayer_authority())
 
	if multiplayer.is_server():
		print("Jugador %d inicializado en servidor" % player_id)
	else:
		print("Jugador %d inicializado en cliente" % player_id)
# ========================================
# PHYSICS PROCESS
# ========================================
func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		# CLIENTE LOCAL: Procesar inputs y físicas
		_apply_gravity(delta)
		_handle_horizontal_movement(delta)
		_handle_jump()
		_handle_dash()
		move_and_slide()
		_update_animation()
		
		# Enviar datos a la red
		_network_update(delta)
	else:
		# CLIENTE REMOTO: Interpolar hacia la posición recibida
		_interpolate_position(delta)
		_update_animation()

func force_leave_floor():
	floor_snap_length = 0.0


# ========================================
# ACTUALIZACIÓN DE RED (Solo cliente local)
# ========================================
func _network_update(delta: float) -> void:
	network_update_timer += delta
	
	# Verificar si es tiempo de enviar actualización
	var update_interval = 1.0 / network_update_rate
	if network_update_timer >= update_interval:
		network_update_timer = 0.0
		
		# Solo enviar si hay cambios significativos
		if _should_send_update():
			_send_position_update()

func _should_send_update() -> bool:
	# Verificar si la posición o velocidad cambiaron significativamente
	var pos_changed = global_position.distance_to(last_sent_position) > position_threshold
	var vel_changed = velocity.distance_to(last_sent_velocity) > velocity_threshold
	
	return pos_changed or vel_changed

func _send_position_update() -> void:
	# Enviar posición actual a todos los clientes
	var current_time = Time.get_ticks_msec() / 1000.0
	
	rpc("_receive_position_update", 
		global_position, 
		velocity, 
		animated_sprite.flip_h,
		current_time)
	
	# Guardar última posición enviada
	last_sent_position = global_position
	last_sent_velocity = velocity

@rpc("any_peer", "unreliable")
func _receive_position_update(pos: Vector2, vel: Vector2, flip: bool, timestamp: float) -> void:

	if is_multiplayer_authority():
		return
	
	# Guardar datos para interpolación
	target_position = pos
	target_velocity = vel
	animated_sprite.flip_h = flip
	
	# Agregar al buffer de interpolación
	position_buffer.append({
		"position": pos,
		"velocity": vel,
		"time": timestamp
	})
	
	# Mantener tamaño del buffer
	if position_buffer.size() > BUFFER_SIZE:
		position_buffer.pop_front()

# ========================================
# INTERPOLACIÓN (Solo clientes remotos)
# ========================================
func _interpolate_position(delta: float) -> void:
	# Interpolación suave hacia la posición objetivo
	global_position = global_position.lerp(target_position, interpolation_speed * delta)
	velocity = velocity.lerp(target_velocity, interpolation_speed * delta)
	
	# Si está muy cerca, ajustar directamente para evitar jitter
	if global_position.distance_to(target_position) < 1.0:
		global_position = target_position

# ========================================
# INPUT SETUP
# ========================================
func _setup_input_actions() -> void:
	if use_custom_controls:
		action_left = "p%d_left" % player_id
		action_right = "p%d_right" % player_id
		action_jump = "p%d_jump" % player_id
		action_dash = "p%d_dash" % player_id
	else:
		action_left = "ui_left"
		action_right = "ui_right"
		action_jump = "ui_up"
		action_dash = "dash"

func get_input_vector() -> Vector2:
	var x_input := Input.get_axis(action_left, action_right)
	return Vector2(x_input, 0.0)

# ========================================
# FÍSICA DE MOVIMIENTO
# ========================================
func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = min(velocity.y, MAX_FALL_SPEED)
	else:
		can_double_jump = true
		velocity.y = 0.0

func _handle_horizontal_movement(delta: float) -> void:
	var input_x := get_input_vector().x
	var target_speed := dash_speed if is_dashing else SPEED
	
	if is_dashing and not is_on_floor():
		velocity.x = move_toward(velocity.x, input_x * dash_speed, ACCELERATION * delta)
	elif input_x != 0:
		velocity.x = move_toward(velocity.x, input_x * target_speed, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

# ========================================
# SALTO (Con sincronización RPC)
# ========================================
func _handle_jump() -> void:
	if not Input.is_action_just_pressed(action_jump):
		return
	
	if is_on_floor():
		velocity.y = JUMP_VELOCITY
		_notify_jump()  # Notificar a todos los clientes
		return
	
	if not is_on_floor() and velocity.y > 0 and can_double_jump:
		can_double_jump = false
		velocity.y = JUMP_VELOCITY
		_notify_jump()  # Notificar a todos los clientes

# RPC: Sincronizar salto en todos los clientes
@rpc("any_peer", "reliable", "call_local")
func _notify_jump() -> void:
	audio.stream = jump_audio
	audio.play()

func _play_collision_sound() -> void:
	audio.stream = collision_sound
	audio.play()

# ========================================
# DASH (Con sincronización RPC)
# ========================================
func _handle_dash() -> void:
	if Input.is_action_just_pressed(action_dash) and can_dash:
		var input_vector := get_input_vector()
		if input_vector.length() > 0:
			_start_dash()

func _start_dash() -> void:
	is_dashing = true
	can_dash = false
	
	# Notificar a todos que iniciamos dash
	rpc("_notify_dash_start")
	
	await get_tree().create_timer(dash_duration).timeout
	is_dashing = false
	
	# Notificar fin de dash
	rpc("_notify_dash_end")
	
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

@rpc("any_peer", "reliable", "call_local")
func _notify_dash_start() -> void:
	pass

@rpc("any_peer", "reliable", "call_local")
func _notify_dash_end() -> void:
	pass

# ========================================
# ANIMACIONES
# ========================================
func _update_animation() -> void:
	var input_x := get_input_vector().x if is_multiplayer_authority() else target_velocity.x
	
	if input_x != 0 and is_multiplayer_authority():
		animated_sprite.flip_h = input_x < 0
	
	if not is_on_floor():
		if velocity.y < 0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif abs(velocity.x) > 10:
		animated_sprite.play("walk")
	else:
		animated_sprite.play("idle")

# ========================================
# KNOCKBACK
# ========================================
func apply_knockback(knockback_vector: Vector2) -> void:
	_play_collision_sound()
	if is_multiplayer_authority():
		velocity += knockback_vector
	else:
		rpc_id(get_multiplayer_authority(), "_receive_knockback", knockback_vector)

@rpc("any_peer", "reliable")
func _receive_knockback(knockback_vector: Vector2) -> void:
	if not is_multiplayer_authority():
		return
	velocity += knockback_vector

# ========================================
# TRANSFERENCIA DE PAPA
# ========================================
func set_can_transfer_potato(value: bool) -> void:
	can_transfer_potato = value

func _on_area_2d_body_entered(body: Node) -> void:
	if not is_multiplayer_authority():
		return
 
	if not (body is Player) or body == self:
		return
 
	var direction = (body.global_position - global_position).normalized()

	body.apply_knockback(direction * 600.0)
 
	if multiplayer.is_server():
		_ask_transfer(body.player_id)
	else:
		_ask_transfer.rpc_id(1, body.player_id)

@rpc("any_peer", "reliable")
func _ask_transfer(to_player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var gm = _get_game_manager()
	if not gm:
		return

	if not can_transfer_potato:
		return
	if gm.get_player_with_potato() != self:
		return
	var to_player = gm.get_player_by_id(to_player_id)
	if to_player:
		gm.transfer_potato_network(self, to_player)

func _get_game_manager():
	return get_tree().current_scene

# ========================================
# UTILIDADES DE DEBUG
# ========================================
func get_network_stats() -> Dictionary:
	return {
		"is_authority": is_multiplayer_authority(),
		"peer_id": get_multiplayer_authority(),
		"position": global_position,
		"velocity": velocity,
		"target_position": target_position,
		"buffer_size": position_buffer.size()
	}

func print_network_stats() -> void:
	var stats = get_network_stats()
	print("=== Player %d Stats ===" % player_id)
	for key in stats:
		print("  %s: %s" % [key, stats[key]])
