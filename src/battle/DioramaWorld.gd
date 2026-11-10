extends Node3D

# Battle shell: the gameplay scene every level plays in. Owns the shared sky,
# lights, pearl, camera, HUD and gameplay managers; the battlefield itself is a
# map scene (src/maps/<id>/, root script MapDefinition) instanced into MapSlot.
# Boot (and R-restart) loads the current level's map (LevelDB.resolve_map) or,
# before any level is picked, the first world's map (or `-- --map <id>`),
# synchronously. Picking a level on another map switches with switch_map():
# threaded load (blocking fallback), then the old map leaves the tree BEFORE the
# new one enters (so "BattleMap" group lookups never see two), Plants / Enemies
# are cleared, the pearl (or the map's defend_model) stands on the new
# pearl_position and EventBus.map_loaded lets placement, spawner and camera
# reconfigure. Same map: nothing reloads; the level only applies its time_of_day
# (or the map's default). Also runs the
# --round-test map contract check, --map-switch-test (src/maps/MapSwitchTest.gd),
# --perf-test (src/battle/PerfTest.gd), --net-test (src/net/NetTest.gd) and
# the --screenshot capture presets (src/battle/CameraPresets.gd).

const CameraPresets := preload("res://src/battle/CameraPresets.gd")

@onready var camera_rig: Node3D = $ThirdPersonCamera
@onready var _map_slot: Node3D = $MapSlot
@onready var _pearl: Node3D = $SacredDragonPearl
@onready var _plants: Node3D = $Plants
@onready var _enemies: Node3D = $Enemies
var _map: MapDefinition = null
var _map_id: String = ""
var _loading_id: String = "" # map being loaded in the background ("" = none)
var _net_bridge: Node = null

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var boot_map: String = LevelDB.resolve_map(GameManager.current_level_id) if GameManager.level_active else _dev_boot_map(args)
	_install_map(_load_scene(LevelDB.get_map_scene(boot_map)), boot_map)
	if "--round-test" in args:
		_assert_map_contracts()
	EventBus.level_selected.connect(_on_level_selected)
	# Round entry (autoloads persist across R-restart reloads, so GameManager
	# owns the per-round reset here rather than in its own _ready).
	# GameFlow and R-restart arrive with a level prepared; with no level (the
	# scene run directly, test flags) the round is the legacy single wave or the
	# test flag's sandbox (GameManager decides).
	GameManager.start_round()

	# LAN co-op: the battle-side replication bridge exists only online, so solo
	# play keeps its node count and per-frame cost unchanged (CONTRACT(lan-coop)).
	if Net != null and Net.is_online():
		ensure_net_bridge()

	if "--map-switch-test" in args:
		load("res://src/maps/MapSwitchTest.gd").new().run(self)
	if "--perf-test" in args:
		load("res://src/battle/PerfTest.gd").new().run(self)
	if "--net-test" in args:
		load("res://src/net/NetTest.gd").new().run(self)
	if "--touch-test" in args:
		load("res://src/battle/TouchTest.gd").new().run(self)
	# Nav regions: --nav-bake writes data/maps/<map_id>/nav_grid.json, --nav-test walks them,
	# --nav-debug draws the spawn regions (the briefing's highlight) for screenshots.
	if "--nav-debug" in args:
		var nav := _map.nav()
		if not nav.is_empty():
			nav.briefing_draw(_map, nav.region_names())
	if "--nav-bake" in args:
		_run_nav_bake()
	if "--nav-test" in args:
		load("res://src/battle/NavTest.gd").new().run(self)
	# Check for automated screenshot command line flag: -- --screenshot
	if "--screenshot" in args:
		_run_automated_screenshot()

## The map booted with no level picked: `-- --map <id>` (so --round-test,
## --perf-test, --nav-test and --screenshot can run on any map), else the first
## world's map.
func _dev_boot_map(args: PackedStringArray) -> String:
	var i := args.find("--map")
	if i < 0:
		return LevelDB.default_map()
	var wanted := args[i + 1] if i + 1 < args.size() else ""
	if LevelDB.get_map_scene(wanted).is_empty():
		push_error("[DioramaWorld] --map \"%s\" is not in data/maps/<map_id>/map.json; booting %s." % [wanted, LevelDB.default_map()])
		return LevelDB.default_map()
	return wanted

func current_map() -> MapDefinition:
	return _map

## The LAN bridge for this battle, or null offline. NetTest calls this after it
## opens a room from inside the running battle; GameFlow's path already has Net
## online by the time the shell loads.
func ensure_net_bridge() -> Node:
	if _net_bridge != null and is_instance_valid(_net_bridge):
		return _net_bridge
	if Net == null or not Net.is_online():
		return null
	var bridge: Node = (load("res://src/net/NetBridge.gd") as GDScript).new()
	bridge.name = "NetBridge"
	bridge.plants_container = _plants
	bridge.enemies_container = _enemies
	bridge.placement = get_node_or_null("PlacementManager") as PlacementManager
	add_child(bridge)
	_net_bridge = bridge
	return bridge

## Swap the battlefield to map_id (no-op when it is already loaded or loading).
## Awaitable: returns once the new map is in the tree and map_loaded went out.
func switch_map(map_id: String) -> void:
	if map_id == _map_id or map_id == _loading_id:
		return
	var path: String = LevelDB.get_map_scene(map_id)
	if path.is_empty():
		push_error("[DioramaWorld] Unknown map \"%s\" (not in data/maps/<map_id>/map.json)." % map_id)
		return
	_loading_id = map_id
	var packed: PackedScene = await _load_scene_threaded(path)
	if _loading_id != map_id:
		return # superseded by a newer switch while loading
	_loading_id = ""
	_install_map(packed, map_id)

func _load_scene(path: String) -> PackedScene:
	return load(path) as PackedScene if not path.is_empty() else null

## Background load; polls once per frame only while the load is in flight.
func _load_scene_threaded(path: String) -> PackedScene:
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
		return _load_scene(path)
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		return ResourceLoader.load_threaded_get(path) as PackedScene
	return _load_scene(path)

func _install_map(packed: PackedScene, map_id: String) -> void:
	var map := packed.instantiate() as MapDefinition if packed else null
	if map == null:
		push_error("[DioramaWorld] Cannot load map \"%s\" (missing scene or root does not extend MapDefinition)." % map_id)
		return
	if _map != null:
		_map_slot.remove_child(_map)
		_map.queue_free()
		for container in [_plants, _enemies]:
			for child in container.get_children():
				container.remove_child(child)
				child.queue_free()
	map.map_id = map_id
	_map_slot.add_child(map)
	_map = map
	_map_id = map_id
	if not _pearl.global_position.is_equal_approx(map.pearl_position):
		_pearl.global_position = map.pearl_position
	_pearl.set_defend_model(map.defend_model)
	EventBus.map_loaded.emit(map)
	if GameManager.level_active and LevelDB.resolve_map(GameManager.current_level_id) == map_id:
		_apply_time_of_day(GameManager.current_level_id)
	elif not _map.default_time_of_day.is_empty() and not _time_of_day_forced():
		GameManager.set_time_of_day(_map.default_time_of_day)

# --day-test / --night-test pin the phase (DayNightCycle applies them at boot); the
# threaded map load can land later, so its default must not override them.
func _time_of_day_forced() -> bool:
	var args := OS.get_cmdline_user_args()
	return "--day-test" in args or "--night-test" in args

func _on_level_selected(_world_id: String, level_id: String) -> void:
	var wanted: String = LevelDB.resolve_map(level_id)
	if wanted != _map_id:
		switch_map(wanted) # applies the level's time of day once installed
	elif _map != null:
		_apply_time_of_day(level_id)

func _apply_time_of_day(level_id: String) -> void:
	var tod := str(LevelDB.get_level(level_id).get("time_of_day", _map.default_time_of_day))
	if not tod.is_empty():
		GameManager.set_time_of_day(tod)

# --round-test guard for the map's silent lookups (CONTRACT(mesh-names) for the
# HCMC park, CONTRACT(add-wave) for the nav grid): they fail silently at runtime,
# so the test fails loudly instead. RouteClearance is the one part that has to wait
# for the map's MultiMeshes and the physics server, so this is a coroutine; the
# spawner's own --round-test wave only starts after the round machine's setup, which
# is long enough for the sweep to land first.
func _assert_map_contracts() -> void:
	if _map == null:
		push_error("[RoundTest] FAIL: no map loaded")
		get_tree().quit(1)
		return
	var problems := _map.contract_problems()
	problems.append_array(BalanceDB.contract_problems())
	problems.append_array(LevelDB.contract_problems())
	problems.append_array(Audio.contract_problems())
	if not problems.is_empty():
		for p in problems:
			push_error("[RoundTest] FAIL (CONTRACT(mesh-names) / CONTRACT(add-plant|add-enemy) / CONTRACT(clip-names) / CONTRACT(add-sound)): " + p)
		get_tree().quit(1)
		return
	problems.append_array(await RouteClearance.run(_map, _map.nav().sample_routes(4)))
	if problems.is_empty():
		print("[RoundTest] mesh-names, unit-registry and nav-route contracts OK.")
		return
	for p in problems:
		push_error("[RoundTest] FAIL (CONTRACT(add-wave) RouteClearance): " + p)
	get_tree().quit(1)

# --nav-bake: samples the loaded map into data/maps/<map_id>/nav_grid.json (NavGrid.bake),
# waiting a few frames first so the map's MultiMeshes and collision are in. Quits when done.
func _run_nav_bake() -> void:
	for i in 30:
		await get_tree().physics_frame
	var nav := _map.nav() if _map != null else null
	if nav == null or _map.nav_path.is_empty():
		push_error("[NavGrid] --nav-bake: the map has no nav_path")
		get_tree().quit(1)
		return
	var walkable: int = await nav.bake()
	get_tree().quit(0 if walkable > 0 else 1)

func _run_automated_screenshot() -> void:
	print("Auto-capture mode active: capturing diorama frame after scene settle...")
	var user_args = OS.get_cmdline_user_args()
	var preset := CameraPresets.find(user_args)
	var cam = find_child("ThirdPersonCamera", true, false)
	if cam and not preset.is_empty():
		CameraPresets.apply(cam, preset)

	for i in range(35):
		await get_tree().process_frame
	
	if "--preview-test" in user_args:
		GameManager.select_plant("lotus_shooter")
		var pm = find_child("PlacementManager", true, false)
		if pm:
			pm.set_process(false)
			pm.current_snapped_pos = Vector3(0.0, 0.08, 6.0)
			pm.ghost_root.position = pm.current_snapped_pos
			pm.ghost_root.visible = true
			pm._update_range_indicator(pm.p1, "lotus_shooter")
		for i in range(5):
			await get_tree().process_frame

	var hud = find_child("HUD", true, false)
	if hud and not ("--keep-hud" in user_args) and not ("--preview-test" in user_args):
		hud.visible = false
	await get_tree().process_frame
	
	if "--no-lod" in user_args:
		get_viewport().mesh_lod_threshold = 0.0
		for _i in range(5):
			await get_tree().process_frame
	var primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var fps = Engine.get_frames_per_second()
	var video_mem = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var texture_mem = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	var process_ms = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("[Telemetry] FPS: %d | Draw Calls: %d | Primitives: %d | Video Mem: %.2f MB | Texture Mem: %.2f MB | Process Time: %.2f ms" % [fps, draw_calls, primitives, video_mem, texture_mem, process_ms])
	
	var img = get_viewport().get_texture().get_image()
	if img:
		# Screenshots land under tools/ (covered by tools/.gdignore) so Godot
		# never imports them as textures and no stray *.png.import files appear.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/.screenshots"))
		# Each camera preset saves under its own file (CameraPresets.PRESETS "shot").
		var shot: String = "screenshot_plant_preview.png" if "--preview-test" in user_args else str(preset.get("shot", CameraPresets.DEFAULT_SHOT))
		if "--night-test" in user_args:
			shot = shot.replace(".png", "_night.png")
		elif "--day-test" in user_args:
			shot = shot.replace(".png", "_day.png")
		if "--no-lod" in user_args:
			shot = shot.replace(".png", "_nolod.png")
		if "--touch" in user_args:
			shot = shot.replace(".png", "_touch.png")
		var path = "res://tools/.screenshots/" + shot
		img.save_png(path)
		print("✓ Captured beautiful cozy diorama screenshot: ", path)
	get_tree().quit()



func _find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var res = _find_mesh(child)
		if res:
			return res
	return null

