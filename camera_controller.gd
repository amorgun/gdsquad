@tool
class_name CameraController extends Node3D

@onready var camera: Camera3D = $camera

@export_group("Pan")
@export_range(1, 100, 1) var pan_speed := 3.
@export_range(1, 10, 0.1, "or_greater") var pan_damp_rate := 8.
@export_range(0, 10, 0.1) var pan_speed_clip := 1.

@export_group("Zoom")
@export_range(1, 100, 1) var zoom_speed := 6.
@export_range(1, 50, 1, "or_greater") var zoom_damp_rate := 4.
@export_range(0, 10, 0.1) var zoom_speed_clip := 1.
@export_range(1, 100, 1) var max_zoom_distance := 3.
@export_range(0.1, 5, 0.05) var min_zoom_distance := 0.1
@export_range(1, 100, 0.1, "or_greater") var zoom_distance: float:
	get: return camera.position.z if camera != null else 0.
	set(value):  if camera != null: camera.position.z = clampf(value, min_zoom_distance, max_zoom_distance)

@export_group("Orbit")
@export_range(1, 100, 1) var orbit_speed := 6.
@export_range(1, 50, 1, "or_greater") var orbit_speed_damp_rate := 5.
@export_range(0, 10, 0.1) var orbit_speed_clip := 1.
@export_range(-180., 180., 1, "radians_as_degrees") var min_orbit_angle
@export_range(-180., 180, 1, "radians_as_degrees") var max_orbit_angle

@export_group("Declination")
@export_range(1, 100, 1) var declination_speed := 6. 
@export_range(1, 50, 1, "or_greater") var declination_speed_damp_rate := 4.
@export_range(0, 10, 0.1) var declination_speed_clip := 1.
@export_range(-180., 180., 1, "radians_as_degrees") var min_declination_angle
@export_range(-180., 180., 1, "radians_as_degrees") var max_declination_angle

@export_group("") 
@export var process_input := true

var current_pan_speed := Vector3.ZERO
var current_zoom_speed := 0.
var current_orbit_speed := 0.
var current_declination_speed := 0.

const pan_actions: Dictionary[String, Vector3] = {
	"camera_forward": Vector3.FORWARD,
	"camera_backward": Vector3.BACK,
	"camera_left": Vector3.LEFT,
	"camera_right": Vector3.RIGHT,
}
var is_rotating := false

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	pan_update(delta)
	zoom_update(delta)
	angle_update(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not process_input:
		return
	var pan_direction := Vector3.ZERO
	for a in pan_actions:
		if event.is_action_pressed(a):
			pan_direction += pan_actions[a]
	if not pan_direction.is_zero_approx():
		current_pan_speed = pan_direction * pan_speed

	if event.is_action_pressed("camera_zoom_in"):
		current_zoom_speed = -zoom_speed
	elif event.is_action_pressed("camera_zoom_out"):
		current_zoom_speed = zoom_speed
	
	if event.is_action_pressed("camera_toggle_rotation"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		is_rotating = true
	if event.is_action_released("camera_toggle_rotation"):
		stop_rotating()
	
func _input(event: InputEvent) -> void:
	if not process_input:
		return
	if event is InputEventMouseMotion:
		update_rotation_direction(event)

func pan_update(delta: float) -> void:
	if current_pan_speed.is_zero_approx():
		return
	if process_input:
		var pan_direction := Vector3.ZERO
		for a in pan_actions:
			if Input.is_action_pressed(a):
				pan_direction += pan_actions[a]
		if not pan_direction.is_zero_approx():
			current_pan_speed = pan_direction * pan_speed

	position += delta * current_pan_speed.rotated(Vector3.UP, rotation.y)
	current_pan_speed = current_pan_speed.lerp(Vector3.ZERO, delta * pan_damp_rate)
	if current_pan_speed.length_squared() < pan_speed_clip * pan_speed_clip:
		current_pan_speed = Vector3.ZERO

func zoom_update(delta: float) -> void:
	if current_zoom_speed == 0:
		return
	zoom_distance = zoom_distance + delta * current_zoom_speed
	current_zoom_speed = lerpf(current_zoom_speed, 0., delta * zoom_damp_rate)
	if abs(current_zoom_speed) < zoom_speed_clip:
		current_zoom_speed = 0

func angle_update(delta: float) -> void:
	if not is_rotating:
		return
	
	rotation.y = clampf(rotation.y - current_orbit_speed * delta, min_orbit_angle, max_orbit_angle)
	current_orbit_speed = lerpf(current_orbit_speed, 0., delta * orbit_speed_damp_rate)
	if abs(current_orbit_speed) < orbit_speed_clip:
		current_orbit_speed = 0
	
	rotation.x = clampf(rotation.x - current_declination_speed * delta, min_declination_angle, max_declination_angle)
	current_declination_speed = lerpf(current_declination_speed, 0., delta * orbit_speed_damp_rate)
	if abs(current_declination_speed) < declination_speed_clip:
		current_declination_speed = 0

func stop_rotating() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	is_rotating = false

func update_rotation_direction(event: InputEventMouseMotion) -> void:
	if not is_rotating:
		return
	var distance := event.screen_relative
	current_orbit_speed = signf(distance.x) * orbit_speed
	current_declination_speed = signf(distance.y) * declination_speed
	
