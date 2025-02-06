@tool
extends Terrain3D

@export var source: Image

# custom mipmap
@export var halfmap: bool :
	set(value):
		var dest: Image = Image.create(source.get_height() / 2, source.get_width() / 2, false, Image.FORMAT_RF)
		for block_y in range(0, source.get_height(), 2):
			for block_x in range(0, source.get_width(), 2):
				var px: Array[float] = []
				for y in range(2):
					for x in range(2):
						px.append(source.get_pixel(block_y + y, block_x + x).r)
				dest.set_pixel(block_y / 2, block_x / 2, Color(px.max(), 0.0, 0.0, 1.0))
		mipmap = dest
@export var mipmap: Image


@export var compress: bool :
	set(value):
		var time : int = Time.get_ticks_usec()
		# for bitpacking back into float
		var util: Terrain3DUtil = Terrain3DUtil.new()
		var compressed: Image = Image.create(source.get_width() / 2, source.get_height() / 2, false, Image.FORMAT_RF)
		# Iterate over each 4x4 set of pixels
		var block_count: int = 0
		var height_4x4: Array[float] = []
		height_4x4.resize(16)
		var indices: Array[int] = []
		indices.resize(16)
		for block_y in range(0, source.get_height(), 4):
			for block_x in range(0, source.get_height(), 4):
				# read the pixels to be compressed in this block
				# this ordering works correctly..
				for y in range(4):
					for x in range(4):
						height_4x4[y * 4 + x] = source.get_pixel(block_x + x, block_y + y).r
				# compress the block
				block_count += 1
				var px0_min: float = height_4x4.min()
				var px1_max: float = height_4x4.max()
				# normalise each h to min -> max in 16 steps, stored in 4 bit indicies
				var range_val: float = px1_max - px0_min
				for i in range(16):
					var index: int = clampi(int(round((height_4x4[i] - px0_min) / range_val * 15.0)), 0, 15)
					indices[i] = index
				# Bitpack first 32 bits of indices (indices 0 to 7)
				var px2_u: int = 0
				for i in range(8):
					px2_u |= (indices[i] << (i * 4))
				var px2_ids: float = util.as_float(px2_u)
				# Bitpack second 32 bits of indices (indices 8 to 15)
				var px3_u: int = 0
				for i in range(8, 16):
					px3_u |= (indices[i] << ((i - 8) * 4))
				var px3_ids: float = util.as_float(px3_u)
				# Write 2x2 compressed block
				var target_x: int = block_x / 2
				var target_y: int = block_y / 2
				compressed.set_pixel(target_x, target_y, Color(px0_min, 0, 0, 1))
				compressed.set_pixel(target_x + 1, target_y, Color(px1_max, 0, 0, 1))
				compressed.set_pixel(target_x, target_y + 1, Color(px2_ids, 0, 0, 1))
				compressed.set_pixel(target_x + 1, target_y + 1, Color(px3_ids, 0, 0, 1))
		compressed_tex = compressed
		print("Compressed ", block_count, " blocks in: ", (Time.get_ticks_usec() - time)/ 1000000.0, "s")
		#compressed_tex.save_exr("res://test_compress.exr")
		#tex.save_exr("res://test_source.exr")
		#EditorInterface.get_resource_filesystem().scan()

@export var compressed_tex: Image

@export var decompress: bool :
	set(value):
		var time : int = Time.get_ticks_usec()
		var util: Terrain3DUtil = Terrain3DUtil.new()
		var compressed: Image = compressed_tex
		var decompressed: Image = Image.create(compressed.get_height() * 2, compressed.get_height() * 2, false, Image.FORMAT_RF)
		# Iterate over each 2x2 set of pixels in the compressed image
		for block_y in range(0, compressed.get_height(), 2):
			for block_x in range(0, compressed.get_height(), 2):
				# Read the compressed 2x2 block
				var px0_min: float = compressed.get_pixel(block_x, block_y).r
				var px1_max: float = compressed.get_pixel(block_x + 1, block_y).r
				var px2_ids: float = compressed.get_pixel(block_x, block_y + 1).r
				var px3_ids: float = compressed.get_pixel(block_x + 1, block_y + 1).r
				# Unpack the indices
				var px2_u: int = util.as_uint(px2_ids)
				var px3_u: int = util.as_uint(px3_ids)
				var indices: Array[int]
				for i in range(8):
					indices.append((px2_u >> (i * 4)) & 0xF)  # Extract 4-bit indices from px2_u
				for i in range(8):
					indices.append((px3_u >> (i * 4)) & 0xF)  # Extract 4-bit indices from px3_u
				# Reconstruct the 4x4 block
				var range_val: float = px1_max - px0_min
				for y in range(4):
					for x in range(4):
						var index: int = indices[y * 4 + x]
						var height: float = px0_min + (index / 15.0) * range_val
						var target_x: int = block_x * 2 + x
						var target_y: int = block_y * 2 + y
						decompressed.set_pixel(target_x, target_y, Color(height, 0, 0, 1))
		decompressed_tex = decompressed
		print("Decompressed in: ", (Time.get_ticks_usec() - time)/ 1000000.0, "s")

@export var decompressed_tex : Image

@export var compare : bool :
	set(value):
		var max_error : float = 0.0;
		var average_error : float = 0.0;
		var toll_0_15 : float = 0.0
		var toll_0_10 : float = 0.0
		var toll_0_05 : float = 0.0
		var toll_0_001 : float = 0.0
		var toll_0_5 : float = 0.0
		for x in source.get_width():
			for y in source.get_height():
				var s_h : float = source.get_pixel(x, y).r
				var c_h : float = decompressed_tex.get_pixel(x, y).r
				var error : float = abs(s_h - c_h)
				max_error = error if error > abs(max_error) else max_error
				average_error += error
				toll_0_15 += 1.0 if error < 0.15 else 0.0
				toll_0_10 += 1.0 if error < 0.10 else 0.0
				toll_0_05 += 1.0 if error < 0.05 else 0.0
				toll_0_001 += 1.0 if error < 0.001 else 0.0
				toll_0_5 += 1.0 if error > 0.5 else 0.0
		var num_px : float = source.get_height() * source.get_width()
		average_error /= num_px
		print("Maximum error in m: ", max_error)
		print("Average error in m: ", average_error)
		print("Error less than 0.15: ", (toll_0_15 / num_px * 100.0)," %")
		print("Error less than 0.10: ", (toll_0_10 / num_px * 100.0)," %")
		print("Error less than 0.05: ", (toll_0_05 / num_px * 100.0)," %")
		print("Error less than 0.001: ", (toll_0_001 / num_px * 100.0)," %")
		print("Error greater than 0.5: ", (toll_0_5 / num_px * 100.0)," %")
		
@export var map_array: Array[Image] # -> Texture2DArray.new().create_from_images()

var hmap_rid : RID
@export var set_heightmaps : bool :
	set(value):
		if hmap_rid.is_valid():
			RenderingServer.free_rid(hmap_rid)
		hmap_rid = RenderingServer.texture_2d_layered_create(map_array, RenderingServer.TEXTURE_LAYERED_2D_ARRAY)
		var mat_rid : RID = self.material.get_material_rid()
		RenderingServer.material_set_param(mat_rid, "_height_maps", hmap_rid)
