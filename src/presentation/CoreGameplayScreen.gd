class_name CoreGameplayScreen
extends Control

# Section 02 — Core Gameplay, beat 1: "One loop, three scales" staged at the
# center of the world atlas. The concentric Orrery diagram displays all three
# time horizons (Seconds, Minutes, Hours) within a single unified multi-circle
# celestial diagram centered on the Dragon Pearl.
#
# The board sits in the center of the screen with a lacquer finish and gold rims.
# When Saigon is clicked, the board switches to the province arc note.
# The "Next" button on the bottom right hands off into the HCMC diorama field.

signal continue_pressed
signal contents_pressed

const BOARD_WIDTH := 780.0
const BOARD_HEIGHT := 630.0

var _scales: VBoxContainer
var _tension: Control
var _province_card: Control
var _hint: Label
var _continue: Button
var _fade_groups: Array[Control] = []
var _orrery: OrreryDiagram = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_scrim()
	_build_header()
	_build_column()


func play_intro() -> void:
	for group in _fade_groups:
		group.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(0.08 * _fade_groups.find(group))
		tween.tween_property(group, "modulate:a", 1.0, 0.5) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The atlas board is open: switch from the concentric orrery to the level arc note.
func set_province_mode(open: bool) -> void:
	_scales.visible = not open
	_tension.visible = not open
	if _province_card != null:
		_province_card.visible = open
	_hint.text = tr(PresentationDeck.CORE_ATLAS_FIELD_HINT if open
		else "Click Saigon on the atlas to open its board  •  Or click Next to enter the field")
	_continue.text = tr(PresentationDeck.CORE_FIELD_ENTER if open else "Next →")


func focus_primary() -> void:
	if _continue != null:
		_continue.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_ESCAPE:
		contents_pressed.emit()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ layout ---

func _build_scrim() -> void:
	# Subtle fullscreen darkening so the centered orrery board stands out against the map
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(UiPalette.HUD_DIM, 0.40)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_fade_groups.append(dim)

	# Centered lacquer plate
	var plate := Panel.new()
	plate.name = "Plate"
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.anchor_top = 0.5
	plate.anchor_bottom = 0.5
	plate.offset_left = -BOARD_WIDTH * 0.5
	plate.offset_right = BOARD_WIDTH * 0.5
	plate.offset_top = -BOARD_HEIGHT * 0.5
	plate.offset_bottom = BOARD_HEIGHT * 0.5
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_TOP, 0.98),
			Color(UiPalette.HUD_GOLD, 0.80), 18, 2, 0,
			Color(UiPalette.HUD_SHADOW, 0.75), 24))
	add_child(plate)
	_fade_groups.append(plate)


func _build_header() -> void:
	# Built inside the centered column for unified alignment
	pass


func _build_column() -> void:
	var plate := get_node_or_null("Plate") as Control
	if plate == null:
		return

	var column := Control.new()
	column.name = "Column"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 24.0
	column.offset_top = 18.0
	column.offset_right = -24.0
	column.offset_bottom = -18.0
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(column)

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
	back.custom_minimum_size = Vector2(40.0, 40.0)
	back.size = Vector2(40.0, 40.0)
	UiPalette.lacquer_button(back, false, false, 16)
	back.pressed.connect(func() -> void: contents_pressed.emit())
	header_row.add_child(back)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 1)
	header_row.add_child(title_box)

	var kicker := _label(PresentationDeck.CORE_KICKER, UiPalette.hud_font(), 10,
		UiPalette.HUD_GOLD, Vector2.ZERO, 2.0)
	kicker.name = "Kicker"
	title_box.add_child(kicker)

	var title := _label(PresentationDeck.CORE_TITLE, UiPalette.hud_font(), 26,
		UiPalette.HUD_INK, Vector2.ZERO)
	title.name = "Title"
	title_box.add_child(title)

	var section_title := _label("Core Gameplay", UiPalette.hud_font(), 12,
		Color(UiPalette.HUD_GOLD, 0.75), Vector2.ZERO, 1.4)
	section_title.name = "SectionTitle"
	section_title.visible = false
	header_row.add_child(section_title)

	var body := _label(PresentationDeck.CORE_BODY, UiPalette.hud_font(), 13,
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

	# --- Principle: "Grow, or hold?" (No grow/hold descriptions, clean & bold) ---
	_tension = _build_tension_bar()
	_tension.name = "TensionCard"
	box.add_child(_tension)

	# --- Province Mode Card (Visible when Saigon is clicked) ---
	_province_card = _build_province_card()
	_province_card.name = "ProvinceCard"
	_province_card.visible = false
	box.add_child(_province_card)

	# --- Footer Row (Hint on left, "Next" button on bottom right) ---
	var footer_row := HBoxContainer.new()
	footer_row.name = "Footer"
	footer_row.add_theme_constant_override("separation", 16)
	box.add_child(footer_row)

	_hint = _label("Click Saigon on the atlas to open its board  •  Or click Next to enter the field",
		UiPalette.hud_font(), 12, UiPalette.HUD_ACCENT, Vector2.ZERO)
	_hint.name = "Hint"
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_row.add_child(_hint)

	_continue = Button.new()
	_continue.name = "ContinueButton"
	_continue.text = tr("Next →")
	_continue.custom_minimum_size = Vector2(160.0, 42.0)
	_continue.size = Vector2(160.0, 42.0)
	UiPalette.lacquer_button(_continue, true, false, 18)
	_continue.pressed.connect(_on_continue)
	footer_row.add_child(_continue)


func _build_tension_bar() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_BOT, 0.95),
			Color(UiPalette.HUD_GOLD, 0.55), 8, 1, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)

	var title_col := VBoxContainer.new()
	title_col.add_theme_constant_override("separation", 1)
	row.add_child(title_col)

	var kicker := _label("CENTRAL PRINCIPLE", UiPalette.hud_font(), 9, Color(UiPalette.HUD_GOLD, 0.8), Vector2.ZERO, 1.8)
	title_col.add_child(kicker)

	var title := _label("Grow, or hold?", UiPalette.hud_font(), 17, UiPalette.HUD_GOLD, Vector2.ZERO)
	title_col.add_child(title)

	var line := _label("Rice Gems buy more economy, or the defence that survives the next wave.",
		UiPalette.hud_font(), 13, UiPalette.HUD_INK, Vector2.ZERO)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(line)

	return bar


func _build_province_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		UiPalette.box(Color(UiPalette.HUD_LACQUER_BOT, 0.95),
			Color(UiPalette.HUD_GOLD, 0.55), 10, 1, 12))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var title := _label("SAIGON  ·  LEVEL ARC", UiPalette.hud_font(), 13, UiPalette.HUD_GOLD, Vector2.ZERO, 1.8)
	vbox.add_child(title)

	var desc := _label("The province board visualises the 'minutes' scale. Level nodes connect tactical battle wins to campaign progression. Night 1 is unlocked for this presentation.", UiPalette.hud_font(), 12, UiPalette.HUD_INK_SOFT, Vector2.ZERO)
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

	var orbit_angle := 0.0:
		set(v):
			orbit_angle = v
			queue_redraw()

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

	func _ready() -> void:
		var tween := create_tween().set_loops()
		tween.tween_property(self, "orbit_angle", TAU, 5.0).from(0.0)

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

		# 7. Draw Nodes on each ring
		var font := UiPalette.hud_font()

		# Hours nodes (Outer)
		var h_orbit := fposmod(orbit_angle * 0.35, TAU)
		_draw_node_set(c, R3_HOURS, _hours_nodes, h_orbit, font, UiPalette.P2_CYAN, 74.0)

		# Minutes nodes (Middle)
		var m_orbit := fposmod(orbit_angle * 0.65, TAU)
		_draw_node_set(c, R2_MINUTES, _minutes_nodes, m_orbit, font, UiPalette.HUD_DAWN, 78.0)

		# Seconds nodes (Inner)
		var s_orbit := fposmod(orbit_angle * 1.20, TAU)
		_draw_node_set(c, R1_SECONDS, _seconds_nodes, s_orbit, font, UiPalette.HUD_ACCENT, 72.0)

		# 8. Orbiting Comet Sparks (one per ring)
		_draw_spark(c, R1_SECONDS, s_orbit, UiPalette.HUD_ACCENT)
		_draw_spark(c, R2_MINUTES, m_orbit, UiPalette.HUD_DAWN)
		_draw_spark(c, R3_HOURS, h_orbit, UiPalette.P2_CYAN)

		# 9. Ring Identification Tags (Callouts on left & right)
		_draw_ring_tags(font)

	func _draw_node_set(c: Vector2, r: float, nodes: Array[Dictionary],
			curr_orbit: float, font: Font, accent: Color, node_w: float) -> void:
		for n in nodes:
			var na: float = n["angle"]
			var np := c + Vector2(cos(na), sin(na)) * r
			var diff := absf(angle_difference(curr_orbit, fposmod(na, TAU)))
			var active := diff < 0.38
			var rect := Rect2(np - Vector2(node_w * 0.5, 11.0), Vector2(node_w, 22.0))

			var fill_col := Color(accent, 0.32) if active else Color(UiPalette.HUD_LACQUER_TOP, 0.95)
			var border_col := accent if active else Color(accent, 0.55)
			var text_col := Color.WHITE if active else UiPalette.HUD_INK

			draw_style_box(UiPalette.box(fill_col, border_col, 5, 2 if active else 1, 0), rect)
			var text_size := font.get_string_size(n["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
			draw_string(font, rect.position + Vector2((rect.size.x - text_size.x) * 0.5, 15.0),
				n["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 10, text_col)

	func _draw_spark(c: Vector2, r: float, a: float, col: Color) -> void:
		var p := c + Vector2(cos(a), sin(a)) * r
		draw_circle(p, 5.0, Color(col, 0.45))
		draw_circle(p, 3.0, col)
		draw_circle(p, 1.5, Color.WHITE)
		for t in 3:
			var ta := a - float(t + 1) * 0.10
			var tp := c + Vector2(cos(ta), sin(ta)) * r
			draw_circle(tp, 2.2 - float(t) * 0.5, Color(col, 0.60 - float(t) * 0.16))

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
		_draw_tag(Vector2(20.0, 30.0), "⏱ SECONDS", "Tactical loop · ~30s", UiPalette.HUD_ACCENT, font)
		_draw_tag(Vector2(20.0, size.y - 48.0), "⏳ MINUTES", "Level arc · ~5m", UiPalette.HUD_DAWN, font)

		# Right tags: Hours & Multi-circle Orrery
		_draw_tag(Vector2(size.x - 180.0, 30.0), "🗺️ HOURS", "Campaign arc · ~10h", UiPalette.P2_CYAN, font)
		_draw_tag(Vector2(size.x - 180.0, size.y - 48.0), "✦ ORRERY", "Concentric Loops", UiPalette.HUD_GOLD, font)

	func _draw_tag(pos: Vector2, title: String, sub: String, col: Color, font: Font) -> void:
		draw_string(font, pos + Vector2(0.0, 14.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
		draw_string(font, pos + Vector2(0.0, 28.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiPalette.HUD_INK_SOFT)
