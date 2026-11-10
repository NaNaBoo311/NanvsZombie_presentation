class_name HudBanner
extends Control

# Battle banners: a lacquer plaque that opens with a little overshoot, with the Warden's
# line on a slip under it. Solid backing means the text never fights the scene. Red
# is for huge waves only; notices (LAN) use the cool spirit tone. HUD decides what to
# say. Painted by HudCanvas, redrawn only while it opens or closes.

enum Kind { NORMAL, DANGER, NOTICE }

const TOP := 150.0
const HOLD_SEC := 3.0
const SLIP_HOLD_SEC := 3.5
const OPEN_SEC := 0.28
const CLOSE_SEC := 0.18
const SIDE_PAD := 44.0
const PLAQUE_HEIGHT := 62.0
const SLIP_GAP := 12.0
const SLIP_WIDTH := 520.0

var _title: Label
var _slip: Label
var _kind := Kind.NORMAL
var _open := 0.0
var _slip_on := false
var _tween: Tween = null
var _slip_tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = UiPalette.hud_label(32)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.visible = false
	add_child(_title)
	_slip = UiPalette.hud_label(18, UiPalette.HUD_INK_SOFT)
	_slip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slip.visible = false
	add_child(_slip)
	HudCanvas.register(self, 60)


func show_banner(text: String, kind: int = Kind.NORMAL, auto_hide: bool = true) -> void:
	_kind = kind
	_title.text = text
	_title.add_theme_font_size_override("font_size", 24 if kind == Kind.NOTICE else 32)
	_title.add_theme_color_override("font_color", _ink())
	_title.visible = true
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(_set_open, _open, 1.0, OPEN_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if auto_hide:
		_tween.tween_interval(HOLD_SEC)
		_tween.tween_method(_set_open, 1.0, 0.0, CLOSE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_callback(_finish_close)


func hide_banner() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
	_finish_close()


## The Warden's line under the banner, for as long as the banner shows.
func show_slip(text: String) -> void:
	_slip.text = "“%s”" % text
	_slip_on = true
	_slip.visible = true
	if _slip_tween != null:
		_slip_tween.kill()
	_slip_tween = create_tween()
	_slip_tween.tween_interval(SLIP_HOLD_SEC)
	_slip_tween.tween_callback(hide_slip)
	HudCanvas.dirty()


func hide_slip() -> void:
	_slip_on = false
	_slip.visible = false
	HudCanvas.dirty()


func _finish_close() -> void:
	_set_open(0.0)
	_title.visible = false


func _set_open(value: float) -> void:
	_open = value
	_title.modulate.a = clampf(value * 1.6 - 0.6, 0.0, 1.0)
	HudCanvas.dirty()


func _ink() -> Color:
	match _kind:
		Kind.DANGER:
			return UiPalette.HUD_DANGER_INK
		Kind.NOTICE:
			return UiPalette.HUD_SPIRIT_INK
	return UiPalette.HUD_INK


func paint_hud(p: HudPainter) -> void:
	var centre_x := get_global_rect().get_center().x
	var y := get_global_rect().position.y + TOP
	p.xf = Transform2D.IDENTITY
	if _open > 0.01 and _title.visible:
		var width := _title.get_minimum_size().x + SIDE_PAD * 2.0
		var rect := Rect2(centre_x - width * 0.5, y, width, PLAQUE_HEIGHT)
		_title.position = rect.position - position
		_title.size = rect.size
		var drawn := rect
		drawn.size.x = maxf(width * _open, 12.0)
		drawn.position.x = centre_x - drawn.size.x * 0.5
		_paint_plaque(p, drawn)
	if _slip_on:
		_slip.custom_minimum_size.x = SLIP_WIDTH
		_slip.size = Vector2(SLIP_WIDTH, 0.0)
		var height := _slip.get_minimum_size().y
		var slip_rect := Rect2(centre_x - (SLIP_WIDTH + 28.0) * 0.5, y + PLAQUE_HEIGHT + SLIP_GAP, SLIP_WIDTH + 28.0, height + 16.0)
		_slip.position = slip_rect.position + Vector2(14.0, 8.0) - position
		p.lacquer(HudPainter.chamfered(slip_rect, 5.0), UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)


func _paint_plaque(p: HudPainter, rect: Rect2) -> void:
	var shape := HudPainter.chamfered(rect, 7.0)
	var top := UiPalette.HUD_LACQUER_TOP
	var bottom := UiPalette.HUD_LACQUER_BOT
	if _kind == Kind.DANGER:
		top = UiPalette.HUD_DANGER
		bottom = UiPalette.HUD_DANGER
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_DANGER, 0.7), 12.0)
	elif _kind == Kind.NOTICE:
		top = UiPalette.HUD_SPIRIT
		bottom = UiPalette.HUD_SPIRIT
	p.lacquer(shape, top, bottom)
	p.stroke(HudPainter.chamfered(rect.grow(-4.0), 4.0), 1.0, UiPalette.HUD_GOLD)
