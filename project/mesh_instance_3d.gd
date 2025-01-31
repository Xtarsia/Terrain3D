@tool
extends MeshInstance3D

@export var generate: bool:
	set(value):
		if value:
			_generate_grid()

@export var size = Vector2i(10, 10)

func _ready():
	_generate_grid()

func _generate_grid():
	if mesh:
		mesh = null
		mesh = ArrayMesh.new()

	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var center_offset: Vector3 = Vector3(size.x / 2, 0, size.y / 2)

	for x in range(size.x):
		for y in range(size.y):
			var top_left = Vector3(x, 0, y + 1) - center_offset
			var top_right = Vector3(x + 1, 0, y + 1) - center_offset
			var bottom_left = Vector3(x, 0, y) - center_offset
			var bottom_right = Vector3(x + 1, 0, y) - center_offset
			var n = Vector3(0,1,0)
			var t = Plane(Vector3(0,1,0))

			if (x + y) % 2 == 0:
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
			else:
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

	immediate_mesh.surface_end()
	
	var surfacetool = SurfaceTool.new()
	surfacetool.create_from_arrays(immediate_mesh.surface_get_arrays(0))
	surfacetool.commit(mesh)
	
