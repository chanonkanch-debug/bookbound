extends CanvasLayer
## The journal (press J once it has appeared). Lines are written in the world's voice:
## no numbers and no game terms. Text lives in JOURNAL in game_data.gd.
## The bestiary at the bottom fills in as you learn how monsters react (Phase 3).

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var ui_root: Control
var C: Dictionary = GameData.COLORS
var list: VBoxContainer
var beasts: VBoxContainer
var beast_head: Label
var new_btn: Button
var new_armed := false
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
	dim.color = Color(0.08, 0.1, 0.14, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 460)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("%s's journal" % w.ch.name, 28, C.ink))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 8)
	scroll.add_child(inner)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	inner.add_child(list)
	beast_head = _label(GameData.BESTIARY_TITLE, 16, C.ink_soft)
	inner.add_child(beast_head)
	beasts = VBoxContainer.new()
	inner.add_child(beasts)
	var row := HBoxContainer.new()
	new_btn = Button.new()
	new_btn.text = GameData.GIVE_UP_TEXT
	new_btn.focus_mode = Control.FOCUS_NONE
	new_btn.pressed.connect(_on_new_pressed)
	row.add_child(new_btn)
	# The Unwritten, Phase 2: before the book, torn pages are kept with the journal.
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
	close_btn.text = "Close the journal"
	close_btn.theme_type_variation = "PrimaryButton"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close_journal)
	row.add_child(close_btn)
	v.add_child(row)
	UiTheme.fit(self, ui_root)


func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


func open() -> void:
	for c in list.get_children() + beasts.get_children():
		c.queue_free()
	var lines: Array = w.ch.get("journal", [])
	if lines.is_empty():
		list.add_child(_label("…", 15, C.ink_soft))
	for i in range(lines.size() - 1, -1, -1):
		list.add_child(_label(lines[i], 15, C.ink if i == lines.size() - 1 else C.ink_soft))
	var known: Array = w.discovery.bestiary_lines() if w.get("discovery") != null else []
	beast_head.visible = not known.is_empty()
	for l in known:
		beasts.add_child(_label(l, 14, C.ink))
	pages_btn.visible = not Game.has_book(w.ch) and not w.ch.get("fragments", []).is_empty()
	visible = true
	w.paused = true


## Q / E (or a shoulder button) with this open turns to the torn pages.
func _process(_dt: float) -> void:
	if visible and pages_btn.visible and (Input.is_action_just_pressed("page_next") or Input.is_action_just_pressed("page_prev")):
		pages_btn.pressed.emit()


## Back from the torn pages.
func reopen() -> void:
	visible = true
	w.paused = true


func close_journal() -> void:
	visible = false
	w.paused = false


func _on_new_pressed() -> void:
	if not new_armed:
		new_armed = true
		new_btn.text = GameData.GIVE_UP_CONFIRM
		get_tree().create_timer(3.0).timeout.connect(func():
			new_armed = false
			new_btn.text = GameData.GIVE_UP_TEXT)
		return
	w.give_up_character()
