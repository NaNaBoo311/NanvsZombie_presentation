extends RefCounted

# TitleEffects — builds the title's generated stage pieces, one draw call each:
#   - leyline(): the Long Mạch ribbon, a Catmull-Rom centreline strip that
#     TitleLeyline.gdshader turns to face the camera and fills with flowing light;
#   - spirits(): rising Cô Hồn, a MultiMesh of quads placed once per stream and
#     animated entirely by TitleSpirits.gdshader;
#   - shots(): looping seed shots along vignette lanes (TitleShots.gdshader);
#   - isles() / beacons(): the chain of floating islands, one per world in the data.
# Everything here runs once at load; the shaders own all motion, so the title
# keeps zero per-frame script cost. Placement is seeded and deterministic.

const LEYLINE_STEPS := 24
const ISLE_SEED := 2411
const ISLE_SIDES := 10
## Above 1 the islands crowd together toward the eclipse, which reads as distance.
const ISLE_SPACING_POWER := 1.35
const ISLE_ROOMY := 10
const ISLE_CROWDED := 30
const ISLE_CROWD_SCALE := 0.42
const BEACON_SIZE := 1.5
const ISLE_GRASS := Color(0.11, 0.25, 0.09)
const ISLE_TREE := Color(0.06, 0.16, 0.08)
const ISLE_ROCK: Array[Color] = [Color(0.36, 0.24, 0.17), Color(0.30, 0.20, 0.16), Color(0.22, 0.16, 0.15)]


## A camera-facing ribbon through `points` (world space). Sets the shader's
## length_m so the flow fades in and out at the ends.
static func curve(points: PackedVector3Array) -> PackedVector3Array:
	var centre := PackedVector3Array()
	for i in range(points.size() - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		for k in range(LEYLINE_STEPS):
			var t := float(k) / LEYLINE_STEPS
			centre.append(0.5 * ((2.0 * p1) + (p2 - p0) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t
				+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	centre.append(points[points.size() - 1])
	return centre


static func leyline(points: PackedVector3Array, material: ShaderMaterial) -> MeshInstance3D:
	var centre := curve(points)

	var verts := PackedVector3Array()
	var tangents := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var along := 0.0
	for i in range(centre.size()):
		if i > 0:
			along += centre[i].distance_to(centre[i - 1])
		var tangent := (centre[mini(i + 1, centre.size() - 1)] - centre[maxi(i - 1, 0)]).normalized()
		for side in [-1.0, 1.0]:
			verts.append(centre[i])
			tangents.append(tangent)
			uvs.append(Vector2(along, side))
		if i > 0:
			var a := (i - 1) * 2
			idx.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	material.set_shader_parameter("length_m", along)
	var mi := MeshInstance3D.new()
	mi.name = "Leyline"
	mi.mesh = mesh
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0
	return mi


## Rising spirits. Each stream is {"centre": Vector3, "radius": float,
## "count": int, "rise": float, "size": float}: spirits start inside a disc of
## `radius` around `centre` and rise `rise` metres while they fade in and out.
static func spirits(streams: Array, material: ShaderMaterial, rng_seed: int) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var total := 0
	for s: Dictionary in streams:
		total += int(s["count"])
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = total
	var i := 0
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for s: Dictionary in streams:
		var centre: Vector3 = s["centre"]
		for _k in range(int(s["count"])):
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * float(s["radius"])
			var pos := centre + Vector3(cos(a) * r, rng.randf_range(-2.0, 2.0), sin(a) * r)
			var rise := float(s["rise"]) * rng.randf_range(0.75, 1.1)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.7, 1.3), rise,
				float(s["size"]) * rng.randf_range(0.75, 1.25)))
			lo = lo.min(pos)
			hi = hi.max(pos + Vector3(0.0, rise, 0.0))
			i += 1
	# The shader moves every quad; the culling box must cover the whole climb.
	mm.custom_aabb = AABB(lo, hi - lo).grow(4.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Spirits"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Looping seed shots. Each lane is [from, to] in the parent's local space;
## `per_lane` seeds share a lane at evenly spread phases.
static func shots(lanes: Array, per_lane: int, material: ShaderMaterial) -> MultiMeshInstance3D:
	var seed_mesh := SphereMesh.new()
	seed_mesh.radius = 0.16
	seed_mesh.height = 0.32
	seed_mesh.radial_segments = 8
	seed_mesh.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = seed_mesh
	mm.instance_count = lanes.size() * per_lane
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var i := 0
	for lane_i in range(lanes.size()):
		var from: Vector3 = lanes[lane_i][0]
		var to: Vector3 = lanes[lane_i][1]
		var dir := (to - from).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var basis := Basis(dir, side.cross(dir), side)
		for k in range(per_lane):
			mm.set_instance_transform(i, Transform3D(basis, from))
			mm.set_instance_custom_data(i, Color(float(k) / per_lane + lane_i * 0.37, from.distance_to(to), 0.0, 0.0))
			i += 1
		lo = lo.min(from).min(to)
		hi = hi.max(from).max(to)
	mm.custom_aabb = AABB(lo, hi - lo).grow(3.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Shots"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Where each island in the chain sits: spread along `centre` from `from_m` metres
## out to `end_gap` short of the far end, closer together as they recede, on
## alternating sides. Works for any count, so new worlds never need layout work.
static func isle_spots(centre: PackedVector3Array, count: int, from_m: float, end_gap: float, side_m: float) -> Array[Transform3D]:
	var total := 0.0
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, centre.size()):
		total += centre[i].distance_to(centre[i - 1])
		lengths.append(total)
	var rng := RandomNumberGenerator.new()
	rng.seed = ISLE_SEED
	var spots: Array[Transform3D] = []
	var k := 1
	# Past a handful of islands they shrink and fan out, or a long chain becomes a wall.
	var crowd := clampf(float(count - ISLE_ROOMY) / float(ISLE_CROWDED - ISLE_ROOMY), 0.0, 1.0)
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var want := from_m + (total - end_gap - from_m) * pow(t, ISLE_SPACING_POWER)
		while k < centre.size() - 1 and lengths[k] < want:
			k += 1
		var along := (centre[k] - centre[k - 1]).normalized()
		var scatter := rng.randf_range(0.7, 1.0 + crowd * 1.6)
		var across := along.cross(Vector3.UP).normalized() * (side_m if i % 2 == 0 else -side_m) * scatter
		var size := rng.randf_range(7.5, 10.5) * lerpf(1.0, 0.72, t) * lerpf(1.0, ISLE_CROWD_SCALE, crowd)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * size)
		spots.append(Transform3D(basis, centre[k] + across + Vector3(0.0, 2.0 + rng.randf_range(-6.0, 6.0) * crowd, 0.0)))
	return spots


## One low-poly floating island per spot: a single faceted mesh in a MultiMesh, so
## the chain is one draw call however many worlds there are. Fog fades the far ones.
static func isles(spots: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _isle_mesh()
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Isles"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## A lantern floating over each island that stands for a real world. `glows` gives one
## colour per spot, brightest for a cleared world; past glows.size() there is no lantern.
static func beacons(spots: Array[Transform3D], glows: Array[Color]) -> MultiMeshInstance3D:
	var orb := SphereMesh.new()
	orb.radius = 1.0
	orb.height = 2.0
	orb.radial_segments = 8
	orb.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = orb
	mm.instance_count = glows.size()
	for i in glows.size():
		var lift := Vector3(0.0, spots[i].basis.get_scale().y * 0.42, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * BEACON_SIZE), spots[i].origin + lift))
		mm.set_instance_color(i, glows[i])
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Beacons"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## A unit island (radius ~1): grassy cap, soil lip, tapering rock, three small trees.
static func _isle_mesh() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = ISLE_SEED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := [[1.0, 0.0], [0.94, -0.09], [0.62, -0.52], [0.26, -0.98]]
	var loops: Array[PackedVector3Array] = []
	for ring: Array in rings:
		var loop := PackedVector3Array()
		for i in ISLE_SIDES:
			var a := TAU * i / ISLE_SIDES
			var r := float(ring[0]) * rng.randf_range(0.88, 1.08)
			loop.append(Vector3(cos(a) * r, float(ring[1]) + rng.randf_range(-0.03, 0.03), sin(a) * r))
		loops.append(loop)
	var tip := Vector3(0.05, -1.32, -0.03)
	for i in ISLE_SIDES:
		var j := (i + 1) % ISLE_SIDES
		_tri(st, Vector3.ZERO, loops[0][j], loops[0][i], ISLE_GRASS)
		for r in range(loops.size() - 1):
			var c: Color = ISLE_ROCK[r]
			_tri(st, loops[r][i], loops[r][j], loops[r + 1][i], c)
			_tri(st, loops[r][j], loops[r + 1][j], loops[r + 1][i], c.darkened(0.08))
		_tri(st, loops[3][i], loops[3][j], tip, ISLE_ROCK[2])
	for spot in [Vector3(-0.42, 0.0, -0.3), Vector3(0.36, 0.0, -0.42), Vector3(0.1, 0.0, 0.3)]:
		_tree(st, spot, rng.randf_range(0.15, 0.22))
	st.generate_normals()
	return st.commit()


static func _tree(st: SurfaceTool, at: Vector3, h: float) -> void:
	var top := at + Vector3(0.0, h * 1.5, 0.0)
	for i in 5:
		var a := TAU * i / 5.0
		var b := TAU * (i + 1) / 5.0
		var p := at + Vector3(cos(a), 0.0, sin(a)) * h * 0.55 + Vector3(0.0, h * 0.3, 0.0)
		var q := at + Vector3(cos(b), 0.0, sin(b)) * h * 0.55 + Vector3(0.0, h * 0.3, 0.0)
		_tri(st, p, top, q, ISLE_TREE)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	st.set_smooth_group(-1)
	st.set_color(color)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
