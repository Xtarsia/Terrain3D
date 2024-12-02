shader_type spatial;

render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

uniform int noise_octaves : hint_range(0, 12, 1) = 8;
uniform float mesh_size = 32.0; // set as tile size + 1
uniform float lod_blend : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform bool smooth_normals = true;
uniform bool color_mode = false;
uniform vec3 camera_pos;

group_uniforms test_textures;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float rock_scale : hint_range(0.01, 2.0, 0.01);
uniform float rock_height : hint_range(0.01, 1.0, 0.01);
uniform float rock_offset : hint_range(0.01, 1.0, 0.01);
uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grass_scale : hint_range(0.01, 2.0, 0.01);
uniform float grass_height : hint_range(0.01, 1.0, 0.01);
uniform float grass_offset : hint_range(0.01, 1.0, 0.01);
group_uniforms;

varying vec3 v_vertex;
varying vec3 v_normal;

float hashv2(vec2 v) {
	return fract(1e4 * sin(17.0 * v.x + v.y * 0.1) * (0.1 + abs(sin(v.y * 13.0 + v.x))));
}

vec3 noise(vec2 x) {
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

float layered_noise(vec2 p, int octaves) {
	p *= 0.005;
    float a = 0.0;
    float b = 1.0;
    vec2  d = vec2(0.0);

    for( int i=0; i < octaves; i++ ) {
        vec3 n = noise(p);
        d += n.yz;
        a += b * n.x / (1.0 + dot(d,d));
        b *= 0.5;
        p = mat2( vec2(0.8, -0.6), vec2(0.6, 0.8) ) * p * 2.0;
    }

	return (a * 100.0 - 50.0);
}

void vertex() {
	vec3 camera_pos_local = camera_pos - MODEL_MATRIX[3].xyz;
	float dist = length((VERTEX.xz) - camera_pos_local.xz - 1.0);
	float vertex_lerp = clamp(dist - mesh_size, 0.0, 1.0);
	VERTEX.xz -= fract(VERTEX.xz) * vertex_lerp;

	// World space position
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Read height
	float h = layered_noise(v_vertex.xz, noise_octaves);
	float u = layered_noise(v_vertex.xz + vec2(1., 0.), noise_octaves);
	float v = layered_noise(v_vertex.xz + vec2(0., 1.), noise_octaves);
	v_normal = normalize(vec3(h - u, 1.0, h - v));

	float cliff_grass = mix(clamp((v_normal.y - 0.66) * 8.0, 0., 1.), 0.0, clamp(h * 0.1 - 6.0, 0.0, 1.0));

	// Detail height
	vec4 rock = texture(rock_a, v_vertex.xz * rock_scale);
	vec4 grass = texture(grass_a, v_vertex.xz * grass_scale);
	float d = mix((rock.a - rock_offset) * rock_height, (grass.a - grass_offset) * grass_height, cliff_grass);
	float detail_blend =  1.0 - clamp(dist - mesh_size + 4.0, 0.0, 4.0) * 0.25;
	v_vertex.y = d * detail_blend + h;

	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;

	COLOR.rgb = mix(vec3(1., 0.33, 0.33), vec3(0.33, 0.33, 0.66), detail_blend);

}

void fragment() {
	vec3 w_normal = normalize(v_normal);

	float h = layered_noise(v_vertex.xz, noise_octaves);
	float u = layered_noise(v_vertex.xz + vec2(1., 0.), noise_octaves);
	float v = layered_noise(v_vertex.xz + vec2(0., 1.), noise_octaves);
	w_normal = normalize(vec3(h - u, 1.0, h - v));

	// screenspace normals
	if (!smooth_normals) {
		vec3 s_normal = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
		w_normal = mat3(INV_VIEW_MATRIX) * s_normal;
	}
	vec3 w_tangent = normalize(cross(w_normal, vec3(0, 0, 1)));
	vec3 w_binormal = normalize(cross(w_normal, w_tangent));
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;

	vec4 rock_rgb = texture(rock_a, v_vertex.xz * rock_scale);
	vec4 rock_nrm = texture(rock_n, v_vertex.xz * rock_scale);

	vec4 grass_rgb = texture(grass_a, v_vertex.xz * grass_scale);
	vec4 grass_nrm = texture(grass_n, v_vertex.xz * grass_scale);

	float cliff_grass = mix(clamp((w_normal.y - 0.66) * 8.0, 0., 1.), 0.0, clamp(v_vertex.y * 0.1 - 6.0, 0.0, 1.0));

	vec4 alb = mix(
		rock_rgb, // cliff
		grass_rgb, // grass
		cliff_grass); // cliff <-> grass
	vec4 nrm = mix(
		rock_nrm, // cliff
		grass_nrm, // grass
		cliff_grass); // cliff <-> grass

	ALBEDO = alb.rgb;
	NORMAL_MAP = nrm.rgb;

	if (color_mode) {
		ALBEDO = COLOR.rgb;
	}
	ROUGHNESS = nrm.a;
	SPECULAR = 1.0 - nrm.a;
	AO = alb.a;
}
