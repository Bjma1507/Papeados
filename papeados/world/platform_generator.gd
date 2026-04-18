extends Node2D

var texture_plataforma_neon = preload("res://scenes/borde.png")
@export_group("Arena Settings")
@export var arena_width := 800
@export var arena_height := 600

@export_group("Platform Settings")
@export var platform_count := 6
@export var platform_min_width := 100
@export var platform_max_width := 150
@export var platform_thickness := 20
@export var margin := 100

@export_group("Distribution")
@export var min_vertical_spacing := 80
@export var min_horizontal_spacing := 60
@export var use_grid_distribution := false

@export_group("Visual")
@export var show_platforms := true
@export var platform_color := Color(0.4, 0.6, 0.8, 1.0)
@export var add_outline := true

@export_group("Gameplay")
@export var ensure_reachability := true
@export var max_jump_distance := 200

var platforms := []
var _map_seed: int = 0

func _ready():
	if multiplayer.is_server():
		_map_seed = randi()
		seed(_map_seed)
		generate_platforms()
	else:
		call_deferred("_request_seed")

func _request_seed() -> void:
	_ask_for_seed.rpc_id(1)

@rpc("any_peer", "reliable")
func _ask_for_seed() -> void:
	if multiplayer.is_server():
		var peer_id = multiplayer.get_remote_sender_id()
		_receive_seed.rpc_id(peer_id, _map_seed)

@rpc("authority", "reliable")
func _receive_seed(seed_value: int) -> void:
	seed(seed_value)
	generate_platforms()

func regenerate_for_round() -> void:
	if not multiplayer.is_server():
		return

	_map_seed = randi()
	_sync_and_generate.rpc(_map_seed)


@rpc("authority", "reliable", "call_local")
func _sync_and_generate(new_seed: int) -> void:
	_map_seed = new_seed
	seed(new_seed)
	generate_platforms()

func generate_platforms():
	platforms.clear()
	for child in get_children():
		child.queue_free()
	generate_random_platforms()

func generate_random_platforms():
	var max_attempts = platform_count * 10
	var attempts = 0

	while platforms.size() < platform_count and attempts < max_attempts:
		attempts += 1

		var width = randf_range(platform_min_width, platform_max_width)
		var x = randf_range(
			-arena_width / 2 + width / 2 + margin,
			arena_width / 2 - width / 2 - margin
		)
		var y = randf_range(
			-arena_height / 2 + margin,
			arena_height / 2 - margin
		)

		var pos = Vector2(x, y)
		if is_valid_position(pos, width):
			create_platform(pos, width)

func is_valid_position(pos: Vector2, width: float) -> bool:
	for platform_data in platforms:
		var other_pos = platform_data.position
		var other_width = platform_data.width

		if abs(pos.x - other_pos.x) < (width + other_width) / 2 + min_horizontal_spacing:
			if abs(pos.y - other_pos.y) < min_vertical_spacing:
				return false
	return true

func create_platform(pos: Vector2, width: float):
	var platform = StaticBody2D.new()
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()

	shape.size = Vector2(width, platform_thickness)
	collision.shape = shape

	platform.position = pos
	platform.add_child(collision)
	platform.add_to_group("platforms")
	add_child(platform)

	if show_platforms:
		add_platform_visual(platform, width)

	platforms.append({
		"position": pos,
		"width": width,
		"node": platform
	})

func add_platform_visual(platform: StaticBody2D, width: float):
	var visual = Panel.new()
	var sb = StyleBoxFlat.new()

	sb.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	sb.border_color = Color(1.0, 0.0, 1.0, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2

	visual.add_theme_stylebox_override("panel", sb)
	visual.size = Vector2(width, platform_thickness)
	visual.position = Vector2(-width / 2, -platform_thickness / 2)
	platform.add_child(visual)

func regenerate():
	generate_platforms()

func _draw():
	if ensure_reachability and Engine.is_editor_hint():
		for i in range(platforms.size()):
			for j in range(i + 1, platforms.size()):
				var dist = platforms[i].position.distance_to(platforms[j].position)
				if dist <= max_jump_distance:
					draw_line(platforms[i].position, platforms[j].position, Color(0, 1, 0, 0.3), 1.0)

func get_nearest_platform(pos: Vector2) -> Dictionary:
	var nearest = null
	var min_distance = INF
	for platform_data in platforms:
		var distance = pos.distance_to(platform_data.position)
		if distance < min_distance:
			min_distance = distance
			nearest = platform_data
	return nearest if nearest else {}

func verify_reachability() -> bool:
	if platforms.size() <= 1:
		return true

	var visited = []
	var to_visit = [0]

	while to_visit.size() > 0:
		var current = to_visit.pop_front()
		if current in visited:
			continue
		visited.append(current)
		for i in range(platforms.size()):
			if i not in visited and i not in to_visit:
				var dist = platforms[current].position.distance_to(platforms[i].position)
				if dist <= max_jump_distance:
					to_visit.append(i)

	return visited.size() == platforms.size()
