// Copyright © 2025 Cory Petkovsek, Roope Palmroos, and Contributors.

R"(

//INSERT: DISPLACEMENT1
uniform float displacement_scale : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform vec3 _displacement_buffer_pos = vec3(0);
uniform highp sampler2D _displacement_buffer : repeat_enable, hint_default_black;

vec3 get_displacement(vec2 pos) {
	vec2 d_uv = (pos - (0.5 / _subdiv) - _displacement_buffer_pos.xz * _vertex_density) / (_mesh_size * 2.0) + 0.5;
	if (all(greaterThanEqual(d_uv, vec2(0.0))) && all(lessThanEqual(d_uv, vec2(1.0)))) {
		highp vec3 nrm_h = textureLod(_displacement_buffer, d_uv, 0.).rgb;
		float height = nrm_h.z - 0.5;
		nrm_h.xy = fma(nrm_h.xy, vec2(2.0), vec2(-1.0));
		nrm_h.z = sqrt(clamp(1.0 - dot(nrm_h.xy, nrm_h.xy), 0.0, 1.0));
		nrm_h = nrm_h.xzy * height * displacement_scale;
		// radial fadeout
		float fade = smoothstep(0.0, 0.33, 1.0 - length((pos - _camera_pos.xz * _vertex_density) / (_mesh_size * 2.) * 2.0));
		return nrm_h * fade;
	}
	return vec3(0.);
}

//INSERT: DISPLACEMENT2
		if (!(CAMERA_VISIBLE_LAYERS == _mouse_layer)) {
		displacement = mix(get_displacement(start_pos), get_displacement(end_pos), vertex_lerp);
		}

)"
