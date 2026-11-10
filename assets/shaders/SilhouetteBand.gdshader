shader_type spatial;
render_mode unshaded, fog_disabled, cull_back;

// ============================================================================
// SilhouetteBand.gdshader
// Distant city silhouette band around the diorama island.
// Single merged draw call. Emulates procedural sky gradient for atmospheric
// horizon blending, adds aerial perspective, and generates night windows.
// Kinds (UV2.y, tools/asset_generator/generators/maps/silhouette_kit.mjs): 0 ground /
// plain, 1 tower, 2 house, 3 low/mid-rise, 4 tree, 5 red beacon, and the old-town
// kinds Hoi An uses: 6 silk lantern (a coloured dot, from the seed), 7 old-town
// house (lamplit shopfront, rare shuttered window), 8 paddy water (mirrors the sky), and
// the street kinds Landmark 81 uses for its two streets running out to the horizon:
// 9 asphalt, 10 pavement, 11 road marking.
// ============================================================================

// Procedural Sky Gradient Uniforms (updated by Landmark81DayGrade from environment)
uniform vec4 sky_top_color : source_color = vec4(0.385, 0.454, 0.55, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform vec4 ground_horizon_color : source_color = vec4(0.646, 0.656, 0.67, 1.0);
uniform vec4 ground_bottom_color : source_color = vec4(0.2, 0.169, 0.133, 1.0);
uniform float sky_curve : hint_range(0.001, 1.0) = 0.15;
uniform float ground_curve : hint_range(0.001, 1.0) = 0.02;
uniform float sky_energy_multiplier = 1.0;
uniform float ground_energy_multiplier = 1.0;

// Day / Night Blend (0.0 = night, 1.0 = day)
uniform float day_blend : hint_range(0.0, 1.0) = 0.0;

// Silhouette Tones
uniform vec3 tone_night : source_color = vec3(0.04, 0.06, 0.12);
uniform vec3 tone_day : source_color = vec3(0.36, 0.48, 0.60);

// Base Fade Heights (rise from haze below island)
uniform float fade_y0 = -10.0;
uniform float fade_y1 = 4.0;

varying vec3 v_world_pos;
varying vec3 v_normal_world;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 eye_dir = normalize(v_world_pos - CAMERA_POSITION_WORLD);

	// 1. Procedural Sky Color behind this fragment
	float v_angle = acos(clamp(eye_dir.y, -1.0, 1.0));
	float c = 1.0 - (v_angle / (PI * 0.5));
	vec3 sky_col;
	if (c > 0.0) {
		float k = clamp(1.0 - pow(1.0 - c, 1.0 / max(sky_curve, 0.001)), 0.0, 1.0);
		sky_col = mix(sky_horizon_color.rgb, sky_top_color.rgb, k) * sky_energy_multiplier;
	} else {
		float k = clamp(1.0 - pow(1.0 + c, 1.0 / max(ground_curve, 0.001)), 0.0, 1.0);
		sky_col = mix(ground_horizon_color.rgb, ground_bottom_color.rgb, k) * ground_energy_multiplier;
	}

	// 2. Silhouette Tone and Base Fade
	vec3 tone = mix(tone_night, tone_day, day_blend);

	// UV2 (TEXCOORD_1): x = row_strength, y = kind + seed
	float row_strength = UV2.x;
	float raw_kind = floor(UV2.y);
	int kind = int(raw_kind);
	float seed = fract(UV2.y);

	float base_fade = smoothstep(fade_y0, fade_y1, v_world_pos.y);
	// Far-bank quay top sits at y = 0.3 at full opacity without bottom fade
	if (kind == 0 && row_strength >= 0.95) {
		base_fade = 1.0;
	}

	float seed_jitter = 1.0 + (seed - 0.5) * 0.08;
	float silhouette_weight = clamp(row_strength * base_fade * seed_jitter, 0.0, 1.0);
	vec3 col = mix(sky_col, tone, silhouette_weight);

	// 3. Night Windows & Lights (Kinds 1: Tower, 2: House, 3: Mid-rise/Low-rise)
	float night_factor = 1.0 - day_blend;
	if (night_factor > 0.01 && (kind == 1 || kind == 2 || kind == 3)) {
		float floor_h = (kind == 1) ? 3.0 : 2.8;
		float bay_w = 2.4;

		vec2 cell_idx = floor(vec2(UV.x / bay_w, UV.y / floor_h));
		vec2 cell_uv = fract(vec2(UV.x / bay_w, UV.y / floor_h));

		float win_mask = step(0.18, cell_uv.x) * step(cell_uv.x, 0.82) *
		                 step(0.18, cell_uv.y) * step(cell_uv.y, 0.82);

		// Density per kind: towers ~0.30, houses ~0.40, lowrise ~0.25
		float density = (kind == 1) ? 0.30 : ((kind == 2) ? 0.40 : 0.25);
		float h_val = hash13(vec3(cell_idx, raw_kind * 13.0 + seed * 99.0));
		float is_lit = (h_val < density) ? 1.0 : 0.0;

		// Anti-shimmer: fade windows if cell is too small on screen
		vec2 fw = fwidth(UV);
		float cell_res = min(bay_w / max(fw.x, 0.0001), floor_h / max(fw.y, 0.0001));
		float shimmer_fade = smoothstep(2.5, 6.0, cell_res);

		// Window colors: warm yellow for houses, warm/cool white mix for towers
		vec3 win_col;
		if (kind == 2) {
			win_col = vec3(0.90, 0.72, 0.36); // warm tungsten / amber
		} else {
			win_col = mix(vec3(0.88, 0.76, 0.55), vec3(0.68, 0.80, 0.90), fract(seed * 7.13));
		}

		// Row 1 south houses get warm shopfront strip on ground floor
		if (kind == 2 && row_strength > 0.75 && UV.y < 2.4) {
			win_mask = step(0.1, cell_uv.x) * step(cell_uv.x, 0.9) * step(0.15, cell_uv.y);
			win_col = vec3(0.90, 0.75, 0.42);
			is_lit = (hash13(vec3(cell_idx.x, 0.0, seed * 50.0)) < 0.75) ? 1.0 : 0.0;
		}

		vec3 win_contrib = win_col * is_lit * win_mask * night_factor * base_fade * row_strength * shimmer_fade;
		// Keep peak at or below 0.9 so windows never exceed glow threshold (1.15)
		col += clamp(win_contrib, vec3(0.0), vec3(0.85));
	}

	// 3b. Old-town houses (kind 7): no window grid. The ground floor glows like an
	// open lamplit shop; above it, now and then one shuttered window is lit.
	if (night_factor > 0.01 && kind == 7 && abs(v_normal_world.y) < 0.5) {
		vec2 cell_idx = floor(vec2(UV.x / 3.2, UV.y / 2.9));
		vec2 cell_uv = fract(vec2(UV.x / 3.2, UV.y / 2.9));
		float lit;
		float mask;
		vec3 win_col;
		if (UV.y < 2.5) {
			mask = step(0.2, cell_uv.x) * step(cell_uv.x, 0.8) * step(0.12, cell_uv.y) * step(cell_uv.y, 0.72);
			lit = (hash13(vec3(cell_idx.x, 7.0, seed * 61.0)) < 0.6) ? 1.0 : 0.0;
			win_col = mix(vec3(0.62, 0.34, 0.12), vec3(0.6, 0.2, 0.1), step(0.7, fract(seed * 5.3 + cell_idx.x * 0.37)));
		} else {
			mask = step(0.3, cell_uv.x) * step(cell_uv.x, 0.7) * step(0.3, cell_uv.y) * step(cell_uv.y, 0.75);
			lit = (hash13(vec3(cell_idx, 17.0 + seed * 71.0)) < 0.14) ? 1.0 : 0.0;
			win_col = vec3(0.55, 0.34, 0.14);
		}
		vec2 fw = fwidth(UV);
		float shimmer_fade = smoothstep(2.0, 5.0, min(3.2 / max(fw.x, 0.0001), 2.9 / max(fw.y, 0.0001)));
		col += clamp(win_col * lit * mask * night_factor * base_fade * row_strength * shimmer_fade, vec3(0.0), vec3(0.85));
	}

	// 3d. Streets (kinds 9-11): flat ribbons, a darker / lighter / near-white tone than
	// the ground, still fading into the haze with the height they sink to.
	if (kind >= 9 && kind <= 11) {
		vec3 street_tone = tone * 0.55;
		if (kind == 10) {
			street_tone = tone * 1.6 + vec3(0.04);
		} else if (kind == 11) {
			street_tone = mix(vec3(0.22, 0.24, 0.28), vec3(0.85), day_blend);
		}
		col = mix(sky_col, street_tone, silhouette_weight);
	}

	// 3c. Paddy water (kind 8): flooded rice fields mirror the sky, a shade darker.
	if (kind == 8) {
		col = mix(col, sky_col * mix(1.15, 0.85, day_blend), 0.55 * base_fade);
	}

	// 4. Red Steady Beacons on tallest towers (kind 5)
	if (kind == 5) {
		vec3 beacon_night = vec3(0.88, 0.08, 0.08); // steady aviation red
		col = mix(tone, beacon_night, night_factor);
	}

	// 5. Silk lanterns (kind 6): the seed picks the silk colour. Allowed past 1.0 so
	// they bloom like the island's lanterns; by day they are dull silk on the tone.
	if (kind == 6) {
		float k6 = floor(seed * 7.0);
		vec3 silk = k6 < 1.0 ? vec3(1.0, 0.16, 0.08) : k6 < 2.0 ? vec3(1.0, 0.5, 0.06)
			: k6 < 3.0 ? vec3(1.0, 0.82, 0.22) : k6 < 4.0 ? vec3(0.95, 0.18, 0.48)
			: k6 < 5.0 ? vec3(0.6, 0.25, 0.9) : k6 < 6.0 ? vec3(0.25, 0.5, 1.0) : vec3(0.25, 0.85, 0.4);
		ALBEDO = mix(mix(tone, silk * 0.6, 0.5), silk * 1.25, night_factor * base_fade);
	} else {
		ALBEDO = clamp(col, vec3(0.0), vec3(0.9));
	}
}
