class_name EnemySpawner
extends Node3D

# Wave spawner: burrow-rise enemies with a dirt-mound telegraph. CONTRACT(add-wave)
# — the other half lives in HungryGhost (is_rising / is_airborne / spawn_buried)
# and in the plant targeting filters (PlantBase.find_nearest_in_cone, LotusShooter,
# PoppingPod skip rising AND airborne). A route with telegraph "ring" (ring only, no
# dome) still rises BURY_DEPTH into its ledge.
#
# Where they come from, in order of preference:
# 1. a nav region (data/maps/<map_id>/nav.json, NavGrid): the spawn group's "zone"
#    names a region, or without one the regions round-robin across a wave. The enemy
#    surfaces on a walkable cell of that region and walks an A* route around water
#    and obstacles (bridges included) to the lawn's edge, then marches in a straight
#    line like any other.
# 2. a spawn group's "at": [x, z] fixed point (round-test determinism).
# 3. a spawn group's "zone": a spawn_zones rect, sampled at random.
# 4. the forest belt: a square ring outside spawn_inner, sampled at random.
# A map with no nav_path has no regions, so 2-4 keep working unchanged.
#
# Flow per spawn: claim pooled mound -> telegraph 1.0s (mound scales in, red
# ring pulses) -> instantiate buried -> rise 0.8s (invulnerable, untargetable,
# no AI, no collision) -> surfaced (normal AI, enemy_spawned emitted late so
# GameManager.alive_enemies only counts hittable ghosts).
#
# Every queue entry carries a `surface` point: the walking surface at the spawn
# spot, which the mound telegraph AND the rise both read. On a nav route that is route
# point 0, so a ghost that starts on a raised deck is telegraphed where it actually
# appears instead of on the park floor. The old paths pass the flat _surface_y, so
# they are unaffected.
#
# Wave-ready: WAVE_DEFS below is the code-first PvZ composition table (groups
# of {enemy_id, count, interval, delay}). request_wave() expands a def into the
# timestamped queue; a future WaveDirector/HUD only calls request_wave() and
# listens to the existing wave_started / wave_completed signals. data/waves/
# JSON and permanent grave markers are the planned next steps, not this file.
#
# Perf budget (AGENTS.md invariants): no _process (one 5Hz pump Timer that
# stops when the queue drains); 1 shared mound mesh + 1 shared opaque material
# across a pool of 8 (0 idle draw calls, <=8 transient, cast_shadow OFF, no
# transparency, no particles, no lights); forest positions precomputed math
# only (no raycasts); scene cache dict on the spawn path. The nav grid is read once
# at map load and a route is one A* per spawn cell (cached), on the 5 Hz pump.
#
# Coexistence: EnemyDebugSpawner (G key) is untouched and shares the
# BalanceDB enemy catalog as single source of truth (CONTRACT(add-enemy)). Debug
# spawns instantly with no rise; spawner spawns buried with telegraph. Both
# write to ../Enemies. Demo loop is OFF unless --spawner-demo is passed, so
# --ghost-test / --spider-test never flake.

## Wave composition table (code-first; JSON later). delays/intervals in seconds.
## Index 0 is Round 1 ("First Night"): ghosts only, single-file trickle, max ~2
## alive at once given the ~23s forest march. Later waves draft harder mixes.
const ROUND_1_INDEX := 0
const WAVE_DEFS: Array[Dictionary] = [
	{
		"id": "round_1",
		"spawns": [
			{"enemy_id": "hungry_ghost", "count": 7, "interval_sec": 20.0, "delay_sec": 5.0},
		],
	},
	{
		"id": "wave_2",
		"spawns": [
			{"enemy_id": "hungry_ghost", "count": 4, "interval_sec": 1.5, "delay_sec": 1.0},
			{"enemy_id": "cast_iron_pot_ghost", "count": 1, "interval_sec": 1.0, "delay_sec": 6.0},
			{"enemy_id": "corpse_demon_cat", "count": 2, "interval_sec": 2.5, "delay_sec": 9.0},
		],
	},
]

## Compressed verification wave (--round-test): 3 ghosts down the x=0 lane into
## a pre-planted lotus + coconut wall. Never used by the real round.
const ROUND_TEST_DEF: Dictionary = {
	"id": "round_test",
	"spawns": [
		{"enemy_id": "hungry_ghost", "count": 1, "interval_sec": 1.0, "delay_sec": 1.0, "at": [0.0, 18.0]},
		{"enemy_id": "hungry_ghost", "count": 1, "interval_sec": 1.0, "delay_sec": 5.0, "at": [0.0, 22.0]},
		{"enemy_id": "hungry_ghost", "count": 1, "interval_sec": 1.0, "delay_sec": 9.0, "at": [0.0, 26.0]},
	],
}
const ROUND_TEST_TIMEOUT := 150.0

# Spawn band sampling comes from the loaded map (EventBus.map_loaded): a square
# ring around spawn_center, outside spawn_inner and inside spawn_outer, with fixed
# fallback points if sampling misses. Defaults below until a map loads.
const GRID_SNAP: float = 2.0
const MAX_SAMPLE_ATTEMPTS: int = 8
var _spawn_center := Vector2.ZERO
var _spawn_inner: float = 25.0
var _spawn_outer: float = 40.0
var _spawn_zones: Dictionary = {}
var _fallback_points: Array[Vector2] = [Vector2(0.0, 30.0)]
## The loaded map's nav grid (NavGrid); empty = no regions, so every spawn uses
## "at" / "zone" / the forest belt exactly as before.
var _nav: NavGrid = null
## Round-robin cursor over the nav regions, re-randomised at the start of each wave so a
## wave's traffic starts from a different side every time.
var _region_cursor: int = 0

const TELEGRAPH_DURATION: float = 1.0
const MOUND_POP_TIME: float = 0.35
const MOUND_SHRINK_TIME: float = 0.25
const MOUND_LINGER_AFTER_RISE: float = 0.4
const MAX_MOUNDS: int = 8
const MAX_QUEUE: int = 64
const PUMP_INTERVAL: float = 0.2
const DEMO_REPEAT_DELAY: float = 15.0
## Enemy origin sits this far above the sampled ground plane (matches the
## 0.3 test spawn height over the ~0.23 lawn top).
const SURFACE_LIFT: float = 0.07

@export var enemies_container_path: NodePath = ^"../Enemies"

var _queue: Array[Dictionary] = [] # {enemy_id, pos, surface, route, due}
var _clock: float = 0.0
var _pump: Timer = null
var _rng := RandomNumberGenerator.new()
var _surface_y: float = 0.3
var _fallback_idx: int = 0

# Mound pool: each root holds one shared-mesh dirt dome + one shared FactionMarker ring.
var _mound_pool: Array[Node3D] = []
var _mound_busy: Dictionary = {} # root instance_id -> true while telegraphing

# Wave tracking: exact own-enemy refs (debug G-spawns never pollute the count).
var _wave_active: bool = false
var _wave_index: int = -1
var _pending_own: Array[Node3D] = [] # scheduled, not yet surfaced
var _alive_own: Array[Node3D] = [] # surfaced, not yet defeated
var _demo_active: bool = false
var _round_test: bool = false # --round-test: compressed win-path verification

# Level sequencing (PvZ2-style): one picked level = N sub-waves back to back.
# _wave_active stays true for the WHOLE level so GameManager ignores interim
# wave_completed; the final sub-wave emits level_completed for the won path.
var _level_active: bool = false
var _level: Dictionary = {}
var _level_wave_idx: int = -1
var _level_token: int = 0
const BREAK_SMALL_SEC: float = 8.0
const BREAK_HUGE_SEC: float = 12.0
const HUGE_WARNING_SEC: float = 3.0

static var _mound_mesh: ArrayMesh = null
static var _mound_mat: StandardMaterial3D = null


func _ready() -> void:
	_rng.seed = 20260922
	_build_mound_pool()
	_pump = Timer.new()
	_pump.name = "SpawnPump"
	_pump.wait_time = PUMP_INTERVAL
	_pump.one_shot = false
	_pump.timeout.connect(_on_pump)
	add_child(_pump)
	if EventBus:
		EventBus.enemy_spawned.connect(_on_enemy_spawned)
		EventBus.enemy_defeated.connect(_on_enemy_defeated)
		EventBus.round_wave_go.connect(_on_round_wave_go)
		EventBus.round_state_changed.connect(_on_round_state_changed)
		EventBus.map_loaded.connect(_on_map_loaded)
	if "--spawner-demo" in OS.get_cmdline_user_args():
		await get_tree().physics_frame
		await get_tree().physics_frame
		start_demo()
	if "--round-test" in OS.get_cmdline_user_args():
		_round_test = true
		_run_round_test()


## Single manual spawn (tests, future director). Empty pos = sample the forest.
func request_spawn(enemy_id: String, pos: Vector3 = Vector3(1.0e9, 0.0, 0.0)) -> void:
	if _enemy_by_id(enemy_id).is_empty():
		push_warning("[EnemySpawner] Unknown enemy id: %s" % enemy_id)
		return
	if _queue.size() >= MAX_QUEUE:
		push_warning("[EnemySpawner] Queue full, dropping %s" % enemy_id)
		return
	var at := pos
	if at.x > 1.0e8:
		at = _sample_forest_pos()
	_enqueue(enemy_id, at, Vector3(at.x, _surface_y, at.z), {}, _clock)


## Single spawn from a named nav region, with the same A* approach route a wave
## group gets. request_spawn() takes a fixed point and never routes; request_wave()
## refuses while peaceful. This is the presentation's summon (and a route test).
## Returns false when the enemy is unknown or the region does not exist.
func request_demo_spawn(enemy_id: String, region: String) -> bool:
	if _enemy_by_id(enemy_id).is_empty():
		push_warning("[EnemySpawner] Unknown enemy id: %s" % enemy_id)
		return false
	if _queue.size() >= MAX_QUEUE:
		push_warning("[EnemySpawner] Queue full, dropping %s" % enemy_id)
		return false
	if _nav == null or _nav.is_empty() or not _nav.has_region(region):
		push_warning("[EnemySpawner] Unknown nav region: %s" % region)
		return false
	_queue_spawn(enemy_id, {"zone": region}, 0, 0.0)
	return true


## Expand WAVE_DEFS[idx] into the queue and announce it.
func request_wave(idx: int) -> void:
	if GameManager and GameManager.peaceful:
		return
	if idx < 0 or idx >= WAVE_DEFS.size():
		push_warning("[EnemySpawner] Bad wave index: %d" % idx)
		return
	_wave_active = true
	_wave_index = idx
	_pending_own.clear()
	_alive_own.clear()
	var def: Dictionary = WAVE_DEFS[idx]
	_expand_def(def)
	EventBus.wave_started.emit(idx)
	print("[EnemySpawner] Wave %d (%s) started: %d spawns queued." % [idx, str(def.get("id", "")), _queue.size()])


## Queue the groups of a wave def. Groups may carry an optional "at": [x, z]
## fixed point (round-test determinism) or a "zone": a nav region on a map with a nav
## grid, else a spawn_zones rect; otherwise the forest is sampled.
func _expand_def(def: Dictionary) -> void:
	_roll_region_cursor()
	for group in def.get("spawns", []):
		var eid := str(group.get("enemy_id", ""))
		if _enemy_by_id(eid).is_empty():
			push_warning("[EnemySpawner] Wave skips unknown id: %s" % eid)
			continue
		var count := int(group.get("count", 1))
		var interval := float(group.get("interval_sec", 2.0))
		var delay := float(group.get("delay_sec", 0.0))
		for i in count:
			_queue_spawn(eid, group, i, delay + interval * i)


## Round 1 entry: the GameManager setup countdown fires round_wave_go when the
## night falls. Level mode sequences the picked level; legacy path runs the
## code-first WAVE_DEFS[0]. Demo mode bypasses the round and loops wave 0.
func _on_round_wave_go() -> void:
	if GameManager and GameManager.peaceful:
		return
	if _demo_active or _wave_active:
		return
	if _round_test:
		return # test path runs its own def once defenses are planted
	if GameManager and GameManager.get("level_active") == true:
		var level: Dictionary = LevelDB.get_level(str(GameManager.get("current_level_id")))
		if not level.is_empty():
			start_level(level)
			return
	request_wave(ROUND_1_INDEX)


## PvZ2 level entry: queue sub-wave 0 now; later sub-waves chain from
## _check_wave_complete. Token-guarded so a re-pick / stop() aborts stale gaps.
func start_level(level: Dictionary) -> void:
	if GameManager and GameManager.peaceful:
		return
	_level_token += 1
	var token := _level_token
	_level_active = true
	_level = level
	_level_wave_idx = -1
	_wave_active = true
	_wave_index = 0
	_pending_own.clear()
	_alive_own.clear()
	_queue.clear()
	_next_level_wave(token)


## Advance to the next sub-wave when the previous one fully drains. Emits
## wave_started per sub-wave (HUD shows the huge banner on huge waves),
## huge_wave_incoming 3s before each huge wave, and level_completed after
## the last kill. Zero per-frame cost: one awaited gap, then silence.
func _next_level_wave(token: int) -> void:
	if token != _level_token or not is_instance_valid(self):
		return
	var waves: Array = _level.get("waves", [])
	_level_wave_idx += 1
	if _level_wave_idx >= waves.size():
		_finish_level()
		return
	var wave: Dictionary = waves[_level_wave_idx]
	var is_huge := bool(wave.get("is_huge", false))
	if _level_wave_idx > 0:
		var gap := BREAK_HUGE_SEC if is_huge else BREAK_SMALL_SEC
		await get_tree().create_timer(gap).timeout
		if token != _level_token or not is_instance_valid(self):
			return
		if not _level_active:
			return
	if is_huge:
		EventBus.huge_wave_incoming.emit(_level_wave_idx)
		await get_tree().create_timer(HUGE_WARNING_SEC).timeout
		if token != _level_token or not is_instance_valid(self):
			return
		if not _level_active:
			return
	_wave_index = _level_wave_idx
	_expand_wave(wave)
	EventBus.wave_started.emit(_level_wave_idx)
	print("[EnemySpawner] Level %s wave %d/%d (huge=%s): %d spawns queued." % [str(_level.get("id", "")), _level_wave_idx + 1, waves.size(), str(is_huge), _queue.size()])


## Queue one level sub-wave (same group math as _expand_def, minus the def).
func _expand_wave(wave: Dictionary) -> void:
	# Re-roll the region order per wave so consecutive waves do not start on the
	# same side; groups without a "zone" round-robin every region.
	_roll_region_cursor()
	for group in wave.get("spawns", []):
		if not (group is Dictionary):
			continue
		var eid := str((group as Dictionary).get("enemy_id", ""))
		if _enemy_by_id(eid).is_empty():
			push_warning("[EnemySpawner] Wave skips unknown id: %s" % eid)
			continue
		var count := int((group as Dictionary).get("count", 1))
		var interval := float((group as Dictionary).get("interval_sec", 2.0))
		var delay := float((group as Dictionary).get("delay_sec", 0.0))
		for i in count:
			_queue_spawn(eid, group, i, delay + interval * i)


## One spawn of one group: pick where it appears and how it walks in, then queue it.
## CONTRACT(add-wave): on a map with a nav grid a group's "zone" must be a key of nav.json
## "regions"; an unknown one silently round-robins instead, so NavGrid.problems() and
## LevelDB (run by --round-test) report it.
func _queue_spawn(enemy_id: String, group: Dictionary, index: int, delay: float) -> void:
	var pos: Vector3
	var surface: Vector3
	var route := {}
	var spot := _pick_nav_spot(group)
	if not is_nan(spot.x):
		route = _nav.find_route(spot)
	if not route.is_empty():
		surface = route["points"][0]
		pos = surface
	else:
		# "at" wins over "zone" wins over the forest, unchanged from before nav grids.
		var fixed: Array = group.get("at", [])
		var zone: String = str(group.get("zone", ""))
		if fixed.size() >= 2:
			pos = Vector3(float(fixed[0]), _surface_y + SURFACE_LIFT, float(fixed[1]))
		elif not zone.is_empty():
			pos = _sample_zone_pos(zone)
		else:
			pos = _sample_forest_pos()
		surface = Vector3(pos.x, _surface_y, pos.z)
	_enqueue(enemy_id, pos, surface, route, _clock + delay)


## A walkable spawn point in a nav region, or Vector2(NAN, NAN) to use a plain spawn. A
## group with an explicit "at" fixed point never takes a region ("at" means "appear
## exactly here and march from here", which --round-test relies on). A group's "zone"
## picks its region; without one the regions round-robin, so a wave comes from every side.
func _pick_nav_spot(group: Dictionary) -> Vector2:
	if _nav == null or _nav.is_empty() or (group.get("at", []) as Array).size() >= 2:
		return Vector2(NAN, NAN)
	var region := str(group.get("zone", ""))
	if not _nav.has_region(region):
		var names := _nav.region_names()
		region = names[_region_cursor % names.size()]
		_region_cursor += 1
	return _nav.sample_spawn(region, _rng)


func _roll_region_cursor() -> void:
	if _nav == null or _nav.is_empty():
		return
	_region_cursor = _rng.randi_range(0, _nav.region_names().size() - 1)


func _finish_level() -> void:
	if not _level_active:
		return
	_level_active = false
	_wave_active = false
	var lid := str(_level.get("id", ""))
	var wid := str(_level.get("world_id", ""))
	EventBus.wave_completed.emit(_level_wave_idx)
	EventBus.level_completed.emit(wid, lid)
	print("[EnemySpawner] Level %s completed." % lid)


## --round-test: full win-path verification (3s setup via GameManager, planted
## defenses, 3-ghost fixed-lane wave). PASS prints and quits on wave_completed;
## FAIL on pearl loss or the safety timeout. Mirrors the --ghost-test precedent.
func _run_round_test() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_plant_test_defenses()
	await EventBus.round_wave_go
	if not is_instance_valid(self):
		return
	_wave_active = true
	_wave_index = 0
	_pending_own.clear()
	_alive_own.clear()
	_expand_def(ROUND_TEST_DEF)
	EventBus.wave_started.emit(0)
	print("[RoundTest] 3 ghosts inbound down x=0; lotus + coconut holding.")
	await get_tree().create_timer(ROUND_TEST_TIMEOUT).timeout
	if is_instance_valid(self) and _wave_active:
		push_error("[RoundTest] FAIL: timed out waiting for wave_completed.")
		get_tree().quit(1)


## Test defenses: coconut wall on the lane, lotus behind it. Positions mirror
## the ghost-test precedent (surface y 0.3, +Z guard facing by default).
func _plant_test_defenses() -> void:
	var container := get_node_or_null("../Plants")
	if container == null:
		container = get_parent()
	var nut_scene: PackedScene = load("res://src/entities/plants/armored_coconut/ArmoredCoconut.tscn")
	var lotus_scene: PackedScene = load("res://src/entities/plants/lotus_shooter/LotusShooter.tscn")
	if nut_scene and container:
		var nut := nut_scene.instantiate() as PlantBase
		container.add_child(nut)
		nut.global_position = Vector3(0.0, 0.3, 10.0)
		nut.grid_coord = Vector2i(0, 5)
	if lotus_scene and container:
		var lotus := lotus_scene.instantiate() as PlantBase
		container.add_child(lotus)
		lotus.global_position = Vector3(0.0, 0.3, 6.0)
		lotus.grid_coord = Vector2i(0, 3)
	print("[RoundTest] Defenses planted: coconut (0,10), lotus (0,6).")


func _on_round_state_changed(state: String) -> void:
	if not _round_test or not is_instance_valid(self):
		return
	if state == "won":
		# A unit that asked for a clip its model lacks played nothing (CONTRACT(clip-names)).
		var missing := BalanceDB.reported_missing_clips()
		if not missing.is_empty():
			push_error("[RoundTest] FAIL (CONTRACT(clip-names)): clips played but missing: %s" % ", ".join(missing))
			get_tree().quit(1)
			return
		if Audio.play_count(Audio.BATTLE_START) < 1:
			push_error("[RoundTest] FAIL (CONTRACT(add-sound)): BATTLE_START never played.")
			get_tree().quit(1)
			return
		if Audio.play_count(Audio.LOTUS_SHOOT) < 1:
			push_error("[RoundTest] FAIL (CONTRACT(add-sound)): LOTUS_SHOOT never played.")
			get_tree().quit(1)
			return
		print("[RoundTest] PASS: setup -> wave -> wave_completed -> won.")
		get_tree().quit(0)
	elif state == "lost":
		push_error("[RoundTest] FAIL: pearl fell during the test wave.")
		get_tree().quit(1)


## Looping demo of WAVE_DEFS[0] for playtesting (needs --spawner-demo).
func start_demo() -> void:
	_demo_active = true
	if not _wave_active:
		request_wave(0)


func stop() -> void:
	_demo_active = false
	_wave_active = false
	_level_active = false
	_level_token += 1
	_level_wave_idx = -1
	_queue.clear()
	_pending_own.clear()
	_alive_own.clear()
	if is_instance_valid(_pump):
		_pump.stop()
	_release_all_mounds()


func _enqueue(enemy_id: String, pos: Vector3, surface: Vector3, route: Dictionary, due: float) -> void:
	_queue.append({"enemy_id": enemy_id, "pos": pos, "surface": surface, "route": route, "due": due})
	if is_instance_valid(_pump) and _pump.is_stopped():
		_pump.start()


func _on_pump() -> void:
	_clock += PUMP_INTERVAL
	# Pump due entries. _run_telegraph requeues (+1s) when the mound pool is
	# exhausted, so the pool cap only delays spawns, never drops them.
	for i in range(_queue.size() - 1, -1, -1):
		var entry: Dictionary = _queue[i]
		if float(entry.get("due", 0.0)) > _clock:
			continue
		_queue.remove_at(i)
		_run_telegraph(str(entry.get("enemy_id", "")), entry.get("pos", Vector3.ZERO), entry.get("surface", Vector3.ZERO), entry.get("route", {}))
	if _queue.is_empty() and is_instance_valid(_pump):
		_pump.stop()
	_check_wave_complete()


## Telegraph -> buried instantiate -> rise -> mound release. Async, guarded:
## the spawner outlives freed test enemies, so every await re-checks validity.
## `surface` is the walking surface at this spawn spot (route point 0 on a nav route,
## the flat _surface_y otherwise) and is the ONLY height the mound and the rise
## read, so the telegraph and the ghost always agree.
func _run_telegraph(enemy_id: String, surface_pos: Vector3, surface: Vector3, route: Dictionary) -> void:
	var mound := _claim_mound()
	if mound == null:
		_enqueue(enemy_id, surface_pos, surface, route, _clock + 1.0)
		return
	var ring_only := str(route.get("telegraph", "mound")) == "ring"
	_show_mound(mound, surface, ring_only)
	await get_tree().create_timer(TELEGRAPH_DURATION).timeout
	if not is_instance_valid(self):
		return
	var scene := _enemy_scene(enemy_id)
	if scene == null:
		_release_mound(mound)
		return
	var enemy := scene.instantiate() as HungryGhost
	if enemy == null:
		push_warning("[EnemySpawner] Scene root is not a HungryGhost: %s" % enemy_id)
		_release_mound(mound)
		return
	# Flag BEFORE add_child so _ready() takes the buried path (no pop-in, no
	# premature enemy_spawned): the count only rises on surfacing.
	enemy.is_rising = true
	_add_enemy_to_container(enemy)
	_pending_own.append(enemy)
	# Hand over the route before the rise, so the first physics tick after
	# _finish_surface already walks it instead of stepping off the spawn spot.
	if not route.is_empty():
		enemy.follow_route(route)
	var rise_to := Vector3(surface.x, surface.y + SURFACE_LIFT, surface.z)
	enemy.spawn_buried(rise_to)
	print("[EnemySpawner] %s rising at %s%s" % [enemy_id, str(rise_to), "" if route.is_empty() else " on nav route"])
	await get_tree().create_timer(HungryGhost.RISE_DURATION + MOUND_LINGER_AFTER_RISE).timeout
	if not is_instance_valid(self):
		return
	_release_mound(mound)


func _on_enemy_spawned(enemy: Node3D) -> void:
	# Buried ghosts emit only on surfacing, so this is the hittable moment.
	var i := _pending_own.find(enemy)
	if i != -1:
		_pending_own.remove_at(i)
		_alive_own.append(enemy as Node3D)
		_check_wave_complete()
	elif _wave_active and enemy.has_meta("wave_split"):
		# Mid-wave offspring of a spawned enemy (BasketBoatZombie's crabs, CONTRACT(add-wave)): it joins
		# the live list here, in the same emit that precedes its parent's
		# enemy_defeated, so the wave cannot end while it lives.
		_alive_own.append(enemy)


func _on_enemy_defeated(enemy: Node3D) -> void:
	var i := _alive_own.find(enemy)
	if i != -1:
		_alive_own.remove_at(i)
	var j := _pending_own.find(enemy)
	if j != -1:
		_pending_own.remove_at(j)
	_check_wave_complete()


func _check_wave_complete() -> void:
	if not _wave_active:
		return
	_sweep_stale()
	if _queue.is_empty() and _pending_own.is_empty() and _alive_own.is_empty():
		# Level mode: chain the next sub-wave; the last one finishes the level.
		if _level_active:
			var waves: Array = _level.get("waves", [])
			if _level_wave_idx + 1 < waves.size():
				EventBus.wave_completed.emit(_wave_index)
				_next_level_wave(_level_token)
				return
			_finish_level()
			return
		_wave_active = false
		EventBus.wave_completed.emit(_wave_index)
		print("[EnemySpawner] Wave %d completed." % _wave_index)
		if _demo_active:
			await get_tree().create_timer(DEMO_REPEAT_DELAY).timeout
			if is_instance_valid(self) and _demo_active and not _wave_active:
				request_wave(_wave_index % WAVE_DEFS.size())


## Drop refs freed without signals (test teardown frees whole groups).
func _sweep_stale() -> void:
	for i in range(_pending_own.size() - 1, -1, -1):
		if not is_instance_valid(_pending_own[i]):
			_pending_own.remove_at(i)
	for i in range(_alive_own.size() - 1, -1, -1):
		if not is_instance_valid(_alive_own[i]):
			_alive_own.remove_at(i)


# ========================================================
# FOREST SAMPLING (math only, no raycasts, spawn path only)
# ========================================================

func _sample_forest_pos() -> Vector3:
	for attempt in MAX_SAMPLE_ATTEMPTS:
		var dx := _rng.randf_range(-_spawn_outer, _spawn_outer)
		var dz := _rng.randf_range(-_spawn_outer, _spawn_outer)
		if absf(dx) < _spawn_inner and absf(dz) < _spawn_inner:
			continue # lawn clearing: graves will own this later, forest owns now
		var x := snappedf(_spawn_center.x + dx, GRID_SNAP)
		var z := snappedf(_spawn_center.y + dz, GRID_SNAP)
		return Vector3(x, _surface_y + SURFACE_LIFT, z)
	var fb: Vector2 = _fallback_points[_fallback_idx % _fallback_points.size()]
	_fallback_idx += 1
	return Vector3(fb.x, _surface_y + SURFACE_LIFT, fb.y)


func _sample_zone_pos(zone_name: String) -> Vector3:
	if _spawn_zones.has(zone_name):
		var rect: Rect2 = _spawn_zones[zone_name]
		var rx := _rng.randf_range(rect.position.x, rect.end.x)
		var rz := _rng.randf_range(rect.position.y, rect.end.y)
		var x := snappedf(rx, GRID_SNAP)
		var z := snappedf(rz, GRID_SNAP)
		return Vector3(x, _surface_y + SURFACE_LIFT, z)
	push_warning("[EnemySpawner] Unknown spawn zone '%s'; falling back to forest." % zone_name)
	return _sample_forest_pos()


## Spawn band, ground height and nav grid of the new map. _surface_y stays the
## flat ground the zone / forest samplers use; MapDefinition.ground_y_at is where
## the map itself defines it, and nav routes are terrain-aware through it.
func _on_map_loaded(map: MapDefinition) -> void:
	_spawn_center = map.spawn_center
	_surface_y = map.ground_y_at(_spawn_center.x, _spawn_center.y)
	_spawn_inner = map.spawn_inner
	_spawn_outer = map.spawn_outer
	_spawn_zones = map.spawn_zones.duplicate()
	_nav = map.nav()
	_region_cursor = 0
	if not map.spawn_fallback_points.is_empty():
		_fallback_points = map.spawn_fallback_points.duplicate()


# ========================================================
# MOUND POOL (1 shared mesh + 1 shared opaque material)
# ========================================================

func _build_mound_pool() -> void:
	for i in MAX_MOUNDS:
		var root := Node3D.new()
		root.name = "Mound%d" % i
		root.visible = false
		var dome := MeshInstance3D.new()
		dome.name = "DirtDome"
		dome.mesh = _get_mound_mesh()
		dome.material_override = _get_mound_mat()
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(dome)
		FactionMarker.attach(root, FactionMarker.Faction.ENEMY, 1.4)
		add_child(root)
		_mound_pool.append(root)


func _claim_mound() -> Node3D:
	for mound in _mound_pool:
		if is_instance_valid(mound) and not _mound_busy.get(mound.get_instance_id(), false):
			_mound_busy[mound.get_instance_id()] = true
			return mound
	return null


## The mound telegraph sits on the walking surface at `surface`, which is route
## point 0 on a nav route, so a ghost that starts on a raised deck is warned where
## it appears. Ring-only routes (telegraph "ring") hide the dirt dome and pulse only
## the FactionMarker ring.
func _show_mound(mound: Node3D, surface: Vector3, ring_only: bool = false) -> void:
	mound.global_position = Vector3(surface.x, surface.y - 0.02, surface.z)
	mound.visible = true
	mound.scale = Vector3.ONE * 0.01
	var dome := mound.get_node_or_null("DirtDome") as MeshInstance3D
	if is_instance_valid(dome):
		dome.visible = not ring_only
	# Two transient tweens per spawn, bound to the pooled root: dead on their
	# own after ~1s, zero per-frame code, zero idle cost after.
	var pop := mound.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(mound, "scale", Vector3.ONE, MOUND_POP_TIME)
	var ring := mound.get_node_or_null("FactionMarker") as MeshInstance3D
	if is_instance_valid(ring):
		var pulse := mound.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6), TELEGRAPH_DURATION * 0.5)
		pulse.tween_property(ring, "scale", Vector3(1.4, 1.0, 1.4), TELEGRAPH_DURATION * 0.5)


func _release_mound(mound: Node3D) -> void:
	if not is_instance_valid(mound):
		return
	var shrink := mound.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	shrink.tween_property(mound, "scale", Vector3.ONE * 0.01, MOUND_SHRINK_TIME)
	shrink.tween_callback(func() -> void:
		if is_instance_valid(mound):
			mound.visible = false
			mound.scale = Vector3.ONE
			var dome := mound.get_node_or_null("DirtDome") as MeshInstance3D
			if is_instance_valid(dome):
				dome.visible = true
		_mound_busy.erase(mound.get_instance_id())
	)


func _release_all_mounds() -> void:
	for mound in _mound_pool:
		if is_instance_valid(mound):
			mound.visible = false
			mound.scale = Vector3.ONE
			var dome := (mound as Node3D).get_node_or_null("DirtDome") as MeshInstance3D
			if is_instance_valid(dome):
				dome.visible = true
	_mound_busy.clear()


## Squashed dirt dome (~108 tris): baked vertex browns, ellipsoid normals.
## Built once, shared by the whole pool — zero texture memory.
static func _get_mound_mesh() -> ArrayMesh:
	if _mound_mesh != null:
		return _mound_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rx := 1.1
	var ry := 0.55
	var rings := 5
	var segs := 12
	var dark := Color(0.23, 0.14, 0.08)
	var light := Color(0.35, 0.23, 0.13)
	var apex := Vector3(0.0, ry, 0.0)
	_mound_mesh = _build_dome(st, rx, ry, rings, segs, dark, light, apex)
	return _mound_mesh


static func _build_dome(st: SurfaceTool, rx: float, ry: float, rings: int, segs: int, dark: Color, light: Color, apex: Vector3) -> ArrayMesh:
	# Ring 0 is the apex; ring r holds segs points from pole to base rim.
	var pts: Array[PackedVector3Array] = []
	pts.append(PackedVector3Array([apex]))
	for r in range(1, rings + 1):
		var t := float(r) / float(rings)
		var half := t * PI * 0.5
		var rr := rx * cos(half)
		var y := ry * sin(half)
		var ring := PackedVector3Array()
		for s in segs:
			var a := TAU * float(s) / float(segs)
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		pts.append(ring)
	for s in segs:
		var s2 := (s + 1) % segs
		_dome_tri(st, pts[0][0], light, pts[1][s], dark, pts[1][s2], dark, rx, ry)
	for r in range(1, rings):
		var t := float(r) / float(rings)
		var col := dark.lerp(light, t)
		for s in segs:
			var s2 := (s + 1) % segs
			_dome_tri(st, pts[r][s], col, pts[r + 1][s], col, pts[r + 1][s2], col, rx, ry)
			_dome_tri(st, pts[r][s], col, pts[r + 1][s2], col, pts[r][s2], col, rx, ry)
	return st.commit()


## Ellipsoid normal: exact for the squashed dome, no generate_normals pass.
static func _dome_tri(st: SurfaceTool, a: Vector3, ca: Color, b: Vector3, cb: Color, c: Vector3, cc: Color, rx: float, ry: float) -> void:
	_dome_vert(st, a, ca, rx, ry)
	_dome_vert(st, b, cb, rx, ry)
	_dome_vert(st, c, cc, rx, ry)


static func _dome_vert(st: SurfaceTool, p: Vector3, col: Color, rx: float, ry: float) -> void:
	var n := Vector3(p.x / (rx * rx), p.y / (ry * ry), p.z / (rx * rx))
	if n.length_squared() < 0.000001:
		n = Vector3.UP
	st.set_normal(n.normalized())
	st.set_color(col)
	st.add_vertex(p)


static func _get_mound_mat() -> StandardMaterial3D:
	if _mound_mat == null:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 1.0
		_mound_mat = mat
	return _mound_mat


# ========================================================
# CATALOG + CONTAINERS (spawn path only, never per-frame)
# ========================================================

## Catalog: BalanceDB (data/units/enemies/<id>.json, CONTRACT(add-enemy)).
func _enemy_by_id(enemy_id: String) -> Dictionary:
	return BalanceDB.enemy_entry(enemy_id)


func _enemy_scene(enemy_id: String) -> PackedScene:
	var scene := BalanceDB.unit_scene(enemy_id)
	if scene == null:
		push_warning("[EnemySpawner] Missing scene for: %s" % enemy_id)
	return scene


func _add_enemy_to_container(enemy: Node) -> void:
	var container := get_node_or_null(enemies_container_path)
	if container:
		container.add_child(enemy)
	else:
		get_parent().add_child(enemy)
