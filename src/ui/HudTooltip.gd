class_name HudTooltip
extends Control

# Lacquer tooltip: a name, a detail line, and the Rice Gem cost when there is one.
# Lives in the engine's tooltip popup, outside the HUD canvas, so it paints itself:
# one draw while it is open, none otherwise. HUD.gd empties the popup's own panel.

const PAD := Vector2(14.0, 10.0)
const WIDTH_MIN := 150.0

var _cost := -1
var _title: Label
var _detail: Label
var _cost_label: Label
var _painter := HudPainter.new()


func setup(title: String, detail: String, cost: int) -> void:
	_cost = cost
	_title = UiPalette.hud_label(18)
	_title.text = title
	add_child(_title)
	_detail = UiPalette.hud_label(14, UiPalette.HUD_INK_SOFT)
	_detail.text = detail
	_detail.visible = not detail.is_empty()
	add_child(_detail)
	_cost_label = UiPalette.hud_label(16)
	_cost_label.text = "%d" % cost
	_cost_label.visible = cost >= 0
	add_child(_cost_label)
	var title_size := _title.get_minimum_size()
	var detail_size := _detail.get_minimum_size() if _detail.visible else Vector2.ZERO
	var cost_size := _cost_label.get_minimum_size() + Vector2(34.0, 0.0) if _cost_label.visible else Vector2.ZERO
	var width := maxf(WIDTH_MIN, maxf(title_size.x + cost_size.x, detail_size.x)) + PAD.x * 2.0
	var height := title_size.y + detail_size.y + PAD.y * 2.0
	custom_minimum_size = Vector2(width, height) + Vector2(8.0, 8.0)
	_title.position = PAD + Vector2(4.0, 4.0)
	_detail.position = _title.position + Vector2(0.0, title_size.y)
	_cost_label.position = Vector2(width - PAD.x - _cost_label.get_minimum_size().x + 4.0, _title.position.y + 1.0)


func _draw() -> void:
	_painter.begin(1.0)
	var rect := Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 8.0))
	_painter.lacquer(HudPainter.chamfered(rect, 6.0), UiPalette.HUD_LACQUER_TOP, UiPalette.HUD_LACQUER_BOT, UiPalette.HUD_GOLD, 0.0)
	if _cost >= 0:
		_painter.gem(Vector2(_cost_label.position.x - 12.0, _cost_label.position.y + 11.0), 8.0)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _painter.indices, _painter.points, _painter.colors)
