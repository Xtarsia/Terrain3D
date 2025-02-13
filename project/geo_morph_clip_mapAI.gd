@tool
extends Node3D

@export var player: CharacterBody3D

enum {
	TILE,
	EDGE_A,
	EDGE_B,
	FILL_A,
	FILL_B,
	TRIM_A,
	TRIM_B,
	HD_TILE_NEAR,
	HD_TILE_FAR
}

enum grid_mode {
	DIAGONAL,
	ALTERNATING,
	SYMETRIC
}

@export var create: bool = false :
	set(value):
		_generate_clipmap()
		_update_shadar_parameters()
@export var destroy: bool = false :
	set(value):
		_exit_tree()

@export var t3d: Terrain3D
@export var update_shaders: bool = false : set = _update_shadar_parameters
@export var terrain_mat: ShaderMaterial
@export var details_mat: ShaderMaterial

@export_range(16, 128, 4) var mesh_size: int = 48 : 
	set(value):
		mesh_size = clamp(value, 16, 128)
		_update_mesh_size(mesh_size)
		_generate_clipmap()

# this is seperate from actual vertex scaling at the moment
@export_range(0.0078125, 2.0) var mesh_density: float = 1.0 :
	set(value):
		mesh_density = roundf(value * 128.0) / 128.0
		update = true

@export_range(0, 16, 1) var lod_levels: int = 7 : 
	set(value):
		lod_levels = clamp(value, 0, 16)
		_generate_clipmap()

@export var mesh_mode: grid_mode = grid_mode.DIAGONAL :
	set(value):
		mesh_mode = value
		_generate_clipmap()
		terrain_mat.set_shader_parameter("mode", value)

@export var cull_margin: float = 200.0 :
	set(value):
		cull_margin = value
		_generate_clipmap()

var last_cam_pos: Vector3 = Vector3()
var update: bool = false
var _array_meshs: Array[ArrayMesh] = []
var scenario: RID
# RID = _lod_rids[lod][TYPE][instance]
var _lod_rids: Array[Array] = []

func _clear_clipmap_rids() -> void:
	for l in _lod_rids.size():
		for m in _lod_rids[l].size():
			for i in _lod_rids[l][m].size():
				RenderingServer.free_rid(_lod_rids[l][m][i])
	_lod_rids.clear()

var mesh_positions: Array[Array]
# Mesh position data updated on size set
# LOD0 only
var trim_a_pos: Array[Vector3] = []
var trim_b_pos: Array[Vector3] = []
var tile_pos_lod_0: Array[Vector3] = []

# LOD1+
var fill_a_pos: Array[Vector3] = []
var fill_b_pos: Array[Vector3] = []
var tile_pos: Array[Vector3] = []
# All LOD Levels
var offset_a: int = 0
var offset_b: int = 0
var offset_c: int = 0
var edge_pos: Array[Vector3] = []

var _position_arrays_init = false

func _update_mesh_size(size: int) -> void:
	tile_pos_lod_0 = [
		Vector3(0, 0, size),
		Vector3(size, 0, size),
		Vector3(size, 0, 0),
		Vector3(size, 0, -size),
		Vector3(size, 0, -size * 2),
		Vector3(0, 0, -size * 2),
		Vector3(-size, 0, -size * 2),
		Vector3(-size * 2, 0, -size * 2),
		Vector3(-size * 2, 0, -size),
		Vector3(-size * 2, 0, 0),
		Vector3(-size * 2, 0, size),
		Vector3(-size, 0, size),
		#inner tiles
		Vector3(0, 0, 0),
		Vector3(-size, 0, 0),
		Vector3(0, 0, -size),
		Vector3(-size, 0, -size)
	]
	tile_pos = [
		Vector3(2, 0, size + 2),
		Vector3(size + 2, 0, size + 2),
		Vector3(size + 2, 0, -2),
		Vector3(size + 2, 0, -size - 2),
		Vector3(size + 2, 0, -size * 2 -2),
		Vector3(-2, 0, -size * 2 - 2),
		Vector3(-size - 2, 0, -size * 2 - 2),
		Vector3(-size * 2 - 2, 0, -size * 2 - 2),
		Vector3(-size * 2 - 2, 0, -size + 2),
		Vector3(-size * 2 - 2, 0, +2),
		Vector3(-size * 2 - 2, 0, size + 2),
		Vector3(-size + 2, 0, size + 2),
	]
	trim_a_pos = [
		Vector3(size * 2, 0, -size * 2),
		Vector3(-size * 2 - 2, 0, -size * 2 - 2)
	]
	trim_b_pos = [
		Vector3(-size * 2, 0, -size * 2 - 2),
		Vector3(-size * 2 - 2, 0, size * 2)
	]
	
	offset_a = size * 2 + 4
	offset_b =  size * 2 + 6
	offset_c = size * 2 + 2
	
	edge_pos = [
		Vector3(offset_c, offset_c,-offset_a),
		Vector3(offset_a, -offset_a ,-offset_b)
	]
	fill_a_pos = [
		Vector3(size - 2, 0, -size * 2 - 2),
		Vector3(-size - 2, 0, size + 2)
	]
	fill_b_pos = [
		Vector3(size + 2, 0, size - 2),
		Vector3(-size * 2 - 2, 0, -size - 2)
	]
	
	_position_arrays_init = true

func _generate_clipmap() -> void:
	if !is_inside_tree():
		return
	_update_mesh_size(mesh_size)
	_clear_clipmap_rids()
	_array_meshs.clear()
	# Create initial set of Mesh blocks to build the clipmap
	# 0 Tile - mesh_size x mesh_size tiles
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size, mesh_size), mesh_mode))
	# 1 EdgeA - 2 x (mesh_size * 4 + 8) strips to bridge LOD transitions along Z axis
	_array_meshs.append(_generate_mesh(Vector2i(2, mesh_size * 4 + 8), mesh_mode))
	# 2 EdgeB - (mesh_size * 4 + 4) x 2 strips to bridge LOD transitions along X asis
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size * 4 + 4, 2), mesh_mode))
	# 3 FillA - 4 x mesh_size
	_array_meshs.append(_generate_mesh(Vector2i(4, mesh_size), mesh_mode))
	# 4 FillB - mesh_size x 4
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size, 4), mesh_mode))
	# 5 TrimA - 2 x (mesh_size * 4 + 2) strips for LOD0 Z axis edge
	_array_meshs.append(_generate_mesh(Vector2i(2, mesh_size * 4 + 2), mesh_mode))
	# 6 TrimB - (mesh_size * 4 + 4) x 2 strips for LOD0 X axis edge
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size * 4 + 2, 2), mesh_mode))
	
	# Setup RenderingServer instances for each LOD level
	scenario = get_world_3d().scenario
	var aabb: AABB
	for level in lod_levels + 1:
		var lod: Array[Array] = []
		# Tiles, 12 
		var tile_rids: Array[RID] = []
		aabb = _array_meshs[TILE].get_aabb()
		aabb.position.y = -cull_margin
		aabb.size.y = cull_margin * 2.0
		var lod_zero_tiles: int = 16 if level == 0 else 12
		for i in lod_zero_tiles:
			tile_rids.append(RenderingServer.instance_create2(_array_meshs[TILE].get_rid(), scenario))
			RenderingServer.instance_set_custom_aabb(tile_rids[i], aabb);
			RenderingServer.instance_set_layer_mask(tile_rids[i], t3d.render_layers)
		lod.append(tile_rids) # index 0 TILE
		
		# 4 Edges and 4 Tabs present on all levels
		var edge_a_rids: Array[RID] = []
		aabb = _array_meshs[EDGE_A].get_aabb()
		aabb.position.y = -cull_margin
		aabb.size.y = cull_margin * 2.0
		for i in 2:
			edge_a_rids.append(RenderingServer.instance_create2(_array_meshs[EDGE_A].get_rid(), scenario))
			RenderingServer.instance_set_custom_aabb(edge_a_rids[i], aabb);
			RenderingServer.instance_set_layer_mask(edge_a_rids[i], t3d.render_layers)
		lod.append(edge_a_rids) # index 1 EDGE_A
		
		var edge_b_rids: Array[RID] = []
		aabb = _array_meshs[EDGE_B].get_aabb()
		aabb.position.y = -cull_margin
		aabb.size.y = cull_margin * 2.0
		for i in 2:
			edge_b_rids.append(RenderingServer.instance_create2(_array_meshs[EDGE_B].get_rid(), scenario))
			RenderingServer.instance_set_custom_aabb(edge_b_rids[i], aabb);
			RenderingServer.instance_set_layer_mask(edge_b_rids[i], t3d.render_layers)
		lod.append(edge_b_rids) # index 2 EDGE_B
		
		# Fillers only present on levels 1+ blank arrays must be added to
		# level 0 to ensure correct indexing when updating positions.
		if level > 0:
			var fill_a_rids: Array[RID] = []
			aabb = _array_meshs[FILL_A].get_aabb()
			aabb.position.y = -cull_margin
			aabb.size.y = cull_margin * 2.0
			for i in 2:
				fill_a_rids.append(RenderingServer.instance_create2(_array_meshs[FILL_A].get_rid(), scenario))
				RenderingServer.instance_set_custom_aabb(fill_a_rids[i], aabb);
				RenderingServer.instance_set_layer_mask(fill_a_rids[i], t3d.render_layers)
			lod.append(fill_a_rids) # index 4 FILL_A
			
			var fill_b_rids: Array[RID] = []
			aabb = _array_meshs[FILL_B].get_aabb()
			aabb.position.y = -cull_margin
			aabb.size.y = cull_margin * 2.0
			for i in 2:
				fill_b_rids.append(RenderingServer.instance_create2(_array_meshs[FILL_B].get_rid(), scenario))
				RenderingServer.instance_set_custom_aabb(fill_b_rids[i], aabb);
				RenderingServer.instance_set_layer_mask(fill_b_rids[i], t3d.render_layers)
			lod.append(fill_b_rids) # index 5 FILL_B
		else:
			lod.append([RID(),RID()]) # index 4 FILL_A
			lod.append([RID(),RID()]) # index 5 FILL_B
		
		# Trims are only present on level 0 we do not need to add blanks as these are indexed last
		if level == 0:
			var trim_a_rids: Array[RID] = []
			aabb = _array_meshs[TRIM_A].get_aabb()
			aabb.position.y = -cull_margin
			aabb.size.y = cull_margin * 2.0
			for i in 2:
				trim_a_rids.append(RenderingServer.instance_create2(_array_meshs[TRIM_A].get_rid(), scenario))
				RenderingServer.instance_set_custom_aabb(trim_a_rids[i], aabb);
				RenderingServer.instance_set_layer_mask(trim_a_rids[i], t3d.render_layers)
			lod.append(trim_a_rids)  # index 6 TRIM_A
			
			var trim_b_rids: Array[RID] = []
			aabb = _array_meshs[TRIM_B].get_aabb()
			aabb.position.y = -cull_margin
			aabb.size.y = cull_margin * 2.0
			for i in 2:
				trim_b_rids.append(RenderingServer.instance_create2(_array_meshs[TRIM_B].get_rid(), scenario))
				RenderingServer.instance_set_custom_aabb(trim_b_rids[i], aabb);
				RenderingServer.instance_set_layer_mask(trim_b_rids[i], t3d.render_layers)
			lod.append(trim_b_rids)  # index 7 TRIM_A
			
		# append lod to lod_rids arrays
		_lod_rids.append(lod)
	
	# update shader with new mesh size
	terrain_mat.set_shader_parameter("mesh_size", mesh_size + 2)

	# force a snap update next frame
	update = true
	#t3d.hide()

func _process(delta: float) -> void:
	#if not update:
		#update = false
		#return
	var active_cam: Camera3D = t3d.get_camera()
	if active_cam == null:
		return
	var tracked_pos: Vector3 = active_cam.global_position
	RenderingServer.global_shader_parameter_set("main_camera_position", tracked_pos)
	#_update_shadar_parameters()
	
	# Updating the camera position is required every frame, as the built in value
	# gets set to the light position during the shadow pass, which causes tessellation
	# to be incorrectly calculated for the shadow pass.
	terrain_mat.set_shader_parameter("camera_pos", tracked_pos)
	#details_mat.set_shader_parameter("camera_pos", tracked_pos)
	# Snap terrain to new position
	if tracked_pos.distance_to(last_cam_pos) > 1.0 * mesh_density or update:
		update = false
		last_cam_pos = tracked_pos
		var pos: Vector3 = Vector3(0.0, 0.0, 0.0)
		for lod in _lod_rids.size():
			var snap_step: float = pow(2.0, lod + 1.0) * mesh_density
			var lod_scale: Vector3 = Vector3(pow(2, lod) * mesh_density, 1.0, pow(2, lod) * mesh_density)
			
			# Snap pos.xz
			var cam_x: float = tracked_pos.x
			var cam_z: float = tracked_pos.z
			pos.x = roundf(cam_x / snap_step) * snap_step
			pos.z = roundf(cam_z / snap_step) * snap_step
			
			# test_x and test_z for edge strip positions
			var half_snap_step: float = snap_step * 2.0
			var aligned_x: float = roundf(cam_x / half_snap_step) * half_snap_step
			var aligned_z: float = roundf(cam_z / half_snap_step) * half_snap_step
			var test_x: int = clampi(int((pos.x - aligned_x) / snap_step) + 1, 0, 2)
			var test_z: int = clampi(int((pos.z - aligned_z) / snap_step) + 1, 0, 2)
			for mesh in _lod_rids[lod].size():
				match mesh:
					TILE:
						for instance in _lod_rids[lod][TILE].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin = tile_pos_lod_0[instance] if lod == 0 else tile_pos[instance]
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][TILE][instance], t)
					EDGE_A:
						for instance in _lod_rids[lod][EDGE_A].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin.z -= offset_c + (test_z * 2.0)
							t.origin.x = edge_pos[instance][test_x]
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][EDGE_A][instance], t)
					EDGE_B:
						for instance in _lod_rids[lod][EDGE_B].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin.z = edge_pos[instance][test_z]
							t.origin.x -= offset_c
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][EDGE_B][instance], t)
					FILL_A:
						if lod > 0:
							for instance in _lod_rids[lod][FILL_A].size():
								var t: Transform3D = Transform3D.IDENTITY
								t.origin = fill_a_pos[instance]
								t = t.scaled(lod_scale)
								t.origin += pos
								RenderingServer.instance_set_transform(_lod_rids[lod][FILL_A][instance], t)
					FILL_B:
						if lod > 0:
							for instance in _lod_rids[lod][FILL_B].size():
								var t: Transform3D = Transform3D.IDENTITY
								t.origin = fill_b_pos[instance]
								t = t.scaled(lod_scale)
								t.origin += pos
								RenderingServer.instance_set_transform(_lod_rids[lod][FILL_B][instance], t)
					# LOD 0 only
					TRIM_A:
						for instance in _lod_rids[lod][TRIM_A].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin = trim_a_pos[instance]
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][TRIM_A][instance], t)
					TRIM_B:
						for instance in _lod_rids[lod][TRIM_B].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin = trim_b_pos[instance]
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][TRIM_B][instance], t)
					_:
						pass

func _generate_mesh(size: Vector2i, mode: grid_mode = grid_mode.DIAGONAL, divisions: int = 1) -> ArrayMesh:
	var immediate_mesh: ImmediateMesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: Vector3 = Vector3(0,1,0)
	var t: Plane = Plane(Vector3(0,1,0))
	for x in range(size.x * divisions):
		for y in range(size.y * divisions):
			var top_left: Vector3 = Vector3(x, 0, y + 1) / divisions
			var top_right: Vector3 = Vector3(x + 1, 0, y + 1) / divisions
			var bottom_left: Vector3 = Vector3(x, 0, y) / divisions
			var bottom_right: Vector3 = Vector3(x + 1, 0, y) / divisions
			
			# midpoint symetric
			if mode == grid_mode.SYMETRIC:
				var center: Vector3 = (top_left + top_right + bottom_left + bottom_right) / 4.0
				
				# Triangle 1: bottom_left, bottom_right, center
				immediate_mesh.surface_set_uv(Vector2(bottom_left.x, bottom_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_left)
				
				immediate_mesh.surface_set_uv(Vector2(bottom_right.x, bottom_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_right)
				
				immediate_mesh.surface_set_uv(Vector2(center.x, center.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(center)
				
				# Triangle 2: bottom_right, top_right, center
				immediate_mesh.surface_set_uv(Vector2(bottom_right.x, bottom_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_right)
				
				immediate_mesh.surface_set_uv(Vector2(top_right.x, top_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_right)
				
				immediate_mesh.surface_set_uv(Vector2(center.x, center.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(center)
				
				# Triangle 3: top_right, top_left, center
				immediate_mesh.surface_set_uv(Vector2(top_right.x, top_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_right)
				
				immediate_mesh.surface_set_uv(Vector2(top_left.x, top_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_left)
				
				immediate_mesh.surface_set_uv(Vector2(center.x, center.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(center)
				
				# Triangle 4: top_left, bottom_left, center
				immediate_mesh.surface_set_uv(Vector2(top_left.x, top_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_left)
				
				immediate_mesh.surface_set_uv(Vector2(bottom_left.x, bottom_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_left)
				
				immediate_mesh.surface_set_uv(Vector2(center.x, center.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(center)
			elif (x + y) % 2 == 0 or not mode == grid_mode.ALTERNATING:
				immediate_mesh.surface_set_uv(Vector2(bottom_left.x,bottom_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_left)
				immediate_mesh.surface_set_uv(Vector2(bottom_right.x,bottom_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_right)
				immediate_mesh.surface_set_uv(Vector2(top_left.x,top_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_left)
				
				immediate_mesh.surface_set_uv(Vector2(top_left.x,top_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_left)
				immediate_mesh.surface_set_uv(Vector2(bottom_right.x,bottom_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_right)
				immediate_mesh.surface_set_uv(Vector2(top_right.x,top_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_right)
			else:
				immediate_mesh.surface_set_uv(Vector2(bottom_left.x,bottom_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_left)
				immediate_mesh.surface_set_uv(Vector2(top_right.x,top_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_right)
				immediate_mesh.surface_set_uv(Vector2(top_left.x,top_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_left)
				
				immediate_mesh.surface_set_uv(Vector2(bottom_left.x,bottom_left.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_left)
				immediate_mesh.surface_set_uv(Vector2(bottom_right.x,bottom_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(bottom_right)
				immediate_mesh.surface_set_uv(Vector2(top_right.x,top_right.z))
				immediate_mesh.surface_set_normal(n)
				immediate_mesh.surface_set_tangent(t)
				immediate_mesh.surface_add_vertex(top_right)
	immediate_mesh.surface_end()
	
	var surfacetool = SurfaceTool.new()
	surfacetool.create_from_arrays(immediate_mesh.surface_get_arrays(0))
	var mesh: ArrayMesh = ArrayMesh.new()
	surfacetool.commit(mesh)
	if divisions > 1:
		mesh.surface_set_material(0, details_mat)
	else:
		mesh.surface_set_material(0, terrain_mat)
	return mesh

func _ready() -> void:
	await RenderingServer.frame_post_draw
	_generate_clipmap()
	_update_shadar_parameters()


func _exit_tree() -> void:
	_clear_clipmap_rids()

func _update_shadar_parameters(_btn: bool = false) -> void:
	if t3d is not Terrain3D:
		return
	var t3d_mat: RID = t3d.material.get_material_rid()
	var params: Array[String] = ["_region_size","_region_texel_size","_vertex_spacing","_vertex_density",
		"_region_map_size","_region_map","_region_locations","_height_maps","_control_maps","_color_maps",
		"_texture_array_albedo","_texture_array_normal","noise_texture","_texture_uv_scale_array",
		"_texture_detile_array","_texture_color_array","_background_mode","_mouse_layer","vertex_normals_distance",
		"height_blending","blend_sharpness","auto_slope","auto_height_reduction","auto_base_texture",
		"auto_overlay_texture","dual_scale_texture","dual_scale_reduction","tri_scale_reduction","dual_scale_far",
		"dual_scale_near","macro_variation1","macro_variation2","noise1_scale","noise1_angle","noise1_offset",
		"noise2_scale","noise3_scale","world_noise_region_blend","world_noise_max_octaves","world_noise_min_octaves",
		"world_noise_lod_distance","world_noise_scale","world_noise_height","world_noise_offset"]
	var param_values: Array[Variant]
	for p in params.size():
		param_values.append(RenderingServer.material_get_param(t3d_mat, params[p]))
	for v in param_values.size():
		RenderingServer.material_set_param(terrain_mat.get_rid(), params[v], param_values[v])
		RenderingServer.material_set_param(details_mat.get_rid(), params[v], param_values[v])
