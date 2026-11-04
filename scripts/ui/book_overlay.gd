extends CanvasLayer
## The open book (press B). Left page: your book. Right page: the hidden chapter.
## Opening the book is also the "awakening act", checked by the world first.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var ui_root: Control
var C: Dictionary = GameData.COLORS
var left: VBoxContainer
var right: VBoxContainer


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

	var close_btn := Button.new()
	close_btn.text = GameData.BOOK_TEXT.close
	close_btn.theme_type_variation = "PrimaryButton"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(close_book)
	v.add_child(close_btn)
	UiTheme.fit(self, ui_root)


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
	for i in ch.spells.size():
		var s: Dictionary = ch.spells[i]
		var mark := "▸" if i == w.casting.page else "•"
		left.add_child(_label("%s  %s" % [mark, Game.spell_name(s)], 15, C.ink))
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
	visible = true


func close_book() -> void:
	close()


func close() -> void:
	visible = false
	w.paused = false
