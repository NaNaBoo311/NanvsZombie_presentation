shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_schlick_ggx;

// Pond Water (crescent lake + koi pond + Lake 3) — opaque, procedural, world-space.
// Same lighting approach as SaigonRiverWater: lit perturbed normal + roughness +
// small fresnel sky boost. Still water: slow multidirectional ripples, no flow
// direction, no bank SDF, no foam boxes. No vertex displacement: koi sit at
// y 0.03 above water 0.02, so VERTEX is never touched.
// Fountain rings are drawn here from `fountains` (x, z, pedestal r, _), which
// replaces the static FountainWaterRipples mesh (see DioramaWorld).
// Optional shore shading from `shore_lake` / `shore_islands` (smooth unions of
// ellipses, no depth texture): a shaded band against the bank walls and deeper colour
// toward the middle. Off while shore_lake_count is 0, so maps that leave it unset look
// unchanged. CONTRACT(lake-shape): ellipse_sd and smin match HoanKiemZones.gd and the
// generator's lake_shape.mjs term for term.
// Never write ALPHA: this material stays opaque.

varying vec3 v_world;
varying vec2 v_d2;
varying vec2 v_d3;

// Palette (turquoise reflecting-lake preset, seeded from the 0x00acc1 fallback)
uniform vec3 deep_color : source_color = vec3(0.05, 0.25, 0.27);
uniform vec3 shallow_color : source_color = vec3(0.30, 0.55, 0.53);
uniform vec3 ring_color : source_color = vec3(0.88, 0.96, 0.97);
uniform float day_blend : hint_range(0.0, 1.0) = 0.0;

// Small stylized fresnel sky boost on top of the engine IBL (same reason as the
// river: engine IBL alone reads too matte at 15-30° gameplay elevations).
uniform vec3 sky_tint : source_color = vec3(0.55, 0.72, 0.88);
uniform float reflect_boost : hint_range(0.0, 0.5) = 0.25;

// Motion
uniform float wave_strength : hint_range(0.0, 1.0) = 0.6;
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.35;

// Roughness base (sky reflection comes from engine IBL + the small fresnel boost)
uniform float roughness_near : hint_range(0.0, 1.0) = 0.06;
uniform float roughness_far : hint_range(0.0, 1.0) = 0.22;

// Fountain ripple rings: world xz centre + pedestal radius in `fountains[i].z`.
// Filled once by Landmark81Water.setup_pond_material() (CONTRACT(mesh-names)).
uniform vec4 fountains[5];
uniform int fountain_count = 0;
uniform float ring_opacity : hint_range(0.0, 1.0) = 0.6;

// Caustic glints: 1 for clear shallow pools, 0 for murky lakes.
uniform float caustic_strength : hint_range(0.0, 1.0) = 1.0;

// Shore shading: the ellipse lobes (centre x, z, radii rx, rz) whose smooth union is
// the water, and the island lobes cut out of it, each set blended over its own metres.
// Filled once by the map (HoanKiemMap._setup_water).
uniform vec4 shore_lake[4];
uniform int shore_lake_count = 0;
uniform float shore_lake_blend = 0.0;
uniform vec4 shore_islands[8];
uniform int shore_island_count = 0;
uniform float shore_island_blend = 0.0;
// Metres of shade against the bank walls, and how dark it gets there.
uniform float shore_band : hint_range(0.0, 4.0) = 1.0;
uniform float shore_shade : hint_range(0.0, 1.0) = 0.4;
// Metres from the bank to the full deep colour.
uniform float depth_span : hint_range(1.0, 40.0) = 14.0;

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Uniform-only math runs once per vertex instead of per pixel.
	vec2 d1 = vec2(0.86, 0.51);
	v_d2 = rot(d1, 2.1);
	v_d3 = rot(d1, -2.4);
}

// Approximate signed distance to an axis-aligned ellipse (negative inside); close
// to exact near the outline, which is the only place the shore band needs it.
float ellipse_sd(vec2 p, vec2 r) {
	float k0 = length(p / r);
	float k1 = length(p / (r * r));
	if (k1 < 1e-6) {
		return -min(r.x, r.y);
	}
	return k0 * (k0 - 1.0) / k1;
}

// Polynomial smooth minimum over `k` metres.
float smin(float a, float b, float k) {
	if (k <= 0.0) {
		return min(a, b);
	}
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return b + (a - b) * h - k * h * (1.0 - h);
}

// Footprint fade: handles both distance AND grazing angles (one pixel covers
// far more water along the view dir at grazing incidence). A wave needs ~6+
// pixels per wavelength to shade cleanly.
float fade_wave(float L, float px) {
	return 1.0 - smoothstep(L / 12.0, L / 5.0, px);
}

void fragment() {
	vec2 p = v_world.xz;

	// World metres per pixel here — drives wave AA and roughness.
	float px = max(fwidth(p.x), fwidth(p.y));
	float detail = 1.0 - smoothstep(0.02, 0.15, px);

	// Analytic normals: 3 multidirectional sines, closed-form derivatives.
	// Directions oppose each other so the pattern shimmers in place instead of
	// drifting one way; wavelengths use non-integer ratios so it never tiles.
	vec2 d1 = vec2(0.86, 0.51);
	vec2 d2 = v_d2;
	vec2 d3 = v_d3;
	float k1 = TAU / 6.0;
	float k2 = TAU / 2.8;
	float k3 = TAU / 1.4;
	float s1 = ripple_speed * 1.0;
	float s2 = ripple_speed * 1.4;
	float s3 = ripple_speed * 1.9;

	float f1 = fade_wave(6.0, px);
	float f2 = fade_wave(2.8, px);
	float f3 = fade_wave(1.4, px);
	float a1 = 0.035 * f1;
	float a2 = 0.022 * f2;
	float a3 = 0.012 * f3;

	float ph1 = dot(d1, p) * k1 + TIME * s1;
	float ph2 = dot(d2, p) * k2 - TIME * s2;
	float ph3 = dot(d3, p) * k3 + TIME * s3;
	vec2 grad = a1 * k1 * d1 * cos(ph1) + a2 * k2 * d2 * cos(ph2) + a3 * k3 * d3 * cos(ph3);

	float amp = wave_strength;
	vec3 n_world = normalize(vec3(-grad.x * amp, 1.0, -grad.y * amp));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Distance to the nearest bank (metres), when the map gave its shore ellipses.
	float shore_d = 1e3;
	if (shore_lake_count > 0) {
		float lake_d = ellipse_sd(p - shore_lake[0].xy, shore_lake[0].zw);
		for (int i = 1; i < 4; i++) {
			if (i >= shore_lake_count) {
				break;
			}
			lake_d = smin(lake_d, ellipse_sd(p - shore_lake[i].xy, shore_lake[i].zw), shore_lake_blend);
		}
		float island_d = 1e3;
		for (int i = 0; i < 8; i++) {
			if (i >= shore_island_count) {
				break;
			}
			float d = ellipse_sd(p - shore_islands[i].xy, shore_islands[i].zw);
			island_d = i == 0 ? d : smin(island_d, d, shore_island_blend);
		}
		shore_d = min(-lake_d, island_d);
	}

	// Still-water body: gentle variation faked from the ripple field so the lakes
	// don't read as flat paint, faded with the waves so it never aliases into a
	// lattice at distance. With shore ellipses, lighter by the banks, deep mid-lake.
	float body_n = 0.5 * (cos(ph1) * 0.5 * f1 + cos(ph2) * 0.3 * f2 + cos(ph3) * 0.2 * f3);
	float lift = 0.5;
	if (shore_lake_count > 0) {
		lift = mix(0.75, 0.2, smoothstep(0.0, depth_span, shore_d));
	}
	vec3 body = mix(deep_color, shallow_color, lift + body_n * 0.3);
	// Shade against the bank walls (no effect while shore_d stays 1e3).
	body *= 1.0 - shore_shade * (1.0 - smoothstep(0.0, shore_band, shore_d));

	// Expanding fountain rings: thin bands radiating from each pedestal.
	// `fract(d - TIME)` gives outward motion; the envelope fades by ~4.5 m so
	// the koi pond (no fountain) and far shores stay calm.
	float ring = 0.0;
	for (int i = 0; i < 5; i++) {
		if (i >= fountain_count) {
			break;
		}
		vec4 f = fountains[i];
		float d = length(p - f.xy) - f.z;
		if (d < 0.0 || d > 4.5) {
			continue;
		}
		float wave = fract(d * 0.9 - TIME * 0.6);
		float band = smoothstep(0.0, 0.12, wave) * (1.0 - smoothstep(0.12, 0.30, wave));
		float env = (1.0 - smoothstep(0.0, 4.5, d)) * smoothstep(0.0, 0.4, d);
		ring = max(ring, band * env);
	}
	// Rings stay visible at panorama distance: never thinner than ~3 px.
	ring *= ring_opacity * mix(0.7, 1.0, detail);
	// Dim rings at night so lantern omnis don't blow them out.
	vec3 ring_col = ring_color * mix(0.55, 1.0, day_blend);

	// Normal -> roughness AA: waves the footprint can't resolve become a softer,
	// wider highlight instead of vanishing (or aliasing into stripes).
	float rough = mix(roughness_near, roughness_far, 1.0 - detail);
	rough += (1.0 - fade_wave(1.4, px)) * 0.15;

	// View-dependent Schlick Fresnel sky reflection at grazing angles
	vec3 view_dir = normalize(-VERTEX);
	float ndotv = clamp(dot(NORMAL, view_dir), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - ndotv, 4.0);
	fresnel = clamp(fresnel * reflect_boost * 1.5, 0.0, 0.45);
	vec3 sky_reflection = mix(sky_tint * 0.40, sky_tint * 1.05, day_blend);

	// Cellular caustics where the 3 wave phases peak together; their cells are as
	// small as the shortest wave, so they fade with it instead of aliasing.
	float caustic_sum = cos(ph1) + cos(ph2) + cos(ph3);
	float caustic_val = smoothstep(1.3, 2.4, caustic_sum) * caustic_strength * f3;
	vec3 caustic_color = vec3(0.92, 0.98, 1.0) * mix(0.06, 0.20, day_blend) * caustic_val;

	// Composite water body with caustics, fountain rings, and fresnel sky sheen
	vec3 water_col = body + caustic_color;
	water_col = mix(water_col, ring_col, clamp(ring, 0.0, 1.0));
	ALBEDO = mix(water_col, sky_reflection, fresnel * (1.0 - ring));

	ROUGHNESS = clamp(rough, 0.08, 0.32);
	SPECULAR = 0.55;
	METALLIC = 0.05;
}
