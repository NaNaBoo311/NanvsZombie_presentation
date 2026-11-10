class_name HudCanvas
extends Control

# The one surface every battle HUD shape is painted on. Each widget registers here
# and adds its shapes in paint_hud(painter); they all land in ONE triangle array, so
# the HUD's backgrounds are one draw call. Measured on Godot 4.7: a merged array is 1
# draw at 400 quads, while each StyleBoxFlat, draw_polygon or draw_circle is 1 draw even
# inside one canvas item. Giving a widget its own painter or panel would cost a draw.
#
# HUD layers, bottom to top: this canvas, icons (one atlas, z HUD_Z_ICON), text (one
# font, z HUD_Z_TEXT). A HUD element takes one of those and nothing else. No label
# outlines or shadows, and never raise a widget's z_index to bring it forward: order
# in the painter does that for free. Text sits on opaque backing instead of outlines.
#
# Zero idle cost: this redraws only when dirty. A widget calls HudCanvas.dirty() after
# a state change, or HudCanvas.animate(seconds) to redraw every frame while its Tween
# runs. Painted widgets read their Control transforms, so tweening a Control's
# position or scale moves its shapes, and its icon and label children, together.
#
# Shapes that must cover icons go in an optional paint_hud_overlay(painter): a second
# array between the icons and the text, repainted alone by dirty_overlay(). It holds
# nothing, and so draws nothing, unless a widget has something to show.

static var _sources: Array[Dictionary] = []
static var _active: HudCanvas = null

var _painter := HudPainter.new()
var _over_painter := HudPainter.new()
var _over: Control
var _animate_until := 0


func _enter_tree() -> void:
	_active = self


func _exit_tree() -> void:
	if _active == self:
		_active = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process(false)
	get_viewport().size_changed.connect(queue_redraw)
	_over = Control.new()
	_over.name = "Overlay"
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.z_index = UiPalette.HUD_Z_OVER
	_over.draw.connect(_draw_overlay)
	add_child(_over)


## `order` sorts painting: higher paints later, on top.
static func register(widget: Control, order: int) -> void:
	_sources = _sources.filter(func(s: Dictionary) -> bool: return is_instance_valid(s["node"]) and s["node"] != widget)
	_sources.append({"node": widget, "order": order})
	_sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	dirty()


static func dirty() -> void:
	if is_instance_valid(_active):
		_active.queue_redraw()


static func dirty_overlay() -> void:
	if is_instance_valid(_active) and is_instance_valid(_active._over):
		_active._over.queue_redraw()


## Redraw every frame for `seconds`, then go idle again.
static func animate(seconds: float) -> void:
	if not is_instance_valid(_active):
		return
	_active._animate_until = maxi(_active._animate_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	_active.set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()
	if Time.get_ticks_msec() > _animate_until:
		set_process(false)


## About one physical pixel at any window size or canvas scale.
func _edge() -> float:
	return clampf(1.0 / maxf(get_viewport().get_screen_transform().get_scale().x, 0.01), 0.4, 1.2)


func _draw() -> void:
	_painter.begin(_edge())
	for source in _sources:
		var node: Control = source["node"]
		if is_instance_valid(node) and node.is_visible_in_tree():
			node.paint_hud(_painter)
	_painter.xf = Transform2D.IDENTITY
	if not _painter.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _painter.indices, _painter.points, _painter.colors)
	dirty_overlay()


func _draw_overlay() -> void:
	_over_painter.begin(_edge())
	for source in _sources:
		var node: Control = source["node"]
		if is_instance_valid(node) and node.is_visible_in_tree() and node.has_method("paint_hud_overlay"):
			node.paint_hud_overlay(_over_painter)
	if not _over_painter.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_over.get_canvas_item(), _over_painter.indices, _over_painter.points, _over_painter.colors)
