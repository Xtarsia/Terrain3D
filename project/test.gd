@tool
extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	var cam: Camera3D = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var snap_step: float = 1.0 / 32.0
	var lod_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
	pos.x = floorf(cam.global_position.x / snap_step) * snap_step
	pos.z = floorf(cam.global_position.z / snap_step) * snap_step
	global_position = pos
