extends RefCounted

# --touch-test: the touch contract, no touchscreen required.
# Emits real InputEventScreenTouch/ScreenDrag through Input.parse_input_event, so
# the run exercises the same chain a phone does: Godot's touch->mouse emulation,
# TouchInput's multi-touch latch in _input, then PlacementManager's
# _unhandled_input. The promises that cannot fail loudly on their own:
#   1. Press aims only; the lift commits exactly one plant at the aimed tile.
#   2. A second finger (pinch/orbit) never plants or digs — even when the
#      emulated mouse release arrives before the raw touch release.
#   3. Pinch changes the camera arm, two-finger drag orbits the view.
#   4. Touch-only controls exist, and rotate/cancel appear only when usable.
# Loaded only by DioramaWorld._ready() under the flag; prints PASS/FAIL and quits.

const PLANT := "sau_shooter"
const FINGER_0 := 0
const FINGER_1 := 1

static var _alive: RefCounted = null # keeps the awaiting coroutine alive

var _tree: SceneTree
var _shell: Node
var _pm: PlacementManager
var _camera: Node3D
var _touch: TouchInput
var _failures: Array[String] = []


func run(shell: Node) -> void:
	_alive = self
	_shell = shell
	_tree = shell.get_tree()
	_pm = shell.find_child("PlacementManager", true, false) as PlacementManager
	_camera = shell.find_child("ThirdPersonCamera", true, false) as Node3D
	_touch = shell.find_child("TouchInput", true, false) as TouchInput
	await _frames(10)
	await _test()

	if _failures.is_empty():
		print("[TouchTest] PASS")
	else:
		for f in _failures:
			print("[TouchTest] FAIL: %s" % f)
	_tree.quit(0 if _failures.is_empty() else 1)


func _test() -> void:
	if _pm == null or _camera == null or _touch == null:
		_fail("battle shell is missing PlacementManager / ThirdPersonCamera / TouchInput")
		return
	if _pm.valid_grid_coords.is_empty():
		_fail("no placeable tiles (map/lawn not loaded)")
		return

	_expect(GameManager.is_touch_ui(), "--touch-test must enable the touch path")
	_expect(_touch.is_processing_input(), "TouchInput listens when touch UI is on")

	# Keep the hover where the test puts it: _process would chase the emulated
	# mouse position between our press and release.
	_pm.set_process(false)
	GameManager.current_sun = 10000
	GameManager.touch_gesture_multi = false

	await _test_tap_places_once()
	await _test_two_fingers_do_not_place()
	await _test_pinch_and_orbit()
	await _test_controls()


## One finger: the press must not plant, the lift must plant once.
func _test_tap_places_once() -> void:
	GameManager.select_plant(PLANT, 0)
	await _frames(1)
	var pick := _visible_free_tile()
	if pick.is_empty():
		_fail("need one on-screen free tile for the tap test")
		return
	var tile: Vector2i = pick[0]
	var screen: Vector2 = pick[1]
	var container: Node = _pm.get_node_or_null(_pm.plants_container_path)
	var plants_before: int = container.get_child_count()
	var sun_before: int = GameManager.current_sun
	var cost: int = GameManager.plant_cost(PLANT)

	_touch_event(true, screen, FINGER_0)
	await _frames(2)
	_expect(GameManager.current_sun == sun_before, "touch press spends nothing (aim only)")
	_expect(not _pm.occupied_tiles.has(tile), "touch press plants nothing")
	_expect(container.get_child_count() == plants_before, "touch press spawns nothing")

	_touch_event(false, screen, FINGER_0)
	await _frames(3)
	_expect(GameManager.current_sun == sun_before - cost, "touch lift debits the sun once")
	_expect(container.get_child_count() == plants_before + 1, "touch lift spawns exactly one plant")
	_expect(_pm.occupied_tiles.has(tile), "touch lift plants on the aimed tile")
	_expect(not GameManager.touch_gesture_multi, "single-finger lift clears the multi-touch latch")

	# Leave the tool in hand; the next case re-selects anyway.
	_pm.occupied_tiles.erase(tile)


## Two fingers: the pinch latch must swallow the commit.
func _test_two_fingers_do_not_place() -> void:
	GameManager.select_plant(PLANT, 0)
	await _frames(1)
	var pick := _visible_free_tile()
	if pick.is_empty():
		_fail("need one on-screen free tile for the multi-touch test")
		return
	var tile: Vector2i = pick[0]
	var screen: Vector2 = pick[1]
	var container: Node = _pm.get_node_or_null(_pm.plants_container_path)
	var plants_before: int = container.get_child_count()
	var sun_before: int = GameManager.current_sun

	_touch_event(true, screen, FINGER_0)
	_touch_event(true, screen + Vector2(90.0, 0.0), FINGER_1)
	await _frames(1)
	_expect(GameManager.touch_gesture_multi, "second finger sets the multi-touch latch")

	# Release the aiming finger first: the emulated mouse release is delivered
	# now, while the raw touch release for finger 1 has not happened yet.
	_touch_event(false, screen, FINGER_0)
	await _frames(2)
	_expect(GameManager.touch_gesture_multi, "latch survives while one finger remains")
	_expect(GameManager.current_sun == sun_before, "pinch spends nothing")
	_expect(container.get_child_count() == plants_before, "pinch spawns no plant")
	_expect(not _pm.occupied_tiles.has(tile), "pinch does not plant on the aimed tile")

	_touch_event(false, screen + Vector2(90.0, 0.0), FINGER_1)
	await _frames(2)
	_expect(not GameManager.touch_gesture_multi, "latch clears when every finger lifts")
	_expect(container.get_child_count() == plants_before, "lifting the last finger still plants nothing")


## Gestures reach the camera, not the grid.
func _test_pinch_and_orbit() -> void:
	GameManager.clear_selection(0)
	await _frames(1)

	var arm_before: float = _camera.arm_length
	var yaw_before: float = _camera._target_yaw
	var pitch_before: float = _camera._target_pitch
	var centre := _viewport_size() * 0.5

	_touch_event(true, centre + Vector2(-60.0, 0.0), FINGER_0)
	_touch_event(true, centre + Vector2(60.0, 0.0), FINGER_1)
	await _frames(1)
	# Spread the fingers apart: zoom in (shorter arm).
	_touch_drag(centre + Vector2(-120.0, 0.0), FINGER_0)
	_touch_drag(centre + Vector2(120.0, 0.0), FINGER_1)
	await _frames(2)
	_expect(_camera.arm_length < arm_before, "spreading two fingers zooms in (shorter arm)")

	# Slide both fingers down: orbit the view.
	_touch_drag(centre + Vector2(-120.0, 80.0), FINGER_0)
	_touch_drag(centre + Vector2(120.0, 80.0), FINGER_1)
	await _frames(2)
	var orbited: bool = absf(_camera._target_pitch - pitch_before) > 0.01 or absf(_camera._target_yaw - yaw_before) > 0.01
	_expect(orbited, "two-finger drag orbits the camera")

	_touch_event(false, centre + Vector2(-120.0, 80.0), FINGER_0)
	_touch_event(false, centre + Vector2(120.0, 80.0), FINGER_1)
	await _frames(1)
	_expect(not GameManager.touch_gesture_multi, "gesture ends with the latch clear")
	_expect(not _pm.p1.is_placing, "gesture did not start a placement")


## The touch-only HUD: present, and only offers actions that do something.
func _test_controls() -> void:
	var hud: Node = _shell.find_child("HUD", true, false)
	if hud == null:
		_fail("HUD not found")
		return
	var controls: Node = hud.find_child("TouchControls", true, false)
	if controls == null:
		_fail("touch controls are not built on a touch device")
		return
	var pause: Button = controls.find_child("Pause", true, false) as Button
	var rotate_left: Button = controls.find_child("RotateLeft", true, false) as Button
	var cancel: Button = controls.find_child("Cancel", true, false) as Button
	if pause == null or rotate_left == null or cancel == null:
		_fail("touch controls are missing Pause / RotateLeft / Cancel")
		return
	_expect(pause.visible, "pause is offered during the round")
	_expect(not rotate_left.visible, "rotate is hidden with no seed in hand")
	_expect(not cancel.visible, "cancel is hidden with no seed in hand")

	GameManager.select_plant(PLANT, 0)
	await _frames(2)
	_expect(rotate_left.visible, "rotate appears with a seed in hand")
	_expect(cancel.visible, "cancel appears with a seed in hand")

	# The rotate button drives the same path as R / the D-pad.
	var step_before: int = _pm.p1.rot_step
	EventBus.placement_rotate_pressed.emit(1, 0)
	await _frames(1)
	_expect(_pm.p1.rot_step != step_before, "rotate button turns the ghost")

	GameManager.clear_selection(0)
	await _frames(2)
	_expect(not rotate_left.visible, "rotate hides again after cancelling")


# --- input synthesis -------------------------------------------------------

func _touch_event(pressed: bool, at: Vector2, index: int) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = _input_space(at)
	event.pressed = pressed
	Input.parse_input_event(event)


func _touch_drag(at: Vector2, index: int) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = _input_space(at)
	event.relative = Vector2.ZERO
	Input.parse_input_event(event)


## Input.parse_input_event takes screen coordinates; the viewport converts them
## back with get_final_transform(). Multiplying by that transform here means the
## event lands on `at` in viewport space. On a desktop/phone the transform is
## the identity, so this is a no-op; under --headless the dummy window reports
## 0x0, which would otherwise scale every synthetic touch far off-screen.
func _input_space(at: Vector2) -> Vector2:
	return _shell.get_viewport().get_final_transform() * at


## An unoccupied placeable tile that is comfortably inside the viewport, plus
## the screen position of its centre. Empty if the current camera framing shows
## no free tile (the sandbox camera is home over the pearl, so this only fails
## if the map did not load).
func _visible_free_tile() -> Array:
	var size := _viewport_size()
	var lo := size * 0.2
	var hi := size * 0.8
	for coord in _pm.valid_grid_coords:
		if _pm.occupied_tiles.has(coord):
			continue
		var world := Vector3(coord.x * _pm.tile_size, _pm._ground_y, coord.y * _pm.tile_size)
		if _pm._map != null:
			world.y = _pm._map.ground_y_at(world.x, world.z) + 0.02
		var screen: Vector2 = _view_camera().unproject_position(world)
		if screen.x < lo.x or screen.y < lo.y or screen.x > hi.x or screen.y > hi.y:
			continue
		return [coord, screen]
	return []


func _viewport_size() -> Vector2:
	return _shell.get_viewport().get_visible_rect().size


## ThirdPersonCamera is a rig (spring arm + Camera3D); projection lives on the
## nested Camera3D, which is also what PlacementManager raycasts through.
func _view_camera() -> Camera3D:
	return _shell.get_viewport().get_camera_3d()


# --- helpers ---------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if not condition:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append(what)


## nth placeable tile that no plant occupies (stale plants from a previous
## sandbox run are skipped).
func _free_tile(n: int) -> Vector2i:
	var seen := 0
	for coord in _pm.valid_grid_coords:
		if _pm.occupied_tiles.has(coord):
			continue
		if seen == n:
			return coord
		seen += 1
	return Vector2i(-999, -999)


func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame
