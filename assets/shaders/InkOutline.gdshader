shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled;

// Ink Outline & Atmospheric Post-Process Shader for Whimsical Cel-Shaded Diorama
// Implements:
// - Hierarchical depth-attenuated linework (Point 3): foreground bold, distant delicate, internal creases fade early
// - Atmospheric aerial perspective (Point 2): distant objects lighten, soften, and recede into dreamy sky haze
// - Zero raster textures, 1 draw call, fully compliant with iGPU 60 FPS invariants.
//
// Depth is the ONLY screen buffer read besides colour: `hint_normal_roughness_texture`
// does not exist in the mobile renderer, so normals are implied by the depth
// Laplacian (silhouettes + creases) and the luminance curvature (interior
// detail). Same shader compiles on Forward+ and Mobile
// (TRAPS.md#mobile-renderer-screen-buffers).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

// Styling controls
uniform vec4 ink_color : source_color = vec4(0.12, 0.09, 0.08, 0.92);
uniform float line_thickness : hint_range(0.5, 3.0, 0.1) = 0.95;
uniform float depth_threshold : hint_range(0.005, 0.2, 0.005) = 0.055;
uniform float color_threshold : hint_range(0.02, 0.5, 0.01) = 0.20;
uniform float outline_opacity : hint_range(0.0, 1.0, 0.05) = 1.0;

// Atmospheric depth controls (Point 2)
uniform vec3 haze_color : source_color = vec3(0.78, 0.88, 0.96);
uniform float haze_start : hint_range(10.0, 200.0, 5.0) = 28.0;
uniform float haze_end : hint_range(60.0, 300.0, 5.0) = 115.0;
uniform float haze_intensity : hint_range(0.0, 1.0, 0.05) = 0.42;

// Storybook paper vibrancy
uniform float color_boost : hint_range(1.0, 1.5, 0.05) = 1.10;

void vertex() {
	// Full screen quad in clip space
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float get_linear_depth(vec2 uv, mat4 inv_proj) {
	float raw_depth = texture(depth_texture, uv).r;
	if (raw_depth <= 0.00001) {
		return 1000.0; // Sky / far background
	}
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -view.z / max(view.w, 0.00001);
}

void fragment() {
	vec2 screen_pixel_size = 1.0 / VIEWPORT_SIZE;
	float raw_depth_center = texture(depth_texture, SCREEN_UV).r;
	float d_c = get_linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	
	// Distance-attenuated line thickness calibrated for diorama camera (arm_length ~85m)
	float dist_scale = clamp(90.0 / max(d_c, 90.0), 0.65, 1.0);
	vec2 offset = screen_pixel_size * (line_thickness * dist_scale);
	
	// Base screen color
	vec3 base_color = texture(screen_texture, SCREEN_UV).rgb;
	
	// 1. Second-order Depth Laplacian (Second Derivative)
	float d_l = get_linear_depth(SCREEN_UV - vec2(offset.x, 0.0), INV_PROJECTION_MATRIX);
	float d_r = get_linear_depth(SCREEN_UV + vec2(offset.x, 0.0), INV_PROJECTION_MATRIX);
	float d_u = get_linear_depth(SCREEN_UV - vec2(0.0, offset.y), INV_PROJECTION_MATRIX);
	float d_d = get_linear_depth(SCREEN_UV + vec2(0.0, offset.y), INV_PROJECTION_MATRIX);
	
	float d_tl = get_linear_depth(SCREEN_UV + vec2(-offset.x, -offset.y), INV_PROJECTION_MATRIX);
	float d_br = get_linear_depth(SCREEN_UV + vec2(offset.x, offset.y), INV_PROJECTION_MATRIX);
	float d_tr = get_linear_depth(SCREEN_UV + vec2(offset.x, -offset.y), INV_PROJECTION_MATRIX);
	float d_bl = get_linear_depth(SCREEN_UV + vec2(-offset.x, offset.y), INV_PROJECTION_MATRIX);
	
	float depth_curv_cardinal = abs(d_l + d_r - 2.0 * d_c) + abs(d_u + d_d - 2.0 * d_c);
	float depth_curv_diagonal = abs(d_tl + d_br - 2.0 * d_c) + abs(d_tr + d_bl - 2.0 * d_c);
	float depth_curv = (depth_curv_cardinal + depth_curv_diagonal * 0.707) / max(d_c, 1.0);
	
	// Suppress outline if center AND all neighbors are sky
	if (raw_depth_center <= 0.00001 && d_l >= 999.0 && d_r >= 999.0 && d_u >= 999.0 && d_d >= 999.0) {
		depth_curv = 0.0;
	}
	
	float depth_edge = smoothstep(depth_threshold, depth_threshold * 2.0, depth_curv);
	
	// 2. Color / Contrast Edge Detection (interior detail: leaf creases at
	// near-equal depth, colour boundaries on flat surfaces)
	vec3 c_l = texture(screen_texture, SCREEN_UV - vec2(offset.x, 0.0)).rgb;
	vec3 c_r = texture(screen_texture, SCREEN_UV + vec2(offset.x, 0.0)).rgb;
	vec3 c_u = texture(screen_texture, SCREEN_UV - vec2(0.0, offset.y)).rgb;
	vec3 c_d = texture(screen_texture, SCREEN_UV + vec2(0.0, offset.y)).rgb;
	
	const vec3 lum_weights = vec3(0.299, 0.587, 0.114);
	float lum_c = dot(base_color, lum_weights);
	float lum_l = dot(c_l, lum_weights);
	float lum_r = dot(c_r, lum_weights);
	float lum_u = dot(c_u, lum_weights);
	float lum_d = dot(c_d, lum_weights);
	float color_curv = abs(lum_l + lum_r - 2.0 * lum_c) + abs(lum_u + lum_d - 2.0 * lum_c);
	float color_edge = smoothstep(color_threshold, color_threshold * 1.8, color_curv);
	
	// Point 3: Hierarchy in linework
	// Internal details (colour curvature) fade out beyond the gameplay island
	float detail_fade = smoothstep(130.0, 88.0, d_c);
	color_edge *= detail_fade;
	
	// Major silhouettes stay present but soften into distant background
	float silhouette_fade = smoothstep(haze_end, haze_start, d_c) * 0.5 + 0.5;
	depth_edge *= silhouette_fade;
	
	// Combine edges
	float total_edge = clamp(depth_edge * 1.0 + color_edge * 0.55, 0.0, 1.0) * outline_opacity;
	
	// Base color enhancement (storybook vibrancy)
	// pow() of a negative is NaN, and the HDR screen can hold slightly negative values in
	// very dark pixels; the glow pass then spreads the NaN into white blobs
	// (TRAPS.md#dark-sky-white-blobs). Clamp first.
	vec3 enhanced_color = pow(max(base_color, vec3(0.0)), vec3(0.96)) * color_boost;
	
	// Point 2: Atmospheric depth (aerial perspective haze)
	// Distant non-sky geometry lightens and softly shifts toward sky haze tint
	if (raw_depth_center > 0.00001) {
		float haze_factor = smoothstep(haze_start, haze_end, d_c) * haze_intensity;
		float gray = dot(enhanced_color, lum_weights);
		// Gentle desaturation at distance
		enhanced_color = mix(enhanced_color, vec3(gray), haze_factor * 0.20);
		// Blend toward dreamy sky haze
		enhanced_color = mix(enhanced_color, haze_color, haze_factor);
	}
	
	// Ink color softens with distance into haze tint
	vec3 current_ink = mix(ink_color.rgb, haze_color, smoothstep(30.0, haze_end, d_c) * 0.5);
	
	// Final composite
	vec3 final_color = mix(enhanced_color, current_ink, total_edge * ink_color.a);
	
	ALBEDO = final_color;
}
