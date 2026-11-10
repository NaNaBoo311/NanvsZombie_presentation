shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_disabled;

// Lantern Glow — Hoi An's silk lanterns, flower lanterns and lit shop windows.
// The generators bake every lantern of every colour onto one material named
// "LanternGlow" (tools/asset_generator/generators/architecture/lantern_kit.mjs), with
// the colour in the vertex COLOR (linear, like every baked colour): silk, the dark
// wooden hubs and the red tassel are rows of the same lantern. Albedo and emission both
// come from it, so one material, and one draw call per mesh, lights lanterns of any
// colour. The kit's UV says where the bamboo ribs are: UV.x is a whole number on every
// rib, UV.y runs up the lantern; ribs are drawn as dark seams and the silk glows
// brightest at its waist, as real silk does with the candle behind it. Plain glow
// (windows, flames) carries UV (0.5, 0.5): no seams, full glow.
// day_blend dims the glow by day; the map pushes it on EventBus.day_blend_changed
// (plain uniform on one shared ShaderMaterial, TRAPS.md#global-uniform). Zero textures,
// zero per-frame script.

uniform float day_blend : hint_range(0.0, 1.0) = 0.0;
// Emission strength at night / by day. At night it is above the preset's glow
// threshold, so the lanterns bloom.
uniform float glow_night = 2.4;
uniform float glow_day = 0.35;
// Brighter core where the silk faces the camera, like the candle behind it.
uniform float core_boost = 0.5;
// Rib seam width (share of a panel) and how dark a seam gets.
uniform float rib_width = 0.09;
uniform float rib_dark = 0.25;

void fragment() {
	vec3 silk = COLOR.rgb;
	float across = fract(UV.x);
	float rib = smoothstep(0.0, rib_width, across) * smoothstep(0.0, rib_width, 1.0 - across);
	float waist = mix(0.55, 1.15, sin(3.14159265 * clamp(UV.y, 0.0, 1.0)));
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float strength = mix(glow_night, glow_day, day_blend) * (1.0 + core_boost * facing * facing) * waist;
	float seam = mix(rib_dark, 1.0, rib);
	ALBEDO = silk * mix(0.35, 0.8, day_blend) * seam;
	EMISSION = silk * strength * seam;
	ROUGHNESS = 0.85;
}
