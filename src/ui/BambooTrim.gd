class_name BambooTrim
extends Control

## Woven-bamboo trim for a framed panel: a lattice of crossed strips along the four
## edges inside the border, with amber studs at the corners. Pure vector drawing (one
## multiline per colour, no textures) redrawn only when the panel resizes, so it costs
## nothing at idle. Put it as the LAST child of the PanelContainer to trim; the panel's
## content margin must be at least INSET + WIDTH + 2 px so the trim never overlaps content.

## Distance from the panel edge to the strip (just inside the border).
@export var inset: float = 5.0
@export var strip_width: float = 8.0
@export var cell: float = 8.0
@export var stud_radius: float = 6.5

const WEAVE := Color(0.35, 0.24, 0.15, 0.55)
const RAIL := Color(0.35, 0.24, 0.15, 0.85)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var a := inset
	var b := inset + strip_width
	var weave := PackedVector2Array()
	var rails := PackedVector2Array()
	# Top and bottom strips: crossed diagonals between two rails.
	for y0 in [a, h - b]:
		rails.append_array([Vector2(a, y0), Vector2(w - a, y0), Vector2(a, y0 + strip_width), Vector2(w - a, y0 + strip_width)])
		var x := a
		while x + cell <= w - a:
			weave.append_array([Vector2(x, y0), Vector2(x + cell, y0 + strip_width), Vector2(x, y0 + strip_width), Vector2(x + cell, y0)])
			x += cell
	# Left and right strips, same weave turned a quarter.
	for x0 in [a, w - b]:
		rails.append_array([Vector2(x0, b), Vector2(x0, h - b), Vector2(x0 + strip_width, b), Vector2(x0 + strip_width, h - b)])
		var y := b
		while y + cell <= h - b:
			weave.append_array([Vector2(x0, y), Vector2(x0 + strip_width, y + cell), Vector2(x0 + strip_width, y), Vector2(x0, y + cell)])
			y += cell
	draw_multiline(weave, WEAVE, 1.0)
	draw_multiline(rails, RAIL, 1.5)
	# Corner studs (lantern amber with a dark ring).
	var c := inset + strip_width * 0.5
	for p in [Vector2(c, c), Vector2(w - c, c), Vector2(c, h - c), Vector2(w - c, h - c)]:
		draw_circle(p, stud_radius, UiPalette.BAMBOO_EDGE)
		draw_circle(p, stud_radius - 2.0, UiPalette.AMBER)
