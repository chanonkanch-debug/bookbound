extends RefCounted
## How each element looks, by shape and motion as well as colour, so the five can be told
## apart without seeing colour (for colour-blind players, and in a busy fight):
##   fire       flickering tongues that lick upward, embers rising
##   water      round drops, smooth ripples that spread outward
##   earth      heavy angular shards and blocks that barely move
##   wind       curls and crescents that spin and streak
##   lightning  zigzags that jump and re-draw every frame
## Drawing only, no rules. Used with `const Fx := preload(...)`.

const Ink := preload("res://scripts/util/ink.gd")


static func _col(el: String) -> Color:
	var C: Dictionary = GameData.COLORS
	return C[el] if C.has(el) else C.ink


## A flying spell (bolt). `v` is its velocity, `t` the world time, `small` for Mira's.
static func bolt(d: CanvasItem, el: String, p: Vector2, v: Vector2, t: float, small := false) -> void:
	var col := _col(el)
	var dir := v.normalized() if v.length() > 0.1 else Vector2.RIGHT
	var side := Vector2(-dir.y, dir.x)
	var s := 1.0 if small else 1.35
	match el:
		"fire":
			# A teardrop pointing forward, its tail flickering, embers drifting up behind.
			var flick := 1.0 + 0.25 * sin(t * 31.0 + p.x * 0.05)
			var tail: Vector2 = p - dir * 13.0 * s * flick + Vector2(0, -3)
			d.draw_colored_polygon(PackedVector2Array([p + dir * 6.0 * s, p + side * 4.5 * s, tail, p - side * 4.5 * s]), col)
			for k in 3:
				var age := fmod(t * 3.0 + k * 0.33, 1.0)
				d.draw_circle(p - dir * (8.0 + 14.0 * age) * s + Vector2(sin(k * 2.0 + t * 9.0) * 3.0, -10.0 * age), 1.4 * (1.0 - age) + 0.4, Color(col, 1.0 - age))
		"water":
			# A round drop with a pale glint and ripples left behind.
			d.draw_circle(p, 5.0 * s, col)
			d.draw_circle(p - dir * 1.5 + side * 1.5, 1.6 * s, Color(GameData.COLORS.paper, 0.8))
			for k in 2:
				var age := fmod(t * 2.5 + k * 0.5, 1.0)
				d.draw_arc(p - dir * (10.0 + 14.0 * age), 2.0 + 5.0 * age, 0, TAU, 12, Color(col, 0.6 * (1.0 - age)), 1.0)
		"earth":
			# A heavy, angular shard that turns slowly. No trail: it doesn't flutter.
			var a0 := t * 2.0 + p.x * 0.01
			var pts := PackedVector2Array()
			for k in 5:
				var rr := (6.5 if k % 2 == 0 else 4.0) * s
				pts.append(p + Vector2.from_angle(a0 + k * TAU / 5.0) * rr)
			d.draw_colored_polygon(pts, col)
			d.draw_polyline(Ink.outline(pts), GameData.COLORS.ink, 1.5)
		"wind":
			# Two crescents spinning around a point, with curved streaks behind.
			var spin := t * 14.0
			for k in 2:
				d.draw_arc(p, 5.0 * s, spin + k * PI, spin + k * PI + 2.0, 8, col, 2.2)
			for k in 3:
				var off: Vector2 = side * (k - 1) * 4.0
				d.draw_arc(p - dir * (12.0 + k * 3.0) + off, 6.0, dir.angle() + PI - 0.6, dir.angle() + PI + 0.6, 6, Color(col, 0.45), 1.2)
		"lightning":
			# A short zigzag that re-draws itself every frame.
			var pts := PackedVector2Array([p + dir * 7.0 * s])
			for k in 4:
				pts.append(p - dir * (k * 4.0) * s + side * (4.0 if k % 2 == 0 else -4.0) * s * randf_range(0.6, 1.3))
			d.draw_polyline(pts, col, 2.4)
			d.draw_circle(p + dir * 6.0 * s, 2.0 * s, col)
		_:
			# Bare hands and anything else: a plain ink blot with a short stroke.
			d.draw_line(p, p - v * 0.04, Color(col, 0.35), 3.0)
			d.draw_circle(p, 4.0 * s, col)


## A lingering zone. `f` fades it in and out (0..1).
static func zone(d: CanvasItem, el: String, p: Vector2, r: float, t: float, f: float, sd := 0.0) -> void:
	var col := _col(el)
	d.draw_circle(p, r, Color(col, 0.14 * f))
	match el:
		"fire":
			# Tongues of flame around the edge and a few inside, all licking upward.
			var n := maxi(8, int(r / 7.0))
			for k in n + 5:
				var base: Vector2
				if k < n:
					base = p + Vector2.from_angle(k * TAU / n + sd) * r * 0.9
				else:
					base = p + Vector2.from_angle(sd + k * 2.4) * r * 0.45
				var h := 10.0 + 7.0 * absf(sin(t * 7.0 + k * 1.7))
				var bw := 5.0
				d.draw_colored_polygon(PackedVector2Array([base + Vector2(-bw, 0), base + Vector2(bw, 0), base + Vector2(sin(t * 5.0 + k) * 3.0, -h)]), Color(col, 0.75 * f))
			d.draw_arc(p, r, 0, TAU, 40, Color(col, 0.4 * f), 1.2)
		"water":
			# Smooth ripples spreading out from the middle.
			for k in 3:
				var age := fmod(t * 0.45 + k / 3.0, 1.0)
				d.draw_arc(p, r * age, 0, TAU, 40, Color(col, 0.5 * f * (1.0 - age * 0.7)), 1.4)
			d.draw_arc(p, r, 0, TAU, 48, Color(col, 0.55 * f), 1.5)
		"earth":
			# A ring of square blocks that doesn't move, and a thick border.
			var n := maxi(8, int(r / 10.0))
			for k in n:
				var a := k * TAU / n + sd
				var c: Vector2 = p + Vector2.from_angle(a) * r
				d.draw_rect(Rect2(c - Vector2(3.5, 3.5), Vector2(7, 7)), Color(col, 0.75 * f))
			d.draw_arc(p, r - 4.0, 0, TAU, 48, Color(col, 0.35 * f), 3.0)
		"wind":
			# Spiral arms turning quickly.
			for k in 3:
				var a0 := t * 3.0 + k * TAU / 3.0
				var pts := PackedVector2Array()
				for j in 9:
					var q := j / 8.0
					pts.append(p + Vector2.from_angle(a0 + q * 2.4) * r * (0.2 + 0.8 * q))
				d.draw_polyline(pts, Color(col, 0.55 * f), 1.6)
			Ink.dashed_circle(d, p, r, Color(col, 0.5 * f), 1.2, t * 2.0)
		"lightning":
			# A jagged border that re-draws every frame, and crackles jumping about inside.
			var pts := PackedVector2Array()
			var n := maxi(18, int(r / 4.0))
			for k in n + 1:
				var a := k * TAU / n
				var jag := (0.1 if k % 2 == 0 else -0.1) * randf_range(0.5, 1.2) if k < n else 0.1
				pts.append(p + Vector2.from_angle(a) * r * (1.0 + jag))
			pts[n] = pts[0]
			d.draw_polyline(pts, Color(col, 0.7 * f), 1.4)
			for c in 2:
				var a := randf() * TAU
				var q: Vector2 = p + Vector2.from_angle(a) * r * randf_range(0.1, 0.6)
				d.draw_polyline(Ink.jag(q, q + Vector2.from_angle(a + randf_range(-1, 1)) * r * 0.45), Color(col, 0.85 * f), 1.5)
		_:
			Ink.dashed_circle(d, p, r, Color(col, 0.6 * f), 1.5, t * 0.5)


## An expanding burst ring (novas, impacts). `k` is how far through its life it is (0..1).
static func ring(d: CanvasItem, el: String, p: Vector2, r: float, k: float, w: float, t: float) -> void:
	var col := Color(_col(el), 1.0 - k)
	if not GameData.COLORS.has(el) or el == "none":
		d.draw_arc(p, r, 0, TAU, 48, col, w)
		return
	match el:
		"fire":
			# A ragged, flickering edge.
			var pts := PackedVector2Array()
			for j in 37:
				var a := j * TAU / 36.0
				pts.append(p + Vector2.from_angle(a) * r * (1.0 + 0.07 * sin(a * 9.0 + t * 18.0)))
			d.draw_polyline(pts, col, w)
		"water":
			# Two smooth rings, one just inside the other.
			d.draw_arc(p, r, 0, TAU, 48, col, w * 0.7)
			d.draw_arc(p, r * 0.86, 0, TAU, 48, Color(col, col.a * 0.6), w * 0.5)
		"earth":
			# Heavy separate blocks.
			var n := maxi(10, int(r / 9.0))
			for j in n:
				var a := j * TAU / n
				d.draw_arc(p, r, a, a + TAU / n * 0.55, 3, col, w * 1.6)
		"wind":
			# A spinning dashed spiral.
			Ink.dashed_circle(d, p, r, col, w, t * 4.0)
			d.draw_arc(p, r * 0.8, t * 4.0, t * 4.0 + 1.6, 10, col, w * 0.6)
		"lightning":
			# A zigzag ring that re-draws every frame.
			var pts := PackedVector2Array()
			for j in 25:
				var a := j * TAU / 24.0
				pts.append(p + Vector2.from_angle(a) * r * (1.0 + (0.08 if j % 2 == 0 else -0.08) * randf_range(0.5, 1.2)))
			d.draw_polyline(pts, col, w * 0.8)
		_:
			d.draw_arc(p, r, 0, TAU, 48, col, w)
