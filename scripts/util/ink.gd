extends RefCounted
## Small drawing helpers for the hand-inked look. Used with `const Ink := preload(...)`.


## A wobbly ink blob (14 points). `sd` gives each blob its own wobble.
static func blob(center: Vector2, r: float, sd: float, t: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 14:
		var a := k / 14.0 * TAU
		var rr := r * (1.0 + 0.09 * sin(a * 3.0 + t * 4.0 + sd))
		pts.append(center + Vector2(cos(a), sin(a)) * rr)
	return pts


## Closes a polygon so it can be drawn as an outline with draw_polyline.
static func outline(pts: PackedVector2Array) -> PackedVector2Array:
	var o := pts.duplicate()
	o.append(pts[0])
	return o


## A jagged lightning line from a to b.
static func jag(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	for i in range(1, 6):
		pts.append(a.lerp(b, i / 6.0) + Vector2(randf_range(-7, 7), randf_range(-7, 7)))
	pts.append(b)
	return pts


static func dashed_circle(d: CanvasItem, c: Vector2, r: float, col: Color, w: float, phase := 0.0) -> void:
	var segs := maxi(24, int(r / 8.0))
	for k in segs:
		if k % 2 == 0:
			continue
		var a0 := phase + k * TAU / segs
		d.draw_arc(c, r, a0, a0 + TAU / segs, 4, col, w)


## Draws text centred on `pos` (pos is the baseline).
static func text_c(d: CanvasItem, pos: Vector2, s: String, size: int, col: Color) -> void:
	var f := ThemeDB.fallback_font
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	d.draw_string(f, pos - Vector2(w / 2.0, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
