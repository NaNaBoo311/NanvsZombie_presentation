class_name RouteClearance
extends RefCounted

# RouteClearance — sweeps enemy routes (NavGrid's) against the obstacles actually in
# the loaded scene, so a route that a later edit blocks (a tree moved onto it, a new
# lamp, a railing closed over the promenade gap) fails a test instead of shipping.
# An enemy on a route is KINEMATIC, so it would clip straight through whatever is in
# the way with no error at all (CONTRACT(add-wave)).
#
# Deliberately not reading forest.json or the zone files: those
# are a second copy that drifts. The source of truth is the scene, so this walks it.
# Never names a map.
#
# For each route it sweeps the largest enemy capsule in BalanceDB.enemies()
# (so a bigger enemy added later is covered) along the route, lifted
# CLEARANCE off the floor so ground, stair nosings and bridge decks do not count,
# and ray-casts down at every sample to check the route's y against the surface that
# is really there. Hits are reported with the node path of what was hit, so the
# author knows what to move. Airborne samples are swept for canopies (tower,
# skybridges, trees) but skip the feet probe, except the touchdown (1->0 transition)
# which is still checked.
#
# Two things keep it cheap, and both matter: one trimesh shape is created per DISTINCT
# mesh and shared by all its instances, and every candidate is rejected by a coarse
# XZ grid of the routes BEFORE a physics body is made. Landmark 81 alone has 768 grass
# tufts, 319 trees split over ~50 material batches and 42 villas split over 4 more;
# the grid cuts that to the handful actually beside a route, so the sweep costs
# milliseconds instead of inserting thousands of bodies into the broadphase.

## Physics layer the temporary obstacle bodies live on. Nothing else uses it, and
## the bodies are freed before returning, so the game never sees them.
const SWEEP_LAYER := 1 << 19
## How far the sweeping capsule is lifted off the route, in metres: enough to clear
## the floor, a stair nosing and a bridge deck, not enough to clear a kerb. Grass
## tufts are 0.44 m tall and the capsule's underside rides 0.35 m up, so they are
## correctly passed over without needing a name list.
const CLEARANCE: float = 0.35
## Spacing of sweep samples along a route, in metres.
const SAMPLE_STEP: float = 0.5
## How far below the route point the feet ray reaches, in metres.
const PROBE_DEPTH: float = 1.5
## Route y may sit at most this far above the surface it is supposed to stand on
## (a ghost legitimately hovers ~0.11 above the lawn) and no further below it (that
## would bury it). Outside either bound the point is wrong.
const FLOAT_MAX: float = 0.45
const SINK_MAX: float = 0.05
## An obstacle whose top is within this of the route point's y is a STEP, not a wall:
## a ghost walks up a kerb or onto a low deck, so a pontoon 0.1 m under the route and
## a bridge parapet beside it are both passable. It is generous on purpose, because the
## alternative is failing the sweep over ground a ghost visibly stands on.
const STEP_UP: float = 0.35
## Grid cell size for the XZ proximity filter, in metres.
const CELL: float = 4.0
## A candidate whose AABB covers more cells than this is not worth iterating: it is
## decided by the overall route bounds instead. Keeps one huge island-sized AABB
## from costing thousands of dictionary lookups.
const MAX_CELLS: int = 512
## Meshes above this triangle count are skipped rather than copied into a trimesh
## shape, so a future detailed model cannot stall the test.
const MAX_TRIS: int = 60000
## Frames to wait after adding bodies so the physics server has registered them.
const SETTLE_FRAMES: int = 2

## An obstacle under the route that must be moved, or a route point whose y does not
## match the surface beneath it. `where` is the route sample, `at` the obstacle's
## own world position, so an author can see both ends of the collision.
class Hit:
	var gate: String # the route's label (NavGrid: "<region>")
	var lane: int
	var where: Vector3
	var thing: String
	var at: Vector3

	func _to_string() -> String:
		return "route \"%s\" #%d at (%.1f, %.1f) %s" % [gate, lane, where.x, where.z, thing]


static func _hit(gate: String, lane: int, where: Vector3, thing: String, at: Vector3) -> Hit:
	var h := Hit.new()
	h.gate = gate
	h.lane = lane
	h.where = where
	h.thing = thing
	h.at = at
	return h




## Sweep every route of `routes` ({gate: label, lane, points, wet, airborne}, see
## NavGrid.sample_routes) against `map`'s scene. Returns one problem string per hit or
## bad feet height; empty means the routes are clear.
static func run(map: Node3D, routes: Array[Dictionary]) -> PackedStringArray:
	var problems := PackedStringArray()
	if routes.is_empty() or map == null:
		return problems

	var capsule := largest_enemy_capsule()
	if capsule.x <= 0.0 or capsule.y <= 0.0:
		problems.append("RouteClearance: no enemy CollisionShape3D found; the routes were not swept")
		return problems

	# Build the XZ grid of the routes, then give only the obstacles beside them a
	# physics body. The grid is what makes this affordable (see the header).
	var grid := _build_grid(routes, capsule.x * 0.5)
	var bounds := _route_bounds(routes, capsule.x * 0.5)
	var t0 := Time.get_ticks_msec()
	var obstacles := {}
	var bodies := _build_sweep(map, grid, bounds, obstacles)
	var tree := map.get_tree()
	for i in SETTLE_FRAMES:
		await tree.physics_frame
	for hit in _sweep(tree, routes, capsule, obstacles):
		problems.append(str(hit))
	for body in bodies:
		if is_instance_valid(body):
			body.queue_free()
	print("[RouteClearance] %d routes, %d sample points, %d obstacle bodies, %d problem(s) in %d ms" % [
		routes.size(), _sample_count(routes), bodies.size(), problems.size(), Time.get_ticks_msec() - t0])
	return problems


## Obstacle bodies for EVERY scene mesh in the XZ rect `bounds` (NavGrid.bake, where no
## route narrows the search). Returns {bodies, obstacles}; the caller waits SETTLE_FRAMES
## physics frames, queries SWEEP_LAYER, then frees the bodies.
static func build_obstacles(map: Node3D, bounds: Rect2) -> Dictionary:
	var grid: Dictionary = {}
	for x in range(int(floor(bounds.position.x / CELL)), int(ceil(bounds.end.x / CELL)) + 1):
		for z in range(int(floor(bounds.position.y / CELL)), int(ceil(bounds.end.y / CELL)) + 1):
			grid[Vector2i(x, z)] = true
	var box := AABB(Vector3(bounds.position.x, -100.0, bounds.position.y), Vector3(bounds.size.x, 300.0, bounds.size.y))
	var obstacles := {}
	var bodies := _build_sweep(map, grid, box, obstacles)
	return {"bodies": bodies, "obstacles": obstacles}


## World top of the obstacle a shape-query hit belongs to (INF for a body this run did not build).
static func obstacle_top(hit: Dictionary, obstacles: Dictionary) -> float:
	return float(_thing(hit, obstacles)["top"])


static func _sample_count(routes: Array[Dictionary]) -> int:
	var n := 0
	for route in routes:
		n += (route["points"] as PackedVector3Array).size()
	return n


## One capsule-sized (radius, height) pair: the largest among the enemy scenes, so a
## bigger enemy is covered without editing this file.
static func largest_enemy_capsule() -> Vector2:
	var best := Vector2.ZERO
	for entry in BalanceDB.enemies():
		var packed := load(str(entry["scene"])) as PackedScene
		if packed == null:
			continue
		var probe := packed.instantiate()
		for child in _all_shapes(probe):
			var shape := child as CollisionShape3D
			if shape == null:
				continue
			var s := shape.shape
			var r := 0.0
			var h := 0.0
			if s is CapsuleShape3D:
				r = (s as CapsuleShape3D).radius
				h = (s as CapsuleShape3D).height
			elif s is CylinderShape3D:
				r = (s as CylinderShape3D).radius
				h = (s as CylinderShape3D).height
			if r * 2.0 > best.x:
				best = Vector2(r * 2.0, h)
		probe.free()
	return best


static func _all_shapes(node: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is CollisionShape3D:
			out.append(cur)
		for child in cur.get_children():
			stack.append(child)
	return out


## One route dict ({points, lengths, wet, airborne}, the format HungryGhost.follow_route
## walks) as a sweep entry, resampled to SAMPLE_STEP so the sweep has even spacing
## however the route was built. `wet` marks the samples on a bridge deck, where the foot
## height is authored and the water plane underneath is not the surface the ghost walks
## on. `airborne` marks gliding samples (both ends airborne); the touchdown 1->0 is
## ground for the feet probe.
static func sweep_entry(label: String, lane: int, route: Dictionary) -> Dictionary:
	return {
		"gate": label, "lane": lane,
		"points": _resample(route["points"] as PackedVector3Array, route["lengths"] as PackedFloat32Array),
		"wet": _resample_wet(route["wet"] as PackedByteArray, route["lengths"] as PackedFloat32Array),
		"airborne": _resample_air(route["airborne"] as PackedByteArray, route["lengths"] as PackedFloat32Array),
	}


## Insert a sample every SAMPLE_STEP along a route, so a long straight hop is swept
## as densely as the resampled approach.
static func _resample(points: PackedVector3Array, lengths: PackedFloat32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.append(points[0])
	for i in lengths.size():
		var steps := maxi(1, int(ceil(lengths[i] / SAMPLE_STEP)))
		for s in range(1, steps + 1):
			out.append(points[i].lerp(points[i + 1], float(s) / float(steps)))
	return out


## The same resampling for the per-sample water flags: every sample generated on
## segment i inherits that segment's flag, since they all lie between the same two
## source points.
static func _resample_wet(wet: PackedByteArray, lengths: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(wet[0] if not wet.is_empty() else 0)
	for i in lengths.size():
		var steps := maxi(1, int(ceil(lengths[i] / SAMPLE_STEP)))
		for s in steps:
			out.append(wet[i] if i < wet.size() else 0)
	return out


## Airborne resampling with AND-of-endpoints for intermediates: a segment whose
## ends are 1->0 (touchdown) yields ground intermediates, so the feet probe still
## checks the touchdown area. Landing points keep their authored flag.
static func _resample_air(air: PackedByteArray, lengths: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.append(air[0] if not air.is_empty() else 0)
	for i in lengths.size():
		var steps := maxi(1, int(ceil(lengths[i] / SAMPLE_STEP)))
		var a0 := air[i] if i < air.size() else 0
		var a1 := air[i + 1] if i + 1 < air.size() else 0
		var seg_air := 1 if (a0 == 1 and a1 == 1) else 0
		for s in range(steps):
			if s < steps - 1:
				out.append(seg_air)
			else:
				out.append(a1)
	return out


## Union of every route's footprint, inflated, so anything nowhere near a route is
## rejected before it costs a trimesh copy.
static func _route_bounds(routes: Array[Dictionary], pad: float) -> AABB:
	var first := (routes[0]["points"] as PackedVector3Array)[0]
	var box := AABB(first, Vector3.ZERO)
	for route in routes:
		for p in route["points"] as PackedVector3Array:
			box = box.expand(p)
	return box.grow(pad)


## Give every obstacle beside a route a physics body on SWEEP_LAYER. One shape per
## distinct mesh, shared by all its instances; a MultiMesh contributes one body per
## instance but they all reference the same shape. Bodies are parented to the map
## and freed by run().
##
## `obstacles` is filled with body id -> {label, top, at}: the label the author
## needs to see, the world top of the box (for the step rule) and where it stands.
## Keying by id rather than by node name keeps the report working whatever the node
## is called and costs nothing at query time.
static func _build_sweep(map: Node3D, grid: Dictionary, bounds: AABB, obstacles: Dictionary) -> Array[CollisionObject3D]:
	var bodies: Array[CollisionObject3D] = []
	var shapes: Dictionary = {} # mesh instance id -> ConcavePolygonShape3D or null
	var stack: Array[Node] = [map]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for child in cur.get_children():
			stack.append(child)
		if cur is MultiMeshInstance3D:
			_collect_multimesh(cur, map, grid, bounds, shapes, bodies, obstacles)
		elif cur is MeshInstance3D:
			_collect_mesh(cur, map, grid, bounds, shapes, bodies, obstacles)
	return bodies


static func _collect_multimesh(node: MultiMeshInstance3D, map: Node3D, grid: Dictionary, bounds: AABB, shapes: Dictionary, bodies: Array[CollisionObject3D], obstacles: Dictionary) -> void:
	var mm := node.multimesh
	if mm == null or mm.mesh == null:
		return
	# Grass tufts are soft: a ghost walks through them (the capsule underside rides 0.35 m
	# up, but a tall tuft still reaches 0.5 m), so they never count as obstacles.
	if "grassmultimesh" in str(node.name).to_lower():
		return
	# The dummy (headless) renderer keeps no instance buffer, so every transform reads back
	# as the origin and the trees would all be swept at (0, 0, 0): callers must have a window.
	var base := mm.mesh.get_aabb()
	var world := node.global_transform
	for i in mm.instance_count:
		var xf := world * mm.get_instance_transform(i)
		var box := _transformed_aabb(base, xf)
		if not _near_route(box, grid, bounds):
			continue
		# One body per instance, all sharing the mesh's trimesh.
		var shape := _shape_for(mm.mesh, shapes)
		if shape == null:
			continue
		bodies.append(_body(map, shape, xf, box, "%s #%d" % [node.name, i], obstacles))


static func _collect_mesh(node: MeshInstance3D, map: Node3D, grid: Dictionary, bounds: AABB, shapes: Dictionary, bodies: Array[CollisionObject3D], obstacles: Dictionary) -> void:
	if node.mesh == null:
		return
	var box := _transformed_aabb(node.mesh.get_aabb(), node.global_transform)
	if not _near_route(box, grid, bounds):
		return
	var shape := _shape_for(node.mesh, shapes)
	if shape == null:
		return
	bodies.append(_body(map, shape, node.global_transform, box, str(node.get_path()), obstacles))


static func _body(map: Node3D, shape: ConcavePolygonShape3D, xf: Transform3D, box: AABB, label: String, obstacles: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	shape.resource_name = label
	body.collision_layer = SWEEP_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	map.add_child(body)
	body.global_transform = xf
	obstacles[body.get_instance_id()] = {
		"label": label,
		"top": box.end.y,
		"at": Vector3(xf.origin.x, 0.0, xf.origin.z),
	}
	return body


## Set of XZ cells (CELL-sized) within pad of any route point.
static func _build_grid(routes: Array[Dictionary], pad: float) -> Dictionary:
	var grid: Dictionary = {}
	for route in routes:
		for p in route["points"] as PackedVector3Array:
			var x0 := int(floor((p.x - pad) / CELL))
			var x1 := int(floor((p.x + pad) / CELL))
			var z0 := int(floor((p.z - pad) / CELL))
			var z1 := int(floor((p.z + pad) / CELL))
			for x in range(x0, x1 + 1):
				for z in range(z0, z1 + 1):
					grid[Vector2i(x, z)] = true
	return grid


## Whether an obstacle's world AABB reaches any route cell. A box too big to iterate
## (the island, a tower batch) is decided by the overall route bounds instead.
static func _near_route(box: AABB, grid: Dictionary, bounds: AABB) -> bool:
	var x0 := int(floor(box.position.x / CELL))
	var x1 := int(floor((box.end.x) / CELL))
	var z0 := int(floor(box.position.z / CELL))
	var z1 := int(floor((box.end.z) / CELL))
	if (x1 - x0 + 1) * (z1 - z0 + 1) > MAX_CELLS:
		return box.intersects(bounds)
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if grid.has(Vector2i(x, z)):
				return true
	return false


## A shared trimesh for this mesh, or null when it is too detailed to copy cheaply.
static func _shape_for(mesh: Mesh, shapes: Dictionary) -> ConcavePolygonShape3D:
	var key := mesh.get_instance_id()
	if shapes.has(key):
		return shapes[key]
	var shape: ConcavePolygonShape3D = null
	if mesh is ArrayMesh and _tris(mesh) <= MAX_TRIS:
		shape = mesh.create_trimesh_shape()
	shapes[key] = shape
	return shape


static func _tris(mesh: ArrayMesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		total += mesh.surface_get_array_len(s) / 3
	return total


## Sweep the capsule along every route, and ray straight down at each sample to
## compare the route's y with the surface that is really under it.
static func _sweep(tree: SceneTree, routes: Array[Dictionary], capsule: Vector2, obstacles: Dictionary) -> Array:
	var space := tree.root.get_world_3d().direct_space_state
	var shape := CapsuleShape3D.new()
	shape.radius = capsule.x * 0.5
	shape.height = capsule.y
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = SWEEP_LAYER
	var ray := PhysicsRayQueryParameters3D.new()
	ray.collision_mask = SWEEP_LAYER
	var hits: Array = []
	for route in routes:
		var points: PackedVector3Array = route["points"]
		var wet: PackedByteArray = route["wet"]
		var air: PackedByteArray = route.get("airborne", PackedByteArray())
		for i in points.size():
			var p: Vector3 = points[i]
			# Capsule centre CLEARANCE + half a height up, so the capsule's underside
			# rides CLEARANCE above the route point: floors, stair nosings and bridge
			# decks pass under it, kerbs and railings do not.
			query.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * (CLEARANCE + capsule.y * 0.5))
			for r in space.intersect_shape(query, 2):
				var thing: Dictionary = _thing(r, obstacles)
				if float(thing["top"]) <= p.y + STEP_UP:
					break # a kerb or a low deck: something to walk onto, not a wall
				hits.append(_hit(str(route["gate"]), int(route["lane"]), p,
					"hits %s standing at (%.1f, %.1f)" % [thing["label"], (thing["at"] as Vector3).x, (thing["at"] as Vector3).z],
					thing["at"] as Vector3))
				break
			if wet[i] == 1:
				continue
			if air.size() > i + 1 and air[i] == 1 and air[i + 1] == 1:
				continue # gliding (touchdown 1->0 is still probed)
			if air.size() > i and air.size() == points.size() and i + 1 == points.size() and air[i] == 1:
				continue # trailing airborne sample with no next (never authored, stay safe)
			var found := _probe_ground(space, ray, p)
			if not is_finite(found):
				continue # nothing to stand on here (over the void off the island)
			var delta := p.y - found
			if delta < -SINK_MAX or delta > FLOAT_MAX:
				hits.append(_hit(str(route["gate"]), int(route["lane"]), p,
					"sits %.2f m %s the surface at y %.2f (route y %.2f) - fix the point's y" % [
						absf(delta), "below" if delta < 0.0 else "above", found, p.y], p))
	return hits


## The walking surface under a route point, or NAN when the ray finds nothing (over
## water and off the island, where the point's y is authored by hand).
static func _probe_ground(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D, p: Vector3) -> float:
	ray.from = p + Vector3.UP * 0.05
	ray.to = p - Vector3.UP * PROBE_DEPTH
	var res := space.intersect_ray(ray)
	return float((res["position"] as Vector3).y) if not res.is_empty() else NAN


## What a hit is: the label and the box top recorded when the body was built. A hit on
## anything this run did not build is reported by its node path, so it is never silent.
static func _thing(hit: Dictionary, obstacles: Dictionary) -> Dictionary:
	var collider: Object = hit.get("collider")
	if collider is Node3D:
		var known: Variant = obstacles.get((collider as Node3D).get_instance_id())
		if known is Dictionary:
			return known
		return {"label": "%s (%s)" % [str((collider as Node3D).name), str((collider as Node3D).get_path())], "top": INF, "at": (collider as Node3D).global_position}
	return {"label": str(hit.get("collider_name", "?")), "top": INF, "at": Vector3.ZERO}


## Axis-aligned bounds of a mesh after a transform, by its 8 corners.
static func _transformed_aabb(box: AABB, xf: Transform3D) -> AABB:
	var out := AABB(xf * box.position, Vector3.ZERO)
	for i in 8:
		var corner := box.position + Vector3(
			box.size.x if i & 1 else 0.0,
			box.size.y if i & 2 else 0.0,
			box.size.z if i & 4 else 0.0)
		out = out.expand(xf * corner)
	return out
