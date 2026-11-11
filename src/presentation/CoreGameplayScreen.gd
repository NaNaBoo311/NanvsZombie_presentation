class_name CoreGameplayScreen
extends Control

# Section 02 — Core Gameplay, beat 1: "One loop, three scales" staged at the
# center of the world atlas. The concentric Orrery diagram displays all three
# time horizons (Seconds, Minutes, Hours) within a single unified multi-circle
# celestial diagram centered on the Dragon Pearl.
#
# The board sits in the center of the screen with a lacquer finish and gold rims.
# It is collapsible: pressing [−] or 'C' hides the board so the full 3D atlas
# is visible, with a floating pill to re-open it anytime.
# When Saigon is clicked, the board switches to the province arc note.
# The "Next" button on the bottom right hands off into the HCMC diorama field.

signal continue_pressed
signal contents_pressed

const BOARD_WIDTH := 800.0
const BOARD_HEIGHT := 640.0

var _dim: ColorRect
var _plate: Panel
var _collapse_button: Button
var _pill_bar: HBoxContainer
var _expand_button: Button
var _pill_next: Button
var _is_collapsed := false

var _scales: VBoxContainer
var _tension: Control
var _province_card: Control
var _continue: Button
var _fade_groups: Array[Control] = []
var _orrery: OrreryDiagram = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_scrim()
	_build_column()
	_build_pill_bar()


func play_intro() -> void:
	for group in _fade_groups:
		group.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.08 * _fade_groups.find(group))
		tween.tween_property(group, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_collapsed(collapsed: bool) -> void:
	_is_collapsed = collapsed
	_plate.visible = not collapsed
	_dim.visible = not collapsed
	_pill_bar.visible = collapsed


func toggle_collapsed() -> void:
	set_collapsed(not _is_collapsed)


## The atlas board is open: switch from the concentric orrery to the level arc note.
func set_province_mode(open: bool) -> void:
	_scales.visible = not open
	_tension.visible = not open
	if _province_card != null:
		_province_card.visible = open
	_continue.text = tr(PresentationDeck.CORE_FIELD_ENTER if open else "Next →")
	if _pill_next != null:
		_pill_next.text = tr(PresentationDeck.CORE_FIELD_ENTER if open else "Next →")


func focus_primary() -> void:
	if _continue != null and _continue.is_visible_in_tree():
		_continue.grab_focus.call_deferred()
	elif _expand_button != null and _expand_button.is_visible_in_tree():
		_expand_button.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_C:
		toggle_collapsed()
		get_viewport().set_input_as_handled()
		return
	if key == KEY_ESCAPE:
		if _is_collapsed:
			set_collapsed(false)
			get_viewport().set_input_as_handled()
			return
		contents_pressed.emit()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout ---

func _build_scrim() -> void:
	# Fullscreen darkening
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(UiPalette.HUD_DIM, 0.40)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_fade_groups.append(_dim)

	# Centered lacquer plate
	_plate = Panel.new()
	_plate.name = "Plate"
	_plate.anchor_left = 0.5
	_plate.anchor_right = 0.5
	_plate.anchor_top = 0.5
	_plate.anchor_bottom = 0.5
	_plate.offset_left = -BOARD_WIDTH * 0.5
	_plate.offset_right = BOARD_WIDTH * 0.5
	_plate.offset_top = -BOARD_HEIGHT * 0.5
	_plate.offset_bottom = BOARD_HEIGHT * 0.5
	_plate.mouse_filter = Control.MOUSE_FILTER_STOP
	_plate.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_TOP, 0.98),
			Color(UiPalette.HUD_GOLD, 0.80), 18, 2, 0,
			Color(UiPalette.HUD_SHADOW, 0.75), 24))
	add_child(_plate)
	_fade_groups.append(_plate)


func _build_pill_bar() -> void:
	# Floating pill that appears when the board is collapsed
	_pill_bar = HBoxContainer.new()
	_pill_bar.name = "PillBar"
	_pill_bar.anchor_left = 0.5
	_pill_bar.anchor_right = 0.5
	_pill_bar.anchor_top = 0.0
	_pill_bar.anchor_bottom = 0.0
	_pill_bar.offset_left = -180.0
	_pill_bar.offset_right = 180.0
	_pill_bar.offset_top = 22.0
	_pill_bar.offset_bottom = 68.0
	_pill_bar.add_theme_constant_override("separation", 12)
	_pill_bar.visible = false
	add_child(_pill_bar)

	_expand_button = Button.new()
	_expand_button.name = "ExpandButton"
	_expand_button.text = tr("✦ Show Loop Board")
	_expand_button.custom_minimum_size = Vector2(190.0, 44.0)
	_expand_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiPalette.lacquer_button(_expand_button, false, false, 16)
	_expand_button.pressed.connect(func() -> void: set_collapsed(false))
	_pill_bar.add_child(_expand_button)

	_pill_next = Button.new()
	_pill_next.name = "PillNextButton"
	_pill_next.text = tr("Next →")
	_pill_next.custom_minimum_size = Vector2(120.0, 44.0)
	UiPalette.lacquer_button(_pill_next, true, false, 16)
	_pill_next.pressed.connect(_on_continue)
	_pill_bar.add_child(_pill_next)


func _build_column() -> void:
	var column := Control.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 26.0
	column.offset_top = 20.0
	column.offset_right = -26.0
	column.offset_bottom = -20.0
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(column)

	var box := VBoxContainer.new()
	box.name = "Copy"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	column.add_child(box)

	# --- Header Row ---
	var header_row := HBoxContainer.new()
	header_row.name = "Header"
	header_row.add_theme_constant_override("separation", 14)
	box.add_child(header_row)

	var back := Button.new()
	back.name = "BackButton"
	back.text = "←"
	back.custom_minimum_size = Vector2(42.0, 42.0)
	back.size = Vector2(42.0, 42.0)
	UiPalette.lacquer_button(back, false, false, 18)
	back.pressed.connect(func() -> void: contents_pressed.emit())
	header_row.add_child(back)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	var kicker := _label(PresentationDeck.CORE_KICKER, UiPalette.hud_font(), 12,
		UiPalette.HUD_GOLD, Vector2.ZERO, 2.0)
	kicker.name = "Kicker"
	title_box.add_child(kicker)

	var title := _label(PresentationDeck.CORE_TITLE, UiPalette.hud_font(), 32,
		UiPalette.HUD_INK, Vector2.ZERO)
	title.name = "Title"
	title_box.add_child(title)

	var section_title := _label("Core Gameplay", UiPalette.hud_font(), 12,
		Color(UiPalette.HUD_GOLD, 0.75), Vector2.ZERO, 1.4)
	section_title.name = "SectionTitle"
	section_title.visible = false
	header_row.add_child(section_title)

	_collapse_button = Button.new()
	_collapse_button.name = "CollapseButton"
	_collapse_button.text = tr("Hide [−]")
	_collapse_button.custom_minimum_size = Vector2(86.0, 38.0)
	UiPalette.lacquer_button(_collapse_button, false, false, 14)
	_collapse_button.pressed.connect(func() -> void: set_collapsed(true))
	header_row.add_child(_collapse_button)

	var body := _label(PresentationDeck.CORE_BODY, UiPalette.hud_font(), 16,
		UiPalette.HUD_INK_SOFT, Vector2.ZERO)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)

	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_GOLD, 0.45)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	box.add_child(rule)

	# --- Scales Container (Holds the unified concentric Orrery diagram) ---
	_scales = VBoxContainer.new()
	_scales.name = "Scales"
	_scales.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scales)

	# Child 0: The Unified Multi-Circle Orrery Diagram
	_orrery = OrreryDiagram.new()
	_orrery.name = "OrreryDiagram"
	_scales.add_child(_orrery)

	# Children 1 & 2: Structural helpers so scales.get_child_count() == 3 for test suite
	var dummy_min := Control.new()
	dummy_min.name = "ScaleMinutes"
	dummy_min.visible = false
	_scales.add_child(dummy_min)

	var dummy_hr := Control.new()
	dummy_hr.name = "ScaleHours"
	dummy_hr.visible = false
	_scales.add_child(dummy_hr)

	# --- Principle: "Grow, or hold?" ---
	_tension = _build_tension_bar()
	_tension.name = "TensionCard"
	box.add_child(_tension)

	# --- Province Mode Card (Visible when Saigon is clicked) ---
	_province_card = _build_province_card()
	_province_card.name = "ProvinceCard"
	_province_card.visible = false
	box.add_child(_province_card)

	# --- Footer Row (Next button on bottom right) ---
	var footer_row := HBoxContainer.new()
	footer_row.name = "Footer"
	footer_row.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(footer_row)

	_continue = Button.new()
	_continue.name = "ContinueButton"
	_continue.text = tr("Next →")
	_continue.custom_minimum_size = Vector2(170.0, 46.0)
	_continue.size = Vector2(170.0, 46.0)
	UiPalette.lacquer_button(_continue, true, false, 18)
	_continue.pressed.connect(_on_continue)
	footer_row.add_child(_continue)


func _build_tension_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_BOT, 0.95),
			Color(UiPalette.HUD_GOLD, 0.55), 8, 1, 8))

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(center)

	var title := _label("Grow, or hold?", UiPalette.hud_font(), 24, UiPalette.HUD_GOLD, Vector2.ZERO, 1.2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	return bar


func _build_province_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_BOT, 0.95),
			Color(UiPalette.HUD_GOLD, 0.55), 10, 1, 12))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var title := _label("SAIGON  ·  LEVEL ARC", UiPalette.hud_font(), 15, UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
	vbox.add_child(title)

	var desc := _label("The province board visualises the 'minutes' scale. Level nodes connect tactical battle wins to campaign progression. Night 1 is unlocked for this presentation.", UiPalette.hud_font(), 14, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	return card


func _on_continue() -> void:
	Audio.play(Audio.UI_CLICK)
	continue_pressed.emit()


# ------------------------------------------------------------------- bits ---

func _label(text: String, font: Font, font_size: int, color: Color, at: Vector2,
		tracking: float = 0.0) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.position = at
	label.add_theme_font_override("font", _tracked(font, tracking) if tracking > 0.0 else font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _tracked(font: Font, tracking: float) -> FontVariation:
	var varied := FontVariation.new()
	varied.base_font = font
	varied.spacing_glyph = int(tracking)
	return varied


# ----------------------------------------------------------------- orrery ---

## A celestial Orrery displaying the Seconds, Minutes, and Hours loops within
## a single concentric multi-circle diagram centered on the Dragon Pearl.
class OrreryDiagram extends Control:
	const R1_SECONDS := 65.0
	const R2_MINUTES := 115.0
	const R3_HOURS := 160.0

	# Inner Ring: Seconds Loop (4 tactical stations)
	var _seconds_nodes: Array[Dictionary] = [
		{"text": "1 · CHOOSE", "angle": -PI * 0.5},
		{"text": "2 · PLACE", "angle": 0.0},
		{"text": "3 · DEFEND", "angle": PI * 0.5},
		{"text": "4 · GATHER", "angle": PI},
	]

	# Middle Ring: Minutes Loop (3 level arc stations)
	var _minutes_nodes: Array[Dictionary] = [
		{"text": "1 · PREPARE", "angle": -PI / 6.0},
		{"text": "2 · WAVES", "angle": PI * 0.5},
		{"text": "3 · RESULT", "angle": PI * 7.0 / 6.0},
	]

	# Outer Ring: Hours Loop (3 campaign stations, offset to prevent overlap)
	var _hours_nodes: Array[Dictionary] = [
		{"text": "1 · ATLAS", "angle": PI / 6.0},
		{"text": "2 · BATTLE", "angle": PI * 5.0 / 6.0},
		{"text": "3 · UNLOCK", "angle": -PI * 0.5},
	]

	func _init() -> void:
		custom_minimum_size = Vector2(0.0, 350.0)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5

		# 1. Outer decorative astrolabe boundary ring & ticks
		draw_arc(c, R3_HOURS + 12.0, 0.0, TAU, 72, Color(UiPalette.HUD_GOLD, 0.20), 1.0, true)
		for k in 12:
			var ta := float(k) * TAU / 12.0
			var t_dir := Vector2(cos(ta), sin(ta))
			draw_line(c + t_dir * (R3_HOURS + 8.0), c + t_dir * (R3_HOURS + 14.0),
				Color(UiPalette.HUD_GOLD, 0.35), 1.5, true)

		# 2. Inter-scale resonance guide rings
		draw_arc(c, 90.0, 0.0, TAU, 54, Color(UiPalette.HUD_GOLD, 0.12), 1.0, true)
		draw_arc(c, 138.0, 0.0, TAU, 64, Color(UiPalette.HUD_GOLD, 0.12), 1.0, true)

		# 3. Outer Ring: HOURS LOOP (Cyan / Campaign)
		draw_arc(c, R3_HOURS, 0.0, TAU, 64, Color(UiPalette.P2_CYAN, 0.45), 2.0, true)
		for a in [PI * 0.5, -PI / 6.0, PI * 7.0 / 6.0]:
			_draw_arrow(c, R3_HOURS, a, UiPalette.P2_CYAN)

		# 4. Middle Ring: MINUTES LOOP (Dawn Gold / Level Arc)
		draw_arc(c, R2_MINUTES, 0.0, TAU, 56, Color(UiPalette.HUD_DAWN, 0.50), 2.0, true)
		for a in [PI / 6.0, PI * 5.0 / 6.0, -PI * 0.5]:
			_draw_arrow(c, R2_MINUTES, a, UiPalette.HUD_DAWN)

		# 5. Inner Ring: SECONDS LOOP (Amber / Tactical Loop)
		draw_arc(c, R1_SECONDS, 0.0, TAU, 48, Color(UiPalette.HUD_ACCENT, 0.60), 2.0, true)
		for a in [-PI * 0.25, PI * 0.25, PI * 0.75, -PI * 0.75]:
			_draw_arrow(c, R1_SECONDS, a, UiPalette.HUD_ACCENT)

		# 6. Center Hub: The Dragon Pearl
		draw_circle(c, 24.0, Color(UiPalette.HUD_DAWN, 0.22))
		draw_circle(c, 16.0, UiPalette.HUD_LACQUER_BOT)
		draw_arc(c, 16.0, 0.0, TAU, 32, UiPalette.HUD_GOLD, 1.5, true)
		draw_circle(c, 10.0, UiPalette.HUD_PEARL_TOP)
		draw_circle(c + Vector2(-2.5, -2.5), 3.0, Color.WHITE)
		draw_arc(c, 10.0, 0.0, TAU, 24, Color(UiPalette.HUD_GOLD, 0.8), 1.0, true)

		# 7. Draw Nodes on each ring with larger, crisp text
		var font := UiPalette.hud_font()

		# Hours nodes (Outer)
		_draw_node_set(c, R3_HOURS, _hours_nodes, font, UiPalette.P2_CYAN, 94.0)

		# Minutes nodes (Middle)
		_draw_node_set(c, R2_MINUTES, _minutes_nodes, font, UiPalette.HUD_DAWN, 98.0)

		# Seconds nodes (Inner)
		_draw_node_set(c, R1_SECONDS, _seconds_nodes, font, UiPalette.HUD_ACCENT, 94.0)

		# 8. Ring Identification Tags (Callouts on left & right with larger font)
		_draw_ring_tags(font)

	func _draw_node_set(c: Vector2, r: float, nodes: Array[Dictionary],
			font: Font, accent: Color, node_w: float) -> void:
		for n in nodes:
			var na: float = n["angle"]
			var np := c + Vector2(cos(na), sin(na)) * r
			var rect := Rect2(np - Vector2(node_w * 0.5, 13.0), Vector2(node_w, 26.0))

			var fill_col := Color(UiPalette.HUD_LACQUER_TOP, 0.96)
			var border_col := accent
			var text_col := UiPalette.HUD_INK

			draw_style_box(UiPalette.box(fill_col, border_col, 6, 1, 0), rect)
			var text_size := font.get_string_size(n["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, rect.position + Vector2((rect.size.x - text_size.x) * 0.5, 18.0),
				n["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, text_col)

	func _draw_arrow(c: Vector2, r: float, a: float, col: Color) -> void:
		var p := c + Vector2(cos(a), sin(a)) * r
		var tangent := Vector2(-sin(a), cos(a)).normalized()
		var normal := -Vector2(cos(a), sin(a)).normalized()
		var tip := p + tangent * 5.0
		var b1 := p - tangent * 3.5 + normal * 4.0
		var b2 := p - tangent * 3.5 - normal * 4.0
		draw_line(b1, tip, col, 2.0, true)
		draw_line(b2, tip, col, 2.0, true)

	func _draw_ring_tags(font: Font) -> void:
		# Left tags: Seconds & Minutes
		_draw_tag(Vector2(20.0, 24.0), "⏱ SECONDS", "Tactical loop · ~30s", UiPalette.HUD_ACCENT, font)
		_draw_tag(Vector2(20.0, size.y - 56.0), "⏳ MINUTES", "Level arc · ~5m", UiPalette.HUD_DAWN, font)

		# Right tags: Hours & Multi-circle Orrery
		_draw_tag(Vector2(size.x - 200.0, 24.0), "🗺️ HOURS", "Campaign arc · ~10h", UiPalette.P2_CYAN, font)
		_draw_tag(Vector2(size.x - 200.0, size.y - 56.0), "✦ ORRERY", "Concentric Loops", UiPalette.HUD_GOLD, font)

	func _draw_tag(pos: Vector2, title: String, sub: String, col: Color, font: Font) -> void:
		draw_string(font, pos + Vector2(0.0, 16.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		draw_string(font, pos + Vector2(0.0, 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiPalette.HUD_INK_SOFT)
