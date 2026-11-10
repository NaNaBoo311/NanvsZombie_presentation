class_name PearlMedallion
extends Control

# Pearl health on the HUD, which stays readable when the camera has left the pearl's
# in-world bar behind. A ring counts down around the Pearl, cracks appear below 80%
# and 50%, and in a level three stars show what a win would pay right now
# (GameManager.earned_stars). The ring turns red only when low or struck: red means
# danger. Painted by HudCanvas; signal-driven, a Tween only for the hit flash.

const PANEL_SIZE := Vector2(68.0, 86.0)
const CENTRE := Vector2(34.0, 34.0)
const LOW := 0.34

var _health := 1.0
var _flash := 0.0
var _hit: HudHit
var _flash_tween: Tween = null


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit = HudHit.new()
	_hit.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_hit.position = Vector2.ZERO
	_hit.size = PANEL_SIZE
	add_child(_hit)
	HudCanvas.register(self, 40)
	EventBus.house_health_changed.connect(_on_health_changed)
	EventBus.round_state_changed.connect(_on_round_state_changed)
	_on_round_state_changed(GameManager.round_state)
	_apply_health(GameManager.house_health, GameManager.max_house_health)


func _on_health_changed(current: int, maximum: int) -> void:
	var before := _health
	_apply_health(current, maximum)
	if _health < before:
		if _flash_tween != null:
			_flash_tween.kill()
		_flash = 1.0
		_flash_tween = create_tween()
		_flash_tween.tween_property(self, "_flash", 0.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		HudCanvas.animate(0.5)


func _apply_health(current: int, maximum: int) -> void:
	_health = clampf(float(current) / float(maxi(maximum, 1)), 0.0, 1.0)
	_hit.set_tip(tr("Sacred Pearl"), tr("%d of %d health") % [current, maximum])
	HudCanvas.dirty()


func _on_round_state_changed(state: String) -> void:
	visible = state in ["prepare", "setup", "wave", "sandbox"]
	HudCanvas.dirty()


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	var shape := HudPainter.octagon(CENTRE, 32.0)
	if _flash > 0.0:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_DANGER, 0.8 * _flash), 9.0)
	elif _hit.hovered:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_GOLD, 0.35), 6.0)
	p.lacquer(shape, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	p.stroke(HudPainter.circle(CENTRE, 24.0), 6.5, UiPalette.HUD_RING_TRACK)
	if _health > 0.0:
		var ring := UiPalette.HUD_DANGER if _health < LOW or _flash > 0.25 else UiPalette.HUD_HEALTH
		var steps := maxi(4, int(48.0 * _health))
		p.line(HudPainter.arc(CENTRE, 24.0, -PI * 0.5, -PI * 0.5 + TAU * _health, steps), 5.5, ring)
	var orb := HudPainter.circle(CENTRE, 17.0)
	p.fill(orb, UiPalette.HUD_PEARL_TOP, UiPalette.HUD_PEARL_BOT)
	p.stroke(orb, 1.5, UiPalette.HUD_EDGE)
	p.fill(HudPainter.circle(CENTRE + Vector2(-6.0, -7.0), 3.6), UiPalette.HUD_PEARL_TOP)
	if _health < 0.8:
		p.line(PackedVector2Array([CENTRE + Vector2(15.0, -7.0), CENTRE + Vector2(10.0, -6.0), CENTRE + Vector2(9.0, -3.0), CENTRE + Vector2(5.0, -2.0)]), 1.3, UiPalette.HUD_EDGE)
	if _health < 0.5:
		p.line(PackedVector2Array([CENTRE + Vector2(-14.0, 9.0), CENTRE + Vector2(-9.0, 6.0), CENTRE + Vector2(-7.0, 10.0), CENTRE + Vector2(-2.0, 8.0), CENTRE + Vector2(0.0, 12.0)]), 1.3, UiPalette.HUD_EDGE)
	if GameManager.level_active:
		_paint_stars(p)


func _paint_stars(p: HudPainter) -> void:
	var earned: int = GameManager.earned_stars()
	for i in Progress.MAX_STARS:
		var k := i - 1
		var at := CENTRE + Vector2(k * 21.0, 39.0 - absi(k) * 4.0)
		var points := HudPainter.star(at, 9.5, 4.4)
		p.fill(points, UiPalette.HUD_DAWN if i < earned else UiPalette.HUD_LOCKED_TOP)
		p.stroke(points, 1.2, UiPalette.HUD_EDGE)
