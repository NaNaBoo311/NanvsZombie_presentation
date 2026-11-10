shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

// Lantern Drift — boats and lanterns that move, driven entirely on the GPU
// (src/environment/LanternDrift.gd builds each MultiMesh once): the vertex shader places
// every instance, so the motion costs no CPU at all (AGENTS.md invariant 7). The meshes
// (lantern_drift.mjs) carry UV = (shape id, glow): each mesh holds several shapes and an
// instance collapses every vertex that is not its own shape; glow vertices get the
// lantern look (albedo + emission from their colour, like LanternGlow.gdshader).
//
// INSTANCE_CUSTOM = (phase 0..1, a, motion * 10 + 5 + speed, shape * 10 + colour + bob):
//   w: shape id (0 boat, 10-13 river lanterns, 20-23 sky lanterns), palette index
//      0..9 (grey glow vertices take palette[index] times their grey), bob phase (fraction).
//   motion 0 boat, 1 river lantern let go below the bridge (release_span), 3 river
//     lantern drifting the whole river (river_span): x runs along the span at |speed| m/s
//     (sign = direction, + is downstream to the east) and wraps, shrinking in and out
//     over `fade` metres at each end; a = the lane's z. The instance transform is identity.
//   motion 2 sky lantern: the instance transform holds its release point; it climbs
//     `sky_rise` metres in `sky_period` seconds while the wind carries it, then fades and
//     starts again; a = its size.

uniform float day_blend : hint_range(0.0, 1.0) = 0.0;
uniform float glow_night = 2.4;
uniform float glow_day = 0.35;
uniform vec2 river_span = vec2(-150.0, 140.0);
uniform vec2 release_span = vec2(-42.0, 53.0);
uniform float fade = 12.0;
uniform float water_y = -0.55;
uniform float sky_rise = 78.0;
uniform float sky_period = 150.0;
uniform vec2 sky_wind = vec2(0.22, 0.1);
uniform vec3 palette[12];

varying vec3 v_tint;
varying float v_glow;
varying float v_bright;

void vertex() {
	float motion = floor(INSTANCE_CUSTOM.z / 10.0);
	float shape = floor(INSTANCE_CUSTOM.w / 10.0);
	float colour = floor(mod(INSTANCE_CUSTOM.w, 10.0));
	float ph = fract(INSTANCE_CUSTOM.w) * 6.2831853;
	v_glow = UV.y;
	v_bright = 1.0;
	v_tint = COLOR.rgb;
	// Grey glow (r = g = b) is paper or silk in the instance's palette colour, as bright
	// as the grey: pure white at a lantern's lit heart, darker toward its petal tips.
	if (UV.y > 0.5 && abs(COLOR.r - COLOR.g) < 0.004 && abs(COLOR.g - COLOR.b) < 0.004) {
		v_tint = palette[int(clamp(colour, 0.0, 11.0))] * COLOR.r;
	}
	if (abs(UV.x - shape) > 0.5) {
		VERTEX = vec3(0.0);
	} else if (motion < 1.5 || motion > 2.5) {
		// On the river.
		float speed = INSTANCE_CUSTOM.z - motion * 10.0 - 5.0;
		vec2 span = (motion > 0.5 && motion < 1.5) ? release_span : river_span;
		float len = span.y - span.x;
		float travel = fract(INSTANCE_CUSTOM.x + TIME * abs(speed) / len) * len;
		float dir = speed >= 0.0 ? 1.0 : -1.0;
		float x = dir > 0.0 ? span.x + travel : span.y - travel;
		float grow = smoothstep(0.0, fade, travel) * smoothstep(0.0, fade, len - travel);
		// Turn the model's bow (+Z) onto the direction of travel (+-X), then rock it.
		vec3 v = VERTEX * grow;
		v = vec3(dir * v.z, v.y, -dir * v.x);
		v.y += v.z * sin(TIME * 1.1 + ph) * 0.04;
		VERTEX = v + vec3(x, water_y + sin(TIME * 1.4 + ph) * 0.04, INSTANCE_CUSTOM.y);
		NORMAL = vec3(dir * NORMAL.z, NORMAL.y, -dir * NORMAL.x);
	} else {
		// In the sky, from the release point in the instance transform.
		float t = fract(INSTANCE_CUSTOM.x + TIME / sky_period);
		float elapsed = t * sky_period;
		float grow = smoothstep(0.0, 0.03, t) * (1.0 - smoothstep(0.82, 1.0, t)) * INSTANCE_CUSTOM.y;
		vec3 sway = vec3(sin(TIME * 0.5 + ph * 7.0), 0.0, cos(TIME * 0.4 + ph * 5.0)) * 0.9 * t;
		VERTEX = VERTEX * grow + vec3(sky_wind.x * elapsed, t * sky_rise, sky_wind.y * elapsed) + sway;
		// The flame burns down as it climbs, and flickers.
		v_bright = (1.0 - 0.45 * t) * (0.9 + 0.1 * sin(TIME * 9.0 + ph * 3.0));
	}
}

void fragment() {
	if (v_glow > 0.5) {
		ALBEDO = v_tint * mix(0.35, 0.8, day_blend);
		EMISSION = v_tint * mix(glow_night, glow_day, day_blend) * v_bright;
	} else {
		ALBEDO = v_tint;
	}
	ROUGHNESS = 0.85;
}
