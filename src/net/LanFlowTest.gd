extends RefCounted

# --lan-flow-test: two-process end-to-end LAN co-op test (CONTRACT(lan-coop)).
#
#   host:   $GODOT --path . -- --lan-flow-test host
#   client: $GODOT --path . -- --lan-flow-test client [ip]   (default 127.0.0.1)
#
# Unlike --net-test (transport only, inside a battle that both processes boot
# alone), this drives the real flow from the atlas: the host opens a room, the
# guest joins, the host picks a level, both load the same battle. The host
# confirms its loadout only after the guest's read-only briefing has flown out,
# so the guest must fly its camera back home (the base) when setup starts. Each
# side's placement preview must appear on the other, then clear. The guest
# places a plant, the host validates and replicates it back, then the host
# returns to the atlas and the guest follows. Exit code 0 = PASS, 1 = FAIL.
#
# The test-level id is the one --flow-test drives; the whole run stays inside
# the host-only progress rules, so it must not require an unlocked level that a
# fresh save lacks.
#
# Loaded by GameFlow.boot() under the flag (RefCounted coroutine, kept alive by
# _alive exactly like PerfTest / NetTest).

const LEVEL_ID := "hcmc_01"
const TIMEOUT_SEC := 150.0
const JOIN_TIMEOUT_SEC := 45.0
const SCENE_TIMEOUT_SEC := 60.0
const EVENT_TIMEOUT_SEC := 30.0
const SUN_GRANT := 5000

static var _alive: RefCounted = null # keeps the awaiting coroutine alive

var _tree: SceneTree
var _done := false


func run() -> void:
	_alive = self
	_tree = Engine.get_main_loop() as SceneTree
	var args := OS.get_cmdline_user_args()
	var index := args.find("--lan-flow-test")
	var mode := "host"
	if index >= 0 and index + 1 < args.size():
		mode = args[index + 1]
	var ip := "127.0.0.1"
	if index >= 0 and index + 2 < args.size() and args[index + 2].count(".") == 3:
		ip = args[index + 2]
	_start_watchdog(TIMEOUT_SEC)
	if mode == "client":
		await _run_client(ip)
	else:
		await _run_host()


# ========================================================
# HOST
# ========================================================

func _run_host() -> void:
	if not await _wait_scene(GameFlow.ATLAS_SCENE):
		_fail("host: atlas never loaded")
		return
	var guest_in := [false]
	var guest_ready := [false]
	var guest_ok := [false]
	var guest_enemies := [-1]
	var guest_done := [false]
	var guest_saw_preview := [false]
	Net.guest_joined.connect(func() -> void: guest_in[0] = true)
	Net.command_received.connect(func(cmd: Dictionary) -> void:
		var kind := str(cmd.get("t", ""))
		if kind == "lan_test_ready":
			guest_ready[0] = true
		elif kind == "lan_test_ok":
			guest_ok[0] = true
		elif kind == "lan_test_enemies":
			guest_enemies[0] = int(cmd.get("n", 0))
		elif kind == "lan_test_saw_preview":
			guest_saw_preview[0] = true
		elif kind == "lan_test_done":
			guest_done[0] = true)
	var err := Net.host_game("LAN Flow Host")
	if not err.is_empty():
		_fail("host: host_game: " + err)
		return
	if not await _wait_flag(guest_in, JOIN_TIMEOUT_SEC):
		_fail("host: no guest joined the room")
		return
	# Exactly what a level card does.
	await _wait_until(func() -> bool: return not GameFlow.busy, 20.0)
	EventBus.level_play_requested.emit(LEVEL_ID)
	if not await _wait_scene(GameFlow.BATTLE_SCENE):
		_fail("host: battle never loaded")
		return
	await _wait_until(func() -> bool: return not GameFlow.busy, 20.0)
	if not await _wait_until(func() -> bool: return _placement() != null, 20.0):
		_fail("host: no PlacementManager in the battle")
		return
	# A save that has not read hcmc_01's intro opens the Chronicle first: read it.
	if GameManager.round_state == "story":
		GameManager.finish_story()
	# The guest reports ready once its briefing has flown the camera out; only
	# then does the host start, like a real host packing seeds.
	if not await _wait_flag(guest_ready, EVENT_TIMEOUT_SEC):
		_fail("host: guest never loaded the battle")
		return
	if GameManager.round_state == "prepare" and GameManager.is_briefing_open:
		GameManager.confirm_loadout(GameManager.seed_loadout)
	GameManager.add_sun(SUN_GRANT)
	var placement := _placement()
	var plant_type := _first_seed()
	var coord := _free_tile(placement, plant_type)
	if coord == Vector2i(-999, -999):
		_fail("host: no placeable tile for " + plant_type)
		return
	# Host ghost -> guest, then the guest's ghost -> host (what PlacementManager
	# emits when a ghost changes tile, facing or validity).
	EventBus.placement_preview_changed.emit(plant_type, coord, 2, true, 0)
	Net.send_event({"t": "lan_test_preview", "plant": plant_type, "x": coord.x, "z": coord.y})
	if not await _wait_flag(guest_saw_preview, EVENT_TIMEOUT_SEC):
		_fail("host: guest never saw the host's placement preview")
		return
	if not await _wait_until(func() -> bool: return _preview_at(placement, coord, 4), EVENT_TIMEOUT_SEC):
		_fail("host: the guest's placement preview never appeared at %s" % str(coord))
		return
	EventBus.placement_preview_changed.emit("", Vector2i(-999, -999), 0, false, 0)
	Net.send_event({
		"t": "lan_test_place", "plant": plant_type,
		"x": coord.x, "z": coord.y})
	if not await _wait_until(func() -> bool: return placement.plant_at(coord) != null, EVENT_TIMEOUT_SEC):
		_fail("host: guest place command did not spawn a plant at %s" % str(coord))
		return
	if not await _wait_flag(guest_ok, EVENT_TIMEOUT_SEC):
		_fail("host: guest never confirmed the replicated plant")
		return
	# The level's first wave spawns by itself: the guest must see those enemies.
	if not await _wait_until(func() -> bool: return guest_enemies[0] >= 0, 45.0):
		_fail("host: guest never reported the wave it received")
		return
	if guest_enemies[0] <= 0:
		_fail("host: guest received no replicated enemies")
		return
	# Back to the atlas: the guest must follow, staying in the room.
	GameFlow.open_atlas()
	if not await _wait_scene(GameFlow.ATLAS_SCENE):
		_fail("host: did not return to the atlas")
		return
	if not Net.guest_connected():
		_fail("host: guest dropped while returning to the atlas")
		return
	# The guest confirms it observed the return while still connected; only then
	# may this process quit (quitting ends the session).
	if not await _wait_flag(guest_done, EVENT_TIMEOUT_SEC):
		_fail("host: guest never confirmed it followed the host to the atlas")
		return
	_pass("host: join, level sync, guest placement, wave replication and atlas return all work")


# ========================================================
# GUEST
# ========================================================

func _run_client(ip: String) -> void:
	if not await _wait_scene(GameFlow.ATLAS_SCENE):
		_fail("client: atlas never loaded")
		return
	var joined := [false]
	var place_at := [Vector2i(-999, -999), ""]
	var preview_at := [Vector2i(-999, -999), ""]
	Net.join_succeeded.connect(func(_host_name: String) -> void: joined[0] = true)
	Net.event_received.connect(func(ev: Dictionary) -> void:
		if str(ev.get("t", "")) == "lan_test_place":
			place_at[0] = Vector2i(int(ev.get("x", 0)), int(ev.get("z", 0)))
			place_at[1] = str(ev.get("plant", ""))
		elif str(ev.get("t", "")) == "lan_test_preview":
			preview_at[0] = Vector2i(int(ev.get("x", 0)), int(ev.get("z", 0)))
			preview_at[1] = str(ev.get("plant", "")))
	var err := Net.join_game(ip)
	if not err.is_empty():
		_fail("client: join_game: " + err)
		return
	if not await _wait_flag(joined, JOIN_TIMEOUT_SEC):
		_fail("client: no welcome from the host")
		return
	# The host starts the level; GameFlow.remote_play_level follows it.
	if not await _wait_scene(GameFlow.BATTLE_SCENE):
		_fail("client: battle never loaded")
		return
	var placement := _placement()
	if placement == null:
		_fail("client: no PlacementManager in the battle")
		return
	# Let the read-only briefing fly the camera out before the host starts.
	var briefing := _tree.current_scene.find_child("LoadoutBriefing", true, false) as LoadoutBriefing
	if briefing != null and await _wait_until(func() -> bool: return briefing.visible, 10.0):
		await _tree.create_timer(LoadoutBriefing.MOVE_SEC + 0.3).timeout
	Net.send_command({"t": "lan_test_ready"})
	# The host's Start closes this briefing: the camera must fly back to the base.
	if not await _wait_until(func() -> bool: return GameManager.round_state != "prepare", EVENT_TIMEOUT_SEC):
		_fail("client: the host's setup never reached the guest")
		return
	if briefing != null and not briefing.home_pose().is_empty():
		await _tree.create_timer(LoadoutBriefing.HOME_SEC + 0.4).timeout
		var cam := _tree.current_scene.find_child("ThirdPersonCamera", true, false) as Node3D
		var home: Vector3 = briefing.home_pose()["pos"]
		if cam == null or cam.global_position.distance_to(home) > 0.5:
			_fail("client: camera stayed at the briefing pose instead of returning to the base")
			return
	if not await _wait_until(func() -> bool: return preview_at[0].x != -999, EVENT_TIMEOUT_SEC):
		_fail("client: no preview request from the host")
		return
	if not await _wait_until(func() -> bool: return _preview_at(placement, preview_at[0], 2), EVENT_TIMEOUT_SEC):
		_fail("client: the host's placement preview never appeared at %s" % str(preview_at[0]))
		return
	EventBus.placement_preview_changed.emit(str(preview_at[1]), preview_at[0], 4, true, 1)
	Net.send_command({"t": "lan_test_saw_preview"})
	if not await _wait_until(func() -> bool: return place_at[0].x != -999, EVENT_TIMEOUT_SEC):
		_fail("client: no place request from the host")
		return
	if not await _wait_until(func() -> bool: return placement.partner_preview() == null, EVENT_TIMEOUT_SEC):
		_fail("client: the host's cleared preview is still shown")
		return
	EventBus.placement_preview_changed.emit("", Vector2i(-999, -999), 0, false, 1)
	var coord: Vector2i = place_at[0]
	Net.send_command({
		"t": "place", "plant": str(place_at[1]),
		"x": coord.x, "z": coord.y,
		"px": 0.0, "py": 0.0, "pz": 0.0, "rot": 0.0})
	if not await _wait_until(func() -> bool: return placement.plant_at(coord) != null, EVENT_TIMEOUT_SEC):
		_fail("client: host never replicated the plant at %s" % str(coord))
		return
	Net.send_command({"t": "lan_test_ok"})
	# Enemies are spawned by the host's wave after setup: wait for the first
	# replicated one before reporting back (also proves the snapshot channel).
	if not await _wait_until(func() -> bool: return _remote_enemy_count() > 0, 45.0):
		Net.send_command({"t": "lan_test_enemies", "n": 0})
		_fail("client: no replicated enemies arrived after the wave started")
		return
	Net.send_command({"t": "lan_test_enemies", "n": _remote_enemy_count()})
	# The host returns to the atlas: the guest follows without dropping.
	if not await _wait_scene(GameFlow.ATLAS_SCENE):
		_fail("client: did not follow the host back to the atlas")
		return
	if not Net.is_guest():
		_fail("client: link dropped instead of returning to the atlas")
		return
	# Tell the host before quitting: exit() closes the peer and ends the session.
	Net.send_command({"t": "lan_test_done"})
	await _tree.create_timer(0.8).timeout
	_pass("client: join, level sync, own placement and wave replication, atlas return all work")


# ========================================================
# HELPERS
# ========================================================

func _placement() -> PlacementManager:
	var scene := _tree.current_scene
	if scene == null or scene.scene_file_path != GameFlow.BATTLE_SCENE:
		return null
	return scene.get_node_or_null("PlacementManager") as PlacementManager


## Enemies the host announced and the guest instanced as remote copies.
func _remote_enemy_count() -> int:
	var scene := _tree.current_scene
	if scene == null or scene.scene_file_path != GameFlow.BATTLE_SCENE:
		return 0
	var container := scene.get_node_or_null("Enemies")
	if container == null:
		return 0
	var count := 0
	for child in container.get_children():
		if child is HungryGhost and (child as HungryGhost).is_remote:
			count += 1
	return count


## The partner's ghost is shown on `coord`'s tile, facing rotation step `step`,
## with the seed's model loaded into it.
func _preview_at(placement: PlacementManager, coord: Vector2i, step: int) -> bool:
	var ghost := placement.partner_preview()
	if ghost == null or ghost.get_node_or_null("GhostModel") == null:
		return false
	var at := placement.position_for_tile(coord)
	return Vector2(ghost.global_position.x, ghost.global_position.z).distance_to(Vector2(at.x, at.z)) < 0.01 \
		and is_equal_approx(ghost.rotation.y, PlacementManager.ROTATION_ANGLES[step])


func _first_seed() -> String:
	for id in GameManager.seed_loadout:
		if BalanceDB.is_playable(str(id)):
			return str(id)
	return ""


func _free_tile(placement: PlacementManager, plant_type: String) -> Vector2i:
	for coord in placement.valid_grid_coords:
		if placement.remote_placement_allowed(plant_type, coord):
			return coord
	return Vector2i(-999, -999)


func _wait_scene(path: String) -> bool:
	return await _wait_until(func() -> bool:
		var scene := _tree.current_scene
		return scene != null and scene.scene_file_path == path, SCENE_TIMEOUT_SEC)


func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not _done:
		if bool(predicate.call()):
			return true
		if Time.get_ticks_msec() >= deadline:
			return false
		await _tree.create_timer(0.05).timeout
	return false


func _wait_flag(flag: Array, seconds: float) -> bool:
	return await _wait_until(func() -> bool: return bool(flag[0]), seconds)


func _start_watchdog(seconds: float) -> void:
	await _tree.create_timer(seconds, true).timeout
	if not _done:
		push_error("[LanFlowTest] FAIL: timed out after %.0fs" % seconds)
		_tree.quit(1)


func _pass(message: String) -> void:
	_done = true
	print("[LanFlowTest] PASS: " + message)
	_tree.quit(0)


func _fail(message: String) -> void:
	_done = true
	push_error("[LanFlowTest] FAIL: " + message)
	_tree.quit(1)
