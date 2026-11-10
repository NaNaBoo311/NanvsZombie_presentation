shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_schlick_ggx;

// Saigon River Water — opaque, procedural, world-space.
// 1 draw call, zero textures, zero per-frame GDScript (animates via TIME).
// Lit so the engine sun/moon + lantern omnis glitter through the perturbed normal.
// Day/night jade palettes, three toon depth bands, domain-warped shimmer; at night
// up to 16 reflector points (lamps, tower, moon) paint dashed emission streaks plus
// a warm bank glow. The streak block is gated on night, so it costs nothing by day;
// open water skips the foam-box loop via foam_bounds (~240 ALU saved vs ~400 for 16
// reflectors at night).
// Never write ALPHA: this material stays opaque (depth prepass + yacht sorting intact).

varying vec3 v_world;
varying vec2 v_f;
varying vec2 v_d2;
varying vec2 v_d3;
varying vec2 v_d4;

// Palette (Saigon jade preset: deep channel, mid shelf, shallow shore ribbon)
uniform vec3 deep_day : source_color = vec3(0.10, 0.24, 0.20);
uniform vec3 mid_day : source_color = vec3(0.18, 0.33, 0.26);
uniform vec3 shallow_day : source_color = vec3(0.30, 0.42, 0.30);
uniform vec3 deep_night : source_color = vec3(0.02, 0.06, 0.06);
uniform vec3 mid_night : source_color = vec3(0.035, 0.09, 0.08);
uniform vec3 shallow_night : source_color = vec3(0.06, 0.13, 0.11);
uniform vec3 foam_color : source_color = vec3(0.90, 0.95, 0.97);
uniform float day_blend : hint_range(0.0, 1.0) = 0.0;

// Small stylized fresnel sky boost on top of the engine IBL (which alone reads
// too matte at 15-30° gameplay elevations). No reflect()/matrix — one pow.
uniform vec3 sky_tint_day : source_color = vec3(0.55, 0.72, 0.88);
uniform vec3 sky_tint_night : source_color = vec3(0.18, 0.28, 0.48);
uniform float fresnel_cap_night : hint_range(0.0, 1.0) = 0.18;
uniform float reflect_boost : hint_range(0.0, 0.5) = 0.25;

// Motion
uniform vec2 flow_dir = vec2(-1.0, 0.15);
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.6;

// Roughness base (sky reflection comes from engine IBL + the small fresnel boost)
uniform float roughness_near : hint_range(0.0, 1.0) = 0.06;
uniform float roughness_far : hint_range(0.0, 1.0) = 0.22;

// Shore / foam (analytic SDF, world units)
// Bank polyline in world xz, ordered east -> west: straight south bank (stepping out to the
// central bank of zones/south_bank.json), then the r = 25 west-bend arc centred on (-95, -5). Must stay in sync with the
// bank curve authored in landmark_81/west_bend.mjs and filled (with bank_count)
// from Landmark81Water.setup_river_material().
uniform vec2 bank_pts[12];
uniform int bank_count = 0;
uniform vec3 marina_fan = vec3(-3.0, 22.5, 9.8);
uniform vec3 marina_club_fan = vec3(0.0, 0.0, -1000.0); // Phase 3 Marina Club fan (set by Landmark81Water from data/maps/landmark_81/zones/marina_club.json); default = no foam
uniform float band_shore = 2.5;
uniform float band_shelf = 9.0;
uniform float foam_width = 0.5;
uniform float foam_opacity : hint_range(0.0, 1.0) = 0.75;
uniform vec4 foam_boxes[16];
uniform int foam_box_count = 0;
uniform vec4 foam_bounds = vec4(0.0); // min x, min z, max x, max z

// Night reflections: painterly vertical streaks, one point per reflector.
// Filled once by Landmark81Water.setup_river_reflections(); the gated block below
// makes them free by day. reflector_pos = (world x, y, z, intensity),
// reflector_col = (r, g, b, vertical stretch).
uniform vec4 reflector_pos[16];
uniform vec4 reflector_col[16];
uniform int reflector_count = 0;
uniform float streak_width = 0.035;
uniform float streak_jitter = 0.35;
uniform float streak_intensity = 0.8;
uniform vec3 city_glow_color : source_color = vec3(0.95, 0.70, 0.45);
uniform float city_glow_falloff = 6.0;
uniform float city_glow_intensity = 0.15;

// Perf escape hatch: drops waves 3-4, gust/silt noise, foam breakup and the SDF loop.
uniform bool low_quality = false;

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Uniform-only math runs once per vertex (4 verts) instead of per pixel.
	v_f = normalize(flow_dir);
	v_d2 = rot(v_f, 0.6);
	v_d3 = rot(v_f, -0.9);
	v_d4 = rot(v_f, 2.1);
}

// Sin-free hash: fract(sin(...)) loses precision on large TIME-scrolled args
// on Intel/Mali/Adreno. mod() keeps the lattice small and the noise seamless.
float vhash(vec2 p) {
	p = mod(p, 289.0);
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = vhash(i);
	float b = vhash(i + vec2(1.0, 0.0));
	float c = vhash(i + vec2(0.0, 1.0));
	float d = vhash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Footprint fade: handles both distance AND grazing angles (one pixel covers
// far more water along the view dir at grazing incidence). A wave needs ~6+
// pixels per wavelength to shade cleanly.
float fade_wave(float L, float px) {
	return 1.0 - smoothstep(L / 12.0, L / 5.0, px);
}

// Signed distance to the bank polyline (world xz), positive on the river side.
// Keep the NEAREST leg's unsigned distance and take the sign from that same leg:
// a min() over signed distances lets far legs (judged against their extended
// lines) win with large negatives and paints the whole river as shore.
float bank_sdf(vec2 p) {
	if (bank_count < 2) {
		return 1e9; // no bank data: degrade to "no bank foam", never "all foam"
	}
	float best = 1e9;
	float sgn = 1.0;
	for (int i = 0; i < 11; i++) {
		if (i >= bank_count - 1) {
			break;
		}
		vec2 a = bank_pts[i];
		vec2 ba = bank_pts[i + 1] - a;
		float h = clamp(dot(p - a, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
		vec2 rel = (p - a) - ba * h;
		float dist = length(rel);
		if (dist < best) {
			vec2 bh = ba / max(length(ba), 1e-6);
			best = dist;
			sgn = (rel.x * bh.y - rel.y * bh.x) >= 0.0 ? 1.0 : -1.0;
		}
	}
	return best * sgn;
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 f = v_f;

	// World metres per pixel here — drives wave AA, foam min-width and roughness.
	float px = max(fwidth(p.x), fwidth(p.y));
	float detail = 1.0 - smoothstep(0.02, 0.15, px);

	// Analytic normals: 4 directional sines, closed-form derivatives.
	// Wavelengths use non-integer ratios so the pattern never visibly tiles.
	vec2 d1 = f;
	vec2 d2 = v_d2;
	vec2 d3 = v_d3;
	vec2 d4 = v_d4;
	float k1 = TAU / 7.0;
	float k2 = TAU / 3.1;
	float k3 = TAU / 1.7;
	float k4 = TAU / 0.9;
	float s1 = k1 * flow_speed * 1.0;
	float s2 = k2 * flow_speed * 1.3;
	float s3 = k3 * flow_speed * 1.7;
	float s4 = k4 * flow_speed * 2.3;

	// Patchy wind ("cat's-paws"): one noise layer modulates waves 3-4 and breaks shimmer periodicity.
	float gust = 0.5;
	float amp34 = 1.0;
	if (!low_quality) {
		gust = value_noise(p * 0.35 + f * TIME * flow_speed * 0.6);
		amp34 = mix(0.4, 1.0, gust);
	}

	float a1 = 0.050;
	float a2 = 0.030;
	float a3 = 0.018 * amp34;
	float a4 = 0.010 * amp34;
	if (low_quality) {
		a3 = 0.0;
		a4 = 0.0;
	}
	a1 *= fade_wave(7.0, px);
	a2 *= fade_wave(3.1, px);
	a3 *= fade_wave(1.7, px);
	a4 *= fade_wave(0.9, px);

	float ph1 = dot(d1, p) * k1 - TIME * s1;
	float ph2 = dot(d2, p) * k2 - TIME * s2;
	float ph3 = dot(d3, p) * k3 - TIME * s3;
	float ph4 = dot(d4, p) * k4 - TIME * s4;
	float dhdx = a1 * k1 * d1.x * cos(ph1) + a2 * k2 * d2.x * cos(ph2);
	float dhdz = a1 * k1 * d1.y * cos(ph1) + a2 * k2 * d2.y * cos(ph2);
	if (!low_quality) {
		dhdx += a3 * k3 * d3.x * cos(ph3) + a4 * k4 * d4.x * cos(ph4);
		dhdz += a3 * k3 * d3.y * cos(ph3) + a4 * k4 * d4.y * cos(ph4);
	}

	float amp = wave_strength;
	vec3 n_world = normalize(vec3(-dhdx * amp, 1.0, -dhdz * amp));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Fake depth / shore factor (no depth texture).
	float d_bank = bank_sdf(p);
	float d_marina = min(length(v_world.xz - marina_fan.xy) - marina_fan.z,
		length(v_world.xz - marina_club_fan.xy) - marina_club_fan.z);
	float d_shore = min(d_bank, d_marina);
	if (!low_quality && foam_box_count > 0) {
		if (p.x >= foam_bounds.x && p.x <= foam_bounds.z && p.y >= foam_bounds.y && p.y <= foam_bounds.w) {
			for (int i = 0; i < 16; i++) {
				if (i >= foam_box_count) {
					break;
				}
				// Rounded box: r derived from half-extents, no extra uniform.
				float r = min(foam_boxes[i].z, foam_boxes[i].w) * 0.8;
				vec2 q = abs(v_world.xz - foam_boxes[i].xy) - foam_boxes[i].zw + r;
				float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
				d_shore = min(d_shore, sd);
			}
		}
	}
	// Lapping wave motion: animates both shoreline foam and depth band edges
	float lap = sin(TIME * 2.2 + p.x * 0.4 + p.y * 0.3) * 0.12;

	// Three toon depth bands (shallow shore, mid shelf, deep channel)
	vec3 c_deep = mix(deep_night, deep_day, day_blend);
	vec3 c_mid = mix(mid_night, mid_day, day_blend);
	vec3 c_shallow = mix(shallow_night, shallow_day, day_blend);

	float aa = max(px * 1.5, 0.05);
	float edge_shore = band_shore + lap;
	float edge_shelf = band_shelf + lap;
	float shelf_factor = 1.0 - smoothstep(edge_shelf - aa, edge_shelf + aa, d_shore);
	vec3 col_shelf = mix(c_deep, c_mid, shelf_factor);
	float shore_factor = 1.0 - smoothstep(edge_shore - aa, edge_shore + aa, d_shore);
	vec3 body = mix(col_shelf, c_shallow, shore_factor);

	// Crisp stylized shoreline foam rim with animated lapping wave motion
	float dd = max(d_shore + lap, 0.0);
	float fw = max(foam_width, px * 3.5);
	float foam = smoothstep(fw, 0.0, dd) * foam_opacity;
	vec3 foam_col = foam_color * mix(0.70, 1.0, day_blend);

	// Normal -> roughness AA: waves the footprint can't resolve become a softer,
	// wider highlight instead of vanishing (or aliasing into stripes).
	float rough = mix(roughness_near, roughness_far, 1.0 - detail);
	rough += (1.0 - fade_wave(1.7, px)) * 0.15;

	// View-dependent Schlick Fresnel sky reflection at grazing angles
	vec3 view_dir = normalize(-VERTEX);
	float ndotv = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - ndotv, 4.0);
	float fresnel_cap = mix(fresnel_cap_night, 0.45, day_blend);
	fresnel = clamp(fresnel * reflect_boost * 1.5, 0.0, fresnel_cap);
	vec3 sky_tint = mix(sky_tint_night, sky_tint_day, day_blend);
	vec3 sky_reflection = mix(sky_tint * 0.40, sky_tint * 1.05, day_blend);

	// Flow-aligned non-repeating wave shimmer (domain-warped with gust noise + ph3)
	float shimmer_wave = cos(ph1 + gust * 2.4) * 0.6 + cos(ph3 * 0.8 + gust * 1.5) * 0.4;
	float shimmer = smoothstep(0.55, 0.85, shimmer_wave) * fade_wave(3.1, px);
	vec3 river_body = body + vec3(0.90, 0.96, 1.0) * mix(0.002, 0.12, day_blend) * shimmer * (1.0 - shore_factor * 0.5);

	vec3 surface_col = mix(river_body, foam_col, foam);
	ALBEDO = mix(surface_col, sky_reflection, fresnel * (1.0 - foam));

	// Night reflections (emission so they stay bright on dark water through the
	// toon diffuse; values above the night glow_threshold bloom softly).
	// Uniform branch: zero cost by day.
	float night = 1.0 - day_blend;
	vec3 emission = vec3(0.0);
	if (night > 0.01 && reflector_count > 0) {
		vec3 vd = normalize(v_world - CAMERA_POSITION_WORLD);
		vec3 r = vec3(vd.x, -vd.y, vd.z); // mirrored off flat water
		r.xz += n_world.xz * streak_jitter; // waves break the streak up
		vec2 rh = normalize(r.xz + vec2(1e-6, 0.0));
		// Dash mask: broken reflections near, soft solid streaks far. Fades by the
		// dash's own ~1.8 m period (ph2 x 1.7), not the 3.1 m shimmer wave, or the
		// dashes alias into full-river zebra in wide views.
		float dash_raw = smoothstep(0.1, 0.5, 0.5 + 0.5 * cos(ph2 * 1.7 + gust * 3.0));
		float dash = mix(1.0, dash_raw, fade_wave(1.8, px));
		vec3 streak = vec3(0.0);
		for (int i = 0; i < 16; i++) {
			if (i >= reflector_count) {
				break;
			}
			vec3 L = reflector_pos[i].xyz - v_world;
			vec3 l = L * inversesqrt(max(dot(L, L), 1e-6));
			float side = abs(l.x * rh.y - l.z * rh.x); // horizontal (azimuth) error
			float elev = abs(l.y - r.y); // vertical error, allowed to be long
			float m = (1.0 - smoothstep(streak_width * 0.5, streak_width, side))
					* (1.0 - smoothstep(0.0, reflector_col[i].w, elev))
					* step(0.0, dot(l.xz, rh)); // light must be ahead of the ray
			streak += reflector_col[i].rgb * reflector_pos[i].w * m;
		}
		streak *= dash;
		// Warm skyline glow hugging the north bank and the marina fan. Uses
		// d_bank / d_marina, NOT d_shore: d_shore includes the foam boxes, which
		// are skipped outside foam_bounds, so a long falloff on d_shore would seam.
		float d_glow = min(d_bank, d_marina);
		float glow = exp(-max(d_glow, 0.0) / city_glow_falloff) * city_glow_intensity * dash;
		emission = (streak * streak_intensity + city_glow_color * glow) * night * (1.0 - foam);
	}
	EMISSION = emission;

	ROUGHNESS = clamp(rough, 0.08, 0.35);
	SPECULAR = 0.55;
	METALLIC = 0.05;
}
