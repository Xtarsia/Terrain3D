shader_type spatial;

render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

uniform int noise_octaves : hint_range(0, 10, 1) = 2;
uniform float mesh_size : hint_range(4.0, 64.0, 2.0) = 48.0;
uniform float lod_blend : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec3 test : source_color = vec3(1.0);
varying vec3 v_vertex;

float hashv2(vec2 v) {
	return fract(1e4 * sin(fma(17.0, v.x, v.y * 0.1)) * (0.1 + abs(sin(fma(v.y, 13.0, v.x)))));
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
	p *= 0.002;
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
	return a * 200.0 - 100.0;
}

void vertex() {
	// Scale derived from x axis basis vector - x & z axis scales must be the same.
	float scale = length(MODEL_MATRIX[0].xyz);
	float xz_view_dist = length((MODEL_MATRIX * vec4(VERTEX, 0.0)).xz - (INV_VIEW_MATRIX[3].xz - MODEL_MATRIX[3].xz));
	float vertex_lerp = clamp((xz_view_dist - (mesh_size * scale * 1.5)) / mix(1.0, mesh_size * scale * 0.5, lod_blend), 0.0, 1.0) * 2.0;
	VERTEX.xz -= fract(VERTEX.xz / 2.) * vertex_lerp * round((fract((VERTEX.xz) / (4.)) - (0.5) ) * (4.0));
	
	// World space position
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Noise for demo data and some dressing up
	float h = layered_noise(v_vertex.xz, noise_octaves);
	v_vertex.y = 0.;
	
	
	
	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;
	
	vec3[3] col = {vec3(1,0,0), vec3(0,1,0), vec3(0,0,1)};
	int index = int(mod(log2(scale), 3.));
	COLOR.rgb = col[index];
	
}

void fragment() {
	vec3 w_vertex = v_vertex;
	
	// noise normals
	float h = layered_noise(v_vertex.xz, noise_octaves);
	float u = layered_noise(v_vertex.xz + vec2(1., 0.), noise_octaves);
	float v = layered_noise(v_vertex.xz + vec2(0., 1.), noise_octaves);
	vec3 w_normal = normalize(vec3(h - u, 1.0, h - v));
	
	// screenspace normals
	//vec3 s_normal = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	//w_normal = mat3(INV_VIEW_MATRIX) * s_normal;
	//w_normal = vec3(0,1,0);
	vec3 w_tangent = cross(w_normal, vec3(0, 0, 1));
	vec3 w_binormal = cross(w_normal, w_tangent);
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;
	
	ALBEDO =
		mix(vec3(0.415,0.548,0.616) * 0.5,
			mix(vec3(0.13,0.105,0.105), // cliff
				mix(vec3(0.12,0.18,0.12), // grass
				vec3(2.0), // snow
				clamp(w_vertex.y * 0.05 + 1.0 ,0.,1.)), // grass <-> snow
			clamp((w_normal.y - 0.66) * 2.0, 0., 1.)), // cliff <-> grass & snow
			1.0);//clamp(w_vertex.y+80.0,0.,1.)); // water <-> terrain
	//ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;

}
