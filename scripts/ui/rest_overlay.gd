extends CanvasLayer
## What you see when a rest finishes:
##  1. If levels were waiting, a short quiet moment: "The book writes through the night."
##  2. If you have writing ink and a book, the book opens to its pages. Click a page to
##     write into it; the page visibly fills with lines. No numbers anywhere.
##     The Unwritten, Phase 3: above the pages stand the ink pots, the book's own ink and every
##     monster ink you carry. Pick one (click, or up / down), then write: each line on a page is
##     drawn in the ink it was written with, and each evolution shows the ink it branched to.
##  3. Before the book: if a move grew at this rest and you carry monster ink, you may dip
##     your hands into a pot first (or leave them as they are).
## The world stays paused until you close the book.

signal finished

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const InkRules := preload("res://scripts/world/inks.gd")

var w
var ui_root: Control
var C: Dictionary = GameData.COLORS
var veil: ColorRect
var moment: Label
var pages_box: HBoxContainer
var well: Control
var done_btn: Button
var writing := false
var sel := 0          # the page picked with a gamepad or the arrow keys
var pot := "plain"    # the ink pot picked (The Unwritten, Phase 3)
var pots_box: VBoxContainer
var pots_row: HBoxContainer
var pots_lbl: Label
var dipping := false  # choosing a pot for your bare hands
var dip_btn: Button


## One spell page, drawn as lines of ink. More lines = more written into it.
## A gilt frame appears each time the spell evolves.
class PageView extends Control:
	var w
	var slot := 0
	var grow_t := 0.0
	var picked := false   # chosen with a gamepad or the arrow keys
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var ch: Dictionary = w.ch
		var s: Dictionary = ch.spells[slot]
		var mx: int = Game.max_spell_level()
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_rect(r, C.paper)
		draw_rect(r, C.rule, false, 1.0)
		if picked:
			draw_rect(r.grow(3.0), C.gilt, false, 2.0)
		var tier := int(int(s.lvl) / 4.0)
		var path: Array = s.get("branch", [])
		for k in tier:
			# Each evolution's frame is gilt; a branched one is ruled in its ink inside the gilt.
			draw_rect(r.grow(-4.0 - k * 4.0), C.gilt, false, 1.5)
			if k < path.size() and String(path[k]) != "plain":
				draw_rect(r.grow(-5.5 - k * 4.0), Color(InkRules.color(String(path[k])), 0.9), false, 1.0)
		var Ink := preload("res://scripts/util/ink.gd")
		Ink.text_c(self, Vector2(size.x / 2.0, 40), Game.spell_name(s), 16, C.ink)
		# Lines of writing: one per level, the newest one fading in, each in the ink it was
		# written with (the first line is the book's own). A small fork in the margin marks
		# each evolution, in the ink it branched to.
		var col: Color = C[ch.el]
		var inks: Array = s.get("inks", [])
		var top := 60.0
		var line_h := (r.size.y - 70.0) / float(mx)
		for k in mx:
			var y := top + k * line_h
			if k < int(s.lvl):
				var a := 1.0
				if k == int(s.lvl) - 1 and grow_t > 0.0:
					a = 1.0 - grow_t
				var length := r.size.x - 40.0 - float((k * 37) % 30)
				var ink: String = String(inks[k - 1]) if k >= 1 and k - 1 < inks.size() else "plain"
				var lc: Color = col if ink == "plain" else InkRules.color(ink)
				draw_line(Vector2(26, y), Vector2(26 + length * a, y), Color(lc, 0.85), 2.0 if ink != "heavy" else 3.0)
			else:
				draw_line(Vector2(26, y), Vector2(r.size.x - 14, y), Color(C.rule, 0.5), 1.0)
			if (k + 1) % 4 == 0 and int((k + 1) / 4.0) - 1 < path.size():
				var bk: String = String(path[int((k + 1) / 4.0) - 1])
				var fc: Color = C.gilt if bk == "plain" else InkRules.color(bk)
				draw_line(Vector2(16, y + 2), Vector2(12, y - 4), fc, 1.5)
				draw_line(Vector2(16, y + 2), Vector2(20, y - 4), fc, 1.5)
				draw_line(Vector2(16, y + 2), Vector2(16, y + 7), fc, 1.5)


## An ink pot (The Unwritten, Phase 3): the book's own ink, or a monster ink you carry,
## drawn in that ink's shape, as full as your vial. No numbers.
class Pot extends Control:
	var w
	var ink := "plain"
	var picked := false
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var col: Color = C[w.ch.el] if ink == "plain" and Game.has_book() else InkRules.color(ink)
		var f: float = clampf(float(w.ch.ink) / 8.0, 0.15, 1.0) if ink == "plain" else w.inks.fill(ink)
		var c := Vector2(size.x / 2.0, size.y - 8.0)
		var shape: String = "round" if ink == "plain" else String(GameData.Inks.INKS[ink].shape)
		var wd := 26.0
		var ht := 30.0
		match shape:
			"tall":
				wd = 18.0
				ht = 38.0
			"square":
				wd = 28.0
				ht = 28.0
		var body := Rect2(c - Vector2(wd / 2.0, ht), Vector2(wd, ht))
		if picked:
			draw_rect(body.grow(5.0), Color(C.gilt, 0.25))
			draw_rect(body.grow(5.0), C.gilt, false, 2.0)
		draw_rect(body, C.panel)
		draw_rect(Rect2(body.position + Vector2(0, ht * (1.0 - f)), Vector2(wd, ht * f)), col)
		draw_rect(body, C.ink, false, 2.0 if shape != "round" else 1.5)
		draw_rect(Rect2(c - Vector2(wd * 0.3, ht + 6.0), Vector2(wd * 0.6, 6.0)), C.ink)   # the neck
		if shape == "cracked":
			draw_line(body.position + Vector2(4, 6), body.position + Vector2(10, 16), C.ink_soft, 1.0)


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
	ui_root = Control.new()
	var root := ui_root
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
	pots_box = VBoxContainer.new()
	pots_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pots_box.visible = false
	v.add_child(pots_box)
	pots_lbl = Label.new()
	pots_lbl.add_theme_color_override("font_color", C.paper)
	pots_lbl.add_theme_font_size_override("font_size", 15)
	pots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pots_box.add_child(pots_lbl)
	pots_row = HBoxContainer.new()
	pots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pots_row.add_theme_constant_override("separation", 14)
	pots_box.add_child(pots_row)
	dip_btn = Button.new()
	dip_btn.text = String(GameData.Inks.LINES.dip_none)
	dip_btn.focus_mode = Control.FOCUS_NONE
	dip_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dip_btn.pressed.connect(func(): dip_into("plain"))
	dip_btn.visible = false
	pots_box.add_child(dip_btn)
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
	UiTheme.fit(self, ui_root)


## Shows the end of a rest. `levels` is how many levels were just written.
func show_rest(levels: int) -> void:
	visible = true
	w.paused = true
	pages_box.visible = false
	pots_box.visible = false
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
	elif not Game.has_book() and w.inks.dip_waiting() != "":
		_open_dip()
	else:
		close()


# ---------------------------------------------------------------- Ink pots (The Unwritten, Phase 3)

## Builds the row of pots: the book's own ink first, then each monster ink carried.
func _build_pots(list: Array) -> void:
	for c in pots_row.get_children():
		c.queue_free()
	for ink in list:
		var pv := Pot.new()
		pv.w = w
		pv.ink = ink
		pv.custom_minimum_size = Vector2(48, 58)
		pv.mouse_filter = Control.MOUSE_FILTER_STOP
		pv.gui_input.connect(_on_pot_input.bind(ink))
		pots_row.add_child(pv)
	pots_box.visible = list.size() > 1 or dipping
	_show_pot()


func _on_pot_input(ev: InputEvent, ink: String) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		if dipping:
			dip_into(ink)
		else:
			pick_pot(ink)


## Chooses the pot the next lines are written with (also used by the self-test).
func pick_pot(ink: String) -> void:
	if ink in w.inks.pots():
		pot = ink
	_show_pot()


func _show_pot() -> void:
	for pv in pots_row.get_children():
		pv.picked = pv.ink == pot and not dipping
		pv.queue_redraw()
	if dipping:
		pots_lbl.text = String(GameData.Inks.LINES.dip_head)
	elif pot == "plain":
		pots_lbl.text = "%s %s." % [String(GameData.Inks.LINES.pots_head), _cap(String(GameData.Inks.LINES.pot_plain))]
	else:
		var I: Dictionary = GameData.Inks.INKS[pot]
		pots_lbl.text = "%s %s. %s" % [String(GameData.Inks.LINES.pots_head), _cap(String(I.name)), String(I.about)]


static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)


func _cycle_pot(step: int) -> void:
	var list: Array = w.inks.pots()
	var at := maxi(0, list.find(pot))
	pick_pot(list[clampi(at + step, 0, list.size() - 1)])


## Before the book: your hands are growing, and you carry monster ink.
func _open_dip() -> void:
	dipping = true
	pages_box.visible = false
	well.visible = false
	done_btn.visible = false
	_build_pots(w.inks.dip_pots())
	dip_btn.visible = true
	veil.color.a = 0.75


## Dips the growing hand into `ink` ("plain" leaves it) and finishes the rest.
func dip_into(ink: String) -> void:
	if not dipping:
		return
	w.inks.dip(ink)
	dipping = false
	dip_btn.visible = false
	pots_box.visible = false
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
	dipping = false
	dip_btn.visible = false
	if not pot in w.inks.pots():
		pot = "plain"
	_build_pots(w.inks.pots())
	sel = 0
	_pick(0)
	veil.color.a = 0.6


func _on_page_input(ev: InputEvent, pv: PageView) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		write_into(pv.slot)


## Spends one writing ink on page i (also used by the self-test).
func write_into(i: int) -> void:
	if w.spend_ink(i, pot):
		if not pot in w.inks.pots():
			pot = "plain"   # that vial ran dry
		_build_pots(w.inks.pots())
		for pv in pages_box.get_children():
			if pv.slot == i:
				pv.grow_t = 1.0
				pv.create_tween().tween_property(pv, "grow_t", 0.0, 0.6)
				var tw := pv.create_tween()
				tw.tween_method(func(_x): pv.queue_redraw(), 0.0, 1.0, 0.6)
		well.queue_redraw()


## Gamepad and keys: left/right (or the page keys) choose a page, A / Enter writes into it,
## B / Esc closes the book.
func _process(_dt: float) -> void:
	if visible and dipping:
		var dp: Array = w.inks.dip_pots()
		if Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
			dip_into("plain")
		elif not dp.is_empty() and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("read")):
			dip_into(dp[0])
		return
	if not visible or not writing:
		return
	if Input.is_action_just_pressed("ui_up"):
		_cycle_pot(-1)
	elif Input.is_action_just_pressed("ui_down"):
		_cycle_pot(1)
	elif Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("page_prev"):
		_pick(-1)
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("page_next"):
		_pick(1)
	elif Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("read"):
		write_into(sel)
	elif Input.is_action_just_pressed("ui_cancel") or Input.is_action_just_pressed("pause"):
		close()


func _pick(step: int) -> void:
	var n: int = pages_box.get_child_count()
	if n == 0:
		return
	sel = clampi(sel + step, 0, n - 1)
	for pv in pages_box.get_children():
		pv.picked = pv.slot == sel
		pv.queue_redraw()


func close() -> void:
	if w.inks.dip_waiting() != "":
		w.inks.dip("plain")   # closed without choosing: the hands stay as they are
	dipping = false
	writing = false
	var tw := create_tween()
	tw.tween_property(veil, "color:a", 0.0, 0.5)
	tw.tween_callback(func():
		visible = false
		w.paused = false
		finished.emit())
