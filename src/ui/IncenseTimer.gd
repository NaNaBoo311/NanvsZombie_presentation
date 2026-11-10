class_name IncenseTimer
extends Control

# The setup countdown: an incense stick burning down under one short line of text.
# It only changes on the 1 Hz setup_tick, so it costs nothing between seconds, and the
# stick's length reads at a glance while the player watches the lawn. Painted by HudCanvas.

const PANEL_SIZE := Vector2(320.0, 56.0)
const TOP := 104.0
const STICK_MARGIN := 22.0
const STICK_Y := 42.0

var _label: Label
var _total := 0
var _left := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_top = TOP
	offset_bottom = TOP + PANEL_SIZE.y
	_label = UiPalette.hud_label(18)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(0.0, 7.0)
	_label.size = Vector2(PANEL_SIZE.x, 26.0)
	add_child(_label)
	visible = false
	HudCanvas.register(self, 50)
	EventBus.setup_tick.connect(_on_setup_tick)


func _on_setup_tick(seconds_left: int) -> void:
	_total = maxi(_total, seconds_left)
	_left = seconds_left
	_label.text = (tr("Night falls in %ds") if not GameManager.is_day else tr("Ghosts arrive in %ds")) % seconds_left
	HudCanvas.dirty()


func paint_hud(p: HudPainter) -> void:
	p.xf = get_global_transform()
	p.lacquer(HudPainter.chamfered(Rect2(Vector2.ZERO, PANEL_SIZE), 6.0), UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT)
	var left := Vector2(STICK_MARGIN, STICK_Y)
	var right := Vector2(PANEL_SIZE.x - STICK_MARGIN, STICK_Y)
	p.line(PackedVector2Array([left, right]), 3.0, UiPalette.HUD_EDGE)
	var burn := float(_left) / float(maxi(_total, 1))
	var tip := left.lerp(right, burn)
	p.line(PackedVector2Array([left, tip]), 3.0, UiPalette.HUD_DUSK)
	p.fill(HudPainter.circle(tip, 8.0), Color(UiPalette.HUD_DAWN, 0.28))
	p.fill(HudPainter.circle(tip, 3.4), UiPalette.HUD_DAWN)
