shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

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
#define SKIP_PASS 0
#define VERTEX_PASS 1
#define FRAGMENT_PASS 2
#define COLOR_MAP vec4(1.0, 1.0, 1.0, 0.5)
#define SQRT2_HALF 0.7071067811865476

// Inline Functions
#define DECODE_BLEND(control) float(control >> 14u & 0xFFu)
#define DECODE_AUTO(control) bool(control & 0x1u)
#define DECODE_BASE(control) int(control >> 27u & 0x1Fu)
#define DECODE_OVER(control) int(control >> 22u & 0x1Fu)
#define DECODE_ANGLE(control) float(control >>10u & 0xFu) * 0.0625 * TAU
#define DECODE_SCALE(control) scale_array[(control >>7u & 0x7u)]
#define DECODE_HOLE(control) bool(control >>2u & 0x1u)

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    #define fma(a, b, c) ((a) * (b) + (c))
    #define dFdxCoarse(a) dFdx(a)
    #define dFdyCoarse(a) dFdy(a)
#endif

const float[8] scale_array = float[8](0.5, 0.4, 0.3, 0.2, 0.1, 0.8, 0.7, 0.6);

// Private uniforms
uniform vec3 _camera_pos = vec3(0.f);
uniform float _mesh_size = 48.f;
uniform uint _background_mode = 1u; // NONE = 0, FLAT = 1, NOISE = 2
uniform uint _mouse_layer = 0x80000000u; // Layer 32
uniform float _vertex_spacing = 1.0;
uniform float _vertex_density = 1.0; // = 1/_vertex_spacing
uniform float _region_size = 1024.0;
uniform float _region_texel_size = 0.0009765625; // = 1/1024
uniform int _region_map_size = 32;
uniform int _region_map[1024];
uniform vec2 _region_locations[1024];
uniform float _texture_normal_depth_array[32];
uniform float _texture_ao_strength_array[32];
uniform float _texture_roughness_mod_array[32];
uniform float _texture_uv_scale_array[32];
uniform vec2 _texture_detile_array[32];
uniform vec4 _texture_color_array[32];
uniform highp sampler2DArray _height_maps : repeat_disable;
uniform highp sampler2DArray _control_maps : repeat_disable;
#define FILTER_LINEAR
uniform highp sampler2DArray _color_maps : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform highp sampler2DArray _texture_array_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform highp sampler2DArray _texture_array_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;


// Public uniforms
uniform float auto_slope : hint_range(0, 10) = 1.0;
uniform float auto_height_reduction : hint_range(0, 1) = 0.1;
uniform int auto_base_texture : hint_range(0, 31) = 0;
uniform int auto_overlay_texture : hint_range(0, 31) = 1;

uniform int dual_scale_texture : hint_range(0,31) = 0;
uniform float dual_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float tri_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float dual_scale_far : hint_range(0,1000) = 170.0;
uniform float dual_scale_near : hint_range(0,1000) = 100.0;

uniform bool height_blending = true;
uniform bool world_space_normal_blend = true;
uniform float blend_sharpness : hint_range(0, 1) = 0.87;

uniform bool enable_projection = true;
uniform float projection_threshold : hint_range(0.0, 0.99, 0.01) = 0.8;
uniform float projection_angular_division : hint_range(1.0, 16.0, 0.001) = 2.0;

uniform float mipmap_bias : hint_range(0.5, 1.5, 0.01) = 1.0;
uniform float depth_blur : hint_range(0.0, 35.0, 0.1) = 0.0;
uniform float bias_distance : hint_range(0.0, 16384.0, 0.1) = 512.0;

uniform bool enable_macro_variation = true;
uniform vec3 macro_variation1 : source_color = vec3(1.);
uniform vec3 macro_variation2 : source_color = vec3(1.);
uniform float macro_variation_slope : hint_range(0., 1.)  = 0.333;

// Generic noise at 3 scales, which can be used for anything 
uniform highp sampler2D noise_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform float noise1_scale : hint_range(0.001, 1.) = 0.04; // Used for macro variation 1. Scaled up 10x
uniform float noise1_angle : hint_range(0, 6.283) = 0.;
uniform vec2 noise1_offset = vec2(0.5);
uniform float noise2_scale : hint_range(0.001, 1.) = 0.076;	// Used for macro variation 2. Scaled up 10x
uniform float noise3_scale : hint_range(0.001, 1.) = 0.225; // Used for texture blending edge

// Varyings & Types

struct Material {
	vec4 alb_ht;
	vec4 nrm_rg;
	int base;
	int over;
	float nrm_depth;
	float ao_str;
};


varying float v_vertex_xz_dist;
varying vec3 v_vertex;

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

// World Noise
uniform bool world_noise_fragment_normals = false;
uniform float world_noise_region_blend : hint_range(0.05, 0.95, 0.01) = 0.33;
uniform int world_noise_max_octaves : hint_range(0, 15) = 4;
uniform int world_noise_min_octaves : hint_range(0, 15) = 2;
uniform float world_noise_lod_distance : hint_range(0, 40000, 1) = 7500.;
uniform float world_noise_scale : hint_range(0.25, 20, 0.01) = 5.0;
uniform float world_noise_height : hint_range(0, 1000, 0.1) = 64.0;
uniform vec3 world_noise_offset = vec3(0.0);
varying vec2 world_noise_ddxy;

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
float region_blend(vec2 uv2) {
	uv2 -= 0.5;
	const vec2 offset = vec2(0.0,1.0);
	float a = check_region(uv2 + offset.xy);
	float b = check_region(uv2 + offset.yy);
	float c = check_region(uv2 + offset.yx);
	float d = check_region(uv2 + offset.xx);
	vec2 w = smoothstep(vec2(0.0), vec2(1.0), fract(uv2));
	float blend = mix(mix(d, c, w.x), mix(a, b, w.x), w.y);
    return 1.0 - blend;
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
    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0);

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
    float k3 =   a - b - c + d;
    return vec3( k0 + k1 * u.x + k2 * u.y + k3 * u.x * u.y,
                du * ( vec2(k1, k2) + k3 * u.yx) );
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
	float weight = region_blend(uv);
	// only calculate world noise when it could be visibile.
	if (weight <= 1.0 - world_noise_region_blend) {
		return 0.0;
	}
	//TODO: Offset/scale UVs are semi-dependent upon region size 1024. Base on v_vertex.xz instead
	float noise = world_noise((uv + world_noise_offset.xz * 1024. / _region_size) * world_noise_scale * _region_size / 1024. * .1) *
            world_noise_height * 10. + world_noise_offset.y * 100.;
	weight = smoothstep(1.0 - world_noise_region_blend, 1.0, weight);
	return mix(0.0, noise, weight);
}

// World Noise end

void vertex() {
	// Get vertex of flat plane in world coordinates and set world UV
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Camera distance to vertex on flat plane
	v_vertex_xz_dist = length(v_vertex.xz - _camera_pos.xz);

	// Geomorph vertex, set end and start for linear height interpolate
	float scale = MODEL_MATRIX[0][0];
	float vertex_lerp = smoothstep(0.55, 0.95, (v_vertex_xz_dist / scale - _mesh_size - 4.0) / (_mesh_size - 2.0));
	vec2 v_fract = fract(VERTEX.xz * 0.5) * 2.0;
	// For LOD0 morph from a regular grid to an alternating grid to align with LOD1+
	vec2 shift = (scale < _vertex_spacing + 1e-6) ? // LOD0 or not
		// Shift from regular to symetric
		mix(v_fract, vec2(v_fract.x, -v_fract.y),
			round(fract(round(mod(v_vertex.z * _vertex_density, 4.0)) *
			round(mod(v_vertex.x * _vertex_density, 4.0)) * 0.25))
			) :
		// Symetric shift
		v_fract * round((fract(v_vertex.xz * 0.25 / scale) - 0.5) * 4.0);
	vec2 start_pos = v_vertex.xz * _vertex_density;
	vec2 end_pos = (v_vertex.xz - shift * scale) * _vertex_density;
	v_vertex.xz -= shift * scale * vertex_lerp;

	// UV coordinates in world space. Values are 0 to _region_size within regions
	UV = v_vertex.xz * _vertex_density;

	// UV coordinates in region space + texel offset. Values are 0 to 1 within regions
	UV2 = fma(UV, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));

	// Discard vertices for Holes. 1 lookup
	ivec3 v_region = get_index_coord(start_pos, VERTEX_PASS);
	uint control = floatBitsToUint(texelFetch(_control_maps, v_region, 0)).r;
	bool hole = DECODE_HOLE(control);

	// Show holes to all cameras except mouse camera (on exactly 1 layer)
	if ( !(CAMERA_VISIBLE_LAYERS == _mouse_layer) && 
			(hole || (_background_mode == 0u && v_region.z == -1))) {
		v_vertex.x = 0. / 0.;
	} else {		
		// Set final vertex height & calculate vertex normals. 3 lookups
		ivec3 coord_a = get_index_coord(start_pos, VERTEX_PASS);
		ivec3 coord_b = get_index_coord(end_pos, VERTEX_PASS);
		float h = mix(texelFetch(_height_maps, coord_a, 0).r,texelFetch(_height_maps, coord_b, 0).r,vertex_lerp);
		// World Noise
		if (_background_mode == 2u) {
			vec2 nuv_a = fma(start_pos, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));
			vec2 nuv_b = fma(end_pos, vec2(_region_texel_size), vec2(0.5 * _region_texel_size));
			float nh = mix(get_noise_height(nuv_a),get_noise_height(nuv_b),vertex_lerp);
			float nu = mix(get_noise_height(nuv_a + vec2(_region_texel_size, 0.0)),
				get_noise_height(nuv_b + vec2(_region_texel_size, 0.0)),vertex_lerp);
			float nv = mix(get_noise_height(nuv_a + vec2(0.0, _region_texel_size)),
				get_noise_height(nuv_b + vec2(0.0, _region_texel_size)),vertex_lerp);
			world_noise_ddxy = vec2(nh - nu, nh - nv);
			h += nh;
		}

		v_vertex.y = h;
	}

	// Convert model space to view space w/ skip_vertex_transform render mode
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	NORMAL = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	BINORMAL = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
	TANGENT = normalize((MODELVIEW_MATRIX * vec4(TANGENT, 0.0)).xyz);
}

////////////////////////
// Fragment
////////////////////////

vec3 unpack_normal(vec4 rgba) {
	return fma(rgba.xzy, vec3(2.0), vec3(-1.0));
}

vec3 pack_normal(vec3 n) {
	return fma(normalize(n.xzy), vec3(0.5), vec3(0.5));
}

float random(in vec2 xy) {
	return fract(sin(dot(xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(fma(cosa, v.x, - sina * v.y), fma(sina, v.x, cosa * v.y));
}

// Moves a point around a pivot point.
vec2 rotate_around(vec2 point, vec2 pivot, float angle){
	float x = pivot.x + (point.x - pivot.x) * cos(angle) - (point.y - pivot.y) * sin(angle);
	float y = pivot.y + (point.x - pivot.x) * sin(angle) + (point.y - pivot.y) * cos(angle);
	return vec2(x, y);
}

//vec4 height_blend4(vec4 a_value, float a_height, vec4 b_value, float b_height, float blend) {
	//if(height_blending) {
		//float ma = max(a_height + (1.0 - blend), b_height + blend) - (1.001 - blend_sharpness);
	    //float b1 = max(a_height + (1.0 - blend) - ma, 0.0);
	    //float b2 = max(b_height + blend - ma, 0.0);
	    //return (a_value * b1 + b_value * b2) / (b1 + b2);
	//} else {
		//float contrast = 1.0 - blend_sharpness;
		//float factor = (blend - contrast) / contrast;
		//return mix(a_value, b_value, clamp(factor, 0.0, 1.0));
	//}
//}

//float height_blend1(float a_value, float a_height, float b_value, float b_height, float blend) {
	//if(height_blending) {
		//float ma = max(a_height + (1.0 - blend), b_height + blend) - (1.001 - blend_sharpness);
	    //float b1 = max(a_height + (1.0 - blend) - ma, 0.0);
	    //float b2 = max(b_height + blend - ma, 0.0);
	    //return (a_value * b1 + b_value * b2) / (b1 + b2);
	//} else {
		//float contrast = 1.0 - blend_sharpness;
		//float factor = (blend - contrast) / contrast;
		//return mix(a_value, b_value, clamp(factor, 0.0, 1.0));
	//}
//}

vec2 detiling(vec2 uv, vec2 uv_center, int mat_id, inout float normal_rotation){
	if ((_texture_detile_array[mat_id].x + _texture_detile_array[mat_id].y) >= 0.001){
		uv_center = floor(uv_center) + 0.5;
		float detile = fma(random(uv_center), 2.0, -1.0) * TAU; // -180deg to 180deg
		// Rotation
		float rotation = detile * _texture_detile_array[mat_id].x;
		uv = rotate_around(uv, uv_center, rotation);
		// Accumulate total rotation for normal rotation
		normal_rotation += rotation;
		// Shift
		uv += rotate(vec2(_texture_detile_array[mat_id].y * detile), cos(detile), sin(detile));
	}
	return uv;
}

mat2 rotate_plane(float angle) {
	float c = cos(angle), s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c));
}

//// 2-4 lookups ( 2-6 with dual scaling )
//void get_material(vec3 i_normal, float i_height, vec4 ddxy, uint control, ivec3 index, mat3 TANGENT_WORLD_MATRIX, out Material out_mat, float blend) {
	//out_mat = Material(vec4(0.), vec4(0.), 0, 0, 0.0, 0.0);
	//vec2 index_pos = vec2(index.xy);
	//
	//// Translate index position to world space.
	//index_pos += _region_locations[index.z] * _region_size;
	//index_pos *= _vertex_spacing;
	//
	//vec2 base_uv;
	//float p_angle = 0.0;
	//
	//if (i_normal.y >= projection_threshold || !enable_projection) {
		//base_uv = v_vertex.xz;
	//} else {
		//// Project UVs and determine surface normal angle
		//// Quantize the normal otherwise textures lose continuity across domains
		//// Avoid potential singularitys for unit length normal, usually worst case would be
		//// sqrt(3.0)/2.0, however as we are nullifying y component and renormalizing, 
		//// we can use sqrt(2.0)/2.0, as a lower bound.
		//
		//vec3 p_normal = normalize(vec3(i_normal.x, 0., i_normal.z));
		//p_normal = normalize(round(p_normal * SQRT2_HALF * projection_angular_division));
		//vec3 p_tangent = normalize(cross(p_normal, vec3(0., 1., 0.)));
		//vec3 p_binormal = normalize(cross(p_tangent, p_normal));
		//p_angle = atan(-i_normal.x, -i_normal.z);
		//base_uv = vec2(dot(v_vertex, p_tangent), dot(v_vertex, p_binormal));
		//// Project uv_center for detiling
		//vec3 i_pos = vec3(index_pos.x, i_height, index_pos.y);
		//index_pos = vec2(dot(i_pos, p_tangent), dot(i_pos, p_binormal));
	//}

	// Enable Autoshader if outside regions or painted in regions, otherwise manual painted
	//bool auto_shader = index.z < 0 || DECODE_AUTO(control);
	//out_mat.base = int(auto_shader) * auto_base_texture + int(!auto_shader) * DECODE_BASE(control);
	//out_mat.over = int(auto_shader) * auto_overlay_texture + int(!auto_shader) * DECODE_OVER(control);
	//blend = float(auto_shader) * clamp(
			//(auto_slope * 2. * ( TANGENT_WORLD_MATRIX[1].y - 1.) + 1.)
			//- auto_height_reduction * .01 * v_vertex.y // Reduce as vertices get higher
			//, 0., 1.) + 
			 //float(!auto_shader) * blend;

	//out_mat.nrm_depth = _texture_normal_depth_array[out_mat.base];
	//out_mat.ao_str = _texture_ao_strength_array[out_mat.base];

	// Control map scale & rotation, apply to both base and uv_center.
	// Define base scale from control map value as array index. 0.5 as baseline.
	//float control_scale = DECODE_SCALE(control);
	//base_uv *= control_scale;
	//index_pos *=  control_scale;
	//ddxy *= control_scale;
//
	//// Apply global uv rotation from control map
	//float uv_rotation = DECODE_ANGLE(control);
	//base_uv = rotate_around(base_uv, vec2(0), uv_rotation);
	//index_pos = rotate_around(index_pos, vec2(0), uv_rotation);
//
	//vec2 matUV = base_uv;
	//vec4 albedo_ht = vec4(0.);
	//vec4 normal_rg = vec4(0.5, 0.5, 1.0, 1.0);
	//vec4 albedo_far = vec4(0.);
	//vec4 normal_far = vec4(0.5, 0.5, 1.0, 1.0);
	//float mat_scale = _texture_uv_scale_array[out_mat.base];
	//float normal_angle = uv_rotation + p_angle;
	//vec4 dd1 = ddxy;
	//
	//// If dual scaling, apply to base texture.
	//if(index.z < 0) {
		//mat_scale *= tri_scale_reduction;
	//}
	//float far_factor = clamp(smoothstep(dual_scale_near, dual_scale_far, length(v_vertex - _camera_pos)), 0.0, 1.0);
	//if (blend < 1.0 && (
			//(far_factor < 1. && (out_mat.base == dual_scale_texture)) || out_mat.base != dual_scale_texture)) {
		//// 2 lookups
		////each time we change scale, recalculate antitiling from baseline to maintain continuity.
		//matUV = detiling(base_uv * mat_scale, index_pos * mat_scale, out_mat.base, normal_angle);
		//mat2 normal_align = rotate_plane(-normal_angle);
		//dd1.xy *= normal_align;
		//dd1.zw *= normal_align;
		//dd1 *= mat_scale;
		//albedo_ht = textureGrad(_texture_array_albedo, vec3(matUV, float(out_mat.base)), dd1.xy, dd1.zw);
		//normal_rg = textureGrad(_texture_array_normal, vec3(matUV, float(out_mat.base)), dd1.xy, dd1.zw);
//
		//// Unpack & rotate base normal for blending
		//normal_rg.xyz = unpack_normal(normal_rg);
		//normal_rg.xz *= normal_align;
	//}
//
	//if (far_factor > 0. && ((out_mat.base == dual_scale_texture && blend < 1.0)
			//|| (out_mat.over == dual_scale_texture && blend > 0.0))) {
		//// 2 lookups
		//mat_scale *= dual_scale_reduction;
		//float dual_scale_normal = uv_rotation + p_angle; //do not add near & far rotations
		//// Do not apply detiling if tri-scale reduction occurs.
		//matUV = index.z < 0 ? base_uv * mat_scale : detiling(base_uv * mat_scale, index_pos * mat_scale, dual_scale_texture, dual_scale_normal);
		//mat2 normal_align_far = rotate_plane(-dual_scale_normal);
		//vec4 dd_far = ddxy * mat_scale;
		//dd_far.xy *= normal_align_far;
		//dd_far.zw *= normal_align_far;
		//albedo_far = textureGrad(_texture_array_albedo, vec3(matUV, float(dual_scale_texture)), dd_far.xy, dd_far.zw);
		//normal_far = textureGrad(_texture_array_normal, vec3(matUV, float(dual_scale_texture)), dd_far.xy, dd_far.zw);
//
		//// Unpack & rotate dual scale normal for blending
		//normal_far.xyz = unpack_normal(normal_far);
		//normal_far.xz *= normal_align_far;
	//}
	//
	//if (out_mat.base == dual_scale_texture) {
		//albedo_ht = mix(albedo_ht, albedo_far, far_factor);
		//normal_rg = mix(normal_rg, normal_far, far_factor);
	//}
//
	//// Apply color to base
	//albedo_ht.rgb *= _texture_color_array[out_mat.base].rgb;
//
	//// Apply Roughness modifier to base
	//normal_rg.a = clamp(normal_rg.a + _texture_roughness_mod_array[out_mat.base], 0., 1.);
//
	//out_mat.alb_ht = albedo_ht;
	//out_mat.nrm_rg = normal_rg;
//
	//if (blend > 0.) {
		//// 2 lookups
		//// Setup overlay texture to blend
		//float mat_scale2 = _texture_uv_scale_array[out_mat.over];
		//float normal_angle2 = uv_rotation + p_angle;
		//vec2 matUV2 = detiling(base_uv * mat_scale2, index_pos * mat_scale2, out_mat.over, normal_angle2);
		//vec4 dd2 = ddxy * mat_scale2;
		//mat2 normal_align2 = rotate_plane(-normal_angle2);
		//dd2.xy *= normal_align2;
		//dd2.zw *= normal_align2;
		//vec4 albedo_ht2 = textureGrad(_texture_array_albedo, vec3(matUV2, float(out_mat.over)), dd2.xy, dd2.zw);
		//vec4 normal_rg2 = textureGrad(_texture_array_normal, vec3(matUV2, float(out_mat.over)), dd2.xy, dd2.zw);
//
		//// Unpack & rotate overlay normal for blending
		//normal_rg2.xyz = unpack_normal(normal_rg2);
		//normal_rg2.xz *= normal_align2;
//
		//// If dual scaling, apply to overlay texture
		//if(out_mat.over == dual_scale_texture) {
			//albedo_ht2 = mix(albedo_ht2, albedo_far, far_factor);
			//normal_rg2 = mix(normal_rg2, normal_far, far_factor);
		//}
//
		//// Apply color to overlay
		//albedo_ht2.rgb *= _texture_color_array[out_mat.over].rgb;
//
		//// Apply Roughness modifier to overlay
		//normal_rg2.a = clamp(normal_rg2.a + _texture_roughness_mod_array[out_mat.over], 0., 1.);
//
		//// apply world space normal weighting from base, to overlay layer
		//float over_blend = albedo_ht2.a; // dont modify actual height value
		//if (world_space_normal_blend) {
			//over_blend *= bool(control >>3u & 0x1u) ? 1.0 : clamp((TANGENT_WORLD_MATRIX * normal_rg.xyz).y, 0.0, 1.0);
		//}
//
		//// Blend overlay and base
		//out_mat.alb_ht = height_blend4(albedo_ht, albedo_ht.a, albedo_ht2, over_blend, blend);
		//out_mat.nrm_rg = height_blend4(normal_rg, albedo_ht.a, normal_rg2, over_blend, blend);
		//out_mat.nrm_depth = height_blend1(_texture_normal_depth_array[out_mat.base], albedo_ht.a,
			//_texture_normal_depth_array[out_mat.over], over_blend, blend);
		//out_mat.ao_str = height_blend1(_texture_ao_strength_array[out_mat.base], albedo_ht.a,
			//_texture_ao_strength_array[out_mat.over], over_blend, blend);
	//}
	//return;
//}

float blend_weights(float weight, float detail) {
	float result = max(0.1 * weight, fma(10.0, (weight + detail), 1.0f - (detail + 10.0)));
	return result;
}

struct i_data {
	int base;
	int over;
	float blend;
	float angle;
	float scale;
	bool auto;
};
#define I_DATA(c) i_data(DECODE_BASE(c), DECODE_OVER(c), DECODE_BLEND(c) * 0.003921568627450, DECODE_ANGLE(c), DECODE_SCALE(c), DECODE_AUTO(c))

void fragment() {
	// Recover UVs
	vec2 uv = UV;
	vec2 uv2 = UV2;
	
	// Lookup offsets, ID and blend weight
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
	
	vec3 base_ddx = dFdxCoarse(v_vertex);
	vec3 base_ddy = dFdyCoarse(v_vertex);
	vec4 base_derivatives = vec4(base_ddx.xz, base_ddy.xz);
	// Calculate the effective mipmap for regionspace, and when less than 0,
	// skip all extra lookups required for bilinear blend.
	float region_mip = log2(max(length(base_ddx.xz), length(base_ddy.xz)) * _vertex_density);
	bool bilerp = region_mip < 0.0;

	ivec3 index[4];
	// control map lookups, used for some normal lookups as well
	index[0] = get_index_coord(index_id + offsets.xy, FRAGMENT_PASS);
	index[1] = get_index_coord(index_id + offsets.yy, FRAGMENT_PASS);
	index[2] = get_index_coord(index_id + offsets.yx, FRAGMENT_PASS);
	index[3] = get_index_coord(index_id + offsets.xx, FRAGMENT_PASS);
	
	// Terrain normals
	vec3 index_normal[4];
	float h[8];
	// allows additional derivatives, eg world noise, brush previews etc
	float u = 0.0;
	float v = 0.0;
	
	// World Noise
	if (_background_mode == 2u && world_noise_fragment_normals) {
		float noise_height = get_noise_height(uv2);
		u += noise_height - get_noise_height(uv2 + vec2(_region_texel_size, 0.0));
		v += noise_height - get_noise_height(uv2 + vec2(0.0, _region_texel_size));
	}
	if (_background_mode == 2u && !world_noise_fragment_normals) {
		u += world_noise_ddxy.x;
		v += world_noise_ddxy.y;
	}
	// Re-use index[] for the first lookups, skipping some math. 3 lookups
	h[3] = texelFetch(_height_maps, index[3], 0).r; // 0 (0,0)
	h[2] = texelFetch(_height_maps, index[2], 0).r; // 1 (1,0)
	h[0] = texelFetch(_height_maps, index[0], 0).r; // 2 (0,1)
	index_normal[3] = normalize(vec3(h[3] - h[2] + u, _vertex_spacing, h[3] - h[0] + v));

	// Set flat world normal - overriden if bilerp is true
	vec3 w_normal = index_normal[3];

	// Setting this here, instead of after the branch appears to be ~10% faster.
	// Likley as flat derivatives seem more cache friendly for texture lookups.
	if (enable_projection && w_normal.y < projection_threshold) {
		vec3 p_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
		vec3 p_binormal = normalize(cross(p_tangent, w_normal));
		base_derivatives.xy = vec2(dot(base_ddx, p_tangent), dot(base_ddx, p_binormal));
		base_derivatives.zw = vec2(dot(base_ddy, p_tangent), dot(base_ddy, p_binormal));
	}
	
	// Adjust derivatives for mipmap bias and depth blur effect
	base_derivatives *=  mix(mipmap_bias,
		depth_blur + 1.,
		smoothstep(0.0, 1.0, (v_vertex_xz_dist - bias_distance) / bias_distance));

	// Branching smooth normals.
	if (bilerp) {
		// 5 lookups
		// Fetch the additional required height values for smooth normals
		h[1] = texelFetch(_height_maps, index[1], 0).r; // 3 (1,1)
		h[4] = texelFetch(_height_maps, get_index_coord(index_id + offsets.yz, FRAGMENT_PASS), 0).r; // 4 (1,2)
		h[5] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zy, FRAGMENT_PASS), 0).r; // 5 (2,1)
		h[6] = texelFetch(_height_maps, get_index_coord(index_id + offsets.zx, FRAGMENT_PASS), 0).r; // 6 (2,0)
		h[7] = texelFetch(_height_maps, get_index_coord(index_id + offsets.xz, FRAGMENT_PASS), 0).r; // 7 (0,2)

		// Calculate the normal for the remaining index ids.
		index_normal[0] = normalize(vec3(h[0] - h[1] + u, _vertex_spacing, h[0] - h[7] + v));
		index_normal[1] = normalize(vec3(h[1] - h[5] + u, _vertex_spacing, h[1] - h[4] + v));
		index_normal[2] = normalize(vec3(h[2] - h[6] + u, _vertex_spacing, h[2] - h[1] + v));

		// Set interpolated world normal
		w_normal = 
			index_normal[0] * weights[0] +
			index_normal[1] * weights[1] +
			index_normal[2] * weights[2] +
			index_normal[3] * weights[3] ;
	}
		
	// Apply terrain normals
	vec3 w_tangent = normalize(cross(w_normal, vec3(0.0, 0.0, 1.0)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;
	
	// Used for material world space normal map blending
	mat3 TANGENT_WORLD_MATRIX = mat3(w_tangent, w_normal, w_binormal);

	// Get index control data
	// 4 lookups
	uint control[4] = {
		floatBitsToUint(texelFetch(_control_maps, index[0], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[1], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[2], 0).r),
		floatBitsToUint(texelFetch(_control_maps, index[3], 0).r)
	};

	// Parse all control map data
	i_data data[4] = {
		I_DATA(control[0]),
		I_DATA(control[1]),
		I_DATA(control[2]),
		I_DATA(control[3])
	};
	
	// Autoshader
	float auto_blend = clamp((auto_slope * 2. * ( TANGENT_WORLD_MATRIX[1].y - 1.) + 1.)
			- auto_height_reduction * .01 * v_vertex.y // Reduce as vertices get higher
			, 0., 1.);
	//TODO - unroll this
	for (int i = 0; i < 4; i++) {
		if (index[i].z < 0 || data[i].auto) {
			data[i].base = auto_base_texture;
			data[i].over = auto_overlay_texture;
			data[i].blend = auto_blend;
		}
	}
	
	// pre-outs
	vec4 color_map = COLOR_MAP;
	vec4 normal_rough = vec4(0.);
	vec4 albedo_height = vec4(0.);
	float normal_map_depth = 0.;
	float ao_strength = 0.;

	// Set per texture ID weighting.
	float t_weight[32] = float[32](
		0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.,0.
	);
	//TODO - unroll this
	for (int i = 0; i < 4; i++) {
		t_weight[data[i].base] += weights[i] * clamp(fma(1.0 - data[i].blend, 1.01, -0.005), 0., 1.);
		t_weight[data[i].over] += weights[i] * clamp(fma(data[i].blend, 1.01, -0.005), 0., 1.);
	}
	float total_weight = 0.;
	//TODO make this better, maybe avoid the pow() function where this is used somehow?
	float sharpness = mix(8., 64., blend_sharpness);
	//TODO - unroll this, and the inner loop, branching like this does seem to work,
	// but it may be more reliable on older hardware to unroll.
	for (int i = 0; i < 4; i++) {
		if (!bilerp && i != 3) {
			continue;
		}
		// Index position for detiling & projection.
		vec2 i_pos = vec2(index[i].xy);
		i_pos += _region_locations[index[i].z] * _region_size;
		i_pos *= _vertex_spacing;
		
		// Projection
		vec2 i_uv;
		float p_angle = 0.0;
		if (index_normal[i].y >= projection_threshold || !enable_projection) {
			i_uv = uv;
		} else {
			// Project UVs and determine surface normal angle
			// Quantize the normal otherwise textures lose continuity across domains
			// Avoid potential singularitys for unit length normal, usually worst case would be
			// sqrt(3.0)/2.0, however as we are nullifying y component and renormalizing, 
			// we can use sqrt(2.0)/2.0, as a lower bound.
			vec3 p_normal = normalize(vec3(index_normal[i].x, 0., index_normal[i].z));
			p_normal = normalize(round(p_normal * SQRT2_HALF * projection_angular_division));
			vec3 p_tangent = normalize(cross(p_normal, vec3(0., 1., 0.)));
			vec3 p_binormal = normalize(cross(p_tangent, p_normal));
			p_angle = atan(-index_normal[i].x, -index_normal[i].z);
			i_uv = vec2(dot(v_vertex, p_tangent), dot(v_vertex, p_binormal));
			// Project uv_center for detiling
			vec3 p_pos = vec3(i_pos.x, h[i], i_pos.y);
			i_pos = vec2(dot(p_pos, p_tangent), dot(p_pos, p_binormal));
		}
		
		// Control map scale & rotation
		vec4 i_dd = base_derivatives * data[i].scale;
		i_uv *= data[i].scale;
		i_pos *= data[i].scale;
		i_uv = rotate_around(i_uv, vec2(0), data[i].angle);
		i_pos = rotate_around(i_pos, vec2(0), data[i].angle);
		
		// world normal adjustment requires acess to base layer from next iteration
		vec4 nrm = vec4(0.,1.,0.,1.); // if base is skipped we dont want to reduce any of the overlay height value
		for (int l = 0; l < 2; l++) {
			int id = l == 0 ? data[i].base : data[i].over;
			if (t_weight[id] <= 0.001) {
				continue;
			}
			//do this before its overwriten
			float world_normal = (l == 0 ? 1. : clamp((TANGENT_WORLD_MATRIX * normalize(nrm.xyz)).y, 0., 1.));
			float id_scale = _texture_uv_scale_array[id];
			float id_angle = data[i].angle + p_angle;
			vec2 id_uv = detiling(i_uv * id_scale, i_pos * id_scale, id, id_angle);
			mat2 id_align = rotate_plane(-id_angle);
			vec4 id_dd = i_dd * id_scale;
			id_dd.xy *= id_align;
			id_dd.zw *= id_align;
			vec4 alb = textureGrad(_texture_array_albedo, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
			nrm = textureGrad(_texture_array_normal, vec3(id_uv, float(id)), id_dd.xy, id_dd.zw);
			alb.rgb *= _texture_color_array[id].rgb;
			nrm.a = clamp(nrm.a + _texture_roughness_mod_array[id], 0., 1.);
			nrm.xyz = fma(nrm.xzy, vec3(2.0), vec3(-1.0));
			nrm.xz *= id_align;
			
			float id_weight = pow(weights[i] + t_weight[id] + alb.a * world_normal, sharpness);
			albedo_height += alb * id_weight;
			normal_rough += nrm * id_weight;
			normal_map_depth += _texture_normal_depth_array[id] * id_weight;
			ao_strength += _texture_ao_strength_array[id] * id_weight;
			total_weight += id_weight;
		}
	}
	float t_inv = 1.0 / total_weight;
	albedo_height *= t_inv;
	normal_rough *= t_inv;
	normal_map_depth *= t_inv;
	ao_strength *= t_inv;

	// Macro variation. 2 lookups
	vec3 macrov = vec3(1.);
	if (enable_macro_variation) {
		float noise1 = texture(noise_texture, rotate(uv * noise1_scale * .1, cos(noise1_angle), sin(noise1_angle)) + noise1_offset).r;
		float noise2 = texture(noise_texture, uv * noise2_scale * .1).r;
		macrov = mix(macro_variation1, vec3(1.), noise1);
		macrov *= mix(macro_variation2, vec3(1.), noise2);
		macrov = mix(vec3(1.0), macrov, clamp(w_normal.y + macro_variation_slope, 0., 1.));
	}
	
	// Wetness/roughness modifier, converting 0 - 1 range to -1 to 1 range
	float roughness = fma(color_map.a - 0.5, 2.0, normal_rough.a);
	
	// Apply PBR
	ALBEDO = albedo_height.rgb * color_map.rgb * macrov;
	ROUGHNESS = roughness;
	SPECULAR = 1. - normal_rough.a;
	NORMAL_MAP = fma(normalize(normal_rough.xzy), vec3(0.5), vec3(0.5));
	NORMAL_MAP_DEPTH = normal_map_depth;

	// Higher and/or facing up, less occluded.
	float ao = (1. - (albedo_height.a * log(2.1 - ao_strength))) * (1. - normal_rough.y);
	AO = clamp(1. - ao * ao_strength, albedo_height.a, 1.0);
	AO_LIGHT_AFFECT = 1. - albedo_height.a;

}

