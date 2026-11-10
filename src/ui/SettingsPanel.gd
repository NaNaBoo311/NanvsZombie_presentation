class_name SettingsPanel
extends Control

# The Settings dialog, used by the title and the pause menu: three volume sliders and
# fullscreen, all live and saved as they change (GameSettings). Esc or Back closes it and
# returns focus to the button that opened it. A modal overlay outside the HUD canvas, so
# it paints its own panel: one draw while open, none otherwise. Works while the tree
# is paused. Keyboard and gamepad reach every control.

const PANEL_SIZE := Vector2(480.0, 312.0)
const ROW_LABEL_W := 150.0

var _return_focus: Control = null
var _first: Control = null
var _fullscreen: CheckButton
var _back: Button
var _painter := HudPainter.new()
var _sheet: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 20
	_build()


func open() -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	_fullscreen.set_pressed_no_signal(GameSettings.is_fullscreen())
	visible = true
	_first.grab_focus()


func close() -> void:
	visible = false
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = UiPalette.HUD_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_sheet = Control.new()
	_sheet.name = "Sheet"
	_sheet.set_anchors_preset(Control.PRESET_CENTER)
	_sheet.offset_left = -PANEL_SIZE.x * 0.5
	_sheet.offset_right = PANEL_SIZE.x * 0.5
	_sheet.offset_top = -PANEL_SIZE.y * 0.5
	_sheet.offset_bottom = PANEL_SIZE.y * 0.5
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.draw.connect(_paint_sheet)
	add_child(_sheet)

	var box := VBoxContainer.new()
	box.position = Vector2(32.0, 24.0)
	box.size = PANEL_SIZE - Vector2(64.0, 48.0)
	box.add_theme_constant_override("separation", 14)
	_sheet.add_child(box)

	var title := _text(tr("Settings"), 30, UiPalette.HUD_ACCENT)
	box.add_child(title)
	_first = _slider_row(box, tr("Music"), &"Music")
	_slider_row(box, tr("Effects"), &"SFX")
	_slider_row(box, tr("Interface"), &"UI")

	var row := HBoxContainer.new()
	box.add_child(row)
	var label := _text(tr("Fullscreen"), 20, UiPalette.HUD_INK)
	label.custom_minimum_size.x = ROW_LABEL_W
	row.add_child(label)
	_fullscreen = CheckButton.new()
	_fullscreen.name = "Fullscreen"
	_fullscreen.add_theme_font_override("font", UiPalette.hud_font())
	_fullscreen.add_theme_font_size_override("font_size", 16)
	_fullscreen.add_theme_color_override("font_color", UiPalette.HUD_INK_SOFT)
	_fullscreen.add_theme_color_override("font_focus_color", UiPalette.HUD_ACCENT)
	_fullscreen.add_theme_color_override("font_hover_color", UiPalette.HUD_ACCENT)
	_fullscreen.add_theme_color_override("font_pressed_color", UiPalette.HUD_INK)
	_fullscreen.add_theme_color_override("font_hover_pressed_color", UiPalette.HUD_ACCENT)
	_fullscreen.text = tr("F11")
	_fullscreen.toggled.connect(GameSettings.set_fullscreen)
	row.add_child(_fullscreen)

	_back = Button.new()
	_back.name = "Back"
	_back.text = tr("Back")
	_back.custom_minimum_size = Vector2(0.0, 46.0)
	UiPalette.lacquer_button(_back, true, false, 20)
	_back.pressed.connect(close)
	box.add_child(_back)


func _slider_row(box: VBoxContainer, caption: String, bus: StringName) -> HSlider:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := _text(caption, 20, UiPalette.HUD_INK)
	label.custom_minimum_size.x = ROW_LABEL_W
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "%sVolume" % bus
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = GameSettings.volume(bus)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.add_theme_stylebox_override("slider", UiPalette.box(UiPalette.HUD_EDGE, UiPalette.HUD_GOLD, 3, 1, 3))
	slider.add_theme_stylebox_override("grabber_area", UiPalette.box(UiPalette.HUD_GOLD, UiPalette.HUD_GOLD, 3, 0, 3))
	slider.add_theme_stylebox_override("grabber_area_highlight", UiPalette.box(UiPalette.HUD_ACCENT, UiPalette.HUD_ACCENT, 3, 0, 3))
	slider.add_theme_stylebox_override("focus", UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), UiPalette.HUD_ACCENT, 5, 2, 4))
	slider.value_changed.connect(func(v: float) -> void:
		GameSettings.set_volume(bus, v)
		Audio.play(Audio.UI_CLICK))
	row.add_child(slider)
	return slider


func _text(content: String, font_size: int, color: Color) -> Label:
	var label := UiPalette.hud_label(font_size, color)
	label.text = content
	label.z_index = 0
	return label


func _paint_sheet() -> void:
	_painter.begin(1.0)
	var shape := HudPainter.chamfered(Rect2(Vector2.ZERO, PANEL_SIZE), 12.0)
	_painter.lacquer(shape, UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	_painter.stroke(HudPainter.chamfered(Rect2(Vector2.ZERO, PANEL_SIZE).grow(-5.0), 9.0), 1.0, UiPalette.HUD_GOLD)
	RenderingServer.canvas_item_add_triangle_array(_sheet.get_canvas_item(), _painter.indices, _painter.points, _painter.colors)
