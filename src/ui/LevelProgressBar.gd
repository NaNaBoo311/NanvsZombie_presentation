class_name LevelProgressBar
extends Control

# The Leyline: level progress as a cord running from night to dawn. A small lantern
# walks along it as spirits fall, huge waves are red flags (grey once passed), and it
# ends at a sunrise, which is where "Dawn Breaks" pays off. Painted by HudCanvas;
# the kill count is in its tooltip. Signal-driven: tweens only while something moves.
# Unlit during setup, lit during "wave" of a picked level; hidden in menus and sandbox.
# Flag fractions come from LevelDB.flag_fractions via level_flags_defined.

const PANEL_SIZE := Vector2(252.0, 44.0)
const CORD_LEFT := 16.0
const CORD_RIGHT := 216.0
const CORD_Y := 24.0
const CORD_STEPS := 16
const KNOTS := 9
## The last flag stops short of the sunrise so the two never overlap.
const FLAG_LIMIT := 0.9

var _flags: Array[float] = []
var _progress := 0.0
var _shown := 0.0
var _danger := 0.0
var _lit := false
var _hit: HudHit
var _move_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_hit = HudHit.new()
	_hit.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hit)
	HudCanvas.register(self, 30)
	if EventBus:
		EventBus.level_flags_defined.connect(_on_flags_defined)
		EventBus.level_progress_changed.connect(_on_progress_changed)
		EventBus.round_state_changed.connect(_on_round_state_changed)
		EventBus.huge_wave_incoming.connect(_on_huge_wave)


func _on_flags_defined(fractions: Array) -> void:
	_flags.clear()
	for f in fractions:
		_flags.append(clampf(float(f), 0.0, 1.0))
	_set_progress(0, _infer_total(), 0.0)


func _infer_total() -> int:
	if GameManager and GameManager.get("level_total") != null:
		return int(GameManager.level_total)
	return 0


func _on_progress_changed(killed: int, total: int, progress: float) -> void:
	_set_progress(killed, total, progress)


func _set_progress(killed: int, total: int, progress: float) -> void:
	_progress = clampf(progress, 0.0, 1.0)
	if is_instance_valid(_hit):
		_hit.set_tip(tr("The Leyline"), tr("%d of %d spirits calmed") % [killed, total] if total > 0 else "")
	if _move_tween != null:
		_move_tween.kill()
	if not visible:
		_shown = _progress
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "_shown", _progress, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	HudCanvas.animate(0.34)


func _on_round_state_changed(state: String) -> void:
	var level: bool = GameManager != null and bool(GameManager.get("level_active"))
	visible = level and (state == "wave" or state == "setup")
	_lit = state == "wave"
	if visible:
		_replay_progress()
	HudCanvas.dirty()


## R-restart rebuilds the HUD mid-level: re-pull killed/total from GameManager.
func _replay_progress() -> void:
	if GameManager == null:
		return
	var total := int(GameManager.get("level_total"))
	var killed := int(GameManager.get("level_killed"))
	var progress := 0.0
	if total > 0:
		progress = clampf(float(killed) / float(total), 0.0, 1.0)
	_shown = progress
	_on_progress_changed(killed, total, progress)


## Red pulse around the cord while a huge wave lands (transient, zero idle cost).
func _on_huge_wave(_wave_idx: int) -> void:
	if not visible:
		return
	var tween := create_tween()
	tween.tween_property(self, "_danger", 1.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.6)
	tween.tween_property(self, "_danger", 0.0, 0.6)
	HudCanvas.animate(2.5)


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	var shape := HudPainter.chamfered(Rect2(Vector2.ZERO, PANEL_SIZE), 6.0)
	if _danger > 0.0:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_DANGER, 0.75 * _danger), 9.0)
	elif _hit.hovered:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_GOLD, 0.35), 6.0)
	p.lacquer(shape, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	var track := PackedVector2Array([Vector2(CORD_LEFT, CORD_Y), Vector2(CORD_RIGHT, CORD_Y)])
	p.line(track, 8.0, UiPalette.HUD_EDGE)
	p.line(track, 4.5, UiPalette.HUD_LOCKED_TOP.lerp(UiPalette.HUD_GOLD, 0.22))
	for i in range(1, KNOTS):
		var knot := Vector2(lerpf(CORD_LEFT, CORD_RIGHT, float(i) / KNOTS), CORD_Y)
		p.fill(HudPainter.octagon(knot, 1.5), UiPalette.HUD_EDGE)
	var walker := Vector2(_cord_x(_shown), CORD_Y)
	if _lit and _shown > 0.005:
		var path := PackedVector2Array()
		var tints := PackedColorArray()
		for i in CORD_STEPS + 1:
			var t := _shown * float(i) / CORD_STEPS
			path.append(Vector2(_cord_x(t), CORD_Y))
			tints.append(_cord_tint(t))
		p.line(path, 5.5, UiPalette.HUD_DAWN, tints)
	for f in _flags:
		_paint_flag(p, minf(f, FLAG_LIMIT), _lit and _shown + 0.001 >= f)
	if _lit:
		_paint_lantern(p, walker)
	_paint_sunrise(p, Vector2(CORD_RIGHT + 12.0, CORD_Y + 3.0))


func _cord_x(t: float) -> float:
	return lerpf(CORD_LEFT, CORD_RIGHT, t)


func _cord_tint(t: float) -> Color:
	if t < 0.55:
		return UiPalette.HUD_NIGHT.lerp(UiPalette.HUD_DUSK, t / 0.55)
	return UiPalette.HUD_DUSK.lerp(UiPalette.HUD_DAWN, (t - 0.55) / 0.45)


func _paint_flag(p: HudPainter, t: float, passed: bool) -> void:
	var foot := Vector2(_cord_x(t), CORD_Y)
	p.line(PackedVector2Array([foot, foot + Vector2(0.0, -15.0)]), 1.6, UiPalette.HUD_EDGE)
	var cloth := PackedVector2Array([foot + Vector2(0.0, -17.0), foot + Vector2(13.0, -12.0), foot + Vector2(0.0, -6.0)])
	p.fill(cloth, UiPalette.HUD_LOCKED_TOP if passed else UiPalette.HUD_DANGER)
	p.stroke(cloth, 1.1, UiPalette.HUD_GOLD if passed else UiPalette.HUD_EDGE)


func _paint_lantern(p: HudPainter, c: Vector2) -> void:
	p.fill(HudPainter.circle(c, 11.0), Color(UiPalette.HUD_DAWN, 0.22))
	var body := HudPainter.octagon(c, 8.0)
	p.fill(body, UiPalette.HUD_DAWN)
	p.stroke(body, 1.4, UiPalette.HUD_EDGE)


func _paint_sunrise(p: HudPainter, c: Vector2) -> void:
	var colour := UiPalette.HUD_DAWN if _lit else UiPalette.HUD_LOCKED_TOP.lerp(UiPalette.HUD_GOLD, 0.3)
	var dome := HudPainter.arc(c, 11.0, PI, TAU, 14)
	p.fill(dome, colour)
	p.stroke(dome, 1.3, UiPalette.HUD_EDGE)
	for a in [PI + 0.5, PI + 1.1, PI + 2.0, PI + 2.6]:
		var d := Vector2(cos(a), sin(a))
		p.line(PackedVector2Array([c + d * 13.5, c + d * 17.0]), 1.5, colour)
