shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Atlas Path — the dashed level-path ribbon on the province screen
// (built by src/menus/atlas/ProvinceBoard.gd). UV.x is the arc-length fraction
// 0..1 along the path; the ribbon shows up to `reveal`, which the board tweens
// 0 -> 1 as the path draws itself. Dash spacing is in metres via path_length.
// Static at idle: nothing reads TIME.

uniform vec3 color : source_color = vec3(1.0, 0.93, 0.7);
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
uniform float path_length = 1.0;
uniform float dash_metres = 0.07;
uniform float dash_fill : hint_range(0.0, 1.0) = 0.62;

void fragment() {
	if (UV.x > reveal || fract(UV.x * path_length / dash_metres) > dash_fill) {
		discard;
	}
	ALBEDO = color;
}
