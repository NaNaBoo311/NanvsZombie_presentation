class_name PresentationContents
extends Control

# The contents page between the cover and a section. It is the talk's map: six
# section rows in slide order, number and title only. A row with no scene in
# PresentationDeck.SECTIONS is dimmed and non-clickable, so the page never offers
# a dead action. Back returns to the cover; Section 01 opens the concept screen.
#
# Painted on one HudCanvas for the buttons and one custom draw for the page
# furniture; no 3D stage and no per-frame script once the intro fade ends.

signal section_pressed(index: int)
signal title_pressed

const MARGIN := 72.0
const ROW_SEPARATION := 8

var _rows: Array[Button] = []
var _canvas: HudCanvas
var _fade_groups: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_canvas()
	_build_header()
	_build_list()
	section_pressed.connect(GameFlow.open_section)
	title_pressed.connect(GameFlow.open_title)
	_play_intro()
	if "--contents-shot" in OS.get_cmdline_user_args():
		_capture_shot()


func focus_primary() -> void:
	if not _rows.is_empty():
		_rows[0].grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		title_pressed.emit()
		get_viewport().set_input_as_handled()


func _build_background() -> void:
	var base := ColorRect.new()
	base.name = "Base"
	base.color = UiPalette.HUD_LACQUER_BOT
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(base)

	var glow := TextureRect.new()
	glow.name = "Glow"
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.texture = _glow_texture()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var furniture := Control.new()
	furniture.name = "Furniture"
	furniture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	furniture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	furniture.draw.connect(_paint_furniture.bind(furniture))
	add_child(furniture)

	var frame := Panel.new()
	frame.name = "InlayFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 22.0
	frame.offset_top = 22.0
	frame.offset_right = -22.0
	frame.offset_bottom = -22.0
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_GOLD, 0.0), Color(UiPalette.HUD_GOLD, 0.20), 0, 1, 0))
	add_child(frame)


func _glow_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiPalette.HUD_GOLD, 0.10))
	gradient.set_color(1, Color(UiPalette.HUD_GOLD, 0.0))
	gradient.add_point(0.55, Color(UiPalette.HUD_GOLD, 0.035))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.72, 0.42)
	texture.fill_to = Vector2(1.0, 1.0)
	return texture


func _paint_furniture(node: Control) -> void:
	var painter := HudPainter.new()
	painter.begin(1.0)
	var size := node.size
	var far := Vector2(size.x * 0.72, size.y * 0.42)
	painter.line(HudPainter.arc(far, size.y * 0.34, 0.0, TAU, 72, false), 1.0,
		Color(UiPalette.HUD_GOLD, 0.10))
	painter.line(HudPainter.arc(far, size.y * 0.46, 0.0, TAU, 72, false), 1.0,
		Color(UiPalette.HUD_GOLD, 0.06))
	painter.line(PackedVector2Array([Vector2(MARGIN, 96.0), Vector2(size.x - MARGIN, 96.0)]),
		1.0, Color(UiPalette.HUD_GOLD, 0.22))
	painter.line(PackedVector2Array([Vector2(MARGIN, size.y - 42.0),
		Vector2(size.x - MARGIN, size.y - 42.0)]), 1.0, Color(UiPalette.HUD_GOLD, 0.22))
	RenderingServer.canvas_item_add_triangle_array(node.get_canvas_item(),
		painter.indices, painter.points, painter.colors)


func _build_canvas() -> void:
	_canvas = HudCanvas.new()
	_canvas.name = "HudCanvas"
	add_child(_canvas)


func _build_header() -> void:
	var header := Control.new()
	header.name = "Header"
	header.anchor_right = 1.0
	header.offset_left = MARGIN
	header.offset_top = 34.0
	header.offset_right = -MARGIN
	header.offset_bottom = 100.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_fade_groups.append(header)

	var back := HudMenuButton.new()
	back.name = "BackButton"
	back.text = "←"
	back.position = Vector2.ZERO
	back.size = Vector2(48.0, 48.0)
	back.custom_minimum_size = Vector2(48.0, 48.0)
	back.pressed.connect(func() -> void: title_pressed.emit())
	header.add_child(back)

	var wordmark := _label("Leyline Warden", UiPalette.hud_font(), 24,
		UiPalette.HUD_INK, Vector2(68.0, 10.0))
	wordmark.name = "Wordmark"
	header.add_child(wordmark)

	SafeArea.apply(header)


func _build_list() -> void:
	var main := Control.new()
	main.name = "Main"
	main.anchor_right = 1.0
	main.anchor_bottom = 1.0
	main.offset_left = MARGIN
	main.offset_top = 116.0
	main.offset_right = -MARGIN
	main.offset_bottom = -72.0
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main)
	_fade_groups.append(main)

	var title := _label(PresentationDeck.CONTENTS_TITLE, UiPalette.hud_font(), 56,
		UiPalette.HUD_INK, Vector2.ZERO)
	title.name = "Title"
	main.add_child(title)

	var rows := VBoxContainer.new()
	rows.name = "Sections"
	rows.anchor_right = 1.0
	rows.anchor_bottom = 1.0
	rows.offset_top = 96.0
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	main.add_child(rows)

	for i in PresentationDeck.SECTIONS.size():
		var row := _build_row(i)
		rows.add_child(row)
		_rows.append(row)

	SafeArea.apply(main)


func _build_row(index: int) -> Button:
	var spec: Dictionary = PresentationDeck.SECTIONS[index]
	var live := not str(spec["scene"]).is_empty()
	var row := Button.new()
	row.name = "Section%s" % str(spec["number"])
	row.custom_minimum_size = Vector2(0.0, 60.0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE
	row.disabled = not live
	row.add_theme_stylebox_override("normal", _row_style(live, false, false))
	row.add_theme_stylebox_override("hover", _row_style(live, true, false))
	row.add_theme_stylebox_override("pressed", _row_style(live, true, true))
	row.add_theme_stylebox_override("focus",
		UiPalette.box(Color(UiPalette.HUD_GOLD, 0.0), Color(UiPalette.HUD_ACCENT, 0.85), 6, 2, 0))
	row.add_theme_stylebox_override("disabled", _row_style(false, false, false))
	if live:
		row.pressed.connect(func() -> void: _on_section(index))

	var number := _label(str(spec["number"]), UiPalette.hud_font(), 34,
		UiPalette.HUD_GOLD if live else Color(UiPalette.HUD_INK_SOFT, 0.60),
		Vector2.ZERO)
	number.name = "Number"
	number.anchor_top = 0.0
	number.anchor_bottom = 1.0
	number.offset_left = 22.0
	number.offset_top = 0.0
	number.offset_right = 86.0
	number.offset_bottom = 0.0
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(number)

	var title := _label(str(spec["title"]), UiPalette.hud_font(), 24,
		UiPalette.HUD_INK if live else Color(UiPalette.HUD_INK_SOFT, 0.75),
		Vector2.ZERO)
	title.name = "Title"
	title.anchor_top = 0.0
	title.anchor_bottom = 1.0
	title.offset_left = 96.0
	title.offset_top = 0.0
	title.offset_right = -24.0
	title.offset_bottom = 0.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	return row


func _row_style(live: bool, hover: bool, pressed: bool) -> StyleBoxFlat:
	var fill := UiPalette.HUD_LACQUER_TOP
	var edge := Color(UiPalette.HUD_GOLD, 0.34)
	if live:
		fill = UiPalette.HUD_LACQUER_LIT if hover else Color(UiPalette.HUD_LACQUER_TOP, 0.86)
		edge = UiPalette.HUD_ACCENT if hover else UiPalette.HUD_GOLD
	else:
		fill = Color(UiPalette.HUD_LOCKED_TOP, 0.55)
		edge = Color(UiPalette.HUD_GOLD, 0.14)
	if pressed:
		fill = UiPalette.HUD_GOLD
	return UiPalette.lacquer_box(fill, edge, 6, 1, 0)


func _on_section(index: int) -> void:
	if index < 0 or index >= PresentationDeck.SECTIONS.size():
		return
	if str(PresentationDeck.SECTIONS[index]["scene"]).is_empty():
		return
	Audio.play(Audio.UI_CLICK)
	section_pressed.emit(index)


func _label(text: String, font: Font, font_size: int, color: Color, at: Vector2,
		tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.position = at
	label.add_theme_font_override("font", _tracked(font, tracking) if tracking != 0 else font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _tracked(font: Font, tracking: int) -> FontVariation:
	var varied := FontVariation.new()
	varied.base_font = font
	varied.spacing_glyph = tracking
	return varied


func _play_intro() -> void:
	for group in _fade_groups:
		group.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.08 * _fade_groups.find(group))
		tween.tween_property(group, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Dev capture only: `--contents-shot` saves the page and quits.
func _capture_shot() -> void:
	await get_tree().create_timer(1.4).timeout
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("[PresentationContents] Contents capture came back empty.")
		get_tree().quit(1)
		return
	var shot := "screenshot_contents_%dx%d%s.png" % [img.get_width(), img.get_height(),
		"_touch" if GameManager.is_touch_ui() else ""]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/.screenshots"))
	img.save_png("res://tools/.screenshots/%s" % shot)
	print("✓ Captured contents screenshot: res://tools/.screenshots/%s" % shot)
	get_tree().quit()
