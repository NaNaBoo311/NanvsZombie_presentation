shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// ============================================================================
// TitleSpirits.gdshader
// Wandering spirits (Cô Hồn) rising out of the title's cloud sea toward the pearls'
// light: one MultiMesh of camera-facing quads. Each draws one of three silhouettes
// from its phase: a hooded wanderer, a conical-hat vendor's ghost, or a small flame
// wisp. All trail a wavering tail that fades out, and read cool against the warm
// world (cool means spirit). Cozy, not horror (docs/LORE.md). All motion is here;
// the CPU places instances once.
// INSTANCE_CUSTOM: x phase, y speed scale, z rise height (m), w size (m).
// ============================================================================

uniform vec4 body_color : source_color = vec4(0.80, 0.90, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.42, 0.56, 0.95, 1.0);
uniform float cycle = 11.0;
uniform float sway = 1.4;

varying float v_fade;
varying float v_phase;

void vertex() {
	float t = fract(TIME / cycle * INSTANCE_CUSTOM.y + INSTANCE_CUSTOM.x);
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	base.y += t * INSTANCE_CUSTOM.z;
	base.x += sin(t * 9.0 + INSTANCE_CUSTOM.x * 40.0) * sway;
	vec4 view = VIEW_MATRIX * vec4(base, 1.0);
	view.xy += VERTEX.xy * INSTANCE_CUSTOM.w;
	POSITION = PROJECTION_MATRIX * view;
	v_fade = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.72, 1.0, t));
	v_phase = INSTANCE_CUSTOM.x;
}

void fragment() {
	vec2 p = vec2(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0);
	int kind = int(fract(v_phase * 7.13) * 3.0);
	float below = clamp((0.35 - p.y) / 1.25, 0.0, 1.0);
	// The tail sways more the further it trails.
	p.x += sin(p.y * 5.0 + TIME * 3.0 + v_phase * 50.0) * 0.16 * below;
	float head_r = kind == 2 ? 0.30 : 0.34;
	float head_y = kind == 2 ? -0.05 : 0.28;
	float head = length(p - vec2(0.0, head_y)) - head_r;
	float half_w = head_r * (1.0 - below * 0.96);
	float tail = max(abs(p.x) - half_w, max(p.y - head_y, -0.92 - p.y));
	float d = min(head, tail);
	if (kind == 1) {
		// Non la: a wide flat cone over the head, the silhouette that reads at any size.
		float hat = max(abs(p.x) * 0.5 + (p.y - 0.72), -(p.y - 0.42));
		d = min(d, hat);
	} else if (kind == 0) {
		// Hood: a taller crown and shoulders that flare a little.
		d = min(d, length((p - vec2(0.0, 0.42)) * vec2(1.0, 0.8)) - 0.34);
	} else {
		// Flame wisp: a tip that licks upward.
		d = min(d, max(abs(p.x) * 1.5 + (p.y - 0.40) * 0.9, -p.y));
	}
	float shape = 1.0 - smoothstep(-0.03, 0.05, d);
	// The halo must reach zero before the quad's edge, or the quad shows as a box.
	float glow = exp(-max(d, 0.0) * 8.0) * 0.42 * (1.0 - smoothstep(0.6, 0.95, length(p * vec2(1.0, 0.85))));
	float eyes = 0.0;
	if (kind != 2) {
		eyes = 1.0 - smoothstep(0.05, 0.09, min(length(p - vec2(-0.13, 0.26)), length(p - vec2(0.13, 0.26))));
	}
	vec3 col = mix(glow_color.rgb, body_color.rgb, shape * (1.0 - below * 0.75));
	col = mix(col, vec3(0.08, 0.1, 0.2), eyes * shape);
	float tail_fade = 1.0 - smoothstep(0.35, 1.0, below);
	ALBEDO = col * 1.1;
	ALPHA = clamp((shape * 0.95 * tail_fade + glow * (1.0 - shape)) * v_fade, 0.0, 1.0);
}
