extends RefCounted
## How erasure sites, torn pages and the Hearth's windows look (The Unwritten, Phase 2).
## Drawing only, no rules. Used with `const SiteFx := preload(...)`.
##   bare        pale paper, the ruled lines breaking up toward the centre, a slow breath
##   cleared     the same, with a small warm glow at the centre: rest here
##   restoring   ink spreads out from the centre in a wave: a gilt front, tendrils, sparks,
##               and behind it the colour wash and the place's own details (fence, reeds...)
##   restored    denser lines, colour, details and a campfire (the campfire is world.gd's)
##   fading      a restored site with the pale creeping back over it

const Ink := preload("res://scripts/util/ink.gd")

const WASH := {1: "good", 2: "water", 3: "earth"}


static func _hash(i: int, sd: float) -> float:
	return fmod(absf(sin(i * 12.9898 + sd * 78.233) * 43758.5453), 1.0)


## `pale` 0..1 (1 = blank), `state` erased/cleared/restored, `fx_t` seconds since it was
## written back (or -1), `t` world time.
static func draw_site(d: CanvasItem, s: Dictionary, pale: float, state: String, fx_t: float, t: float) -> void:
	var C: Dictionary = GameData.COLORS
	var p: Vector2 = s.p
	var r: float = s.r
	var sd: float = float(p.x * 0.013 + p.y * 0.007)
	var aura: float = r * float(GameData.Lore.ERASURE.aura)
	var front := 1e9
	var k := 1.0
	if fx_t >= 0.0:
		k = clampf(fx_t / float(GameData.Lore.RESTORE_FX.time), 0.0, 1.0)
		front = aura * (1.0 - pow(1.0 - k, 3.0))
	var written: float = 1.0 - pale
	# While the wave runs, the pale drains away behind it, whatever the site was before.
	var pale_a: float = (pow(1.0 - k, 3.0) if fx_t >= 0.0 else pale)

	# The pale: bare paper with the lines thinning out toward the centre.
	if pale_a > 0.01:
		var breath := 1.0 + 0.04 * sin(t * float(GameData.Lore.ERASURE.pulse) + sd)
		d.draw_colored_polygon(Ink.blob(p, r * 1.12 * breath, sd, t * 0.05), Color(C.paper.lightened(0.7), 0.55 * pale_a))
		d.draw_colored_polygon(Ink.blob(p, r * 0.85 * breath, sd + 2.0, t * 0.05), Color(C.paper.lightened(0.85), 0.75 * pale_a))
		for row in 7:
			var y := (row - 3) * r * 0.27
			var hw := sqrt(maxf(0.0, r * r * 1.1 - y * y))
			for j in 10:
				var x0 := -hw + j * hw / 5.0
				var x1 := x0 + hw / 5.0 * 0.8
				var mid := absf((x0 + x1) * 0.5) / maxf(1.0, hw)
				if _hash(row * 10 + j, sd) > mid * 1.3:
					continue   # more gaps near the middle: the lines are being unwritten
				d.draw_line(p + Vector2(x0, y), p + Vector2(x1, y), Color(C.rule, 0.8 * pale_a), 1.0)
		Ink.dashed_circle(d, p, r * breath, Color(C.ink_soft, 0.3 * pale_a), 1.0, t * 0.15)
		if state == "erased":
			# A few ghost strokes drifting about: words that have lost their page.
			for j in 4:
				var a := t * 0.2 + j * TAU / 4.0 + sd
				var q: Vector2 = p + Vector2.from_angle(a) * r * (0.3 + 0.15 * sin(t * 0.7 + j))
				d.draw_line(q, q + Vector2.from_angle(a + 1.2) * 9.0, Color(C.ink_soft, 0.22 * pale_a), 1.2)
		elif state == "cleared":
			# The pale is still, and something warm waits at the centre.
			var g := 0.5 + 0.5 * sin(t * 2.2)
			d.draw_circle(p, 5.0 + 2.0 * g, Color(C.gilt, 0.55))
			d.draw_arc(p, r * float(GameData.Lore.ERASURE.restore_reach) * (0.9 + 0.1 * g), 0, TAU, 40, Color(C.gilt, 0.25 + 0.2 * g), 1.5)

	# Written back: a colour wash and the place's own details, out to the front of the wave.
	var det_a: float = 1.0 if fx_t >= 0.0 else written
	if det_a > 0.01 and (state == "restored" or fx_t >= 0.0):
		var wash: Color = C[WASH.get(int(s.region), "good")]
		var wr := minf(r * 1.2, front)
		d.draw_colored_polygon(Ink.blob(p, wr, sd, 0.0), Color(wash, float(GameData.Lore.RESTORE_FX.wash) * det_a))
		d.draw_polyline(Ink.outline(Ink.blob(p, wr, sd, 0.0)), Color(wash, 0.35 * det_a), 1.2)
		_details(d, s, det_a, front, t, sd)

	# The wave itself.
	if fx_t >= 0.0 and k < 1.0:
		d.draw_arc(p, front, 0, TAU, 96, Color(C.gilt, 0.9 * (1.0 - k)), 3.0)
		d.draw_arc(p, front * 0.92, 0, TAU, 96, Color(C.ink, 0.5 * (1.0 - k)), 1.5)
		for j in 14:
			# Ink tendrils racing out from the centre.
			var a := j * TAU / 14.0 + sd
			var wob := sin(fx_t * 6.0 + j) * 0.12
			d.draw_line(p, p + Vector2.from_angle(a + wob) * front * 0.85, Color(C.ink, 0.25 * (1.0 - k)), 1.5)
		for j in int(GameData.Lore.RESTORE_FX.sparks):
			# Gilt sparks drifting up.
			var a := j * 2.39996 + sd
			var base: Vector2 = p + Vector2.from_angle(a) * r * sqrt(fmod(j * 0.618, 1.0))
			var rise := fmod(fx_t * 0.6 + _hash(j, sd), 1.0)
			d.draw_circle(base + Vector2(sin(fx_t * 3.0 + j) * 4.0, -50.0 * rise), 2.2 * (1.0 - rise) + 0.5, Color(C.gilt, (1.0 - rise) * (1.0 - k * 0.6)))


static func _in(q: Vector2, p: Vector2, front: float) -> bool:
	return q.distance_to(p) < front


static func _details(d: CanvasItem, s: Dictionary, a: float, front: float, t: float, sd: float) -> void:
	var C: Dictionary = GameData.COLORS
	var p: Vector2 = s.p
	var r: float = s.r
	var ink := Color(C.ink, 0.7 * a)
	# Denser lines than the paper around it: the place is more written than before it was lost.
	for j in 46:
		var q: Vector2 = p + Vector2.from_angle(j * 2.39996 + sd * 3.0) * r * 1.1 * sqrt(fmod(j * 0.618 + 0.05, 1.0))
		if not _in(q, p, front):
			continue
		var ang := sin(j * 1.3 + sd) * 0.6
		d.draw_line(q, q + Vector2(sin(ang) * 4.0, -8.0), Color(C.ink, 0.32 * a), 1.2)
		if j % 3 == 0:
			d.draw_line(q + Vector2(4, 0), q + Vector2(4 + sin(ang + 0.4) * 3.0, -6.0), Color(C.ink, 0.28 * a), 1.2)
		if j % 7 == 0:
			d.draw_circle(q + Vector2(0, -9), 2.2, Color(C.fire if j % 2 == 0 else C.gilt, 0.7 * a))   # small flowers
	match String(s.detail):
		"fence":
			var posts: Array = []
			for j in 8:
				var x := -0.8 * r + j * 1.6 * r / 7.0
				posts.append(p + Vector2(x, 0.25 * r - x * 0.2 + sin(j * 1.7) * 4.0))
			for j in posts.size():
				var q: Vector2 = posts[j]
				if not _in(q, p, front):
					continue
				d.draw_line(q, q + Vector2(0, -16), ink, 2.5)
				if j > 0 and _in(posts[j - 1], p, front):
					d.draw_line(posts[j - 1] + Vector2(0, -12), q + Vector2(0, -12), Color(C.ink_soft, 0.8 * a), 1.5)
					d.draw_line(posts[j - 1] + Vector2(0, -5), q + Vector2(0, -5), Color(C.ink_soft, 0.8 * a), 1.5)
		"grass":
			var col := Color(C.good, 0.75 * a)
			for j in 60:
				var q: Vector2 = p + Vector2.from_angle(j * 2.39996 + sd) * r * 0.95 * sqrt(fmod(j * 0.618, 1.0))
				if not _in(q, p, front):
					continue
				var sway := sin(t * 1.6 + j) * 2.0
				d.draw_line(q, q + Vector2(sway - 2.0, -9.0), col, 1.3)
				d.draw_line(q + Vector2(2, 0), q + Vector2(sway + 3.0, -7.0), col, 1.3)
			for j in 6:
				var q: Vector2 = p + Vector2.from_angle(j * 1.9 + sd) * r * 0.5
				if _in(q, p, front):
					d.draw_circle(q + Vector2(0, -10), 2.5, Color(C.gilt, 0.8 * a))
		"pool":
			if _in(p, p, front):
				var pr := minf(r * 0.6, front)
				d.draw_colored_polygon(Ink.blob(p, pr, sd, 0.0), Color(C.water, 0.3 * a))
				d.draw_polyline(Ink.outline(Ink.blob(p, pr, sd, 0.0)), Color(C.water, 0.6 * a), 1.5)
				for j in 3:
					var age := fmod(t * 0.35 + j / 3.0, 1.0)
					d.draw_arc(p, pr * age, 0, TAU, 32, Color(C.water, 0.5 * a * (1.0 - age)), 1.2)
		"stones":
			for j in 8:
				var u := j / 7.0
				var q: Vector2 = p + Vector2(lerpf(-0.85, 0.85, u) * r, sin(u * PI * 1.5) * 0.35 * r)
				if _in(q, p, front):
					d.draw_colored_polygon(Ink.blob(q, 7.5, float(j), 0.0), Color(C.ink_soft, 0.55 * a))
					d.draw_polyline(Ink.outline(Ink.blob(q, 7.5, float(j), 0.0)), ink, 1.2)
		"reeds":
			for c in 6:
				var base: Vector2 = p + Vector2.from_angle(c * 1.05 + sd) * r * 0.6
				if not _in(base, p, front):
					continue
				for j in 4:
					var q := base + Vector2((j - 1.5) * 5.0, 0)
					var top := q + Vector2(sin(t * 1.2 + j + c) * 3.0, -26.0 - j * 3.0)
					d.draw_line(q, top, Color(C.wind, 0.8 * a), 1.4)
					d.draw_colored_polygon(Ink.blob(top, 2.5, float(j), 0.0), Color(C.earth, 0.8 * a))
		"banner":
			var foot := p + Vector2(-0.15 * r, 0.2 * r)
			if _in(foot, p, front):
				d.draw_line(foot, foot + Vector2(0, -52), ink, 2.5)
				var pts := PackedVector2Array()
				for j in 7:
					var u := j / 6.0
					pts.append(foot + Vector2(u * 34.0, -50.0 + sin(t * 3.0 + u * 4.0) * 3.0 * u))
				for j in range(6, -1, -1):
					var u := j / 6.0
					pts.append(foot + Vector2(u * 34.0, -32.0 + sin(t * 3.0 + u * 4.0 + 0.4) * 3.0 * u))
				d.draw_colored_polygon(pts, Color(C.danger, 0.85 * a))
		"hill":
			for j in 3:
				var rr := r * (0.35 + 0.28 * j)
				if rr < front:
					d.draw_arc(p + Vector2(0, 0.45 * r), rr, PI + 0.35, TAU - 0.35, 40, Color(C.earth, 0.7 * a), 2.0)
		"line":
			var dir := Vector2.from_angle(0.3)
			var ln: float = minf(r * 1.1, front)
			d.draw_line(p - dir * ln, p + dir * ln, ink, 3.0)
			var n := int(ln * 2.0 / 14.0)
			for j in n:
				var q: Vector2 = p - dir * ln + dir * (j * 14.0 + 7.0)
				d.draw_line(q, q + dir.orthogonal() * 6.0, Color(C.ink_soft, 0.7 * a), 1.2)


## A torn page lying in the world. `kind` is grass / stone / site, `seen` 0..1.
static func draw_page(d: CanvasItem, p: Vector2, kind: String, seen: float, t: float) -> void:
	var C: Dictionary = GameData.COLORS
	if kind == "stone":
		d.draw_colored_polygon(Ink.blob(p + Vector2(4, 2), 11.0, 3.0, 0.0), Color(C.ink_soft, 0.5))
		d.draw_polyline(Ink.outline(Ink.blob(p + Vector2(4, 2), 11.0, 3.0, 0.0)), Color(C.ink, 0.5), 1.2)
	if seen <= 0.01:
		return
	var off := Vector2(-8, -6) if kind == "stone" else Vector2.ZERO
	var q: Vector2 = p + off
	var torn := PackedVector2Array([q + Vector2(-7, -5), q + Vector2(2, -7), q + Vector2(4, -4), q + Vector2(8, -5), q + Vector2(7, 6), q + Vector2(-6, 7)])
	d.draw_colored_polygon(torn, Color(C.panel, seen))
	d.draw_polyline(Ink.outline(torn), Color(C.ink_soft, 0.8 * seen), 1.0)
	for j in 3:
		d.draw_line(q + Vector2(-4, -2 + j * 3), q + Vector2(4, -2 + j * 3), Color(C.ink_soft, 0.5 * seen), 0.8)
	var g := maxf(0.0, sin(t * 1.4 + p.x))
	d.draw_circle(q + Vector2(5, -4), 1.8 * g, Color(C.gilt, g * seen))
	if kind == "grass":
		for j in 7:
			var b := p + Vector2((j - 3) * 3.2, 7)
			d.draw_line(b, b + Vector2(sin(t * 1.5 + j) * 1.5 - 1.0, -12.0), Color("b59a3c", 0.75), 1.2)


## A small house at the Hearth; its window lights up once its site is written back.
static func draw_window(d: CanvasItem, p: Vector2, lit: float, t: float) -> void:
	var C: Dictionary = GameData.COLORS
	var body := Rect2(p + Vector2(-9, -6), Vector2(18, 13))
	d.draw_rect(body, Color(C.panel, 0.9))
	d.draw_rect(body, Color(C.ink_soft, 0.8), false, 1.2)
	d.draw_polyline(PackedVector2Array([p + Vector2(-11, -6), p + Vector2(0, -15), p + Vector2(11, -6)]), Color(C.ink_soft, 0.8), 1.2)
	var win := Rect2(p + Vector2(-3, -3), Vector2(6, 6))
	if lit > 0.0:
		var flick := 0.85 + 0.15 * sin(t * 5.0 + p.x)
		d.draw_circle(p, 12.0, Color(C.gilt, 0.12 * lit * flick))
		d.draw_rect(win, Color(C.gilt, 0.9 * lit * flick))
	else:
		d.draw_rect(win, Color(C.ink, 0.35))
