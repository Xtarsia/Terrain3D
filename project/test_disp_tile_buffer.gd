@tool
extends Terrain3D

@export var set_d_buffer: bool = false :
	set(value):
		_update_process_parameters()
		var vp: SubViewport = $"../SubViewport"
		vp.size = Vector2i(mesh_size * 4 * tesselation_level, mesh_size * 4)
		RenderingServer.material_set_param(material.get_material_rid(), "_displacement_buffer", vp.get_texture().get_rid())

func _update_process_parameters() -> void:
	var d_rid: RID = $"../SubViewport/ColorRect".material.get_rid()
	RenderingServer.material_set_param(d_rid, "_tesselation_level", tesselation_level)
	RenderingServer.material_set_param(d_rid, "_camera_pos", get_snapped_position())
	RenderingServer.material_set_param(d_rid, "_mesh_size", mesh_size)
	RenderingServer.material_set_param(d_rid, "_vertex_spacing", vertex_spacing)
	RenderingServer.material_set_param(d_rid, "_vertex_density", 1.0 / vertex_spacing)
	RenderingServer.material_set_param(d_rid, "_region_size", region_size)
	RenderingServer.material_set_param(d_rid, "_region_texel_size", 1.0 / region_size)
	RenderingServer.material_set_param(d_rid, "_region_map_size", 32)
	RenderingServer.material_set_param(d_rid, "_region_map", data.get_region_map())
	RenderingServer.material_set_param(d_rid, "_region_locations", data.get_region_locations())
	RenderingServer.material_set_param(d_rid, "_height_maps", data.get_height_maps_rid())
	RenderingServer.material_set_param(d_rid, "_control_maps", data.get_control_maps_rid())
	RenderingServer.material_set_param(d_rid, "_color_maps", data.get_color_maps_rid())
	
	RenderingServer.material_set_param(d_rid, "_texture_uv_scale_array", assets.get_texture_uv_scales())
	RenderingServer.material_set_param(d_rid, "_texture_detile_array", assets.get_texture_detiles())
	RenderingServer.material_set_param(d_rid, "_texture_array_albedo", assets.get_albedo_array_rid())
	RenderingServer.material_set_param(d_rid, "_texture_array_normal", assets.get_normal_array_rid())
	RenderingServer.material_set_param(d_rid, "_texture_ao_strength_array", assets.get_texture_ao_strengths())
	RenderingServer.material_set_param(d_rid, "_texture_uv_projections", assets.get_texture_uv_projections())
	RenderingServer.material_set_param(d_rid, "_texture_color_array", assets.get_texture_colors())
	RenderingServer.material_set_param(d_rid, "_texture_roughness_mod_array", assets.get_texture_roughness_mods())
	RenderingServer.material_set_param(d_rid, "_texture_displacement_array", assets.get_texture_displacements())
	
	RenderingServer.material_set_param(d_rid, "blend_sharpness", material.blend_sharpness)

func _ready() -> void:
	set_d_buffer = true

func _physics_process(_delta: float) -> void:
	var d_rid: RID = $"../SubViewport/ColorRect".material.get_rid()
	RenderingServer.material_set_param(d_rid, "_camera_pos", get_snapped_position())
	var vp: SubViewport = $"../SubViewport"
	vp.set_update_mode(SubViewport.UPDATE_ONCE)
	RenderingServer.material_set_param(material.get_material_rid(), "_displacement_buffer_pos", get_snapped_position())
	if Engine.is_editor_hint():
		set_d_buffer = true
