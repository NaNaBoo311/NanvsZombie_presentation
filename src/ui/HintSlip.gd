class_name HintSlip
extends Control

# The controls hint: one small slip that says only what applies right now. Idle it
# teaches the basics, then steps aside after a few plants; holding a seed or the shovel
# brings back the keys for that action. Touch devices never see keyboard keys. The
# dev keys (TAB, H, T) show only in the sandbox or with --dev-seeds. Painted by HudCanvas.

const PLANTS_TO_RETIRE := 3
const BOTTOM_GAP := 14.0
const HEIGHT := 30.0
const SIDE_PAD := 16.0

var _label: Label
var _plants_placed := 0
var _tween: Tween = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	offset_top = -BOTTOM_GAP - HEIGHT
	offset_bottom = -BOTTOM_GAP
	_label = UiPalette.hud_label(14, UiPalette.HUD_INK_SOFT)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)
	HudCanvas.register(self, 45)
	EventBus.plant_selected_for_placement.connect(func(_type: String, id: int) -> void: _on_mine(id))
	EventBus.plant_placed.connect(_on_plant_placed)
	EventBus.placement_cancelled.connect(_on_mine)
	EventBus.shovel_mode_changed.connect(func(_active: bool, id: int) -> void: _on_mine(id))
	EventBus.round_state_changed.connect(func(_state: String) -> void: _refresh())
	SafeArea.apply(self)
	_refresh()


func _on_mine(player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_refresh.call_deferred()


func _on_plant_placed(_type: String, _coord: Vector2i, player_id: int) -> void:
	if player_id == GameManager.local_player_id():
		_plants_placed += 1
	_on_mine(player_id)


func _refresh() -> void:
	var text := _text_now()
	if not text.is_empty():
		_label.text = text
	visible = not text.is_empty()
	if visible:
		var width := _label.get_minimum_size().x + SIDE_PAD * 2.0
		offset_left = -width * 0.5
		offset_right = width * 0.5
		_label.position = Vector2(SIDE_PAD, 0.0)
		_label.size = Vector2(width - SIDE_PAD * 2.0, HEIGHT)
		if not get_meta(SafeArea.META_BASE, []).is_empty():
			remove_meta(SafeArea.META_BASE)
		SafeArea.apply(self)
	HudCanvas.dirty()


func _text_now() -> String:
	if not GameManager.round_state in ["setup", "wave", "sandbox"]:
		return ""
	var touch := GameManager.is_touch_ui()
	var id: int = GameManager.local_player_id()
	if GameManager.is_shovel_for(id):
		return tr("Tap a plant to dig it up") if touch else tr("Click a plant to dig it up  •  Right-click to cancel")
	if not GameManager.selected_plant_for(id).is_empty():
		return tr("Drag to aim, lift to plant") if touch else tr("Click ground to plant  •  R to rotate  •  Right-click to cancel")
	if not GameManager.level_active or "--dev-seeds" in OS.get_cmdline_user_args():
		return tr("Tap a seed, drag to aim, lift to plant") if touch else tr("1–9 Pick a plant  •  X Shovel  •  TAB Seeds  •  T Day/Night  •  H Enemies")
	if _plants_placed >= PLANTS_TO_RETIRE:
		return ""
	return tr("Tap a seed, drag to aim, lift to plant") if touch else tr("1–9 Pick a plant  •  X Shovel  •  Left drag to pan  •  Right drag to orbit  •  Scroll to zoom")


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	p.lacquer(HudPainter.chamfered(Rect2(Vector2.ZERO, size), 5.0), UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT, UiPalette.HUD_GOLD, 2.0)
