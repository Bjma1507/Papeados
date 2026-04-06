extends Node2D

@export var arena_width := 800
@export var arena_height := 600
@export var boundary_thickness := 20


func _ready() -> void:
	create_walls()

func create_walls():
	# Floor
	create_wall(
		Vector2(0, arena_height / 2),
		Vector2(arena_width, boundary_thickness)
	)

	# Top
	create_wall(
		Vector2(0, -arena_height / 2),
		Vector2(arena_width, boundary_thickness)
	)

	# Left
	create_wall(
		Vector2(-arena_width / 2, 0),
		Vector2(boundary_thickness, arena_height)
	)

	# Right
	create_wall(
		Vector2(arena_width / 2, 0),
		Vector2(boundary_thickness, arena_height)
	)


func create_wall(pos: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	var collision_shape := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.extents = size / 2
	collision_shape.shape = shape
	wall.position = pos
	wall.add_child(collision_shape)
	add_child(wall)
