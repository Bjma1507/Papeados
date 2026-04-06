extends Node2D
class_name LaunchPlatform

@onready var area: Area2D = $Area2D


@export var launch_speed := 800.0

func _ready() -> void:
		area.body_entered.connect(_on_area_body_entered)


func launch_player(player: Player) -> void:
	var direction = (player.global_position - global_position).normalized()
	player.velocity = direction * launch_speed
	player.force_leave_floor()


func _on_area_body_entered(body: Node) -> void:
	if body is Player:
		launch_player(body)
