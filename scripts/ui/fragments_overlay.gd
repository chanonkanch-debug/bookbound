extends CanvasLayer
## The torn pages you've found (The Unwritten, Phase 2), shown one at a time as torn paper,
## in the order found. Opened from the back of the book, or from the journal before you have
## a book. Left / right (or Q / E, or the shoulder buttons) turn between them.
## Text: GameData.Lore.FRAGMENTS and GameData.Lore.LINES. Esc closes it (world.close_overlays).

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var ui_root: Control
var sheet: TornSheet
var head: Label
var counter: Label
var prev_btn: Button
var next_btn: Button
var at := 0
var came_from = null     # the overlay to go back to when this one closes


## A sheet of torn paper: ragged edges, a few ruled lines, the page's words on it.
class TornSheet extends Control:
	var title := ""
	var body := ""
	var sd := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var f := ThemeDB.fallback_font
		var pts := PackedVector2Array()
		var n := 28
		for k in n:
			var u := float(k) / n
			var q: Vector2
			if u < 0.25:
				q = Vector2(size.x * u * 4.0, 0)
			elif u < 0.5:
				q = Vector2(size.x, size.y * (u - 0.25) * 4.0)
			elif u < 0.75:
				q = Vector2(size.x * (1.0 - (u - 0.5) * 4.0), size.y)
			else:
				q = Vector2(0, size.y * (1.0 - (u - 0.75) * 4.0))
			var jag := 6.0 * sin(k * 7.3 + sd) + 4.0 * sin(k * 2.1 + sd * 2.0)
			q += (q - size / 2.0).normalized() * jag
			pts.append(q)
		draw_colored_polygon(pts, Color(C.panel.darkened(0.03), 1.0))
		var o := pts.duplicate()
		o.append(pts[0])
		draw_polyline(o, Color(C.ink_soft, 0.7), 1.2)
		var y := 70.0
		while y < size.y - 24.0:
			draw_line(Vector2(24, y), Vector2(size.x - 24, y), Color(C.rule, 0.5), 1.0)
			y += 26.0
		draw_string(f, Vector2(28, 44), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 56, 20, Color(C.ink_soft, 0.95))
		var ly := 92.0
		for line in body.split("\n"):
			var col: Color = C.ink_soft if line.begins_with("(") else C.ink
			# Wrap long lines by hand on the ruled lines.
			for part in _wrap(f, line, size.x - 56, 16):
				draw_string(f, Vector2(28, ly), part, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
				ly += 26.0

	static func _wrap(f: Font, line: String, width: float, fs: int) -> Array:
		var out: Array = []
		var cur := ""
		for word in line.split(" "):
			var t := word if cur == "" else cur + " " + word
			if cur != "" and f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				out.append(cur)
				cur = word
			else:
				cur = t
		out.append(cur)
		return out


func _ready() -> void:
	layer = 11
	visible = false
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.theme = UiTheme.make()
	add_child(ui_root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	center.add_child(v)
	head = Label.new()
	head.text = String(GameData.Lore.LINES.fragments_head)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_color", GameData.COLORS.paper)
	head.add_theme_font_size_override("font_size", 14)
	v.add_child(head)
	sheet = TornSheet.new()
	sheet.custom_minimum_size = Vector2(640, 340)
	v.add_child(sheet)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	prev_btn = _button(String(GameData.Lore.LINES.fragments_prev), func(): turn(-1))
	row.add_child(prev_btn)
	counter = Label.new()
	counter.add_theme_color_override("font_color", GameData.COLORS.paper)
	row.add_child(counter)
	next_btn = _button(String(GameData.Lore.LINES.fragments_next), func(): turn(1))
	row.add_child(next_btn)
	var close_btn := _button(String(GameData.Lore.LINES.fragments_close), close)
	close_btn.theme_type_variation = "PrimaryButton"
	row.add_child(close_btn)
	UiTheme.fit(self, ui_root)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func open(from = null) -> void:
	came_from = from
	at = maxi(0, w.pages.found_pages().size() - 1)   # open on the newest page
	_show()
	visible = true
	w.paused = true


func turn(dir: int) -> void:
	var n: int = w.pages.found_pages().size()
	if n == 0:
		return
	at = clampi(at + dir, 0, n - 1)
	_show()


func _show() -> void:
	var found: Array = w.pages.found_pages()
	head.text = String(GameData.Lore.LINES.fragments_head)
	if not Game.has_book(w.ch):
		head.text += "\n" + String(GameData.Lore.LINES.fragments_bare)
	if found.is_empty():
		sheet.title = ""
		sheet.body = String(GameData.Lore.LINES.fragments_none)
		counter.text = ""
	else:
		var f: Dictionary = found[at]
		sheet.title = String(f.title)
		sheet.body = String(f.text)
		sheet.sd = float(at) * 1.7 + 0.4
		counter.text = "%s" % "· ".repeat(at) + "●" + " ·".repeat(found.size() - at - 1)
	prev_btn.disabled = at <= 0
	next_btn.disabled = at >= found.size() - 1
	sheet.queue_redraw()


func _process(_dt: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("page_prev") or Input.is_action_just_pressed("ui_left"):
		turn(-1)
	elif Input.is_action_just_pressed("page_next") or Input.is_action_just_pressed("ui_right"):
		turn(1)
	# Esc / B / Start close it through world.close_overlays().


func close() -> void:
	visible = false
	w.paused = false
	if came_from != null and came_from.has_method("reopen"):
		came_from.reopen()
