@tool
extends SubViewport

@onready var rect: TextureRect = $TextureRect

var time: int = 0

@export var source: Image :
	set(value):
		source = value
		if not value or value.is_empty():
			return
		if value.get_format() != Image.FORMAT_RF:
			printerr("Image must be FORMAT_RH")
			source = null
			return
		size = source.get_size()
		rect.texture = ImageTexture.create_from_image(value)
		render_target_update_mode = SubViewport.UPDATE_ONCE
		print("Waiting 1 frame for viewport to render")
		time = Time.get_ticks_usec()
		await RenderingServer.frame_post_draw
		
		vp_image = get_texture().get_image()
		result = Image.create_from_data(1024, 1024, false, Image.FORMAT_RF, vp_image.get_data())
		time = Time.get_ticks_usec() - time
		print(float(time) / 1000000)

@export var vp_image: Image
@export var result: Image

func decode_texture_color(color: Color) -> float:
	var byte_array = PackedByteArray([
		int(color.r * 255.0),
		int(color.g * 255.0),
		int(color.b * 255.0),
		int(color.a * 255.0)
	])
	return byte_array.decode_float(0)
