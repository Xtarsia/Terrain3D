@tool
extends Node3D

@export_range(1.0, 2048.0, 1.0) var snap_step: float = 32.0
@export var lock: bool = false
@export var cam: Camera3D

func _process(delta: float) -> void:
	var mesh_size: int = 16
	var editor_cam: Camera3D = cam
	if Engine.is_editor_hint():
		editor_cam = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if not lock:
		global_position.x = round(editor_cam.global_position.x / snap_step) * snap_step
		global_position.z = round(editor_cam.global_position.z / snap_step) * snap_step
		# diff between next LOD step and current step
		var test_z = (global_position.z - round(editor_cam.global_position.z / (snap_step * 2.0)) * snap_step * 2.0) / snap_step
		var test_x = (global_position.x - round(editor_cam.global_position.x / (snap_step * 2.0)) * snap_step * 2.0) / snap_step
		var offset_a = mesh_size * 2 + 4
		var offset_b =  mesh_size * 2 + 6
		var offset_c = mesh_size * 2 + 2

		#match int(test_z):
			#-1:
				#$E1.position.z = offset_c
				#$E2.position.z = offset_a
				#
				#$C1.position.z = offset_c
				#$C2.position.z = offset_a
				#$C3.position.z = offset_c
				#$C4.position.z = offset_a
			#0: 
				#$E1.position.z = offset_c
				#$E2.position.z = -offset_a
				#
				#$C1.position.z = offset_c
				#$C2.position.z = -offset_a
				#$C3.position.z = offset_c
				#$C4.position.z = -offset_a
			#1:
				#$E1.position.z = -offset_a
				#$E2.position.z = -offset_b
				#
				#$C1.position.z = -offset_a
				#$C2.position.z = -offset_b
				#$C3.position.z = -offset_a
				#$C4.position.z = -offset_b
		#match int(test_x):
			#-1:
				#$E3.position.x = offset_c
				#$E4.position.x = offset_a
				#
				#$C1.position.x = offset_c
				#$C2.position.x = offset_a
				#$C3.position.x = offset_a
				#$C4.position.x = offset_c
			#0: 
				#$E3.position.x = offset_c
				#$E4.position.x = -offset_a
				#
				#$C1.position.x = offset_c
				#$C2.position.x = -offset_a
				#$C3.position.x = -offset_a
				#$C4.position.x = offset_c
			#1:
				#$E3.position.x = -offset_a
				#$E4.position.x = -offset_b
				#
				#$C1.position.x = -offset_a
				#$C2.position.x = -offset_b
				#$C3.position.x = -offset_b
				#$C4.position.x = -offset_a
