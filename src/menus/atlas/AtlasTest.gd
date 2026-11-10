extends RefCounted

# --atlas-test: checks the atlas menu's picking and province states. For every
# province: a straight-down ray at its label point and at each of its islets
# must pick it (outline data + pick math), and, with the camera snapped to that
# province's rail position, the screen-space pick at the projected label must
# too (camera path). Zoom: the wheel zooms, extremes settle and still pick. States and tooltips must agree with LevelDB + Progress, and
# the menu must be idle once settled. Then the province screen: a content-less
# province must not open; HCMC opens within time with its levels in list order,
# every node inside the outline, node states / next marker matching Progress;
# clicking node 0 enters it directly; Back returns the camera to the rail pose. Prints "[AtlasTest] PASS" or each failure,
# quits 0 / 1. Loaded only by AtlasMenu._ready() under the flag. Read-only: it
# never writes the save.

# Nothing else references this RefCounted once run() awaits.
static var _alive: RefCounted = null

var _failures: Array[String] = []


func run(menu: Node) -> void:
	_alive = self
	var tree := menu.get_tree()
	await tree.process_frame
	var atlas: AtlasProvinces = menu.provinces
	if atlas.count() != 34:
		_failures.append("expected 34 provinces, got %d" % atlas.count())

	var screen_ok := 0
	for i in atlas.count():
		var id := atlas.ids[i]
		var top: float = menu._tops[i]
		var lab := atlas.labels[i]
		if atlas.pick(Vector3(lab.x, 20.0, lab.y), Vector3.DOWN, menu._tops) != i:
			_failures.append("down-ray at %s label picked %d" % [id, atlas.pick(Vector3(lab.x, 20.0, lab.y), Vector3.DOWN, menu._tops)])
		for part in atlas._parts[i].slice(1):
			var c := _centroid(part[0])
			if atlas.pick(Vector3(c.x, 20.0, c.y), Vector3.DOWN, menu._tops) != i:
				_failures.append("down-ray at a %s islet/island %s picked another province" % [id, c])
		menu._snap_rail(menu._rail_offset_of(id))
		var cam: Camera3D = menu._camera
		var world := Vector3(lab.x, top, lab.y)
		var screen := cam.unproject_position(world)
		if cam.is_position_behind(world) or not menu.get_viewport().get_visible_rect().has_point(screen):
			_failures.append("%s label off-screen from its own rail position" % id)
			continue
		var got: int = menu.pick_at(screen)
		if got != i:
			_failures.append("screen pick at %s label -> %s" % [id, atlas.ids[got] if got >= 0 else "none"])
		else:
			screen_ok += 1

	for i in atlas.count():
		var world: Dictionary = menu._world_by_province.get(atlas.ids[i], {})
		var want := 0
		if not world.is_empty():
			var wid := str(world["id"])
			var total := LevelDB.get_level_ids(wid).size()
			want = 1 if not Progress.is_world_unlocked(wid) else (3 if total > 0 and Progress.completed_count(wid) >= total else 2)
		if int(menu._states[i]) != want:
			_failures.append("%s state %d, expected %d" % [atlas.ids[i], int(menu._states[i]), want])
		var text: String = menu.describe(i)
		if world.is_empty() and not text.ends_with("Coming soon"):
			_failures.append("%s tooltip: %s" % [atlas.ids[i], text])
		if not world.is_empty() and Progress.is_world_unlocked(str(world["id"])) and not text.ends_with("levels"):
			_failures.append("%s tooltip: %s" % [atlas.ids[i], text])

	await _check_zoom(menu, atlas, tree)
	await _check_touch_gestures(menu, tree)
	await _check_province_screen(menu, atlas, tree)

	menu._set_goal(menu.rail_length())
	for i in 240:
		await tree.process_frame
		if not menu.is_processing():
			break
	if menu.is_processing():
		_failures.append("camera still processing 4 s after a glide (idle cost)")

	print("[AtlasTest] screen picks OK: %d/%d" % [screen_ok, atlas.count()])
	if _failures.is_empty():
		print("[AtlasTest] PASS")
	else:
		for f in _failures:
			print("[AtlasTest] FAIL: %s" % f)
	tree.quit(0 if _failures.is_empty() else 1)


## Wheel zooms (not travel); zoom glides to ZOOM_MIN / ZOOM_MAX, scales the
## camera distance, keeps picking right, and settles to idle.
func _check_zoom(menu: Node, atlas: AtlasProvinces, tree: SceneTree) -> void:
	var hi := atlas.index_of("hcmc")
	menu._snap_rail(menu._rail_offset_of("hcmc"))
	var rail_before: float = menu._rail_goal
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	menu._unhandled_input(wheel)
	if menu._zoom_goal >= 1.0 or menu._rail_goal != rail_before:
		_failures.append("wheel did not zoom in (or moved the rail)")
	var base := Vector3(0.0, menu.CAM_HEIGHT, menu.CAM_BACK).length()
	for z in [menu.ZOOM_MIN, menu.ZOOM_MAX, 1.0]:
		menu.set_zoom_goal(z)
		for i in 300:
			await tree.process_frame
			if not menu.is_processing():
				break
		if menu.is_processing() or absf(menu.zoom() - z) > 1e-3:
			_failures.append("zoom did not settle at %.2f" % z)
			continue
		var cam: Camera3D = menu._camera
		if absf(cam.global_position.distance_to(menu._rail_target()) - base * z) > 0.01:
			_failures.append("camera distance wrong at zoom %.2f" % z)
		var lab := atlas.labels[hi]
		var got: int = menu.pick_at(cam.unproject_position(Vector3(lab.x, menu._tops[hi], lab.y)))
		if got != hi:
			_failures.append("pick at HCMC label wrong at zoom %.2f" % z)


## Touch gestures (CONTRACT(touch-input)): a spread fingers pinch is a zoom, a
## two-finger drag travels the rail, and neither leaves the atlas screen. Called
## directly: a headless run reports no touchscreen, so TouchInput is not
## listening and only the handlers can be checked.
func _check_touch_gestures(menu: Node, tree: SceneTree) -> void:
	menu.set_zoom_goal(1.0)
	for i in 240:
		await tree.process_frame
		if not menu.is_processing():
			break
	var zoom_before: float = menu._zoom_goal
	menu._on_touch_pinch(2.0)
	if absf(menu._zoom_goal - zoom_before * 0.5) > 1e-4:
		_failures.append("pinch did not halve the zoom goal (%.3f -> %.3f)" % [zoom_before, menu._zoom_goal])
	menu.set_zoom_goal(1.0)
	var rail_before: float = menu._rail_goal
	menu._on_touch_drag(Vector2(0.0, -20.0))
	var want: float = rail_before - 20.0 * menu.PAN_GESTURE_METRES
	if absf(menu._rail_goal - want) > 1e-4:
		_failures.append("two-finger drag did not travel the rail (%.3f -> %.3f, want %.3f)" % [rail_before, menu._rail_goal, want])
	if menu.mode != 0:
		_failures.append("a gesture left the atlas screen")


## The first province no world in data/worlds/ names (LevelDB), so the check keeps
## working as provinces gain content.
func _contentless_index(atlas: AtlasProvinces) -> int:
	var used := {}
	for w in LevelDB.get_worlds():
		used[str(w.get("province", ""))] = true
	for i in atlas.ids.size():
		if not used.has(atlas.ids[i]):
			return i
	return -1


func _check_province_screen(menu: Node, atlas: AtlasProvinces, tree: SceneTree) -> void:
	menu.click_province(_contentless_index(atlas))
	if menu.mode != 0:
		_failures.append("content-less province opened")
		return
	var hi := atlas.index_of("hcmc")
	menu._snap_rail(menu._rail_offset_of("hcmc"))
	var t0 := Time.get_ticks_msec()
	menu.click_province(hi)
	await menu.transition_finished
	var open_ms := Time.get_ticks_msec() - t0
	if menu.mode != 1 or menu.board == null:
		_failures.append("HCMC did not open")
		return
	if open_ms > 1300:
		_failures.append("zoom-in + reveal took %d ms" % open_ms)
	var board: ProvinceBoard = menu.board
	var ids := LevelDB.get_level_ids("hcmc")
	if board.level_ids != ids:
		_failures.append("nodes %s, expected %s" % [board.level_ids, ids])
	var want_next := -1
	for i in ids.size():
		var p := board.node_positions[i]
		if not atlas.contains(hi, Vector2(p.x, p.z)):
			_failures.append("node %d at %s is outside the HCMC outline" % [i, p])
		var want := 2 if Progress.is_level_completed(ids[i]) else (1 if Progress.is_level_unlocked(ids[i]) else 0)
		if want == 1 and want_next < 0:
			want_next = i
		if board.node_states[i] != want:
			_failures.append("node %d state %d, expected %d" % [i, board.node_states[i], want])
	if board.next_index != want_next:
		_failures.append("next marker on %d, expected %d" % [board.next_index, want_next])
	var cam: Camera3D = menu._camera
	var screen := cam.unproject_position(board.node_positions[0])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	var requested_level := [""]
	var on_play := func(lvl: String) -> void: requested_level[0] = lvl
	EventBus.level_play_requested.connect(on_play)
	var gameflow_connected := EventBus.level_play_requested.is_connected(GameFlow.play_level)
	if gameflow_connected:
		EventBus.level_play_requested.disconnect(GameFlow.play_level)
	menu._province_input(click)
	if requested_level[0] != ids[0]:
		_failures.append("clicking node 0 did not request playing level %s (got %s)" % [ids[0], requested_level[0]])
	EventBus.level_play_requested.disconnect(on_play)
	if gameflow_connected:
		EventBus.level_play_requested.connect(GameFlow.play_level)
	# Android's Back button must leave the province screen, not the app.
	t0 = Time.get_ticks_msec()
	menu._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await menu.transition_finished
	var close_ms := Time.get_ticks_msec() - t0
	if close_ms > 1000:
		_failures.append("zoom-out took %d ms" % close_ms)
	if menu.mode != 0 or menu.board != null:
		_failures.append("Back did not return to the atlas")
	if cam.global_position.distance_to(menu._rail_eye()) > 0.01:
		_failures.append("camera not back on the rail pose")
	print("[AtlasTest] province screen: open %d ms, close %d ms" % [open_ms, close_ms])


static func _centroid(ring: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in ring:
		c += p
	return c / float(maxi(ring.size(), 1))
