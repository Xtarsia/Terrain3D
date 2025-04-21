// Copyright © 2025 Cory Petkovsek, Roope Palmroos, and Contributors.

R"(

//INSERT: DUAL_SCALING_UNIFORMS
uniform int dual_scale_texture : hint_range(0,31) = 0;
uniform float dual_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float tri_scale_reduction : hint_range(0.001,1) = 0.3;
uniform float dual_scale_far : hint_range(0,1000) = 170.0;
uniform float dual_scale_near : hint_range(0,1000) = 100.0;

//INSERT: DUAL_SCALING
		// dual scaling
		float far_factor = clamp(smoothstep(dual_scale_near, dual_scale_far, length(v_vertex - _camera_pos)), 0.0, 1.0);
		vec4 far_alb = vec4(0.);
		vec4 far_nrm = vec4(0.);
		if (far_factor > 0. && (data.texture_id[0] == dual_scale_texture || data.texture_id[1] == dual_scale_texture)) {
			float far_scale = _texture_uv_scale_array[dual_scale_texture] * dual_scale_reduction;
			far_scale *= index.z < 0 ? tri_scale_reduction : 1.;
			float far_angle = i_angle + p_angle;
			vec2 far_uv = detiling(i_uv * far_scale, i_pos * far_scale, dual_scale_texture, far_angle);
			mat2 far_align = rotate_plane(-far_angle);
			mat2 far_align_dd = rotate_plane(-(far_angle - p_angle));
			vec4 far_dd = i_dd * far_scale;
			far_dd.xy *= far_align_dd;
			far_dd.zw *= far_align_dd;
			far_alb = textureGrad(_texture_array_albedo, vec3(far_uv, float(dual_scale_texture)), far_dd.xy, far_dd.zw);
			far_nrm = textureGrad(_texture_array_normal, vec3(far_uv, float(dual_scale_texture)), far_dd.xy, far_dd.zw);
			far_alb.rgb *= _texture_color_array[dual_scale_texture].rgb;
			far_nrm.a = clamp(far_nrm.a + _texture_roughness_mod_array[dual_scale_texture], 0., 1.);
			// Unpack normal map rotation and blending.
			far_nrm.xyz = fma(far_nrm.xzy, vec3(2.0), vec3(-1.0));
			far_nrm.xz *= far_align;
		}

//INSERT: DUAL_SCALING_MIX
			// If dual scaling, apply to overlay texture
			if (id == dual_scale_texture && far_factor > 0.) {
				alb = mix(alb, far_alb, far_factor);
				nrm = mix(nrm, far_nrm, far_factor);
			}

)"