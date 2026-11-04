extends RefCounted
## The Unwritten, Phase 2: erasure sites, guardians, restoring and slow re-erasure.
## Rules only; world.gd and site_fx.gd draw them. Numbers and text: scripts/data/lore_data.gd
## (GameData.Lore). The state lives in Game.world (its own save file), not in the character,
## so a host can own it later.
##
## A site is one of:
##   "erased"    pale and bare. A guardian waits; monsters gather; spells read slower and
##               ink comes back slower nearby; ground patches near it don't react.
##   "cleared"   the guardian is beaten, but the paper is still bare. Rest at the centre
##               (hold R) to write it back.
##   "restored"  written back: a campfire, a colour wash, details, fewer monsters, a lit
##               window in the Hearth. Its `pale` (0..1) rises slowly when its region is
##               left alone (REERASE); at 1 it is erased again and its guardian returns.

const EnemyScript := preload("res://scripts/world/enemy.gd")

var w
var ws: Dictionary            # Game.world
var guardians := {}           # site id -> the guardian monster while it is alive
var fx := {}                  # site id -> seconds since it was written back (for the drawing)
var _patch_t := 0.0


func _init(world) -> void:
	w = world
	if Game.world.is_empty():
		Game.world = Game.new_world()
	ws = Game.world


static func site(id: String) -> Dictionary:
	for s in GameData.Lore.SITES:
		if s.id == id:
			return s
	return {}


func state(id: String) -> Dictionary:
	return ws.sites[id]


func is_restored(id: String) -> bool:
	return String(state(id).state) == "restored"


## How bare the site's paper is, 0 (fully written) to 1 (blank).
func paleness(id: String) -> float:
	var st := state(id)
	return float(st.pale) if String(st.state) == "restored" else 1.0


func restored_count() -> int:
	var n := 0
	for s in GameData.Lore.SITES:
		if is_restored(s.id):
			n += 1
	return n


## 0..1: how strongly the nearest bare site reaches this point.
func strength(p: Vector2) -> float:
	var best := 0.0
	var aura: float = float(GameData.Lore.ERASURE.aura)
	for s in GameData.Lore.SITES:
		var k := paleness(s.id)
		if k <= 0.0:
			continue
		var d: float = p.distance_to(s.p)
		var a: float = float(s.r) * aura
		if d >= a:
			continue
		var f: float = 1.0 if d <= float(s.r) else 1.0 - (d - float(s.r)) / (a - float(s.r))
		best = maxf(best, f * k)
	return best


## Reading goes slower near a bare site (a multiplier on read speed).
func read_speed(p: Vector2) -> float:
	return lerpf(1.0, float(GameData.Lore.ERASURE.read_speed), strength(p))


## Casting ink comes back slower near a bare site (a multiplier on the refill rate).
func ink_regen(p: Vector2) -> float:
	return lerpf(1.0, float(GameData.Lore.ERASURE.ink_regen), strength(p))


## The site whose centre you can rest at to write it back, or {}.
func restorable_at(p: Vector2) -> Dictionary:
	for s in GameData.Lore.SITES:
		var st := state(s.id)
		var want: bool = String(st.state) == "cleared" or (String(st.state) == "restored" and float(st.pale) > 0.0)
		if want and p.distance_to(s.p) < float(s.r) * float(GameData.Lore.ERASURE.restore_reach):
			return s
	return {}


## Campfires that exist now: the fixed ones plus one at every restored site.
func campfires() -> Array:
	var out: Array = GameData.CAMPFIRES.duplicate()
	for s in GameData.Lore.SITES:
		if is_restored(s.id) and paleness(s.id) < 0.5:
			out.append(s.p)
	return out


# ---------------------------------------------------------------- Monsters

## Where a new monster should appear instead of around you: inside a bare site close by
## that still has its guardian (monsters gather there), or null.
func gather_point(near: Vector2):
	var E: Dictionary = GameData.Lore.ERASURE
	var options: Array = []
	for s in GameData.Lore.SITES:
		# Only while its guardian still sleeps there: during the fight nothing else joins in,
		# and once the guardian is beaten the pale stops drawing them.
		if String(state(s.id).state) == "erased" and not guardian_alive(s.id) and near.distance_to(s.p) < float(E.gather_range):
			options.append(s)
	if options.is_empty() or randf() >= float(E.gather_chance):
		return null
	var s: Dictionary = options.pick_random()
	return s.p + Vector2.from_angle(randf() * TAU) * float(s.r) * randf_range(0.5, 1.1)


## True if a monster about to appear here should not (restored sites are calmer).
func calm(p: Vector2) -> bool:
	var E: Dictionary = GameData.Lore.ERASURE
	for s in GameData.Lore.SITES:
		if is_restored(s.id) and paleness(s.id) < 0.5 and p.distance_to(s.p) < float(s.r) * float(E.calm_radius):
			return randf() < float(E.calm_skip)
	return false


func _wake_guardian(s: Dictionary) -> void:
	w.journal("site_first_seen", String(GameData.Lore.LINES.site_first_seen))
	var G: Dictionary = GameData.Lore.GUARDIANS[int(s.region)]
	var g = EnemyScript.new()
	g.setup(w, int(G.tier), s.p)
	g.guardian = s.id
	g.title = String(G.name)
	g.hp *= float(G.hp)
	g.max_hp = g.hp
	g.dmg *= float(G.dmg)
	g.r *= float(G.size)
	g.spd *= float(G.spd)
	g.xp = roundi(g.xp * float(G.xp))
	g.aggro = true
	g.home_p = s.p
	g.leash = float(s.r) * float(GameData.Lore.GUARDIAN_LEASH)
	w.actors.add_child(g)
	w.enemies.append(g)
	guardians[s.id] = g
	for k in int(G.escorts):
		var e = EnemyScript.new()
		e.setup(w, int(G.tier), s.p + Vector2.from_angle(k * TAU / maxf(1.0, float(G.escorts)) + 0.7) * float(s.r) * 0.6)
		e.aggro = true
		w.actors.add_child(e)
		w.enemies.append(e)
	w.ring(s.p, float(s.r) * 0.3, float(s.r) * 1.3, 0.9, GameData.COLORS.ink_soft, 2.0)


func guardian_alive(id: String) -> bool:
	var g = guardians.get(id)
	return g != null and is_instance_valid(g) and not g.dead


## Called by the world when a monster dies.
func on_kill(e) -> void:
	if String(e.guardian) == "":
		return
	var id: String = e.guardian
	guardians.erase(id)
	var st := state(id)
	if String(st.state) == "erased":
		st.state = "cleared"
		w.journal("guardian_first", String(GameData.Lore.LINES.guardian_first))
		w.ring(site(id).p, 10.0, float(site(id).r), 1.2, GameData.COLORS.gilt, 2.5)
		Game.save_game()


# ---------------------------------------------------------------- Restoring

## Called at the end of every finished rest. Writes back the site you rested in, if any.
func on_rest(p: Vector2) -> bool:
	var s := restorable_at(p)
	if s.is_empty():
		return false
	restore(String(s.id))
	return true


func restore(id: String) -> void:
	var s := site(id)
	var st := state(id)
	var again: bool = int(st.times) > 0
	st.state = "restored"
	st.pale = 0.0
	st.times = int(st.times) + 1
	st.warned = false
	ws.seen[str(int(s.region))] = float(ws.time)
	fx[id] = 0.0
	w.journal("restore_first", String(GameData.Lore.LINES.restore_first))
	w.journal("site_" + id, String(s.line))
	if again:
		w.journal("rewritten", String(GameData.Lore.LINES.rewritten))
	w.ring(s.p, 10.0, float(s.r) * float(GameData.Lore.ERASURE.aura), float(GameData.Lore.RESTORE_FX.time) * 0.7, GameData.COLORS.gilt, 3.0)
	w.feel_hitstop()
	Game.save_game()


# ---------------------------------------------------------------- Every step

func tick(dt: float) -> void:
	ws.time = float(ws.time) + dt
	var reg: int = w.region
	if reg >= 1:
		ws.seen[str(reg)] = float(ws.time)
	for id in fx.keys():
		fx[id] = float(fx[id]) + dt
		if fx[id] > float(GameData.Lore.RESTORE_FX.time) + 1.0:
			fx.erase(id)
	var p: Vector2 = w.player.position
	var alive: bool = w.player.dead_t <= 0.0
	for s in GameData.Lore.SITES:
		var st := state(s.id)
		if alive and String(st.state) == "erased" and not guardian_alive(s.id) \
				and p.distance_to(s.p) < float(s.r) + float(GameData.Lore.GUARDIAN_WAKE):
			_wake_guardian(s)
		if alive and p.distance_to(s.p) < float(s.r) * 1.2:
			w.journal("site_first_seen", String(GameData.Lore.LINES.site_first_seen))
		if String(st.state) == "restored":
			_fade(s, st, dt)
	_patch_t -= dt
	if _patch_t <= 0.0:
		_patch_t = 0.5
		_fade_patches()


func reerase_on() -> bool:
	return bool(GameData.Lore.REERASE.enabled) and bool(Game.settings.get("reerase", true))


## Slow re-erasure: a restored site fades once its region has been left alone for a while.
func _fade(s: Dictionary, st: Dictionary, dt: float) -> void:
	if not reerase_on():
		return
	var R: Dictionary = GameData.Lore.REERASE
	var away: float = away_time(int(s.region))
	if away < float(R.grace):
		return
	st.pale = minf(1.0, float(st.pale) + dt / float(R.fade_time))
	if float(st.pale) >= float(R.warn_at) and not bool(st.warned):
		st.warned = true
		w.journal("reerase_first", String(GameData.Lore.LINES.reerase_first))
	if float(st.pale) >= 1.0:
		st.state = "erased"
		st.pale = 1.0


## Seconds of play since you were last in this region.
func away_time(reg: int) -> float:
	return float(ws.time) - float(ws.seen.get(str(reg), 0.0))


## Ground patches near a bare site lose their nature (grass won't burn, puddles don't soak...).
func _fade_patches() -> void:
	var tf: float = float(GameData.Lore.ERASURE.terrain_fade)
	for pt in w.terrain.patches:
		var faded := false
		for s in GameData.Lore.SITES:
			if paleness(s.id) >= 0.5 and pt.p.distance_to(s.p) < float(s.r) * tf:
				faded = true
				break
		pt.faded = faded


# ---------------------------------------------------------------- Designer view (F1)

func designer_text() -> String:
	var soft: String = GameData.COLORS.ink_soft.to_html(false)
	var out := "\n[b]Erasure sites[/b] (%d of %d restored) · world time %.0fs · re-erasure %s\n" % [
		restored_count(), GameData.Lore.SITES.size(), float(ws.time), "on" if reerase_on() else "off"]
	for s in GameData.Lore.SITES:
		var st := state(s.id)
		var extra := ""
		match String(st.state):
			"erased":
				extra = "guardian %s" % ("awake" if guardian_alive(s.id) else "waiting")
			"cleared":
				extra = "rest at the centre to write it back"
			"restored":
				var away := away_time(int(s.region))
				extra = "pale %d%% · region left alone %.0fs (fades after %.0fs) · written back %d×" % [
					roundi(100.0 * float(st.pale)), away, float(GameData.Lore.REERASE.grace), int(st.times)]
		out += "[color=#%s]%s[/color] (%s) %s · %s\n" % [soft, s.name, GameData.REGIONS[int(s.region)].name, String(st.state), extra]
	var here := strength(w.player.position)
	out += "here: erasure %d%% · read speed x%.2f · ink refill x%.2f\n" % [roundi(here * 100.0), read_speed(w.player.position), ink_regen(w.player.position)]
	return out
