shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

// Atlas Focus Beam — the gold light pillar over the focused province of the
// presentation's Vietnam atlas (src/presentation/ConceptAtlas.gd). A tapered
// open cylinder; the core is brightest where the surface faces the camera and
// the shaft fades out toward its top. No textures and no TIME, so it costs
// nothing while the picked world stays the same.

uniform vec4 beam_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float beam_strength : hint_range(0.0, 2.0) = 1.0;

void fragment() {
	float core = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	core *= core;
	float fade = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y));
	ALBEDO = beam_color.rgb;
	ALPHA = beam_color.a * beam_strength * core * fade;
}
