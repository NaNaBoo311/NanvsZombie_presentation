shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Fountain spray cones — cheap opaque animation for the merged FountainSprays mesh.
// UV.y runs 0 (base) -> 1 (tip) on the THREE ConeGeometry the island generator
// bakes; bands scroll toward the base (falling water) and the tip gets a lighter
// foam cap. Mild night emission keeps the plumes readable under lantern light.
// Never write ALPHA: stays opaque so yacht/depth sorting is untouched.

uniform vec3 spray_color : source_color = vec3(0.55, 0.85, 0.90);
uniform vec3 foam_color : source_color = vec3(0.90, 0.97, 0.98);
uniform float day_blend : hint_range(0.0, 1.0) = 0.0;
uniform float scroll_speed : hint_range(0.0, 3.0) = 1.2;
uniform float emission_night : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	// Falling bands: +TIME moves the pattern toward the base (UV.y decreasing).
	float bands = fract(UV.y * 3.0 + TIME * scroll_speed);
	float band = smoothstep(0.0, 0.25, bands) * (1.0 - smoothstep(0.25, 0.55, bands));
	// Foam tip near the apex.
	float tip = smoothstep(0.65, 1.0, UV.y);

	vec3 body = mix(spray_color, foam_color, band * 0.5 + tip * 0.7);
	// Dim at night like the river/pond foam so lanterns don't blow it out,
	// then add a small constant emission so the plume never goes black.
	vec3 tinted = body * mix(0.55, 1.0, day_blend);
	EMISSION = body * emission_night * (1.0 - day_blend);

	ALBEDO = tinted;
	ROUGHNESS = 0.25;
	SPECULAR = 0.4;
	METALLIC = 0.0;
}
