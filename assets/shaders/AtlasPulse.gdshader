shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// Atlas Pulse — the ring around the next level node on the province screen
// (src/menus/atlas/ProvinceBoard.gd). Breathes in scale and brightness from
// TIME on the GPU only: no script runs for it, and it exists only while the
// province screen is open.

uniform vec3 color : source_color = vec3(1.0, 0.8, 0.3);
uniform float speed = 2.2;

void vertex() {
	VERTEX.xz *= 1.0 + 0.12 * sin(TIME * speed);
}

void fragment() {
	ALBEDO = color * (0.75 + 0.35 * sin(TIME * speed));
}
