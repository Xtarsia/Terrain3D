@tool
extends MeshInstance3D

@export var bake_xform: bool = false :
	set(value):
		bake_transform_into_mesh()

@export var new_mesh: ArrayMesh

# Function to bake the transform into the mesh
func bake_transform_into_mesh():
	# Get the node's transform
	var g_transform: Transform3D = transform

	# Create a new ArrayMesh to store the baked mesh
	new_mesh = ArrayMesh.new()

	# Iterate over each surface of the mesh
	for surface_index in mesh.get_surface_count():
		var arrays = mesh.surface_get_arrays(surface_index).duplicate()
		
		if !arrays:
			continue

		# Extract the vertex array
		var vertices = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals = arrays[Mesh.ARRAY_NORMAL].duplicate()

		# Transform vertices and normals
		if vertices:
			for i in range(vertices.size()):
				vertices[i] *= g_transform
		print(vertices)
		# Update the arrays with transformed data
		arrays[Mesh.ARRAY_VERTEX] = vertices

		# Add the transformed surface to the new mesh
		new_mesh.add_surface_from_arrays(mesh.surface_get_primitive_type(surface_index), arrays)

	# Replace the existing mesh with the new baked mesh
	#mesh = new_mesh

	# Reset the node's transform
	#transform = Transform3D()
