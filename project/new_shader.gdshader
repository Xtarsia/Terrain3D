shader_type spatial;

render_mode blend_mix,depth_draw_always,cull_back,diffuse_burley,specular_schlick_ggx,skip_vertex_transform;

uniform int noise_octaves : hint_range(0, 10, 1) = 2;
uniform float mesh_size : hint_range(16.0, 64.0, 2.0) = 64.0;
uniform float lod_blend : hint_range(0.0, 1.0, 0.01) = 1.0;

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
	return a * 196.0 - 110.0;
}

void vertex() {
	// Translate vertex in xz plane in local space
	// Scale derived from x axis basis vector - x & z axis scales must be the same.
	float scale = length(MODEL_MATRIX[0].xyz);
	float xz_view_dist = length((MODEL_MATRIX * vec4(VERTEX, 0.0)).xz - (INV_VIEW_MATRIX[3].xz - MODEL_MATRIX[3].xz));
	// Lerp ODD Vertices, is scaled by LOD mesh scale, pingpongs from mid point to edge, back to mid point
	// requires LOD meshes to be scaled and spaced appropiately. offset by mesh_size to account for the inner circle.
	// all vertices are shared across LOD boundarys, removing the requirement for the seam mesh entirely.
	float vertex_lerp = clamp((xz_view_dist - 2.0 * scale * mesh_size + mesh_size) / (mesh_size * lod_blend) * 2.0, 0.0, 2.0);

	// Apply the Geomorphed position
	VERTEX.xz -= fract(VERTEX.xz / 2.) * vertex_lerp;

	// World space position
	v_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Noise for demo data and some dressing up
	float h = layered_noise(v_vertex.xz, noise_octaves);
	v_vertex.y = 0.;//h;
	// Far Clip edges
	float max_lod = 16.0;
	if (vertex_lerp > 0. && scale > max_lod) {
		v_vertex.x = 0. / 0.;
	}

	VERTEX = (VIEW_MATRIX * vec4(v_vertex, 1.0)).xyz;

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
	vec3 w_tangent = cross(w_normal, vec3(0, 0, 1));
	vec3 w_binormal = cross(w_normal, w_tangent);
	NORMAL = mat3(VIEW_MATRIX) * w_normal;
	TANGENT = mat3(VIEW_MATRIX) * w_tangent;
	BINORMAL = mat3(VIEW_MATRIX) * w_binormal;

	ALBEDO =
		mix(vec3(0.13,0.105,0.105), // cliff
			mix(vec3(0.12,0.18,0.12), // grass
			vec3(2.0), // snow
			clamp(w_vertex.y * 0.05 + 1.0 ,0.,1.)), // grass <-> snow
		clamp((w_normal.y - 0.66) * 2.0, 0., 1.)); // cliff <-> grass & snow
	ROUGHNESS = 0.8;
	SPECULAR = 0.2;

}
