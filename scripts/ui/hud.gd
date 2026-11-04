extends CanvasLayer
## On-screen UI while playing: region name, spell buttons, and the side panel
## (stats, spells and ink, margins, journal, designer view).

const UiTheme := preload("res://scripts/ui/ui_theme.gd")


class Bar extends Control:
	var value := 0.0
	var max_value := 1.0
	var col := Color.RED
	var back := Color.GRAY
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), back)
		draw_rect(Rect2(0, 0, size.x * clampf(value / max_value, 0.0, 1.0), size.y), col)


class Pips extends Control:
	var lvl := 1
	var max_lvl := 8
	var col := Color.RED
	var off := Color.GRAY
	var gilt := Color.GOLD
	func _draw() -> void:
		var gap := 3.0
		var w := (size.x - gap * (max_lvl - 1)) / max_lvl
		for k in max_lvl:
			var rect := Rect2(k * (w + gap), 0, w, size.y)
			draw_rect(rect, col if k < lvl else off)
			if (k + 1) % 4 == 0:
				draw_rect(rect.grow(1.0), gilt, false, 1.0)


class CastButton extends Button:
	var cd := 0.0
	var col := Color.RED
	var open := false
	func _draw() -> void:
		if cd > 0.0:
			draw_rect(Rect2(0, size.y - 4, size.x * cd, 4), col)
		if open:
			draw_rect(Rect2(Vector2.ZERO, size).grow(2.0), col, false, 2.0)


## Darkens the screen edges: overcast strain now, low health later.
class Vignette extends Control:
	var amount := 0.0
	var col := Color.BLACK
	func _draw() -> void:
		if amount <= 0.01:
			return
		var s := size
		var e := minf(s.x, s.y) * 0.22
		var solid := Color(col, amount)
		var clear := Color(col, 0.0)
		var quads := [
			[Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x - e, e), Vector2(e, e)],
			[Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - e, s.y - e), Vector2(s.x - e, e)],
			[Vector2(s.x, s.y), Vector2(0, s.y), Vector2(e, s.y - e), Vector2(s.x - e, s.y - e)],
			[Vector2(0, s.y), Vector2(0, 0), Vector2(e, e), Vector2(e, s.y - e)],
		]
		for q in quads:
			draw_polygon(PackedVector2Array(q), PackedColorArray([solid, solid, clear, clear]))


var w
var C: Dictionary = GameData.COLORS
var root: Control
var region_lbl: Label
var region_sub: Label
var ceremony_lbl: Label
var castbar: HBoxContainer
var cast_btns: Array = []
var last_page_btn: CastButton
var book_btn: Button
var lvl_lbl: Label
var bars := {}
var status_lbl: Label
var ink_lbl: Label
var spell_box: VBoxContainer
var margins_box: VBoxContainer
var log_box: VBoxContainer
var new_btn: Button
var new_armed := false
var dev_box: VBoxContainer
var dev_lbl: RichTextLabel
var dev_t := 0.0
var honed_t := 0.0
var death: Control
var vignette: Vignette
var region := -1


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)

	vignette = Vignette.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.col = C.danger
	root.add_child(vignette)

	# Death veil
	death = ColorRect.new()
	death.color = Color(C.paper, 0.75)
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death.visible = false
	root.add_child(death)
	var dc := CenterContainer.new()
	dc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dc.offset_right = -320
	death.add_child(dc)
	var dv := _ignore(VBoxContainer.new())
	dc.add_child(dv)
	dv.add_child(_label("The ink runs dry", 40, C.ink, HORIZONTAL_ALIGNMENT_CENTER))
	dv.add_child(_label("Waking at the Hearth…", 16, C.ink_soft, HORIZONTAL_ALIGNMENT_CENTER))

	var row := _ignore(HBoxContainer.new())
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(row)

	# Left: play area overlay
	var left := _ignore(MarginContainer.new())
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		left.add_theme_constant_override("margin_" + side, 20)
	row.add_child(left)
	var lv := _ignore(VBoxContainer.new())
	left.add_child(lv)
	region_lbl = _label("", 26, C.ink)
	region_sub = _label("", 13, C.ink_soft)
	lv.add_child(region_lbl)
	lv.add_child(region_sub)
	ceremony_lbl = _label("", 16, C.gilt)
	ceremony_lbl.visible = false
	lv.add_child(ceremony_lbl)
	var spacer := _ignore(Control.new())
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)
	castbar = _ignore(HBoxContainer.new())
	castbar.add_theme_constant_override("separation", 8)
	lv.add_child(castbar)

	# Right: side panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 0)
	row.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var pv := VBoxContainer.new()
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv.add_theme_constant_override("separation", 10)
	scroll.add_child(pv)

	var name_row := HBoxContainer.new()
	var name_lbl := _label(w.ch.name, 24, C.ink)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvl_lbl = _label("", 13, C.ink_soft)
	name_row.add_child(name_lbl)
	name_row.add_child(lvl_lbl)
	pv.add_child(name_row)
	if Game.has_book():
		var t: Dictionary = GameData.THICKNESS[w.ch.thick]
		var e: Dictionary = GameData.ELEMENTS[w.ch.el]
		pv.add_child(_label("%s %s book · %d pages · %s" % [t.name, e.name, w.ch.pages, e.verb], 13, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		pv.add_child(_label("No book yet · bare hands · Book Ceremony at Lv %d" % GameData.CEREMONY_LEVEL, 13, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))
	for b in [["hp", "HP", C.danger], ["mp", "Mana", C.water], ["xp", "XP", C.gilt]]:
		pv.add_child(_bar_row(b[0], b[1], b[2]))
	status_lbl = _label("", 12, C.ink_soft)
	pv.add_child(status_lbl)

	pv.add_child(HSeparator.new())
	var pages_row := HBoxContainer.new()
	var ph := _label("Pages" if Game.has_book() else "Bare hands", 15, C.ink_soft)
	ph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ink_lbl = _label("", 14, C.ink)
	pages_row.add_child(ph)
	pages_row.add_child(ink_lbl)
	pv.add_child(pages_row)
	spell_box = VBoxContainer.new()
	spell_box.add_theme_constant_override("separation", 10)
	pv.add_child(spell_box)

	pv.add_child(HSeparator.new())
	pv.add_child(_label("Margins", 15, C.ink_soft))
	margins_box = VBoxContainer.new()
	pv.add_child(margins_box)

	pv.add_child(HSeparator.new())
	pv.add_child(_label("Journal", 15, C.ink_soft))
	log_box = VBoxContainer.new()
	pv.add_child(log_box)

	pv.add_child(HSeparator.new())
	new_btn = _button("Start a new character", _on_new_pressed)
	pv.add_child(new_btn)
	pv.add_child(_button("Designer view (F1)", toggle_dev))
	dev_box = VBoxContainer.new()
	dev_box.visible = false
	dev_lbl = RichTextLabel.new()
	dev_lbl.bbcode_enabled = true
	dev_lbl.fit_content = true
	dev_lbl.scroll_active = false
	dev_box.add_child(dev_lbl)
	dev_box.add_child(_button("Complete the trigger", func(): w.dev_complete_trigger()))
	dev_box.add_child(_button("Gain a level", func(): w.gain_xp(Game.xp_next(w.ch.level) - w.ch.xp)))
	pv.add_child(dev_box)

	rebuild_spells()
	refresh_margins(false)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("designer_view"):
		toggle_dev()


# ---------------------------------------------------------------- Builders

func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(cb)
	return b


func _bar_row(key: String, label: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := _label(label, 12, C.ink_soft)
	l.custom_minimum_size = Vector2(44, 0)
	var bar := Bar.new()
	bar.col = col
	bar.back = Color(C.ink, 0.1)
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var num := _label("", 12, C.ink_soft, HORIZONTAL_ALIGNMENT_RIGHT)
	num.custom_minimum_size = Vector2(76, 0)
	h.add_child(l)
	h.add_child(bar)
	h.add_child(num)
	bars[key] = {"bar": bar, "num": num}
	return h


# ---------------------------------------------------------------- Spells

func rebuild_spells() -> void:
	for c in spell_box.get_children():
		c.queue_free()
	var ch: Dictionary = w.ch
	ink_lbl.text = "Ink %d" % ch.ink
	if not Game.has_book():
		_rebuild_bare_hands()
		_rebuild_castbar()
		return
	var mx := Game.max_spell_level()
	for i in ch.spells.size():
		var s: Dictionary = ch.spells[i]
		var st: Dictionary = Game.spell_stats(s)
		var row := HBoxContainer.new()
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label("%d · %s" % [i + 1, Game.spell_name(s)], 16, C.ink))
		var next := "Fully written" if s.lvl >= mx else "evolves at Lv %d" % mini(mx, (int(s.lvl / 4.0) + 1) * 4)
		col.add_child(_label("Lv %d/%d · %s · %d dmg · %d ink · read %.2fs · %s" % [s.lvl, mx, GameData.KIND_LABEL[st.kind], roundi(st.dmg), roundi(st.mana), float(st.read), next], 12, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))
		var pips := Pips.new()
		pips.lvl = s.lvl
		pips.max_lvl = mx
		pips.col = C[ch.el]
		pips.off = Color(C.ink, 0.12)
		pips.gilt = C.gilt
		pips.custom_minimum_size = Vector2(0, 5)
		col.add_child(pips)
		row.add_child(col)
		var b := _button("+ Ink", w.spend_ink.bind(i))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = ch.ink < 1 or s.lvl >= mx
		row.add_child(b)
		spell_box.add_child(row)
	_rebuild_castbar()


## Before the ceremony: list the bare-hands moves. Ink is saved for later.
func _rebuild_bare_hands() -> void:
	for c in spell_box.get_children():
		c.queue_free()
	ink_lbl.text = "Ink %d (saved)" % w.ch.ink
	for i in GameData.BARE_HANDS.size():
		var st: Dictionary = Game.bare_stats(i)
		var col := VBoxContainer.new()
		col.add_child(_label("%d · %s" % [i + 1, st.name], 16, C.ink))
		var cost := "free" if float(st.mana) <= 0.0 else "%d mana" % roundi(st.mana)
		var honed := ""
		if float(st.mastery) >= 0.01:
			honed = " · honed +%d%%" % roundi(100.0 * float(st.mastery))
		col.add_child(_label("%s · %d dmg · %s%s" % [st.get("label", GameData.KIND_LABEL[st.kind]), roundi(st.dmg), cost, honed], 12, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))
		spell_box.add_child(col)
	spell_box.add_child(_label("Moves you favour grow honed. Your ink waits for the book you'll receive at the ceremony.", 12, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))


## Stats for cast button i: a spell once you have a book, a bare-hands move before.
func _slot_stats(i: int) -> Dictionary:
	if Game.has_book():
		return Game.spell_stats(w.ch.spells[i])
	return Game.bare_stats(i)


func _rebuild_castbar() -> void:
	for c in castbar.get_children():
		c.queue_free()
	cast_btns.clear()
	var bound := Game.has_book()
	var col: Color = C[w.ch.el] if bound else C.none
	var n: int = w.ch.spells.size() if bound else GameData.BARE_HANDS.size()
	for i in n:
		var b := CastButton.new()
		b.text = "%d   %s" % [i + 1, Game.spell_name(w.ch.spells[i]) if bound else GameData.BARE_HANDS[i].name]
		b.col = col
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(C.paper, 0.85), col))
		b.pressed.connect(func(): w.casting.turn_to(i))
		castbar.add_child(b)
		cast_btns.append(b)
	last_page_btn = CastButton.new()
	last_page_btn.text = "4   Last Page"
	last_page_btn.col = C.gilt
	last_page_btn.focus_mode = Control.FOCUS_NONE
	last_page_btn.add_theme_stylebox_override("normal", UiTheme.box(Color(C.paper, 0.85), C.gilt, 2))
	last_page_btn.visible = false
	castbar.add_child(last_page_btn)
	book_btn = Button.new()
	book_btn.text = "B   Open book"
	book_btn.focus_mode = Control.FOCUS_NONE
	book_btn.add_theme_stylebox_override("normal", UiTheme.box(Color(C.paper, 0.85), C.ink))
	book_btn.pressed.connect(w.open_book)
	book_btn.visible = bound
	castbar.add_child(book_btn)


# ---------------------------------------------------------------- Per-frame refresh

func refresh(dt: float) -> void:
	var p = w.player
	var ch: Dictionary = w.ch
	_set_bar("hp", p.hp, Game.max_hp(), "%d/%d" % [ceili(p.hp), Game.max_hp()])
	_set_bar("mp", p.mana, Game.max_mana(), "%d/%d" % [floori(p.mana), Game.max_mana()])
	_set_bar("xp", ch.xp, Game.xp_next(ch.level), "%d/%d" % [ch.xp, Game.xp_next(ch.level)])
	lvl_lbl.text = "Lv %d" % ch.level

	var bits: Array = []
	if w.streak > 1:
		bits.append("Streak %d" % w.streak)
	if ch.el == "fire" and p.heat > 0:
		bits.append("Heat %d" % p.heat)
	if ch.aspect.awakened:
		bits.append(GameData.ASPECTS[ch.aspect.id].name)
	status_lbl.text = " · ".join(bits)

	var free_cast: bool = ch.aspect.awakened and ch.aspect.id == "stillness" and p.still > 0.4
	var cs = w.casting
	for i in cast_btns.size():
		var b: CastButton = cast_btns[i]
		var st: Dictionary = _slot_stats(i)
		b.open = i == cs.page
		b.cd = cs.progress() if cs.reading and cs.slot == i else (1.0 - cs.turn_t / maxf(0.01, cs.turn_time()) if cs.turn_target == i else 0.0)
		b.modulate.a = 1.0 if free_cast or p.mana >= st.mana else 0.55
		b.queue_redraw()
	last_page_btn.visible = w.last_page_ready()
	last_page_btn.queue_redraw()
	vignette.amount = 0.35 * cs.strain_t / float(GameData.OVERCAST.strain_time)
	vignette.queue_redraw()

	var rd: float = p.position.length()
	var reg := 0
	while rd >= GameData.REGIONS[reg].max:
		reg += 1
	if reg != region:
		region_lbl.text = GameData.REGIONS[reg].name
		region_sub.text = GameData.REGIONS[reg].sub
		if region >= 0:
			add_log("Entered %s." % GameData.REGIONS[reg].name)
		region = reg
	death.visible = p.dead_t > 0.0
	ceremony_lbl.visible = w.ceremony_ready()
	if ceremony_lbl.visible:
		ceremony_lbl.text = "Your Book Ceremony is ready. Return to the Hearth."

	honed_t -= dt
	if honed_t <= 0.0 and not Game.has_book():
		honed_t = 1.0
		_rebuild_bare_hands()   # honed bonuses change as you fight
	dev_t -= dt
	if dev_box.visible and dev_t <= 0.0:
		dev_t = 0.3
		_refresh_dev()


func _set_bar(key: String, v: float, mx: float, txt: String) -> void:
	var b: Bar = bars[key].bar
	b.value = v
	b.max_value = mx
	b.queue_redraw()
	bars[key].num.text = txt


# ---------------------------------------------------------------- Margins, log, misc

func refresh_margins(fresh: bool) -> void:
	for c in margins_box.get_children():
		c.queue_free()
	var m: Array = w.ch.aspect.margins
	if m.is_empty():
		margins_box.add_child(_label("Nothing written here. Yet.", 14, C.ink_soft, HORIZONTAL_ALIGNMENT_LEFT, true))
		return
	for i in m.size():
		var l := _label(m[i], 14, C.gilt, HORIZONTAL_ALIGNMENT_LEFT, true)
		margins_box.add_child(l)
		if fresh and i == m.size() - 1:
			l.modulate.a = 0.0
			l.create_tween().tween_property(l, "modulate:a", 1.0, 2.0)


func stir_book_button() -> void:
	var tw := book_btn.create_tween().set_loops(3)
	tw.tween_property(book_btn, "modulate", C.gilt, 0.35)
	tw.tween_property(book_btn, "modulate", Color.WHITE, 0.35)


func add_log(t: String) -> void:
	var l := _label(t, 13, C.ink, HORIZONTAL_ALIGNMENT_LEFT, true)
	log_box.add_child(l)
	log_box.move_child(l, 0)
	while log_box.get_child_count() > 6:
		var last := log_box.get_child(log_box.get_child_count() - 1)
		log_box.remove_child(last)
		last.queue_free()
	for i in log_box.get_child_count():
		log_box.get_child(i).add_theme_color_override("font_color", C.ink if i == 0 else C.ink_soft)


func _on_new_pressed() -> void:
	if not new_armed:
		new_armed = true
		new_btn.text = "Press again to give up %s's book" % w.ch.name
		get_tree().create_timer(3.0).timeout.connect(_disarm_new)
		return
	w.give_up_character()


func _disarm_new() -> void:
	new_armed = false
	new_btn.text = "Start a new character"


func toggle_dev() -> void:
	dev_box.visible = not dev_box.visible
	if dev_box.visible:
		_refresh_dev()


func _refresh_dev() -> void:
	if not Game.has_book():
		_refresh_dev_lean()
		return
	var a: Dictionary = w.ch.aspect
	var as_: Dictionary = GameData.ASPECTS[a.id]
	var met: bool = w.chapter.act_met()
	var soft: String = C.ink_soft.to_html(false)
	dev_lbl.text = "[color=#%s]SPOILERS. In the online game this lives only on the server.[/color]\n\n[b]%s[/b]: %s\n\n[color=#%s]Trigger[/color]  %s\n[color=#%s]Progress[/color]  %d / %d · hint %d of 4%s\n[color=#%s]Awaken[/color]  %s\n[color=#%s]Act possible now[/color]  %s" % [
		soft, as_.name, as_.effect,
		soft, w.chapter.trigger_text(),
		soft, a.progress, a.need, a.stage, " · awakened" if a.awakened else "",
		soft, w.chapter.act_text(),
		soft, "yes" if met else "no",
	]


## Designer view before the ceremony: playstyle signals and the current book odds.
func _refresh_dev_lean() -> void:
	var ch: Dictionary = w.ch
	var soft: String = C.ink_soft.to_html(false)
	var sc := Game.lean_scores(ch)
	var ew := Game.element_weights(ch)
	var tw := Game.thickness_weights(ch)
	var etot := 0.0
	for k in ew:
		etot += ew[k]
	var ttot := 0.0
	for k in tw:
		ttot += tw[k]
	var sig: Dictionary = ch.get("signals", {})
	var temper: Dictionary = ch.get("temper", {})
	var lines: Array = []
	for k in Game.ELS:
		var parts: Array = []
		for sname in GameData.SIGNALS:
			if GameData.SIGNALS[sname].el == k:
				parts.append("%s %d" % [sname, roundi(float(sig.get(sname, 0.0)))])
		lines.append("[color=#%s]%s[/color]  score %d · temper x%.2f · [b]%d%%[/b]\n   [color=#%s]%s[/color]" % [
			C[k].to_html(false), GameData.ELEMENTS[k].name, roundi(sc[k]), float(temper.get(k, 1.0)),
			roundi(100.0 * ew[k] / etot), soft, ", ".join(parts)])
	var sh := Game.move_shares(ch)
	var mv: Array = []
	for m in sh:
		mv.append("%s %d%%" % [m, roundi(100.0 * sh[m])])
	var th: Array = []
	for t in tw:
		th.append("%s %d%%" % [t, roundi(100.0 * tw[t] / ttot)])
	dev_lbl.text = "[color=#%s]SPOILERS. Players never see these numbers.[/color]\n\n[b]Book element[/b] (signals, score, chance now)\n%s\n\n[b]Thickness[/b]  %s\n[color=#%s]Moves %s · focus %.2f[/color]\n\n[color=#%s]Ceremony at Lv %d. Rules are in SIGNALS, LEAN and FOCUS in game_data.gd.[/color]" % [
		soft, "\n".join(lines), ", ".join(th), soft, ", ".join(mv), Game.focus(ch), soft, GameData.CEREMONY_LEVEL]
