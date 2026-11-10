shader_type canvas_item;

// ============================================================================
// ResultGrade.gdshader
// The result screens' colour grade over the live scene: `drain` takes the colour out
// (a lost Pearl), and `edge` closes a tinted vignette in from the corners: warm dawn
// on a win, danger red on a loss. Uses only the screen buffer, which both renderers
// share (TRAPS.md#mobile-renderer-screen-buffers). Exists only while a result shows.
// ============================================================================

uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float drain : hint_range(0.0, 1.0) = 0.0;
uniform float edge : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(1.0, 0.7, 0.3, 1.0);

void fragment() {
	vec3 scene = max(texture(screen, SCREEN_UV).rgb, vec3(0.0));
	float luma = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(scene, vec3(luma) * vec3(0.82, 0.86, 1.0), drain);
	vec2 c = UV * 2.0 - 1.0;
	float v = smoothstep(0.45, 1.35, length(c * vec2(1.0, 0.9)));
	COLOR = vec4(mix(col, edge_color.rgb, v * edge), 1.0);
}
