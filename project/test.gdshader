shader_type canvas_item;
render_mode blend_disabled;

uniform uint _background_mode = 0u;
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1/_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1/REGION_SIZE
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _color_maps : repeat_disable;

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2

// Takes in world space XZ (UV) coordinates & search depth (only applicable for background mode none)
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < 0; i++) {
		if ((layer_index == -1 && _background_mode == 0u) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

void fragment() {
	vec2 uv = SCREEN_UV / SCREEN_PIXEL_SIZE;
	// Lookup offsets, ID and blend weight
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv * _vertex_density);
	vec2 weight = fract(uv * _vertex_density);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y, // 0
		weight.x * weight.y, // 1
		weight.x * invert.y, // 2
		invert.x * invert.y  // 3
	);

	ivec3 index[4];
	// Map lookups
	index[0] = get_index_coord(index_id + offsets.xy, VERTEX_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, VERTEX_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, VERTEX_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, VERTEX_PASS);
	highp float h[8];
	h[0] = texelFetch(_height_maps, index[0], 0).r; // 0 (0,1)
	h[1] = texelFetch(_height_maps, index[1], 0).r; // 1 (1,1)
	h[2] = texelFetch(_height_maps, index[2], 0).r; // 2 (1,0)
	h[3] = texelFetch(_height_maps, index[3], 0).r; // 3 (0,0)
	h[4] = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, VERTEX_PASS), 0).r; // 4 (1,2)
	h[5] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, VERTEX_PASS), 0).r; // 5 (2,1)
	h[6] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, VERTEX_PASS), 0).r; // 6 (2,0)
	h[7] = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, VERTEX_PASS), 0).r; // 7 (0,2)
	vec3 index_normal[4];
	// this should be improved by doing full width(-1 to +1 instead of 0 to +1), with 2x _vertex_spacing on Y.
	// doing so will require additional height reads above.
	index_normal[0] = vec3(h[0] - h[1], _vertex_spacing, h[0] - h[7]);
	index_normal[1] = vec3(h[1] - h[5], _vertex_spacing, h[1] - h[4]);
	index_normal[2] = vec3(h[2] - h[6], _vertex_spacing, h[2] - h[1]);
	index_normal[3] = vec3(h[3] - h[2], _vertex_spacing, h[3] - h[0]);

	vec3 w_normal = normalize(
		index_normal[0] * weights[0] +
		index_normal[1] * weights[1] +
		index_normal[2] * weights[2] +
		index_normal[3] * weights[3]);

	uint control[4];
	control[0] = floatBitsToUint(texelFetch(_control_maps, index[0], 0).r);
	control[1] = floatBitsToUint(texelFetch(_control_maps, index[1], 0).r);
	control[2] = floatBitsToUint(texelFetch(_control_maps, index[2], 0).r);
	control[3] = floatBitsToUint(texelFetch(_control_maps, index[3], 0).r);

	#define OUTPUT 0

	#if OUTPUT == 0
	// output normal map
	COLOR.rgb = w_normal.rbg * 0.5 + 0.5;
	COLOR.a = 1.;

	#elif OUTPUT == 1
	// output height map
	float pixel_out = h[3];
	uint encode = floatBitsToUint(pixel_out);
	COLOR = vec4(
		float(encode & 0xFFu),
		float((encode >> 8u) & 0xFFu),
		float((encode >> 16u) & 0xFFu),
		float((encode >> 24u) & 0xFFu)
	) / 255.0;

	#elif OUTPUT == 2
	// output control map - NEEDS TESTING
	encode = control[3];
	COLOR = vec4(
		float(encode & 0xFFu),
		float((encode >> 8u) & 0xFFu),
		float((encode >> 16u) & 0xFFu),
		float((encode >> 24u) & 0xFFu)
	) / 255.0;
	#endif
}
