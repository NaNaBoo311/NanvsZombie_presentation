shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// ============================================================================
// TitleMist.gdshader
// The title's cloud sea, and its thinner foreground band, cut like painted paper to
// match the hard-edged islands. Value noise sets the large drift, a cellular layer
// rounds it into billows, and the height is stepped into hard bands: valley, body,
// crest and a lit top. Crests far from the camera (world -Z) warm toward the
// eclipse. Band edges are antialiased with fwidth, so distance never shimmers. A
// radial UV fade hides the plane's edges. Reads no depth or screen texture, so it
// renders the same on the Mobile renderer (TRAPS.md#mobile-renderer-screen-buffers).
// ============================================================================

uniform vec4 valley : source_color = vec4(0.15, 0.10, 0.25, 1.0);
uniform vec4 body : source_color = vec4(0.22, 0.15, 0.33, 1.0);
uniform vec4 crest : source_color = vec4(0.32, 0.21, 0.40, 1.0);
uniform vec4 lit_top : source_color = vec4(0.50, 0.30, 0.44, 1.0);
uniform vec4 far_glow : source_color = vec4(0.98, 0.58, 0.40, 1.0);
uniform float far_z = -320.0;
uniform float near_z = 80.0;
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float scale = 0.022;
uniform float drift = 0.8;

varying vec3 v_world;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Distance to the nearest of a jittered grid of points: round, puffy cells.
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float best = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 19.0));
			best = min(best, length(g + o - f));
		}
	}
	return best;
}

float step_band(float h, float edge_at, float aa) {
	return smoothstep(edge_at - aa, edge_at + aa, h);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world.xz * scale + vec2(TIME * drift * scale, TIME * drift * scale * 0.3);
	float large = vnoise(p) * 0.65 + vnoise(p * 2.1 + 17.0) * 0.35;
	float billow = 1.0 - cells(p * 5.5 + large * 2.0);
	float h = large * 0.86 + billow * 0.16;
	float aa = max(fwidth(h) * 0.9, 0.002);
	float low = step_band(h, 0.44, aa);
	float mid = step_band(h, 0.55, aa);
	float top = step_band(h, 0.67, aa);
	float far = 1.0 - clamp((v_world.z - far_z) / (near_z - far_z), 0.0, 1.0);
	vec3 col = mix(valley.rgb, body.rgb, low);
	col = mix(col, crest.rgb, mid);
	col = mix(col, lit_top.rgb, top);
	col = mix(col, far_glow.rgb, far * far * far * mid * 0.8);
	vec2 c = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.55, 1.0, length(c));
	ALBEDO = col;
	ALPHA = clamp((base_alpha + (1.0 - base_alpha) * low) * edge * opacity, 0.0, 1.0);
}
