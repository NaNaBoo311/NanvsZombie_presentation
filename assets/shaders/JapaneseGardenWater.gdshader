shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back;

// Japanese Garden Mountain Stream Shader
// Deep, tranquil water with low-poly vertex rippling, gentle surface flow, and glassy specular glints.
uniform vec4 water_color : source_color = vec4(0.04, 0.11, 0.15, 0.92);
uniform vec4 shallow_color : source_color = vec4(0.08, 0.18, 0.22, 0.88);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.98, 0.92);
uniform float wave_speed : hint_range(0.0, 5.0) = 0.85;
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.016;

void vertex() {
	// Low-poly faceted vertex bobbing
	float wave = sin(VERTEX.x * 2.8 + TIME * wave_speed * 1.4) * cos(VERTEX.z * 2.2 + TIME * wave_speed) * wave_amplitude;
	VERTEX.y += wave;
}

void fragment() {
	float flow_time = TIME * wave_speed * 0.35;
	
	// Micro-ripples across stream surface
	float ripple1 = sin(UV.x * 14.0 + flow_time * 2.2);
	float ripple2 = cos(UV.y * 20.0 - flow_time * 1.6 + ripple1 * 0.5);
	float ripple = (ripple1 + ripple2) * 0.5;

	// Soft shoreline / edge foam accent
	float edge_dist = abs(UV.y - 0.5) * 2.0; // 0 at stream center, 1 at banks
	float bank_foam = smoothstep(0.80, 0.98, edge_dist + ripple * 0.12);

	// Deep mountain stream color gradient
	vec3 water_rgb = mix(water_color.rgb, shallow_color.rgb, smoothstep(0.25, 0.85, edge_dist));
	vec3 final_color = mix(water_rgb + ripple * 0.018, foam_color.rgb, bank_foam * 0.5);

	ALBEDO = final_color;
	ALPHA = mix(water_color.a, 0.98, bank_foam);
	ROUGHNESS = 0.06; // Glassy mirror surface reflecting moon/sun and lanterns
	SPECULAR = 0.90;
}
