extends Node2D

@export var duration := 10.0

@onready var area: Area2D = $Area2D

func _ready() -> void:
	area.body_entered.connect(_on_area_body_entered)


func _on_area_body_entered(body: Node) -> void:
	if body is Player:
		for player in get_tree().get_nodes_in_group("players"):
			if player is Player:
				player.set_gravity_inverted(true)
				start_timer(player)

func start_timer(player: Player) -> void:
	var timer := Timer.new()
	timer.wait_time = duration
	timer.one_shot = true
	add_child(timer)

	timer.timeout.connect(func():
		if is_instance_valid(player):
			player.set_gravity_inverted(false)
		timer.queue_free()
	)

	timer.start()
