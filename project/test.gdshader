shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
	vec4 source = texelFetch(TEXTURE, ivec2(SCREEN_UV / SCREEN_PIXEL_SIZE), 0);
	uint encode = floatBitsToUint(source.r);

	COLOR = vec4(
		float(encode & 0xFFu),
		float((encode >> 8u) & 0xFFu),
		float((encode >> 16u) & 0xFFu),
		float((encode >> 24u) & 0xFFu)
	) / 255.0;
}
