extends "res://scripts/dev/balance.gd"
## The new-player bot: `godot --headless --path . -- --firsthour`
##
## Plays the first hour the way a person who has never seen the game might: it only uses
## a control once it would plausibly have found it (by trying keys, or from a nudge),
## it misreads some wind-ups, it doesn't know about resting until something tells it,
## and it wanders outward as it gets braver. It logs everything the player would see
## (journal lines, interface parts appearing, nudges, levels written, the ceremony,
## margin notes) with a timestamp, then prints a minute-by-minute table.
## docs/FIRST_HOUR.md is written from these logs.
##
## Options: `--persona=careful|curious|bold` (default: all three), `--minutes=N` (default 60),
## `--seed=N` for a repeatable run.

const PERSONAS := {
	# found_attack: seconds near a monster before it tries Space/right mouse by itself
	# tries_keys:   presses number keys and Q/E out of curiosity (doesn't wait for a nudge)
	# dodge:        chance of reading a wind-up at first, and after it has dodged a few times
	# brave:        how fast it wanders outward (regions per written level, roughly)
	# flee_hp:      health share at which it backs off
	# reads:        seconds between opening the journal / book once it has them
	"careful": {"found_attack": 25.0, "tries_keys": false, "dodge": [0.3, 0.65], "brave": 0.7, "flee_hp": 0.5, "reads": 150.0},
	"curious": {"found_attack": 6.0, "tries_keys": true, "dodge": [0.4, 0.75], "brave": 1.0, "flee_hp": 0.4, "reads": 90.0},
	"bold": {"found_attack": 2.0, "tries_keys": false, "dodge": [0.15, 0.5], "brave": 1.6, "flee_hp": 0.25, "reads": 300.0},
}

var P: Dictionary
var wd
var clock := 0.0          # play time, including time spent in menus
var log_lines: Array = []
var minute_rows: Array = []
var seen := {}            # snapshot of what's been logged already
var knows := {}           # controls this player has found: attack, pages, rest, journal, book, map
var near_t := 0.0         # seconds spent with a monster near before finding attack
var decided := {}         # enemy id -> will it dodge this wind-up?
var dodges_done := 0
var waypoint := Vector2(0, 300)
var going_home := false
var ceremony_due := false
var next_read := 0.0
var stance_t := 0.0
var stance := 0
var stat := {}            # per-minute counters
var last_level := 1
var died := 0
var was_dead := false
var sites_seen := {}      # erasure sites this player has noticed (The Unwritten, Phase 2)


func run_first_hour() -> void:
	var minutes := 60.0
	var only := ""
	var sd := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="):
			minutes = float(a.substr(10))
		if a.begins_with("--persona="):
			only = a.substr(10)
		if a.begins_with("--seed="):
			sd = int(a.substr(7))
	for pname in PERSONAS:
		if only != "" and pname != only:
			continue
		if sd >= 0:
			seed(sd)
		await _play(pname, minutes * 60.0)
	print("\n=== done ===")


func _play(pname: String, total: float) -> void:
	P = PERSONAS[pname]
	print("\n=== First hour: %s player ===" % pname.to_upper())
	Game.ch = Game.new_character("Bot", "orphan")
	wd = await _new_world()
	wd.go_to_ceremony.connect(func(): ceremony_due = true)
	# The Unwritten, Phase 3: a newcomer tries whatever pot is there; the careful one leaves
	# their bare hands alone.
	wd.bot_pot = "carried"
	wd.bot_dip = "plain" if pname == "careful" else "carried"
	clock = 0.0
	log_lines.clear()
	minute_rows.clear()
	seen = {"journal": 0, "ui": {}, "nudged": {}, "margins": 0, "visited": {}, "hands": 0}
	knows = {}
	sites_seen = {}
	decided.clear()
	dodges_done = 0
	near_t = 0.0
	waypoint = Vector2(0, 300)
	going_home = false
	ceremony_due = false
	next_read = 0.0
	died = 0
	last_level = 1
	retreating = false
	_reset_stat()
	var minute := 1
	while clock < total:
		_frame()
		if ceremony_due:
			await _do_ceremony()
		if clock >= minute * 60.0:
			_end_minute(minute)
			minute += 1
	_print_report(pname)
	wd.queue_free()
	await get_tree().process_frame
	Game.delete_save()


func _reset_stat() -> void:
	stat = {"kills": 0, "casts": 0, "hurt": 0, "events": 0, "fight": 0.0, "walk": 0.0, "rest": 0.0, "hearth": 0.0, "menu": 0.0, "dead": 0.0}


# ---------------------------------------------------------------- One frame

func _frame() -> void:
	want = -1
	want_aim = null
	want_charge = 0.0
	wd.rest_held = false
	wd.rest_pressed = false
	var p = wd.player
	var hp0: float = p.hp
	var casts0: int = wd.casting.casts
	var alive0 := {}
	for e in wd.enemies:
		alive0[e] = true
	if p.dead_t > 0.0:
		p.steer = Vector2.ZERO
		stat.dead += DT
	elif Game.has_book():
		_think_with_book()
	else:
		_think_bare_new()
	_apply(wd)
	if not knows.has("attack"):
		wd.read_held = false
	wd._update(DT)
	clock += DT
	if p.hp < hp0 - 0.5:
		stat.hurt += 1
	stat.casts += wd.casting.casts - casts0
	for e in alive0:
		if is_instance_valid(e) and e.dead:
			stat.kills += 1
	if wd.resting:
		stat.rest += DT
	elif p.position.length() < GameData.TOWN_RADIUS:
		stat.hearth += DT
	elif _engaged():
		stat.fight += DT
	else:
		stat.walk += DT
	_watch()
	_menus()


func _engaged() -> bool:
	for e in wd.enemies:
		if not e.dead and e.aggro and e.position.distance_to(wd.player.position) < 300.0:
			return true
	return false


## Would this player see the wind-up coming this time? Decided once per wind-up.
func _sees_windup() -> bool:
	var any := false
	var skill: float = lerpf(float(P.dodge[0]), float(P.dodge[1]), clampf(dodges_done / 6.0, 0.0, 1.0))
	for e in wd.enemies:
		if e.dead or not e.winding_up():
			decided.erase(e.get_instance_id())
			continue
		var id: int = e.get_instance_id()
		if not decided.has(id):
			decided[id] = randf() < skill
		if decided[id]:
			any = true
	return any


## The comfort band: how far out this player is willing to wander right now.
func _band() -> Vector2:
	var lvl: float = float(wd.ch.level) * float(P.brave)
	if lvl < 3.0:
		return Vector2(220, 560)
	if lvl < 7.0:
		return Vector2(300, 1000)
	return Vector2(400, 1450)


func _wander(p) -> void:
	var b := _band()
	if p.position.distance_to(waypoint) < 40.0 or waypoint.length() > b.y + 50.0:
		var a := randf() * TAU
		waypoint = Vector2.from_angle(a) * randf_range(b.x, b.y)
		# The Unwritten, Phase 2: a bare patch it has seen draws it back, if it's brave enough
		# (curious and bold players at once, careful ones once they have a book).
		var drawn: bool = P.tries_keys or float(P.brave) > 1.0 or Game.has_book()
		for site in GameData.Lore.SITES:
			if drawn and sites_seen.has(site.id) and not wd.erasure.is_restored(site.id) \
					and site.p.length() < b.y + 50.0 and randf() < 0.5:
				waypoint = site.p
				break
	p.steer = (waypoint - p.position).normalized()


## The Unwritten, Phase 2: what a newcomer does around erasure sites. Notices them when it
## sees one; walks into the warm glow of a beaten site and, if it knows how, rests there.
func _site_habits(p) -> bool:
	for site in GameData.Lore.SITES:
		if p.position.distance_to(site.p) < 450.0:
			sites_seen[site.id] = true
	if not knows.has("rest") or _engaged():
		return false
	if not wd.erasure.restorable_at(p.position).is_empty() and wd.can_rest():
		p.steer = Vector2.ZERO
		wd.rest_held = true
		return true
	for site in GameData.Lore.SITES:
		if String(wd.erasure.state(site.id).state) == "cleared" and p.position.distance_to(site.p) < 320.0:
			p.steer = (site.p - p.position).normalized()
			return true
	return false


func _go_home(p) -> void:
	if p.position.length() < 60.0:
		p.steer = Vector2.ZERO
	else:
		p.steer = -p.position.normalized()


## Before the book: someone who has never played.
func _think_bare_new() -> void:
	var p = wd.player
	if not wd.resting and _site_habits(p):
		return
	var frac: float = p.hp / Game.max_hp()
	var pending: bool = Game.pending_level() > int(wd.ch.level)
	# Resting, once found.
	if wd.resting:
		p.steer = Vector2.ZERO
		wd.rest_held = true
		return
	if knows.has("rest"):
		var want_rest: bool = frac < 0.6 or (pending and randf() < 0.002)
		if wd.ceremony_ready() or going_home:
			going_home = true
			if p.position.length() > 80.0:
				_go_home(p)
				return
			p.steer = Vector2.ZERO
			wd.rest_held = true
			wd.rest_pressed = true
			return
		if want_rest and wd.can_rest():
			p.steer = Vector2.ZERO
			if wd.near_campfire():
				wd.rest_pressed = true
			wd.rest_held = true
			return
	# Hurt: back off toward the Hearth (that's all a new player knows to do).
	if frac < float(P.flee_hp) or retreating:
		retreating = frac < 0.9
		_go_home(p)
		if _sees_windup():
			_dodge(wd)
		return
	var near = wd.nearest(p.position, 300.0)
	if near == null or not near.aggro:
		_wander(p)
		return
	if not knows.has("attack"):
		near_t += DT
		if near_t > float(P.found_attack) or wd.ch.nudged.get("attack", false):
			_learn("attack", "tried Space / right mouse")
		if _sees_windup():
			_dodge(wd)
		else:
			# Backs away, toward home rather than further out.
			p.steer = ((p.position - near.position).normalized() - p.position.normalized()).normalized() * 0.5
		return
	if _sees_windup() and _dodge(wd):
		dodges_done += 1
		if knows.has("pages") and wd.casting.page_count() > 2 and randf() < 0.3:
			want = 2
		return
	# Stances: a curious player flips between them; others stick to the first.
	stance_t -= DT
	if knows.has("pages") and stance_t <= 0.0:
		stance_t = randf_range(8.0, 20.0)
		stance = randi() % wd.casting.page_count()
	var st: int = stance if knows.has("pages") else 0
	var d: float = p.position.distance_to(near.position)
	want_aim = near.position
	p.steer = (near.position - p.position).normalized() if d > 55.0 else Vector2.ZERO
	if d < 75.0 or (st == 2 and d < 140.0):
		want = st


## With a book: the balance bot's tactics, but clumsier and with only the controls it found.
func _think_with_book() -> void:
	var p = wd.player
	if not wd.resting and _site_habits(p):
		return
	if wd.resting:
		p.steer = Vector2.ZERO
		wd.rest_held = true
		return
	home = waypoint
	if p.position.distance_to(waypoint) < 40.0:
		_wander(p)
	var frac: float = p.hp / Game.max_hp()
	var pending: bool = Game.pending_level() > int(wd.ch.level)
	if pending and wd.can_rest() and not _engaged() and randf() < 0.01:
		p.steer = Vector2.ZERO
		wd.rest_held = true
		wd.rest_pressed = wd.near_campfire()
		return
	var seeing: bool = _sees_windup()
	_think_book(wd)
	if not seeing and wd.enemies.any(func(e): return not e.dead and e.winding_up() and e.position.distance_to(p.position) < 120.0):
		# Didn't see it coming: keeps doing what it was doing instead of stepping away.
		var near = wd.nearest(p.position, 300.0)
		if near != null and not wd.casting.reading:
			p.steer = Vector2.ZERO
	elif seeing:
		dodges_done += 1 if randf() < 0.01 else 0
	if not knows.has("pages") and want > 0:
		want = 0
	if frac < float(P.flee_hp) * 0.8 and not wd.can_rest():
		_go_home(p)


func _learn(what: String, how: String) -> void:
	if knows.has(what):
		return
	knows[what] = true
	_log("player", "found %s (%s)" % [what, how])


# ---------------------------------------------------------------- Menus the player opens

func _menus() -> void:
	var ch: Dictionary = wd.ch
	# Controls found by nudge or by trying keys.
	if ch.nudged.get("rest", false) or ch.get("rested", false):
		_learn("rest", "nudge" if ch.nudged.get("rest", false) else "rested by chance")
	if ch.nudged.get("page", false) or (P.tries_keys and clock > 90.0 and knows.has("attack")):
		_learn("pages", "nudge" if ch.nudged.get("page", false) else "pressed 1-3 / Q E")
	if ch.ui.get("journal", false) and (ch.nudged.get("journal", false) or P.tries_keys):
		_learn("journal", "J")
	if Game.has_book() and (ch.nudged.get("book", false) or P.tries_keys):
		_learn("book", "B")
	if ch.ui.get("map", false) and (P.tries_keys or ch.nudged.get("map", false)):
		_learn("map", "nudge" if ch.nudged.get("map", false) else "M")
	if clock < next_read or wd.player.dead_t > 0.0 or _engaged():
		return
	next_read = clock + float(P.reads) * randf_range(0.7, 1.3)
	if knows.has("journal"):
		ch.opened.journal = true
		_spend(12.0)
	if knows.has("book"):
		ch.opened.book = true
		if wd.chapter.try_awaken():
			_log("chapter", "the hidden chapter awakens (%s)" % ch.aspect.id)
		_spend(8.0)


## Time spent in a menu or screen while the world is paused.
func _spend(sec: float) -> void:
	clock += sec
	stat.menu += sec


# ---------------------------------------------------------------- The ceremony

func _do_ceremony() -> void:
	ceremony_due = false
	going_home = false
	_spend(35.0)   # reading the ceremony screen and opening the book
	Game.bind_book(Game.ch)
	Game.ch.ui.book = true
	if not Game.ch.journal_ids.has("book_received"):
		Game.ch.journal_ids["book_received"] = true
		Game.ch.journal.append(GameData.JOURNAL.book_received)
	_log("ceremony", "book: %s %s, hidden chapter %s" % [Game.ch.el, Game.ch.thick, Game.ch.aspect.id])
	wd.queue_free()
	await get_tree().process_frame
	wd = await _new_world()
	wd.go_to_ceremony.connect(func(): ceremony_due = true)
	wd.bot_pot = "carried"
	decided.clear()


# ---------------------------------------------------------------- Watching what the player sees

func _log(kind: String, text: String) -> void:
	var m := int(clock / 60.0)
	var s := int(clock) % 60
	log_lines.append("%02d:%02d  %-9s %s" % [m, s, kind, text])
	if kind != "player":
		stat.events += 1


func _watch() -> void:
	var ch: Dictionary = wd.ch
	var j: Array = ch.journal
	while seen.journal < j.size():
		_log("journal", "\"%s\"" % j[seen.journal])
		seen.journal += 1
	for k in GameData.UI_PARTS:
		if ch.ui.get(k, false) and not seen.ui.has(k):
			seen.ui[k] = true
			_log("unlock", k)
	for k in ch.nudged:
		if not seen.nudged.has(k):
			seen.nudged[k] = true
			_log("nudge", "%s (%s)" % [k, GameData.NUDGES[k].glyph])
	for line in wd.all_margins():
		if not seen.has("m|" + line):
			seen["m|" + line] = true
			_log("margin", "\"%s\"" % line)
	if int(ch.level) != last_level:
		_log("level", "rested and wrote Lv %d" % ch.level)
		last_level = int(ch.level)
		_spend(5.0 + (6.0 if Game.has_book() else 0.0))
	var dead: bool = wd.player.dead_t > 0.0
	if dead and not was_dead:
		died += 1
		_log("death", "fell (died %d times so far)" % died)
	was_dead = dead


func _end_minute(minute: int) -> void:
	var reg := 0
	var rd: float = wd.player.position.length()
	while rd >= GameData.REGIONS[reg].max:
		reg += 1
	var main := "walk"
	var best := 0.0
	for k in ["fight", "walk", "rest", "hearth", "menu", "dead"]:
		if float(stat[k]) > best:
			best = float(stat[k])
			main = k
	minute_rows.append([minute, GameData.REGIONS[reg].name, int(wd.ch.level), Game.pending_level(), stat.kills, stat.casts, stat.hurt, stat.events, main,
		roundi(stat.fight), roundi(stat.walk), roundi(stat.rest + stat.hearth)])
	_reset_stat()


func _print_report(pname: String) -> void:
	print("\n-- Timeline (%s) --" % pname)
	for l in log_lines:
		print(l)
	print("\n-- Minute by minute (%s) --" % pname)
	print("min | where            | Lv (pending) | kills casts hits | new | mostly  | fight walk safe (s)")
	var quiet := 0
	var quiet_runs: Array = []
	for r in minute_rows:
		print("%3d | %-16s | %2d (%2d)      | %5d %5d %4d | %3d | %-7s | %4d %4d %4d" % r)
		if int(r[7]) == 0:
			quiet += 1
		else:
			if quiet >= 3:
				quiet_runs.append("%d-%d" % [int(r[0]) - quiet, int(r[0]) - 1])
			quiet = 0
	if quiet >= 3:
		quiet_runs.append("%d-%d" % [int(minute_rows[-1][0]) - quiet + 1, int(minute_rows[-1][0])])
	print("Quiet stretches (3+ minutes with nothing new): %s" % (", ".join(quiet_runs) if not quiet_runs.is_empty() else "none"))
	print("Found: %s" % ", ".join(knows.keys()))
	print("Deaths: %d · final level %d (pending %d) · book: %s" % [died, wd.ch.level, Game.pending_level(), "%s %s" % [wd.ch.el, wd.ch.thick] if Game.has_book() else "none"])
	var paths: Array = []
	for sl in wd.ch.get("spells", []):
		paths.append("[%s]" % ", ".join(sl.get("branch", [])))
	print("Inks: vials %s · pages grew %s · hands dipped %s" % [str(wd.ch.get("vials", {})), " ".join(paths) if not paths.is_empty() else "-", str(wd.ch.hands.get("branch", {}))])
	print("Erasure sites written back: %d of %d · torn pages found: %d of %d (%s)" % [wd.erasure.restored_count(), GameData.Lore.SITES.size(),
		wd.ch.get("fragments", []).size(), GameData.Lore.FRAGMENTS.size(), ", ".join(wd.ch.get("fragments", []))])
