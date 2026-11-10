class_name HudPainter
extends RefCounted

# Vector shapes for the battle HUD, collected into ONE triangle array so the whole HUD
# background is a single draw call however detailed it gets (HudCanvas). Colours are
# per vertex: gradients, soft shadows and glows need no texture and no shader.
# Triangle arrays are not antialiased, so every edge gets a `feather`: a ring of
# vertices fading to alpha 0, about one physical pixel wide. Polygons must be
# star-shaped around their average point (rectangles, octagons, circles, stars).
# `xf` maps a widget's local points to the canvas, so a tweened card squashes for free.

var points := PackedVector2Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
var feather := 1.0
var xf := Transform2D.IDENTITY


func begin(edge_feather: float) -> void:
	points.clear()
	colors.clear()
	indices.clear()
	feather = edge_feather
	xf = Transform2D.IDENTITY


## Fill, top colour to bottom colour. `soft` widens the edge fade (drop shadows).
func fill(poly: PackedVector2Array, top: Color, bottom: Color = top, soft: float = -1.0) -> void:
	var loop := _clockwise(poly)
	var fade := feather if soft < 0.0 else soft
	var y0 := INF
	var y1 := -INF
	var centre := Vector2.ZERO
	for p in loop:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
		centre += p
	centre /= loop.size()
	var span := maxf(y1 - y0, 0.001)
	var inner := offset(loop, -fade * 0.5)
	var outer := offset(loop, fade * 0.5)
	var hub := _vertex(centre, top.lerp(bottom, clampf((centre.y - y0) / span, 0.0, 1.0)))
	var base := points.size()
	var n := loop.size()
	for i in n:
		var c := top.lerp(bottom, clampf((inner[i].y - y0) / span, 0.0, 1.0))
		_vertex(inner[i], c)
		_vertex(outer[i], _clear(c))
	for i in n:
		var j := (i + 1) % n
		var a := base + i * 2
		var b := base + j * 2
		indices.append_array([hub, a, b, a, a + 1, b + 1, a, b + 1, b])


## Closed outline, centred on the polygon's edge.
func stroke(poly: PackedVector2Array, width: float, color: Color) -> void:
	_band(_clockwise(poly), width, PackedColorArray([color]), true)


## Open line. `tints` (one per point) overrides `color`, for gradients along a cord.
func line(path: PackedVector2Array, width: float, color: Color, tints := PackedColorArray()) -> void:
	_band(path, width, tints if not tints.is_empty() else PackedColorArray([color]), false)


## Soft light outside a shape.
func glow(poly: PackedVector2Array, color: Color, size: float) -> void:
	var loop := _clockwise(poly)
	var mid := offset(loop, size * 0.4)
	var far := offset(loop, size)
	var strong := color
	var soft := color
	soft.a *= 0.42
	_ribbon(loop, mid, PackedColorArray([strong]), PackedColorArray([soft]), true)
	_ribbon(mid, far, PackedColorArray([soft]), PackedColorArray([_clear(color)]), true)


## The HUD's card treatment: drop shadow, gold inlay outside, ink outline, gradient body.
## The gold line keeps a shape readable on bright lawn, the ink on night sky.
func lacquer(poly: PackedVector2Array, top: Color, bottom: Color, gold: Color = UiPalette.HUD_GOLD, drop: float = 3.0) -> void:
	var loop := _clockwise(poly)
	if drop > 0.0:
		var shadow := PackedVector2Array()
		for p in offset(loop, 1.5):
			shadow.append(p + Vector2(0.0, drop))
		fill(shadow, UiPalette.HUD_SHADOW, UiPalette.HUD_SHADOW, 3.0)
	fill(offset(loop, 1.0), top, bottom)
	stroke(offset(loop, 2.1), 1.3, gold)
	stroke(offset(loop, 0.6), 1.75, UiPalette.HUD_EDGE)


## A ring of soft light rays around `c`, from bright at the hub to clear at `reach`.
func rays(c: Vector2, reach: float, count: int, phase: float, spread: float, color: Color) -> void:
	for i in count:
		var a := phase + TAU * i / count
		var hub := _vertex(c, color)
		var left := _vertex(c + Vector2(cos(a - spread), sin(a - spread)) * reach, _clear(color))
		var right := _vertex(c + Vector2(cos(a + spread), sin(a + spread)) * reach, _clear(color))
		indices.append_array([hub, left, right])


## Faceted Rice Gem, drawn instead of a live 3D viewport.
func gem(c: Vector2, r: float) -> void:
	var at := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * r
	var hull: PackedVector2Array = [at.call(0.0, -1.1), at.call(0.72, -0.42), at.call(0.72, 0.42), at.call(0.0, 1.1), at.call(-0.72, 0.42), at.call(-0.72, -0.42)]
	fill(hull, UiPalette.HUD_FACET_MID)
	var facets := [
		[UiPalette.HUD_FACET_LIGHT, [0.0, -1.04, 0.66, -0.4, 0.28, -0.28, 0.0, -0.5]],
		[UiPalette.HUD_FACET_SOFT, [0.0, -1.04, 0.0, -0.5, -0.28, -0.28, -0.66, -0.4]],
		[UiPalette.HUD_FACET_WARM, [0.66, -0.4, 0.66, 0.4, 0.28, 0.28, 0.28, -0.28]],
		[UiPalette.HUD_FACET_SOFT, [-0.66, -0.4, -0.28, -0.28, -0.28, 0.28, -0.66, 0.4]],
		[UiPalette.HUD_FACET_DEEP, [0.0, 1.04, 0.0, 0.5, 0.28, 0.28, 0.66, 0.4]],
		[UiPalette.HUD_FACET_WARM, [0.0, 1.04, -0.66, 0.4, -0.28, 0.28, 0.0, 0.5]],
	]
	for f in facets:
		var pts := PackedVector2Array()
		for i in range(0, f[1].size(), 2):
			pts.append(at.call(f[1][i], f[1][i + 1]))
		fill(pts, f[0])
	stroke(hull, 1.2, UiPalette.HUD_FACET_EDGE)


## A lacquer button for a HudHit of `size`, in the widget's local space.
func button(hit: HudHit, size: Vector2) -> void:
	var shape := chamfered(Rect2(Vector2.ZERO, size), 7.0)
	if hit.hovered:
		glow(offset(shape, 3.0), Color(UiPalette.HUD_GOLD, 0.35), 6.0)
	var top := UiPalette.HUD_GOLD if hit.is_pressed() else (UiPalette.HUD_LACQUER_LIT if hit.hovered else UiPalette.HUD_LACQUER_TOP)
	var bottom := UiPalette.HUD_GOLD if hit.is_pressed() else UiPalette.HUD_LACQUER_BOT
	lacquer(shape, top, bottom)


func glyph_pause(c: Vector2, color: Color) -> void:
	var half := Vector2(3.5, 11.0)
	for x in [-6.0, 6.0]:
		var at := c + Vector2(x, 0.0)
		fill(chamfered(Rect2(at - half, half * 2.0), 1.2), color)


func glyph_cross(c: Vector2, color: Color) -> void:
	var r := 10.0
	line(PackedVector2Array([c + Vector2(-r, -r), c + Vector2(r, r)]), 4.0, color)
	line(PackedVector2Array([c + Vector2(r, -r), c + Vector2(-r, r)]), 4.0, color)


## A three-quarter turn with an arrowhead; `direction` -1 is counter-clockwise.
func glyph_rotate(c: Vector2, direction: int, color: Color) -> void:
	var start := -PI * 0.5 + 0.5 * direction
	var finish := start + 4.6 * direction
	line(arc(c, 11.0, start, finish, 22), 3.6, color)
	var tip := c + Vector2(cos(finish), sin(finish)) * 11.0
	var along := Vector2(-sin(finish), cos(finish)) * direction
	var out := Vector2(cos(finish), sin(finish))
	fill(PackedVector2Array([tip + along * 7.0, tip + out * 6.0, tip - out * 6.0]), color)


static func chamfered(rect: Rect2, cut: float) -> PackedVector2Array:
	var a := rect.position
	var b := rect.end
	return PackedVector2Array([
		Vector2(a.x + cut, a.y), Vector2(b.x - cut, a.y), Vector2(b.x, a.y + cut), Vector2(b.x, b.y - cut),
		Vector2(b.x - cut, b.y), Vector2(a.x + cut, b.y), Vector2(a.x, b.y - cut), Vector2(a.x, a.y + cut),
	])


static func circle(c: Vector2, r: float) -> PackedVector2Array:
	return arc(c, r, 0.0, TAU, maxi(20, int(r * 2.2)), false)


## Points along a circle; `closed_end` keeps the last point (open arcs need it).
static func arc(c: Vector2, r: float, from: float, to: float, steps: int, closed_end: bool = true) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := steps + 1 if closed_end else steps
	for i in count:
		var a := lerpf(from, to, float(i) / float(steps))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## The part of a disc at `c` still covered by an equal moon moved `d` along unit `u`.
## An outline, so the caller can fill it; empty once the moon has cleared.
static func eclipse(c: Vector2, r: float, u: Vector2, d: float, steps: int = 14) -> PackedVector2Array:
	if d >= r * 2.0 - 0.4:
		return PackedVector2Array()
	var base := u.angle()
	var half := acos(clampf(d / (r * 2.0), 0.0, 1.0))
	var out := arc(c, r, base - half, base + half, steps)
	out.append_array(eclipse_edge(c, r, u, d, steps).slice(1, steps))
	return out


## The moon's leading edge across the disc, for the corona line.
static func eclipse_edge(c: Vector2, r: float, u: Vector2, d: float, steps: int = 14) -> PackedVector2Array:
	var base := u.angle()
	var half := acos(clampf(d / (r * 2.0), 0.0, 1.0))
	return arc(c + u * d, r, base + PI - half, base + PI + half, steps)


static func octagon(c: Vector2, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 8:
		var a := PI / 8.0 + i * PI / 4.0
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func star(c: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		out.append(c + Vector2(cos(a), sin(a)) * (inner if i % 2 == 1 else outer))
	return out


## `poly` pushed outward by `d` (inward when negative), mitred at the corners.
static func offset(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	return _offset(poly, d, true)


static func _offset(poly: PackedVector2Array, d: float, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var prev := poly[(i - 1 + n) % n] if closed or i > 0 else poly[i]
		var next := poly[(i + 1) % n] if closed or i < n - 1 else poly[i]
		var e0 := (poly[i] - prev).normalized()
		var e1 := (next - poly[i]).normalized()
		if e0 == Vector2.ZERO:
			e0 = e1
		if e1 == Vector2.ZERO:
			e1 = e0
		var n0 := Vector2(e0.y, -e0.x)
		var n1 := Vector2(e1.y, -e1.x)
		var m := (n0 + n1).normalized()
		out.append(poly[i] + m * d / maxf(m.dot(n0), 0.35))
	return out


func _band(path: PackedVector2Array, width: float, tints: PackedColorArray, closed: bool) -> void:
	var half := maxf(width * 0.5 - feather * 0.5, 0.0)
	var edge := half + feather
	var solid := PackedColorArray()
	var fade := PackedColorArray()
	var scale_alpha := minf(width / feather, 1.0)
	for c in tints:
		c.a *= scale_alpha
		solid.append(c)
		fade.append(_clear(c))
	var a := _offset(path, -edge, closed)
	var b := _offset(path, -half, closed)
	var c2 := _offset(path, half, closed)
	var d := _offset(path, edge, closed)
	_ribbon(a, b, fade, solid, closed)
	_ribbon(b, c2, solid, solid, closed)
	_ribbon(c2, d, solid, fade, closed)


func _ribbon(a: PackedVector2Array, b: PackedVector2Array, ca: PackedColorArray, cb: PackedColorArray, closed: bool) -> void:
	var base := points.size()
	var n := a.size()
	for i in n:
		_vertex(a[i], ca[i if ca.size() > 1 else 0])
		_vertex(b[i], cb[i if cb.size() > 1 else 0])
	var last := n if closed else n - 1
	for i in last:
		var p := base + i * 2
		var q := base + (i + 1) % n * 2
		indices.append_array([p, q, p + 1, p + 1, q, q + 1])


func _vertex(p: Vector2, c: Color) -> int:
	points.append(xf * p)
	colors.append(c)
	return points.size() - 1


## Screen-clockwise, so "outward" is the same way for every polygon.
static func _clockwise(poly: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		area += a.x * b.y - b.x * a.y
	if area >= 0.0:
		return poly
	var out := poly.duplicate()
	out.reverse()
	return out


static func _clear(c: Color) -> Color:
	c.a = 0.0
	return c
