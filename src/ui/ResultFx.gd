class_name ResultFx
extends Control

# One transient painted layer for the result screens: `paint` fills a HudPainter every
# frame while `running`, so rays, shards and bursts are one draw call and need no
# particle nodes or textures. Idle when not running, and only exists on a result screen.

var paint: Callable
var running := false:
	set(value):
		running = value
		set_process(value)
		queue_redraw()

var _painter := HudPainter.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_process(false)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not paint.is_valid():
		return
	_painter.begin(1.0)
	paint.call(_painter)
	_painter.xf = Transform2D.IDENTITY
	if not _painter.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _painter.indices, _painter.points, _painter.colors)
