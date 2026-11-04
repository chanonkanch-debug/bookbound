extends RefCounted
## The Unwritten, Phase 3: monster inks and branching growth. Rules only; drawing is in
## world.gd (drops), hud.gd (vials), rest_overlay.gd (pots) and book_overlay.gd (paths).
## Numbers and words: scripts/data/ink_data.gd (GameData.Inks).
##
##   drops     a monster that comes apart may leave a drop of its own ink; walk over it
##   vials     ch.vials holds doses per ink (shown as fuller or emptier vials, never counts)
##   writing   at a rest, each level written into a page can be dipped in one pot:
##             slot.inks records the pot per level ("plain" = the book's own ink)
##   steps     when a page evolves (every 4 levels), slot.branch gets the monster ink used most
##             since its last evolution ("plain" if none); any pale wins, once per book
##   stats     every step's branch is applied on top of the plain evolution (apply_path)
##   hands     before the book, a move that grows at a rest can be dipped too (ch.hands.branch)
##
## Static helpers (stats, names) are used by game.gd; the rest needs the world.

const ORDER := ["plain", "quick", "heavy", "stubborn", "pale"]
const MULT := ["read", "dmg", "mana", "speed", "radius", "dur", "dash_len", "range", "tick", "life", "width", "dodge", "size", "spread", "push_x"]
const MULT_DEFAULT := {"life": 1.1, "width": 1.0, "dodge": 1.0, "size": 1.0, "tick": 0.5, "spread": 1.0}
const ADD := ["pierce", "push", "guard", "guard_in", "echo", "linger", "raise_push", "echo_dash"]
const KEEP_MAX := ["guard_time", "echo_delay", "back"]
const FLAGS := ["returns", "loops", "inward", "follows", "cages"]
const WORDS := ["name", "line", "margin"]

var w
var drops: Array = []        # {"p": Vector2, "ink": String, "t": seconds lying there}


func _init(world) -> void:
	w = world
	ensure(w.ch)


## Fills in the Phase 3 fields on a character (new, migrated, or a test's hand-made one).
static func ensure(ch: Dictionary) -> void:
	if not ch.has("vials"):
		ch.vials = {}
	if not ch.has("pale_used"):
		ch.pale_used = false
	for s in ch.get("spells", []):
		ensure_slot(s)
	if ch.has("hands") and not ch.hands.has("branch"):
		ch.hands.branch = {}
	if ch.has("hands") and not ch.hands.has("dip"):
		ch.hands.dip = ""


## A page written before Phase 3 has plain ink in every level and plain steps.
static func ensure_slot(s: Dictionary) -> void:
	var lvl := int(s.get("lvl", 1))
	if not s.has("inks"):
		s.inks = []
		for k in maxi(0, lvl - 1):
			s.inks.append("plain")
	if not s.has("branch"):
		s.branch = []
		for k in int(lvl / 4.0):
			s.branch.append("plain")


# ---------------------------------------------------------------- Stats (static)

## Which branch table a spell grows from.
static func kind_of(spell: Dictionary) -> String:
	return String(spell.get("branch_kind", spell.get("kind", "bolt")))


## The changes one step makes, for a spell kind and the ink that step took.
static func mods_for(kind: String, ink: String) -> Dictionary:
	if ink == "pale":
		return GameData.Inks.PALE.get(kind, {})
	if ink == "plain" or ink == "":
		return {}
	return GameData.Inks.BRANCHES.get(kind, {}).get(ink, {})


## One step's changes on top of stats `st` (see the field list in ink_data.gd).
static func apply(st: Dictionary, mods: Dictionary) -> void:
	for k in mods:
		var v = mods[k]
		if k in WORDS:
			continue
		if k == "push_x":
			if st.has("push"):
				st.push = float(st.push) * float(v)
		elif k in MULT:
			if st.has(k) or MULT_DEFAULT.has(k):
				st[k] = float(st.get(k, MULT_DEFAULT.get(k, 1.0))) * float(v)
		elif k == "count":
			st.count = int(st.get("count", 0)) + int(v)
		elif k == "jumps":
			if st.has("jumps"):
				st.jumps = maxi(1, int(st.jumps) + int(v))
		elif k == "slow":
			st.slow = clampf(float(st.get("slow", 1.0)) + float(v), 0.1, 1.0)
		elif k in ADD:
			st[k] = float(st.get(k, 0.0)) + float(v)
			if k == "pierce":
				st.pierce = int(st.pierce)
		elif k in KEEP_MAX:
			st[k] = maxf(float(st.get(k, 0.0)), float(v))
		elif k in FLAGS:
			st[k] = bool(v)


## Every step of a page's path applied in order. Also sets `mark` (the newest monster ink,
## for the drawing) and `path` (the steps).
static func apply_path(st: Dictionary, kind: String, path: Array) -> void:
	st.path = path.duplicate()
	st.mark = ""
	for ink in path:
		apply(st, mods_for(kind, String(ink)))
		if String(ink) != "plain":
			st.mark = String(ink)


## The word a branched spell takes from its newest monster-ink step, or "".
static func branch_word(kind: String, path: Array) -> String:
	for k in range(path.size() - 1, -1, -1):
		var m := mods_for(kind, String(path[k]))
		if m.has("name"):
			return String(m.name)
	return ""


## A bare-hands move after its dips (HAND_BRANCHES).
static func apply_hands(st: Dictionary, path: Array) -> void:
	st.path = path.duplicate()
	st.mark = ""
	var table: Dictionary = GameData.Inks.HAND_BRANCHES.get(String(st.get("move", "")), {})
	for ink in path:
		if table.has(String(ink)):
			apply(st, table[ink])
			st.mark = String(ink)


## "quick, then heavy" for a path (no numbers), or "" for none yet.
static func path_words(path: Array) -> String:
	var bits: Array = []
	for ink in path:
		bits.append(String(GameData.Inks.LINES.path_plain) if String(ink) == "plain" else String(ink))
	return (", %s " % String(GameData.Inks.LINES.path_then)).join(bits)


static func color(ink: String) -> Color:
	if GameData.Inks.INKS.has(ink):
		return GameData.Inks.INKS[ink].color
	return GameData.COLORS.ink


# ---------------------------------------------------------------- Vials

func me() -> Dictionary:
	return w.ch


func dose(ink: String) -> int:
	return int(me().vials.get(ink, 0))


func full(ink: String) -> bool:
	return dose(ink) >= int(GameData.Inks.INKS[ink].cap)


## 0..1 how full a vial looks.
func fill(ink: String) -> float:
	return clampf(float(dose(ink)) / float(GameData.Inks.INKS[ink].cap), 0.0, 1.0)


## Inks you carry, in pot order. The pale is left out once the book has taken it.
func carried() -> Array:
	var out: Array = []
	for ink in GameData.Inks.INK_ORDER:
		if dose(ink) > 0 and not (ink == "pale" and bool(me().pale_used)):
			out.append(ink)
	return out


## The pots offered when writing a level: the book's own ink, then what you carry.
func pots() -> Array:
	return ["plain"] + carried()


## The pots offered to your bare hands (never the pale).
func dip_pots() -> Array:
	return carried().filter(func(k): return k != "pale")


# ---------------------------------------------------------------- Drops

## A monster came apart. It may leave a drop of its own ink.
func on_kill(e) -> void:
	var ink := ""
	if String(e.guardian) != "":
		ink = "pale"
		if bool(me().pale_used):
			return   # the book has had its pale; guardians leave none now
	else:
		for k in GameData.Inks.INKS:
			if String(GameData.Inks.INKS[k].from) == String(e.foe_name):
				ink = k
				break
	if ink == "" or randf() >= float(GameData.Inks.INKS[ink].chance):
		return
	var sc: float = float(GameData.Inks.DROP.scatter)
	drops.append({"p": e.position + Vector2(randf_range(-sc, sc), randf_range(-sc, sc)), "ink": ink, "t": 0.0})


func tick(dt: float) -> void:
	if drops.is_empty():
		return
	var D: Dictionary = GameData.Inks.DROP
	var p: Vector2 = w.player.position
	var alive: bool = w.player.dead_t <= 0.0
	for dr in drops:
		dr.t = float(dr.t) + dt
		var d: float = p.distance_to(dr.p)
		if not alive:
			continue
		if full(String(dr.ink)):
			if d < float(D.pickup):
				w.journal("vials_full", String(GameData.Inks.LINES.vials_full))
			continue
		if d < float(D.pull) and d > 1.0:
			dr.p += (p - dr.p) / d * minf(d, float(D.pull_speed) * dt)
			d = p.distance_to(dr.p)
		if d < float(D.pickup):
			pick_up(dr)
	drops = drops.filter(func(x): return float(x.t) < float(D.life) and not x.has("taken"))


func pick_up(dr: Dictionary) -> void:
	dr.taken = true
	var ink: String = dr.ink
	me().vials[ink] = dose(ink) + 1
	w.unlock("vials")
	if w.hud != null:
		w.hud.vials.fresh = 1.0
	w.ring(dr.p, 3, 16, 0.35, color(ink), 1.5)
	if ink == "pale":
		w.journal("ink_first_pale", String(GameData.Inks.LINES.first_pale))
	else:
		w.journal("ink_first_drop", String(GameData.Inks.LINES.first_drop))
		w.journal("ink_" + ink, "%s: %s" % [String(GameData.Inks.INKS[ink].name).substr(0, 1).to_upper() + String(GameData.Inks.INKS[ink].name).substr(1), String(GameData.Inks.INKS[ink].about)])


# ---------------------------------------------------------------- Writing (at a rest)

## A level was just written into page i with `pot`. Spends a dose of a monster ink.
## Returns the pot actually used ("plain" if that ink has run out).
func write(i: int, pot: String) -> String:
	var s: Dictionary = me().spells[i]
	ensure_slot(s)
	if pot != "plain" and not pot in carried():
		pot = "plain"
	if pot != "plain":
		me().vials[pot] = dose(pot) - 1
	s.inks.append(pot)
	return pot


## The monster inks written into page i since its last evolution.
static func window(s: Dictionary, step: int) -> Array:
	var start := maxi(0, 4 * (step - 1) - 1)   # page levels start at 1, so the first step has three
	return s.inks.slice(start, s.inks.size())


## Page i just evolved: its new step branches by the ink used most since the last one.
## Returns the ink the step took.
func resolve_step(i: int) -> String:
	var s: Dictionary = me().spells[i]
	ensure_slot(s)
	var step: int = s.branch.size() + 1
	var win := window(s, step)
	var ink := choose(win, bool(me().pale_used))
	s.branch.append(ink)
	var kind := kind_of(GameData.SPELLS[me().el][int(s.i)])
	if ink == "pale":
		me().pale_used = true
		var line: String = String(GameData.Inks.PALE[kind].margin)
		me().disc.margins.append(line)
		w.on_hint(line)
	elif ink != "plain":
		w.journal("first_branch", String(GameData.Inks.LINES.first_branch))
		w.journal("branch_%s_%s" % [kind, ink], String(GameData.Inks.BRANCHES[kind][ink].line))
	return ink


## The ink a step takes from the inks written in its window.
static func choose(win: Array, pale_used: bool) -> String:
	if "pale" in win and not pale_used:
		return "pale"
	var best := "plain"
	var best_n := 0
	for k in range(win.size() - 1, -1, -1):   # newest first, so a tie goes to the newest
		var ink: String = String(win[k])
		if ink == "plain" or ink == "pale":
			continue
		var n: int = win.count(ink)
		if n > best_n:
			best_n = n
			best = ink
	return best


# ---------------------------------------------------------------- Bare hands

## A move grew at this rest (hands.gd). If you carry monster ink, the dip waits for you;
## otherwise the step stays plain. Returns true if a dip is waiting.
func offer_dip(move: String) -> bool:
	if not me().hands.branch.has(move):
		me().hands.branch[move] = []
	if dip_pots().is_empty():
		me().hands.branch[move].append("plain")
		return false
	me().hands.dip = move
	return true


func dip_waiting() -> String:
	return String(me().hands.get("dip", ""))


## Dip the waiting move's hands into `ink` ("plain" leaves them as they are).
func dip(ink: String) -> void:
	var move := dip_waiting()
	if move == "":
		return
	me().hands.dip = ""
	if ink != "plain" and not ink in dip_pots():
		ink = "plain"
	me().hands.branch[move].append(ink)
	if ink != "plain":
		me().vials[ink] = dose(ink) - 1
		w.journal("dip_%s_%s" % [move, ink], String(GameData.Inks.HAND_BRANCHES[move][ink].line))


# ---------------------------------------------------------------- Designer view (F1)

func designer_text() -> String:
	var soft: String = GameData.COLORS.ink_soft.to_html(false)
	var out := "\n[b]Monster inks[/b] · pale %s\n" % ("taken by this book" if bool(me().pale_used) else "not used yet")
	var v: Array = []
	for ink in GameData.Inks.INK_ORDER:
		v.append("%s %d/%d" % [ink, dose(ink), int(GameData.Inks.INKS[ink].cap)])
	out += "vials: %s · drops lying: %d\n" % [", ".join(v), drops.size()]
	if Game.has_book(me()):
		for i in me().spells.size():
			var s: Dictionary = me().spells[i]
			ensure_slot(s)
			var kind := kind_of(GameData.SPELLS[me().el][int(s.i)])
			var st: Dictionary = Game.spell_stats(s)
			var nxt := (int(s.branch.size()) + 1)
			out += "[color=#%s]%s[/color] (%s) path [%s] · since last step [%s] → next step would take %s\n" % [
				soft, Game.spell_name(s), kind, ", ".join(s.branch), ", ".join(window(s, nxt)), choose(window(s, nxt), bool(me().pale_used))]
			out += "   read %.2fs · dmg %d · ink %d · size x%.2f%s%s\n" % [float(st.read), roundi(st.dmg), roundi(st.mana), float(st.get("size", 1.0)),
				_extra(st), " · mark %s" % st.mark if String(st.mark) != "" else ""]
	else:
		var hb: Dictionary = me().hands.get("branch", {})
		out += "hands: %s · dip waiting: %s\n" % [str(hb), dip_waiting() if dip_waiting() != "" else "no"]
	return out


static func _extra(st: Dictionary) -> String:
	var bits: Array = []
	for k in ["count", "pierce", "push", "guard", "guard_in", "echo", "linger", "raise_push", "echo_dash"]:
		if float(st.get(k, 0.0)) != 0.0:
			bits.append("%s %s" % [k, str(snappedf(float(st[k]), 0.01))])
	for k in FLAGS:
		if bool(st.get(k, false)):
			bits.append(k)
	for k in ["speed", "radius", "dur", "dash_len", "tick", "jumps", "slow", "width", "dodge"]:
		if st.has(k) and k in ["jumps"]:
			bits.append("%s %d" % [k, int(st[k])])
		elif st.has(k):
			bits.append("%s %s" % [k, str(snappedf(float(st[k]), 0.01))])
	return " · " + ", ".join(bits) if not bits.is_empty() else ""
