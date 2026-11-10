extends RefCounted

# --map-switch-test: proves the battle shell has no park left in it and that
# switching maps leaks nothing. Visits landmark_81 -> test_flat -> landmark_81 ->
# test_flat -> landmark_81 through DioramaWorld.switch_map(); on every visit it
# checks the map took over (one map in the tree and in the "BattleMap" group,
# pearl, camera bounds, empty Plants/Enemies), that placement works on the new
# lawn (ground raycast hit, a lawn tile valid, a point off the lawn invalid),
# then spawns a Lotus and a Hungry Ghost. Node/object counts on the fresh
# landmark_81 visits 2 and 3 must match (no growth per round trip). Finally a
# level whose "map" names test_flat must switch through level_selected and
# survive an R-restart reload. Prints "[MapSwitchTest] PASS" or each failure,
# then quits 0 / 1. Loaded only by DioramaWorld._ready() under the flag.

const SETTLE_FRAMES := 20
const LOTUS := "res://src/entities/plants/lotus_shooter/LotusShooter.tscn"
const GHOST := "res://src/entities/enemies/hungry_ghost/HungryGhost.tscn"

# The R-restart step reloads the shell, whose _ready would start a second run.
static var _started := false
# Nothing else references this RefCounted once run() awaits; without this the
# instance is freed and the coroutine silently never resumes.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree


func run(shell: Node) -> void:
	if _started:
		return
	_started = true
	_alive = self
	_tree = shell.get_tree()
	await _frames(SETTLE_FRAMES)
	var counts: Array[Dictionary] = []
	for map_id in ["landmark_81", "test_flat", "landmark_81", "test_flat", "landmark_81"]:
		await shell.switch_map(map_id)
		await _frames(SETTLE_FRAMES)
		if map_id == "landmark_81":
			counts.append(_counts())
		await _check_visit(shell, map_id)
	print("[MapSwitchTest] fresh landmark_81 visits: %s" % str(counts))
	for key in counts[1]:
		if counts[2][key] != counts[1][key]:
			_failures.append("%s grew between round trips: %d -> %d" % [key, counts[1][key], counts[2][key]])
	await _check_level_switch_and_restart()

	if _failures.is_empty():
		print("[MapSwitchTest] PASS")
	else:
		for f in _failures:
			print("[MapSwitchTest] FAIL: %s" % f)
	_tree.quit(0 if _failures.is_empty() else 1)


func _check_visit(shell: Node, map_id: String) -> void:
	var map: MapDefinition = shell.current_map()
	var tag := "[%s]" % map_id
	if map == null or map.map_id != map_id:
		_failures.append("%s not the current map" % tag)
		return
	if shell.get_node("MapSlot").get_child_count() != 1 or _tree.get_nodes_in_group(MapDefinition.GROUP).size() != 1:
		_failures.append("%s more than one map in the tree" % tag)
	if not shell.get_node("SacredDragonPearl").global_position.is_equal_approx(map.pearl_position):
		_failures.append("%s pearl not on pearl_position" % tag)
	if shell.get_node("ThirdPersonCamera").pan_bounds != map.camera_bounds:
		_failures.append("%s camera bounds not from the map" % tag)
	if shell.get_node("Plants").get_child_count() + shell.get_node("Enemies").get_child_count() != 0:
		_failures.append("%s Plants/Enemies not cleared" % tag)

	var pm = shell.get_node("PlacementManager")
	if pm.valid_grid_coords.is_empty():
		_failures.append("%s no lawn tiles" % tag)
		return
	var coord: Vector2i = pm.valid_grid_coords[int(pm.valid_grid_coords.size() / 2.0)]
	var lawn_pos := Vector3(coord.x * pm.tile_size, map.ground_y, coord.y * pm.tile_size)
	var ray := PhysicsRayQueryParameters3D.create(lawn_pos + Vector3.UP * 10.0, lawn_pos + Vector3.DOWN * 10.0, 1)
	if shell.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		_failures.append("%s ground raycast missed the lawn at %s" % [tag, lawn_pos])
	pm.selected_plant_type = "lotus_shooter"
	if not pm._check_placement_validity(pm.p1, lawn_pos, coord):
		_failures.append("%s lawn tile %s rejected" % [tag, coord])
	var rect: Rect2 = map.lawn_rect("")
	var off := Vector3(rect.end.x + 6.0, map.ground_y, rect.position.y - 6.0)
	if pm._check_placement_validity(pm.p1, off, Vector2i(int(off.x / pm.tile_size), int(off.z / pm.tile_size))):
		_failures.append("%s point off the lawn accepted" % tag)
	pm.selected_plant_type = ""

	var lotus := (load(LOTUS) as PackedScene).instantiate() as Node3D
	shell.get_node("Plants").add_child(lotus)
	lotus.global_position = lawn_pos + Vector3.UP * 0.3
	var ghost := (load(GHOST) as PackedScene).instantiate() as Node3D
	shell.get_node("Enemies").add_child(ghost)
	ghost.global_position = shell.get_node("EnemySpawner")._sample_forest_pos()
	await _frames(30)
	if not is_instance_valid(lotus) or not is_instance_valid(ghost):
		_failures.append("%s spawned plant/enemy did not survive 30 frames" % tag)


## A level whose own "map" is test_flat switches via level_selected, and an
## R-restart comes back on that map (the level dict is patched in memory only).
func _check_level_switch_and_restart() -> void:
	var level: Dictionary = LevelDB.get_level("hcmc_01")
	level["map"] = "test_flat"
	GameManager.start_level("hcmc", "hcmc_01")
	var shell: Node = _tree.current_scene
	for i in 120:
		await _tree.process_frame
		if shell.current_map() and shell.current_map().map_id == "test_flat":
			break
	if shell.current_map() == null or shell.current_map().map_id != "test_flat":
		_failures.append("level_selected did not switch to the level's map")
	_tree.reload_current_scene()
	await _frames(SETTLE_FRAMES)
	var reloaded: Node = _tree.current_scene
	if reloaded == shell or reloaded.current_map() == null or reloaded.current_map().map_id != "test_flat":
		_failures.append("R-restart did not come back on the level's map")
	level.erase("map")


func _counts() -> Dictionary:
	return {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


func _frames(n: int) -> void:
	for i in n:
		await _tree.physics_frame
