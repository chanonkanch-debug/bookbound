extends CanvasLayer
## What the player sees while playing. Almost nothing, on purpose:
## no numbers, no bars, no level. Each piece fades in the first time it matters
## (see UI_PARTS and the unlock rules in world.gd):
##   hands    three stance marks, once an enemy first comes close
##   journal  a small notebook mark and whispered lines, after a first kill, near-death or Hearth visit
##   book     the book at the bottom of the screen, from the ceremony on
##   margins  margin notes beside the book, with the first one
##   map      the map (M), after finding a map scrap or walking all three regions
##   vials    small vials of monster ink at the bottom right, after the first drop is taken
##            (The Unwritten, Phase 3): each looks as full as it is, never a count
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
	const Ink := preload("res://scripts/util/ink.gd")
	var w
	var glow := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var cs = w.casting
		var c := Vector2(size.x / 2.0, size.y - 46.0)
		if not Game.has_book():
			# One mark per move: a fist (Jab), an open palm (Shove), a foot (Sidestep),
			# then moves learned from monsters. Small dots under a mark show how far it has grown.
			var moves: Array = Game.bare_moves()
			var n: int = moves.size()
			for i in n:
				var p := c + Vector2((i - (n - 1) / 2.0) * 46.0, 0)
				var open: bool = i == (cs.turn_target if cs.turning() else cs.page)
				var col := Color(C.ink, 0.9 if open else 0.3)
				draw_circle(p, 17.0, Color(C.paper, 0.75 if open else 0.4))
				if open and w.player.mana < float(moves[i].get("mana", 0.0)):
					# Too little ink for this move: its rim breaks up, edged red.
					Ink.dashed_circle(self, p, 17.0, Color(C.danger, 0.8), 2.0)
				else:
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
					_:
						match String(moves[i].move):
							"flank":   # a curve around a dot
								draw_circle(p + Vector2(3, 0), 3.0, col)
								draw_arc(p + Vector2(3, 0), 9.0, PI * 0.6, PI * 1.9, 12, col, 2.0)
							"rush":    # a heavy arrow
								draw_line(p + Vector2(-9, 0), p + Vector2(7, 0), col, 4.0)
								draw_colored_polygon(PackedVector2Array([p + Vector2(10, 0), p + Vector2(3, -6), p + Vector2(3, 6)]), col)
							"brace":   # a shoulder turned to the blow
								draw_arc(p + Vector2(-3, 0), 9.0, -1.1, 1.1, 12, col, 4.0)
				var grown: int = w.hands.tier(String(moves[i].move))
				for k in grown:
					draw_circle(p + Vector2((k - (grown - 1) / 2.0) * 7.0, 24.0), 2.2, col)
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
		# Can the open page pay for itself? If not, its lines break up and the edge goes red.
		var cost: float = cs.page_cost()
		var short: bool = w.player.mana < cost
		if short:
			draw_rect(r.grow(2.0), Color(C.danger, 0.55 + 0.2 * sin(w.time * 5.0)), false, 1.5)
		for side in 2:
			var x0: float = r.position.x + 8.0 + side * bw / 2.0
			for ln in 5:
				var y: float = r.position.y + 12.0 + ln * 8.5
				var full := 0.15 + 0.85 * clampf(ink_f * 5.0 - ln, 0.0, 1.0)
				if short:
					Ink.dashed_line(self, Vector2(x0, y), Vector2(x0 + bw / 2.0 - 16.0, y), Color(el, 0.85 * full), 2.0, 6.0)
				else:
					draw_line(Vector2(x0, y), Vector2(x0 + bw / 2.0 - 16.0, y), Color(el, 0.85 * full), 2.0)
		if turning:
			# A page lifting off the right side, arching over the spine and settling on the left.
			var spine_x: float = r.position.x + bw / 2.0
			var reach: float = cos(k_turn * PI) * (bw / 2.0 - 2.0)
			var lift: float = sin(k_turn * PI) * float(GameData.FEEL.page_turn_lift)
			var top := Vector2(spine_x + reach, r.position.y + 2.0 - lift)
			var bot := Vector2(spine_x + reach, r.end.y - 2.0 - lift * 0.6)
			var page := PackedVector2Array([Vector2(spine_x, r.position.y), top, bot, Vector2(spine_x, r.end.y)])
			draw_colored_polygon(page, Color(C.paper.darkened(0.08 * sin(k_turn * PI)), 1.0))
			draw_polyline(Ink.outline(page), Color(C.ink, 0.8), 1.2)
			for ln in 3:
				var q := 0.25 + ln * 0.22
				draw_line(Vector2(spine_x, r.position.y).lerp(Vector2(spine_x, r.end.y), q), top.lerp(bot, q), Color(el, 0.35), 1.0)
		# One dot per page, the open one filled.
		var n_pages: int = cs.page_count()
		for i in n_pages:
			var dp := c + Vector2((i - (n_pages - 1) / 2.0) * 14.0, bh / 2.0 + 12.0)
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


## The Unwritten, Phase 3: the monster inks you carry, one small vial each, by shape and fill.
class Vials extends Control:
	var w
	var fresh := 0.0
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var x := size.x - 14.0
		for ink in GameData.Inks.INK_ORDER:
			if int(w.ch.get("vials", {}).get(ink, 0)) <= 0:
				continue
			var I: Dictionary = GameData.Inks.INKS[ink]
			var wd := 10.0
			var ht := 22.0
			match String(I.shape):
				"tall":
					wd = 8.0
					ht = 28.0
				"round":
					wd = 14.0
					ht = 18.0
				"square":
					wd = 13.0
					ht = 20.0
			x -= wd
			var body := Rect2(Vector2(x, size.y - 18.0 - ht), Vector2(wd, ht))
			var f: float = w.inks.fill(ink)
			draw_rect(body, Color(C.paper, 0.8))
			draw_rect(Rect2(body.position + Vector2(0, ht * (1.0 - f)), Vector2(wd, ht * f)), Color(I.color, 0.9))
			draw_rect(body, Color(C.ink, 0.6 + 0.4 * fresh), false, 1.2)
			draw_rect(Rect2(body.position + Vector2(wd * 0.25, -4.0), Vector2(wd * 0.5, 4.0)), Color(C.ink, 0.7))
			if ink == "pale" and bool(w.ch.get("pale_used", false)):
				draw_line(body.position, body.end, Color(C.ink_soft, 0.8), 1.0)
			x -= 10.0


var w
var C: Dictionary = GameData.COLORS
var root: Control
var vials: Vials
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
var whisper_queue: Array = []   # journal lines waiting their turn (one at a time)
var whispering := false


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

	vials = Vials.new()
	vials.w = w
	vials.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vials.anchor_left = 1.0
	vials.anchor_right = 1.0
	vials.anchor_top = 1.0
	vials.anchor_bottom = 1.0
	vials.offset_left = -200
	vials.offset_top = -70
	vials.modulate.a = 0.0
	root.add_child(vials)

	numbers = _label("", 12, C.ink_soft)
	numbers.position = Vector2(24, 56)
	root.add_child(numbers)

	for part in GameData.UI_PARTS:
		shown[part] = false
	journal_mark.modulate.a = 0.0
	dock.modulate.a = 0.0
	_sync_parts(false)
	UiTheme.fit(self, root)


func _full(c: Control, parent: Control = null) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else root).add_child(c)
	return c


func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _label(text: String, font_size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, wraps := false) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wraps:
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
			"vials":
				node = vials
		if node == null:
			continue
		var target := 1.0 if (ui.get("hands", false) and not Game.has_book()) or (ui.get("book", false) and Game.has_book()) or part == "journal" else 0.0
		if part == "journal" or part == "vials":
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
	if frac < float(GameData.READABILITY.low_hp_pulse) and p.dead_t <= 0.0:
		# Near the end, the dark edges beat like a heart.
		vignette.amount *= 0.8 + 0.2 * pow(absf(sin(w.time * 3.2)), 6.0)
	vignette.queue_redraw()
	strain_v.amount = 0.35 * w.casting.strain_t / float(GameData.OVERCAST.strain_time)
	strain_v.queue_redraw()
	dock.glow = maxf(0.0, dock.glow - dt)
	dock.queue_redraw()
	journal_mark.fresh = maxf(0.0, journal_mark.fresh - dt * 0.5)
	journal_mark.queue_redraw()
	vials.fresh = maxf(0.0, vials.fresh - dt)
	vials.queue_redraw()
	death.visible = p.dead_t > 0.0

	# The world works out which region you're in (a rule); the HUD only shows the name.
	var reg: int = w.region
	if reg != region and reg >= 0:
		if region >= 0:
			region_lbl.text = GameData.REGIONS[reg].name
			var tw := region_lbl.create_tween()
			tw.tween_property(region_lbl, "modulate:a", 0.8, 1.0)
			tw.tween_interval(2.5)
			tw.tween_property(region_lbl, "modulate:a", 0.0, 1.5)
		region = reg

	numbers.visible = Game.show_numbers()
	if numbers.visible:
		numbers.text = "HP %d/%d · ink %d/%d · Lv %d (+%d waiting) · XP %d/%d" % [
			ceili(p.hp), Game.max_hp(), floori(p.mana), Game.max_mana(), w.ch.level,
			Game.pending_level(w.ch) - int(w.ch.level), Game.xp_into_level(w.ch), Game.xp_next(Game.pending_level(w.ch))]


## A new journal line whispers in at the bottom left, then fades. Lines that arrive
## together wait their turn, so none is lost behind another.
func add_log(t: String) -> void:
	if not w.ch.get("ui", {}).get("journal", false):
		return
	whisper_queue.append(t)
	if not whispering:
		_next_whisper()


func _next_whisper() -> void:
	if whisper_queue.is_empty():
		whispering = false
		return
	whispering = true
	whisper.text = whisper_queue.pop_front()
	journal_mark.fresh = 1.0
	var hold: float = float(GameData.WHISPER_TIME) if whisper_queue.is_empty() else float(GameData.WHISPER_QUEUED)
	var tw := whisper.create_tween()
	tw.tween_property(whisper, "modulate:a", 1.0, 0.6)
	tw.tween_interval(hold)
	tw.tween_property(whisper, "modulate:a", 0.0, 0.9)
	tw.tween_callback(_next_whisper)


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
