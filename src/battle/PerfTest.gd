extends RefCounted

# --perf-test: draw-call and layout regression test for the battle shell.
# For day and night, snaps the camera to each view in VIEWS (the gameplay camera
# plus CameraPresets rows), lets it settle, then takes the MEDIAN draw calls and
# primitives over SAMPLE_FRAMES - a single frame is noisy (TRAPS.md
# #multimesh-aabb-draw-calls). It also hashes every MultiMesh instance under the
# map: `layout` covers count, x/z and basis (placement changed), `heights` covers y
# (things re-seated on the ground). Viewport GPU render time is measured and reported
# per view (machine-dependent, never failed). Compared with
# data/maps/<map_id>/perf_baseline.json:
# FAIL when a view's draw calls exceed baseline + DRAW_CALL_TOLERANCE or the
# layout hash differs. Heights, primitives and GPU ms are reported, never failed.
# `-- --perf-test --update-baseline` rewrites the baseline after an approved
# change. Prints "[PerfTest] PASS" or each failure, then quits 0 / 1. Loaded only
# by DioramaWorld._ready() under the flag.

const CameraPresets := preload("res://src/battle/CameraPresets.gd")
const VIEWS := ["gameplay", "--wide-overview", "--axonometric", "--skyline-panorama"]
const SETTLE_FRAMES := 40
const SAMPLE_FRAMES := 30
const TRANSITION_MAX_FRAMES := 900
const DRAW_CALL_TOLERANCE := 3
const DRAW_RETRIES := 3

static var _alive: RefCounted = null # keeps the awaiting coroutine alive

var _tree: SceneTree
var _baseline_path: String = ""
var _failures: Array[String] = []


func run(shell: Node) -> void:
	_alive = self
	_tree = shell.get_tree()
	_baseline_path = "res://data/maps/%s/perf_baseline.json" % shell.current_map().map_id
	var vp_rid: RID = shell.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	await _frames(SETTLE_FRAMES)
	var cam: Node = shell.find_child("ThirdPersonCamera", true, false)
	var cycle: Node = shell.find_child("DayNightCycle", true, false)
	var gameplay := {
		"pos": cam.global_position, "arm": cam.arm_length, "pitch": cam.pitch_degrees,
		"yaw": cam.yaw_degrees, "fov": cam.camera.fov,
	}
	var gameplay_target: Node3D = cam.target

	var measured := {"draw_calls": {}, "primitives": {}, "gpu_ms": {}}
	for phase in ["day", "night"]:
		GameManager.set_time_of_day(phase)
		await _await_transition(cycle)
		for view in VIEWS:
			if view == "gameplay":
				CameraPresets.apply(cam, gameplay)
				cam.set_target(gameplay_target)
			else:
				CameraPresets.apply(cam, CameraPresets.by_flag(view))
			var key := "%s/%s" % [phase, view.trim_prefix("--")]
			var dc: Array[int] = []
			var prims: Array[int] = []
			var gpus: Array[float] = []
			# A hidden or minimized window keeps processing but stops drawing, and the
			# monitors go stale: raise it and retry before calling the view unmeasurable.
			var drawn := 0
			for attempt in DRAW_RETRIES:
				_raise_window()
				await _frames(SETTLE_FRAMES)
				dc.clear()
				prims.clear()
				gpus.clear()
				var drawn_before := Engine.get_frames_drawn()
				for i in SAMPLE_FRAMES:
					await _tree.process_frame
					dc.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
					prims.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
					gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
				drawn = Engine.get_frames_drawn() - drawn_before
				if drawn >= SAMPLE_FRAMES / 2:
					break
			if drawn < SAMPLE_FRAMES / 2:
				_failures.append("%s: the window drew %d of %d frames after %d tries - keep it visible while the test runs" % [key, drawn, SAMPLE_FRAMES, DRAW_RETRIES])
			measured["draw_calls"][key] = _median(dc)
			measured["primitives"][key] = _median(prims)
			measured["gpu_ms"][key] = _median_float(gpus)
	var hashes := _layout_hashes(shell.current_map())
	measured["layout"] = hashes[0]
	measured["heights"] = hashes[1]

	if "--update-baseline" in OS.get_cmdline_user_args() and _failures.is_empty():
		var to_save := {"draw_calls": measured["draw_calls"], "primitives": measured["primitives"], "layout": measured["layout"], "heights": measured["heights"]}
		var f := FileAccess.open(_baseline_path, FileAccess.WRITE)
		f.store_string(JSON.stringify(to_save, "  ", true) + "\n")
		f.close()
		print("[PerfTest] baseline written: %s" % _baseline_path)
	else:
		_compare(measured)

	if _failures.is_empty():
		print("[PerfTest] PASS")
	else:
		for f in _failures:
			print("[PerfTest] FAIL: %s" % f)
	_tree.quit(0 if _failures.is_empty() else 1)


func _compare(measured: Dictionary) -> void:
	var base: Variant = JSON.parse_string(FileAccess.get_file_as_string(_baseline_path))
	if not (base is Dictionary):
		_failures.append("no baseline at %s - run with --update-baseline once" % _baseline_path)
		return
	for key in measured["draw_calls"]:
		var now: int = measured["draw_calls"][key]
		var was: int = int(base["draw_calls"].get(key, -1))
		var prims_now: int = measured["primitives"][key]
		var prims_was: int = int(base["primitives"].get(key, 0))
		var gpu_now: float = float(measured.get("gpu_ms", {}).get(key, 0.0))
		print("[PerfTest] %-24s draw calls %3d (baseline %3d)  primitives %7d (baseline %7d)  gpu %5.2f ms" % [key, now, was, prims_now, prims_was, gpu_now])
		if was < 0:
			_failures.append("%s has no baseline entry" % key)
		elif now > was + DRAW_CALL_TOLERANCE:
			_failures.append("%s draw calls %d > baseline %d + %d" % [key, now, was, DRAW_CALL_TOLERANCE])
		elif now < was - DRAW_CALL_TOLERANCE:
			print("[PerfTest] note: %s is %d below baseline - consider --update-baseline" % [key, was - now])
	if measured["layout"] != base.get("layout", ""):
		_failures.append("MultiMesh layout hash changed (placement moved); if intended, --update-baseline")
	if measured["heights"] != base.get("heights", ""):
		print("[PerfTest] note: MultiMesh heights changed (instances re-seated on the ground)")


func _raise_window() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()


# Waits for DayNightCycle to finish the cross-fade it just started (it idles with
# processing off), plus a few frames for the settled sky bake.
func _await_transition(cycle: Node) -> void:
	await _tree.process_frame
	var guard := 0
	while cycle and cycle.is_processing() and guard < TRANSITION_MAX_FRAMES:
		await _tree.process_frame
		guard += 1
	await _frames(5)


# [layout, heights]: SHA-1 of every MultiMesh instance under `map`, walked in tree
# order, rounded to millimetres so float noise never trips it.
func _layout_hashes(map: Node) -> Array[String]:
	var layout := PackedStringArray()
	var heights := PackedStringArray()
	for node in map.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm == null:
			continue
		layout.append("%s:%d" % [map.get_path_to(node), mm.instance_count])
		for i in mm.instance_count:
			var t := mm.get_instance_transform(i)
			layout.append("%d,%d|%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
				roundi(t.origin.x * 1000.0), roundi(t.origin.z * 1000.0),
				roundi(t.basis.x.x * 1000.0), roundi(t.basis.x.y * 1000.0), roundi(t.basis.x.z * 1000.0),
				roundi(t.basis.y.x * 1000.0), roundi(t.basis.y.y * 1000.0), roundi(t.basis.y.z * 1000.0),
				roundi(t.basis.z.x * 1000.0), roundi(t.basis.z.y * 1000.0), roundi(t.basis.z.z * 1000.0)])
			heights.append(str(roundi(t.origin.y * 1000.0)))
	return ["\n".join(layout).sha1_text(), "\n".join(heights).sha1_text()]


func _median(values: Array[int]) -> int:
	values.sort()
	return values[values.size() / 2]


func _median_float(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]



func _frames(n: int) -> void:
	for i in n:
		await _tree.process_frame
