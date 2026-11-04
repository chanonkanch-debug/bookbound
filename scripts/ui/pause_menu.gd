extends CanvasLayer
## The pause menu (Esc, or Start on a gamepad). Drawn like a page of the book:
##   Back to the world · Settings · What my hands know (the controls) · Rest here and leave
## Settings are saved in user://settings.cfg (Game.set_setting). The controls page only lists
## what the player has already found, so it never gives away a secret (see KEY_PAGE).
## Works with a mouse, keys or a gamepad: up/down to choose, A or Enter to pick, B or Esc to go back.
## All text is in PAUSE and KEY_PAGE in game_data.gd.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const Ink := preload("res://scripts/util/ink.gd")

var w
var C: Dictionary = GameData.COLORS
var root: Control
var page: Control
var main_box: VBoxContainer
var settings_box: VBoxContainer
var keys_box: VBoxContainer
var key_page: KeyPage
var setting_btns := {}
var view := "main"


## A sheet of paper with ruled lines, a margin and a folded corner.
class Sheet extends Control:
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(3.0), Color(C.ink, 0.25))
		draw_rect(r, C.paper)
		var y := 70.0
		while y < size.y - 20.0:
			draw_line(Vector2(18, y), Vector2(size.x - 18, y), Color(C.rule, 0.55), 1.0)
			y += 28.0
		draw_line(Vector2(54, 12), Vector2(54, size.y - 12), Color(C.danger, 0.35), 1.0)
		var f := 26.0
		draw_colored_polygon(PackedVector2Array([Vector2(size.x - f, 0), Vector2(size.x, f), Vector2(size.x - f, f)]), C.panel)
		draw_polyline(PackedVector2Array([Vector2(size.x - f, 0), Vector2(size.x - f, f), Vector2(size.x, f)]), Color(C.ink_soft, 0.6), 1.0)
		draw_rect(r, Color(C.ink, 0.7), false, 1.5)


## The controls, written on the page in two hands: the key, then the gamepad.
class KeyPage extends Control:
	var lines: Array = []
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var f := ThemeDB.fallback_font
		var y := 22.0
		for l in lines:
			draw_string(f, Vector2(0, y), String(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C.ink)
			draw_string(f, Vector2(210, y), String(l[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C.ink_soft)
			draw_string(f, Vector2(530, y), String(l[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(C.gilt, 0.95))
			y += 28.0


func _ready() -> void:
	layer = 15
	visible = false
	root = Control.new()
	root.theme = _theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	page = Sheet.new()
	page.custom_minimum_size = Vector2(840, 470)
	center.add_child(page)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_left", 72)
	page.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	margin.add_child(stack)
	stack.add_child(_label(GameData.PAUSE.title, 26, C.ink))

	main_box = VBoxContainer.new()
	main_box.add_theme_constant_override("separation", 10)
	stack.add_child(main_box)
	main_box.add_child(_button(GameData.PAUSE.resume, close))
	main_box.add_child(_button(GameData.PAUSE.settings, func(): _show("settings")))
	main_box.add_child(_button(GameData.PAUSE.keys, func(): _show("keys")))
	main_box.add_child(_button(GameData.PAUSE.quit, _quit))

	settings_box = VBoxContainer.new()
	settings_box.add_theme_constant_override("separation", 10)
	stack.add_child(settings_box)
	for k in ["hitstop", "shake", "ui_scale", "show_numbers"]:
		var b := _button("", _cycle.bind(k))
		setting_btns[k] = b
		settings_box.add_child(b)
	settings_box.add_child(_button(GameData.PAUSE.back, func(): _show("main")))

	keys_box = VBoxContainer.new()
	keys_box.add_theme_constant_override("separation", 10)
	stack.add_child(keys_box)
	key_page = KeyPage.new()
	key_page.custom_minimum_size = Vector2(700, 300)
	keys_box.add_child(key_page)
	keys_box.add_child(_button(GameData.PAUSE.back, func(): _show("main")))
	UiTheme.fit(self, root)


func _theme() -> Theme:
	var t := UiTheme.make()
	# A visible focus mark, so a gamepad can see which line is chosen.
	var focus := UiTheme.box(Color(C.gilt, 0.12), C.gilt, 2)
	t.set_stylebox("focus", "Button", focus)
	return t


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(300, 0)
	b.pressed.connect(cb)
	return b


func open() -> void:
	UiTheme.fit(self, root)
	visible = true
	w.paused = true
	w.pointer_down = false
	w.casting.cancel()
	_show("main")


func close() -> void:
	visible = false
	w.paused = false


func _show(v: String) -> void:
	view = v
	main_box.visible = v == "main"
	settings_box.visible = v == "settings"
	keys_box.visible = v == "keys"
	if v == "settings":
		_refresh_settings()
	if v == "keys":
		key_page.lines = key_lines(w.ch)
		key_page.custom_minimum_size.y = 28.0 * key_page.lines.size() + 10.0
		key_page.queue_redraw()
	var box: VBoxContainer = {"main": main_box, "settings": settings_box, "keys": keys_box}[v]
	for c in box.get_children():
		if c is Button:
			c.grab_focus()
			break


func _process(_dt: float) -> void:
	if not visible:
		return
	if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_cancel"):
		if view == "main":
			close()
		else:
			_show("main")


## The controls this character has found so far (KEY_PAGE in game_data.gd).
static func key_lines(ch: Dictionary) -> Array:
	var out: Array = []
	var bare: bool = not Game.has_book(ch)
	var pages: int = (Game.bare_moves(ch).size() if bare else ch.get("spells", []).size())
	for row in GameData.KEY_PAGE:
		var cond: String = row[3]
		var show := false
		match cond:
			"always":
				show = true
			"pages":
				show = pages > 1 and (not bare or ch.ui.get("hands", false))
			"learned":
				show = bare and not ch.get("hands", {}).get("learned", []).is_empty()
			"rested":
				show = ch.get("rested", false) or ch.get("nudged", {}).get("rest", false)
			"lastpage":
				show = not bare and ch.aspect.get("awakened", false) and ch.aspect.get("id", "") == "lastpage"
			_:
				show = ch.get("ui", {}).get(cond, false)
		if show:
			out.append(row)
	return out


func _cycle(k: String) -> void:
	var v = Game.settings.get(k, GameData.SETTINGS[k])
	if k == "ui_scale":
		var opts: Array = GameData.UI_SCALES
		var i := 0
		for j in opts.size():
			if is_equal_approx(float(opts[j]), float(v)):
				i = j
		Game.set_setting(k, opts[(i + 1) % opts.size()])
		w.apply_ui_scale()
	else:
		Game.set_setting(k, not bool(v))
	_refresh_settings()


func _refresh_settings() -> void:
	var P: Dictionary = GameData.PAUSE
	for k in setting_btns:
		var v = Game.settings.get(k, GameData.SETTINGS[k])
		var shown: String
		if k == "ui_scale":
			var i := 0
			for j in GameData.UI_SCALES.size():
				if is_equal_approx(float(GameData.UI_SCALES[j]), float(v)):
					i = j
			shown = String(P.scales[i])
		else:
			shown = P.on if bool(v) else P.off
		setting_btns[k].text = "%s: %s" % [P[k], shown]


func _quit() -> void:
	Game.save_game()
	get_tree().quit()
