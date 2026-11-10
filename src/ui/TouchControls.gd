class_name TouchControls
extends Control

# On-screen controls for phones/tablets. HUD creates this node only when
# GameManager.is_touch_ui() (and never under --perf-test), so a desktop/solo
# scene has no extra nodes and no extra draw calls.
#
# Only the actions that a touchscreen cannot express are here:
#   - Pause (top-right): there is no Esc key on a phone.
#   - Rotate left/right while a seed is in hand: there is no R key.
#   - Cancel while placing or holding the shovel: there is no right-click.
# Seed selection, the shovel card, planting and digging all use the existing
# HUD and world touches, so the layout stays the one players already know.
#
# Buttons are HudHits painted by HudCanvas, with drawn glyphs, so the row adds no
# draws of its own. Signal-driven and allocation-free after _ready: no _process, no
# polling. process_mode ALWAYS so Pause still answers while the tree is paused.

const BUTTON_SIZE := 64.0
const EDGE := 16.0
const GAP := 10.0
const ROW_WIDTH := BUTTON_SIZE * 3.0 + GAP * 2.0
## The HUD owns the bottom of a narrow screen (Leyline -96..-52, hint slip -44..-14:
## HUD.gd, HintSlip.gd). The edit row floats above both instead of covering them.
const BOTTOM_BAND := 104.0

var _pause: HudHit
var _rotate_left: HudHit
var _rotate_right: HudHit
var _cancel: HudHit
var _edit_row: HBoxContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	HudCanvas.register(self, 80)
	EventBus.plant_selected_for_placement.connect(_on_plant_selected)
	EventBus.plant_placed.connect(_on_plant_placed)
	EventBus.placement_cancelled.connect(_on_placement_cancelled)
	EventBus.shovel_mode_changed.connect(_on_shovel_mode_changed)
	EventBus.round_state_changed.connect(_on_round_state_changed)
	_refresh()

func _build() -> void:
	_pause = _make_button()
	_pause.name = "Pause"
	_pause.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause.offset_left = -EDGE - BUTTON_SIZE
	_pause.offset_top = EDGE
	_pause.offset_right = -EDGE
	_pause.offset_bottom = EDGE + BUTTON_SIZE
	_pause.pressed.connect(func() -> void: EventBus.pause_requested.emit())
	add_child(_pause)
	SafeArea.apply(_pause)

	_edit_row = HBoxContainer.new()
	_edit_row.name = "EditTools"
	_edit_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edit_row.add_theme_constant_override("separation", int(GAP))
	_edit_row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_edit_row.offset_left = -EDGE - ROW_WIDTH
	_edit_row.offset_top = -BOTTOM_BAND - BUTTON_SIZE
	_edit_row.offset_right = -EDGE
	_edit_row.offset_bottom = -BOTTOM_BAND
	add_child(_edit_row)

	_rotate_left = _make_button()
	_rotate_left.name = "RotateLeft"
	_rotate_left.pressed.connect(func() -> void: EventBus.placement_rotate_pressed.emit(-1, GameManager.local_player_id()))
	_edit_row.add_child(_rotate_left)

	_rotate_right = _make_button()
	_rotate_right.name = "RotateRight"
	_rotate_right.pressed.connect(func() -> void: EventBus.placement_rotate_pressed.emit(1, GameManager.local_player_id()))
	_edit_row.add_child(_rotate_right)

	_cancel = _make_button()
	_cancel.name = "Cancel"
	_cancel.pressed.connect(_on_cancel)
	_edit_row.add_child(_cancel)
	SafeArea.apply(_edit_row)

func _make_button() -> HudHit:
	var button := HudHit.new()
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button


func paint_hud(p: HudPainter) -> void:
	var c := Vector2(BUTTON_SIZE, BUTTON_SIZE) * 0.5
	if _pause.is_visible_in_tree():
		_paint_button(p, _pause)
		p.glyph_pause(c, _ink(_pause))
	if _rotate_left.is_visible_in_tree():
		_paint_button(p, _rotate_left)
		p.glyph_rotate(c, -1, _ink(_rotate_left))
		_paint_button(p, _rotate_right)
		p.glyph_rotate(c, 1, _ink(_rotate_right))
	if _cancel.is_visible_in_tree():
		_paint_button(p, _cancel)
		p.glyph_cross(c, _ink(_cancel))


func _paint_button(p: HudPainter, hit: HudHit) -> void:
	p.xf = hit.get_global_transform()
	p.button(hit, hit.size)


func _ink(hit: HudHit) -> Color:
	return UiPalette.HUD_SEAL_INK if hit.is_pressed() else UiPalette.HUD_INK


func _on_cancel() -> void:
	if GameManager == null:
		return
	var local_id: int = GameManager.local_player_id()
	if GameManager.is_shovel_for(local_id):
		GameManager.cancel_shovel(local_id)
	elif not GameManager.selected_plant_for(local_id).is_empty():
		GameManager.clear_selection(local_id)

func _refresh() -> void:
	if GameManager == null:
		return
	var local_id: int = GameManager.local_player_id()
	var placing := not GameManager.selected_plant_for(local_id).is_empty()
	var shovelling := GameManager.is_shovel_for(local_id)
	_rotate_left.visible = placing
	_rotate_right.visible = placing
	_cancel.visible = placing or shovelling
	_edit_row.visible = _cancel.visible
	_pause.visible = GameManager.round_state in ["setup", "wave", "sandbox"]
	HudCanvas.dirty()

func _on_plant_selected(_plant_type: String, player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_refresh()

func _on_plant_placed(_plant_type: String, _grid_coord: Vector2i, player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_refresh()

func _on_placement_cancelled(player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_refresh()

func _on_shovel_mode_changed(_active: bool, player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_refresh()

func _on_round_state_changed(_state: String) -> void:
	_refresh()
