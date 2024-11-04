@tool
extends Node3D

@export var build:bool : set = _build
@export var clear:bool : set = _clear
@export_range(1, 128) var size:int = 64 : set = _set_size
@export_range(1, 1024) var divisor:int = 384 : set = _set_divisor
@export var layer_offset: float

@export var test: bool : set = _test

var t3d:Terrain3D
var mat:RID
var rd_instance:RID
var rd_mesh:RID
var lod_mesh:PlaneMesh = PlaneMesh.new()
var subdiv:bool = false

@export var shader: ShaderMaterial = load("res://test.material")

func _test(btn: bool = false) -> void:
	var mat_rid = shader.get_rid()
	RenderingServer.material_set_param(mat_rid, "_region_size", RenderingServer.material_get_param(mat, "_region_size"))
	RenderingServer.material_set_param(mat_rid, "_region_texel_size", RenderingServer.material_get_param(mat, "_region_texel_size"))
	RenderingServer.material_set_param(mat_rid, "_vertex_spacing_size", RenderingServer.material_get_param(mat, "_vertex_spacing"))
	RenderingServer.material_set_param(mat_rid, "_vertex_density", RenderingServer.material_get_param(mat, "_vertex_density"))
	RenderingServer.material_set_param(mat_rid, "_region_map_size", RenderingServer.material_get_param(mat, "_region_map_size"))
	RenderingServer.material_set_param(mat_rid, "_region_map", RenderingServer.material_get_param(mat, "_region_map"))
	RenderingServer.material_set_param(mat_rid, "_region_locations", RenderingServer.material_get_param(mat, "_region_locations"))
	RenderingServer.material_set_param(mat_rid, "_height_maps", RenderingServer.material_get_param(mat, "_height_maps"))
	RenderingServer.material_set_param(mat_rid, "_control_maps", RenderingServer.material_get_param(mat, "_control_maps"))
	RenderingServer.material_set_param(mat_rid, "_color_maps", RenderingServer.material_get_param(mat, "_color_maps"))
	RenderingServer.material_set_param(mat_rid, "_texture_array_albedo", RenderingServer.material_get_param(mat, "_texture_array_albedo"))
	RenderingServer.material_set_param(mat_rid, "_texture_array_normal", RenderingServer.material_get_param(mat, "_texture_array_normal"))
	shader.set_shader_parameter("noise_texture", RenderingServer.material_get_param(mat, "noise_texture"))
	
	RenderingServer.material_set_param(mat_rid, "_texture_uv_scale_array", RenderingServer.material_get_param(mat, "_texture_uv_scale_array"))
	RenderingServer.material_set_param(mat_rid, "_texture_detile_array", RenderingServer.material_get_param(mat, "_texture_detile_array"))
	RenderingServer.material_set_param(mat_rid, "_texture_color_array", RenderingServer.material_get_param(mat, "_texture_color_array"))
	RenderingServer.material_set_param(mat_rid, "_background_mode", RenderingServer.material_get_param(mat, "_background_mode"))
	RenderingServer.material_set_param(mat_rid, "_mouse_layer", RenderingServer.material_get_param(mat, "_mouse_layer"))
	
	shader.set_shader_parameter("vertex_normals_distance", RenderingServer.material_get_param(mat, "vertex_normals_distance"))
	shader.set_shader_parameter("height_blending", RenderingServer.material_get_param(mat, "height_blending"))
	shader.set_shader_parameter("blend_sharpness", RenderingServer.material_get_param(mat, "blend_sharpness"))
	shader.set_shader_parameter("auto_slope", RenderingServer.material_get_param(mat, "auto_slope"))
	shader.set_shader_parameter("auto_height_reduction", RenderingServer.material_get_param(mat, "auto_height_reduction"))
	shader.set_shader_parameter("auto_base_texture", RenderingServer.material_get_param(mat, "auto_base_texture"))
	shader.set_shader_parameter("auto_overlay_texture", RenderingServer.material_get_param(mat, "auto_overlay_texture"))
	
	shader.set_shader_parameter("dual_scale_texture", RenderingServer.material_get_param(mat, "dual_scale_texture"))
	shader.set_shader_parameter("dual_scale_reduction", RenderingServer.material_get_param(mat, "dual_scale_reduction"))
	shader.set_shader_parameter("tri_scale_reduction", RenderingServer.material_get_param(mat, "tri_scale_reduction"))
	shader.set_shader_parameter("macro_variation1", RenderingServer.material_get_param(mat, "macro_variation1"))
	shader.set_shader_parameter("macro_variation2", RenderingServer.material_get_param(mat, "macro_variation2"))
	
	shader.set_shader_parameter("noise1_scale", RenderingServer.material_get_param(mat, "noise1_scale"))
	shader.set_shader_parameter("noise1_angle", RenderingServer.material_get_param(mat, "noise1_angle"))
	shader.set_shader_parameter("noise1_offset", RenderingServer.material_get_param(mat, "noise1_offset"))
	shader.set_shader_parameter("noise2_scale", RenderingServer.material_get_param(mat, "noise2_scale"))
	shader.set_shader_parameter("noise3_scale", RenderingServer.material_get_param(mat, "noise3_scale"))
	
	shader.set_shader_parameter("world_noise_region_blend", RenderingServer.material_get_param(mat, "world_noise_region_blend"))
	shader.set_shader_parameter("world_noise_max_octaves", RenderingServer.material_get_param(mat, "world_noise_max_octaves"))
	shader.set_shader_parameter("world_noise_min_octaves", RenderingServer.material_get_param(mat, "world_noise_min_octaves"))
	shader.set_shader_parameter("world_noise_lod_distance", RenderingServer.material_get_param(mat, "world_noise_lod_distance"))
	shader.set_shader_parameter("world_noise_scale", RenderingServer.material_get_param(mat, "world_noise_scale"))
	shader.set_shader_parameter("world_noise_height", RenderingServer.material_get_param(mat, "world_noise_height"))
	shader.set_shader_parameter("world_noise_offset", RenderingServer.material_get_param(mat, "world_noise_offset"))
	pass

func _set_size(s:int = 32) -> void:
	if s > 128 or s < 1:
		push_warning("Size outside of allowed range: 1 to 128")
		return
	size = s
	lod_mesh.size = Vector2(s, s)
	if subdiv:
		_build()
	return

func _set_divisor(d:int = 2) -> void:
	if d > 1024 or d < 1:
		push_warning("Divisor outside of allowed range: 1 to 1024")
		return
	divisor = d
	lod_mesh.subdivide_width = d
	lod_mesh.subdivide_depth = d
	if subdiv:
		_build()
	return

func _clear(_btn:bool = false) -> void:
	RenderingServer.free_rid(rd_instance)
	RenderingServer.free_rid(rd_mesh)
	subdiv = false

func _build(_btn:bool = false) -> void:
	_clear()
	lod_mesh.center_offset.y = layer_offset
	await RenderingServer.frame_post_draw
	
	var scenario:RID = t3d.get_world_3d().get_scenario()
	rd_mesh = RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(rd_mesh, RenderingServer.PRIMITIVE_TRIANGLES, lod_mesh.surface_get_arrays(0))
	RenderingServer.mesh_surface_set_material(rd_mesh, 0, shader.get_rid())
	rd_instance = RenderingServer.instance_create2(rd_mesh, scenario)
	RenderingServer.instance_set_extra_visibility_margin(rd_instance, 5000.0)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rd_instance, RenderingServer.SHADOW_CASTING_SETTING_ON)
	RenderingServer.instance_set_visible(rd_instance, self.visible)
	subdiv = true
	
func _ready():
	var visible_changed:Callable = func() -> void:
		RenderingServer.instance_set_visible(rd_instance, self.visible)
		return
	self.visibility_changed.connect(visible_changed)
	lod_mesh.size = Vector2(size, size)
	lod_mesh.subdivide_width = divisor
	lod_mesh.subdivide_depth = divisor
	t3d = get_parent()
	mat = t3d.material.get_material_rid()
	_test()
	_build()

func _exit_tree():
	_clear()

func _process(_delta):
	if t3d != null:
		if subdiv and t3d.get_camera() != null:
			var cam_pos:Vector3 = round(t3d.get_camera().global_transform.origin)
			cam_pos.y = 0.0
			var t:Transform3D = Transform3D.IDENTITY
			t.origin = cam_pos
			RenderingServer.instance_set_transform(rd_instance, t)
