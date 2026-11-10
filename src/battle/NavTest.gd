extends RefCounted

# --nav-test: proves every nav region on the loaded map is walkable end to end.
# `SAMPLES` hungry ghosts are placed on spawn points of every region; each must surface,
# walk its whole A* route (NavGrid), and reach the pearl. Prints, per run: route length,
# the measured time to the end of the route and to the pearl, plus the time every enemy
# type WOULD take (its own speed over the same route). It also checks the telegraph: the
# mound must appear exactly SURFACE_LIFT + 0.02 under the ghost that rises from it, or the
# warning is showing somewhere the player cannot see. No plants are placed and no wave is
# scheduled (the flag is in GameFlow.SANDBOX_FLAGS), so the ghosts have a clear run.
#
# Fails on the timeout, on any NavGrid.problems(), on a ghost that never reaches the pearl,
# on a route time more than TIME_TOLERANCE off length / speed (+ the rise), and on any
# RouteClearance sweep hit. Prints "[NavTest] PASS" or every failure, then quits 0 / 1.
# Loaded only by DioramaWorld._ready() under the flag.

## How long a ghost may take to settle, plant, and walk, in seconds.
const SETTLE_FRAMES := 30
## How long from a spawn to the pearl is still believable before we call it a hang.
const RUN_TIMEOUT := 220.0
## Spawn points tried per region.
const SAMPLES := 4
## Measured time-to-route-end may differ from (rise + length / speed) by this much.
const TIME_TOLERANCE := 1.5
## How far the mound may sit from where its ghost surfaces, in metres.
const MOUND_TOLERANCE := 0.05
# The R-restart step reloads the shell, whose _ready would start a second run.
static var _started := false
# Nothing else references this RefCounted once run() awaits; without this the
# instance is freed and the coroutine silently never resumes.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree
var _t0: int = 0


func run(shell: Node) -> void:
	if _started:
		return
	_started = true
	_alive = self
	_tree = shell.get_tree()
	await _frames(SETTLE_FRAMES)

	if DisplayServer.get_name() == "headless":
		_failures.append("run --nav-test with a window (not --headless): the sweep cannot see MultiMesh trees there")
		_finish()
		return
	var map := _tree.get_first_node_in_group(MapDefinition.GROUP) as MapDefinition
	var nav := map.nav() if map else null
	if nav == null or nav.is_empty():
		_failures.append("map has no nav grid (%s)" % ("no map" if map == null else map.nav_path))
		_finish()
		return
	for problem in nav.problems():
		_failures.append(problem)

	var spawner := shell.find_child("EnemySpawner", true, false) as Node
	if spawner == null:
		_failures.append("no EnemySpawner in the shell")
		_finish()
		return

	for region in nav.region_names():
		print("[NavTest] region %-6s %4d spawn cells" % [region, nav.spawn_cells(region)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var runs: Array[Dictionary] = []
	for region in nav.region_names():
		for i in SAMPLES:
			var spot := nav.sample_spawn(region, rng)
			if is_nan(spot.x):
				_failures.append("region %s has no walkable spawn cell" % region)
				break
			var route := nav.find_route(spot)
			if route.is_empty():
				_failures.append("region %s: no route from (%.1f, %.1f)" % [region, spot.x, spot.y])
				continue
			runs.append({"gate": region, "lane": i, "route": route, "done": false, "lane_t": -1.0, "pearl_t": -1.0,
				"enemy": null, "mound_ok": false})
	_t0 = Time.get_ticks_msec()
	await _run_all(spawner, runs)
	_report(runs)
	_failures.append_array(await RouteClearance.run(map, nav.sample_routes(SAMPLES)))
	_finish()


## Seconds since the run started, from the wall clock. A per-frame fixed step would
## measure however fast the machine happens to run, and every number below is a
## promise about how long a walk looks like it takes.
func _now() -> float:
	return float(Time.get_ticks_msec() - _t0) / 1000.0


## Place one ghost per region sample and watch each until it reaches the pearl. Each
## ghost's clock starts the moment it is told to rise, so the rise is part of what the
## player sees; placing them one at a time (each waits out a rise) keeps the mound pool
## from being what is being measured.
##
## The watcher runs CONCURRENTLY with the placements. A watcher that only started once
## every ghost was placed would time the first ghosts at whatever moment the loop got
## around to looking at them, so a slow first placement inflates every lane time it had
## not already checked — the reported approach time then depends on how busy the machine
## was, which is a test that fails at random.
var _watch_done := false

func _run_all(spawner: Node, runs: Array[Dictionary]) -> void:
	# Long enough to place every ghost (one rise each) and then to walk every route.
	_watch_done = false
	_watch(runs, float(runs.size()) * (HungryGhost.RISE_DURATION + 0.1) + RUN_TIMEOUT)
	for run in runs:
		run["due"] = _now()
		await _place(spawner, run, float(run["due"]))
	while not _watch_done:
		await _frames(1)


## Poll every ghost each frame until the deadline: when it leaves its route, and when it
## reaches the pearl.
func _watch(runs: Array[Dictionary], budget: float) -> void:
	var deadline := _now() + budget
	while _now() < deadline:
		await _frames(1)
		var clock := _now()
		for run in runs:
			if run["done"] or float(run.get("due", -1.0)) < 0.0:
				continue
			var enemy := run["enemy"] as Node3D
			if not is_instance_valid(enemy):
				continue # freed without a defeat event: the spawn itself went wrong
			run["pearl_t"] = clock - float(run["due"])
			if not enemy.has_method("is_on_route") or not enemy.is_on_route():
				# Off the route: it has reached its lane and is marching in.
				if run["lane_t"] < 0.0:
					run["lane_t"] = clock - float(run["due"])
				if _at_house(enemy):
					run["done"] = true
	_watch_done = true
	if not runs.is_empty() and not bool(runs[0]["done"]):
		_failures.append("timeout after %.0fs: not every ghost reached the pearl" % RUN_TIMEOUT)


## Put one ghost on a region's route. The mound is sampled while it is still
## telegraphing, which is the only moment its position is meaningful.
func _place(spawner: Node, run: Dictionary, at: float) -> void:
	var route: Dictionary = run["route"]
	var surface: Vector3 = (route["points"] as PackedVector3Array)[0]
	run["surface"] = surface
	run["length"] = _route_length(route)
	run["scale"] = float(route.get("scale", 1.0))
	# Rise the ghost from the route's own surface, the way _run_telegraph does, so
	# the mound check sees the real telegraph-to-ghost relationship.
	var enemy := _instantiate(spawner)
	if enemy == null:
		return
	# Hand the route over before the rise, exactly as EnemySpawner does, then rise
	# through the real API so the ghost's own tween, its is_rising gate and the
	# mound's position are the production ones. A test that buried it by hand would
	# leave is_rising true forever and the ghost would never take a step.
	enemy.follow_route(route)
	enemy.spawn_buried(surface + Vector3.UP * EnemySpawner.SURFACE_LIFT)
	enemy.set_physics_process(false)
	run["enemy"] = enemy
	# Show the mound where the spawner would, then read it back next frame.
	# Ring-only routes hide the dome; the position check then applies to the ring.
	var mound := _claim_mound(spawner)
	if mound != null:
		mound.global_position = Vector3(surface.x, surface.y - 0.02, surface.z)
		mound.visible = true
		mound.scale = Vector3.ONE
		var dome := (mound as Node3D).get_node_or_null("DirtDome") as MeshInstance3D
		if is_instance_valid(dome):
			dome.visible = str(route.get("telegraph", "mound")) != "ring"
		run["mound"] = mound
	await _tree.create_timer(HungryGhost.RISE_DURATION + 0.1).timeout
	if mound != null and is_instance_valid(mound):
		var ghost := run["enemy"] as Node3D
		if is_instance_valid(ghost):
			# Not SURFACE_LIFT: the ghost rises to the surface + lift and then, within
			# a frame, _walk_route puts it on the route's own authored y, which is
			# where it stands. The telegraph has to be 0.02 under THAT. Ring-only
			# routes glide steeply from the ledge, so the ghost has already dropped
			# by check time; the ring is checked against the authored start instead.
			if str(route.get("telegraph", "mound")) == "ring":
				var want: float = surface.y - 0.02
				run["mound_ok"] = absf(mound.global_position.y - want) <= MOUND_TOLERANCE
				run["mound_delta"] = mound.global_position.y - want
			else:
				var got := ghost.global_position.y - 0.02
				run["mound_ok"] = absf(mound.global_position.y - got) <= MOUND_TOLERANCE
				run["mound_delta"] = mound.global_position.y - got
		mound.visible = false
		mound.scale = Vector3.ONE
		var dome_off := (mound as Node3D).get_node_or_null("DirtDome") as MeshInstance3D
		if is_instance_valid(dome_off):
			dome_off.visible = true
		run["mound"] = null
	if is_instance_valid(run["enemy"]):
		(run["enemy"] as Node3D).set_physics_process(true)
	run["surfaced_at"] = at


func _instantiate(spawner: Node) -> HungryGhost:
	var scene := BalanceDB.unit_scene("hungry_ghost")
	if scene == null:
		_failures.append("hungry_ghost has no scene")
		return null
	var enemy := scene.instantiate() as HungryGhost
	enemy.is_rising = true
	_add_enemy(spawner, enemy)
	return enemy


func _add_enemy(spawner: Node, enemy: Node) -> void:
	var container := spawner.get_node_or_null("^../Enemies")
	if container == null:
		container = spawner.get_parent()
	container.add_child(enemy)


func _claim_mound(spawner: Node) -> Node3D:
	for mound in spawner.get("_mound_pool") as Array:
		if is_instance_valid(mound) and not (mound as Node3D).visible:
			return mound as Node3D
	return null


## Close enough to the pearl to count as arrived, using the same reach the ghost's
## own siege check uses.
func _at_house(enemy: Node3D) -> bool:
	var house := enemy.get_tree().get_first_node_in_group("CentralHouse") as Node3D
	if house == null:
		return false
	if house.has_method("get_distance_to_wall"):
		return float(house.call("get_distance_to_wall", enemy.global_position)) <= 2.5
	return enemy.global_position.distance_to(house.global_position) <= 6.0


func _route_length(route: Dictionary) -> float:
	var total := 0.0
	for seg in (route.get("lengths", PackedFloat32Array()) as PackedFloat32Array):
		total += seg
	return total


func _report(runs: Array[Dictionary]) -> void:
	var ref_speed := float(BalanceDB.num("hungry_ghost", "speed", 0.0))
	print("[NavTest] %d region runs (hungry_ghost @ %.2f m/s)" % [runs.size(), ref_speed])
	for run in runs:
		var region := str(run["gate"])
		var length := float(run.get("length", 0.0))
		var want := HungryGhost.RISE_DURATION + (length / ref_speed if ref_speed > 0.0 else 0.0)
		var lane_t := float(run.get("lane_t", -1.0))
		var pearl_t := float(run.get("pearl_t", -1.0))
		print("  %-8s #%d  %6.2f m  expect %5.1fs  route %5.1fs  pearl %5.1fs%s" % [
			region, int(run["lane"]), length, want, lane_t, pearl_t,
			"" if bool(run.get("mound_ok", false)) else "  MOUND MISPLACED"])
		if lane_t < 0.0:
			_failures.append("region %s #%d never left its route" % [region, int(run["lane"])])
			continue
		if absf(lane_t - want) > TIME_TOLERANCE:
			_failures.append("region %s #%d took %.1fs to its route end, expected %.1fs (tolerance %.1fs)" % [region, int(run["lane"]), lane_t, want, TIME_TOLERANCE])
		if not bool(run.get("mound_ok", false)):
			_failures.append("region %s #%d: the mound telegraph was %.3f m off the ghost's surface (tolerance %.2f)" % [
				region, int(run["lane"]), float(run.get("mound_delta", 0.0)), MOUND_TOLERANCE])


func _finish() -> void:
	if _failures.is_empty():
		print("[NavTest] PASS")
		_tree.quit(0)
		return
	for f in _failures:
		print("[NavTest] FAIL: %s" % f)
	_tree.quit(1)


func _frames(n: int) -> void:
	for i in n:
		await _tree.physics_frame
