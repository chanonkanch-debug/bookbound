extends Control
## Draws a book cover. Spine thickness shows how many pages it has.
## An empty `el` draws a closed, unknown book with a "?".

var el := ""
var spine := 16.0


func _draw() -> void:
	var C: Dictionary = GameData.COLORS
	var o := Vector2(10, 20)
	var cw := 180.0
	var chh := 240.0
	var block := Rect2(o + Vector2(cw - 8, 6), Vector2(spine + 8, chh - 12))
	draw_rect(block, C.panel)
	var x := 0.0
	while x < spine:
		draw_line(o + Vector2(cw + x, 7), o + Vector2(cw + x, chh - 7), C.rule, 1.0)
		x += 3.0
	draw_rect(block, C.rule, false, 1.0)
	var cc: Color = C[el] if el != "" else C.ink_soft
	draw_rect(Rect2(o, Vector2(cw, chh)), cc)
	draw_rect(Rect2(o, Vector2(10, chh)), Color(0, 0, 0, 0.2))
	var center := o + Vector2(cw / 2.0 + 4, chh / 2.0 - 14)
	_glyph(center, 3.2, C.on_el)
	var f := ThemeDB.fallback_font
	var label: String = GameData.ELEMENTS[el].name.to_upper() if el != "" else ""
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	draw_string(f, o + Vector2(cw / 2.0 + 4 - tw / 2.0, chh - 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C.on_el)


func _glyph(c: Vector2, s: float, col: Color) -> void:
	var raw: Array = []
	match el:
		"fire": raw = [[12, 2], [16, 7], [18, 12], [17, 17], [12, 21], [7, 17], [6, 12], [9, 8], [11, 11]]
		"water": raw = [[12, 2], [16, 9], [18, 14], [16, 19], [12, 21], [8, 19], [6, 14], [8, 9]]
		"earth": raw = [[2, 20], [9, 7], [13, 13], [16, 9], [22, 20]]
		"lightning": raw = [[13, 2], [4, 14], [10, 14], [9, 22], [18, 10], [12, 10]]
		"wind":
			for k in 3:   # three wavy gust lines
				var y := c.y + (k - 1) * 6.0 * s
				var ln := (18.0 - absi(k - 1) * 5.0) * s
				var line := PackedVector2Array()
				for q in 13:
					var x := q / 12.0
					line.append(Vector2(c.x - ln / 2.0 + x * ln, y + sin(x * TAU + k) * 1.4 * s))
				draw_polyline(line, col, 1.8 * s)
			return
		_:
			var f := ThemeDB.fallback_font
			var w := f.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x
			draw_string(f, c + Vector2(-w / 2.0, 24), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 72, col)
			return
	var pts := PackedVector2Array()
	for q in raw:
		pts.append(c + (Vector2(q[0], q[1]) - Vector2(12, 12)) * s)
	draw_colored_polygon(pts, col)
