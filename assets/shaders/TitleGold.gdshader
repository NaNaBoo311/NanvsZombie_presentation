shader_type canvas_item;

// ============================================================================
// TitleGold.gdshader
// The wordmark's gilding: pale gold at the top of the letters, deep gold at the foot.
// Only the fill changes; the engine's outline pass is left alone.
// ============================================================================

uniform vec4 light : source_color = vec4(1.0, 0.95, 0.72, 1.0);
uniform vec4 deep : source_color = vec4(0.96, 0.66, 0.26, 1.0);
uniform float top_y = 14.0;
uniform float foot_y = 72.0;

varying float v_y;

void vertex() {
	v_y = VERTEX.y;
}

void fragment() {
	if (COLOR.r > 0.6) {
		COLOR.rgb = mix(light.rgb, deep.rgb, clamp((v_y - top_y) / (foot_y - top_y), 0.0, 1.0));
	}
}
