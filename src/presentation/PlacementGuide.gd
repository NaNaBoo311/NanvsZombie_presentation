class_name PlacementGuide
extends Control

# Section 02, beat 3: the five placement rules, live. The guide never decides
# anything — PlacementManager still validates the ghost — it reads the same
# public state the manager reads and shows which of the five checks are passing
# for the tile under the cursor. The facing dial follows the ghost's 45° step.
#
# It updates on EventBus signals only: a resting cursor costs nothing, and the
# checks are recomputed at most once per hovered tile / rotation / gem change.

signal continue_pressed

const PANEL_WIDTH := 302.0
const MARGIN := 28.0
const DOT := 11.0

var placement: PlacementManager = null

var _panel: PanelContainer
var _seed: Label
var _dots: Array[Panel] = []
var _checks: Array[Label] = []
var _compass: FacingCompass
var _facing: Label
var _continue: Button
var _plant := ""
var _coord := Vector2i(-999, -999)
var _step := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_panel()
	EventBus.placement_preview_changed.connect(_on_preview)
	EventBus.plant_selected_for_placement.connect(_on_selected)
	EventBus.placement_cancelled.connect(_on_cancelled)
	EventBus.sun_amount_changed.connect(func(_n: int) -> void: _refresh())
	EventBus.seed_cooldown_started.connect(func(_p: String) -> void: _refresh())
	EventBus.seed_cooldown_finished.connect(func(_p: String) -> void: _refresh())
	EventBus.plant_placed.connect(func(_p: String, _c: Vector2i, _i: int) -> void: _refresh())
	resized.connect(_place)
	_refresh()
	visible = false


func play_intro() -> void:
	visible = true
	modulate.a = 0.0
	_refresh()
	_place()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# ------------------------------------------------------------------- build ---

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel",
		UiPalette.lacquer_box(UiPalette.HUD_LACQUER_TOP, Color(UiPalette.HUD_GOLD, 0.85),
			10, 2, 18))
	add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Copy"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var kicker := _label("PLACEMENT", 10, UiPalette.HUD_GOLD, 2.4)
	box.add_child(kicker)

	var title := _label(PresentationDeck.CORE_PLACEMENT_TITLE, 22, UiPalette.HUD_INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)

	var rule := ColorRect.new()
	rule.color = Color(UiPalette.HUD_GOLD, 0.45)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	box.add_child(rule)

	_seed = _label("", 12, UiPalette.HUD_ACCENT, 1.2)
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seed.custom_minimum_size = Vector2(0.0, 34.0)
	box.add_child(_seed)

	for text in PresentationDeck.CORE_CHECKS:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override("separation", 9)
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(DOT, DOT)
		dot.size = Vector2(DOT, DOT)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(dot)
		_dots.append(dot)
		var label := _label(str(text), 13, UiPalette.HUD_INK_SOFT)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(label)
		_checks.append(label)
		box.add_child(row)

	var dial := VBoxContainer.new()
	dial.name = "Facing"
	dial.alignment = BoxContainer.ALIGNMENT_CENTER
	dial.add_theme_constant_override("separation", 4)
	box.add_child(dial)

	_compass = FacingCompass.new()
	_compass.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dial.add_child(_compass)

	_facing = _label(PresentationDeck.CORE_FACING_HINT, 11, UiPalette.HUD_INK_SOFT, 1.2)
	_facing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dial.add_child(_facing)

	var shortcuts := _label("G · Spawn ghost  •  TAB · Seeds  •  X · Shovel", 11, UiPalette.HUD_INK_SOFT)
	shortcuts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(shortcuts)

	_continue = Button.new()
	_continue.name = "ContinueButton"
	_continue.text = tr(PresentationDeck.CORE_BACK)
	_continue.custom_minimum_size = Vector2(0.0, 44.0)
	_continue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue.mouse_filter = Control.MOUSE_FILTER_STOP
	UiPalette.lacquer_button(_continue, true, false, 18)
	_continue.pressed.connect(_on_continue)
	box.add_child(_continue)

	_place()


func _place() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0 or _panel == null:
		return
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)
	_panel.reset_size()
	var height := maxf(_panel.get_combined_minimum_size().y, _panel.size.y)
	_panel.size = Vector2(PANEL_WIDTH, height)
	_panel.position = Vector2(view.x - PANEL_WIDTH - MARGIN, maxf((view.y - height) * 0.5, 20.0))


# ------------------------------------------------------------------ state ---

func _on_selected(plant_type: String, player_id: int) -> void:
	if player_id != GameManager.local_player_id():
		return
	_plant = plant_type
	_coord = Vector2i(-999, -999)
	_refresh()


func _on_cancelled(player_id: int) -> void:
	if player_id != GameManager.local_player_id():
		return
	_plant = ""
	_coord = Vector2i(-999, -999)
	_refresh()


func _on_preview(plant_type: String, coord: Vector2i, rot_step: int,
		_plantable: bool, player_id: int) -> void:
	if player_id != GameManager.local_player_id():
		return
	_plant = plant_type
	_coord = coord
	_step = rot_step
	_refresh()


func _refresh() -> void:
	if _seed == null:
		return
	_seed.text = _seed_line()
	var states := _states()
	for i in _dots.size():
		_paint_dot(_dots[i], states[i])
		_checks[i].add_theme_color_override("font_color",
			UiPalette.HUD_INK if states[i] == 1 else
			(UiPalette.HUD_DANGER_TEXT if states[i] == 2 else UiPalette.HUD_INK_SOFT))
	_compass.set_step(_step if not _plant.is_empty() else -1)
	_facing.text = _facing_line()
	_panel.reset_size()
	_place()


func _seed_line() -> String:
	if _plant.is_empty():
		return tr("Pick a seed from the bank.")
	var name := tr(str(BalanceDB.get_unit(_plant).get("name", _plant)))
	var role := ""
	for spec: Dictionary in PresentationDeck.CORE_ROLES:
		if str(spec["id"]) == _plant:
			role = str(spec["role"])
	if role.is_empty():
		return name
	return "%s  ·  %s" % [name.to_upper(), role]


func _facing_line() -> String:
	if _plant.is_empty() or _step < 0:
		return PresentationDeck.CORE_FACING_HINT
	return tr("Facing %s  ·  R / Shift+R") % FACINGS[_step & 7]


## 0 = not asked yet, 1 = pass, 2 = fail. Same order as PresentationDeck.CORE_CHECKS.
func _states() -> Array[int]:
	var states: Array[int] = [0, 0, 0, 0, 0]
	if _plant.is_empty() or _coord == Vector2i(-999, -999) or placement == null:
		return states
	var pos := placement.position_for_tile(_coord)
	states[0] = 1 if placement._is_in_placeable_square(pos) else 2
	states[1] = 2 if placement._in_pearl_footprint(pos) else 1
	states[2] = 2 if placement.occupied_tiles.has(_coord) else 1
	states[3] = 1 if GameManager.can_afford(_plant) else 2
	states[4] = 2 if GameManager.is_seed_cooling(_plant) else 1
	return states


func _paint_dot(dot: Panel, state: int) -> void:
	var fill := UiPalette.HUD_SEAL_EMPTY
	var edge := Color(UiPalette.HUD_GOLD, 0.35)
	if state == 1:
		fill = UiPalette.HUD_HEALTH
		edge = UiPalette.HUD_HEALTH.lightened(0.3)
	elif state == 2:
		fill = UiPalette.HUD_DANGER
		edge = UiPalette.HUD_DANGER_TEXT
	dot.add_theme_stylebox_override("panel",
		UiPalette.box(fill, edge, int(DOT * 0.5), 1, 0))


func _on_continue() -> void:
	Audio.play(Audio.UI_CLICK)
	continue_pressed.emit()


# ------------------------------------------------------------------- bits ---

const FACINGS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]


func _label(text: String, font_size: int, color: Color, tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = tr(text)
	var font := UiPalette.hud_font()
	if tracking != 0:
		var varied := FontVariation.new()
		varied.base_font = font
		varied.spacing_glyph = tracking
		font = varied
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## Eight 45° ticks; step 0 faces +Z (toward the camera) and sits at the bottom,
## matching PlacementManager.ROTATION_ANGLES. Redraws only when the step changes.
class FacingCompass extends Control:
	const SIZE := Vector2(96.0, 96.0)

	var step := -1

	func _init() -> void:
		custom_minimum_size = SIZE
		size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_step(value: int) -> void:
		if value == step:
			return
		step = value
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 6.0
		draw_circle(c, r, Color(UiPalette.HUD_LACQUER_BOT, 0.9))
		draw_arc(c, r, 0.0, TAU, 40, Color(UiPalette.HUD_GOLD, 0.35), 1.0, true)
		for k in 8:
			var angle := PI * 0.5 + float(k) * PI * 0.25
			var dir := Vector2(cos(angle), sin(angle))
			var active := k == step
			draw_line(c + dir * (r - (16.0 if active else 10.0)), c + dir * (r - 4.0),
				UiPalette.HUD_ACCENT if active else Color(UiPalette.HUD_GOLD, 0.45),
				4.0 if active else 2.0, true)
		draw_circle(c, 4.0, Color(UiPalette.HUD_GOLD, 0.6))
