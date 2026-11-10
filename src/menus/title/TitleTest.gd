extends RefCounted

# --title-test: boots the presentation cover (the only test flag that does not skip
# it), checks the cover copy, credits and actions, opens and closes Settings, then
# presses Play and waits for the atlas with the fade clear.
#
# The cover sits on the game's all-3D title stage: a home island on the leyline and
# a chain of islands built from the world data. This test asserts the island, its
# vignette and the effects (leyline, spirits, seed shots) exist, that the chain has
# a lantern for every world in LevelDB, and guards the stage's budget rules (no
# SubViewport, one shadow light, no spot or omni lights) before exercising the cover.
# Prints "[TitleTest] PASS" or each failure, then quits 0 / 1. Loaded only by
# GameFlow.boot() under the flag.

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
	_check_cover(title)
	var cover := title.get_node_or_null("UI/Cover") as Control
	if cover == null:
		return _finish()

	var settings_button := cover.get_node_or_null("Actions/Links/SettingsButton") as Button
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
			await _tree.process_frame
			if settings.visible:
				_failures.append("Settings panel did not close")

	if not GameManager.is_touch_ui() \
			and cover.get_node_or_null("Actions/Links/QuitButton") == null:
		_failures.append("desktop Quit button is missing")

	var play := cover.get_node_or_null("Actions/PlayButton") as Button
	if play != null:
		play.pressed.emit()
		await _wait_scene(GameFlow.ATLAS_SCENE)
	_finish()


func _check_cover(title: Node) -> void:
	var cover := title.get_node_or_null("UI/Cover")
	if cover == null:
		_failures.append("presentation cover is missing")
		return
	if not (cover.get_node_or_null("Lockup/Logo/Mark") is TextureRect):
		_failures.append("university mark is missing")
	for path in ["Lockup/Eyebrow", "Lockup/University", "Lockup/Faculty",
			"TitleBlock/Course", "TitleBlock/TitleFirst", "TitleBlock/TitleSecond",
			"TitleBlock/Subtitle", "TitleBlock/Tagline",
			"Credits/Header", "Credits/Lecturer", "Credits/Date"]:
		if cover.get_node_or_null(path) == null:
			_failures.append("cover is missing %s" % path)
	var first := cover.get_node_or_null("TitleBlock/TitleFirst") as Label
	if first != null and first.text != tr(PresentationDeck.TITLE_FIRST):
		_failures.append("first title line says \"%s\"" % first.text)
	var second := cover.get_node_or_null("TitleBlock/TitleSecond") as Label
	if second != null and second.text != tr(PresentationDeck.TITLE_SECOND):
		_failures.append("second title line says \"%s\"" % second.text)
	var tagline := cover.get_node_or_null("TitleBlock/Tagline") as Label
	if tagline != null and tagline.text != tr(PresentationDeck.TAGLINE):
		_failures.append("tagline says \"%s\"" % tagline.text)
	var lecturer := cover.get_node_or_null("Credits/Lecturer") as Label
	if lecturer != null and lecturer.text != tr(PresentationDeck.LECTURER):
		_failures.append("lecturer says \"%s\"" % lecturer.text)

	var presenters := cover.get_node_or_null("Credits/Presenters") as VBoxContainer
	if presenters == null:
		_failures.append("presenter credits are missing")
	elif presenters.get_child_count() != PresentationDeck.PRESENTERS.size():
		_failures.append("presenter credits list %d of %d names" % [
			presenters.get_child_count(), PresentationDeck.PRESENTERS.size()])
	else:
		for i in presenters.get_child_count():
			var row := presenters.get_child(i) as HBoxContainer
			var spec: Dictionary = PresentationDeck.PRESENTERS[i]
			if row == null or row.get_child_count() != 2:
				_failures.append("presenter row %d is malformed" % (i + 1))
				continue
			var name_label := row.get_child(0) as Label
			var id_label := row.get_child(1) as Label
			if name_label == null or name_label.text != tr(str(spec["name"])):
				_failures.append("presenter %d has the wrong name" % (i + 1))
			if id_label == null or id_label.text != str(spec["id"]):
				_failures.append("presenter %d has the wrong student id" % (i + 1))

	var play := cover.get_node_or_null("Actions/PlayButton") as Button
	if play == null:
		_failures.append("Play button is missing")
	elif play.text != tr("Play the game"):
		_failures.append("Play button says \"%s\"" % play.text)


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
