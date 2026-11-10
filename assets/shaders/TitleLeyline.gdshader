shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// ============================================================================
// TitleLeyline.gdshader
// The Long Mạch (dragon leyline) on the title: a glowing jade ribbon that always
// faces the camera. TitleEffects.gd builds the centreline strip: VERTEX is on the
// centreline, NORMAL carries the curve tangent, UV.x is metres along the curve
// and UV.y is the side (-1 / +1). Light pulses flow along it toward Saigon.
// It leaves the eclipse, wraps the front of each island's cliff, and ends in the
// Pearl, so it reads as one unbroken line. Depth-tested, so units stand in front of it.
// ============================================================================

uniform vec4 core : source_color = vec4(0.62, 1.0, 0.82, 1.0);
uniform vec4 edge : source_color = vec4(0.12, 0.62, 0.52, 1.0);
uniform vec4 pulse_tint : source_color = vec4(1.0, 0.88, 0.55, 1.0);
uniform float width = 2.2;
/// The ribbon thins over its last metres, so it reads as a cord where it crosses the lawn.
uniform float taper_m = 90.0;
uniform float energy = 1.9;
uniform float length_m = 600.0;
uniform float pulse_spacing = 26.0;
uniform float flow_speed = 9.0;

varying float v_side;
varying float v_s;

void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 to_cam = normalize(INV_VIEW_MATRIX[3].xyz - wpos);
	vec3 side = normalize(cross(tangent, to_cam));
	float taper = mix(0.22, 1.0, smoothstep(0.0, taper_m, length_m - UV.x));
	wpos += side * UV.y * width * taper;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
	v_side = UV.y;
	v_s = UV.x;
}

void fragment() {
	float d = abs(v_side);
	float core_f = exp(-d * d * 10.0);
	float halo = exp(-d * 2.6) * 0.5;
	float phase = fract((v_s - TIME * flow_speed) / pulse_spacing);
	float pulse = smoothstep(0.80, 0.97, phase) * (1.0 - smoothstep(0.97, 1.0, phase));
	float ends = smoothstep(0.0, 30.0, v_s) * (1.0 - smoothstep(length_m - 6.0, length_m, v_s));
	vec3 col = mix(edge.rgb, core.rgb, core_f) * (core_f + halo) + pulse_tint.rgb * pulse * core_f * 1.6;
	ALBEDO = col * energy;
	ALPHA = clamp((core_f + halo) * ends, 0.0, 1.0);
}
