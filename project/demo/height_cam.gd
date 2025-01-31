@tool
extends SubViewport

@onready var t3d: Terrain3D = get_parent()
@onready var cam: Camera3D = $Camera3D
var last_pos: Vector2 = Vector2(0,0)
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	cam.set_cull_mask(1 << (t3d.mouse_layer - 1))
	await RenderingServer.frame_post_draw
	t3d.material.texture_height_data = get_texture()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if t3d != null:
		if t3d.get_camera() != null:
			var cam_pos:Vector3 = t3d.get_camera().global_transform.origin
			var camp_pos_2d: Vector2 = Vector2(cam_pos.x, cam_pos.z)
			if last_pos.distance_to(camp_pos_2d) > 0.5:
				last_pos = camp_pos_2d
				cam.global_position.x = floor(cam_pos.x)
				cam.global_position.z = floor(cam_pos.z)
				#set_update_mode(SubViewport.UPDATE_ONCE)
