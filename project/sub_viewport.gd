@tool
extends SubViewport

@onready var rect: TextureRect = $TextureRect

@export var source: Image :
	set(value):
		if value.get_format() != Image.FORMAT_RF:
			printerr("Image must be FORMAT_RH")
			return
		if not value or value.is_empty():
			return
		source = value
		size = source.get_size()
		rect.texture = ImageTexture.create_from_image(value)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		print("Waiting 1 frame for viewport to render")
		await RenderingServer.frame_post_draw
		vp_image = get_texture().get_image()

@export var vp_image: Image :
	set(value):
		vp_image = value
		for h in value.get_height():
			for w in value.get_width():
				var source_height: float = source.get_pixel(h,w).r
				var dest_height: float = decode_texture_color(value.get_pixel(h,w))
				assert(source_height == dest_height)
		print("vp_image 100% match with source after decode check")
		result = Image.create_from_data(1024, 1024, false, Image.FORMAT_RF, value.get_data())

@export var result: Image :
	set(value):
		result = value
		for h in value.get_height():
			for w in value.get_width():
				var source_height: float = source.get_pixel(h,w).r
				var result_height: float = result.get_pixel(h,w).r
				assert(source_height == result_height)
		print("result matches source")

func decode_texture_color(color: Color) -> float:
	var byte_array = PackedByteArray([
		int(color.r * 255.0),
		int(color.g * 255.0),
		int(color.b * 255.0),
		int(color.a * 255.0)
	])
	return byte_array.decode_float(0)
