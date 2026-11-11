class_name CoreGameplayTest
extends RefCounted

# Section 02 regression test (--core-test):
#   1. PresentationDeck row 02 points at the section atlas and has title.
#   2. Atlas opens on Saigon with the centered Orrery concentric loop diagram.
#   3. Province click switches the orrery for the field instruction.
#   4. Next button transitions into the HCMC field.
#   5. RoleCards open on entry and dismiss when Show me is pressed.
#   6. SeedSelector opens next so presenter can pick loadout.
#   7. PlacementGuide opens, evaluates the 5 checks and facing compass.
#   8. Back to contents button finishes the section and restores starting_sun.
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
	await _check_seed_selector(field)
	await _check_guide(field)
	await _check_finish(field)
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
	var hint := screen.find_child("Hint", true, false) as Label
	if hint == null or not hint.visible:
		_failures.append("province mode does not show the field instruction")
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
	if GameManager.round_state != "sandbox":
		_failures.append("field round state is \"%s\", not sandbox" % GameManager.round_state)
	if GameManager.current_level_id != "hcmc_01":
		_failures.append("field did not prepare hcmc_01")
	if GameManager.current_sun != CoreGameplayField.DEMO_SUN:
		_failures.append("field starts at %d gems, not %d" % [GameManager.current_sun, CoreGameplayField.DEMO_SUN])
	var map := field.call("current_map") as MapDefinition
	if map == null or map.map_id != "landmark_81":
		_failures.append("field is not on landmark_81")
	var loadout := GameManager.seed_loadout
	for id in CoreGameplayField.LOADOUT:
		if not loadout.has(id):
			_failures.append("loadout is missing %s" % id)
	if loadout.size() != CoreGameplayField.LOADOUT.size():
		_failures.append("loadout has %d seeds, expected %d" % [
			loadout.size(), CoreGameplayField.LOADOUT.size()])
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


func _check_seed_selector(field: Node) -> void:
	var hud := field.get_node_or_null("HUDLayer/HUD")
	var selector: SeedSelector = hud.get_node_or_null("SeedSelector") if hud != null else null
	if selector == null:
		_failures.append("field has no SeedSelector")
		return
	await _seconds(0.3)
	if not selector.is_open:
		_failures.append("SeedSelector did not open after role cards")
	selector.close()
	await _seconds(0.4)
	if selector.is_open:
		_failures.append("SeedSelector did not close")


func _check_guide(field: Node) -> void:
	var guide := field.get_node_or_null("PresentationLayer/PlacementGuide") as PlacementGuide
	if guide == null:
		_failures.append("field has no placement guide")
		return
	await _seconds(0.5)
	if not guide.visible:
		_failures.append("placement guide did not open")
	var dots: Array = guide.get("_dots")
	if dots.size() != PresentationDeck.CORE_CHECKS.size():
		_failures.append("guide shows %d checks, expected %d" % [
			dots.size(), PresentationDeck.CORE_CHECKS.size()])
	if guide.find_child("Facing", true, false) == null:
		_failures.append("guide has no facing dial")

	var placement := field.get_node("PlacementManager") as PlacementManager
	if placement == null:
		_failures.append("field has no PlacementManager")
		return
	var heard := [false]
	var handler := func(_t: String, _c: Vector2i, _r: int, _v: bool, _p: int) -> void:
		heard[0] = true
	EventBus.placement_preview_changed.connect(handler)
	EventBus.plant_selected_for_placement.emit("lotus_shooter",
		GameManager.local_player_id())
	var cam := (field.get("camera_rig") as Node).get("camera") as Camera3D
	var tile := Vector2i(2, -4)
	if cam != null:
		placement._update_raycast_hover(placement.p1,
			cam.unproject_position(placement.position_for_tile(tile)))
	EventBus.placement_preview_changed.disconnect(handler)
	if not heard[0]:
		_failures.append("a hovered tile never reached the guide")
	var seed_label := guide.get("_seed") as Label
	if seed_label == null or not seed_label.text.to_upper().contains("LOTUS"):
		_failures.append("guide does not name the selected seed")
	if guide.get("_coord") != tile:
		_failures.append("the guide followed tile %s, not %s" % [
			str(guide.get("_coord")), str(tile)])
	var states: Array = guide.call("_states")
	if states.size() != PresentationDeck.CORE_CHECKS.size():
		_failures.append("guide did not evaluate five checks")
	elif states.has(2):
		_failures.append("an empty lawn tile failed a placement check %s at %s (gems %d)" % [
			str(states), str(guide.get("_coord")), GameManager.current_sun])
	EventBus.placement_cancelled.emit(GameManager.local_player_id())
	await _seconds(0.1)


func _check_finish(field: Node) -> void:
	var guide := field.get_node_or_null("PresentationLayer/PlacementGuide") as PlacementGuide
	if guide == null:
		_failures.append("field has no placement guide")
		return
	var button := guide.find_child("ContinueButton", true, false) as Button
	if button == null:
		_failures.append("guide has no continue button")
		return
	button.pressed.emit()
	var contents := await _wait_scene(GameFlow.CONTENTS_SCENE)
	if contents == null:
		_failures.append("did not return to contents scene")
		return
	if GameManager.starting_sun == CoreGameplayField.DEMO_SUN:
		_failures.append("starting_sun was not restored")


# ------------------------------------------------------------------- bits ---

func _seconds(sec: float) -> void:
	await _tree.create_timer(sec).timeout


func _finish() -> void:
	if _failures.is_empty():
		print("✓ CoreGameplayTest passed: section 02 atlas, cards, seed selector, guide and normal gameplay flow cleanly.")
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
