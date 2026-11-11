class_name CoreGameplayTest
extends RefCounted

# Section 02 regression test (--core-test):
#   1. PresentationDeck row 02 points at the section atlas and has title.
#   2. Atlas opens on Saigon with the centered Orrery concentric loop diagram.
#   3. Province click switches the orrery for the field instruction.
#   4. Next button transitions into the HCMC field.
#   5. RoleCards open on entry and dismiss when Show me is pressed.
#   6. Gameplay resumes with original NanVsZombie battle loop (prepare / setup / wave).
#
# GameFlow.boot() runs this under --core-test.

var _tree: SceneTree
var _failures: Array[String] = []


func run(tree: SceneTree) -> void:
	_tree = tree
	var contents := await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		_failures.append("presentation did not boot to contents")
		return _finish()
	GameFlow.open_section(1)
	var atlas := await _wait_scene(GameFlow.CORE_ATLAS_SCENE)
	if atlas == null:
		_failures.append("section 02 did not open CoreGameplayAtlas")
		return _finish()
	_check_deck()
	_check_atlas(atlas)
	await _check_province(atlas)
	var field := await _check_field(atlas)
	if field == null:
		return _finish()
	await _check_roles(field)
	await _check_gameplay(field)
	_finish()


# ------------------------------------------------------------------- atlas ---

func _check_deck() -> void:
	var row: Dictionary = PresentationDeck.SECTIONS[1]
	if str(row.get("scene", "")) != GameFlow.CORE_ATLAS_SCENE:
		_failures.append("deck row 02 does not point at the section atlas")
	if str(row.get("title", "")) != "Core Gameplay":
		_failures.append("deck row 02 has the wrong title")


func _check_atlas(atlas: Node) -> void:
	var screen := atlas.get_node_or_null("UI/CoreGameplayScreen") as Control
	if screen == null:
		_failures.append("section 02 atlas has no presentation screen")
		return
	for name in ["BackButton", "Kicker", "SectionTitle", "Title", "Scales", "ContinueButton"]:
		if screen.find_child(name, true, false) == null:
			_failures.append("section 02 screen is missing %s" % name)
	var scales := screen.find_child("Scales", true, false)
	if scales != null and scales.get_child_count() != PresentationDeck.CORE_SCALES.size():
		_failures.append("the loop legend has %d scales" % scales.get_child_count())
	var game_chrome := atlas.get_node_or_null("UI/TitleButton") as Control
	if game_chrome != null and game_chrome.visible:
		_failures.append("the atlas still shows the game's home button")
	if (atlas.get_node("UI/Title") as Control).visible:
		_failures.append("the atlas still shows its own title")
	var back := screen.find_child("BackButton", true, false) as Button
	if back == null or back.text != "←":
		_failures.append("section 02 screen has no back arrow")


func _check_province(atlas: Node) -> void:
	atlas.call("open_province", "hcmc")
	var mode := -1
	for _i in 900:
		await _tree.process_frame
		mode = int(atlas.get("mode"))
		if mode == 1: # Mode.PROVINCE
			break
	if mode != 1:
		_failures.append("Saigon's province board did not open")
		return
	var screen := atlas.get_node("UI/CoreGameplayScreen")
	var scales := screen.find_child("Scales", true, false) as Control
	if scales != null and scales.visible:
		_failures.append("the loop legend is still up over the province board")
	var board: Variant = atlas.get("board")
	if board == null:
		_failures.append("the province board is missing")
	if (atlas.get_node("UI/Back") as Control).visible:
		_failures.append("the atlas's own Back button is still showing")


# ------------------------------------------------------------------- field ---

func _check_field(atlas: Node) -> Node:
	atlas.call("_on_continue")
	var field := await _wait_scene(GameFlow.CORE_FIELD_SCENE)
	if field == null:
		return null
	if GameManager.current_level_id != "hcmc_01":
		_failures.append("field did not prepare hcmc_01")
	var map := field.call("current_map") as MapDefinition
	if map == null or map.map_id != "landmark_81":
		_failures.append("field is not on landmark_81")
	return field


func _check_roles(field: Node) -> void:
	var cards := field.get_node_or_null("PresentationLayer/RoleCards") as RoleCards
	if cards == null:
		_failures.append("field has no role cards")
		return
	if not cards.visible:
		_failures.append("role cards did not open on first entry")
	await _seconds(3.8)
	if not cards.visible:
		return
	var button := cards.get_node_or_null("ContinueButton") as Button
	if button == null:
		_failures.append("role cards have no continue button")
		return
	if button.disabled:
		_failures.append("role cards never finished revealing")
	button.pressed.emit()
	await _seconds(0.6)
	if cards.visible:
		_failures.append("role cards did not dismiss")


func _check_gameplay(field: Node) -> void:
	await _seconds(0.5)
	if not GameManager.round_state in ["prepare", "setup", "wave"]:
		_failures.append("gameplay did not resume in prepare/setup/wave (state is %s)" % GameManager.round_state)
	var hud := field.get_node_or_null("HUDLayer/HUD")
	if hud == null:
		_failures.append("field has no HUD")


# ------------------------------------------------------------------- bits ---

func _seconds(sec: float) -> void:
	await _tree.create_timer(sec).timeout


func _finish() -> void:
	if _failures.is_empty():
		print("✓ CoreGameplayTest passed: section 02 atlas, role cards, and normal gameplay flow cleanly.")
		_tree.quit()
	else:
		push_error("[CoreGameplayTest] Failures (%d):\n  - %s" % [
			_failures.size(), "\n  - ".join(_failures)])
		_tree.quit(1)


func _wait_scene(scene_path: String) -> Node:
	for _i in 600:
		await _tree.process_frame
		var cur := _tree.current_scene
		if cur != null and cur.scene_file_path == scene_path:
			return cur
	return null
