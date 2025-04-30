@tool
extends SubViewport

@export var rect: TextureRect
@export var panel: Panel
@export var terrain: Terrain3D :
	set(value):
		terrain = value
		_update_material_uniforms()
		render_target_update_mode = SubViewport.UPDATE_ONCE

var time: int = 0

@export var source: Image :
	set(value):
		render_target_update_mode = SubViewport.UPDATE_ONCE
		print("Waiting 1 frame for viewport to render")
		time = Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		
		vp_image = get_texture().get_image()
		result = Image.create_from_data(1024, 1024, false, Image.FORMAT_RF, vp_image.get_data())
		
		vp_image.save_png("res://vp_image.png")
		time = Time.get_ticks_usec() - time
		print(float(time) / 1000000)

@export var vp_image: Image
@export var result: Image

func decode_texture_color(color: Color) -> float:
	var byte_array = PackedByteArray([
		int(color.r * 255.0),
		int(color.g * 255.0),
		int(color.b * 255.0),
		int(color.a * 255.0)
	])
	return byte_array.decode_float(0)

func _update_material_uniforms() -> void:
	if panel:
		var material: ShaderMaterial = panel.material
		if material:
			var mat_rid: RID = material.get_rid()
			if terrain and mat_rid.is_valid():
				RenderingServer.material_set_param(mat_rid, "_background_mode", terrain.material.world_background)
				RenderingServer.material_set_param(mat_rid, "_vertex_spacing", terrain.vertex_spacing)
				RenderingServer.material_set_param(mat_rid, "_vertex_density", 1.0 / terrain.vertex_spacing)
				RenderingServer.material_set_param(mat_rid, "_region_size", terrain.region_size)
				RenderingServer.material_set_param(mat_rid, "_region_texel_size", 1.0 / terrain.region_size)
				RenderingServer.material_set_param(mat_rid, "_region_map_size", 32)
				RenderingServer.material_set_param(mat_rid, "_region_map", terrain.data.get_region_map())
				RenderingServer.material_set_param(mat_rid, "_region_locations", terrain.data.get_region_locations())
				RenderingServer.material_set_param(mat_rid, "_height_maps", terrain.data.get_height_maps_rid())
				RenderingServer.material_set_param(mat_rid, "_control_maps", terrain.data.get_control_maps_rid())
				RenderingServer.material_set_param(mat_rid, "_color_maps", terrain.data.get_color_maps_rid())
