@tool
extends EditorPlugin


func _enter_tree():
	add_autoload_singleton("GsqLogger", "res://addons/gdsquad/logging.gd")

func _exit_tree():
	remove_autoload_singleton("GsqLogger")
