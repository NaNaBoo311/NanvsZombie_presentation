class_name ConceptFacingDemo
extends Control

# The 360° exhibit: a top-down lawn around the Dragon Pearl with eight home
# facings. Clicking a facing (or pressing 1–8 while this is the live exhibit)
# turns the plant's cone; spirits sit on the four spawn gates to show what the
# choice is for. Painted with HudPainter in one draw call and redrawn only on
# change, so the diagram costs nothing while the presenter talks.

signal facing_changed(index: int)

const FACINGS := 8
## Home facing 0 points east, then clockwise in screen space.
const START_ANGLE := 0.0
const CONE_HALF := 0.32

var facing := 0:
	set(value):
		var next: int = posmod(value, FACINGS)
		if next == facing:
			return
		facing = next
		queue_redraw()
		facing_changed.emit(facing)

var _hover := -1


func _ready() -> void:
	custom_minimum_size = Vector2(360.0, 320.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process(false)


func set_facing(index: int) -> void:
	facing = index


func step(direction: int) -> void:
	facing += direction


func facing_angle() -> float:
	return START_ANGLE + TAU * float(facing) / float(FACINGS)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hit := _facing_at(event.position)
		if hit != _hover:
			_hover = hit
			queue_redraw()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var hit := _facing_at(mb.position)
			if hit >= 0:
				Audio.play(Audio.UI_CLICK)
				set_facing(hit)
			accept_event()


func _facing_at(position: Vector2) -> int:
	var c := size * 0.5
	var offset := position - c
	var reach := minf(size.x, size.y) * 0.44
	if offset.length() > reach:
		return -1
	var angle := offset.angle() - START_ANGLE
	return posmod(roundi(angle / (TAU / FACINGS)), FACINGS)


func _draw() -> void:
	var painter := HudPainter.new()
	painter.begin(1.0)
	_paint(painter)
	if not painter.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),
			painter.indices, painter.points, painter.colors)


func _paint(p: HudPainter) -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.355
	var lawn := HudPainter.circle(c, r * 0.82)
	var outer := HudPainter.circle(c, r)

	p.fill(outer, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	p.glow(outer, Color(UiPalette.HUD_GOLD, 0.16), 18.0)
	p.stroke(outer, 1.4, Color(UiPalette.HUD_GOLD, 0.46))
	p.fill(lawn, UiPalette.HUD_HEALTH.darkened(0.56), UiPalette.HUD_HEALTH.darkened(0.72))
	p.stroke(lawn, 1.2, Color(UiPalette.HUD_GOLD, 0.3))

	# Tile grid, clipped to the lawn by drawing chords.
	for i in range(-3, 4):
		var d := r * 0.82 * float(i) / 3.5
		var half := sqrt(maxf(r * r * 0.82 * 0.82 - d * d, 0.0))
		if half <= 0.0:
			continue
		var a := Color(UiPalette.HUD_GOLD, 0.12)
		p.line(PackedVector2Array([c + Vector2(-half, d), c + Vector2(half, d)]), 0.7, a)
		p.line(PackedVector2Array([c + Vector2(d, -half), c + Vector2(d, half)]), 0.7, a)
	# The Pearl's dais and gem.
	p.fill(HudPainter.circle(c, r * 0.22), Color(UiPalette.HUD_EDGE, 0.55))
	p.stroke(HudPainter.circle(c, r * 0.22), 1.0, Color(UiPalette.HUD_GOLD, 0.55))
	p.glow(HudPainter.circle(c, r * 0.1), Color(UiPalette.HUD_FACET_LIGHT, 0.55), 26.0)
	p.gem(c, r * 0.1)

	# Four spawn gates: chevrons on the ring, pointing at the Pearl.
	for i in 4:
		var angle := START_ANGLE + TAU * float(i) / 4.0 + PI * 0.25
		var dir := Vector2(cos(angle), sin(angle))
		var side := Vector2(-dir.y, dir.x)
		var at := c + dir * r * 0.96
		var tip := at - dir * r * 0.1
		var gate := PackedVector2Array([at + side * r * 0.08, tip, at - side * r * 0.08])
		p.fill(gate, UiPalette.HUD_DANGER_TEXT)
		p.stroke(gate, 1.0, Color(UiPalette.HUD_EDGE, 0.8))
		p.fill(HudPainter.circle(c + dir * r * 0.82 + side * r * 0.09, r * 0.025),
			UiPalette.HUD_DANGER_TEXT)

	# The cone the selected plant covers.
	var angle := facing_angle()
	var dir := Vector2(cos(angle), sin(angle))
	var reach := r * 0.66
	var left := c + Vector2(cos(angle - CONE_HALF), sin(angle - CONE_HALF)) * reach
	var right := c + Vector2(cos(angle + CONE_HALF), sin(angle + CONE_HALF)) * reach
	var cone := PackedVector2Array([c, left, right])
	p.fill(cone, Color(UiPalette.HUD_ACCENT, 0.18))
	p.line(PackedVector2Array([c, left]), 1.2, Color(UiPalette.HUD_ACCENT, 0.5))
	p.line(PackedVector2Array([c, right]), 1.2, Color(UiPalette.HUD_ACCENT, 0.5))
	p.line(HudPainter.arc(c, reach, angle - CONE_HALF, angle + CONE_HALF, 18), 1.2,
		Color(UiPalette.HUD_ACCENT, 0.5))

	# The plant sits at the cone's mouth and faces the same way.
	var plant := c + dir * r * 0.3
	for i in 6:
		var a := angle + TAU * float(i) / 6.0
		p.fill(HudPainter.circle(plant + Vector2(cos(a), sin(a)) * r * 0.055, r * 0.04),
			UiPalette.HUD_FACET_SOFT)
	p.fill(HudPainter.circle(plant, r * 0.05), UiPalette.HUD_FACET_MID)
	p.stroke(HudPainter.circle(plant, r * 0.05), 1.0, UiPalette.HUD_FACET_EDGE)

	# Eight click targets on the facing ring, outside the play area.
	for i in FACINGS:
		var a := START_ANGLE + TAU * float(i) / float(FACINGS)
		var at := c + Vector2(cos(a), sin(a)) * r * 1.12
		var chosen := i == facing
		var hovered := i == _hover
		var dot_r := r * (0.078 if chosen else 0.062)
		if hovered and not chosen:
			p.glow(HudPainter.circle(at, dot_r), Color(UiPalette.HUD_ACCENT, 0.35), 8.0)
		p.fill(HudPainter.circle(at, dot_r),
			UiPalette.HUD_GOLD if chosen else UiPalette.HUD_LACQUER_TOP,
			UiPalette.HUD_GOLD if chosen else UiPalette.HUD_LACQUER_BOT)
		p.stroke(HudPainter.circle(at, dot_r), 1.1,
			UiPalette.HUD_ACCENT if chosen or hovered else Color(UiPalette.HUD_GOLD, 0.62))
		if chosen:
			p.line(PackedVector2Array([plant, at]), 1.0, Color(UiPalette.HUD_ACCENT, 0.34))
