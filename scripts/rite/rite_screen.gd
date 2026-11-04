extends Control
## The Book Rite: name + background in, random book out.

signal enter_world

const UiTheme := preload("res://scripts/ui/ui_theme.gd")


## Draws the book cover. Spine thickness shows how many pages it has.
class BookCover extends Control:
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


var C: Dictionary = GameData.COLORS
var bg_key := "sailor"
var name_edit: LineEdit
var note: Label
var cover: BookCover
var traits: RichTextLabel
var reveal_actions: HBoxContainer
var continue_btn: Button
var pending: Dictionary = {}
var saved: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	var bg := ColorRect.new()
	bg.color = C.paper
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 64)
	center.add_child(row)

	# ---- Left column: who you were
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(_label("PLAYABLE PROTOTYPE · GODOT", 12, C.gilt))
	left.add_child(_label("Bookbound", 64, C.ink))
	left.add_child(_label("Every mage is born holding a grimoire. It decides how you fight, never how strong you are. You can't trade it, and it may be keeping a secret.", 15, C.ink_soft, true))
	left.add_child(HSeparator.new())
	left.add_child(_label("The Book Rite", 30, C.ink))
	left.add_child(_label("Choose who you were. The book chooses the rest.", 15, C.ink))
	left.add_child(_label("NAME", 12, C.ink_soft))
	name_edit = LineEdit.new()
	name_edit.text = "Arin"
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(name_edit)
	left.add_child(_label("BACKGROUND", 12, C.ink_soft))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for k in GameData.BACKGROUNDS:
		var b := Button.new()
		b.text = GameData.BACKGROUNDS[k].name
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == bg_key
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick_bg.bind(k))
		flow.add_child(b)
	left.add_child(flow)
	note = _label(GameData.BACKGROUNDS[bg_key].note, 14, C.ink_soft, true)
	left.add_child(note)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var roll := Button.new()
	roll.text = "Receive your book"
	roll.theme_type_variation = "PrimaryButton"
	roll.pressed.connect(_roll)
	actions.add_child(roll)
	continue_btn = Button.new()
	continue_btn.visible = false
	continue_btn.pressed.connect(_continue)
	actions.add_child(continue_btn)
	left.add_child(actions)

	# ---- Right column: the book
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	cover = BookCover.new()
	cover.custom_minimum_size = Vector2(240, 290)
	cover.pivot_offset = Vector2(100, 140)
	cover.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(cover)
	traits = RichTextLabel.new()
	traits.bbcode_enabled = true
	traits.fit_content = true
	traits.scroll_active = false
	traits.custom_minimum_size = Vector2(440, 0)
	traits.visible = false
	right.add_child(traits)
	reveal_actions = HBoxContainer.new()
	reveal_actions.add_theme_constant_override("separation", 10)
	reveal_actions.visible = false
	var enter := Button.new()
	enter.text = "Enter the field"
	enter.theme_type_variation = "PrimaryButton"
	enter.pressed.connect(_enter)
	reveal_actions.add_child(enter)
	var reroll := Button.new()
	reroll.text = "Try another character"
	reroll.pressed.connect(_roll)
	reveal_actions.add_child(reroll)
	right.add_child(reveal_actions)

	saved = Game.load_game()
	if not saved.is_empty():
		continue_btn.text = "Continue as %s (Lv %d %s)" % [saved.name, saved.level, GameData.ELEMENTS[saved.el].name]
		continue_btn.visible = true


func _label(text: String, size: int, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _pick_bg(k: String) -> void:
	bg_key = k
	note.text = GameData.BACKGROUNDS[k].note


func _roll() -> void:
	pending = Game.new_character(name_edit.text.strip_edges(), bg_key)
	traits.visible = false
	reveal_actions.visible = false
	cover.el = ""
	cover.queue_redraw()
	var tw := create_tween()
	tw.tween_property(cover, "rotation", -0.07, 0.12)
	tw.tween_property(cover, "rotation", 0.07, 0.15)
	tw.tween_property(cover, "rotation", -0.04, 0.15)
	tw.tween_property(cover, "rotation", 0.0, 0.15)
	tw.tween_callback(_reveal)


func _reveal() -> void:
	var p := pending
	var t: Dictionary = GameData.THICKNESS[p.thick]
	var e: Dictionary = GameData.ELEMENTS[p.el]
	cover.el = p.el
	cover.spine = float(t.spine)
	cover.queue_redraw()
	var names: Array = []
	for s in p.spells:
		names.append(GameData.SPELLS[p.el][s.i].name)
	var soft: String = C.ink_soft.to_html(false)
	traits.text = "[color=#%s]BINDING[/color]\n[b]%s[/b] · %s\n[color=#%s]%s[/color]\n\n[color=#%s]THICKNESS[/color]\n[b]%s[/b], %d pages\n[color=#%s]%s[/color]\n\n[color=#%s]SPELLS[/color]\n%s" % [
		soft, e.name, e.verb, soft, e.passive,
		soft, t.name, p.pages, soft, t.trade,
		soft, ", ".join(names),
	]
	traits.visible = true
	reveal_actions.visible = true


func _enter() -> void:
	Game.ch = pending
	Game.save_game()
	enter_world.emit()


func _continue() -> void:
	Game.ch = saved
	enter_world.emit()
