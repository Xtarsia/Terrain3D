@tool
extends Node3D

@export var grid_size: Vector2i = Vector2i(10, 10) # Number of tiles in x and z directions
@export var tile_size: int = 1 # Size of each tile
@export var regen: bool = false :
	set(value):
		regenerate_grid()
var tiles: Array = [] # Stores the tiles for repositioning
var camera: Camera3D
var last_grid_position: Vector3

func regenerate_grid() -> void:
	# Remove all existing tiles
	for tile in tiles:
		tile.queue_free()
	tiles.clear()

	# Generate a new grid
	generate_grid()
	position_grid(last_grid_position)

func _ready() -> void:
	camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	last_grid_position = get_grid_center(camera.global_transform.origin)
	generate_grid()
	position_grid(last_grid_position)

func _process(delta: float) -> void:
	if not camera:
		return

	var camera_position = camera.global_transform.origin
	var current_grid_center = get_grid_center(camera_position)

	if current_grid_center != last_grid_position:
		update_grid(current_grid_center)
		last_grid_position = current_grid_center

func generate_grid() -> void:
	for x in range(grid_size.x):
		for z in range(grid_size.y):
			var tile = create_tile()
			tiles.append(tile)
			add_child(tile)

func create_tile() -> MeshInstance3D:
	var tile = MeshInstance3D.new()
	tile.mesh = PlaneMesh.new()
	tile.mesh.size = Vector2(tile_size, tile_size)
	
	# Create a material with a random color
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(randf(), randf(), randf())
	tile.material_override = material
	return tile

func position_grid(center_position: Vector3) -> void:
	var start_x = center_position.x - (grid_size.x / 2) * tile_size
	var start_z = center_position.z - (grid_size.y / 2) * tile_size
	var i = 0
	for x in range(grid_size.x):
		for z in range(grid_size.y):
			tiles[i].position = Vector3(start_x + x * tile_size, 0, start_z + z * tile_size)
			i += 1

func update_grid(camera_position: Vector3) -> void:
	# Calculate the camera's current grid-aligned center
	var new_grid_center = get_grid_center(camera_position)
	var dx = int((new_grid_center.x - last_grid_position.x) / tile_size)
	var dz = int((new_grid_center.z - last_grid_position.z) / tile_size)

	if dx == 0 and dz == 0:
		return  # No significant movement, no update needed

	for tile in tiles:
		# Check if the tile has moved out of bounds in the x-direction
		if tile.position.x < new_grid_center.x - (grid_size.x / 2) * tile_size:
			tile.position.x += grid_size.x * tile_size  # Move to the opposite edge
		elif tile.position.x >= new_grid_center.x + (grid_size.x / 2) * tile_size:
			tile.position.x -= grid_size.x * tile_size  # Move to the opposite edge

		# Check if the tile has moved out of bounds in the z-direction
		if tile.position.z < new_grid_center.z - (grid_size.y / 2) * tile_size:
			tile.position.z += grid_size.y * tile_size  # Move to the opposite edge
		elif tile.position.z >= new_grid_center.z + (grid_size.y / 2) * tile_size:
			tile.position.z -= grid_size.y * tile_size  # Move to the opposite edge

	# Update the last grid position to the new one
	last_grid_position = new_grid_center


func get_grid_center(position: Vector3) -> Vector3:
	# Calculate the grid center based on the camera's xz position and tile size
	return Vector3(
		round(position.x / tile_size) * tile_size,
		0,
		round(position.z / tile_size) * tile_size
	)
