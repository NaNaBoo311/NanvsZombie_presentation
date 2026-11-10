extends RefCounted

# --title-test: boots the title screen (the only test flag that does not skip
# it), checks the menu the player actually sees, opens and closes the LAN panel,
# then presses the primary button and waits for the atlas with the fade clear.
# The title is an all-3D stage: a home island on the leyline and a chain of islands
# built from the world data. This test asserts the island, its vignette and the
# effects (leyline, spirits, seed shots) exist, that the chain has a lantern for every
# world in LevelDB, and guards the stage's
# budget rules (no SubViewport, one shadow light, no spot or omni lights) before
# exercising the menu. Prints "[TitleTest] PASS" or each failure, then quits
# 0 / 1. Loaded only by GameFlow.boot() under the flag.

const TIMEOUT_FRAMES := 900

# Nothing else references this RefCounted once run() awaits.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree


func run() -> void:
	_alive = self
	_tree = Engine.get_main_loop() as SceneTree
	var title := await _wait_scene(GameFlow.TITLE_SCENE)
	if title == null:
		return _finish()
	_check_stage(title)
	var camera := title.get_node_or_null("Camera3D") as Camera3D
	if camera == null or not camera.current:
		_failures.append("title camera is missing or not current")
	if title.get_node_or_null("UI/TitleBlock/Wordmark") == null:
		_failures.append("wordmark is missing")
	if title.get_node_or_null("UI/TitleBlock/Subtitle") == null:
		_failures.append("subtitle is missing")
	var menu := title.get_node_or_null("UI/Menu") as VBoxContainer
	if menu == null:
		_failures.append("menu is missing")
		return _finish()
	var primary := menu.get_node_or_null("PrimaryButton") as Button
	if primary == null:
		_failures.append("primary button is missing")
	elif primary.text != tr("Continue") and primary.text != tr("New Game"):
		_failures.append("primary button says \"%s\", not Continue or New Game" % primary.text)
	var lan_button := menu.get_node_or_null("LanButton") as Button
	if lan_button == null:
		_failures.append("LAN button is missing")
	if not GameManager.is_touch_ui() and menu.get_node_or_null("QuitButton") == null:
		_failures.append("desktop Quit button is missing")

	var settings_button := menu.get_node_or_null("SettingsButton") as Button
	if settings_button == null:
		_failures.append("Settings button is missing")
	else:
		settings_button.pressed.emit()
		await _tree.process_frame
		var settings := title.get_node_or_null("UI/SettingsPanel") as Control
		if settings == null or not settings.visible:
			_failures.append("Settings did not open the panel")
		else:
			settings.close()

	if lan_button != null:
		lan_button.pressed.emit()
		await _tree.process_frame
		var panel := title.get_node_or_null("UI/LanPanel") as Control
		if panel == null or not panel.visible:
			_failures.append("LAN Co-op did not open the panel")
		else:
			panel.close()
			await _tree.process_frame
			if panel.visible:
				_failures.append("LAN panel did not close")

	if primary != null:
		primary.pressed.emit()
		await _wait_scene(GameFlow.ATLAS_SCENE)
	_finish()


func _check_stage(title: Node) -> void:
	var home := title.get_node_or_null("Worlds/Home")
	if home == null:
		_failures.append("home island is missing")
		return
	for child in ["Shard", "Pearl", "Vignette"]:
		if home.get_node_or_null(str(child)) == null:
			_failures.append("home island is missing %s" % child)
	if not (home.get_node_or_null("Landmarks") is MeshInstance3D):
		_failures.append("the Pearl was not baked to one mesh")
	for group in ["Plants", "Enemies"]:
		var units := home.get_node_or_null("Vignette/%s" % group)
		if units == null or units.get_child_count() == 0:
			_failures.append("vignette has no %s" % group.to_lower())
	if not (home.get_node_or_null("Vignette/Baked") is MeshInstance3D):
		_failures.append("vignette was not baked to one mesh")
	var isles := title.get_node_or_null("Isles") as MultiMeshInstance3D
	var beacons := title.get_node_or_null("Beacons") as MultiMeshInstance3D
	var world_count: int = LevelDB.get_worlds().size()
	if isles == null or isles.multimesh.instance_count < world_count:
		_failures.append("the island chain has fewer islands than the %d worlds" % world_count)
	if beacons == null or beacons.multimesh.instance_count != world_count:
		_failures.append("the island chain needs one lantern per world (%d)" % world_count)
	if not (title.get_node_or_null("Leyline") is MeshInstance3D):
		_failures.append("leyline is missing")
	for path in ["Spirits", "Worlds/Home/Vignette/Shots"]:
		var mmi := title.get_node_or_null(path) as MultiMeshInstance3D
		if mmi == null or mmi.multimesh.instance_count == 0:
			_failures.append("%s is missing or empty" % path)
	if not title.find_children("*", "SubViewport", true, false).is_empty():
		_failures.append("title stage uses a SubViewport")
	var shadow_lights := 0
	for node in title.find_children("*", "Light3D", true, false):
		if node is OmniLight3D or node is SpotLight3D:
			_failures.append("title stage has a spot/omni light: %s" % node.name)
		elif (node as Light3D).shadow_enabled:
			shadow_lights += 1
	if shadow_lights != 1:
		_failures.append("title stage has %d shadow lights, expected 1" % shadow_lights)


func _finish() -> void:
	if _failures.is_empty():
		print("[TitleTest] PASS")
	else:
		for failure in _failures:
			print("[TitleTest] FAIL: %s" % failure)
	_tree.quit(0 if _failures.is_empty() else 1)


## The scene at `path` once it is current, ready and GameFlow is idle (fade clear).
func _wait_scene(path: String) -> Node:
	for _i in TIMEOUT_FRAMES:
		await _tree.process_frame
		var scene := _tree.current_scene
		if scene and scene.scene_file_path == path and scene.is_node_ready() and not GameFlow.busy:
			if GameFlow.fade_alpha() > 0.01:
				_failures.append("fade not clear on %s" % path.get_file())
			return scene
	_failures.append("timed out waiting for %s" % path.get_file())
	return null
