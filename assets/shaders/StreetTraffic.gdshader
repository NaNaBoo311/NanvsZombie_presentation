shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Street traffic driven entirely on the GPU (src/environment/StreetTraffic.gd): every
// MultiMesh instance keeps the identity transform and this vertex shader moves it round
// a rounded-rectangle loop (the street ring's centreline: `loop_centre`, half extents `loop_half`,
// corner radius `corner_r`), so the traffic costs no CPU at all (AGENTS.md invariant 7).
// INSTANCE_CUSTOM = (start offset 0..1 of the loop, lane + sideways jitter, variant id,
// speed m/s). Lane 0 is the inner lane driven clockwise seen from above, lane 1 the
// outer lane driven anticlockwise: right-hand traffic. The mesh holds several vehicles
// told apart by UV.x; an instance collapses every vertex that is not its own variant.
// ALBEDO is the baked vertex colour (bakeToVertexColors, already linear).

uniform vec2 loop_centre = vec2(0.0, 0.0);
uniform vec2 loop_half = vec2(60.0, 120.0);
uniform float corner_r = 5.0;
uniform float lane_offset = 1.6;
uniform float road_y = 0.03;

// Position (xy = x, z) and unit heading (zw) at arc length s on the loop with half
// extents h and corner radius r, starting at the west end of the north side and going
// east (clockwise seen from above, +X east and -Z north).
vec4 loop_point(float s, vec2 h, float r) {
	float lx = 2.0 * (h.x - r);
	float lz = 2.0 * (h.y - r);
	float q = 1.5707963 * r;
	vec2 starts[4] = vec2[](vec2(-(h.x - r), -h.y), vec2(h.x, -(h.y - r)), vec2(h.x - r, h.y), vec2(-h.x, h.y - r));
	vec2 dirs[4] = vec2[](vec2(1.0, 0.0), vec2(0.0, 1.0), vec2(-1.0, 0.0), vec2(0.0, -1.0));
	vec2 centres[4] = vec2[](vec2(h.x - r, -(h.y - r)), vec2(h.x - r, h.y - r), vec2(-(h.x - r), h.y - r), vec2(-(h.x - r), -(h.y - r)));
	for (int k = 0; k < 4; k++) {
		float len = (k % 2 == 0) ? lx : lz;
		if (s < len) {
			return vec4(starts[k] + dirs[k] * s, dirs[k]);
		}
		s -= len;
		if (s < q) {
			float a = -1.5707963 + float(k) * 1.5707963 + s / r;
			return vec4(centres[k] + r * vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
		}
		s -= q;
	}
	return vec4(starts[0], dirs[0]);
}

void vertex() {
	float variant = INSTANCE_CUSTOM.z;
	if (abs(UV.x - variant) > 0.5) {
		VERTEX = vec3(0.0);
	} else {
		float lane = INSTANCE_CUSTOM.y > 0.5 ? 1.0 : 0.0;
		float jitter = INSTANCE_CUSTOM.y - lane;
		float side = lane * 2.0 - 1.0; // inner -1, outer +1
		vec2 h = loop_half + vec2(side * lane_offset + jitter);
		float r = max(corner_r + side * lane_offset + jitter, 1.0);
		float perimeter = 4.0 * (h.x - r) + 4.0 * (h.y - r) + 6.2831853 * r;
		float s = fract(INSTANCE_CUSTOM.x + TIME * INSTANCE_CUSTOM.w / perimeter) * perimeter;
		if (lane > 0.5) {
			s = perimeter - s; // the outer lane runs the other way
		}
		vec4 p = loop_point(s, h, r);
		vec2 dir = lane > 0.5 ? -p.zw : p.zw;
		// Yaw the model (+Z forward) onto dir: cos = dir.y, sin = dir.x.
		vec3 v = VERTEX;
		VERTEX = vec3(dir.y * v.x + dir.x * v.z, v.y, -dir.x * v.x + dir.y * v.z) + vec3(loop_centre.x + p.x, road_y, loop_centre.y + p.y);
		vec3 n = NORMAL;
		NORMAL = vec3(dir.y * n.x + dir.x * n.z, n.y, -dir.x * n.x + dir.y * n.z);
	}
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
}
