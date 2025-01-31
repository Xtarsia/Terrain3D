shader_type spatial;

render_mode cull_disabled, skip_vertex_transform;

void vertex() {
    // Step 1: Convert clip-space vertex to NDC
    vec4 ndc_position = vec4(VERTEX.xy, -1.0, 1.0); // `-1` for z to define ray direction in view space
    
    // Step 2: Transform to world space direction
    vec4 world_direction = INV_VIEW_MATRIX * (INV_PROJECTION_MATRIX * ndc_position);
    world_direction /= world_direction.w; // Normalize homogeneous coordinate

    // Compute the direction from the camera to the point on the clip-space quad
    vec3 ray_direction = normalize(world_direction.xyz - INV_VIEW_MATRIX[3].xyz);

    // Step 3: Ray-plane intersection for XZ plane (y = 0)
    float t = -INV_VIEW_MATRIX[3].y / ray_direction.y; // Intersection distance along the ray
    vec3 intersection_position = INV_VIEW_MATRIX[3].xyz + t * ray_direction; // Position on XZ plane

    // Step 4: Sample heightmap to adjust the Y position based on heightmap
    vec2 uv = vec2(intersection_position.x, intersection_position.z) * 0.5 + 0.5; // Map to [0,1] UV range
    float height = 0.;//texture(heightmap, uv).r * height_scale;
    intersection_position.y = height;

    // Step 5: Set the new VERTEX position in world space
    VERTEX = intersection_position;
	VERTEX = (VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = vec3(1.0);
	// Called for every pixel the material is visible on.
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
