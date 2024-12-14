@tool
extends Node3D

#testing stuff
@export var player: CharacterBody3D

enum {
	TILE,
	EDGE_A,
	EDGE_B,
	TAB,
	FILL_A,
	FILL_B,
	TRIM_A,
	TRIM_B,
	HD_TILE_NEAR,
	HD_TILE_FAR
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

@export_range(16, 64, 4) var mesh_size: int = 48 : 
	set(value):
		mesh_size = clamp(value, 16, 64)
		_update_mesh_size(mesh_size)
		if value < tessellation_distance:
			tessellation_distance = value
		else:
			_generate_clipmap()

@export_range(0.25, 8.0) var vertex_scaling: float = 1.0

@export_range(0, 10, 1) var lod_levels: int = 7 : 
	set(value):
		lod_levels = clamp(value, 0, 10)
		_generate_clipmap()

@export_range(0, 32, 2) var tessellation_divisions: int = 8 :
	set(value):
		# 22 is broken force 20 or 24
		var new_value = clamp((value / 2) * 2, 0, 32)
		if new_value == 22 and tessellation_divisions < 22:
			tessellation_divisions = new_value + 2
		elif new_value == 22 and tessellation_divisions > 22:
			tessellation_divisions = new_value - 2
		else:
			tessellation_divisions = new_value
		_generate_clipmap()

@export_range(16, 32, 2) var tessellation_distance: int = 24 :
	set(value):
		tessellation_distance = clamp(value, 16, mesh_size)
		_generate_clipmap()

@export_range(0.1, 1.0, 0.1) var tessellation_depth: float = 0.5 :
	set(value):
		tessellation_depth = value
		details_mat.set_shader_parameter("tesselation_depth", tessellation_depth)
		
## When enabled adds an additional split at half the size, which halfs the vertex density
## This LOD transition is noticable at close distances. Best used with higher sizes 32m or greater.
@export var tessellation_lod_split: bool = false :
	set(value):
		tessellation_lod_split = value
		_generate_clipmap()

@export var tessellation_shadow_cast: RenderingServer.ShadowCastingSetting = RenderingServer.SHADOW_CASTING_SETTING_ON :
	set(value):
		tessellation_shadow_cast = value
		_generate_clipmap()

## TODO still has problems, snap value has to be doubled to work with blending
## which breaks the current layout, maybe fixable in vertex().
@export var symetric_mesh: bool = false :
	set(value):
		symetric_mesh = value
		_generate_clipmap()

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

# Mesh position data updated on size set
# LOD0 only
var trim_a_pos: Array[Vector3] = []
var trim_b_pos: Array[Vector3] = []
var tile_pos_lod_0: Array[Vector3] = []
var hd_tile_pos: Array[Vector3] = []
# LOD1+
var fill_a_pos: Array[Vector3] = []
var fill_b_pos: Array[Vector3] = []
var tile_pos: Array[Vector3] = []
# All LOD Levels
var offset_a: int = 0
var offset_b: int = 0
var offset_c: int = 0
var edge_pos: Array[Vector3] = []
var tab_pos_x: Array[Vector3] = []
var tab_pos_z: Array[Vector3] = []

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
	tab_pos_x = [
		Vector3(offset_c, offset_c, -offset_a),
		Vector3(offset_a, -offset_a, -offset_b),
		Vector3(offset_a, -offset_a, -offset_b),
		Vector3(offset_c, offset_c, -offset_a)
	]
	tab_pos_z = [
		Vector3(offset_c, offset_c, -offset_a),
		Vector3(offset_a, -offset_a, -offset_b),
		Vector3(offset_c, offset_c, -offset_a),
		Vector3(offset_a, -offset_a, -offset_b)
	]
	fill_a_pos = [
		Vector3(size - 2, 0, -size * 2 - 2),
		Vector3(-size - 2, 0, size + 2)
	]
	fill_b_pos = [
		Vector3(size + 2, 0, size - 2),
		Vector3(-size * 2 - 2, 0, -size - 2)
	]
	
	hd_tile_pos = []
	for x in size:
		for y in size:
			var pos: Vector3 = Vector3(x * 2.0 - size, 0.0, y * 2.0 - size)
			hd_tile_pos.append(pos)
	_position_arrays_init = true


func _clear_clipmap_rids() -> void:
	for l in _lod_rids.size():
		for m in _lod_rids[l].size():
			for i in _lod_rids[l][m].size():
				RenderingServer.free_rid(_lod_rids[l][m][i])
	_lod_rids.clear()


func _generate_clipmap() -> void:
	if !is_inside_tree():
		return
	if _position_arrays_init == false:
		_update_mesh_size(mesh_size)
	scenario = get_world_3d().scenario
	_array_meshs.clear()
	# Create initial set of Mesh blocks to build the clipmap
	# 0 Tile - mesh_size x mesh_size tiles
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size, mesh_size), symetric_mesh))
	# 1 EdgeA - 2 x (mesh_size * 4 + 4) strips to bridge LOD transitions along Z axis
	_array_meshs.append(_generate_mesh(Vector2i(2, mesh_size * 4 + 4), symetric_mesh))
	# 2 EdgeB - (mesh_size * 4 + 4) x 2 strips to bridge LOD transitions along X asis
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size * 4 + 4, 2), symetric_mesh))
	# 3 Tab - 2 x 2 corner tabs to bridge corner LOD transitions
	_array_meshs.append(_generate_mesh(Vector2i(2, 2), symetric_mesh))
	# 4 FillA - 4 x mesh_size
	_array_meshs.append(_generate_mesh(Vector2i(4, mesh_size), symetric_mesh))
	# 5 FillB - mesh_size x 4
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size, 4), symetric_mesh))
	# 6 TrimA - 2 x (mesh_size * 4 + 2) strips for LOD0 Z axis edge
	_array_meshs.append(_generate_mesh(Vector2i(2, mesh_size * 4 + 2), symetric_mesh))
	# 7 TrimB - (mesh_size * 4 + 4) x 2 strips for LOD0 X axis edge
	_array_meshs.append(_generate_mesh(Vector2i(mesh_size * 4 + 2, 2), symetric_mesh))
	
	var symetric_detail: bool = symetric_mesh #(tessellation == tessellation.DISABLED && symetric_mesh or tessellation != tessellation.DISABLED)
	# 8 HD_TILE_NEAR - 2 x 2 tile
	_array_meshs.append(_generate_mesh(Vector2i(2, 2), symetric_detail, max(tessellation_divisions, 1)))
	# 9 HD_TILE_FAR - 2 x 2 tile
	_array_meshs.append(_generate_mesh(Vector2i(2, 2), symetric_detail, max(tessellation_divisions / 2, 1)))
	
	_clear_clipmap_rids()
	
	# Setup RenderingServer instances for each LOD level
	var aabb: AABB
	for level in lod_levels + 1:
		var lod: Array[Array] = []
		# Tiles, 12 
		var tile_rids: Array[RID] = []
		aabb = _array_meshs[TILE].get_aabb()
		aabb.position.y = -cull_margin
		aabb.size.y = cull_margin * 2.0
		var lod_zero_tiles: int = 16 if level == 0  and tessellation_divisions == 0 else 12
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
		
		var tab_rids: Array[RID] = []
		aabb = _array_meshs[TAB].get_aabb()
		aabb.position.y = -cull_margin
		aabb.size.y = cull_margin * 2.0
		for i in 4:
			tab_rids.append(RenderingServer.instance_create2(_array_meshs[TAB].get_rid(), scenario))
			RenderingServer.instance_set_custom_aabb(tab_rids[i], aabb);
			RenderingServer.instance_set_layer_mask(tab_rids[i], t3d.render_layers)
		lod.append(tab_rids) # index 3 TAB
		
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
		
		# Trims & HD_Tiles are only present on level 0 we do not need to add blanks as these are indexed last
		if level == 0:
			var trim_a_rids: Array[RID] = []
			aabb = _array_meshs[TRIM_A].get_aabb()
			## TODO set aabb to 4m(?) fixed bounds once positioned along y during snap update
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
			
			if tessellation_divisions != 0:
				var hd_tile_rids: Array[RID] = []
				aabb = _array_meshs[TAB].get_aabb()
				aabb.position.y = -8.0#-cull_margin
				aabb.size.y = 16.0#cull_margin * 2.0
				for i in hd_tile_pos.size():
					# Tiles outside the tessellation area are populated with TABs.
					var tile_type: int = HD_TILE_NEAR
					var shadow: int = tessellation_shadow_cast
					var tile_dist: float = Vector2(hd_tile_pos[i].x, hd_tile_pos[i].z).length()
					if tessellation_lod_split and tessellation_divisions >= 4:
						if tile_dist < min(tessellation_distance / 2, mesh_size):
							tile_type = HD_TILE_NEAR
						elif tile_dist < min(tessellation_distance, mesh_size):
							tile_type = HD_TILE_FAR
							#shadow = RenderingServer.SHADOW_CASTING_SETTING_ON
						else:
							tile_type = TAB
							shadow = RenderingServer.SHADOW_CASTING_SETTING_ON
					elif tile_dist < min(tessellation_distance, mesh_size):
						tile_type = HD_TILE_NEAR
					else:
						tile_type = TAB
						shadow = RenderingServer.SHADOW_CASTING_SETTING_ON
					hd_tile_rids.append(RenderingServer.instance_create2(_array_meshs[tile_type].get_rid(), scenario))
					RenderingServer.instance_set_custom_aabb(hd_tile_rids[i], aabb);
					RenderingServer.instance_geometry_set_cast_shadows_setting(hd_tile_rids[i], shadow)
					RenderingServer.instance_set_layer_mask(hd_tile_rids[i], t3d.render_layers)
				lod.append(hd_tile_rids)
			
		# append lod to lod_rids arrays
		_lod_rids.append(lod)
	
	# update shader with new mesh size
	terrain_mat.set_shader_parameter("mesh_size", mesh_size + 1)
	details_mat.set_shader_parameter("mesh_size", min(tessellation_distance, mesh_size) - 4.0)
	if tessellation_lod_split and tessellation_divisions >= 4:
		details_mat.set_shader_parameter("tile_div", max(tessellation_divisions / 2, 1))
	else:
		details_mat.set_shader_parameter("tile_div", max(tessellation_divisions, 1))
	# force a snap update next frame
	update = true
	#t3d.hide()


func _generate_mesh(size: Vector2i, symetric: bool = false, divisions: int = 1) -> ArrayMesh:
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
			
			if (x + y) % 2 == 0 or not symetric:
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


func _process(_delta: float) -> void:
	var active_cam: Camera3D = t3d.get_camera()
	if active_cam == null:
		return
	RenderingServer.global_shader_parameter_set("main_camera_position", active_cam.global_position)
	RenderingServer.global_shader_parameter_set("player_position", player.global_position)
	#_update_shadar_parameters()
	
	# Updating the camera position is required every frame, as the built in value
	# gets set to the light position during the shadow pass, which causes tessellation
	# to be incorrectly calculated for the shadow pass.
	terrain_mat.set_shader_parameter("camera_pos", active_cam.global_position)
	details_mat.set_shader_parameter("camera_pos", active_cam.global_position)
	# Snap terrain to new position
	if active_cam.global_position.distance_to(last_cam_pos) > 1.0 * vertex_scaling or update:
		update = false
		last_cam_pos = active_cam.global_position
		# edge and corner offsets updated every snap
		var pos: Vector3 = Vector3(0.0, 0.0, 0.0)
		for lod in _lod_rids.size():
			# Snap instance transforms
			var snap_step: float = pow(2.0, lod + 1.0) * vertex_scaling
			var lod_scale: Vector3 = Vector3(pow(2, lod) * vertex_scaling, 1.0, pow(2, lod) * vertex_scaling)
			pos.x = floorf(active_cam.global_position.x / snap_step) * snap_step
			pos.z = floorf(active_cam.global_position.z / snap_step) * snap_step
			#if lod == 0:
				#details_mat.set_shader_parameter("snap_pos", pos + Vector3(1.0, 0.0, 1.0))
			# Reposition edge strips and corner tabs [0, 1, 2]
			var test_x: int = clampi((pos.x - floorf(active_cam.global_position.x
				/ (snap_step * 2.0)) * snap_step * 2.0) / snap_step + 1, 0, 2)
			var test_z: int = clampi((pos.z - floorf(active_cam.global_position.z
				/ (snap_step * 2.0)) * snap_step * 2.0) / snap_step + 1, 0, 2)
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
							t.origin.z -= offset_c
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
					TAB:
						for instance in _lod_rids[lod][TAB].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin.x = tab_pos_x[instance][test_x]
							t.origin.z = tab_pos_z[instance][test_z]
							t = t.scaled(lod_scale)
							t.origin += pos
							RenderingServer.instance_set_transform(_lod_rids[lod][TAB][instance], t)
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
					HD_TILE_NEAR: # near, far and tabs stored in the same array.
						for instance in _lod_rids[lod][HD_TILE_NEAR].size():
							var t: Transform3D = Transform3D.IDENTITY
							t.origin = hd_tile_pos[instance]
							t = t.scaled(lod_scale)
							t.origin += pos
							var height: float = t3d.data.get_height(t.origin + Vector3(1.0, 0.0, 1.0))
							t.origin.y = height if !is_nan(height) else active_cam.global_position.y
							RenderingServer.instance_set_transform(_lod_rids[lod][HD_TILE_NEAR][instance], t)
					_:
						pass

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
