class_name ConceptCanvas
extends Control

# One painted surface for a concept exhibit. `paint` receives (painter, size) and
# writes shapes into a HudPainter; they land in one triangle array, so a whole
# diagram is one draw call. Redraws only when repaint() is called.

var paint: Callable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(repaint)


func repaint() -> void:
	queue_redraw()


func _draw() -> void:
	if not paint.is_valid():
		return
	var painter := HudPainter.new()
	painter.begin(1.0)
	paint.call(painter, size)
	if not painter.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(),
			painter.indices, painter.points, painter.colors)
