extends RefCounted

# --title-test: boots the presentation cover (the only test flag that does not
# skip it) and walks the talk's front door: the cover copy and the Account
# dialog, Start into the contents page, section 01 into Concept & Vision, the
# header Back arrow (the page reopens), the section's Enter the game hand-off to the
# playable atlas, and the atlas's icon-only return to the cover.
#
# It also guards the inherited 3D stage: the home island, its vignette and the
# effects exist, the chain has a lantern for every world in LevelDB, and the
# stage keeps its budget (no SubViewport, one shadow light, no spot or omni
# lights). Prints "[TitleTest] PASS" or each failure, then quits 0 / 1. Loaded
# only by GameFlow.boot() under the flag.

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

	if not GameManager.is_touch_ui() \
			and cover.get_node_or_null("Actions/Links/QuitButton") == null:
		_failures.append("desktop Quit button is missing")

	var play := cover.get_node_or_null("Actions/PlayButton") as Button
	if play == null:
		return _finish()
	play.pressed.emit()
	var contents := await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		return _finish()
	_check_contents(contents)

	var section := contents.get_node_or_null("Main/Sections/Section01") as Button
	if section == null:
		_finish()
		return
	section.pressed.emit()
	var concept := await _wait_scene(GameFlow.CONCEPT_SCENE)
	if concept == null:
		return _finish()
	var screen := concept.get_node_or_null("UI/ConceptScreen") as ConceptScreen
	if screen == null:
		_failures.append("Concept & Vision did not build its screen")
		return _finish()
	var back := screen.get_node_or_null("Header/BackButton") as Button
	if back == null:
		_failures.append("concept screen has no Back button")
		return _finish()
	back.pressed.emit()
	contents = await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		return _finish()
	section = contents.get_node_or_null("Main/Sections/Section01") as Button
	if section == null:
		_failures.append("contents page cannot reopen section 01")
		return _finish()
	section.pressed.emit()
	concept = await _wait_scene(GameFlow.CONCEPT_SCENE)
	if concept == null:
		return _finish()
	screen = concept.get_node_or_null("UI/ConceptScreen") as ConceptScreen
	if screen == null:
		_failures.append("reopened section has no screen")
		return _finish()

	# The contents page no longer carries the playable build; section 01's final
	# action is the only hand-off to the atlas.
	screen.show_exhibit(3)
	await _tree.process_frame
	var enter := screen.get_node_or_null("Bottom/EnterGameButton") as Button
	if enter == null or not enter.visible or enter.text != tr("Enter the game"):
		_failures.append("section 01 does not offer Enter the game")
		return _finish()
	enter.pressed.emit()
	var atlas := await _wait_scene(GameFlow.ATLAS_SCENE)
	if atlas == null:
		return _finish()
	_check_atlas_return(atlas)
	var home := atlas.get_node_or_null("UI/TitleButton") as Button
	if home != null:
		home.pressed.emit()
		await _wait_scene(GameFlow.TITLE_SCENE)
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
			"TitleBlock/Subtitle", "Actions/PlayButton",
			"Actions/Links/AccountButton", "Footer/Lecturer", "Footer/Date"]:
		if cover.get_node_or_null(path) == null:
			_failures.append("cover is missing %s" % path)
	if cover.get_node_or_null("Credits") != null:
		_failures.append("cover still carries the old presented-by credits block")
	for path in ["TitleBlock/Tagline", "TitleBlock/Pitch", "Actions/Links/SettingsButton"]:
		if cover.get_node_or_null(path) != null:
			_failures.append("cover still carries %s" % path)
	var first := cover.get_node_or_null("TitleBlock/TitleFirst") as Label
	if first != null and first.text != tr(PresentationDeck.TITLE_FIRST):
		_failures.append("first title line says \"%s\"" % first.text)
	var second := cover.get_node_or_null("TitleBlock/TitleSecond") as Label
	if second != null and second.text != tr(PresentationDeck.TITLE_SECOND):
		_failures.append("second title line says \"%s\"" % second.text)
	var lecturer := cover.get_node_or_null("Footer/Lecturer") as Label
	if lecturer != null and lecturer.text != tr(PresentationDeck.LECTURER):
		_failures.append("lecturer says \"%s\"" % lecturer.text)
	var date := cover.get_node_or_null("Footer/Date") as Label
	if date != null and date.text != tr(PresentationDeck.DATE):
		_failures.append("date says \"%s\"" % date.text)
	var play := cover.get_node_or_null("Actions/PlayButton") as Button
	if play == null:
		_failures.append("cover has no primary action")
	elif play.text != tr("Start"):
		_failures.append("cover primary action says \"%s\"" % play.text)
	_check_accounts(cover)


func _check_accounts(cover: Control) -> void:
	var account := cover.get_node_or_null("Actions/Links/AccountButton") as Button
	if account == null:
		_failures.append("Account button is missing")
		return
	account.pressed.emit()
	var panel := cover.get_node_or_null("AccountsPanel")
	if panel == null or not (panel as Control).visible:
		_failures.append("Account did not open the presenter dialog")
		return
	var rows := panel.get_node_or_null("Sheet/Body/Presenters") as VBoxContainer
	if rows == null:
		_failures.append("presenter dialog has no presenter list")
	elif rows.get_child_count() != PresentationDeck.PRESENTERS.size():
		_failures.append("presenter dialog lists %d of %d names" % [
			rows.get_child_count(), PresentationDeck.PRESENTERS.size()])
	else:
		for i in rows.get_child_count():
			var row := rows.get_child(i) as HBoxContainer
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
	panel.call("close")


func _check_contents(contents: Node) -> void:
	var title := contents.get_node_or_null("Main/Title") as Label
	if title == null or title.text != tr(PresentationDeck.CONTENTS_TITLE):
		_failures.append("contents page has no title")
	if contents.get_node_or_null("Main/Hint") != null:
		_failures.append("contents page still carries the hint")
	if contents.get_node_or_null("Header/AccountButton") != null:
		_failures.append("contents page still carries the Account button")
	if contents.get_node_or_null("Header/Kicker") != null:
		_failures.append("contents page still carries the kicker")
	if contents.get_node_or_null("Footer") != null:
		_failures.append("contents page still carries its footer")
	var sections := contents.get_node_or_null("Main/Sections")
	if sections == null:
		_failures.append("contents page has no section list")
		return
	if sections.get_child_count() != PresentationDeck.SECTIONS.size():
		_failures.append("contents lists %d of %d sections" % [
			sections.get_child_count(), PresentationDeck.SECTIONS.size()])
	for i in PresentationDeck.SECTIONS.size():
		var spec: Dictionary = PresentationDeck.SECTIONS[i]
		var row := sections.get_node_or_null("Section%s" % str(spec["number"])) as Button
		if row == null:
			_failures.append("contents is missing section %s" % spec["number"])
			continue
		var live := i == 0
		if row.disabled == live:
			_failures.append("section %s is %s" % [spec["number"],
				"disabled" if live else "live"])
		var row_title := row.get_node_or_null("Title") as Label
		if row_title == null or row_title.text != tr(str(spec["title"])):
			_failures.append("section %s has the wrong title" % spec["number"])
		if row.get_node_or_null("Blurb") != null:
			_failures.append("section %s still carries a description" % spec["number"])
		if row.get_node_or_null("State") != null:
			_failures.append("section %s still carries a state label" % spec["number"])


func _check_atlas_return(atlas: Node) -> void:
	var home := atlas.get_node_or_null("UI/TitleButton") as Button
	if home == null:
		_failures.append("atlas has no return-to-title button")
		return
	if not home.text.is_empty():
		_failures.append("atlas return-to-title button is not icon-only")
	if home.get_node_or_null("Glyph") == null:
		_failures.append("atlas return-to-title button has no icon")
	if home.tooltip_text != tr("Back to title"):
		_failures.append("atlas return-to-title button has the wrong tooltip")


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
