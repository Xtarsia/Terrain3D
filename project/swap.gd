@tool
extends Node3D

@export var test:bool = false :
	set(value):
		create_tiles()
@export var tile_size: int = 32 :
	set(value):
		tile_size = nearest_po2(value) if value > tile_size else nearest_po2(value / 2)
@export var grid_size: int = 16

var camera: Camera3D
var last_grid_position: Vector3 = Vector3.ZERO
var tile_div: Array[PlaneMesh]
var instances: Array[MeshInstance3D]

func generate_grid() -> void:
	for x in range(grid_size):
		for z in range(grid_size):
			var instance = MeshInstance3D.new()
			instances.append(instance)
			add_child(instance)

func position_grid(center_position: Vector3) -> void:
	var start_x = center_position.x - (grid_size / 2) * tile_size
	var start_z = center_position.z - (grid_size / 2) * tile_size
	var i = 0
	for x in range(grid_size):
		for z in range(grid_size):
			instances[i].position = Vector3(start_x + x * tile_size, 0, start_z + z * tile_size)
			i += 1
			
func update_grid(camera_position: Vector3) -> void:
	# Calculate the camera's current grid-aligned center
	var new_grid_center = Vector3(
		round(camera_position.x / tile_size) * tile_size,
		0,
		round(camera_position.z / tile_size) * tile_size
	)
	var dx = int((new_grid_center.x - last_grid_position.x) / tile_size)
	var dz = int((new_grid_center.z - last_grid_position.z) / tile_size)

	if dx == 0 and dz == 0:
		return  # No significant movement, no update needed

	for instance in instances:
		# Check if the tile has moved out of bounds in the x-direction
		if instance.position.x < new_grid_center.x - (grid_size / 2) * tile_size:
			instance.position.x += grid_size * tile_size  # Move to the opposite edge
		elif instance.position.x >= new_grid_center.x + (grid_size / 2) * tile_size:
			instance.position.x -= grid_size * tile_size  # Move to the opposite edge

		# Check if the tile has moved out of bounds in the z-direction
		if instance.position.z < new_grid_center.z - (grid_size / 2) * tile_size:
			instance.position.z += grid_size * tile_size  # Move to the opposite edge
		elif instance.position.z >= new_grid_center.z + (grid_size / 2) * tile_size:
			instance.position.z -= grid_size * tile_size  # Move to the opposite edge

	# Update the last grid position to the new one
	last_grid_position = new_grid_center

func create_tiles() -> void:
	tile_div.clear()
	var divisions: Array[int] = [tile_size - 1]
	var div:int = tile_size
	while div >  1:
		div /= 2
		divisions.append(div - 1)
	for i in range(divisions.size()):
		var mesh = PlaneMesh.new()
		mesh.size = Vector2(tile_size, tile_size)
		mesh.subdivide_depth = divisions[i]
		mesh.subdivide_width = divisions[i]
		
		var material = StandardMaterial3D.new()
		material.albedo_color = Color(randf(), randf(), randf())
		mesh.surface_set_material(0, material)
		
		tile_div.append(mesh)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	create_tiles()
	generate_grid()
	position_grid(camera.global_position.snapped(Vector3.ONE * tile_size))
	print("LOD Levels: ", tile_div.size())
	print("Max distance: ", grid_size * tile_size / 2.0)

func _process(delta: float) -> void:
	if not camera or tile_div.is_empty():
		return
	
	var camera_position: Vector3 = camera.global_transform.origin
	update_grid(camera_position)
	for instance in instances:
		var instance_position: Vector3 = instance.global_transform.origin
		var distance: float = max( 1.0, camera_position.distance_to(instance_position) - tile_size)
		
		# Calculate log2 using natural log
		var log2_distance: int = int(log(tile_size * tile_size / distance) / log(2))
		
		# Determine the level directly
		var level: int = tile_div.size() - 1 - clamp(log2_distance, 0, tile_div.size() - 1)
		
		# Assign the corresponding LOD
		instance.mesh = tile_div[level]
