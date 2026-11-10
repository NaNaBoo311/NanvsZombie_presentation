shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Street Walkers — pedestrians strolling up and down a map's streets, driven entirely on
// the GPU (src/environment/StreetWalkers.gd builds the MultiMesh once): no CPU per frame
// (AGENTS.md invariant 7). The mesh (architecture/hoi_an_street_life.mjs walkers) holds
// several people told apart by UV.x; an instance collapses every vertex that is not its
// own variant. UV.y tags the limbs (1 left leg, 2 right leg, 3 left arm, 4 right arm) for
// the walk cycle; pure white shirts take the walker's palette colour.
// Instance transform: the walker's start on its lane, local +Z along the street, with a
// uniform size scale. INSTANCE_CUSTOM = (phase 0..1, segment length m, speed m/s,
// variant * 10 + palette index + gait phase fraction). A walker goes to the end of its
// segment, turns round and comes back.

uniform vec3 palette[10];
uniform float stride = 1.3;    // metres per full gait cycle (two steps)
uniform float swing = 0.5;     // leg swing, radians
uniform float hip_y = 0.82;
uniform float shoulder_y = 1.4;

varying vec3 v_tint;

vec3 swing_x(vec3 v, float pivot_y, float a) {
	vec2 p = vec2(v.y - pivot_y, v.z);
	float c = cos(a);
	float s = sin(a);
	return vec3(v.x, pivot_y + p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	float variant = floor(INSTANCE_CUSTOM.w / 10.0);
	float colour = floor(mod(INSTANCE_CUSTOM.w, 10.0));
	float ph = fract(INSTANCE_CUSTOM.w) * 6.2831853;
	v_tint = COLOR.rgb;
	if (COLOR.r > 0.99 && COLOR.g > 0.99 && COLOR.b > 0.99) {
		v_tint = palette[int(clamp(colour, 0.0, 9.0))];
	}
	if (abs(UV.x - variant) > 0.5) {
		VERTEX = vec3(0.0);
	} else {
		float scale = max(length(MODEL_MATRIX[0].xyz), 0.001);
		float len = INSTANCE_CUSTOM.y;
		float speed = INSTANCE_CUSTOM.z;
		float cyc = fract(INSTANCE_CUSTOM.x + TIME * speed / (2.0 * len));
		float out_leg = step(cyc, 0.5);
		float s = (out_leg > 0.5 ? cyc * 2.0 : 2.0 - cyc * 2.0) * len / scale;
		// Walk cycle: legs and arms swing in opposition about hip and shoulder.
		float gait = TIME * 6.2831853 * speed / stride + ph;
		float a = sin(gait) * swing;
		vec3 v = VERTEX;
		float tag = UV.y;
		if (abs(tag - 1.0) < 0.5) {
			v = swing_x(v, hip_y, a);
		} else if (abs(tag - 2.0) < 0.5) {
			v = swing_x(v, hip_y, -a);
		} else if (abs(tag - 3.0) < 0.5) {
			v = swing_x(v, shoulder_y, -a * 0.8);
		} else if (abs(tag - 4.0) < 0.5) {
			v = swing_x(v, shoulder_y, a * 0.8);
		}
		v.y += abs(sin(gait)) * 0.03;
		vec3 n = NORMAL;
		if (out_leg < 0.5) {
			// Coming back: turn round.
			v.xz = -v.xz;
			n.xz = -n.xz;
		}
		v.z += s;
		VERTEX = v;
		NORMAL = n;
	}
}

void fragment() {
	ALBEDO = v_tint;
	ROUGHNESS = 0.85;
}
