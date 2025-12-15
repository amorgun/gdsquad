class_name Model extends Node3D

@onready var skeleton: Skeleton3D = $Skeleton3D

func reset() -> void:
	for c in skeleton.get_children():
		skeleton.remove_child(c)
		c.queue_free()
