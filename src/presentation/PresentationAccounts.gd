class_name PresentationAccounts
extends Control

# The Account dialog: who is presenting. The cover and the contents page open it;
# nothing else is in it — no invented roles, no contact details. Esc or Close
# returns focus to the button that opened it.
#
# A modal, so it may paint its own panel (HudCanvas rules apply to the live HUD,
# not to a dimmed overlay). One sheet, one draw while open.

const PANEL_SIZE := Vector2(520.0, 356.0)
const NOTO_REGULAR_PATH := "res://assets/fonts/NotoSans-Regular.ttf"
const NOTO_BOLD_PATH := "res://assets/fonts/NotoSans-Bold.ttf"

var _return_focus: Control = null
var _close: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 40
	_build()


func open() -> void:
	_return_focus = get_viewport().gui_get_focus_owner()
	visible = true
	_close.grab_focus.call_deferred()


func close() -> void:
	visible = false
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = UiPalette.HUD_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var sheet := Control.new()
	sheet.name = "Sheet"
	sheet.set_anchors_preset(Control.PRESET_CENTER)
	sheet.offset_left = -PANEL_SIZE.x * 0.5
	sheet.offset_right = PANEL_SIZE.x * 0.5
	sheet.offset_top = -PANEL_SIZE.y * 0.5
	sheet.offset_bottom = PANEL_SIZE.y * 0.5
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.draw.connect(_paint_sheet.bind(sheet))
	add_child(sheet)

	var box := VBoxContainer.new()
	box.name = "Body"
	box.position = Vector2(34.0, 28.0)
	box.size = PANEL_SIZE - Vector2(68.0, 56.0)
	box.add_theme_constant_override("separation", 8)
	sheet.add_child(box)

	var kicker := _label(tr("PRESENTED BY"), UiPalette.hud_font(), 11, UiPalette.HUD_GOLD, 2.2)
	box.add_child(kicker)

	var title := _label(tr("Leyline Warden"), UiPalette.hud_font(), 32, UiPalette.HUD_ACCENT)
	box.add_child(title)

	var course := _label(tr(PresentationDeck.COURSE), _noto(false), 13, UiPalette.HUD_INK_SOFT)
	box.add_child(course)

	var rule := ColorRect.new()
	rule.name = "Rule"
	rule.color = Color(UiPalette.HUD_GOLD, 0.45)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	box.add_child(rule)

	var rows := VBoxContainer.new()
	rows.name = "Presenters"
	rows.add_theme_constant_override("separation", 6)
	box.add_child(rows)
	for presenter: Dictionary in PresentationDeck.PRESENTERS:
		rows.add_child(_presenter_row(str(presenter["name"]), str(presenter["id"])))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var footer := HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 14)
	box.add_child(footer)

	var lecturer := _label(tr("Lecturer · %s") % PresentationDeck.LECTURER,
		_noto(false), 13, UiPalette.HUD_INK_SOFT)
	lecturer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(lecturer)

	_close = Button.new()
	_close.name = "CloseButton"
	_close.text = tr("Close")
	_close.custom_minimum_size = Vector2(104.0, 38.0)
	UiPalette.lacquer_button(_close, false, false, 16)
	_close.pressed.connect(close)
	footer.add_child(_close)


func _presenter_row(presenter_name: String, student_id: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Presenter"
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.add_theme_constant_override("separation", 12)

	var name_label := _label(presenter_name, _noto(false), 17, UiPalette.HUD_INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var id_label := _label(student_id, _noto(true), 15, UiPalette.HUD_GOLD)
	id_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(id_label)
	return row


func _paint_sheet(sheet: Control) -> void:
	var painter := HudPainter.new()
	painter.begin(1.0)
	painter.lacquer(HudPainter.chamfered(Rect2(Vector2.ZERO, sheet.size), 12.0),
		UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT, UiPalette.HUD_GOLD, 6.0)
	RenderingServer.canvas_item_add_triangle_array(sheet.get_canvas_item(),
		painter.indices, painter.points, painter.colors)


func _label(text: String, font: Font, font_size: int, color: Color,
		tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font",
		_tracked(font, tracking) if tracking != 0 else font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _tracked(font: Font, tracking: int) -> FontVariation:
	var varied := FontVariation.new()
	varied.base_font = font
	varied.spacing_glyph = tracking
	return varied


func _noto(bold: bool) -> Font:
	return load(NOTO_BOLD_PATH if bold else NOTO_REGULAR_PATH)
