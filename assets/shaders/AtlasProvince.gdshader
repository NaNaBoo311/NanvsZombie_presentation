shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Atlas Province — the province pieces of vietnam_world_atlas.glb (Provinces_Locked
// and every Province_<id>). Albedo is the baked vertex colour; UV2.x holds the
// province index (vietnam_provinces.json `index`), baked by
// tools/asset_generator/generators/environment/vietnam_world_atlas/vietnam_world_atlas.mjs.
// The picker sets hovered_id / selected_id (-1 = none): that province lifts like a
// puzzle piece being picked up and brightens toward highlight_color. Nothing reads
// TIME, so there is no cost while the ids stay the same.
// province_state[index] (pushed by src/menus/atlas/AtlasMenu.gd on load and on
// progress changes): 0 no content, 1 has content but locked (desaturated and
// darkened), 2 unlocked (as authored), 3 all levels completed (warm gold tint).
// 34 slots = the 34 provinces of vietnam_provinces.json (AtlasMenu.PROVINCE_SLOTS).
// Not pixel-matched to StandardMaterial3D (TRAPS.md#pbr-parity): put every
// province mesh on this shader so the pieces match each other.

uniform int hovered_id = -1;
uniform int selected_id = -1;
uniform float hover_lift : hint_range(0.0, 0.5) = 0.06;
uniform float selected_lift : hint_range(0.0, 0.5) = 0.12;
uniform vec3 highlight_color : source_color = vec3(1.0, 0.96, 0.82);
uniform float hover_mix : hint_range(0.0, 1.0) = 0.12;
uniform float selected_mix : hint_range(0.0, 1.0) = 0.4;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float province_state[34];
// Province screen: every province except focus_id darkens by focus_dim (tweened).
uniform int focus_id = -1;
uniform float focus_dim : hint_range(0.0, 1.0) = 0.0;
uniform float locked_mix : hint_range(0.0, 1.0) = 0.6;
uniform vec3 completed_tint : source_color = vec3(1.0, 0.84, 0.4);
uniform float completed_mix : hint_range(0.0, 1.0) = 0.22;

varying float v_highlight;
varying float v_state;
varying float v_focus;

// Godot's glTF import stores COLOR_0 sRGB-encoded (the StandardMaterial3D path
// needs vertex_color_is_srgb = true for the same reason).
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	int id = int(round(UV2.x));
	v_state = (id >= 0 && id < 34) ? province_state[id] : 0.0;
	v_focus = id == focus_id ? 1.0 : 0.0;
	v_highlight = 0.0;
	if (id == selected_id) {
		VERTEX.y += selected_lift;
		v_highlight = selected_mix;
	} else if (id == hovered_id) {
		VERTEX.y += hover_lift;
		v_highlight = hover_mix;
	}
}

void fragment() {
	vec3 base = srgb_to_linear(COLOR.rgb);
	if (v_state > 0.5 && v_state < 1.5) {
		float luma = dot(base, vec3(0.2126, 0.7152, 0.0722));
		base = mix(base, vec3(luma * 0.7), locked_mix);
	} else if (v_state > 2.5) {
		base = mix(base, completed_tint, completed_mix);
	}
	if (focus_id >= 0 && v_focus < 0.5) {
		base *= 1.0 - focus_dim;
	}
	ALBEDO = mix(base, highlight_color, v_highlight);
	ROUGHNESS = roughness;
	METALLIC = 0.03;
}
