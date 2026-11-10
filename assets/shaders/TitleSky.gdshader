shader_type sky;

// ============================================================================
// TitleSky.gdshader
// The title's sky during the Millennial Eclipse (docs/LORE.md): an indigo zenith,
// a violet band, and the rose-amber twilight an eclipse throws around the whole
// horizon, banked low behind the islands. The black sun sits upper right with a
// gold corona, soft rays and a diamond-ring bead; faint stars only near the top.
// Purely procedural, no texture, no TIME (so the radiance pass never re-renders).
//
// The layout is screen-relative: TitleMenu.gd passes the camera basis and the
// half-FOV tangents, so sx/sy below are frame coordinates in [-1, 1] at any
// aspect. The eclipse is placed by those coordinates too.
// ============================================================================

uniform vec3 cam_forward = vec3(0.0, 0.0, -1.0);
uniform vec3 cam_right = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_up = vec3(0.0, 1.0, 0.0);
uniform float tan_h = 0.48;
uniform float tan_v = 0.27;

uniform vec4 zenith : source_color = vec4(0.07, 0.06, 0.19, 1.0);
uniform vec4 violet : source_color = vec4(0.25, 0.17, 0.40, 1.0);
uniform vec4 rose : source_color = vec4(0.72, 0.38, 0.40, 1.0);
uniform vec4 amber : source_color = vec4(0.96, 0.64, 0.38, 1.0);
uniform vec4 low_haze : source_color = vec4(0.33, 0.24, 0.42, 1.0);
/// Frame height of the twilight band's brightest line (-1 bottom, 1 top).
uniform float band_y = -0.12;

uniform vec2 eclipse_xy = vec2(0.40, 0.56);
uniform float eclipse_radius = 0.042;
uniform vec4 corona : source_color = vec4(1.0, 0.82, 0.52, 1.0);
uniform float corona_energy = 1.7;
uniform float star_density : hint_range(0.0, 0.05) = 0.008;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float fwd = max(dot(dir, cam_forward), 0.05);
	float sx = dot(dir, cam_right) / fwd / tan_h;
	float sy = dot(dir, cam_up) / fwd / tan_v;

	// Vertical twilight: zenith -> violet -> rose -> amber band -> violet haze below.
	float h = sy - band_y;
	vec3 col = low_haze.rgb;
	col = mix(col, amber.rgb, smoothstep(-0.55, -0.02, h));
	col = mix(col, rose.rgb, smoothstep(0.0, 0.28, h));
	col = mix(col, violet.rgb, smoothstep(0.22, 0.75, h));
	col = mix(col, zenith.rgb, smoothstep(0.7, 1.5, h));
	// The band is warmest under the eclipse and cools away from it sideways.
	col *= 1.0 - 0.18 * clamp(abs(sx - eclipse_xy.x) - 0.3, 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.9, abs(h)));

	// Eclipse, in frame units corrected to a round disc.
	vec2 e = vec2((sx - eclipse_xy.x) * tan_h, (sy - eclipse_xy.y) * tan_v);
	float r = length(e);
	float ang = atan(e.y, e.x);
	float rim = max(r - eclipse_radius, 0.0) / eclipse_radius;
	float rays = 0.62 + 0.22 * sin(ang * 11.0 + 0.7) + 0.16 * sin(ang * 23.0 + 2.1);
	float glow = exp(-rim * 3.4) * rays + exp(-rim * 0.6) * 0.18;
	vec2 bead_dir = vec2(cos(-0.75), sin(-0.75));
	float bead = exp(-length(e / eclipse_radius - bead_dir * 1.02) * 9.0);
	col += corona.rgb * (glow * corona_energy + bead * 6.0);
	// The disc is darker than black-on-glow would read: bloom spills the corona
	// over it, so it is pushed negative-safe to zero and kept tight to the rim.
	float disc = 1.0 - smoothstep(eclipse_radius * 0.985, eclipse_radius, r);
	col = mix(col, vec3(0.0), disc);

	// Faint stars, only in the top of the frame and away from the corona.
	vec3 cell = floor(dir * 200.0);
	float hs = hash13(cell);
	if (hs < star_density) {
		vec3 centre = normalize((cell + 0.5) / 200.0);
		float d = length(dir - centre) * 200.0;
		float mask = smoothstep(0.35, 0.8, sy) * smoothstep(1.5, 3.0, rim);
		col += vec3(0.85, 0.88, 1.0) * max(0.0, 1.0 - d * 4.0) * (0.5 + 0.5 * hash13(cell + 7.0)) * mask * 1.4;
	}

	COLOR = col;
}
