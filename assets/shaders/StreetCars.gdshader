shader_type spatial;
render_mode cull_back, diffuse_burley;

// Street Cars: the cars of a map's streets driving along their lanes, entirely on the GPU
// (src/environment/StreetCars.gd builds the MultiMesh once): no CPU per frame (AGENTS.md
// invariant 7). Instance transform: the car at its lane (yaw 0 = nose +x, driving east;
// yaw 180 = driving west). INSTANCE_CUSTOM = (speed m/s, span start x, span length m,
// palette index). The car drives to the end of the span and starts over at the other end,
// shrinking in and out over fade_m so it appears from, and vanishes into, the distance.
// The paint (plain light grey in the mesh, architecture/saigon_street_vehicles.mjs) takes
// the car's palette colour; glass, tyres and lights keep their own.
// Past the island rim (|world x| > rim_x) the car crossfades to the outskirts look over
// rim_fade_m: the same unshaded day/night silhouette tone SilhouetteBand.gdshader uses
// (tone_day / tone_night, same source_color convention), so moving cars melt into the
// distant band instead of driving lit PBR paint across it.

uniform vec3 palette[6];
uniform float fade_m = 14.0;
uniform float rim_x = 1000000000.0; // island half-width (outskirts island_bounds); huge = never (maps with no outskirts)
uniform float rim_fade_m = 15.0;
uniform vec3 tone_day : source_color = vec3(0.36, 0.48, 0.60);
uniform vec3 tone_night : source_color = vec3(0.04, 0.06, 0.12);
uniform float day_blend = 1.0; // 0 night .. 1 day, driven by StreetCars.gd via EventBus.day_blend_changed

varying vec3 v_tint;
varying float v_outskirt;

void vertex() {
	float speed = INSTANCE_CUSTOM.x;
	float start = INSTANCE_CUSTOM.y;
	float len = INSTANCE_CUSTOM.z;
	float dir = MODEL_MATRIX[0].x < 0.0 ? -1.0 : 1.0;
	float x0 = MODEL_MATRIX[3].x;
	float travel = mod(x0 - start + dir * speed * TIME, len);
	float grow = smoothstep(0.0, fade_m, travel) * smoothstep(0.0, fade_m, len - travel);
	// The world-x move expressed in the car's own axes (yaw only, unit scale).
	vec3 along_x = vec3(MODEL_MATRIX[0].x, MODEL_MATRIX[1].x, MODEL_MATRIX[2].x);
	VERTEX = VERTEX * grow + (start + travel - x0) * along_x;
	v_tint = COLOR.rgb;
	if (COLOR.r > 0.8 && abs(COLOR.r - COLOR.b) < 0.03) {
		v_tint = palette[int(clamp(INSTANCE_CUSTOM.w, 0.0, 5.0))];
	}
	v_outskirt = smoothstep(rim_x, rim_x + rim_fade_m, abs(start + travel));
}

void fragment() {
	// Custom shaders render about 8% darker than StandardMaterial3D (TRAPS.md#pbr-parity).
	vec3 tone = mix(tone_night, tone_day, day_blend);
	float lum = dot(v_tint, vec3(0.3333));
	vec3 sc = mix(v_tint, vec3(lum), 0.6); // desaturate toward the silhouette read
	sc = mix(sc, tone, 0.75);
	ALBEDO = mix(v_tint * 1.08, vec3(0.0), v_outskirt);
	EMISSION = sc * v_outskirt; // flat, light-independent: the unshaded band look
	ROUGHNESS = 0.45;
	METALLIC = 0.2;
}
