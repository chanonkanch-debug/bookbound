extends RefCounted
## Casting is reading. Rules only (no drawing), so this can run on a server later.
##
## Hold the read key to start reading the page the book is open to; release to cast.
## Release before the page's read time and the spell fizzles (half the ink back).
## Keep holding past it to overcharge, up to READ.overcharge_cap more power.
## Moving slows reading. A hit may break the read. Turning pages takes time.
## Before the ceremony the "pages" are bare-hands stances (Jab, Shove, Sidestep).
##
## Numbers: READ, PAGES, OVERCAST in game_data.gd.

var w

var page := 0              # the page (spell slot) or stance the book is open to
var turn_target := -1      # page being turned to, -1 when not turning
var turn_t := 0.0          # seconds left on the current page turn
var reading := false
var slot := 0              # what is being read: a page index, or 3 for the hidden Last Page
var t := 0.0               # read progress in seconds (slower while moving)
var st: Dictionary = {}    # stats of the spell being read
var paid := 0.0            # casting ink paid for this read
var recover_t := 0.0
var strain_t := 0.0        # overcast strain, for the visuals
var armed := true          # the read key must be let go between casts (no auto-repeat)
var fizzle_fx := 0.0       # >0 right after a fizzle or broken read, for the visuals
var last_result := ""      # "cast", "fizzle", "broken" or "refused" (used by tests and the bot)
var casts := 0             # total successful casts (designer view, balance bot)
var fizzles := 0


func _init(world) -> void:
	w = world


func page_count() -> int:
	if not Game.has_book():
		return Game.bare_moves().size()
	return w.ch.spells.size()


func turn_time() -> float:
	if not Game.has_book():
		return float(GameData.PAGES.stance_switch)
	return float(GameData.PAGES.turn_time[w.ch.thick])


func turning() -> bool:
	return turn_target >= 0


## Turn toward page i. Each page between here and there takes one turn.
func turn_to(i: int) -> void:
	if i < 0 or i >= page_count() or reading:
		return
	if i == page and not turning():
		return
	if turning():
		# Already turning: just change where we're heading.
		turn_target = i
		return
	turn_target = i
	turn_t = turn_time()


func turn_by(step: int) -> void:
	var base := turn_target if turning() else page
	turn_to(clampi(base + step, 0, page_count() - 1))


## Stats for page i (or 3 for Last Page) as they would be cast now.
func stats_for(i: int) -> Dictionary:
	if not Game.has_book():
		return Game.bare_stats(i)
	if i == 3:
		var prim: Dictionary = Game.spell_stats(w.ch.spells[0])
		return {"kind": "nova", "el": w.ch.el, "dmg": prim.dmg * 3.0 + 40.0, "radius": 200.0, "tier": 0,
			"read": float(GameData.READ.last_page_read), "over": 0.0, "mana": 0.0, "name": "Last Page"}
	return Game.spell_stats(w.ch.spells[i])


## 0..1 progress toward the minimum read time, and 0..1 overcharge.
func progress() -> float:
	if not reading:
		return 0.0
	return clampf(t / maxf(0.001, float(st.read)), 0.0, 1.0)


func overcharge() -> float:
	if not reading or float(st.get("over", 0.0)) <= 0.0 or t < float(st.read):
		return 0.0
	return clampf((t - float(st.read)) / float(st.over), 0.0, 1.0)


func ready_to_cast() -> bool:
	return reading and t >= float(st.read)


## Called every simulation step. `held` is whether the read key is down,
## `want_slot` is 3 while the Last Page key is held instead.
func tick(dt: float, held: bool, want_slot := -1) -> void:
	recover_t = maxf(0.0, recover_t - dt)
	strain_t = maxf(0.0, strain_t - dt)
	fizzle_fx = maxf(0.0, fizzle_fx - dt)
	if turning():
		turn_t -= dt
		if turn_t <= 0.0:
			page += signi(turn_target - page)
			if page == turn_target:
				turn_target = -1
			else:
				turn_t = turn_time()
	if reading:
		var moving: bool = w.player.still <= 0.0
		t += dt * (float(GameData.READ.move_mult) if moving else 1.0)
		if not held:
			armed = true
			release()
		return
	if not held:
		armed = true
		return
	if armed and not turning() and recover_t <= 0.0 and w.player.dead_t <= 0.0:
		begin(want_slot if want_slot >= 0 else page)


func begin(i: int) -> void:
	if i == 3 and Game.has_book() and not w.last_page_ready():
		return
	if (i != 3 or not Game.has_book()) and i >= page_count():
		return
	armed = false
	st = stats_for(i)
	slot = i
	var a: Dictionary = w.ch.aspect
	var free: bool = Game.has_book() and a.awakened and a.id == "stillness" and w.player.still > 0.4
	var cost: float = 0.0 if free else float(st.mana)
	var p = w.player
	if p.mana >= cost:
		p.mana -= cost
		paid = cost
	else:
		# Overcast: the missing ink is paid in health. Refused if it would kill you.
		var missing: float = cost - p.mana
		var hp_cost: float = missing * float(GameData.OVERCAST.hp_per_ink)
		if p.hp <= hp_cost + 1.0:
			last_result = "refused"
			fizzle_fx = 0.4
			return
		paid = p.mana
		p.mana = 0.0
		p.hp -= hp_cost
		strain_t = float(GameData.OVERCAST.strain_time)
		w.on_overcast(hp_cost)
	reading = true
	t = 0.0


func release() -> void:
	if not reading:
		return
	reading = false
	if t < float(st.read):
		_fizzle("fizzle")
		return
	var k := overcharge()
	var mult: float = 1.0 + float(GameData.READ.overcharge_cap) * k
	var cast_st: Dictionary = st.duplicate()
	if cast_st.kind == "dash":
		cast_st.dash_len = float(cast_st.dash_len) * (1.0 + float(GameData.READ.overcharge_dash_len) * k)
	cast_st.overcharge = k
	recover_t = float(GameData.READ.recover)
	last_result = "cast"
	casts += 1
	w.on_cast(slot, cast_st, mult)


## A hit may break the read (chance by element, see READ.break_chance).
func on_hurt() -> void:
	if not reading:
		return
	var el: String = w.ch.el if Game.has_book() else "none"
	if randf() < float(GameData.READ.break_chance.get(el, 0.4)):
		reading = false
		_fizzle("broken")


func _fizzle(kind: String) -> void:
	w.player.mana = minf(Game.max_mana(), w.player.mana + paid * float(GameData.READ.fizzle_refund))
	last_result = kind
	fizzles += 1
	if kind == "fizzle":
		w.on_fizzle()
	fizzle_fx = 0.5
	recover_t = float(GameData.READ.recover)
	paid = 0.0


## Called when the book changes (ceremony) or a new world opens.
func reset() -> void:
	page = 0
	turn_target = -1
	reading = false
	recover_t = 0.0
