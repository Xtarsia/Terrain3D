@tool
extends MeshInstance3D

@export var build:bool : set = _build
@export var clear:bool : set = _clear

var t3d:Terrain3D
var mat:RID
var rd_instance:RID
var rd_mesh:RID
var subdiv:bool = false

func _clear(_btn:bool = false) -> void:
	RenderingServer.free_rid(rd_instance)
	RenderingServer.free_rid(rd_mesh)
	subdiv = false

func _build(_btn:bool = false) -> void:
	RenderingServer.free_rid(rd_instance)
	RenderingServer.free_rid(rd_mesh)
	t3d = get_parent()
	mat = t3d.material.get_material_rid()
	await RenderingServer.frame_post_draw
	
	var scenario:RID = get_world_3d().get_scenario()
	rd_mesh = RenderingServer.mesh_create()
	RenderingServer.mesh_add_surface_from_arrays(rd_mesh, RenderingServer.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(0))
	RenderingServer.mesh_surface_set_material(rd_mesh, 0, mat)
	rd_instance = RenderingServer.instance_create2(rd_mesh, scenario)
	RenderingServer.instance_set_extra_visibility_margin(rd_instance, 500.0)
	RenderingServer.instance_geometry_set_cast_shadows_setting(rd_instance, RenderingServer.SHADOW_CASTING_SETTING_ON)
	subdiv = true
	
func _ready():
	return
	await get_tree().create_timer(5.0).timeout
	_build(true)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta):
	if subdiv and t3d.get_camera() != null:
		var cam_pos:Vector3 = t3d.get_camera().transform.origin.floor()
		cam_pos.y = 0.0
		var t:Transform3D = Transform3D.IDENTITY
		t.origin = cam_pos
		RenderingServer.instance_set_transform(rd_instance, t)
