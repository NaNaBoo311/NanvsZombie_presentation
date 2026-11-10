shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled, shadows_disabled;

// ============================================================================
// TitleShots.gdshader
// The title vignette's seed shots: one MultiMesh of small seeds, each flying
// along its instance's local +X from a plant's muzzle toward the horde and
// looping. The seed is stretched into a streak; a shallow arc and a fade at
// both ends hide the loop. All motion is here; the CPU places lanes once.
// INSTANCE_CUSTOM: x phase, y lane length (m).
// ============================================================================

uniform vec4 tint : source_color = vec4(0.45, 1.0, 0.35, 1.0);
uniform vec4 head_tint : source_color = vec4(1.0, 1.0, 0.8, 1.0);
uniform float energy = 4.2;
uniform float speed = 13.0;
uniform float streak = 9.0;
/// The source seed mesh's half-length along X, for the head-to-tail gradient.
uniform float seed_half = 0.16;

varying float v_fade;
varying float v_along;

void vertex() {
	float len = max(INSTANCE_CUSTOM.y, 0.1);
	float t = fract(TIME * speed / len + INSTANCE_CUSTOM.x);
	v_along = clamp(VERTEX.x / seed_half * 0.5 + 0.5, 0.0, 1.0);
	VERTEX.x = VERTEX.x * streak + t * len;
	VERTEX.y += sin(t * PI) * len * 0.05;
	v_fade = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.86, 1.0, t));
}

void fragment() {
	// Bright head at the front (+X), a green trail fading out behind it.
	float head = smoothstep(0.7, 1.0, v_along);
	ALBEDO = mix(tint.rgb, head_tint.rgb, head) * energy;
	ALPHA = v_fade * v_along * v_along;
}
