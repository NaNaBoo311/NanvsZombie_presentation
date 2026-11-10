shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float grid_opacity : hint_range(0.0, 1.0) = 1.0;

varying vec4 v_instance_color;

void vertex() {
	v_instance_color = COLOR;
}

void fragment() {
	// Instance color supplied by MultiMeshInstance3D
	vec4 tile_col = v_instance_color;
	
	// UV is 0.0..1.0 across the 1.88m x 1.88m plane
	vec2 uv_centered = abs(UV - vec2(0.5)) * 2.0; // 0.0 at center, 1.0 at tile border
	float d = max(uv_centered.x, uv_centered.y);   // Chebyshev distance for square tile
	
	// Crisp glowing outer border (outer ~12% of the tile)
	float border = smoothstep(0.76, 0.88, d);
	
	// Subtle inner fill so the grass remains clearly visible through the cell
	float fill = 0.08;
	
	// Corner accent brackets
	float corner = smoothstep(0.70, 0.90, uv_centered.x * uv_centered.y) * 0.28;
	
	float alpha = (fill + border * 0.65 + corner) * tile_col.a * grid_opacity;
	
	ALBEDO = tile_col.rgb;
	ALPHA = clamp(alpha, 0.0, 0.78);
}
