class_name HudMenuButton
extends HudHit

# A large lacquer menu button: painted by HudCanvas, with real keyboard and gamepad focus
# (unlike the HUD's click-only HudHit). The mouse moves focus too, so hover and focus
# are one highlight. `primary` gets the gold fill. The caption is the Button's own text.

const CUT := 8.0

var primary := false


## Primary is also a text colour (seal ink on the gold fill), so changing it after
## _ready must refresh the overrides.
func set_primary(on: bool) -> void:
	primary = on
	_apply_ink()


func _apply_ink() -> void:
	var ink := UiPalette.HUD_SEAL_INK if primary else UiPalette.HUD_INK
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		add_theme_color_override(state, ink)
	add_theme_color_override("font_pressed_color", UiPalette.HUD_SEAL_INK)


func _init() -> void:
	super()
	focus_mode = Control.FOCUS_ALL
	add_theme_font_override("font", UiPalette.hud_font())
	add_theme_font_size_override("font_size", 22)
	focus_entered.connect(HudCanvas.dirty)
	focus_exited.connect(HudCanvas.dirty)
	mouse_entered.connect(grab_focus)


func _ready() -> void:
	_apply_ink()
	HudCanvas.register(self, 90)


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	var rect := Rect2(Vector2.ZERO, size)
	var shape := HudPainter.chamfered(rect, CUT)
	var lit := has_focus() or hovered
	if lit:
		p.glow(HudPainter.offset(shape, 3.0), Color(UiPalette.HUD_ACCENT, 0.5), 9.0)
	var top := UiPalette.HUD_ACCENT if primary else (UiPalette.HUD_LACQUER_LIT if lit else UiPalette.HUD_LACQUER_TOP)
	var bottom := UiPalette.HUD_GOLD if primary else UiPalette.HUD_LACQUER_BOT
	if is_pressed():
		top = UiPalette.HUD_GOLD
		bottom = UiPalette.HUD_GOLD
	p.lacquer(shape, top, bottom, UiPalette.HUD_ACCENT if lit else UiPalette.HUD_GOLD)
	var inlay := UiPalette.HUD_SEAL_INK if primary else UiPalette.HUD_GOLD
	inlay.a = 0.6
	p.stroke(HudPainter.chamfered(rect.grow(-4.0), 5.0), 1.0, inlay)
