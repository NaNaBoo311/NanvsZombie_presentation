extends RefCounted

# --flow-test: drives the real Boot -> atlas -> province -> battle -> result ->
# province -> atlas loop through GameFlow, on a throwaway save (never
# user://save.cfg). Checks at each step that only one screen exists (no battle
# map in the menu, no atlas in the battle), the fade is clear, the pause panel
# pauses and resumes, a forced win shows the result with Next Level, "Map"
# returns zoomed into HCMC with hcmc_02 open and popped, and Back reaches the
# atlas. Then four more play -> Map round trips: a node / object / resource count
# on the returned province screen that grows on BOTH of the last two trips is a
# leak (a leak grows every trip; a one-off spike from a late free or load does
# not). Prints "[FlowTest] PASS" or each failure, then quits 0 / 1. Loaded only
# by GameFlow.boot() under the flag.

const TEST_SAVE := "user://save_flow_test.cfg"
const TIMEOUT_FRAMES := 900

# Nothing else references this RefCounted once run() awaits.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree


func run() -> void:
	_alive = self
	_tree = GameFlow.get_tree()
	Progress._save_path = TEST_SAVE
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	Progress._load()

	var menu: Node = await _wait_scene(GameFlow.ATLAS_SCENE)
	if menu == null:
		return _finish()
	_expect_menu_only("boot")
	if Audio.current_track() != Audio.ATLAS_TRACK:
		_failures.append("atlas did not start its music (got %s)" % Audio.current_track())
	menu.open_province("hcmc")
	await menu.transition_finished
	EventBus.level_play_requested.emit("hcmc_01")

	var battle: Node = await _wait_scene(GameFlow.BATTLE_SCENE)
	if battle == null:
		return _finish()
	_expect_battle_only("battle")
	if GameManager.current_level_id != "hcmc_01" or not GameManager.level_active:
		_failures.append("battle is not running hcmc_01")
	if Audio.current_track() != &"hcmc_battle_theme":
		_failures.append("battle did not start its music (got %s)" % Audio.current_track())
	# Briefing: the level waits in prepare with no countdown and no enemies.
	var setup_ticks := 0
	var tick_conn := func(_s: int) -> void: setup_ticks += 1
	EventBus.setup_tick.connect(tick_conn)
	for i in 5:
		await _tree.process_frame
	# The fresh save has not read hcmc_01's intro: the Chronicle opens first.
	if GameManager.round_state != "story":
		_failures.append("first play did not open the story intro (got %s)" % GameManager.round_state)
	else:
		GameManager.finish_story()
		await _tree.process_frame
	if GameManager.round_state != "prepare":
		_failures.append("battle did not wait in prepare (got %s)" % GameManager.round_state)
	if setup_ticks != 0:
		_failures.append("setup_tick fired during prepare")
	if GameManager.alive_enemies != 0:
		_failures.append("enemies alive during prepare")
	var briefing: Node = battle.find_child("LoadoutBriefing", true, false)
	if briefing == null:
		_failures.append("no LoadoutBriefing in battle")
	else:
		if not briefing.visible:
			_failures.append("briefing not visible in prepare")
		# Pack rules: duplicates and unknown ids are refused.
		var first_id := str(GameManager.seed_loadout[0]) if not GameManager.seed_loadout.is_empty() else "lotus_shooter"
		if GameManager.try_pack_seed(first_id):
			_failures.append("packing a duplicate seed was not refused")
		if GameManager.try_pack_seed("__no_such_seed__"):
			_failures.append("packing an unknown seed was not refused")
		# Unpack rules: unknown ids refused; forced ids refused when the level forces any.
		if GameManager.try_unpack_seed("__no_such_seed__"):
			_failures.append("unpacking an unknown seed was not refused")
		var forced: Array = LevelDB.seed_rules("hcmc_01")["forced"]
		for fid in forced:
			if GameManager.try_unpack_seed(str(fid)):
				_failures.append("unpacking forced %s was not refused" % str(fid))
		# An empty loadout disables Start.
		var kept: Array = GameManager.seed_loadout.duplicate()
		GameManager.set_seed_loadout([])
		for i in 5:
			await _tree.process_frame
		if not briefing.get("_start_button").disabled:
			_failures.append("Start not disabled on empty loadout")
		GameManager.set_seed_loadout(kept)
		for i in 5:
			await _tree.process_frame
		# Confirm locks the bank in order and enters setup.
		var confirmed: Array = GameManager.seed_loadout.duplicate()
		GameManager.confirm_loadout(confirmed)
		if GameManager.round_state != "setup":
			_failures.append("confirm did not enter setup (got %s)" % GameManager.round_state)
		if GameManager.seed_loadout != confirmed:
			_failures.append("bank does not equal the confirmed ids in order")
		# Retry reopens the briefing prefilled with the loadout just used.
		var starts_before := Audio.music_starts
		GameFlow.retry()
		battle = await _wait_scene(GameFlow.BATTLE_SCENE)
		if battle == null:
			return _finish()
		for i in 5:
			await _tree.process_frame
		if Audio.music_starts != starts_before:
			_failures.append("retry restarted the battle track")
		if GameManager.round_state != "prepare":
			_failures.append("retry did not reopen prepare (got %s)" % GameManager.round_state)
		elif GameManager.seed_loadout != confirmed:
			_failures.append("retry did not prefill the loadout just used")
		else:
			GameManager.confirm_loadout(GameManager.seed_loadout.duplicate())
			for i in 5:
				await _tree.process_frame
		briefing = battle.find_child("LoadoutBriefing", true, false)
	EventBus.setup_tick.disconnect(tick_conn)

	var panel: Node = battle.find_child("BattlePanel", true, false)
	panel.open_pause()
	if not _tree.paused or not panel.visible:
		_failures.append("pause did not pause")
	panel.close_pause()
	if _tree.paused or panel.visible:
		_failures.append("resume did not unpause")

	# Forced win: the level's real completion path (GameManager -> Progress).
	GameManager._round_enabled = true
	GameManager.round_state = "wave"
	EventBus.level_completed.emit("hcmc", "hcmc_01")
	if GameManager.round_state != "won" or panel.mode != 1 or not panel.visible:
		_failures.append("win did not show the result panel")
	if not panel.get_node("Center/Panel/VBox/Buttons/Next").visible:
		_failures.append("Next Level missing after unlocking hcmc_02")
	if not Progress.is_level_completed("hcmc_01") or not Progress.is_level_unlocked("hcmc_02"):
		_failures.append("win did not record progress")

	GameFlow.back_to_province()
	menu = await _wait_scene(GameFlow.ATLAS_SCENE)
	if menu == null:
		return _finish()
	_expect_menu_only("back to map")
	if Audio.current_track() != Audio.ATLAS_TRACK:
		_failures.append("back to map did not restore atlas music (got %s)" % Audio.current_track())
	if menu.mode != 1 or menu.board == null or menu.provinces.ids[menu._open_index] != "hcmc":
		_failures.append("did not come back zoomed into HCMC")
	else:
		var board: ProvinceBoard = menu.board
		if board.node_states[1] != ProvinceBoard.NodeState.OPEN or board.next_index != 1:
			_failures.append("hcmc_02 is not the open next node")
		if board.node_states[0] != ProvinceBoard.NodeState.COMPLETED:
			_failures.append("hcmc_01 not shown completed")
	if Progress.last_world != "hcmc":
		_failures.append("last_world not saved")

	menu.close_province()
	await menu.transition_finished
	if menu.mode != 0:
		_failures.append("Back did not reach the atlas")
	await _check_round_trips(menu)
	_finish()


func _check_round_trips(menu: Node) -> void:
	var counts: Array[Dictionary] = []
	for trip in 4:
		menu.open_province("hcmc")
		await menu.transition_finished
		EventBus.level_play_requested.emit("hcmc_01")
		if await _wait_scene(GameFlow.BATTLE_SCENE) == null:
			return
		GameFlow.back_to_province()
		menu = await _wait_scene(GameFlow.ATLAS_SCENE)
		if menu == null:
			return
		for i in 30:
			await _tree.process_frame
		counts.append({
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		})
		menu.close_province()
		await menu.transition_finished
	print("[FlowTest] province screen after each round trip: %s" % str(counts))
	for key in counts[1]:
		if counts[2][key] > counts[1][key] and counts[3][key] > counts[2][key]:
			_failures.append("%s grew on every round trip: %d -> %d -> %d" % [key, counts[1][key], counts[2][key], counts[3][key]])


func _finish() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	if _failures.is_empty():
		print("[FlowTest] PASS")
	else:
		for f in _failures:
			print("[FlowTest] FAIL: %s" % f)
	_tree.quit(0 if _failures.is_empty() else 1)


## The scene at `path` once it is current, ready and GameFlow is idle (fade clear).
func _wait_scene(path: String) -> Node:
	for i in TIMEOUT_FRAMES:
		await _tree.process_frame
		var scene := _tree.current_scene
		if scene and scene.scene_file_path == path and scene.is_node_ready() and not GameFlow.busy:
			if GameFlow.fade_alpha() > 0.01:
				_failures.append("fade not clear on %s" % path.get_file())
			return scene
	_failures.append("timed out waiting for %s" % path.get_file())
	return null


func _expect_menu_only(step: String) -> void:
	if not _tree.get_nodes_in_group(MapDefinition.GROUP).is_empty():
		_failures.append("%s: a battle map exists in the menu" % step)


func _expect_battle_only(step: String) -> void:
	if _tree.get_nodes_in_group(MapDefinition.GROUP).size() != 1:
		_failures.append("%s: expected one battle map" % step)
	if _tree.root.find_child("AtlasMenu", true, false) != null:
		_failures.append("%s: the atlas menu still exists" % step)
