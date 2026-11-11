class_name EnemyStatesBeat
extends Control

# Section 02, beat 4: the shared state chain, walked by a real hungry ghost on the
# real lawn. The strip never drives the ghost — it reads HungryGhost.ai_state()
# on a 10 Hz timer while one is alive, so the chips can only ever show what the AI
# is actually doing. SPAWN lights on the summon itself (the mound telegraph and the
# rise happen before the ghost enters the tree), the rest are polled.
#
# Summoning goes through EnemySpawner.request_demo_spawn(), which is the only path
# that attaches a nav route, so ROUTE is real. A presenter's Lotus Shooter can kill
# the demo ghost: the chain then stops on the slide's own last rule, "any active
# state dies at zero health", and Summon again starts a fresh one.

signal finished

const MARGIN := 28.0
const CHIP_SIZE := Vector2(88.0, 30.0)
const SIEGE_SIZE := Vector2(88.0, 26.0)
const TOP_SLOT := 28.0
const POLL_SEC := 0.1
const GHOST_ID := "hungry_ghost"
const GHOST_REGION := "north"

var spawner: EnemySpawner = null

var _strip: PanelContainer
var _chips: Dictionary = {}
var _line: Label
var _branches: Label
var _summon: Button
var _finish: Button
var _timer: Timer
var _ghost: Node3D = null
var _state := ""
var _visited: Dictionary = {}
var _waiting := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_strip()
	_timer = Timer.new()
	_timer.wait_time = POLL_SEC
	_timer.timeout.connect(_poll)
	add_child(_timer)
	EventBus.enemy_spawned.connect(_on_enemy_spawned)
	visible = false


func play_intro() -> void:
	visible = true
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_place.call_deferred()


func stop() -> void:
	_timer.stop()
	visible = false


# ------------------------------------------------------------------- build ---

func _build_strip() -> void:
	_strip = PanelContainer.new()
	_strip.name = "Strip"
	_strip.anchor_right = 1.0
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.add_theme_stylebox_override("panel",
		UiPalette.lacquer_box(Color(UiPalette.HUD_LACQUER_TOP, 0.97),
			Color(UiPalette.HUD_GOLD, 0.85), 12, 2, 16))
	add_child(_strip)

	var box := VBoxContainer.new()
	box.name = "Copy"
	box.add_theme_constant_override("separation", 6)
	_strip.add_child(box)

	box.add_child(_chain())

	_branches = _label("EAT  ─ plant destroyed ─▶  MARCH", 10, Color(UiPalette.HUD_INK_SOFT, 0.8), 1.0)
	_branches.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_branches)

	_line = _label("", 15, UiPalette.HUD_INK)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(0.0, 40.0)
	box.add_child(_line)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	_summon = Button.new()
	_summon.name = "SummonButton"
	_summon.text = tr(PresentationDeck.CORE_SUMMON)
	_summon.custom_minimum_size = Vector2(196.0, 44.0)
	_summon.size = Vector2(196.0, 44.0)
	UiPalette.lacquer_button(_summon, false, false, 18)
	_summon.pressed.connect(_summon_pressed)
	buttons.add_child(_summon)

	_finish = Button.new()
	_finish.name = "FinishButton"
	_finish.text = tr(PresentationDeck.CORE_BACK)
	_finish.custom_minimum_size = Vector2(196.0, 44.0)
	_finish.size = Vector2(196.0, 44.0)
	UiPalette.lacquer_button(_finish, true, false, 18)
	_finish.pressed.connect(_on_finish)
	buttons.add_child(_finish)


func _chain() -> Control:
	var row := HBoxContainer.new()
	row.name = "Chain"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	var states: Array = PresentationDeck.CORE_STATES
	for i in states.size():
		if i > 0:
			var arrow := _label("›", 14, UiPalette.HUD_INK_SOFT)
			arrow.custom_minimum_size = Vector2(10.0, TOP_SLOT + CHIP_SIZE.y)
			arrow.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			row.add_child(arrow)
		row.add_child(_chain_cell(str(states[i])))
	return row


func _chain_cell(state: String) -> Control:
	var key := state.to_lower()
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 4)
	var top := Control.new()
	top.custom_minimum_size = Vector2(0.0, TOP_SLOT)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(top)
	if key == "march":
		# The siege branch sits over MARCH, exactly where the slide puts it.
		var siege := _chip(PresentationDeck.CORE_SIEGE, SIEGE_SIZE)
		siege.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		top.add_child(siege)
		siege.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cell.add_child(_chip(key, CHIP_SIZE))
	return cell


func _chip(state: String, chip_size: Vector2) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "Chip_%s" % state
	chip.custom_minimum_size = chip_size
	chip.size = chip_size
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(state, 10, UiPalette.HUD_INK_SOFT, 1.8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(label)
	_chips[state.to_lower()] = chip
	_paint_chip(chip, 0)
	return chip


func _place() -> void:
	if _strip == null:
		return
	var view := get_viewport_rect().size
	var height := _strip.get_combined_minimum_size().y
	_strip.offset_left = MARGIN
	_strip.offset_right = -MARGIN
	_strip.offset_top = view.y - height - MARGIN
	_strip.offset_bottom = view.y - MARGIN


# ------------------------------------------------------------------ summon ---

func _summon_pressed() -> void:
	if spawner == null:
		return
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	_waiting = false
	_visited.clear()
	_state = ""
	_summon.disabled = true
	_summon.text = tr(PresentationDeck.CORE_SUMMON)
	# The mound telegraph and the rise are the spawn state; the ghost enters the
	# tree only after them, so light SPAWN here rather than waiting for a poll.
	_set_state("spawn")
	_waiting = true
	if not spawner.request_demo_spawn(GHOST_ID, GHOST_REGION):
		_waiting = false
		_summon.disabled = false
		_line.text = tr("No nav region on this map.")


func _on_enemy_spawned(enemy: Node3D) -> void:
	if not _waiting:
		return
	_waiting = false
	_ghost = enemy
	_summon.disabled = false
	_timer.start()


func _poll() -> void:
	if not is_instance_valid(_ghost):
		_timer.stop()
		return
	var state := str(_ghost.call("ai_state")) if _ghost.has_method("ai_state") else ""
	if state.is_empty():
		return
	_set_state(state)
	if state == "dead":
		_timer.stop()
		_summon.text = tr(PresentationDeck.CORE_SUMMON_AGAIN)


func _set_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	_visited[state] = true
	for key in _chips:
		var chip: PanelContainer = _chips[key]
		_paint_chip(chip, 2 if key == state else (1 if _visited.has(key) else 0))
	_line.text = tr(str(PresentationDeck.CORE_STATE_LINES.get(state, "")))
	_place.call_deferred()


func _paint_chip(chip: PanelContainer, state: int) -> void:
	var fill := UiPalette.HUD_LACQUER_BOT
	var edge := Color(UiPalette.HUD_GOLD, 0.30)
	var ink := Color(UiPalette.HUD_INK_SOFT, 0.70)
	if state == 1:
		fill = UiPalette.HUD_LACQUER_LIT
		edge = Color(UiPalette.HUD_GOLD, 0.85)
		ink = UiPalette.HUD_GOLD
	elif state == 2:
		fill = UiPalette.HUD_GOLD
		edge = UiPalette.HUD_ACCENT
		ink = UiPalette.HUD_SEAL_INK
	chip.add_theme_stylebox_override("panel", UiPalette.lacquer_box(fill, edge, 6, 2, 8))
	var label := chip.get_child(0) as Label
	if label != null:
		label.add_theme_color_override("font_color", ink)


func _on_finish() -> void:
	Audio.play(Audio.UI_CLICK)
	_timer.stop()
	finished.emit()


## The demo ghost, while one is alive (the field frees it when the beat ends).
func ghost() -> Node3D:
	return _ghost if is_instance_valid(_ghost) else null


# ------------------------------------------------------------------- bits ---

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
