extends RefCounted

# --concept-test: boots section 01 and checks the four exhibits: the pitch and its
# at-a-glance grid, the world atlas and its camera stay, the reference ledger, the
# pillars and the final Enter the game hand-off. The header Back arrow reopens the
# contents page, section 01 returns to a fresh concept screen, and the atlas's home
# button returns to the cover.
#
# Prints "[ConceptTest] PASS" or each failure, then quits 0 / 1. Loaded only by
# GameFlow.boot() under the flag.

const TIMEOUT_FRAMES := 1200

# Nothing else references this RefCounted once run() awaits.
static var _alive: RefCounted = null

var _failures: Array[String] = []
var _tree: SceneTree


func run() -> void:
	_alive = self
	_tree = Engine.get_main_loop() as SceneTree
	var concept := await _wait_scene(GameFlow.CONCEPT_SCENE)
	if concept == null:
		return _finish()
	var screen := concept.get_node_or_null("UI/ConceptScreen") as ConceptScreen
	if screen == null:
		_failures.append("Concept & Vision did not build its screen")
		return _finish()
	_check_chrome(screen)
	_check_pitch(screen)
	await _check_world(concept, screen)
	_check_references(screen)
	_check_pillars(screen)

	var back := screen.get_node_or_null("Header/BackButton") as Button
	if back == null:
		_failures.append("concept screen has no Back button")
		return _finish()
	back.pressed.emit()
	var contents := await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		return _finish()
	var section := contents.get_node_or_null("Main/Sections/Section01") as Button
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
	screen.show_exhibit(3)
	await _tree.process_frame
	var enter := screen.get_node_or_null("Bottom/EnterGameButton") as Button
	if enter == null:
		_failures.append("concept screen has no final action")
		return _finish()
	if not enter.visible:
		_failures.append("Enter the game is not visible on the last exhibit")
	if enter.text != tr("Enter the game"):
		_failures.append("last exhibit's action says \"%s\"" % enter.text)
	enter.pressed.emit()
	var atlas := await _wait_scene(GameFlow.ATLAS_SCENE)
	if atlas == null:
		return _finish()
	var home := atlas.get_node_or_null("UI/TitleButton") as Button
	if home == null:
		_failures.append("atlas has no return-to-title button")
	else:
		home.pressed.emit()
		await _wait_scene(GameFlow.TITLE_SCENE)
	_finish()


func _check_chrome(screen: ConceptScreen) -> void:
	for path in ["Header/BackButton", "Header/Kicker", "Header/SectionTitle",
			"Bottom/Tabs", "Bottom/EnterGameButton"]:
		if screen.get_node_or_null(path) == null:
			_failures.append("concept screen is missing %s" % path)
	for path in ["Bottom/ContentsButton", "Bottom/PrevButton", "Bottom/NextButton"]:
		if screen.get_node_or_null(path) != null:
			_failures.append("concept screen still carries %s" % path)
	var enter := screen.get_node_or_null("Bottom/EnterGameButton") as Button
	if enter != null and enter.visible:
		_failures.append("Enter the game is visible before the last exhibit")
	for label in screen.find_children("*", "Label", true, false):
		if (label as Label).text.begins_with("EXHIBIT "):
			_failures.append("concept screen still shows an exhibit kicker: %s" % label.text)
			break
	var tabs := screen.get_node_or_null("Bottom/Tabs")
	if tabs != null and tabs.get_child_count() != ConceptScreen.EXHIBITS.size():
		_failures.append("concept tabs list %d of %d exhibits" % [
			tabs.get_child_count(), ConceptScreen.EXHIBITS.size()])
	if screen.get_node_or_null("Main").get_child_count() != ConceptScreen.EXHIBITS.size():
		_failures.append("concept screen does not build all four exhibits")
	if screen.get_node_or_null("Main/Circle") != null:
		_failures.append("section 01 still contains the gameplay circle exhibit")
	if screen.find_child("PerfLabel", true, false) != null:
		_failures.append("concept screen still shows the live performance badge")


func _check_pitch(screen: ConceptScreen) -> void:
	var panel := screen.get_node_or_null("Main/Pitch") as Control
	if panel == null or not panel.visible:
		_failures.append("the pitch exhibit is not open first")
		return
	var glance := panel.get_node_or_null("Copy/Glance")
	if glance == null or glance.get_child_count() != PresentationDeck.CONCEPT_GLANCE.size():
		_failures.append("the pitch glance grid does not list every item")


func _check_world(concept: Node, screen: ConceptScreen) -> void:
	screen.show_exhibit(1)
	await _tree.create_timer(1.3).timeout
	var camera := concept.get_node_or_null("Camera3D") as Camera3D
	if camera == null:
		_failures.append("concept scene has no camera")
	else:
		if camera.global_position.x < 200.0:
			_failures.append("camera did not travel to the world atlas")
	var atlas := concept.get_node_or_null("WorldAtlas") as ConceptAtlas
	if atlas == null:
		_failures.append("the world atlas is missing")
		return
	if atlas.get_node_or_null("Pivot/Atlas") == null:
		_failures.append("the atlas model is missing")
	if atlas.province_index(0) < 0:
		_failures.append("the first world has no atlas province")
	if atlas.current != 0:
		_failures.append("the atlas does not open on the first world")
	if atlas.focus_id != atlas.province_index(0):
		_failures.append("the atlas does not focus the first world's province")
	var beam := atlas.get_node_or_null("Pivot/FocusBeam") as Node3D
	if beam == null or not beam.visible:
		_failures.append("the atlas does not mark the picked province")
	var first_beam: Vector3 = beam.position if beam != null else Vector3.ZERO
	var tabs := screen.get_node_or_null("Main/World/Copy/WorldTabs")
	if tabs == null:
		_failures.append("the world exhibit has no world tabs")
		return
	if tabs.get_child_count() != PresentationDeck.WORLDS.size():
		_failures.append("the world exhibit lists %d of %d worlds" % [
			tabs.get_child_count(), PresentationDeck.WORLDS.size()])
	var third := tabs.get_child(2) as Button
	if third == null:
		return
	third.pressed.emit()
	await _tree.create_timer(0.9).timeout
	if atlas.current != 2:
		_failures.append("picking a world does not switch the atlas")
	if atlas.focus_id != atlas.province_index(2):
		_failures.append("the atlas does not highlight the picked world")
	if beam != null and beam.position.is_equal_approx(first_beam):
		_failures.append("the focus beam stays on the first province")
	var place := screen.get_node_or_null("Main/World/Copy") as VBoxContainer
	if place != null:
		var found := _find_text(place, PresentationDeck.WORLDS[2]["place"])
		if found == null:
			_failures.append("the world exhibit does not describe the picked world")
	screen.show_exhibit(0)
	await _tree.create_timer(1.2).timeout
	if camera != null and camera.global_position.x > 100.0:
		_failures.append("camera did not return to the title stage")


func _check_references(screen: ConceptScreen) -> void:
	screen.show_exhibit(2)
	var panel := screen.get_node_or_null("Main/References") as Control
	if panel == null or not panel.visible:
		_failures.append("the reference exhibit did not open")
		return
	var ledger := panel.get_node_or_null("Visual/Ledger")
	if ledger == null:
		_failures.append("the reference ledger is missing")
	elif ledger.get_child_count() != PresentationDeck.REFERENCES.size() + 2:
		_failures.append("the reference ledger has %d rows" % ledger.get_child_count())


func _check_pillars(screen: ConceptScreen) -> void:
	screen.show_exhibit(3)
	var panel := screen.get_node_or_null("Main/Pillars") as Control
	if panel == null or not panel.visible:
		_failures.append("the pillar exhibit did not open")
		return
	var cards := panel.get_node_or_null("Visual/PillarStack/Pillars")
	if cards == null or cards.get_child_count() != PresentationDeck.PILLARS.size():
		_failures.append("the pillar exhibit does not build every pillar")
	var enter := screen.get_node_or_null("Bottom/EnterGameButton") as Button
	if enter == null or not enter.visible or enter.text != tr("Enter the game"):
		_failures.append("the last exhibit does not offer Enter the game")


## Walks a subtree for a Label whose text equals `text`; returns it or null.
func _find_text(root: Node, text: Variant) -> Label:
	for node in root.find_children("*", "Label", true, false):
		if (node as Label).text == tr(str(text)):
			return node as Label
	return null


func _finish() -> void:
	if _failures.is_empty():
		print("[ConceptTest] PASS")
	else:
		for failure in _failures:
			print("[ConceptTest] FAIL: %s" % failure)
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
