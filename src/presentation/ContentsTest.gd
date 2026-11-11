extends RefCounted

# --contents-test: boots the contents page directly and checks the talk's map:
# six numbered section rows in slide order, live rows derived from their deck
# scene path, the disabled rows
# dimmed and unfocusable, no Account/hint/footer, Back to the cover, Start
# reopening the page, and section 01 opening Concept & Vision.
#
# Prints "[ContentsTest] PASS" or each failure, then quits 0 / 1. Loaded only by
# GameFlow.boot() under the flag.

const TIMEOUT_FRAMES := 900

# Nothing else references this RefCounted once run() awaits.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree


func run() -> void:
	_alive = self
	_tree = Engine.get_main_loop() as SceneTree
	var contents := await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		return _finish()
	_check_page(contents)

	var back := contents.get_node_or_null("Header/BackButton") as Button
	if back == null:
		_failures.append("contents page has no back button")
		return _finish()
	back.pressed.emit()
	var title := await _wait_scene(GameFlow.TITLE_SCENE)
	if title == null:
		return _finish()
	var cover := title.get_node_or_null("UI/Cover") as Control
	var start := cover.get_node_or_null("Actions/PlayButton") as Button if cover != null else null
	if start == null:
		_failures.append("cover has no Start action")
		return _finish()
	if start.text != tr("Start"):
		_failures.append("cover action says \"%s\"" % start.text)
	start.pressed.emit()
	contents = await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		return _finish()

	var section := contents.get_node_or_null("Main/Sections/Section01") as Button
	if section == null:
		_failures.append("contents page has no section 01 row")
		return _finish()
	section.pressed.emit()
	var concept := await _wait_scene(GameFlow.CONCEPT_SCENE)
	if concept == null:
		return _finish()
	var screen := concept.get_node_or_null("UI/ConceptScreen")
	if screen == null:
		_failures.append("section 01 did not build its screen")
	_finish()


func _check_page(contents: Node) -> void:
	var title := contents.get_node_or_null("Main/Title") as Label
	if title == null or title.text != tr(PresentationDeck.CONTENTS_TITLE):
		_failures.append("contents page has no title")
	for path in ["Main/Hint", "Header/AccountButton", "Header/Kicker", "Main/Footer"]:
		if contents.get_node_or_null(path) != null:
			_failures.append("contents page still carries %s" % path)
	if contents.get_node_or_null("AccountsPanel") != null:
		_failures.append("contents page still builds the Accounts panel")
	if contents.get_node_or_null("Main/Sections/Section01/Blurb") != null:
		_failures.append("section rows still carry a description")
	var sections := contents.get_node_or_null("Main/Sections")
	if sections == null:
		_failures.append("contents page has no section list")
		return
	if sections.get_child_count() != PresentationDeck.SECTIONS.size():
		_failures.append("contents lists %d of %d sections" % [
			sections.get_child_count(), PresentationDeck.SECTIONS.size()])
	if PresentationDeck.SECTIONS.size() != 6:
		_failures.append("contents deck has %d sections, expected 6" % PresentationDeck.SECTIONS.size())
	for i in PresentationDeck.SECTIONS.size():
		var spec: Dictionary = PresentationDeck.SECTIONS[i]
		var row := sections.get_node_or_null("Section%s" % str(spec["number"])) as Button
		if row == null:
			_failures.append("contents is missing section %s" % spec["number"])
			continue
		var live := not str(spec.get("scene", "")).is_empty()
		if row.disabled == live:
			_failures.append("section %s is %s" % [spec["number"],
				"disabled" if live else "live"])
		if live and row.focus_mode == Control.FOCUS_NONE:
			_failures.append("section %s cannot take focus" % spec["number"])
		if not live and row.focus_mode != Control.FOCUS_NONE:
			_failures.append("disabled section %s can still take focus" % spec["number"])
		var number := row.get_node_or_null("Number") as Label
		if number == null or number.text != str(spec["number"]):
			_failures.append("section %s has the wrong number label" % spec["number"])
		var row_title := row.get_node_or_null("Title") as Label
		if row_title == null or row_title.text != tr(str(spec["title"])):
			_failures.append("section %s has the wrong title" % spec["number"])
		for absent in ["Blurb", "State"]:
			if row.get_node_or_null(absent) != null:
				_failures.append("section %s still carries a %s" % [spec["number"], absent])


func _finish() -> void:
	if _failures.is_empty():
		print("[ContentsTest] PASS")
	else:
		for failure in _failures:
			print("[ContentsTest] FAIL: %s" % failure)
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
