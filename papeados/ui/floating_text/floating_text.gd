extends Node2D

@export var lifetime := 3.0
@export var float_speed :=30.0

@onready var label : Label = $Label

func _ready() -> void:
	label.text = "PAPEADO"
	
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y - 40, lifetime)
	tween.parallel().tween_property(label, "modulate:a", 0.0, lifetime)
	
	await get_tree().create_timer(lifetime).timeout
	queue_free()
