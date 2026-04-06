extends Node

@export var base_gravity := 900
var gravity_multiplier := 1.0

func get_gravity() -> float:
	return base_gravity * gravity_multiplier

func invert_gravity(duration: float) -> void:
	gravity_multiplier = -1.0

	for player in get_tree().get_nodes_in_group("players"):
		if player is Player:
			player.force_leave_floor()
	
	await get_tree().create_timer(duration).timeout
	
	gravity_multiplier = 1.0

	for player in get_tree().get_nodes_in_group("players"):
		if player is Player:
			player.force_leave_floor()
