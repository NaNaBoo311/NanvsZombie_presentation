class_name ConceptScreen
extends Control

# Section 01 — Concept & Vision. Five exhibits in one UI layer over the inherited
# title stage: the pitch, the 360° facing demo, the 3D world carousel, the
# reference ledger and the design pillars. The screen owns only the copy and the
# exhibits; ConceptVision owns the camera and the carousel.
#
# Every panel is built once and toggled visible, so switching exhibits costs no
# allocation and no per-frame work. Shapes are painted through ConceptCanvas /
# HudCanvas; the facing diagram redraws only when it changes.

signal stage_focus_requested(active: bool)
signal world_selected(index: int)
signal enter_game_pressed
signal contents_pressed

const MARGIN := 72.0
const TOP := 34.0
const MAIN_TOP := 104.0
const MAIN_BOTTOM := -104.0
const NOTO_REGULAR_PATH := "res://assets/fonts/NotoSans-Regular.ttf"
const EXHIBITS := ["The pitch", "The circle", "The world", "References", "Pillars"]

var current := 0

var _main: Control
var _panels: Array[Control] = []
var _tabs: Array[Button] = []
var _prev: Button
var _next: HudMenuButton
var _stage: HudCanvas
var _facing: ConceptFacingDemo
var _world_tabs: Array[Button] = []
var _world_place: Label
var _world_hook: Label
var _world_index := 0
var _fade_groups: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_scrim()
	_stage = HudCanvas.new()
	_stage.name = "HudCanvas"
	add_child(_stage)
	_build_header()
	_build_main()
	_build_bottom()
	_build_accounts_hook()
	_show_exhibit(0, false)


func play_intro() -> void:
	for group in _fade_groups:
		group.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.10 * _fade_groups.find(group))
		tween.tween_property(group, "modulate:a", 1.0, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func show_exhibit(index: int) -> void:
	_show_exhibit(index, true)


func focus_primary() -> void:
	_next.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		contents_pressed.emit()
		get_viewport().set_input_as_handled()
	elif key == KEY_LEFT:
		_show_exhibit(current - 1)
		get_viewport().set_input_as_handled()
	elif key == KEY_RIGHT:
		_show_exhibit(current + 1)
		get_viewport().set_input_as_handled()
	elif current == 1 and key >= KEY_1 and key <= KEY_8:
		_facing.set_facing(key - KEY_1)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ chrome ---

func _build_scrim() -> void:
	var wash := ColorRect.new()
	wash.name = "Wash"
	wash.color = Color(UiPalette.HUD_EDGE, 0.10)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)

	var scrim := TextureRect.new()
	scrim.name = "Scrim"
	scrim.texture = _scrim_texture()
	scrim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)


func _scrim_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(UiPalette.HUD_EDGE, 0.92))
	gradient.set_color(1, Color(UiPalette.HUD_EDGE, 0.0))
	gradient.add_point(0.32, Color(UiPalette.HUD_EDGE, 0.84))
	gradient.add_point(0.52, Color(UiPalette.HUD_EDGE, 0.38))
	gradient.add_point(0.72, Color(UiPalette.HUD_EDGE, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(1.0, 0.0)
	return texture


func _build_header() -> void:
	var header := Control.new()
	header.name = "Header"
	header.anchor_right = 1.0
	header.offset_left = MARGIN
	header.offset_top = TOP
	header.offset_right = -MARGIN
	header.offset_bottom = TOP + 64.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	_fade_groups.append(header)

	var back := HudMenuButton.new()
	back.name = "BackButton"
	back.text = "←"
	back.position = Vector2.ZERO
	back.size = Vector2(44.0, 44.0)
	back.custom_minimum_size = Vector2(44.0, 44.0)
	back.pressed.connect(func() -> void: contents_pressed.emit())
	header.add_child(back)

	var kicker := _label(PresentationDeck.CONCEPT_KICKER, UiPalette.hud_font(), 11,
		UiPalette.HUD_GOLD, Vector2(62.0, 1.0), 2.0)
	kicker.name = "Kicker"
	header.add_child(kicker)

	var title := _label("Concept & Vision", UiPalette.hud_font(), 22,
		UiPalette.HUD_INK, Vector2(62.0, 20.0))
	title.name = "SectionTitle"
	header.add_child(title)

	SafeArea.apply(header)


func _build_main() -> void:
	_main = Control.new()
	_main.name = "Main"
	_main.anchor_right = 1.0
	_main.anchor_bottom = 1.0
	_main.offset_left = MARGIN
	_main.offset_top = MAIN_TOP
	_main.offset_right = -MARGIN
	_main.offset_bottom = MAIN_BOTTOM
	_main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_main)
	_fade_groups.append(_main)

	_panels.append(_build_pitch_panel())
	_panels.append(_build_circle_panel())
	_panels.append(_build_world_panel())
	_panels.append(_build_reference_panel())
	_panels.append(_build_pillar_panel())
	for panel in _panels:
		panel.visible = false
		_main.add_child(panel)

	SafeArea.apply(_main)


func _build_bottom() -> void:
	var bottom := Control.new()
	bottom.name = "Bottom"
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = MARGIN
	bottom.offset_top = -88.0
	bottom.offset_right = -MARGIN
	bottom.offset_bottom = -36.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_fade_groups.append(bottom)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.position = Vector2.ZERO
	tabs.size = Vector2(560.0, 40.0)
	tabs.add_theme_constant_override("separation", 6)
	bottom.add_child(tabs)
	for i in EXHIBITS.size():
		var tab := Button.new()
		tab.name = "Tab%s" % str(i + 1)
		tab.text = "%02d  %s" % [i + 1, tr(EXHIBITS[i])]
		tab.tooltip_text = tr(EXHIBITS[i])
		tab.custom_minimum_size = Vector2(104.0, 38.0)
		tab.focus_mode = Control.FOCUS_ALL
		tab.pressed.connect(_show_exhibit.bind(i))
		UiPalette.lacquer_button(tab, false, false, 12)
		tabs.add_child(tab)
		_tabs.append(tab)

	var contents := _quiet_button("Back to contents")
	contents.name = "ContentsButton"
	contents.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	contents.offset_left = -444.0
	contents.offset_top = 3.0
	contents.offset_right = -280.0
	contents.offset_bottom = 39.0
	contents.pressed.connect(func() -> void: contents_pressed.emit())
	bottom.add_child(contents)

	_prev = _quiet_button("← Prev")
	_prev.name = "PrevButton"
	_prev.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_prev.offset_left = -270.0
	_prev.offset_top = 0.0
	_prev.offset_right = -178.0
	_prev.offset_bottom = 40.0
	_prev.pressed.connect(_show_exhibit.bind(-1))
	bottom.add_child(_prev)

	_next = HudMenuButton.new()
	_next.name = "NextButton"
	_next.text = tr("Next exhibit")
	_next.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_next.offset_left = -166.0
	_next.offset_top = 0.0
	_next.offset_right = 0.0
	_next.offset_bottom = 42.0
	_next.mouse_filter = Control.MOUSE_FILTER_STOP
	_next.pressed.connect(_on_next)
	bottom.add_child(_next)

	SafeArea.apply(bottom)


func _build_accounts_hook() -> void:
	# The Account dialog lives on the contents page; the section does not repeat it.
	pass


# ----------------------------------------------------------------- panels ---

func _new_panel(name: String) -> Control:
	var panel := Control.new()
	panel.name = name
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_visual_frame(panel)
	return panel


func _left_column(panel: Control, kicker: String, title: String,
		body: String) -> VBoxContainer:
	var left := VBoxContainer.new()
	left.name = "Copy"
	left.anchor_right = 0.35
	left.anchor_bottom = 1.0
	left.offset_top = 2.0
	left.offset_bottom = -2.0
	left.add_theme_constant_override("separation", 14)
	panel.add_child(left)

	var eyebrow := _label(kicker, UiPalette.hud_font(), 11, UiPalette.HUD_GOLD,
		Vector2.ZERO, 2.0)
	left.add_child(eyebrow)

	var heading := _label(title, UiPalette.hud_font(), 40, UiPalette.HUD_INK, Vector2.ZERO)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.custom_minimum_size = Vector2(0.0, 52.0)
	left.add_child(heading)

	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_GOLD, 0.55)
	rule.custom_minimum_size = Vector2(128.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(rule)

	var copy := _label(body, UiPalette.hud_font(), 17, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.custom_minimum_size = Vector2(0.0, 108.0)
	left.add_child(copy)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	return left


func _add_visual_frame(panel: Control) -> void:
	var visual := Control.new()
	visual.name = "Visual"
	visual.anchor_left = 0.39
	visual.anchor_right = 1.0
	visual.anchor_bottom = 1.0
	visual.offset_left = 10.0
	visual.offset_top = 2.0
	visual.offset_right = -2.0
	visual.offset_bottom = -2.0
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(visual)

	var frame := ConceptCanvas.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.paint = _paint_frame
	visual.add_child(frame)


func _paint_frame(p: HudPainter, size: Vector2) -> void:
	var inset := 6.0
	var gold := Color(UiPalette.HUD_GOLD, 0.32)
	var long := 28.0
	# Four corner brackets, in the deck's thin gold line weight.
	for corner in [Vector2(inset, inset), Vector2(size.x - inset, inset),
			Vector2(inset, size.y - inset), Vector2(size.x - inset, size.y - inset)]:
		var sx := 1.0 if corner.x < size.x * 0.5 else -1.0
		var sy := 1.0 if corner.y < size.y * 0.5 else -1.0
		p.line(PackedVector2Array([corner, corner + Vector2(long * sx, 0.0)]), 1.0, gold)
		p.line(PackedVector2Array([corner, corner + Vector2(0.0, long * sy)]), 1.0, gold)


func _build_pitch_panel() -> Control:
	var panel := _new_panel("Pitch")
	var left := _left_column(panel, "EXHIBIT 01 · THE PITCH", PresentationDeck.CONCEPT_TITLE,
		PresentationDeck.CONCEPT_PITCH)

	var quote := _label(PresentationDeck.CONCEPT_QUOTE, _noto(), 22,
		UiPalette.HUD_GOLD, Vector2.ZERO)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(quote)

	var visual := panel.get_node("Visual") as Control
	var art := ConceptCanvas.new()
	art.name = "Eclipse"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.paint = _paint_pitch
	visual.add_child(art)

	var glance := HBoxContainer.new()
	glance.name = "Glance"
	glance.anchor_top = 0.70
	glance.anchor_bottom = 1.0
	glance.anchor_right = 1.0
	glance.offset_left = 34.0
	glance.offset_top = 20.0
	glance.offset_right = -34.0
	glance.offset_bottom = -24.0
	glance.alignment = BoxContainer.ALIGNMENT_CENTER
	glance.add_theme_constant_override("separation", 18)
	visual.add_child(glance)
	for spec: Dictionary in PresentationDeck.CONCEPT_GLANCE:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 2)
		var label := _label(str(spec["label"]), UiPalette.hud_font(), 9,
			UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
		column.add_child(label)
		var value := _label(str(spec["value"]), UiPalette.hud_font(), 14,
			UiPalette.HUD_INK, Vector2.ZERO)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(value)
		glance.add_child(column)
	return panel


## The live title stage is the keyart; this only lays the at-a-glance band across
## its foot, so the numbers never fight the island's foliage.
func _paint_pitch(p: HudPainter, size: Vector2) -> void:
	var band := HudPainter.chamfered(Rect2(18.0, size.y * 0.70, size.x - 36.0,
		size.y * 0.30), 10.0)
	p.lacquer(band, Color(UiPalette.HUD_LACQUER_TOP, 0.92),
		Color(UiPalette.HUD_LACQUER_BOT, 0.96), Color(UiPalette.HUD_GOLD, 0.42), 0.0)
	p.line(PackedVector2Array([Vector2(36.0, size.y * 0.70),
		Vector2(size.x - 36.0, size.y * 0.70)]), 1.0, Color(UiPalette.HUD_GOLD, 0.22))
	p.line(PackedVector2Array([Vector2(size.x * 0.06, size.y * 0.62),
		Vector2(size.x * 0.44, size.y * 0.62)]), 1.0, Color(UiPalette.HUD_GOLD, 0.30))


func _build_circle_panel() -> Control:
	var panel := _new_panel("Circle")
	var left := _left_column(panel, "EXHIBIT 02 · THE CIRCLE", PresentationDeck.CIRCLE_TITLE,
		PresentationDeck.CIRCLE_BODY)
	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 18)
	for spec: Dictionary in PresentationDeck.CIRCLE_STATS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 0)
		var value := _label(str(spec["value"]), UiPalette.hud_font(), 32,
			UiPalette.HUD_GOLD, Vector2.ZERO)
		column.add_child(value)
		var label := _label(str(spec["label"]), UiPalette.hud_font(), 9,
			UiPalette.HUD_INK_SOFT, Vector2.ZERO, 1.4)
		column.add_child(label)
		stats.add_child(column)
	left.add_child(stats)

	var hint := _label("Click a facing · 1–8 on the keyboard", _noto(), 13,
		UiPalette.HUD_ACCENT, Vector2.ZERO)
	left.add_child(hint)

	var visual := panel.get_node("Visual") as Control
	_facing = ConceptFacingDemo.new()
	_facing.name = "FacingDemo"
	_facing.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_facing.offset_left = 12.0
	_facing.offset_top = 4.0
	_facing.offset_right = -12.0
	_facing.offset_bottom = -4.0
	visual.add_child(_facing)
	return panel


func _build_world_panel() -> Control:
	var panel := _new_panel("World")
	var left := _left_column(panel, "EXHIBIT 03 · THE WORLD", PresentationDeck.WORLDS_TITLE,
		PresentationDeck.WORLDS_BODY)

	var caption := _label("3D CAROUSEL · PICK A WORLD", UiPalette.hud_font(), 10,
		UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
	caption.name = "CarouselCaption"
	left.add_child(caption)

	var tabs := HBoxContainer.new()
	tabs.name = "WorldTabs"
	tabs.add_theme_constant_override("separation", 6)
	left.add_child(tabs)
	for i in PresentationDeck.WORLDS.size():
		var spec: Dictionary = PresentationDeck.WORLDS[i]
		var tab := Button.new()
		tab.name = "World%s" % str(spec["id"])
		tab.text = tr(str(spec["name"]))
		tab.custom_minimum_size = Vector2(0.0, 38.0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_mode = Control.FOCUS_ALL
		tab.pressed.connect(_select_world.bind(i))
		UiPalette.lacquer_button(tab, false, false, 12)
		tabs.add_child(tab)
		_world_tabs.append(tab)

	_world_place = _label("", _noto(), 16, UiPalette.HUD_GOLD, Vector2.ZERO)
	_world_place.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_world_place)

	_world_hook = _label("", _noto(), 15, UiPalette.HUD_INK, Vector2.ZERO)
	_world_hook.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_world_hook.custom_minimum_size = Vector2(0.0, 72.0)
	left.add_child(_world_hook)

	var promise := _label(PresentationDeck.WORLDS_PROMISE, UiPalette.hud_font(), 12,
		UiPalette.HUD_INK_SOFT, Vector2.ZERO)
	promise.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(promise)

	_select_world(0, false)
	return panel


func _build_reference_panel() -> Control:
	var panel := _new_panel("References")
	var left := _left_column(panel, "EXHIBIT 04 · REFERENCES", PresentationDeck.REFERENCES_TITLE,
		PresentationDeck.REFERENCES_BODY)
	var note := _label("One comparison ledger.\nA TAKE and an AVOID per title.", _noto(), 13,
		UiPalette.HUD_INK_SOFT, Vector2.ZERO)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(note)

	var visual := panel.get_node("Visual") as Control
	var backdrop := Panel.new()
	backdrop.name = "LedgerBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 8.0
	backdrop.offset_top = 8.0
	backdrop.offset_right = -8.0
	backdrop.offset_bottom = -8.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_theme_stylebox_override("panel",
		UiPalette.lacquer_box(Color(UiPalette.HUD_LACQUER_TOP, 0.90),
			Color(UiPalette.HUD_GOLD, 0.32), 8, 1, 0))
	visual.add_child(backdrop)

	var ledger := VBoxContainer.new()
	ledger.name = "Ledger"
	ledger.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ledger.offset_left = 18.0
	ledger.offset_top = 8.0
	ledger.offset_right = -18.0
	ledger.offset_bottom = -8.0
	ledger.add_theme_constant_override("separation", 0)
	visual.add_child(ledger)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	for spec in [["GAME", 0.34], ["TAKE", 0.36], ["AVOID", 0.30]]:
		var cell := Control.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_stretch_ratio = float(spec[1]) * 10.0
		cell.custom_minimum_size = Vector2(0.0, 20.0)
		var label := _label(str(spec[0]), UiPalette.hud_font(), 9, UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
		label.position = Vector2.ZERO
		cell.add_child(label)
		head.add_child(cell)
	ledger.add_child(head)
	ledger.add_child(_rule())

	for spec: Dictionary in PresentationDeck.REFERENCES:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 68.0)
		row.add_theme_constant_override("separation", 12)

		var game := VBoxContainer.new()
		game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.size_flags_stretch_ratio = 3.4
		var name_label := _label(str(spec["game"]), UiPalette.hud_font(), 15,
			UiPalette.HUD_INK, Vector2.ZERO)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game.add_child(name_label)
		var year := _label(str(spec["year"]), _noto(), 12, UiPalette.HUD_GOLD, Vector2.ZERO)
		game.add_child(year)
		row.add_child(game)

		var take := _label(str(spec["take"]), _noto(), 13, UiPalette.HUD_INK, Vector2.ZERO)
		take.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		take.size_flags_stretch_ratio = 3.6
		row.add_child(take)

		var avoid := _label(str(spec["avoid"]), _noto(), 13, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
		avoid.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		avoid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		avoid.size_flags_stretch_ratio = 3.0
		row.add_child(avoid)

		var cell := VBoxContainer.new()
		cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cell.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_theme_constant_override("separation", 0)
		cell.add_child(row)
		cell.add_child(_rule())
		ledger.add_child(cell)
	return panel


func _build_pillar_panel() -> Control:
	var panel := _new_panel("Pillars")
	_left_column(panel, "EXHIBIT 05 · PILLARS", PresentationDeck.PILLARS_TITLE,
		PresentationDeck.PILLARS_BODY)

	var visual := panel.get_node("Visual") as Control
	var cards := HBoxContainer.new()
	cards.name = "Pillars"
	cards.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cards.offset_left = 10.0
	cards.offset_top = 20.0
	cards.offset_right = -10.0
	cards.offset_bottom = -10.0
	cards.add_theme_constant_override("separation", 14)
	visual.add_child(cards)

	for spec: Dictionary in PresentationDeck.PILLARS:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",
			UiPalette.lacquer_box(Color(UiPalette.HUD_LACQUER_TOP, 0.94),
				Color(UiPalette.HUD_GOLD, 0.48), 8, 1, 18))
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		card.add_child(box)

		var number := _label(str(spec["number"]), UiPalette.hud_font(), 34,
			UiPalette.HUD_GOLD, Vector2.ZERO)
		box.add_child(number)
		var rule := ColorRect.new()
		rule.color = Color(UiPalette.HUD_GOLD, 0.55)
		rule.custom_minimum_size = Vector2(42.0, 2.0)
		box.add_child(rule)
		var title := _label(str(spec["title"]), UiPalette.hud_font(), 23,
			UiPalette.HUD_INK, Vector2.ZERO)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(0.0, 72.0)
		box.add_child(title)
		var line := _label(str(spec["line"]), _noto(), 14, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(line)
		cards.add_child(card)
	return panel


# ------------------------------------------------------------- navigation ---

func _show_exhibit(index: int, animate: bool = true) -> void:
	if _panels.is_empty():
		return
	index = clampi(index, 0, _panels.size() - 1)
	current = index
	for i in _panels.size():
		_panels[i].visible = i == index
	for i in _tabs.size():
		UiPalette.lacquer_button(_tabs[i], i == index, false, 14)
		_tabs[i].add_theme_color_override("font_color",
			UiPalette.HUD_SEAL_INK if i == index else UiPalette.HUD_INK)
	_prev.disabled = index == 0
	var last := index == _panels.size() - 1
	_next.text = tr("Enter the game") if last else tr("Next exhibit")
	_next.set_primary(last)
	_next.custom_minimum_size = Vector2(190.0, 42.0) if last else Vector2(166.0, 42.0)
	_next.size.x = 190.0 if last else 166.0
	_next.offset_left = -190.0 if last else -166.0
	_next.offset_right = 0.0
	HudCanvas.dirty()
	stage_focus_requested.emit(index == 2)
	if animate:
		var tween := create_tween()
		_panels[index].modulate.a = 0.0
		tween.tween_property(_panels[index], "modulate:a", 1.0, 0.24) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_next() -> void:
	if current >= _panels.size() - 1:
		Audio.play(Audio.UI_CLICK)
		enter_game_pressed.emit()
		return
	_show_exhibit(current + 1)


func _select_world(index: int, announce: bool = true) -> void:
	index = clampi(index, 0, PresentationDeck.WORLDS.size() - 1)
	_world_index = index
	for i in _world_tabs.size():
		UiPalette.lacquer_button(_world_tabs[i], i == index, false, 12)
		_world_tabs[i].add_theme_color_override("font_color",
			UiPalette.HUD_SEAL_INK if i == index else UiPalette.HUD_INK)
	var spec: Dictionary = PresentationDeck.WORLDS[index]
	_world_place.text = tr(str(spec["place"]))
	_world_hook.text = tr(str(spec["hook"]))
	if announce:
		Audio.play(Audio.UI_CLICK)
		world_selected.emit(index)


# ------------------------------------------------------------------- bits ---

func _rule() -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_GOLD, 0.20)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	return rule


func _quiet_button(text: String) -> Button:
	var button := Button.new()
	button.text = tr(text)
	button.flat = true
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", UiPalette.hud_font())
	button.add_theme_font_size_override("font_size", 14)
	for state in ["font_color", "font_hover_color", "font_focus_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, UiPalette.HUD_INK_SOFT)
	button.add_theme_color_override("font_pressed_color", UiPalette.HUD_ACCENT)
	button.add_theme_stylebox_override("hover",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.0), 0, 0, 6))
	button.add_theme_stylebox_override("pressed",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.0), 0, 0, 6))
	button.add_theme_stylebox_override("focus",
		UiPalette.box(Color(UiPalette.HUD_ACCENT, 0.0), Color(UiPalette.HUD_ACCENT, 0.60), 4, 1, 6))
	button.custom_minimum_size = Vector2(0.0, 38.0)
	return button


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


func _noto() -> Font:
	return load(NOTO_REGULAR_PATH)
