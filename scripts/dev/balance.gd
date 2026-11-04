extends Node
## Balance bot: `godot --headless --path . -- --balance`
##
## Part 1 (bare hands): plays the bare-hands phase with five scripted playstyles and
##   prints how fast each reaches the ceremony, how often it dies, and its book odds.
## Part 2 (books): plays every element and thickness in each of the 3 regions, casting
##   through the real read and page-turn rules, and prints how long each takes to earn
##   the same amount of XP there. Every book should be within ±20% of the region average.
## Part 3 (`--chapters`): how fast each hidden-chapter trigger progresses, to check the
##   chapters still unlock in about the same play time.
##
## Part 4 (`--only=firsthour`): the new-player bot (scripts/dev/first_hour.gd), a timeline of
##   what a newcomer sees in their first hour. docs/FIRST_HOUR.md is written from it.
##
## Part 5 (`--only=sites`, The Unwritten, Phase 2): every element (and bare hands in the
##   Fields) walks up to an erasure site, beats its guardian and escorts, and writes it back.
##   Prints how long that takes and how often the bot falls. Every book should be within ±20%.
##
## Part 6 (`--only=branches`, The Unwritten, Phase 3): every element and thickness with every
##   branch path its pages can grow (quick, heavy, stubborn, plain, and the pale), fully grown,
##   in the Knight's Reach; and bare hands with every dip path in the Fields. Prints how long
##   each takes to earn the same XP. Steps stack by multiplying, so the order inks were used in
##   doesn't change how a page plays: each combination is run once ("quick+heavy" covers
##   quick-then-heavy and heavy-then-quick). Every path should be within ±20% of its book's
##   average (and of the region average).
##
## Options: `--runs=N` runs per case (default 3), `--signals` shows raw playstyle signals,
## `--only=books` / `--only=bare` / `--only=sites` / `--only=chapters` / `--only=firsthour` /
## `--only=branches` runs one part. `--th=thin` tests one thickness (with --only=branches).

const World := preload("res://scripts/world/world.gd")
const DT := 1.0 / 30.0

const STYLES := {
	"brawler": "locks onto one enemy and jabs it down (Escalate)",
	"spreader": "jabs a different enemy each time (Chain)",
	"controller": "keeps enemies off with Shove, backs away (Redirect)",
	"skirmisher": "never stops moving, sidesteps through enemies (Move)",
	"anchor": "plants their feet and lets enemies come (Persist)",
	"mixed": "switches between all of the above every few seconds",
}

## The book test: level, where to stand, and how much XP to earn in each region.
const REGION_TESTS := [
	{"name": "Inkling Fields", "level": 5, "radius": 400.0, "xp": 150, "max_time": 900.0},
	{"name": "Blot Marsh", "level": 8, "radius": 850.0, "xp": 240, "max_time": 900.0},
	{"name": "Knight's Reach", "level": 11, "radius": 1280.0, "xp": 375, "max_time": 900.0},
]

var focus_target = null
var last_target = null
var orbit_dir := 1.0
var mixed_style := "brawler"
var mixed_t := 0.0
var want := -1             # the page/stance the bot wants to use this frame (-1 = none)
var want_aim = null
var want_charge := 0.0     # 0..1 how much to overcharge
var retreating := false
var home := Vector2.ZERO
var fight_t := 0.0
var fights: Array = []
var lull := 0.0
var only_el := ""          # `--el=fire` tests just one element (lets you run elements in parallel)
var only_th := ""          # `--th=thin` tests just one thickness (Part 6)


func run() -> void:
	var runs := 3
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--el="):
			only_el = a.substr(5)
		if a.begins_with("--th="):
			only_th = a.substr(5)
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "" or only == "bare":
		await _bare_part(runs)
	if only == "" or only == "books":
		await _book_part(runs)
	if only == "" or only == "sites":
		await _site_part(runs)
	if only == "branches":
		await _branch_part(runs)
	if only == "chapters" or "--chapters" in OS.get_cmdline_user_args():
		await _chapter_part()
	if only == "firsthour":
		# Part 4 (The Unwritten, Phase 1): the new-player bot, same as `-- --firsthour`.
		var fh = load("res://scripts/dev/first_hour.gd").new()
		add_child(fh)
		await fh.run_first_hour()
		fh.queue_free()
	print("\n=== done ===")


# ================================================================ Part 1: bare hands

func _bare_part(runs: int) -> void:
	print("\n=== Bare hands: %d runs per style, ceremony at Lv %d ===" % [runs, GameData.CEREMONY_LEVEL])
	for style in STYLES:
		var times: Array = []
		var deaths := 0
		var odds_sum := {}
		var thick_sum := {}
		var hits := {}
		var sig_sum := {}
		for r in runs:
			var res: Dictionary = await _play_bare(style)
			times.append(res.time)
			deaths += res.deaths
			for k in res.odds:
				odds_sum[k] = odds_sum.get(k, 0.0) + res.odds[k] / runs
			for k in res.thick:
				thick_sum[k] = thick_sum.get(k, 0.0) + res.thick[k] / runs
			for k in res.signals:
				sig_sum[k] = sig_sum.get(k, 0.0) + float(res.signals[k]) / runs
			var top: String = res.top
			hits[top] = hits.get(top, 0) + 1
		times.sort()
		var avg := 0.0
		for t in times:
			avg += t / times.size()
		print("\n%s: %s" % [style.to_upper(), STYLES[style]])
		print("  time to Lv %d: avg %ds (fastest %ds, slowest %ds) · deaths %.1f per run" % [
			GameData.CEREMONY_LEVEL, roundi(avg), roundi(times[0]), roundi(times[-1]), float(deaths) / runs])
		print("  book element odds: %s" % _fmt(odds_sum))
		print("  book thickness odds: %s" % _fmt(thick_sum))
		print("  top leaning per run: %s" % str(hits))
		if "--signals" in OS.get_cmdline_user_args():
			var bits: Array = []
			for k in GameData.SIGNALS:
				bits.append("%s %d" % [k, roundi(sig_sum.get(k, 0.0))])
			print("  avg signals: %s" % ", ".join(bits))


func _fmt(d: Dictionary) -> String:
	var bits: Array = []
	for k in d:
		bits.append("%s %d%%" % [k, roundi(100.0 * d[k])])
	return ", ".join(bits)


func _new_world():
	var w = World.new()
	add_child(w)
	await get_tree().process_frame
	w.set_process(false)
	w.auto_rest_ui = true
	return w


func _play_bare(style: String) -> Dictionary:
	Game.ch = Game.new_character("Bot", "orphan")
	var w = await _new_world()
	w.player.position = Vector2(0, 200)
	focus_target = null
	last_target = null
	retreating = false
	var t := 0.0
	var deaths := 0
	var was_dead := false
	var max_time := 1800.0
	while t < max_time and Game.pending_level() < GameData.CEREMONY_LEVEL:
		want = -1
		want_aim = null
		want_charge = 0.0
		w.rest_held = false
		_think_bare(w, style)
		_apply(w)
		w._update(DT)
		t += DT
		var dead: bool = w.player.dead_t > 0.0
		if dead and not was_dead:
			deaths += 1
		was_dead = dead
	var res := {
		"time": t, "deaths": deaths, "signals": Game.ch.get("signals", {}).duplicate(), "top": Game.top_lean(),
		"odds": _norm(Game.element_weights()),
		"thick": _norm(Game.thickness_weights()),
	}
	w.queue_free()
	await get_tree().process_frame
	Game.delete_save()
	return res


func _norm(d: Dictionary) -> Dictionary:
	var total := 0.0
	for k in d:
		total += float(d[k])
	var out := {}
	for k in d:
		out[k] = float(d[k]) / total
	return out


## Turns "I want to use page i at this spot" into key presses, through the real rules:
## turn the page first, hold the read key for the read time (plus any overcharge), release.
func _apply(w) -> void:
	var cs = w.casting
	if want_aim != null:
		w.bot_aim = want_aim
	if cs.reading:
		var need: float = float(cs.st.read) + float(cs.st.get("over", 0.0)) * want_charge
		w.read_held = cs.t < need
		return
	if want < 0:
		w.read_held = false
		return
	if cs.page != want or cs.turning():
		cs.turn_to(want)
		w.read_held = false
		return
	# Let go for a frame between casts so the next one starts fresh.
	w.read_held = not w.read_held if cs.recover_t <= 0.0 else false


## When hurt or out of ink: rest if it's safe, otherwise head for the Hearth.
func _retreat(w) -> void:
	var p = w.player
	if w.resting or (w.can_rest() and not w.casting.reading):
		p.steer = Vector2.ZERO
		w.rest_held = true
	else:
		p.steer = -p.position.normalized() if p.position.length() > 60.0 else Vector2.ZERO


## Hurt or out of ink, like a sensible player would notice.
func _should_retreat(w) -> bool:
	var p = w.player
	var hp_f: float = p.hp / Game.max_hp()
	var ink_f: float = p.mana / Game.max_mana()
	if retreating:
		if hp_f > 0.95 and ink_f > 0.9:
			retreating = false
	elif hp_f < 0.35 or (ink_f < 0.08 and hp_f < 0.6):
		retreating = true
	return retreating


func _think_bare(w, style: String) -> void:
	var p = w.player
	if p.dead_t > 0.0:
		p.steer = Vector2.ZERO
		return
	if _should_retreat(w):
		_retreat(w)
		if style == "skirmisher" and not w.resting:
			want = 2
		return
	var near = w.nearest(p.position, 2000.0)
	if near == null:
		p.steer = (Vector2(0, 400) - p.position).normalized()
		return
	var to: Vector2 = near.position - p.position
	var d := to.length()
	if style == "mixed":
		mixed_t -= DT
		if mixed_t <= 0.0:
			mixed_t = randf_range(3.0, 7.0)
			mixed_style = ["brawler", "spreader", "controller", "skirmisher", "anchor"].pick_random()
		style = mixed_style
	if style != "anchor" and _dodge(w):   # anchors stand their ground and take the hit
		return
	want_aim = near.position
	match style:
		"brawler":
			if focus_target == null or not is_instance_valid(focus_target) or focus_target.dead:
				focus_target = near
			var ft: Vector2 = focus_target.position - p.position
			p.steer = ft.normalized() if ft.length() > 55.0 else Vector2.ZERO
			want_aim = focus_target.position
			if ft.length() < 70.0:
				want = 0
		"spreader":
			# Keep the same pick for the whole read; switch to another enemy for the next one.
			if not w.casting.reading or focus_target == null or not is_instance_valid(focus_target) or focus_target.dead:
				var pick = near
				if last_target != null and is_instance_valid(last_target) and pick == last_target:
					var other = w.nearest(p.position, 160.0, [last_target])
					if other != null:
						pick = other
				focus_target = pick
			var pt: Vector2 = focus_target.position - p.position
			p.steer = pt.normalized() if pt.length() > 55.0 else Vector2.ZERO
			want_aim = focus_target.position
			if pt.length() < 70.0:
				want = 0
			if w.casting.reading:
				last_target = focus_target
		"controller":
			if d < 60.0:
				p.steer = -to.normalized()
			elif d > 90.0:
				p.steer = to.normalized()
			else:
				p.steer = Vector2.ZERO
			if d < 80.0:
				want = 1 if p.mana >= 4.0 else 0
		"skirmisher":
			var side := Vector2(-to.y, to.x).normalized() * orbit_dir
			p.steer = (side + to.normalized() * (0.6 if d > 60.0 else -0.4)).normalized()
			if d < 140.0 and p.mana >= 3.0 and randf() < 0.03:
				want = 2
				orbit_dir = -orbit_dir
			elif d < 70.0:
				want = 0
		"anchor":
			if d > 130.0:
				p.steer = to.normalized()
			else:
				p.steer = Vector2.ZERO
				if d < 70.0:
					want = 0


## Steps out of the way of a monster that is winding up near you. Returns true if dodging.
func _dodge(w) -> bool:
	var p = w.player
	for e in w.enemies:
		if e.dead or not e.winding_up():
			continue
		var to: Vector2 = p.position - e.position
		var gap: float = to.length() - e.r - p.r
		var f: Dictionary = e.f
		match e.behavior:
			"charge":
				var lane: float = absf(e.lunge.cross(to))
				if gap < float(f.charge_speed) * float(f.charge_time) + 20.0 and lane < e.r + p.r + 12.0 and e.lunge.dot(to) > 0.0:
					p.steer = Vector2(-e.lunge.y, e.lunge.x) * (1.0 if e.lunge.cross(to) >= 0.0 else -1.0)
					return true
			_:
				if gap < float(f.reach) + 22.0:
					p.steer = to.normalized()
					return true
	return false


# ================================================================ Part 2: books

func _book_part(runs: int) -> void:
	print("\n=== Books: seconds to earn the same XP in each region (%d runs each, Mira along) ===" % runs)
	print("Read and page-turn rules apply. ! marks a book more than 20%% off the region average.\n")
	var rows := {}
	var fight_lens: Array = [[], [], []]
	for el in Game.ELS:
		if only_el != "" and el != only_el:
			continue
		for th in GameData.THICKNESS:
			var key: String = "%s %s" % [el, th]
			rows[key] = []
			for ri in REGION_TESTS.size():
				var tsum := 0.0
				var dsum := 0.0
				var csum := 0.0
				var osum := 0.0
				for r in runs:
					var res: Dictionary = await _play_book(el, th, ri)
					tsum += res.time / runs
					dsum += float(res.deaths) / runs
					csum += float(res.casts) / runs
					osum += float(res.overcasts) / runs
					fight_lens[ri].append_array(res.fights)
				rows[key].append({"time": tsum, "deaths": dsum, "casts": csum, "overcasts": osum})
	var means: Array = []
	for ri in REGION_TESTS.size():
		var m := 0.0
		for key in rows:
			m += rows[key][ri].time / rows.size()
		means.append(m)
	var head := "%-18s" % "book"
	for rt in REGION_TESTS:
		head += "| %-26s" % ("%s (Lv %d)" % [rt.name, rt.level])
	print(head)
	var worst := 0.0
	for key in rows:
		var line := "%-18s" % key
		for ri in REGION_TESTS.size():
			var c: Dictionary = rows[key][ri]
			var rel: float = c.time / means[ri] - 1.0
			worst = maxf(worst, absf(rel))
			line += "| %4ds %+4d%%%s deaths %.1f  " % [roundi(c.time), roundi(rel * 100.0), "!" if absf(rel) > 0.2 else " ", c.deaths]
		print(line)
	var avg := "%-18s" % "average"
	for ri in REGION_TESTS.size():
		avg += "| %4ds                      " % roundi(means[ri])
	print(avg)
	print("\nWidest gap from the region average: %d%% (goal: within 20%%)" % roundi(worst * 100.0))
	for ri in REGION_TESTS.size():
		var fl: Array = fight_lens[ri]
		fl.sort()
		if fl.is_empty():
			continue
		var s := 0.0
		for x in fl:
			s += x / fl.size()
		print("Fight length in %s: median %ds, average %ds (%d fights)" % [REGION_TESTS[ri].name, roundi(fl[int(fl.size() / 2.0)]), roundi(s), fl.size()])


## One run: a character with this book at the region's level, fighting there
## until they earn the region's XP target.
func _play_book(el: String, th: String, ri: int, path: Array = []) -> Dictionary:
	var rt: Dictionary = REGION_TESTS[ri]
	var c := _book_bot(el, th, int(rt.level), path)
	Game.ch = c
	var w = await _new_world()
	home = Vector2.from_angle(randf() * TAU) * float(rt.radius)
	w.player.position = home
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	for k in int(GameData.MONSTERS.initial):
		w.spawn(false)
	retreating = false
	fights = []
	fight_t = 0.0
	var t := 0.0
	var deaths := 0
	var overcasts := 0
	var was_dead := false
	var xp0: int = _total_xp(c)
	var cs = w.casting
	var target: int = branch_xp if branch_xp > 0 else int(rt.xp)
	while t < float(rt.max_time) * (1.6 if branch_xp > 0 else 1.0) and _total_xp(c) - xp0 < target:
		want = -1
		want_aim = null
		want_charge = 0.0
		w.rest_held = false
		var strain_before: float = cs.strain_t
		_think_book(w)
		_apply(w)
		w._update(DT)
		if cs.strain_t > strain_before + 0.5:
			overcasts += 1
		_track_fight(w)
		t += DT
		var dead: bool = w.player.dead_t > 0.0
		if dead and not was_dead:
			deaths += 1
		was_dead = dead
	var res := {"time": t, "deaths": deaths, "casts": cs.casts, "overcasts": overcasts, "fights": fights.duplicate()}
	w.queue_free()
	await get_tree().process_frame
	Game.delete_save()
	return res


## A character with this book at this level, with all the writing ink spent evenly.
## `path` (Part 6) is the ink each evolution took; otherwise every step is plain. The pale
## goes on the first page only, the others take plain ink in its place.
func _book_bot(el: String, th: String, level: int, path: Array = []) -> Dictionary:
	var c := Game.new_character("Bot", "orphan")
	c.el = el
	c.thick = th
	c.level = level
	var n: int = GameData.THICKNESS[th].slots
	var idx: Array = [0] if n == 1 else ([0, 1, 2] if n == 3 else [0, [1, 2].pick_random()])
	c.spells = []
	for i in idx:
		c.spells.append({"i": i, "lvl": 1})
	c.aspect = {"id": "stillness", "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 99999, "streak": 99}
	# Spend all the writing ink a player would have by now, evenly.
	var ink: int = GameData.INK_PER_LEVEL * (level - 1)
	var mx: int = GameData.THICKNESS[th].max_level
	while ink > 0:
		var low = null
		for s in c.spells:
			if s.lvl < mx and (low == null or s.lvl < low.lvl):
				low = s
		if low == null:
			break
		low.lvl += 1
		ink -= 1
	for k in c.spells.size():
		var sl: Dictionary = c.spells[k]
		sl.inks = []
		for j in int(sl.lvl) - 1:
			sl.inks.append("plain")
		sl.branch = []
		for j in int(int(sl.lvl) / 4.0):
			var ink_j: String = String(path[j]) if j < path.size() else "plain"
			if ink_j == "pale" and k > 0:
				ink_j = "plain"
			sl.branch.append(ink_j)
	c.pale_used = "pale" in path
	return c


## XP including levels already gained, so leveling up mid-run doesn't reset the count.
func _total_xp(c: Dictionary) -> int:
	var total := int(c.xp)
	for l in range(1, int(c.level)):
		total += Game.xp_next(l)
	return total


## A "fight" lasts while a hunting monster is within 300 px of you, and only ends
## after 5 s without one (so a short step back doesn't split one fight into two).
func _track_fight(w) -> void:
	var p = w.player
	var engaged := false
	if p.dead_t <= 0.0:
		for e in w.enemies:
			if not e.dead and e.aggro and e.position.distance_to(p.position) < 300.0:
				engaged = true
				break
	if engaged:
		fight_t += DT + lull
		lull = 0.0
	elif fight_t > 0.0:
		lull += DT
		if lull > 5.0:
			if fight_t > 3.0:
				fights.append(fight_t)
			fight_t = 0.0
			lull = 0.0


## The book bot: picks the page that does the most damage per second of reading
## (counting page turns), keeps a sensible distance, dodges wind-ups, overcharges
## when nothing is close, and walks home when hurt or dry.
func _think_book(w) -> void:
	var p = w.player
	var cs = w.casting
	if p.dead_t > 0.0:
		p.steer = Vector2.ZERO
		return
	if _should_retreat(w):
		_retreat(w)
		return
	var near = w.nearest(p.position, 700.0)
	if near == null:
		var to_home: Vector2 = home - p.position
		p.steer = to_home.normalized() if to_home.length() > 40.0 else Vector2.ZERO
		return
	var dodging := _dodge(w)
	var d: float = p.position.distance_to(near.position)
	# Score every page: expected damage / (read + turn time).
	var best: int = cs.page
	var best_v := -1.0
	var best_aim: Vector2 = near.position
	for i in w.ch.spells.size():
		var st: Dictionary = cs.stats_for(i)
		var turns: int = absi(i - (cs.turn_target if cs.turning() else cs.page))
		var cost_t: float = float(st.read) + float(GameData.READ.recover) + turns * float(GameData.PAGES.turn_time[w.ch.thick])
		var ev := _expected(w, st, near)
		var v: float = ev[0] / cost_t
		if v > best_v:
			best_v = v
			best = i
			best_aim = ev[1]
	var st_b: Dictionary = cs.stats_for(best)
	var gap: float = d - near.r - p.r
	if not dodging:
		var pref := 170.0
		match st_b.kind:
			"nova":
				pref = float(st_b.radius) * 0.55
			"dash":
				pref = float(st_b.dash_len) * 0.6
			"zone":
				pref = minf(150.0, float(st_b.range) * 0.7)
		if cs.reading:
			p.steer = Vector2.ZERO
		elif d > pref + 25.0:
			p.steer = (near.position - p.position).normalized()
		elif d < pref - 35.0 and st_b.kind != "nova":
			p.steer = (p.position - near.position).normalized()
		else:
			p.steer = Vector2.ZERO
	if best_v <= 0.0:
		return
	var affordable: bool = p.mana >= float(st_b.mana) or p.hp / Game.max_hp() > 0.7
	if not affordable:
		return
	want = best
	want_aim = best_aim
	want_charge = 1.0 if gap > 140.0 and not dodging else 0.0


## [expected damage, aim point] for casting `st` now, aimed at or around `near`.
func _expected(w, st: Dictionary, near) -> Array:
	var p = w.player
	var d: float = p.position.distance_to(near.position)
	var tier: int = int(st.get("tier", 0))
	var dmg: float = float(st.dmg)
	match st.kind:
		"bolt":
			var reach: float = float(st.speed) * float(st.get("life", 1.1))
			if d > reach * 0.9:
				return [0.0, near.position]
			var n := maxi(1, (5 if tier >= 2 else (3 if tier >= 1 else 1)) + int(st.get("count", 0)))
			var hits_n: float = 1.0 + 0.35 * (n - 1) * (1.0 if d < 120.0 else 0.4)
			hits_n *= 1.0 + 0.3 * int(st.get("pierce", 0)) * (1.0 if _count_near(w, near.position, 120.0) > 1 else 0.0)
			if bool(st.get("returns", false)):
				hits_n *= 1.5
			return [dmg * hits_n, near.position]
		"chain":
			if d > float(st.range):
				return [0.0, near.position]
			var cl := _count_near(w, near.position, 170.0)
			return [dmg * (1.0 + 0.8 * minf(cl - 1, int(st.jumps) + 2 * tier)) * (1.0 + float(st.get("linger", 0.0))), near.position]
		"nova":
			var r: float = float(st.radius) * (1.0 + 0.25 * tier)
			var cnt := _count_near(w, p.position, r * 0.9)
			if cnt == 0:
				return [0.0, near.position]
			return [dmg * cnt * ((2.0 if tier >= 3 else 1.0) + float(st.get("echo", 0.0))), near.position]
		"zone":
			if d > float(st.range) + 40.0:
				return [0.0, near.position]
			for z in w.zones:
				if z.src == "player" and z.p.distance_to(near.position) < z.r:
					return [0.0, near.position]
			var r: float = float(st.radius) * (1.0 + 0.15 * tier)
			var cnt := _count_near(w, near.position, r)
			if bool(st.get("follows", false)):
				# A pale zone sits on you: worth it when they're close.
				var cnt_f := _count_near(w, p.position, float(st.radius) * (1.0 + 0.15 * tier))
				return [dmg * cnt_f * float(st.dur) * (1.0 + 0.3 * tier) / float(st.get("tick", 0.5)) * 0.45, p.position]
			var ticks: float = float(st.dur) * (1.0 + 0.3 * tier) / float(st.get("tick", 0.5))
			return [dmg * cnt * ticks * 0.45, near.position]
		"dash":
			if d > float(st.dash_len):
				return [0.0, near.position]
			return [dmg * _count_near(w, near.position, 50.0), near.position + (near.position - p.position).normalized() * 30.0]
	return [0.0, near.position]


func _count_near(w, at: Vector2, r: float) -> int:
	var n := 0
	for e in w.enemies:
		if not e.dead and e.position.distance_to(at) < r + e.r:
			n += 1
	return n


# ================================================================ Part 3: hidden chapters

## How many trigger events per minute each hidden chapter gets with the book bot in
## Inkling Fields and Blot Marsh. Compare with the numbers in docs/DESIGN_NOTES.md.
func _chapter_part() -> void:
	print("\n=== Hidden chapter trigger rates (events per minute, book bot, 5 min each) ===")
	for el in Game.ELS:
		for th in ["thin", "thick"]:
			var res := await _play_rates(el, th)
			print("%-16s %s" % ["%s %s" % [el, th], res])


func _play_rates(el: String, th: String) -> Dictionary:
	var c := Game.new_character("Bot", "orphan")
	c.el = el
	c.thick = th
	c.level = 6
	var n: int = GameData.THICKNESS[th].slots
	c.spells = []
	for i in n:
		c.spells.append({"i": i, "lvl": 3 if n > 1 else 6})
	c.aspect = {"id": "stillness", "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 99999, "streak": 99}
	Game.ch = c
	var w = await _new_world()
	home = Vector2(0, 400)
	w.player.position = home
	retreating = false
	var cs = w.casting
	var t := 0.0
	var T := 300.0
	var still_casts := 0
	var streak_kills := 0
	var echo_kills := 0
	var recovers := 0
	var kills := 0
	var low := false
	var hunger_streak: int = int(GameData.CHAPTER_TUNING.hunger_streak)
	while t < T:
		want = -1
		want_aim = null
		want_charge = 0.0
		w.rest_held = false
		_think_book(w)
		_apply(w)
		var was_still: bool = w.player.still > 0.4
		var casts_before: int = cs.casts
		var pre := {}
		for e in w.enemies:
			pre[e] = [e.ally_hit > 0.0, w.streak]
		w._update(DT)
		if cs.casts > casts_before and was_still:
			still_casts += 1
		for e in pre:
			if is_instance_valid(e) and e.dead:
				kills += 1
				if pre[e][1] >= hunger_streak:
					streak_kills += 1
				if pre[e][0]:
					echo_kills += 1
		var f: float = w.player.hp / Game.max_hp()
		if f < 0.25:
			low = true
		elif low and f > 0.6:
			low = false
			recovers += 1
		t += DT
	w.queue_free()
	await get_tree().process_frame
	Game.delete_save()
	var m := T / 60.0
	return {"casts": snappedf(cs.casts / m, 0.1), "still_casts": snappedf(still_casts / m, 0.1),
		"kills": snappedf(kills / m, 0.1), "streak_kills": snappedf(streak_kills / m, 0.1),
		"echo_kills": snappedf(echo_kills / m, 0.1), "recovers": snappedf(recovers / m, 0.01)}


# ================================================================ Part 5: erasure sites

## The level a player would usually be at when reaching each region's sites.
const SITE_TESTS := {1: 5, 2: 8, 3: 11}


func _site_part(runs: int) -> void:
	print("\n=== Erasure sites: seconds to beat the guardian and write the site back (%d runs each, medium books) ===" % runs)
	print("fight = from the guardian waking to its fall; all = until the site is written back.")
	print("! marks a book whose fight is more than 20%% off the region average. Bare hands fight the Fields at Lv 4.\n")
	var rows := {}
	var who: Array = []
	for el in Game.ELS:
		if only_el == "" or el == only_el:
			who.append(el)
	if only_el == "" or only_el == "bare":
		who.append("bare")
	for el in who:
		rows[el] = {}
		for reg in SITE_TESTS:
			if el == "bare" and reg != 1:
				continue
			var tsum := 0.0
			var fsum := 0.0
			var dsum := 0.0
			var wins := 0
			for r in runs:
				var res: Dictionary = await _play_site(el, reg)
				fsum += (float(res.cleared) - float(res.woke) if res.cleared >= 0.0 else 900.0) / runs
				if "--verbose" in OS.get_cmdline_user_args():
					print("  %s in %s: %ds, deaths %d, %s, guardian woke at %ds, fell at %ds" % [el, GameData.REGIONS[reg].name, roundi(res.time), res.deaths, "written back" if res.done else "not done", roundi(res.woke), roundi(res.cleared)])
				tsum += res.time / runs
				dsum += float(res.deaths) / runs
				wins += 1 if res.done else 0
			rows[el][reg] = {"time": tsum, "fight": fsum, "deaths": dsum, "wins": wins}
	var means := {}
	for reg in SITE_TESTS:
		var m := 0.0
		var n := 0
		for el in rows:
			if el != "bare" and rows[el].has(reg):
				m += rows[el][reg].fight
				n += 1
		means[reg] = m / maxf(1.0, n)
	var head := "%-11s" % "book"
	for reg in SITE_TESTS:
		head += "| %-36s" % ("%s (Lv %d)" % [GameData.REGIONS[reg].name, SITE_TESTS[reg]])
	print(head)
	var worst := 0.0
	for el in rows:
		var line := "%-11s" % el
		for reg in SITE_TESTS:
			if not rows[el].has(reg):
				line += "| %-36s" % ""
				continue
			var c: Dictionary = rows[el][reg]
			var rel: float = c.fight / maxf(1.0, float(means[reg])) - 1.0
			var books_here: int = rows.keys().filter(func(k): return k != "bare" and rows[k].has(reg)).size()
			if el != "bare":
				worst = maxf(worst, absf(rel))
			var rel_s: String = ("%+4d%%" % roundi(rel * 100.0)) if books_here > 1 else "     "   # one book alone (--el=) has nothing to compare with
			line += "| fight %3ds %s%s all %4ds done %d/%d " % [roundi(c.fight), rel_s, "!" if absf(rel) > 0.2 and el != "bare" and books_here > 1 else " ", roundi(c.time), c.wins, runs]
		print(line)
	var avg := "%-11s" % "average"
	for reg in SITE_TESTS:
		avg += "| fight %3ds                          " % roundi(float(means[reg]))
	print(avg)
	print("\nWidest fight-length gap from the region average (books): %d%% (goal: within 20%%)" % roundi(worst * 100.0))


## One run: walk to the region's first site, wake its guardian, beat it, rest at the centre.
func _play_site(el: String, reg: int) -> Dictionary:
	var site: Dictionary = {}
	for s in GameData.Lore.SITES:
		if int(s.region) == reg:
			site = s
			break
	if el == "bare":
		var c := Game.new_character("Bot", "orphan")
		c.level = 4
		Game.ch = c
	else:
		Game.ch = _book_bot(el, "medium", int(SITE_TESTS[reg]))
	var w = await _new_world()
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	home = site.p
	var start: Vector2 = site.p + (Vector2.ZERO - site.p).normalized() * (float(site.r) + 380.0)
	w.player.position = start
	retreating = false
	focus_target = null
	last_target = null
	var t := 0.0
	var deaths := 0
	var was_dead := false
	var done := false
	var er = w.erasure
	var woke := -1.0
	var cleared := -1.0
	while t < 900.0:
		want = -1
		want_aim = null
		want_charge = 0.0
		w.rest_held = false
		var st: String = String(er.state(site.id).state)
		if woke < 0.0 and er.guardian_alive(site.id):
			woke = t
		if cleared < 0.0 and st != "erased":
			cleared = t
		if st == "restored":
			done = true
			break
		if st == "cleared" and w.nearest(w.player.position, 400.0) == null:
			# Walk to the centre and hold R there.
			var to_c: Vector2 = site.p - w.player.position
			if to_c.length() > 12.0 and not w.resting:
				w.player.steer = to_c.normalized()
			else:
				w.player.steer = Vector2.ZERO
				w.rest_held = true
		elif st == "erased" and not er.guardian_alive(site.id) and not retreating and w.player.dead_t <= 0.0:
			w.player.steer = (site.p - w.player.position).normalized()   # head for the site
		elif st == "erased" and not retreating and w.player.dead_t <= 0.0 and w.nearest(w.player.position, 160.0) == null \
				and er.guardians[site.id].position.distance_to(w.player.position) > 320.0:
			# A player after the site goes back for its guardian rather than chasing strays.
			w.player.steer = (er.guardians[site.id].position - w.player.position).normalized()
		elif el == "bare":
			_think_bare(w, "mixed")
		else:
			_think_book(w)
		_apply(w)
		w._update(DT)
		t += DT
		if "--trace" in OS.get_cmdline_user_args() and fmod(t, 20.0) < DT:
			var g = er.guardians.get(site.id)
			var gs := "none"
			if g != null and is_instance_valid(g):
				gs = "hp %d/%d at %d from you, %d from site, aggro %s, state %s" % [g.hp, g.max_hp, g.position.distance_to(w.player.position), g.position.distance_to(site.p), g.aggro, g.state]
			print("    t %ds: you %s hp %d ink %d retreat %s resting %s · guardian %s · monsters %d" % [t, w.player.position.round(), w.player.hp, w.player.mana, retreating, w.resting, gs, w.enemies.size()])
		var dead: bool = w.player.dead_t > 0.0
		if dead and not was_dead:
			deaths += 1
		was_dead = dead
	w.queue_free()
	await get_tree().process_frame
	Game.delete_save()
	return {"time": t, "deaths": deaths, "done": done, "woke": woke, "cleared": cleared}


# ================================================================ Part 6: branch paths

const BRANCH_XP := 1.5     # the branch test earns half as much XP again as the book test, for steadier numbers
var branch_xp := 0         # set while Part 6 runs (0 = use the region's own XP target)

## Every combination of `n` steps from `inks` (order doesn't matter), as arrays.
func _combos(inks: Array, n: int, from := 0) -> Array:
	if n == 0:
		return [[]]
	var out: Array = []
	for k in range(from, inks.size()):
		for rest in _combos(inks, n - 1, k):
			out.append([inks[k]] + rest)
	return out


## Every path a page of this thickness can grow: all combinations of plain and the three
## monster inks, and the same with one step taken by the pale.
func _paths(steps: int) -> Array:
	var base := ["plain", "quick", "heavy", "stubborn"]
	var out: Array = _combos(base, steps)
	for rest in _combos(base, steps - 1):
		out.append(["pale"] + rest)
	return out


func _path_name(path: Array) -> String:
	var bits: Array = []
	for k in path:
		bits.append(String(k))
	return "+".join(bits)


func _branch_part(runs: int) -> void:
	var rt: Dictionary = REGION_TESTS[2].duplicate()
	rt.xp = roundi(float(rt.xp) * BRANCH_XP)
	branch_xp = int(rt.xp)
	print("\n=== Branch paths: seconds to earn %d XP in %s at Lv %d, every page fully grown (%d runs each) ===" % [int(rt.xp), rt.name, int(rt.level), runs])
	print("A path is the inks its evolutions took. The pale goes on the first page only (one per book).")
	print("vs book = against that book's own average over all its paths; ! marks more than 20% off.\n")
	var all_rows: Array = []
	var books: Dictionary = {}
	for el in Game.ELS:
		if only_el != "" and el != only_el:
			continue
		for th in GameData.THICKNESS:
			if only_th != "" and th != only_th:
				continue
			var steps := int(int(GameData.THICKNESS[th].max_level) / 4.0)
			var key := "%s %s" % [el, th]
			books[key] = []
			for path in _paths(steps):
				var tsum := 0.0
				var dsum := 0.0
				for r in runs:
					seed(1000 + r * 7919 + path.size())   # the same dice for every path's run r
					var res: Dictionary = await _play_book(el, th, 2, path)
					tsum += res.time / runs
					dsum += float(res.deaths) / runs
				var row := {"book": key, "path": _path_name(path), "time": tsum, "deaths": dsum}
				books[key].append(row)
				all_rows.append(row)
			var bm := 0.0
			for row in books[key]:
				bm += float(row.time) / books[key].size()
			for row in books[key]:
				row.rel_book = float(row.time) / bm - 1.0
			var line := "%-17s avg %4ds |" % [key, roundi(bm)]
			for row in books[key]:
				line += " %s %d%+d%%%s" % [row.path, roundi(row.time), roundi(100.0 * row.rel_book), "!" if absf(row.rel_book) > 0.2 else ""]
			print(line)
	var mean := 0.0
	for row in all_rows:
		mean += float(row.time) / maxf(1.0, all_rows.size())
	var worst_book := 0.0
	var worst_all := 0.0
	var off: Array = []
	for row in all_rows:
		var rel_all: float = float(row.time) / mean - 1.0
		worst_book = maxf(worst_book, absf(float(row.rel_book)))
		worst_all = maxf(worst_all, absf(rel_all))
		if absf(float(row.rel_book)) > 0.2:
			off.append("%s %s %+d%%" % [row.book, row.path, roundi(100.0 * float(row.rel_book))])
	print("\nRegion average %ds over %d paths." % [roundi(mean), all_rows.size()])
	print("Widest gap from its own book's average: %d%% · from the region average: %d%% (goal: within 20%%)" % [roundi(worst_book * 100.0), roundi(worst_all * 100.0)])
	if not off.is_empty():
		print("More than 20%% off its book: %s" % ", ".join(off))
	if only_el == "" or only_el == "bare":
		await _bare_branch_part(runs * 3)   # the mixed bare-hands bot is noisier, so it gets more runs


## Bare hands: every dip path (the same on all three moves), Lv 4 in the Fields, the mixed style.
func _bare_branch_part(runs: int) -> void:
	print("\n--- Bare hands: seconds to earn 180 XP in the Fields at Lv 4, every move grown twice (%d runs each) ---" % runs)
	var rows: Array = []
	var m := 0.0
	for path in _combos(["plain", "quick", "heavy", "stubborn"], 2):
		var tsum := 0.0
		var dsum := 0.0
		for r in runs:
			seed(2000 + r * 7919)
			var res: Dictionary = await _play_bare_xp(path)
			tsum += res.time / runs
			dsum += float(res.deaths) / runs
		rows.append({"path": _path_name(path), "time": tsum, "deaths": dsum})
		m += tsum
	m /= rows.size()
	var worst := 0.0
	var line := "bare hands avg %ds |" % roundi(m)
	for row in rows:
		var rel: float = float(row.time) / m - 1.0
		worst = maxf(worst, absf(rel))
		line += " %s %d%+d%%%s" % [row.path, roundi(row.time), roundi(100.0 * rel), "!" if absf(rel) > 0.2 else ""]
	print(line)
	print("Widest gap from the bare-hands average: %d%% (goal: within 20%%)" % roundi(worst * 100.0))


func _play_bare_xp(path: Array) -> Dictionary:
	var c := Game.new_character("Bot", "orphan")
	c.level = 4
	for mv in ["jab", "shove", "sidestep"]:
		c.hands.tier[mv] = 2
		c.hands.branch[mv] = path.duplicate()
	Game.ch = c
	var w = await _new_world()
	home = Vector2(0, 380)
	w.player.position = home
	retreating = false
	focus_target = null
	last_target = null
	var t := 0.0
	var deaths := 0
	var was_dead := false
	var xp0: int = _total_xp(c)
	while t < 900.0 and _total_xp(c) - xp0 < 180:
		want = -1
		want_aim = null
		want_charge = 0.0
		w.rest_held = false
		_think_bare(w, "mixed")
		_apply(w)
		w._update(DT)
		t += DT
		var dead: bool = w.player.dead_t > 0.0
		if dead and not was_dead:
			deaths += 1
		was_dead = dead
	w.queue_free()
	await get_tree().process_frame
	Game.delete_save()
	return {"time": t, "deaths": deaths}
