shader_type canvas_item;

// Displacement buffer shader, mimics the main shader in 2d and out puts
// RG Terrain Normal, and B texture height value. A is unusuable when passing
// the buffer directly via RID (avoids GPU > CPU > GPU copys) as alpha
// is premultiplied by the viewport.

// For normals, This could be corrected for by the following:
// `vec2 normal_unmult_alpha = (nrm - nrm * 0.5) / max(alpha, DIV_255) * 2.0;`
// However this gives increasing loss of precision as the alpha approaches zero, so we avoid
// using alpha entirely by packing normals into 2 channels, and height as the 3rd.

// Defined Constants
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2
#define COLOR_MAP_DEF vec4(1.0, 1.0, 1.0, 0.5)
#define DIV_255 0.003921568627450 // 1. / 255.
#define DIV_1024 0.0009765625 // 1. / 1024.
#define TAU_16TH -0.392699081698724 // -TAU / 16.

// Inline Functions
#define DECODE_BLEND(control) float(control >> 14u & 0xFFu) * DIV_255
#define DECODE_AUTO(control) bool(control & 0x1u)
#define DECODE_BASE(control) int(control >> 27u & 0x1Fu)
#define DECODE_OVER(control) int(control >> 22u & 0x1Fu)
#define DECODE_ANGLE(control) float(control >>10u & 0xFu) * TAU_16TH
// This math recreates the scale value directly rather than using an 8 float const array.
#define DECODE_SCALE(control) (0.9 - float(((control >>7u & 0x7u) + 3u) % 8u + 1u) * 0.1)
#define DECODE_HOLE(control) bool(control >>2u & 0x1u)

#define TEXTURE_ID_PROJECTED(id) bool((_texture_uv_projections >> uint(id)) & 0x1u)

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
uniform float _tesselation_level = 0.;
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1./_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1./region_size
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform uint _texture_uv_projections;
uniform vec2 _texture_detile_array[32];
uniform vec4 _texture_color_array[32];
uniform vec2 _texture_displacement_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;


// Public uniforms
#define AUTO_SHADER
uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;

uniform int dual_scale_texture : hint_range(0,31) = 0;
uniform float dual_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float tri_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float dual_scale_far : hint_range(0,1000) = 170.0;
uniform float dual_scale_near : hint_range(0,1000) = 100.0;

uniform float blend_sharpness : hint_range(0, 1) = 0.5;
uniform bool enable_projection = true;
uniform float projection_threshold : hint_range(0.0, 0.99, 0.01) = 0.8;

// Varyings & Types

// We only care about 1 value here.
struct material {
	vec4 albedo_height;
	vec4 normal_rough;
	float normal_map_depth;
	float ao_strength;
	float total_weight;
};

////////////////////////
// Vertex
////////////////////////

// Takes in world space XZ (UV) coordinates & search depth (only applicable for background mode none)
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv, const int search) {
	vec2 r_uv = round(uv);
	vec2 o_uv = mod(r_uv,_region_size);
	ivec2 pos;
	int bounds, layer_index = -1;
	for (int i = -1; i < clamp(search, SKIP_PASS, FRAGMENT_PASS); i++) {
		if ((layer_index == -1 && _background_mode == 0u ) || i < 0) {
			r_uv -= i == -1 ? vec2(0.0) : vec2(float(o_uv.x <= o_uv.y), float(o_uv.y <= o_uv.x));
			pos = ivec2(floor((r_uv) * _region_texel_size)) + (_region_map_size / 2);
			bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
			layer_index = (_region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1);
		}
	}
	return ivec3(ivec2(mod(r_uv,_region_size)), layer_index);
}

// Takes in descaled (world_space / region_size) world to region space XZ (UV2) coordinates, returns vec3 with:
// XY: (0. to 1.) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
vec3 get_index_uv(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int layer_index = _region_map[ pos.y * _region_map_size + pos.x ] * bounds - 1;
	return vec3(uv2 - _region_locations[layer_index], float(layer_index));
}

////////////////////////
// Fragment
////////////////////////

float random(in vec2 xy) {
	return fract(sin(dot(xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate_vec2(const vec2 v, const vec2 cs) {
	return vec2(fma(cs.x, v.x,  cs.y * v.y), fma(cs.x, v.y, -cs.y * v.x));
}

// 2-4 lookups ( 2-6 with dual scaling )
void accumulate_material(const mat3 TNB, const float weight, const ivec3 index,
			const uint control, const vec2 texture_weight, const ivec2 texture_id, const vec3 i_normal,
			float h, inout material mat, const vec3 v_vertex, float scale) {

	// Applying scaling before projection reduces the number of multiplys ops required.
	vec3 i_vertex = v_vertex;

	// Control map scale
	float control_scale = DECODE_SCALE(control);
	// tri scaling
	if (index.z < 0) {
		control_scale *= tri_scale_reduction;
	}
	i_vertex *= control_scale;
	h *= control_scale;

	// Index position for detiling.
	vec2 i_pos = fma(_region_locations[index.z], vec2(_region_size), vec2(index.xy));
	i_pos *= _vertex_spacing * control_scale;

	// Projection
	vec2 i_uv = i_vertex.xz;
	mat2 p_align = mat2(1.);
	vec2 p_uv = i_uv;
	vec2 p_pos = i_pos;
	if (i_normal.y <= projection_threshold && enable_projection) {
		// Projected normal map alignment matrix
		p_align = mat2(vec2(i_normal.z, -i_normal.x), vec2(i_normal.x, i_normal.z));
		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-i_normal.xz) * 1.3065629648763765); // sqrt(1.0 + sqrt(0.5))
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0; // sqrt(0.5)
		xz = vec2(-xz.y, xz.x);
		p_pos = floor(vec2(dot(i_pos, xz), -h));
		p_uv = vec2(dot(i_vertex.xz, xz), -i_vertex.y);
	}

	// Control map rotation. Must be applied seperatley from detiling to maintain UV continuity.
	float c_angle = DECODE_ANGLE(control);
	vec2 c_cs_angle = vec2(cos(c_angle), sin(c_angle));
	i_uv = rotate_vec2(i_uv, c_cs_angle);
	i_pos = rotate_vec2(i_pos, c_cs_angle);
	p_uv = rotate_vec2(p_uv, c_cs_angle);
	p_pos = rotate_vec2(p_pos, c_cs_angle);

	// Blend adjustment of Higher ID from Lower ID normal map in world space.
	float world_normal = 1.;
	// mat3 multiply, reduced to 2x fma and 1x mult.
	#define FAST_WORLD_NORMAL(n) fma(TNB[0], vec3(n.x), fma(TNB[2], vec3(n.z), TNB[1] * vec3(n.y)))

	float blend = DECODE_BLEND(control); // only used for branching.
	float sharpness = fma(11., blend_sharpness, 1.);

	// dual scaling
	float far_factor = clamp(smoothstep(dual_scale_near, dual_scale_far, length(v_vertex - _camera_pos)), 0.0, 1.0);
	vec4 far_alb = vec4(0.);
	vec4 far_nrm = vec4(0.);
	if (far_factor > 0. && any(equal(texture_id, ivec2(dual_scale_texture)))) {
		bool projected = TEXTURE_ID_PROJECTED(dual_scale_texture);
		float far_scale = _texture_uv_scale_array[dual_scale_texture] * dual_scale_reduction;

		// Detiling and Control map rotation
		vec2 id_pos = fma(p_pos, vec2(float(projected)), i_pos * vec2(float(!projected)));
		vec2 uv_center = floor(fma(id_pos, vec2(far_scale), vec2(0.5)));
		vec2 far_detile = fma(random(uv_center), 2.0, -1.0) * _texture_detile_array[dual_scale_texture] * TAU;
		vec2 far_cs_angle = vec2(cos(far_detile.x), sin(far_detile.x));
		// Apply UV rotation and shift around pivot.
		vec2 far_uv = fma(p_uv, vec2(float(projected)), i_uv * vec2(float(!projected)));
		far_uv = rotate_vec2(fma(far_uv, vec2(far_scale), -uv_center), far_cs_angle) + uv_center + far_detile.y - 0.5;
		// Manual transpose to rotate derivatives and normals counter to uv rotation whilst also
		// including control map rotation. avoids extra matrix op, and sin/cos calls.
		far_cs_angle = vec2(
			fma(far_cs_angle.x, c_cs_angle.x, -far_cs_angle.y * c_cs_angle.y),
			fma(far_cs_angle.y, c_cs_angle.x, far_cs_angle.x * c_cs_angle.y));

		far_alb = textureLod(_texture_array_albedo, vec3(far_uv, float(dual_scale_texture)), scale);
		far_nrm = textureLod(_texture_array_normal, vec3(far_uv, float(dual_scale_texture)), scale);
		far_alb.rgb *= _texture_color_array[dual_scale_texture].rgb;
		far_nrm.a = clamp(far_nrm.a + _texture_roughness_mod_array[dual_scale_texture], 0., 1.);
		// Unpack and rotate normal map.
		far_nrm.xyz = fma(far_nrm.xzy, vec3(2.0), vec3(-1.0));
		far_nrm.xz = rotate_vec2(far_nrm.xz, far_cs_angle);
		far_nrm.xz = fma((far_nrm.xz * p_align), vec2(float(projected)), far_nrm.xz * vec2(float(!projected)));

		// apply weighting when far_factor == 1.0 as the later lookup will be skipped.
		if (far_factor == 1.0) {
			float id_w = texture_id[0] == dual_scale_texture ? texture_weight[0] : texture_weight[1];
			float id_weight = exp2(sharpness * log2(weight + id_w + far_alb.a)) * weight;
			far_alb.a = fma(far_alb.a, _texture_displacement_array[dual_scale_texture].y, _texture_displacement_array[dual_scale_texture].x);
			world_normal = FAST_WORLD_NORMAL(far_nrm).y;
			mat.albedo_height = fma(far_alb, vec4(id_weight), mat.albedo_height);
			mat.normal_rough = fma(far_nrm, vec4(id_weight), mat.normal_rough);
			mat.normal_map_depth = fma(_texture_normal_depth_array[dual_scale_texture], id_weight, mat.normal_map_depth);
			mat.ao_strength = fma(_texture_ao_strength_array[dual_scale_texture], id_weight, mat.ao_strength);
			mat.total_weight += id_weight;
		}
	}


	// 1st Texture Asset ID
	if (blend < 1.0
			&& !(far_factor == 1.0 && texture_id[0] == dual_scale_texture)
		) {
		int id = texture_id[0];
		bool projected = TEXTURE_ID_PROJECTED(id);
		float id_w = texture_weight[0];
		float id_scale = _texture_uv_scale_array[id];

		// Detiling and Control map rotation
		vec2 id_pos = fma(p_pos, vec2(float(projected)), i_pos * vec2(float(!projected)));
		vec2 uv_center = floor(fma(id_pos, vec2(id_scale), vec2(0.5)));
		vec2 id_detile = fma(random(uv_center), 2.0, -1.0) * _texture_detile_array[id] * TAU;
		vec2 id_cs_angle = vec2(cos(id_detile.x), sin(id_detile.x));
		// Apply UV rotation and shift around pivot.
		vec2 id_uv = fma(p_uv, vec2(float(projected)), i_uv * vec2(float(!projected)));
		id_uv = rotate_vec2(fma(id_uv, vec2(id_scale), -uv_center), id_cs_angle) + uv_center + id_detile.y - 0.5;
		// Manual transpose to rotate derivatives and normals counter to uv rotation whilst also
		// including control map rotation. avoids extra matrix op, and sin/cos calls.
		id_cs_angle = vec2(
			fma(id_cs_angle.x, c_cs_angle.x, -id_cs_angle.y * c_cs_angle.y),
			fma(id_cs_angle.y, c_cs_angle.x, id_cs_angle.x * c_cs_angle.y));

		vec4 alb = textureLod(_texture_array_albedo, vec3(id_uv, float(id)), scale);
		vec4 nrm = textureLod(_texture_array_normal, vec3(id_uv, float(id)), scale);
		alb.rgb *= _texture_color_array[id].rgb;
		nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
		// Unpack and rotate normal map.
		nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
		nrm.xz = rotate_vec2(nrm.xz, id_cs_angle);
		nrm.xz = fma((nrm.xz * p_align), vec2(float(projected)), nrm.xz * vec2(float(!projected)));

		// If dual scaling, apply to overlay texture
		if (id == dual_scale_texture && far_factor > 0.) {
			alb = mix(alb, far_alb, far_factor);
			nrm = mix(nrm, far_nrm, far_factor);
		}
		world_normal = FAST_WORLD_NORMAL(nrm).y;

		alb.a = fma(alb.a, _texture_displacement_array[id].y, _texture_displacement_array[id].x);
		float id_weight = exp2(sharpness * log2(weight + id_w + alb.a)) * weight;
		mat.albedo_height = fma(alb, vec4(id_weight), mat.albedo_height);
		mat.normal_rough = fma(nrm, vec4(id_weight), mat.normal_rough);
		mat.normal_map_depth = fma(_texture_normal_depth_array[id], id_weight, mat.normal_map_depth);
		mat.ao_strength = fma(_texture_ao_strength_array[id], id_weight, mat.ao_strength);
		mat.total_weight += id_weight;
	}

	// 2nd Texture Asset ID
	if (blend > 0.0 && texture_id[1] != texture_id[0]
		&& !(far_factor == 1.0 && texture_id[1] == dual_scale_texture)
		) {
		int id = texture_id[1];
		bool projected = TEXTURE_ID_PROJECTED(id);
		float id_w = texture_weight[1];
		float id_scale = _texture_uv_scale_array[id];

		// Detiling and Control map rotation
		vec2 id_pos = fma(p_pos, vec2(float(projected)), i_pos * vec2(float(!projected)));
		vec2 uv_center = floor(fma(id_pos, vec2(id_scale), vec2(0.5)));
		vec2 id_detile = fma(random(uv_center), 2.0, -1.0) * _texture_detile_array[id] * TAU;
		vec2 id_cs_angle = vec2(cos(id_detile.x), sin(id_detile.x));
		// Apply UV rotation and shift around pivot.
		vec2 id_uv = fma(p_uv, vec2(float(projected)), i_uv * vec2(float(!projected)));
		id_uv = rotate_vec2(fma(id_uv, vec2(id_scale), -uv_center), id_cs_angle) + uv_center + id_detile.y - 0.5;
		// Manual transpose to rotate derivatives and normals counter to uv rotation whilst also
		// including control map rotation. avoids extra matrix op, and sin/cos calls.
		id_cs_angle = vec2(
			fma(id_cs_angle.x, c_cs_angle.x, -id_cs_angle.y * c_cs_angle.y),
			fma(id_cs_angle.y, c_cs_angle.x, id_cs_angle.x * c_cs_angle.y));

		vec4 alb = textureLod(_texture_array_albedo, vec3(id_uv, float(id)), scale);
		vec4 nrm = textureLod(_texture_array_normal, vec3(id_uv, float(id)), scale);
		alb.rgb *= _texture_color_array[id].rgb;
		nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
		// Unpack and rotate normal map.
		nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
		nrm.xz = rotate_vec2(nrm.xz, id_cs_angle);
		nrm.xz = fma((nrm.xz * p_align), vec2(float(projected)), nrm.xz * vec2(float(!projected)));

		// If dual scaling, apply to overlay texture
		if (id == dual_scale_texture && far_factor > 0.) {
			alb = mix(alb, far_alb, far_factor);
			nrm = mix(nrm, far_nrm, far_factor);
		}
		alb.a = fma(alb.a, _texture_displacement_array[id].y, _texture_displacement_array[id].x);
		float id_weight = exp2(sharpness * log2(weight + id_w + alb.a * clamp(world_normal, 0., 1.))) * weight;
		mat.albedo_height = fma(alb, vec4(id_weight), mat.albedo_height);
		mat.normal_rough = fma(nrm, vec4(id_weight), mat.normal_rough);
		mat.normal_map_depth = fma(_texture_normal_depth_array[id], id_weight, mat.normal_map_depth);
		mat.ao_strength = fma(_texture_ao_strength_array[id], id_weight, mat.ao_strength);
		mat.total_weight += id_weight;
	}
}

void fragment() {
	// Calculate UV Tiles
	float scale = floor(UV.x * (_tesselation_level));
	float p_scale = pow(2.0, scale);
	vec2 uv = (vec2(fract(UV.x * _tesselation_level), UV.y) - 0.5) * (_mesh_size * 2.0) / p_scale;
	uv += round(_camera_pos.xz * p_scale) / p_scale * _vertex_density + (pow(0.5, _tesselation_level) * 0.5);

	vec2 uv2 = uv * _region_texel_size;

	// Lookup offsets, ID and blend weight
	vec3 region_uv = get_index_uv(uv2);
	const vec3 offsets = vec3(0, 1, 2);
	vec2 index_id = floor(uv);
	vec2 weight = fract(uv);
	vec2 invert = 1.0 - weight;
	vec4 weights = vec4(
		invert.x * weight.y, // 0
		weight.x * weight.y, // 1
		weight.x * invert.y, // 2
		invert.x * invert.y  // 3
	);

	ivec3 index[4];
	// control map lookups, used for some normal lookups as well
	index[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);

	// Terrain normals
	vec3 index_normal[4];
	float h[4];
	// allows additional derivatives, eg world noise, brush previews etc
	float u = 0.0;
	float v = 0.0;

	// Re-use index[] for the first lookups, skipping some math. 3 lookups
	h[3] = texelFetch(_height_maps, index[3], 0).r; // 0 (0,0)
	h[2] = texelFetch(_height_maps, index[2], 0).r; // 1 (1,0)
	h[0] = texelFetch(_height_maps, index[0], 0).r; // 2 (0,1)
	index_normal[3] = normalize(vec3(h[3] - h[2] + u, _vertex_spacing, h[3] - h[0] + v));

	// 5 lookups
	// Fetch the additional required height values for smooth normals
	h[1] = texelFetch(_height_maps, index[1], 0).r; // 3 (1,1)
	float h_4 = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r; // 4 (1,2)
	float h_5 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r; // 5 (2,1)
	float h_6 = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r; // 6 (2,0)
	float h_7 = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r; // 7 (0,2)

	// Calculate the normal for the remaining index ids.
	index_normal[0] = normalize(vec3(h[0] - h[1] + u, _vertex_spacing, h[0] - h_7 + v));
	index_normal[1] = normalize(vec3(h[1] - h_5 + u, _vertex_spacing, h[1] - h_4 + v));
	index_normal[2] = normalize(vec3(h[2] - h_6 + u, _vertex_spacing, h[2] - h[1] + v));

	// Set interpolated world normal
	vec3 w_normal =
		index_normal[0] * weights[0] +
		index_normal[1] * weights[1] +
		index_normal[2] * weights[2] +
		index_normal[3] * weights[3] ;
	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	mat3 TNB = mat3(w_tangent, w_normal, w_binormal);

	// We have to construct interpolted height value here, we are operating solely in texture space.
	float terrain_height = h[0] * weights[0] + h[1] * weights[1] + h[2] * weights[2] + h[3] * weights[3];
	vec3 v_vertex = vec3(uv.x * _vertex_spacing, terrain_height, uv.y * _vertex_spacing);

	// Get index control data
	// 1 - 4 lookups
	uvec4 control = uvec4(
		floatBitsToUint(texelFetch(_control_maps, index[0], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[1], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[2], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[3], 0).r));

	{
		// Auto blend calculation
		float auto_blend = clamp(fma(auto_slope * 2.0, (w_normal.y - 1.0), 1.0)
			- auto_height_reduction * 0.01 * v_vertex.y, 0.0, 1.0);
		// Enable Autoshader if outside regions or painted in regions, otherwise manual painted
		uvec4 is_auto = (control & uvec4(0x1u)) | uvec4(uint(region_uv.z < 0.0));
		uint u_auto =
			((uint(auto_base_texture) & 0x1Fu) << 27u) |
			((uint(auto_overlay_texture) & 0x1Fu) << 22u) |
			((uint(fma(auto_blend, 255.0 , 0.5)) & 0xFFu) << 14u);
		control = control * (1u - is_auto) + u_auto * is_auto;
	}

	// Vectorised Deocode of all texture IDs, then swizzle to per index mapping.
	// Passed to accumulate_material to avoid repeated decoding.
	ivec4 t_id[2] = {ivec4(control >> uvec4(27u) & uvec4(0x1Fu)),
		ivec4(control >> uvec4(22u) & uvec4(0x1Fu))};
	ivec2 texture_ids[4] = ivec2[4](
		ivec2(t_id[0].x, t_id[1].x),
		ivec2(t_id[0].y, t_id[1].y),
		ivec2(t_id[0].z, t_id[1].z),
		ivec2(t_id[0].w, t_id[1].w));

	// uninterpolated weights.
	vec4 weights_id_1 = vec4(control >> uvec4(14u) & uvec4(0xFFu)) * DIV_255;
	vec4 weights_id_0 = 1.0 - weights_id_1;
	vec2 t_weights[4] = vec2[4](
				vec2(weights_id_0[0], weights_id_1[0]),
				vec2(weights_id_0[1], weights_id_1[1]),
				vec2(weights_id_0[2], weights_id_1[2]),
				vec2(weights_id_0[3], weights_id_1[3]));
	// interpolated weights
	#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS

	t_weights = {vec2(0), vec2(0), vec2(0), vec2(0)};
	weights_id_0 *= weights;
	weights_id_1 *= weights;
	for (int i = 0; i < 4; i++) {
		vec2 w_0 = vec2(weights_id_0[i]);
		vec2 w_1 = vec2(weights_id_1[i]);
		ivec2 id_0 = texture_ids[i].xx;
		ivec2 id_1 = texture_ids[i].yy;
		t_weights[0] += fma(w_0, vec2(equal(texture_ids[0], id_0)), w_1 * vec2(equal(texture_ids[0], id_1)));
		t_weights[1] += fma(w_0, vec2(equal(texture_ids[1], id_0)), w_1 * vec2(equal(texture_ids[1], id_1)));
		t_weights[2] += fma(w_0, vec2(equal(texture_ids[2], id_0)), w_1 * vec2(equal(texture_ids[2], id_1)));
		t_weights[3] += fma(w_0, vec2(equal(texture_ids[3], id_0)), w_1 * vec2(equal(texture_ids[3], id_1)));
	}

	#endif

	// Struct to accumulate all texture data.
	material mat = material(vec4(0.0), vec4(0.0), 0., 0., 0.);
	accumulate_material(TNB, weights[3], index[3], control[3], t_weights[3],
		texture_ids[3], index_normal[3], h[3], mat, v_vertex, scale);
	accumulate_material(TNB, weights[2], index[2], control[2], t_weights[2],
		texture_ids[2], index_normal[2], h[2], mat, v_vertex, scale);
	accumulate_material(TNB, weights[1], index[1], control[1], t_weights[1],
		texture_ids[1], index_normal[1], h[1], mat, v_vertex, scale);
	accumulate_material(TNB, weights[0], index[0], control[0], t_weights[0],
		texture_ids[0], index_normal[0], h[0], mat, v_vertex, scale);

	// normalize accumulated values back to 0.0 - 1.0 range.
	float weight_inv = 1.0 / mat.total_weight;
	mat.normal_rough *= weight_inv;
	mat.albedo_height *= weight_inv;

	// Output
	COLOR.rg = fma(w_normal.xz, vec2(0.5), vec2(0.5));
	COLOR.b = mat.albedo_height.a;

}
