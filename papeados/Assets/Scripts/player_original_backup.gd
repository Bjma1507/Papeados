extends CharacterBody2D
#class_name Player

const SPEED := 300.0
const JUMP_VELOCITY := -400.0
const GRAVITY := 900.0
const MAX_FALL_SPEED := 900.0
const ACCELERATION := 800.05
const FRICTION := 600.0

@export_group("Dash Settings")
@export var dash_speed := 600.0
@export var dash_duration := 0.2
@export var dash_cooldown := 1.5

@export_group("Player Configuration")
@export var player_id := 1
@export var use_custom_controls := false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision_area: Area2D = $Area2D

@export var jump_audio : AudioStreamWAV

@onready var audio = $AudioStreamPlayer2D


var can_double_jump := true
var can_dash := true
var is_dashing := false
var can_transfer_potato := false

var action_left: String
var action_right: String
var action_jump: String
var action_dash: String

func _ready() -> void:
	_setup_input_actions()
	collision_area.body_entered.connect(_on_area_2d_body_entered)

func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_horizontal_movement(delta)
	_handle_jump()
	_handle_dash()
	_update_animation()
	move_and_slide()

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

func _handle_jump() -> void:
	if not Input.is_action_just_pressed(action_jump):
		return
	
	if is_on_floor():
		velocity.y = JUMP_VELOCITY
		audio.stream = jump_audio;
		audio.play();
		return
	
	if not is_on_floor() and velocity.y > 0 and can_double_jump:
		can_double_jump = false
		velocity.y = JUMP_VELOCITY
		audio.stream = jump_audio;
		audio.play();
	
func _handle_dash() -> void:
	if Input.is_action_just_pressed(action_dash) and can_dash:
		var input_vector := get_input_vector()
		if input_vector.length() > 0:
			_start_dash()

func _start_dash() -> void:
	is_dashing = true
	can_dash = false
	
	await get_tree().create_timer(dash_duration).timeout
	is_dashing = false
	
	await get_tree().create_timer(dash_cooldown).timeout
	can_dash = true

func _update_animation() -> void:
	var input_x := get_input_vector().x
	
	if input_x != 0:
		animated_sprite.flip_h = input_x < 0
	
	if not is_on_floor():
		if velocity.y < 0:
			animated_sprite.play("jump")
		else:
			animated_sprite.play("fall")
	elif input_x != 0:
		animated_sprite.play("walk")
	else:
		animated_sprite.play("idle")

func apply_knockback(knockback_vector: Vector2) -> void:
	velocity += knockback_vector

func set_can_transfer_potato(value: bool) -> void:
	can_transfer_potato = value

func _on_area_2d_body_entered(body: Node) -> void:
	if body is Player and body != self:
		var direction = (body.global_position - global_position).normalized()
		var knockback = direction * 300.0
		body.apply_knockback(knockback)

	if body is Player and body != self and can_transfer_potato and _get_game_manager().get_player_with_potato() == self:
		var game_manager = _get_game_manager()
		game_manager.attach_potato_to_player(game_manager.active_potatoes[0], body)

func _get_game_manager() -> GameManager:
	return get_tree().current_scene as GameManager
