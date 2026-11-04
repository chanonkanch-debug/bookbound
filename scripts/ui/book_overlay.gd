extends CanvasLayer
## The open book (press B). Left page: your book. Right page: the hidden chapter.
## Opening the book is also the "awakening act", checked by the world first.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const InkRules := preload("res://scripts/world/inks.gd")

var w
var ui_root: Control
var C: Dictionary = GameData.COLORS
var left: VBoxContainer
var right: VBoxContainer
var pages_btn: Button


func _ready() -> void:
	layer = 10
	visible = false
	ui_root = Control.new()
	var root := ui_root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.make()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 400)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var pages := HBoxContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_theme_constant_override("separation", 24)
	v.add_child(pages)
	left = VBoxContainer.new()
	left.custom_minimum_size = Vector2(370, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	pages.add_child(left)
	pages.add_child(VSeparator.new())
	right = VBoxContainer.new()
	right.custom_minimum_size = Vector2(370, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 10)
	pages.add_child(right)

	var row := HBoxContainer.new()
	v.add_child(row)
	# The Unwritten, Phase 2: torn pages are kept at the back of the book.
	pages_btn = Button.new()
	pages_btn.text = String(GameData.Lore.LINES.fragments_button)
	pages_btn.focus_mode = Control.FOCUS_NONE
	pages_btn.pressed.connect(func():
		visible = false
		w.fragments_ui.open(self))
	row.add_child(pages_btn)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	var close_btn := Button.new()
	close_btn.text = GameData.BOOK_TEXT.close
	close_btn.theme_type_variation = "PrimaryButton"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close_book)
	row.add_child(close_btn)
	UiTheme.fit(self, ui_root)


## The Unwritten, Phase 3: how a page has grown, drawn as a path that forks at each
## evolution. The way it went is inked in the ink it took (quick forks up, heavy runs
## straight on, stubborn forks down, pale leaves the line in a loop); the ways it didn't go
## are faint. Steps still to come are faint forks. No numbers.
class BranchPath extends Control:
	var path: Array = []
	var steps := 1
	var el_col := Color.BLACK
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var y := size.y / 2.0
		var x := 8.0
		var seg := (size.x - 24.0) / float(maxi(1, steps))
		draw_circle(Vector2(x, y), 3.5, el_col)
		var cy := y
		for k in steps:
			var x1 := x + seg
			var done := k < path.size()
			var ink: String = String(path[k]) if done else ""
			# The three ways it could go, faint.
			for dy in [-7.0, 0.0, 7.0]:
				draw_line(Vector2(x + seg * 0.45, cy), Vector2(x1, cy + dy), Color(C.ink_soft, 0.35), 1.2)
			draw_line(Vector2(x, cy), Vector2(x + seg * 0.45, cy), Color(el_col, 0.85) if done else Color(C.ink_soft, 0.35), 1.5)
			if done:
				var col: Color = C.gilt if ink == "plain" else InkRules.color(ink)
				var ny: float = cy + float({"quick": -7.0, "stubborn": 7.0}.get(ink, 0.0))
				draw_line(Vector2(x + seg * 0.45, cy), Vector2(x1, ny), col, 2.5 if ink == "heavy" else 2.0)
				if ink == "pale":
					draw_arc(Vector2(x + seg * 0.75, cy - 5.0), 5.0, 0, TAU, 16, col, 1.5)
				draw_circle(Vector2(x1, ny), 3.0, col)
				cy = ny
			x = x1


func _label(text: String, font_size: int, col: Color, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func open(awakened_now: bool) -> void:
	for c in left.get_children() + right.get_children():
		c.queue_free()
	var ch: Dictionary = w.ch
	var t: Dictionary = GameData.THICKNESS[ch.thick]
	var e: Dictionary = GameData.ELEMENTS[ch.el]
	left.add_child(_label("%s's book" % ch.name, 30, C.ink))
	left.add_child(_label("%s · %s" % [t.name, e.name], 14, C.ink_soft))
	left.add_child(_label(e.passive, 15, C.ink))
	var steps := int(Game.max_spell_level() / 4.0)
	for i in ch.spells.size():
		var s: Dictionary = ch.spells[i]
		var mark := "▸" if i == w.casting.page else "•"
		left.add_child(_label("%s  %s" % [mark, Game.spell_name(s)], 15, C.ink))
		if steps > 0:
			var bp := BranchPath.new()
			bp.path = s.get("branch", [])
			bp.steps = steps
			bp.el_col = C[ch.el]
			bp.custom_minimum_size = Vector2(40.0 + 56.0 * steps, 24)
			bp.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			left.add_child(bp)
			if not bp.path.is_empty():
				left.add_child(_label("%s %s" % [String(GameData.Inks.LINES.written_head), InkRules.path_words(bp.path)], 12, C.ink_soft))
	if int(ch.ink) > 0:
		left.add_child(_label(GameData.BOOK_TEXT.ink_waiting, 14, C.ink_soft))
	# Margin notes: hidden-chapter hints and spell secrets, once they've appeared.
	var m: Array = w.all_margins()
	if not m.is_empty() and ch.ui.get("margins", false):
		left.add_child(HSeparator.new())
		for line in m:
			left.add_child(_label(line, 13, C.gilt))

	var a: Dictionary = ch.aspect
	if a.awakened:
		var as_: Dictionary = GameData.ASPECTS[a.id]
		right.add_child(_label(GameData.BOOK_TEXT.awakened_head, 12, C.ink_soft, true))
		right.add_child(_label(as_.name, 40, C.gilt, true))
		right.add_child(_label(String(as_.get("told", as_.effect)), 15, C.ink, true))
		if awakened_now:
			right.modulate.a = 0.0
			right.create_tween().tween_property(right, "modulate:a", 1.0, 1.8)
		else:
			right.modulate.a = 1.0
	elif a.stage >= 4:
		right.modulate.a = 1.0
		right.add_child(_label(GameData.BOOK_TEXT.not_yet, 28, Color(C.ink_soft, 0.6), true))
		right.add_child(_label(GameData.BOOK_TEXT.moving, 14, C.ink_soft, true))
	else:
		right.modulate.a = 1.0
		right.add_child(_label(GameData.BOOK_TEXT.blank, 16, Color(C.ink_soft, 0.7), true))
	pages_btn.visible = not ch.get("fragments", []).is_empty()
	visible = true


## Q / E (or a shoulder button) with this open turns to the torn pages.
func _process(_dt: float) -> void:
	if visible and pages_btn.visible and (Input.is_action_just_pressed("page_next") or Input.is_action_just_pressed("page_prev")):
		pages_btn.pressed.emit()


## Back from the torn pages.
func reopen() -> void:
	visible = true
	w.paused = true


func close_book() -> void:
	close()


func close() -> void:
	visible = false
	w.paused = false
