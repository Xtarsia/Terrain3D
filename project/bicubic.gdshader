shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;

/* The terrain depends on this shader to function. Don't change most things in vertex() or
 * terrain normal calculations in fragment(). You probably only want to customize the
 * material calculation and PBR application in fragment().
 *
 * Uniforms that begin with _ are private and will not display in the inspector. However,
 * you can set them via code. You are welcome to create more of your own hidden uniforms.
 *
 * This system only supports albedo, height, normal, roughness. Most textures don't need the other
 * PBR channels. Height can be used as an approximation for AO. For the rare textures do need
 * additional channels, you can add maps for that one texture. e.g. an emissive map for lava.
 *
 */

// Defined Constants
#define COLOR_MAP_DEF vec4(1.0, 1.0, 1.0, 0.5)
#define DIV_255 0.003921568627450 // 1. / 255.
#define DIV_1024 0.0009765625 // 1. / 1024.
#define TAU_16TH -0.392699081698724 // -TAU / 16.

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

// Private uniforms
group_uniforms shader_uniforms;
uniform vec3 _target_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform float _subdiv = 1.f;
uniform float _tessellation_level = 0.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1./_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1./region_size
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_ao_affect_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec2 _texture_detile_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
#define FILTER_LINEAR
#define FILTER_METHOD filter_linear_mipmap_anisotropic

uniform highp sampler2DArray _color_maps : source_color, FILTER_METHOD, repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, FILTER_METHOD, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, FILTER_METHOD, repeat_enable;
group_uniforms;

// Public uniforms
group_uniforms shader_uniforms.general;
uniform float ground_level : hint_range(-1000., 1000.) = 0.0;
uniform float region_blend : hint_range(.001, 1., 0.001) = 0.25;

uniform bool flat_terrain_normals = false;
uniform float blend_sharpness : hint_range(0, 1) = 0.5;
group_uniforms;

#define AUTO_SHADER
group_uniforms shader_uniforms.auto_shader;
uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform float auto_sea_level : hint_range(-1024.0, 1024.0, 0.1) = 0.0;
uniform float auto_beach_height : hint_range(2.0, 256., 0.1) = 15;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_underlay_texture : hint_range(0, 31) = 2;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;
group_uniforms;

#define DISPLACEMENT
uniform float _displacement_scale : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform highp sampler2D _displacement_buffer : repeat_disable, filter_linear;

group_uniforms shader_uniforms.dual_scaling;
uniform int dual_scale_texture : hint_range(0,31) = 0;
uniform float dual_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float tri_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float dual_scale_far : hint_range(0,1000) = 170.0;
uniform float dual_scale_near : hint_range(0,1000) = 100.0;
group_uniforms;

group_uniforms shader_uniforms.macro_variation;
uniform vec3 macro_variation1 : source_color = vec3(1.);
uniform vec3 macro_variation2 : source_color = vec3(1.);
uniform float macro_variation_slope : hint_range(0., 1.)  = 0.333;
uniform highp sampler2D noise_texture : source_color, FILTER_METHOD, repeat_enable;
uniform float noise1_scale : hint_range(0.001, 1.) = 0.04; // Used for macro variation 1. Scaled up 10x
uniform float noise1_angle : hint_range(0, 6.283) = 0.;
uniform vec2 noise1_offset = vec2(0.5);
uniform float noise2_scale : hint_range(0.001, 1.) = 0.076;	// Used for macro variation 2. Scaled up 10x
group_uniforms;


group_uniforms shader_uniforms.mipmaps;
uniform float bias_distance : hint_range(0.0, 16384.0, 0.1) = 512.0;
uniform float mipmap_bias : hint_range(0.5, 1.5, 0.01) = 1.0;
uniform float depth_blur : hint_range(0.0, 35.0, 0.1) = 0.0;
group_uniforms;

group_uniforms shader_uniforms.world_background_noise;
uniform bool world_noise_fragment_normals = false;
uniform int world_noise_max_octaves : hint_range(0, 15) = 4;
uniform int world_noise_min_octaves : hint_range(0, 15) = 2;
uniform float world_noise_lod_distance : hint_range(0., 40000., 1.) = 7500.;
uniform float world_noise_scale : hint_range(0.25, 20, 0.01) = 5.0;
uniform float world_noise_height : hint_range(-1000., 1000., 0.1) = 32.0;
uniform vec3 world_noise_offset = vec3(0.0);
group_uniforms;
varying vec2 world_noise_ddxy;


// Varyings & Types

struct material {
	vec4 albedo_height;
	vec4 normal_rough;
	float normal_map_depth;
	float ao;
	float ao_affect;
	float total_weight;
};

varying vec3 v_vertex;
varying float v_vertex_xz_dist;
varying vec3 v_camera_pos;

////////////////////////
// Vertex
////////////////////////

// Takes in world space XZ (UV) coordinates
// Returns ivec3 with:
// XY: (0 to _region_size - 1) coordinates within a region
// Z: layer index used for texturearrays, -1 if not in a region
ivec3 get_index_coord(const vec2 uv) {
	vec2 r_uv = round(uv);
	ivec2 pos = ivec2(floor(r_uv * _region_texel_size)) + (_region_map_size / 2);
	int bounds = int(uint(pos.x | pos.y) < uint(_region_map_size));
	int layer_index = _region_map[pos.y * _region_map_size + pos.x] * bounds - 1;
	return ivec3(ivec2(mod(r_uv, _region_size)), layer_index);
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

float interpolated_height(vec2 pos) {
	const vec2 offsets = vec2(0, 1);
	vec2 index_id = floor(pos);
	ivec3 index[4];
	index[0] = get_index_coord(index_id + offsets.xy);
	index[1] = get_index_coord(index_id + offsets.yy);
	index[2] = get_index_coord(index_id + offsets.yx);
	index[3] = get_index_coord(index_id + offsets.xx);
	float h0 = texelFetch(_height_maps, index[0], 0).r;
	float h1 = texelFetch(_height_maps, index[1], 0).r;
	float h2 = texelFetch(_height_maps, index[2], 0).r;
	float h3 = texelFetch(_height_maps, index[3], 0).r;
	vec2 f = fract(pos);
	vec2 i = 1.0 - f;
	vec4 w = vec4(i.x * f.y, f.x * f.y, f.x * i.y, i.x * i.y);
	float h = h0 * w[0] + h1 * w[1] + h2 * w[2] + h3 * w[3];
	return h;
}

vec3 get_displacement(vec2 pos, float scale) {
	float s = floor(log2(1.0 / (scale * _vertex_density)));
	scale = pow(2.0, s) * 0.5;
	vec2 d_uv = (scale * pos - round(_target_pos.xz * _vertex_density * scale)) / (_mesh_size * 2.0) + 0.5;
	d_uv.x += s - 1.;
	d_uv.x /= log2(_subdiv);
	highp vec3 disp = vec3(0.);
	if (all(greaterThanEqual(d_uv, vec2(0.0))) && all(lessThanEqual(d_uv, vec2(1.0)))) {
		disp = textureLod(_displacement_buffer, d_uv, 0.).rgb * 2.0 - 1.0;
		disp *= _displacement_scale;
	}
	return disp;
}

// Takes in UV2 region space coordinates, returns 1.0 or 0.0 if a region is present or not.
float check_region(const vec2 uv2) {
	ivec2 pos = ivec2(floor(uv2)) + (_region_map_size / 2);
	int layer_index = 0;
	if (uint(pos.x | pos.y) < uint(_region_map_size)) {
		layer_index = clamp(_region_map[ pos.y * _region_map_size + pos.x ] - 1, -1, 0) + 1;
	}
	return float(layer_index);
}

// Takes in UV2 region space coordinates, returns a blend value (0 - 1 range) between empty, and valid regions
float get_region_blend(vec2 uv2) {
	uv2 -= 0.5011; // correct for floating point error
	const vec2 offset = vec2(0.0, 1.0);
	float a = check_region(uv2 + offset.xy);
	float b = check_region(uv2 + offset.yy);
	float c = check_region(uv2 + offset.yx);
	float d = check_region(uv2 + offset.xx);
	vec2 blend_factor = vec2(2.0 + 126.0 * (1.0 - region_blend));
	vec2 f = fract(uv2);
	vec2 w = 1.0 / (1.0 + exp(blend_factor * log((1.0 - f) / f)));
	float blend = mix(mix(d, c, w.x), mix(a, b, w.x), w.y);
	return (1.0 - blend) * 2.0;
}

// World Noise Functions Start

// Takes in UV2 region space coordinates, returns a blend value (0 - 1 range) between empty, and valid regions
float get_noise_region_blend(vec2 uv2) {
	uv2 -= 0.5011; // correct for floating point error
	const vec2 offset = vec2(0.0, 1.0);
	float a = check_region(uv2 + offset.xy);
	float b = check_region(uv2 + offset.yy);
	float c = check_region(uv2 + offset.yx);
	float d = check_region(uv2 + offset.xx);
	vec2 w = smoothstep(vec2(0.0), vec2(1.0), fract(uv2));
	float blend = mix(mix(d, c, w.x), mix(a, b, w.x), w.y);
    return 1.0 - blend * 2.0;
}

float hashf(float f) {
	return fract(sin(f) * 1e4);
}

float hashv2(vec2 v) {
	return fract(1e4 * sin(fma(17.0, v.x, v.y * 0.1)) * (0.1 + abs(sin(fma(v.y, 13.0, v.x)))));
}

// https://iquilezles.org/articles/morenoise/
vec3 noise2D(vec2 x) {
    vec2 f = fract(x);
    // Quintic Hermine Curve.  Similar to SmoothStep()
	vec2 f2 = f * f, f3 = f2 * f, s = f - 1.0, s2 = s * s;
	vec2 u = f3 * fma(vec2(6.0), f2, fma(vec2(-15.0), f, vec2(10.0)));
	vec2 du = 30.0 * f2 * s2;

    vec2 p = floor(x);

	// Four corners in 2D of a tile
	float a = hashv2( p+vec2(0,0) );
    float b = hashv2( p+vec2(1,0) );
    float c = hashv2( p+vec2(0,1) );
    float d = hashv2( p+vec2(1,1) );

    // Mix 4 corner percentages
    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   d - (b + k2);
	return vec3(fma(k2, u.y, fma(u.x, fma(k3, u.y, k1), k0)),
		 du * fma(vec2(k3), u.yx, vec2(k1, k2)));
}

float world_noise(vec2 p) {
    float a = 0.0;
    float b = 1.0;
    vec2  d = vec2(0.0);

    int octaves = int( clamp(
		float(world_noise_max_octaves) - floor(v_vertex_xz_dist/(world_noise_lod_distance)),
		float(world_noise_min_octaves), float(world_noise_max_octaves))
	);

    for( int i=0; i < octaves; i++ ) {
        vec3 n = noise2D(p);
        d += n.yz;
        a += b * n.x / (1.0 + dot(d,d));
        b *= 0.5;
        p = mat2( vec2(0.8, -0.6), vec2(0.6, 0.8) ) * p * 2.0;
    }
    return a;
}

float get_noise_height(const vec2 uv) {
	float weight = get_noise_region_blend(uv);
	// Only calculate world noise when it would be visible.
    if (weight <= 0.5) {
		return 0.0;
	}
	//TODO: Offset/scale UVs are semi-dependent upon region size 1024. Base on v_vertex.xz instead
	float noise = world_noise((uv + world_noise_offset.xz * 1024. / _region_size) * world_noise_scale * _region_size / 1024. * .1) *
            world_noise_height * 10. + world_noise_offset.y * 100.;
    weight = smoothstep(0.5, 1.0, weight);
    return mix(0.0, noise, weight);
}

// World Noise Functions End


void vertex() {
	// Save Camera Position to varying for access in later functions
	v_camera_pos = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;

	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Distance from target node to vertex on a flat plane
	v_vertex_xz_dist = length(v_vertex.xz - _target_pos.xz);

	// Geomorph vertex across clipmap LODs, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float inv_scale = 1.0 / scale;
	float max_xz = max(abs(v_vertex.x - _target_pos.x), abs(v_vertex.z - _target_pos.z));
	float vertex_lerp = smoothstep(0.0, 1.0, (max_xz * inv_scale - _mesh_size - 4.0) / (_mesh_size - 4.0));
	vec2 vertex_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing / _subdiv + 1e-6) ? // LOD0 or not
		// Shift from regular to symmetric
		mix(vertex_fract, vec2(vertex_fract.x, -vertex_fract.y),
			round(fract(round(mod(v_vertex.z * inv_scale, 4.0)) *
			round(mod(v_vertex.x * inv_scale, 4.0)) * 0.25))) :
		// Symmetric shift
		vertex_fract * round((fract(v_vertex.xz * 0.25 * inv_scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in region space. 0-1 covers 1 region, 1-2 is the next region, etc.
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos);
	bool hole = bool(floatBitsToUint(texelFetch(_height_maps, v_region, 0).r) & 0x1u);

	vec3 displacement = vec3(0.);
	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) && (hole
		)){
		v_vertex.x = 0. / 0.;
	} else {
		// Set final vertex height.
		float h;
		// This branch is static for each of the clipmap segments
		// Interpolated reads only occur where sub-texel values are required.
		if (scale < _vertex_spacing) {
			h = interpolated_height(UV);
		} else {
			ivec3 coord_a = get_index_coord(start_pos);
			ivec3 coord_b = get_index_coord(end_pos);
			h = mix(texelFetch(_height_maps, coord_a, 0).r, texelFetch(_height_maps, coord_b, 0).r, vertex_lerp);
		}

		// Apply background ground level and region blend, dont include texel offset
		h = mix(h, ground_level, smoothstep(0.0, 1.0, get_region_blend(UV * _region_texel_size)));

		// World Noise
		if (_background_mode == 2u) {
			vec2 nuv_a = start_pos * _region_texel_size;
			vec2 nuv_b = end_pos * _region_texel_size;
			float nh = mix(get_noise_height(nuv_a), get_noise_height(nuv_b), vertex_lerp);
			float nu = mix(get_noise_height(nuv_a + vec2(_region_texel_size, 0.0)),
				get_noise_height(nuv_b + vec2(_region_texel_size, 0.0)), vertex_lerp);
			float nv = mix(get_noise_height(nuv_a + vec2(0.0, _region_texel_size)),
				get_noise_height(nuv_b + vec2(0.0, _region_texel_size)), vertex_lerp);
			world_noise_ddxy = vec2(nh - nu, nh - nv);
			h += nh;
		}

		if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer)) {
			displacement = mix(get_displacement(start_pos, scale), get_displacement(end_pos, scale * 2.0), vertex_lerp);
		}

		v_vertex.y = h;
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	// Include displacement without modifying v_vertex.
	VERTEX = (VIEW_MATRIX * vec4(v_vertex + displacement, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
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

void accumulate_texture(const mat3 TNB, const float weight, const float id_w, const int id,
		const vec2 i_uv, const vec2 i_pos, in vec4 i_dd, const mat2 p_align,
		const vec2 c_cs_angle, inout float world_normal, inout material mat) {

	float id_scale = _texture_uv_scale_array[id];
	vec4 id_dd = i_dd * id_scale;

	// Detiling and Control map rotation
	vec2 uv_center = floor(fma(i_pos, vec2(id_scale), vec2(0.5)));
	vec2 id_detile = fma(random(uv_center), 2.0, -1.0) * _texture_detile_array[id] * TAU;
	vec2 id_cs_angle = vec2(cos(id_detile.x), sin(id_detile.x));

	// Apply UV rotation and shift around pivot.
	vec2 id_uv = rotate_vec2(fma(i_uv, vec2(id_scale), -uv_center), id_cs_angle) + uv_center + id_detile.y - 0.5;

	// Manual transpose to rotate derivatives and normals counter to uv rotation
	// whilst also including control map rotation.
	id_cs_angle = vec2(
		fma(id_cs_angle.x, c_cs_angle.x, -id_cs_angle.y * c_cs_angle.y),
		fma(id_cs_angle.y, c_cs_angle.x, id_cs_angle.x * c_cs_angle.y));

	// Align derivatives for correct anisotropic filtering
	id_dd.xy = rotate_vec2(id_dd.xy, id_cs_angle);
	id_dd.zw = rotate_vec2(id_dd.zw, id_cs_angle);

	vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
	vec4 nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);

	alb.rgb *= _texture_color_array[id].rgb;
	nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);

	// Unpack and rotate normal map.
	nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
	float ao = length(nrm.xyz) * 2.0 - 1.0;
	ao = mix(ao * ao * _texture_ao_strength_array[id] + 1.0 - _texture_ao_strength_array[id], 1.0, alb.a * alb.a);
	nrm.xyz = normalize(nrm.xyz);
	nrm.xz = rotate_vec2(nrm.xz, id_cs_angle) * p_align;

	float sharpness = fma(56., blend_sharpness, 8.);
	float blend = weight + id_w + alb.a * world_normal;
	float id_weight = exp2(sharpness * log2(blend)) * id_w;

	mat.albedo_height = fma(alb, vec4(id_weight), mat.albedo_height);
	mat.normal_rough = fma(nrm, vec4(id_weight), mat.normal_rough);
	mat.normal_map_depth = fma(_texture_normal_depth_array[id], id_weight, mat.normal_map_depth);
	mat.ao = fma(ao, id_weight, mat.ao);
	mat.ao_affect = fma(_texture_ao_affect_array[id], id_weight, mat.ao_affect);
	mat.total_weight += id_weight;

	world_normal = clamp(fma(TNB[0], vec3(nrm.x), fma(TNB[2], vec3(nrm.z), TNB[1] * vec3(nrm.y))).y, 0., 1.);
	world_normal = mix(1., world_normal, smoothstep(0., 0.5, id_w));
}

// 2-4 lookups ( 2-6 with dual scaling )
void accumulate_material(vec3 base_ddx, vec3 base_ddy, const mat3 TNB, const float weight, const ivec3 index,
		const vec3 texture_weight, const ivec3 texture_id, const vec3 i_normal, float h, inout material mat) {

	// Applying scaling before projection reduces the number of multiplys ops required.
	vec3 i_vertex = v_vertex;

	// Control map scale
	float control_scale = 0.5;
	base_ddx *= control_scale;
	base_ddy *= control_scale;
	i_vertex *= control_scale;
	h *= control_scale;

	// Index position for detiling.
	vec2 i_pos = fma(_region_locations[index.z], vec2(_region_size), vec2(index.xy));
	i_pos *= _vertex_spacing * control_scale;

	// Projection
	vec2 i_uv = i_vertex.xz;
	vec4 i_dd = vec4(base_ddx.xz, base_ddy.xz);
	mat2 p_align = mat2(1.);

	if (i_normal.y <= 0.7071067811865475) {
		// Projected normal map alignment matrix
		p_align = mat2(vec2(i_normal.z, -i_normal.x), vec2(i_normal.x, i_normal.z));

		// Fast 45 degree snapping https://iquilezles.org/articles/noatan/
		vec2 xz = round(normalize(-i_normal.xz) * 1.3065629648763765);
		xz *= abs(xz.x) + abs(xz.y) > 1.5 ? 0.7071067811865475 : 1.0;
		xz = vec2(-xz.y, xz.x);

		i_pos = floor(vec2(dot(i_pos, xz), -h));
		i_uv = vec2(dot(i_vertex.xz, xz), -i_vertex.y);

		#ifndef IS_DISPLACEMENT_BUFFER
		i_dd.xy = vec2(dot(base_ddx.xz, xz), -base_ddx.y);
		i_dd.zw = vec2(dot(base_ddy.xz, xz), -base_ddy.y);
		#endif
	}

	// Control map rotation. Must be applied seperatley from detiling to maintain UV continuity.
	float c_angle = 0.; // currently not present in data.
	vec2 c_cs_angle = vec2(cos(c_angle), sin(c_angle));
	i_uv = rotate_vec2(i_uv, c_cs_angle);
	i_pos = rotate_vec2(i_pos, c_cs_angle);

	float world_normal = 1.;

	accumulate_texture(TNB, weight, texture_weight[0], texture_id[0],
			i_uv, i_pos, i_dd, p_align, c_cs_angle, world_normal, mat);

	accumulate_texture(TNB, weight, texture_weight[1], texture_id[1],
			i_uv, i_pos, i_dd, p_align, c_cs_angle, world_normal, mat);

	accumulate_texture(TNB, weight, texture_weight[2], texture_id[2],
			i_uv, i_pos, i_dd, p_align, c_cs_angle, world_normal, mat);
}

float get_height(vec2 index_id, vec2 offset) {
	float height = texelFetch(_height_maps, get_index_coord(index_id + offset), 0).r;
	if (_background_mode != 0u) {
		float blend = get_region_blend(index_id * _region_texel_size + offset * _region_texel_size);
		height = mix(height, ground_level, smoothstep(0., 1., blend));
	}

	return height;
}


void fragment() {
// -----------------------------------------------------------------------------
// Recover UVs
// -----------------------------------------------------------------------------

vec2 uv = UV;
vec2 uv2 = UV2;


// -----------------------------------------------------------------------------
// 4x4 Bicubic footprint
//
//             X
//        -1   0   1   2
//
//   -1    0   1   2   3
//    0    4   5   6   7
//    1    8   9  10  11
//    2   12  13  14  15
//
// The 16 locations remain independent throughout material accumulation.
// -----------------------------------------------------------------------------

vec2 index_id = floor(uv);
vec2 weight = fract(uv);

float x = weight.x;
float y = weight.y;


// -----------------------------------------------------------------------------
// bicubic weights
// -----------------------------------------------------------------------------

vec4 weights_x = vec4(
	(1.0 - x) * (1.0 - x) * (1.0 - x) / 6.0,
	(3.0 * x * x * x - 6.0 * x * x + 4.0) / 6.0,
	(-3.0 * x * x * x + 3.0 * x * x + 3.0 * x + 1.0) / 6.0,
	x * x * x / 6.0
);

vec4 weights_y = vec4(
	(1.0 - y) * (1.0 - y) * (1.0 - y) / 6.0,
	(3.0 * y * y * y - 6.0 * y * y + 4.0) / 6.0,
	(-3.0 * y * y * y + 3.0 * y * y + 3.0 * y + 1.0) / 6.0,
	y * y * y / 6.0
);


// -----------------------------------------------------------------------------
// 4x4 index coordinates
// -----------------------------------------------------------------------------

ivec3 index[16];

index[ 0] = get_index_coord(index_id + vec2(-1.0, -1.0));
index[ 1] = get_index_coord(index_id + vec2( 0.0, -1.0));
index[ 2] = get_index_coord(index_id + vec2( 1.0, -1.0));
index[ 3] = get_index_coord(index_id + vec2( 2.0, -1.0));

index[ 4] = get_index_coord(index_id + vec2(-1.0,  0.0));
index[ 5] = get_index_coord(index_id + vec2( 0.0,  0.0));
index[ 6] = get_index_coord(index_id + vec2( 1.0,  0.0));
index[ 7] = get_index_coord(index_id + vec2( 2.0,  0.0));

index[ 8] = get_index_coord(index_id + vec2(-1.0,  1.0));
index[ 9] = get_index_coord(index_id + vec2( 0.0,  1.0));
index[10] = get_index_coord(index_id + vec2( 1.0,  1.0));
index[11] = get_index_coord(index_id + vec2( 2.0,  1.0));

index[12] = get_index_coord(index_id + vec2(-1.0,  2.0));
index[13] = get_index_coord(index_id + vec2( 0.0,  2.0));
index[14] = get_index_coord(index_id + vec2( 1.0,  2.0));
index[15] = get_index_coord(index_id + vec2( 2.0,  2.0));


// -----------------------------------------------------------------------------
// Derivatives / region mip
// -----------------------------------------------------------------------------

vec3 base_ddx = dFdxCoarse(v_vertex);
vec3 base_ddy = dFdyCoarse(v_vertex);

float region_mip =
	log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);


// -----------------------------------------------------------------------------
// World noise
// -----------------------------------------------------------------------------

float u = 0.0;
float v = 0.0;

if (_background_mode == 2u && world_noise_fragment_normals) {
	float noise_height = get_noise_height(uv2);

	u += noise_height -
		get_noise_height(uv2 + vec2(_region_texel_size, 0.0));

	v += noise_height -
		get_noise_height(uv2 + vec2(0.0, _region_texel_size));
}

if (_background_mode == 2u && !world_noise_fragment_normals) {
	u += world_noise_ddxy.x;
	v += world_noise_ddxy.y;
}


// -----------------------------------------------------------------------------
// 4x4 height samples
// -----------------------------------------------------------------------------

float h[16];
h[ 5] = get_height(index_id, vec2( 0.0,  0.0));
h[ 6] = get_height(index_id, vec2( 1.0,  0.0));
h[ 7] = get_height(index_id, vec2( 2.0,  0.0));
h[ 9] = get_height(index_id, vec2( 0.0,  1.0));
h[10] = get_height(index_id, vec2( 1.0,  1.0));
h[11] = get_height(index_id, vec2( 2.0,  1.0));
h[13] = get_height(index_id, vec2( 0.0,  2.0));
h[14] = get_height(index_id, vec2( 1.0,  2.0));

vec3 index_normal[4];

index_normal[0] = normalize(vec3(h[ 5] - h[ 6] + u, _vertex_spacing, h[ 5] - h[ 9] + v));
index_normal[1] = normalize(vec3(h[ 6] - h[ 7] + u, _vertex_spacing, h[ 6] - h[10] + v));
index_normal[2] = normalize(vec3(h[ 9] - h[10] + u, _vertex_spacing, h[ 9] - h[13] + v));
index_normal[3] = normalize(vec3(h[10] - h[11] + u, _vertex_spacing, h[10] - h[14] + v));

vec3 w_normal = normalize(
	index_normal[0] * (weights_x.y * weights_y.y) +
	index_normal[1] * (weights_x.z * weights_y.y) +
	index_normal[2] * (weights_x.y * weights_y.z) +
	index_normal[3] * (weights_x.z * weights_y.z)
);


// -----------------------------------------------------------------------------
// Terrain tangent basis
// -----------------------------------------------------------------------------

vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));

vec3 w_binormal = normalize(cross(w_normal, w_tangent));

mat3 TNB = mat3(w_tangent, w_normal, w_binormal);


// -----------------------------------------------------------------------------
// Apply terrain normals
// -----------------------------------------------------------------------------

if (flat_terrain_normals) {
	NORMAL = normalize(cross(dFdyCoarse(VERTEX), dFdxCoarse(VERTEX)));
	TANGENT = normalize(cross(NORMAL, VIEW_MATRIX[2].xyz));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
} else {
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;
}


// -----------------------------------------------------------------------------
// Get 4x4 control data
// -----------------------------------------------------------------------------

uint control[16];
for (int i = 0; i < 16; i++) {
	control[i] = floatBitsToUint(texelFetch(_control_maps, index[i], 0).r);
}


// -----------------------------------------------------------------------------
// Auto blend calculation
// -----------------------------------------------------------------------------

float auto_base = clamp(
	fma(
		auto_slope * 2.0,
		w_normal.y - 1.0,
		1.0
	)
	- auto_height_reduction * 0.01 * v_vertex.y,
	0.0,
	1.0
);

float auto_under_over = smoothstep(
	auto_sea_level - auto_beach_height,
	auto_sea_level + auto_beach_height,
	v_vertex.y
);

vec3 auto_weights = vec3(
	1.0 - auto_base,
	auto_base * auto_under_over,
	auto_base * (1.0 - auto_under_over)
);

uint u_auto =
	((uint(auto_base_texture) & 0x1Fu) << 27u) |
	((uint(auto_overlay_texture) & 0x1Fu) << 22u) |
	((uint(auto_underlay_texture) & 0x1Fu) << 17u) |
	((uint(fma(auto_weights.x, 255.0, 0.5)) & 0xFFu) << 9u) |
	((uint(fma(auto_weights.y, 255.0, 0.5)) & 0xFFu) << 1u);


// Enable autoshader for painted/autoshader samples and samples outside regions.

for (int i = 0; i < 16; i++) {
	uint is_auto =
		(control[i] & 0x1u) |
		uint(index[i].z < 0);

	control[i] =
		control[i] * (1u - is_auto) +
		u_auto * is_auto;
}


// -----------------------------------------------------------------------------
// Decode texture IDs and weights.
// -----------------------------------------------------------------------------

ivec3 texture_ids[16];
vec3 texture_weights[16];

for (int i = 0; i < 16; i++) {
	uint c = control[i];

	texture_ids[i] = ivec3(
		int((c >> 27u) & 0x1Fu),
		int((c >> 22u) & 0x1Fu),
		int((c >> 17u) & 0x1Fu)
	);

	float weight_0 =
		float((c >> 9u) & 0xFFu) * DIV_255;

	float weight_1 =
		float((c >> 1u) & 0xFFu) * DIV_255;

	float weight_2 =
		max(0.0, 1.0 - weight_0 - weight_1);

	texture_weights[i] = vec3(
		weight_0,
		weight_1,
		weight_2
	);
}

vec3 source_weights[16];
for (int i = 0; i < 16; i++) {
	source_weights[i] = texture_weights[i];
}

for (int i = 0; i < 16; i++) {
	vec3 result = vec3(0.0);

	for (int j = 0; j < 16; j++) {
		float spatial_weight =
			weights_x[j & 3] * weights_y[j >> 2];

		vec3 w = source_weights[j] * spatial_weight;

		result += vec3(
			w.x * float(texture_ids[i].x == texture_ids[j].x) +
			w.y * float(texture_ids[i].x == texture_ids[j].y) +
			w.z * float(texture_ids[i].x == texture_ids[j].z),

			w.x * float(texture_ids[i].y == texture_ids[j].x) +
			w.y * float(texture_ids[i].y == texture_ids[j].y) +
			w.z * float(texture_ids[i].y == texture_ids[j].z),

			w.x * float(texture_ids[i].z == texture_ids[j].x) +
			w.y * float(texture_ids[i].z == texture_ids[j].y) +
			w.z * float(texture_ids[i].z == texture_ids[j].z)
		);
	}

	texture_weights[i] = result;
}

for (int i = 0; i < 16; i++) {
	float total =
		texture_weights[i].x +
		texture_weights[i].y +
		texture_weights[i].z;

	texture_weights[i] /= max(total, 1e-8);
}

// -----------------------------------------------------------------------------
// Material accumulation
//
// Each of the 16 control locations contributes independently.
//
// The bicubic coefficient belongs to the location, while texture_weights[i]
// remains the local 3-way blend at that location.
//
// No texture IDs are merged.
// -----------------------------------------------------------------------------

material mat = material(vec4(0.0), vec4(0.0), 0.0, 0.0, 0.0, 0.0);

accumulate_material(base_ddx, base_ddy, TNB, weights_x.y * weights_y.y,
	index[0], texture_weights[5], texture_ids[5], index_normal[0], h[5], mat);

accumulate_material(base_ddx, base_ddy, TNB, weights_x.z * weights_y.y,
	index[1], texture_weights[6], texture_ids[6], index_normal[1], h[6], mat);

accumulate_material(base_ddx, base_ddy, TNB, weights_x.y * weights_y.z,
	index[2], texture_weights[9], texture_ids[9], index_normal[2], h[9], mat);

accumulate_material(base_ddx, base_ddy, TNB, weights_x.z * weights_y.z,
	index[3], texture_weights[10], texture_ids[10], index_normal[3], h[10], mat);


// -----------------------------------------------------------------------------
// Normalize accumulated values back to 0.0 - 1.0 range.
// -----------------------------------------------------------------------------

float weight_inv = 1.0 / max(mat.total_weight, 1e-8);

mat.albedo_height *= weight_inv;
mat.normal_rough *= weight_inv;
mat.normal_map_depth *= weight_inv;
mat.ao *= weight_inv;
mat.ao_affect *= weight_inv;

// Macro variation. 2 lookups
	{
		float noise1 = texture(noise_texture, rotate_vec2(fma(uv, vec2(noise1_scale * .1), noise1_offset) , vec2(cos(noise1_angle), sin(noise1_angle)))).r;
		float noise2 = texture(noise_texture, uv * noise2_scale * .1).r;
		vec3 macrov = mix(macro_variation1, vec3(1.), noise1);
		macrov *= mix(macro_variation2, vec3(1.), noise2);
		mat.albedo_height.rgb *= mix(vec3(1.0), macrov, clamp(w_normal.y + macro_variation_slope, 0., 1.));
	}

	// Color map
	//vec4 col_map[4];
	//col_map[3] = index[3].z > -1 ? texelFetch(_color_maps, index[3], 0) : COLOR_MAP_DEF;
	//col_map[0] = index[0].z > -1 ? texelFetch(_color_maps, index[0], 0) : COLOR_MAP_DEF;
	//col_map[1] = index[1].z > -1 ? texelFetch(_color_maps, index[1], 0) : COLOR_MAP_DEF;
	//col_map[2] = index[2].z > -1 ? texelFetch(_color_maps, index[2], 0) : COLOR_MAP_DEF;
//
	//vec4 color_map =
			//col_map[0] * weights[0] +
			//col_map[1] * weights[1] +
			//col_map[2] * weights[2] +
			//col_map[3] * weights[3] ;

	vec4 color_map = vec4(1.);
	// Wetness/roughness modifier, converting 0 - 1 range to -1 to 1 range, clamped to Godot roughness values
	float roughness = clamp(fma(color_map.a - 0.5, 2.0, mat.normal_rough.a), 0., 1.);

	// Apply PBR
	ALBEDO = mat.albedo_height.rgb * color_map.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 1. - roughness;
	// Repack final normal map value.
	NORMAL_MAP = fma(normalize(mat.normal_rough.xzy), vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = mat.normal_map_depth;
	AO = clamp(mat.ao, 0., 1.);
	AO_LIGHT_AFFECT = mat.ao_affect;


}
