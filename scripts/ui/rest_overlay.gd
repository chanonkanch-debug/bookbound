extends CanvasLayer
## What you see when a rest finishes:
##  1. If levels were waiting, a short quiet moment: "The book writes through the night."
##  2. If you have writing ink and a book, the book opens to its pages. Click a page to
##     write into it; the page visibly fills with lines. No numbers anywhere.
## The world stays paused until you close the book.

signal finished

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var C: Dictionary = GameData.COLORS
var veil: ColorRect
var moment: Label
var pages_box: HBoxContainer
var well: Control
var done_btn: Button
var writing := false


## One spell page, drawn as lines of ink. More lines = more written into it.
## A gilt frame appears each time the spell evolves.
class PageView extends Control:
	var w
	var slot := 0
	var grow_t := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var ch: Dictionary = w.ch
		var s: Dictionary = ch.spells[slot]
		var mx: int = Game.max_spell_level()
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_rect(r, C.paper)
		draw_rect(r, C.rule, false, 1.0)
		var tier := int(int(s.lvl) / 4.0)
		for k in tier:
			draw_rect(r.grow(-4.0 - k * 4.0), C.gilt, false, 1.5)
		var Ink := preload("res://scripts/util/ink.gd")
		Ink.text_c(self, Vector2(size.x / 2.0, 40), Game.spell_name(s), 16, C.ink)
		# Lines of writing: one per level, the newest one fading in.
		var col: Color = C[ch.el]
		var top := 60.0
		var line_h := (r.size.y - 70.0) / float(mx)
		for k in mx:
			var y := top + k * line_h
			if k < int(s.lvl):
				var a := 1.0
				if k == int(s.lvl) - 1 and grow_t > 0.0:
					a = 1.0 - grow_t
				var len := r.size.x - 40.0 - float((k * 37) % 30)
				draw_line(Vector2(26, y), Vector2(26 + len * a, y), Color(col, 0.85), 2.0)
			else:
				draw_line(Vector2(26, y), Vector2(r.size.x - 14, y), Color(C.rule, 0.5), 1.0)


## The inkwell: how much writing ink is left, as a fill level.
class Well extends Control:
	var w
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var ink := float(w.ch.ink)
		var f := clampf(ink / 8.0, 0.0, 1.0)
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		draw_rect(r, C.panel)
		draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - f)), Vector2(r.size.x, r.size.y * f)), C.ink)
		draw_rect(r, C.ink, false, 2.0)


func _ready() -> void:
	layer = 11
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.make()
	add_child(root)
	veil = ColorRect.new()
	veil.color = Color(C.ink, 0.0)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	moment = Label.new()
	moment.add_theme_font_size_override("font_size", 26)
	moment.add_theme_color_override("font_color", C.paper)
	moment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(moment)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	pages_box = HBoxContainer.new()
	pages_box.add_theme_constant_override("separation", 14)
	row.add_child(pages_box)
	well = Well.new()
	well.w = w
	well.custom_minimum_size = Vector2(34, 60)
	well.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(well)
	done_btn = Button.new()
	done_btn.text = "Close the book"
	done_btn.theme_type_variation = "PrimaryButton"
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	done_btn.pressed.connect(close)
	v.add_child(done_btn)


## Shows the end of a rest. `levels` is how many levels were just written.
func show_rest(levels: int) -> void:
	visible = true
	w.paused = true
	pages_box.visible = false
	well.visible = false
	done_btn.visible = false
	moment.text = GameData.REST.moment_text if levels > 0 else ""
	moment.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 0.82, 0.8)
	if levels > 0:
		tw.tween_property(moment, "modulate:a", 1.0, 0.8)
		tw.tween_interval(float(GameData.REST.moment_time))
		tw.tween_property(moment, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_after_moment)


func _after_moment() -> void:
	if Game.has_book() and int(w.ch.ink) > 0:
		_open_pages()
	else:
		close()


func _open_pages() -> void:
	writing = true
	for c in pages_box.get_children():
		c.queue_free()
	for i in w.ch.spells.size():
		var pv := PageView.new()
		pv.w = w
		pv.slot = i
		pv.custom_minimum_size = Vector2(190, 260)
		pv.mouse_filter = Control.MOUSE_FILTER_STOP
		pv.gui_input.connect(_on_page_input.bind(pv))
		pages_box.add_child(pv)
	pages_box.visible = true
	well.visible = true
	done_btn.visible = true
	veil.color.a = 0.6


func _on_page_input(ev: InputEvent, pv: PageView) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		write_into(pv.slot)


## Spends one writing ink on page i (also used by the self-test).
func write_into(i: int) -> void:
	if w.spend_ink(i):
		for pv in pages_box.get_children():
			if pv.slot == i:
				pv.grow_t = 1.0
				pv.create_tween().tween_property(pv, "grow_t", 0.0, 0.6)
				var tw := pv.create_tween()
				tw.tween_method(func(_x): pv.queue_redraw(), 0.0, 1.0, 0.6)
		well.queue_redraw()


func close() -> void:
	writing = false
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 0.0, 0.5)
	tw.tween_callback(func():
		visible = false
		w.paused = false
		finished.emit())
