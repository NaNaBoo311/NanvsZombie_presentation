class_name ConceptScreen
extends Control

# Section 01 — Concept & Vision. Four exhibits in one UI layer over the inherited
# title stage: the pitch, the world atlas, the reference ledger and the design
# pillars. The screen owns only the copy and the exhibits; ConceptVision owns the
# camera and the atlas. The 360° facing demo belongs to Section 02, so its copy
# and ConceptFacingDemo stay in the repo for that screen.
#
# Every panel is built once and toggled visible, so switching exhibits costs no
# allocation and no per-frame work. Shapes are painted through ConceptCanvas /
# HudCanvas; the atlas updates only when the picked world changes.

signal stage_focus_requested(active: bool)
signal world_selected(index: int)
signal enter_game_pressed
signal contents_pressed

const MARGIN := 72.0
const TOP := 34.0
const MAIN_TOP := 104.0
const MAIN_BOTTOM := -104.0
const NOTO_REGULAR_PATH := "res://assets/fonts/NotoSans-Regular.ttf"
const EXHIBITS := ["The pitch", "The world", "References", "Pillars"]

var current := 0

var _main: Control
var _panels: Array[Control] = []
var _tabs: Array[Button] = []
var _enter_game: HudMenuButton
var _stage: HudCanvas
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
	if not _tabs.is_empty():
		_tabs[current].grab_focus.call_deferred()


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

	_enter_game = HudMenuButton.new()
	_enter_game.name = "EnterGameButton"
	_enter_game.text = tr("Enter the game")
	_enter_game.primary = true
	_enter_game.visible = false
	_enter_game.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enter_game.offset_left = -190.0
	_enter_game.offset_top = 0.0
	_enter_game.offset_right = 0.0
	_enter_game.offset_bottom = 42.0
	_enter_game.mouse_filter = Control.MOUSE_FILTER_STOP
	_enter_game.pressed.connect(_on_enter_game)
	bottom.add_child(_enter_game)

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


func _left_column(panel: Control, title: String,
		body: String, extra: Array[Control] = []) -> VBoxContainer:
	var left := VBoxContainer.new()
	left.name = "Copy"
	left.anchor_right = 0.35
	left.anchor_bottom = 1.0
	left.offset_top = 2.0
	left.offset_bottom = -2.0
	left.add_theme_constant_override("separation", 14)
	panel.add_child(left)

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

	for child in extra:
		left.add_child(child)

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

	var rule := _rule()
	rule.color = Color(UiPalette.HUD_GOLD, 0.32)

	var glance := GridContainer.new()
	glance.name = "Glance"
	glance.columns = 2
	glance.add_theme_constant_override("h_separation", 28)
	glance.add_theme_constant_override("v_separation", 16)
	for spec: Dictionary in PresentationDeck.CONCEPT_GLANCE:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 3)
		var label := _label(str(spec["label"]), UiPalette.hud_font(), 11,
			UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
		column.add_child(label)
		var value := _label(str(spec["value"]), UiPalette.hud_font(), 16,
			UiPalette.HUD_INK, Vector2.ZERO)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(value)
		glance.add_child(column)

	_left_column(panel, PresentationDeck.CONCEPT_TITLE,
		PresentationDeck.CONCEPT_PITCH, [rule, glance])
	return panel


func _build_world_panel() -> Control:
	var panel := _new_panel("World")
	var left := _left_column(panel, PresentationDeck.WORLDS_TITLE,
		PresentationDeck.WORLDS_BODY)

	var caption := _label("VIETNAM ATLAS · PICK A WORLD", UiPalette.hud_font(), 10,
		UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
	caption.name = "AtlasCaption"
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

	_select_world(0, false)
	return panel


func _build_reference_panel() -> Control:
	var panel := _new_panel("References")
	var left := _left_column(panel, PresentationDeck.REFERENCES_TITLE,
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
	backdrop.add_theme_stylebox_override("panel", UiPalette.board_box())
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
		cell.custom_minimum_size = Vector2(0.0, 28.0)
		var label := _label(str(spec[0]), UiPalette.hud_font(), 13, UiPalette.HUD_GOLD, Vector2.ZERO, 2.2)
		label.position = Vector2.ZERO
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(label)
		head.add_child(cell)
	ledger.add_child(head)
	ledger.add_child(_rule())

	for spec: Dictionary in PresentationDeck.REFERENCES:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0.0, 96.0)
		row.add_theme_constant_override("separation", 12)

		var game := VBoxContainer.new()
		game.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game.size_flags_stretch_ratio = 3.4
		var name_label := _label(str(spec["game"]), UiPalette.hud_font(), 19,
			UiPalette.HUD_INK, Vector2.ZERO)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		game.add_child(name_label)
		var year := _label(str(spec["year"]), _noto(), 14, UiPalette.HUD_GOLD, Vector2.ZERO)
		game.add_child(year)
		row.add_child(game)

		var take := _label(str(spec["take"]), _noto(), 16, UiPalette.HUD_INK, Vector2.ZERO)
		take.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		take.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		take.size_flags_stretch_ratio = 3.6
		row.add_child(take)

		var avoid := _label(str(spec["avoid"]), _noto(), 16, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
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
	_left_column(panel, PresentationDeck.PILLARS_TITLE,
		PresentationDeck.PILLARS_BODY)

	var visual := panel.get_node("Visual") as Control
	var stack := VBoxContainer.new()
	stack.name = "PillarStack"
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 10.0
	stack.offset_top = 20.0
	stack.offset_right = -10.0
	stack.offset_bottom = -10.0
	visual.add_child(stack)
	var top := Control.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(top)

	var cards := HBoxContainer.new()
	cards.name = "Pillars"
	cards.add_theme_constant_override("separation", 14)
	stack.add_child(cards)
	var bottom := Control.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(bottom)

	for spec: Dictionary in PresentationDeck.PILLARS:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UiPalette.board_box(18))
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
	_enter_game.visible = index == _panels.size() - 1
	HudCanvas.dirty()
	# The world exhibit is the one that sends the camera to the atlas stage.
	stage_focus_requested.emit(index == 1)
	if animate:
		var tween := create_tween()
		_panels[index].modulate.a = 0.0
		tween.tween_property(_panels[index], "modulate:a", 1.0, 0.24) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_enter_game() -> void:
	Audio.play(Audio.UI_CLICK)
	enter_game_pressed.emit()


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
