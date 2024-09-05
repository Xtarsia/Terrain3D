@tool
extends Node3D

@export var build:bool : set = _build
@export var clear:bool : set = _clear
@export_range(8, 128) var size:int = 32 : set = _set_size
@export_range(16, 1024) var divisor:int = 256 : set = _set_divisor

var t3d:Terrain3D
var mat:RID
var rd_instance:RID
var rd_mesh:RID
var lod_mesh:PlaneMesh = PlaneMesh.new()
var subdiv:bool = false

func _set_size(s:int = 32) -> void:
	if s > 128 or s < 8:
		push_warning("Size outside of allowed range: 8 to 128")
		return
	size = s
	lod_mesh.size = Vector2(s, s)
	if subdiv:
		_build()
	return

func _set_divisor(d:int = 2) -> void:
	if d > 1024 or d < 16:
		push_warning("Divisor outside of allowed range: 16 to 1024")
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
	await RenderingServer.frame_post_draw
	mat = t3d.material.get_material_rid()
	
	var scenario:RID = t3d.get_world_3d().get_scenario()
	rd_mesh = RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(rd_mesh, RenderingServer.PRIMITIVE_TRIANGLES, lod_mesh.surface_get_arrays(0))
	RenderingServer.mesh_surface_set_material(rd_mesh, 0, mat)
	rd_instance = RenderingServer.instance_create2(rd_mesh, scenario)
	RenderingServer.instance_set_extra_visibility_margin(rd_instance, 500.0)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rd_instance, RenderingServer.SHADOW_CASTING_SETTING_ON)
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
	_build()

func _exit_tree():
	_clear()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	# and !Engine.is_editor_hint()
	if t3d != null:
		if subdiv and t3d.get_camera() != null:
			var cam_pos:Vector3 = t3d.get_camera().transform.origin
			cam_pos += -t3d.get_camera().transform.basis.z * min(size * 0.5, abs(cam_pos.y - t3d.storage.get_height(cam_pos)) * 2.0)
			cam_pos.y = 0.0
			var t:Transform3D = Transform3D.IDENTITY
			t.origin = cam_pos.round()
			RenderingServer.instance_set_transform(rd_instance, t)
