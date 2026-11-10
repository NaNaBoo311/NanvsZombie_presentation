class_name ResultSequence
extends Control

# The win and defeat moments that lead into BattlePanel. Win, "Dawn Breaks": night turns to
# day, a shockwave rolls out from the Pearl, rays turn behind the panel, the plants cheer
# in a ripple, stars stamp in one by one, Jade counts up, any awakened seed gets its own
# reveal (SeedReveal), then the closing Chronicle line writes itself and the buttons
# arrive. Defeat, "Pearl Shattered": the camera shakes, the Pearl goes, cracks race across
# the screen, the colour drains, red closes in, plants wilt, and the panel slams down with
# how far the player got and one tip. Any click or key skips to the end.
# Everything here is transient: Tweens and ResultFx layers that only run on a result,
# so a battle never pays for it. It covers the panel only with a transparent click catcher.

signal finished

const PEARL_HEIGHT := 6.0
const STAR_RADIUS := 31.0
const STAR_GAP := 76.0
const STAR_STEP_SEC := 0.34
const SHARDS := 26
const SPARKS := 38
const CRACKS := 9
const CAMERA_PUSH := 0.72
const SHAKE_STEPS := 9
const SPARK_SEC := 8.0
const SHARD_SEC := 1.7
const SHAKE_METRES := 0.5

var panel: PanelContainer
var title: Label
var star_row: Control
var reward: Label
var chronicle: Label
var buttons: Control
var report: Control # the defeat panel's reached bar and tip
var report_painter: Callable

var _grade: ColorRect
var _back: ResultFx
var _front: ResultFx
var _grade_mat: ShaderMaterial
var _tween: Tween = null
var _side: Tween = null
var _playing := false
var _award: Dictionary = {}
var _origin := Vector2.ZERO
var _won := false
var _wave := 0.0
var _rays := 0.0
var _crack := 0.0
var _shard_t := 0.0
var _star_pop: Array[float] = []
var _burst: Array[float] = []
var _crack_paths: Array[PackedVector2Array] = []
var _shards: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _spark_t := 0.0
var _reveal: SeedReveal = null


func setup(behind_panel_index: int) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1
	var host := get_parent()
	_grade = ColorRect.new()
	_grade.name = "ResultGrade"
	_grade_mat = ShaderMaterial.new()
	_grade_mat.shader = load("res://assets/shaders/ResultGrade.gdshader")
	_grade.material = _grade_mat
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grade.visible = false
	host.add_child(_grade)
	host.move_child(_grade, behind_panel_index)
	_grade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_back = ResultFx.new()
	_back.name = "ResultBack"
	_back.paint = _paint_back
	host.add_child(_back)
	host.move_child(_back, behind_panel_index + 1)
	_back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front = ResultFx.new()
	_front.name = "ResultFront"
	_front.paint = _paint_front
	add_child(_front)
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func is_playing() -> bool:
	return _playing


## Back to nothing: Retry, Map, or a pause panel reusing the same node.
func reset() -> void:
	_kill()
	_kill_ambient()
	_playing = false
	_won = false
	_grade.visible = false
	_back.running = false
	_front.running = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.scale = Vector2.ONE
	panel.rotation = 0.0
	panel.modulate.a = 1.0
	for control: Control in [title, star_row, reward, chronicle, buttons, report]:
		control.modulate.a = 1.0
	star_row.visible = false
	report.visible = false
	chronicle.visible_ratio = 1.0
	if is_instance_valid(_reveal):
		_reveal.queue_free()


func play_win(award: Dictionary) -> void:
	_begin(award)
	_won = true
	_set_grade(0.0, UiPalette.HUD_DAWN)
	star_row.visible = not award.is_empty()
	_make_sparks()
	if GameManager.time_of_day != "day":
		GameManager.set_time_of_day("day")
	_cheer_plants()
	_push_camera()
	Audio.play(Audio.BATTLE_START)
	var total: int = Progress.MAX_STARS
	_star_pop.resize(total)
	_star_pop.fill(0.0)
	_burst.resize(total)
	_burst.fill(0.0)
	_ambient("_spark_t", SPARK_SEC)
	var t := _new_tween()
	t.tween_property(self, "_wave", 1.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "_rays", 1.0, 0.8)
	t.parallel().tween_method(_set_edge, 0.0, 0.42, 0.8)
	t.parallel().tween_callback(_pop_panel).set_delay(0.55)
	t.tween_interval(0.1)
	for i in int(award.get("stars", 0)):
		t.tween_callback(Audio.play.bind(Audio.RICE_GEM_COLLECT))
		t.tween_method(_set_star.bind(i), 0.0, 1.0, STAR_STEP_SEC)
	if not award.is_empty():
		t.tween_callback(func() -> void: reward.modulate.a = 1.0)
		t.tween_method(_count_jade, 0, int(award.get("jade", 0)), 0.6)
	t.tween_interval(0.2)
	t.tween_callback(_after_rewards)


func play_lose() -> void:
	_begin({})
	report.visible = true
	report.modulate.a = 0.0
	_set_grade(0.0, UiPalette.HUD_DANGER)
	_make_cracks()
	_make_shards()
	_shatter_pearl()
	_wilt_plants()
	_shake_camera()
	Audio.play(Audio.BATTLE_START)
	_ambient("_shard_t", SHARD_SEC)
	var t := _new_tween()
	t.tween_property(self, "_crack", 1.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_drain, 0.0, 0.88, 0.9)
	t.parallel().tween_method(_set_edge, 0.0, 0.62, 1.1)
	t.parallel().tween_callback(_slam_panel).set_delay(0.85)
	t.tween_interval(0.35)
	t.tween_property(report, "modulate:a", 1.0, 0.25)
	t.tween_interval(0.25)
	t.tween_callback(_finish)


## Any input during the sequence lands on the final frame at once.
func skip() -> void:
	if not _playing or is_instance_valid(_reveal):
		return
	_kill()
	_wave = 1.0
	_rays = 1.0
	_crack = 1.0
	_shard_t = 1.0
	_spark_t = 1.0
	if _won:
		for i in int(_award.get("stars", 0)):
			_star_pop[i] = 1.0
			_burst[i] = 1.0
		_count_jade(int(_award.get("jade", 0)))
		reward.modulate.a = 1.0
		_set_edge(0.42)
		if not (_award.get("awakened", []) as Array).is_empty():
			panel.scale = Vector2.ONE
			panel.modulate.a = 1.0
			_after_rewards()
			return
	else:
		_set_drain(0.88)
		_set_edge(0.62)
		report.modulate.a = 1.0
	panel.scale = Vector2.ONE
	panel.modulate.a = 1.0
	panel.rotation = 0.0
	_finish()


func _gui_input(event: InputEvent) -> void:
	if _playing and event is InputEventMouseButton and event.pressed:
		skip()
		accept_event()


func _begin(award: Dictionary) -> void:
	reset()
	_award = award
	_playing = true
	_wave = 0.0
	_rays = 0.0
	_crack = 0.0
	_shard_t = 0.0
	_spark_t = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_origin = _pearl_on_screen()
	_grade.visible = true
	_back.running = true
	_front.running = true
	panel.modulate.a = 0.0
	buttons.modulate.a = 0.0
	reward.modulate.a = 0.0
	chronicle.modulate.a = 0.0


## Long background motion gets its own Tween, so it never holds up the timeline.
func _ambient(property: String, seconds: float) -> void:
	_side = create_tween()
	_side.tween_property(self, property, 1.0, seconds)


func _new_tween() -> Tween:
	_kill()
	_tween = create_tween()
	return _tween


func _kill() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _kill_ambient() -> void:
	if _side != null:
		_side.kill()
		_side = null


func _after_rewards() -> void:
	var seeds: Array = _award.get("awakened", [])
	if seeds.is_empty():
		_finish()
		return
	panel.modulate.a = 0.0 # the reveal has the stage to itself
	_front.running = false
	_reveal = SeedReveal.new()
	get_parent().add_child(_reveal)
	_reveal.z_index = 5
	_reveal.finished.connect(_after_reveal)
	_reveal.play(seeds, _origin)


func _after_reveal() -> void:
	_front.running = true
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.2)
	_finish()


## The Chronicle writes itself, then the buttons arrive.
func _finish() -> void:
	_playing = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _new_tween()
	if chronicle.visible:
		chronicle.modulate.a = 1.0
		chronicle.visible_ratio = 0.0
		t.tween_property(chronicle, "visible_ratio", 1.0, chronicle.text.length() / 70.0)
	t.tween_property(buttons, "modulate:a", 1.0, 0.25)
	t.tween_callback(func() -> void:
		_front.running = false
		finished.emit())


func _pop_panel() -> void:
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 0.72
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(panel, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _slam_panel() -> void:
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * 1.5
	panel.rotation = -0.05
	var t := create_tween()
	t.tween_property(panel, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(panel, "rotation", 0.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_star(v: float, index: int) -> void:
	_star_pop[index] = v
	_burst[index] = v


func _count_jade(value: int) -> void:
	reward.text = tr("+%d Jade") % value


func _set_grade(drain: float, color: Color) -> void:
	_grade_mat.set_shader_parameter("drain", drain)
	_grade_mat.set_shader_parameter("edge", 0.0)
	_grade_mat.set_shader_parameter("edge_color", color)


func _set_drain(v: float) -> void:
	_grade_mat.set_shader_parameter("drain", v)


func _set_edge(v: float) -> void:
	_grade_mat.set_shader_parameter("edge", v)


# ------------------------------------------------------------------- world ---

func _house() -> Node3D:
	return get_tree().get_first_node_in_group("CentralHouse") as Node3D


func _camera() -> Camera3D:
	return get_viewport().get_camera_3d()


func _pearl_on_screen() -> Vector2:
	var house := _house()
	var camera := _camera()
	if house == null or camera == null:
		return get_viewport_rect().size * 0.5
	var at := camera.unproject_position(house.global_position + Vector3.UP * PEARL_HEIGHT)
	return at * get_viewport_rect().size / Vector2(get_viewport().get_visible_rect().size)


func _cheer_plants() -> void:
	var house := _house()
	for node in get_tree().get_nodes_in_group("Plants"):
		var plant := node as Node3D
		if plant == null or house == null:
			continue
		var delay := plant.global_position.distance_to(house.global_position) * 0.03
		var base := plant.scale
		var t := plant.create_tween()
		t.tween_interval(delay)
		for hop in 2:
			t.tween_property(plant, "scale", base * Vector3(0.82, 1.3, 0.82), 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.tween_property(plant, "scale", base, 0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _wilt_plants() -> void:
	for node in get_tree().get_nodes_in_group("Plants"):
		var plant := node as Node3D
		if plant == null:
			continue
		var t := plant.create_tween()
		t.tween_interval(randf() * 0.35)
		t.tween_property(plant, "scale", plant.scale * Vector3(1.16, 0.62, 1.16), 0.5).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _shatter_pearl() -> void:
	var house := _house()
	if house == null:
		return
	var bar := house.get("health_sprite") as Node3D
	if bar != null:
		bar.visible = false
	var visuals := house.get_node_or_null("Visuals") as Node3D
	if visuals != null:
		var t := visuals.create_tween()
		t.tween_property(visuals, "scale", Vector3(1.2, 0.8, 1.2), 0.08)
		t.tween_property(visuals, "scale", Vector3(1.0, 0.25, 1.0), 0.32).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _push_camera() -> void:
	var rig := get_tree().current_scene.find_child("ThirdPersonCamera", true, false)
	if rig == null or rig.get("_target_arm_length") == null:
		return
	var t := rig.create_tween()
	t.tween_property(rig, "_target_arm_length", float(rig.get("_target_arm_length")) * CAMERA_PUSH, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _shake_camera() -> void:
	var camera := _camera()
	if camera == null:
		return
	var t := camera.create_tween()
	for i in SHAKE_STEPS:
		var fade := 1.0 - float(i) / SHAKE_STEPS
		t.tween_property(camera, "h_offset", randf_range(-1.0, 1.0) * SHAKE_METRES * fade, 0.045)
		t.parallel().tween_property(camera, "v_offset", randf_range(-1.0, 1.0) * SHAKE_METRES * fade, 0.045)
	t.tween_property(camera, "h_offset", 0.0, 0.08)
	t.parallel().tween_property(camera, "v_offset", 0.0, 0.08)


# ----------------------------------------------------------------- painting ---

func _make_sparks() -> void:
	_sparks.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 417
	for i in SPARKS:
		_sparks.append({"a": rng.randf() * TAU, "d": rng.randf_range(0.08, 0.42), "r": rng.randf_range(140.0, 620.0), "s": rng.randf_range(3.0, 7.0), "p": rng.randf()})


func _make_cracks() -> void:
	_crack_paths.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 911
	var reach := get_viewport_rect().size.length()
	for i in CRACKS:
		var a := TAU * i / CRACKS + rng.randf_range(-0.2, 0.2)
		var at := _origin
		var path := PackedVector2Array([at])
		var travelled := 0.0
		var limit := reach * rng.randf_range(0.38, 0.8)
		while travelled < limit:
			a += rng.randf_range(-0.55, 0.55)
			var step := rng.randf_range(38.0, 88.0)
			at += Vector2(cos(a), sin(a)) * step
			travelled += step
			path.append(at)
		_crack_paths.append(path)


func _make_shards() -> void:
	_shards.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for i in SHARDS:
		var a := rng.randf() * TAU
		_shards.append({"v": Vector2(cos(a), sin(a)) * rng.randf_range(220.0, 620.0) + Vector2(0.0, -180.0), "s": rng.randf_range(6.0, 17.0), "spin": rng.randf_range(-7.0, 7.0), "p": rng.randf() * TAU})


func _paint_back(p: HudPainter) -> void:
	if _won:
		var spin := Time.get_ticks_msec() / 1000.0 * 0.12
		p.rays(_origin, 1500.0, 16, spin, 0.085, Color(UiPalette.HUD_DAWN, 0.34 * _rays))
		p.rays(_origin, 760.0, 11, -spin * 1.7, 0.06, Color(UiPalette.HUD_FLASH, 0.22 * _rays))
		if _wave > 0.0 and _wave < 1.0:
			var r := lerpf(30.0, 1100.0, _wave)
			p.stroke(HudPainter.circle(_origin, r), lerpf(38.0, 3.0, _wave), Color(UiPalette.HUD_FLASH, (1.0 - _wave) * 0.8))
		for s in _sparks:
			var t := fmod(_spark_t * 3.0 + float(s["p"]), 1.0)
			var at: Vector2 = _origin + Vector2(cos(s["a"]), sin(s["a"])) * float(s["r"]) * t + Vector2(0.0, -130.0 * t)
			var alpha := sin(t * PI)
			p.fill(HudPainter.chamfered(Rect2(at, Vector2.ONE * float(s["s"])), float(s["s"]) * 0.5), Color(UiPalette.HUD_DAWN, alpha))
		return
	for path in _crack_paths:
		var count := int(ceil(path.size() * _crack))
		if count < 2:
			continue
		var cut := path.slice(0, count)
		p.line(cut, 5.5, UiPalette.HUD_EDGE)
		p.line(cut, 1.6, UiPalette.HUD_DANGER_TEXT)
	if _shard_t < 1.0:
		var t := _shard_t * 1.5
		for s in _shards:
			var at: Vector2 = _origin + (s["v"] as Vector2) * t + Vector2(0.0, 760.0 * t * t)
			var a := float(s["p"]) + float(s["spin"]) * t
			var size := float(s["s"])
			var tri := PackedVector2Array([at + Vector2(cos(a), sin(a)) * size, at + Vector2(cos(a + 2.2), sin(a + 2.2)) * size, at + Vector2(cos(a + 4.1), sin(a + 4.1)) * size * 0.7])
			p.fill(tri, Color(UiPalette.HUD_PEARL_TOP, 1.0 - _shard_t), Color(UiPalette.HUD_PEARL_BOT, 1.0 - _shard_t))


func _paint_front(p: HudPainter) -> void:
	if not _won or not star_row.visible or panel.modulate.a <= 0.01:
		return
	var centre := star_row.get_global_rect().get_center()
	var total := _star_pop.size()
	for i in total:
		var at := centre + Vector2((i - (total - 1) * 0.5) * STAR_GAP, 0.0)
		var pop: float = _star_pop[i]
		p.fill(HudPainter.star(at, STAR_RADIUS, STAR_RADIUS * 0.46), UiPalette.HUD_LOCKED_TOP)
		p.stroke(HudPainter.star(at, STAR_RADIUS, STAR_RADIUS * 0.46), 2.0, UiPalette.HUD_EDGE)
		if pop <= 0.0:
			continue
		# Falls in large, stamps, settles; sparks fly from the stamp.
		var scale_now := 1.0 + (1.0 - pop) * 1.7 if pop < 0.72 else 1.0 + sin((pop - 0.72) / 0.28 * PI) * 0.16
		var r := STAR_RADIUS * scale_now
		var shape := HudPainter.star(at, r, r * 0.46)
		p.glow(shape, Color(UiPalette.HUD_DAWN, 0.5 * pop), 12.0)
		p.fill(shape, UiPalette.HUD_FLASH, UiPalette.HUD_DAWN)
		p.stroke(shape, 2.0, UiPalette.HUD_EDGE)
		var burst: float = _burst[i]
		if burst > 0.55 and burst < 1.0:
			var b := (burst - 0.55) / 0.45
			for k in 8:
				var a := TAU * k / 8.0
				var d := Vector2(cos(a), sin(a))
				p.line(PackedVector2Array([at + d * (STAR_RADIUS + 18.0 * b), at + d * (STAR_RADIUS + 34.0 * b)]), 3.0, Color(UiPalette.HUD_ACCENT, 1.0 - b))
