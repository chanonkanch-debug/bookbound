extends CanvasLayer
## What the player sees while playing. Almost nothing, on purpose:
## no numbers, no bars, no level. Each piece fades in the first time it matters
## (see UI_PARTS and the unlock rules in world.gd):
##   hands    three stance marks, once an enemy first comes close
##   journal  a small notebook mark and whispered lines, after a first kill, near-death or Hearth visit
##   book     the book at the bottom of the screen, from the ceremony on
##   margins  margin notes beside the book, with the first one
##   map      the map (M), after finding a map scrap or walking all three regions
## Health shows on your ink body and as dark screen edges; casting ink shows as how
## full the open page looks. The F1 designer view (designer_panel.gd) shows every number.
## The hidden `show_numbers` setting (toggle it in F1) brings a small readout back.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const Ink := preload("res://scripts/util/ink.gd")


## Darkens the screen edges: low health (ink) and overcast strain (red).
class Vignette extends Control:
	var amount := 0.0
	var col := Color.BLACK
	func _draw() -> void:
		if amount <= 0.01:
			return
		var s := size
		var e := minf(s.x, s.y) * 0.24
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


## The bottom of the screen: stance marks before the ceremony, the book after.
class Dock extends Control:
	var w
	var glow := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var cs = w.casting
		var c := Vector2(size.x / 2.0, size.y - 46.0)
		if not Game.has_book():
			# Three marks: a fist (Jab), an open palm (Shove), a foot (Sidestep).
			for i in 3:
				var p := c + Vector2((i - 1) * 46.0, 0)
				var open: bool = i == (cs.turn_target if cs.turning() else cs.page)
				var col := Color(C.ink, 0.9 if open else 0.3)
				draw_circle(p, 17.0, Color(C.paper, 0.75 if open else 0.4))
				draw_arc(p, 17.0, 0, TAU, 32, col, 2.0 if open else 1.0)
				match i:
					0:
						draw_circle(p, 6.5, col)
					1:
						for k in 4:
							draw_line(p + Vector2(-6 + k * 4, 2), p + Vector2(-6 + k * 4, -8), col, 2.0)
						draw_circle(p + Vector2(0, 4), 5.0, col)
					2:
						draw_line(p + Vector2(-8, 6), p + Vector2(8, 6), col, 3.0)
						draw_line(p + Vector2(-8, 6), p + Vector2(-6, -7), col, 3.0)
			return
		# The open book. The current page's lines are as dark as your casting ink is full.
		var ink_f: float = clampf(w.player.mana / Game.max_mana(), 0.0, 1.0)
		var el: Color = C[w.ch.el]
		var bw := 96.0
		var bh := 58.0
		var r := Rect2(c - Vector2(bw, bh) / 2.0, Vector2(bw, bh))
		if glow > 0.0 or ink_f > 0.98:
			var g: float = maxf(glow, 0.25 if ink_f > 0.98 else 0.0)
			draw_rect(r.grow(5.0 + 3.0 * g), Color(C.gilt if glow > 0.0 else el, 0.25 * g))
		draw_rect(r, Color(C.paper, 0.92))
		draw_line(r.position + Vector2(bw / 2.0, 0), r.position + Vector2(bw / 2.0, bh), Color(C.ink, 0.5), 1.5)
		draw_rect(r, Color(C.ink, 0.8), false, 1.5)
		var turning: bool = cs.turning()
		var k_turn: float = 1.0 - cs.turn_t / maxf(0.01, cs.turn_time()) if turning else 0.0
		for side in 2:
			var x0: float = r.position.x + 8.0 + side * bw / 2.0
			for ln in 5:
				var y: float = r.position.y + 12.0 + ln * 8.5
				var full := 0.15 + 0.85 * clampf(ink_f * 5.0 - ln, 0.0, 1.0)
				draw_line(Vector2(x0, y), Vector2(x0 + bw / 2.0 - 16.0, y), Color(el, 0.85 * full), 2.0)
		if turning:
			# A page lifting over the spine.
			var px: float = r.position.x + bw / 2.0 + cos(k_turn * PI) * bw / 2.0
			draw_line(Vector2(r.position.x + bw / 2.0, r.position.y), Vector2(px, r.position.y + 4.0), C.ink, 1.5)
			draw_line(Vector2(px, r.position.y + 4.0), Vector2(px, r.end.y - 4.0), C.ink, 1.5)
		# One dot per page, the open one filled.
		var n: int = cs.page_count()
		for i in n:
			var dp := c + Vector2((i - (n - 1) / 2.0) * 14.0, bh / 2.0 + 12.0)
			if i == cs.page and not turning:
				draw_circle(dp, 4.0, el)
			else:
				draw_arc(dp, 4.0, 0, TAU, 16, Color(C.ink, 0.5), 1.2)
		if w.last_page_ready():
			draw_rect(Rect2(r.end.x + 6.0, r.position.y, 8.0, bh), Color(C.gilt, 0.6 + 0.4 * sin(w.time * 6.0)))


## A small notebook in the corner once the journal exists.
class JournalMark extends Control:
	var fresh := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var r := Rect2(Vector2(4, 4), Vector2(22, 28))
		draw_rect(r, Color(C.paper, 0.9))
		draw_rect(r, Color(C.ink, 0.7 + 0.3 * fresh), false, 1.5)
		for k in 3:
			draw_line(r.position + Vector2(5, 8 + k * 6), r.position + Vector2(17, 8 + k * 6), Color(C.ink_soft, 0.7), 1.0)


var w
var C: Dictionary = GameData.COLORS
var root: Control
var vignette: Vignette
var strain_v: Vignette
var death: Control
var dock: Dock
var journal_mark: JournalMark
var whisper: Label
var margin_note: Label
var region_lbl: Label
var numbers: Label
var region := -1
var shown := {}     # which parts are faded in already


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)

	vignette = _full(Vignette.new())
	vignette.col = C.ink
	strain_v = _full(Vignette.new())
	strain_v.col = C.danger

	death = _full(ColorRect.new())
	death.color = Color(C.paper, 0.75)
	death.visible = false
	var dc := _full(CenterContainer.new(), death)
	var dv := _ignore(VBoxContainer.new())
	dc.add_child(dv)
	dv.add_child(_label(GameData.DEATH_TEXT[0], 40, C.ink, HORIZONTAL_ALIGNMENT_CENTER))
	dv.add_child(_label(GameData.DEATH_TEXT[1], 16, C.ink_soft, HORIZONTAL_ALIGNMENT_CENTER))

	dock = _full(Dock.new())
	dock.w = w
	region_lbl = _label("", 22, C.ink_soft)
	region_lbl.position = Vector2(24, 18)
	region_lbl.modulate.a = 0.0
	root.add_child(region_lbl)

	journal_mark = JournalMark.new()
	journal_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	journal_mark.anchor_top = 1.0
	journal_mark.anchor_bottom = 1.0
	journal_mark.offset_left = 18
	journal_mark.offset_top = -52
	journal_mark.offset_right = 50
	journal_mark.offset_bottom = -16
	root.add_child(journal_mark)
	whisper = _label("", 15, C.ink, HORIZONTAL_ALIGNMENT_LEFT, true)
	whisper.anchor_top = 1.0
	whisper.anchor_bottom = 1.0
	whisper.offset_left = 58
	whisper.offset_right = 470
	whisper.offset_top = -50
	whisper.offset_bottom = -16
	whisper.modulate.a = 0.0
	root.add_child(whisper)
	margin_note = _label("", 14, C.gilt, HORIZONTAL_ALIGNMENT_LEFT, true)
	margin_note.anchor_left = 0.5
	margin_note.anchor_right = 0.5
	margin_note.anchor_top = 1.0
	margin_note.anchor_bottom = 1.0
	margin_note.offset_left = 70
	margin_note.offset_right = 360
	margin_note.offset_top = -100
	margin_note.offset_bottom = -40
	margin_note.modulate.a = 0.0
	root.add_child(margin_note)

	numbers = _label("", 12, C.ink_soft)
	numbers.position = Vector2(24, 56)
	root.add_child(numbers)

	for part in GameData.UI_PARTS:
		shown[part] = false
	journal_mark.modulate.a = 0.0
	dock.modulate.a = 0.0
	_sync_parts(false)


func _full(c: Control, parent: Control = null) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else root).add_child(c)
	return c


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


## Fades in any part that has just been unlocked (no text, no explanation).
func _sync_parts(fade: bool) -> void:
	var ui: Dictionary = w.ch.get("ui", {})
	for part in GameData.UI_PARTS:
		var on: bool = ui.get(part, false)
		if on == shown[part]:
			continue
		shown[part] = on
		var node: CanvasItem = null
		match part:
			"hands", "book":
				node = dock
			"journal":
				node = journal_mark
		if node == null:
			continue
		var target := 1.0 if (ui.get("hands", false) and not Game.has_book()) or (ui.get("book", false) and Game.has_book()) or part == "journal" else 0.0
		if part == "journal":
			target = 1.0 if on else 0.0
		if fade:
			node.create_tween().tween_property(node, "modulate:a", target, float(GameData.UI_FADE))
		else:
			node.modulate.a = target


# ---------------------------------------------------------------- Called by the world

func refresh(dt: float) -> void:
	_sync_parts(true)
	var p = w.player
	var frac: float = p.hp / Game.max_hp()
	vignette.amount = clampf((0.45 - frac) / 0.45, 0.0, 1.0) * 0.6 if p.dead_t <= 0.0 else 0.0
	vignette.queue_redraw()
	strain_v.amount = 0.35 * w.casting.strain_t / float(GameData.OVERCAST.strain_time)
	strain_v.queue_redraw()
	dock.glow = maxf(0.0, dock.glow - dt)
	dock.queue_redraw()
	journal_mark.fresh = maxf(0.0, journal_mark.fresh - dt * 0.5)
	journal_mark.queue_redraw()
	death.visible = p.dead_t > 0.0

	var rd: float = p.position.length()
	var reg := 0
	while rd >= GameData.REGIONS[reg].max:
		reg += 1
	if reg != region:
		if region >= 0:
			region_lbl.text = GameData.REGIONS[reg].name
			var tw := region_lbl.create_tween()
			tw.tween_property(region_lbl, "modulate:a", 0.8, 1.0)
			tw.tween_interval(2.5)
			tw.tween_property(region_lbl, "modulate:a", 0.0, 1.5)
		region = reg
		w.on_region(reg)

	numbers.visible = Game.show_numbers()
	if numbers.visible:
		numbers.text = "HP %d/%d · ink %d/%d · Lv %d (+%d waiting) · XP %d/%d" % [
			ceili(p.hp), Game.max_hp(), floori(p.mana), Game.max_mana(), w.ch.level,
			Game.pending_level(w.ch) - int(w.ch.level), Game.xp_into_level(w.ch), Game.xp_next(Game.pending_level(w.ch))]


## A new journal line whispers in at the bottom left, then fades.
func add_log(t: String) -> void:
	if not w.ch.get("ui", {}).get("journal", false):
		return
	whisper.text = t
	journal_mark.fresh = 1.0
	var tw := whisper.create_tween()
	tw.tween_property(whisper, "modulate:a", 1.0, 0.8)
	tw.tween_interval(float(GameData.WHISPER_TIME))
	tw.tween_property(whisper, "modulate:a", 0.0, 1.5)


## A new margin note appears beside the book, then fades (read them all in the book, B).
func refresh_margins(fresh: bool) -> void:
	if not fresh or not w.ch.get("ui", {}).get("margins", false):
		return
	var m: Array = w.all_margins()
	if m.is_empty():
		return
	margin_note.text = m[-1]
	var tw := margin_note.create_tween()
	tw.tween_property(margin_note, "modulate:a", 1.0, 1.5)
	tw.tween_interval(float(GameData.WHISPER_TIME))
	tw.tween_property(margin_note, "modulate:a", 0.0, 2.0)


func stir_book_button() -> void:
	dock.glow = 1.6


func rebuild_spells() -> void:
	dock.queue_redraw()
