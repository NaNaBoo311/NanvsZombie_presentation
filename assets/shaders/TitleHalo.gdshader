shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// ============================================================================
// TitleHalo.gdshader
// The Pearl's warm pool of light on the lawn, painted instead of lit: the title
// allows one shadow light and no omni or spot lights (TitleTest guards this).
// A flat disc fading from the centre, one draw and no light cost.
// ============================================================================

uniform vec4 tint : source_color = vec4(1.0, 0.68, 0.32, 1.0);
uniform float energy = 0.42;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float fade = 1.0 - smoothstep(0.0, 1.0, r);
	ALBEDO = tint.rgb * energy;
	ALPHA = fade * fade;
}
