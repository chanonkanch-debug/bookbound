extends Node
## Balance bot: `godot --headless --path . -- --balance`
## Plays the bare-hands phase with five scripted playstyles, several runs each,
## and prints how fast each style levels, how often it dies, and what book odds
## it ends up with. Use it after changing numbers in game_data.gd to check that
## every style can reach the ceremony at a similar pace.
##
## Add `--runs=N` to change the number of runs per style (default 8).

const World := preload("res://scripts/world/world.gd")
const DT := 1.0 / 30.0
const MAX_TIME := 900.0   # give up after 15 simulated minutes

const STYLES := {
	"brawler": "locks onto one enemy and jabs it down (Escalate)",
	"spreader": "jabs a different enemy each time (Chain)",
	"controller": "keeps enemies off with Shove, backs away (Redirect)",
	"skirmisher": "never stops moving, sidesteps through enemies (Move)",
	"anchor": "plants their feet and lets enemies come (Persist)",
	"mixed": "switches between all of the above every few seconds",
}

var focus_target = null
var last_target = null
var orbit_dir := 1.0
var mixed_style := "brawler"
var mixed_t := 0.0


func run() -> void:
	var runs := 8
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
	print("\n=== Bookbound balance bot: %d runs per style, ceremony at Lv %d ===" % [runs, GameData.CEREMONY_LEVEL])
	for style in STYLES:
		var times: Array = []
		var deaths := 0
		var odds_sum := {}
		var thick_sum := {}
		var hits := {}
		var sig_sum := {}
		for r in runs:
			var res: Dictionary = await _play(style)
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
	print("\n=== done ===")


func _fmt(d: Dictionary) -> String:
	var bits: Array = []
	for k in d:
		bits.append("%s %d%%" % [k, roundi(100.0 * d[k])])
	return ", ".join(bits)


func _play(style: String) -> Dictionary:
	Game.ch = Game.new_character("Bot", "orphan")
	var w = World.new()
	add_child(w)
	await get_tree().process_frame
	w.set_process(false)
	w.player.position = Vector2(0, 200)
	focus_target = null
	last_target = null
	var t := 0.0
	var deaths := 0
	var was_dead := false
	while t < MAX_TIME and int(Game.ch.level) < GameData.CEREMONY_LEVEL:
		_think(w, style)
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


## One decision per frame: where to move and which move to use.
func _think(w, style: String) -> void:
	var p = w.player
	if p.dead_t > 0.0:
		p.steer = Vector2.ZERO
		return
	var near = w.nearest(p.position, 2000.0)
	if near == null:
		p.steer = (Vector2(0, 400) - p.position).normalized()
		return
	var to: Vector2 = near.position - p.position
	var d := to.length()
	# Everyone heads back to heal when low, like a sensible player.
	if p.hp / Game.max_hp() < 0.3:
		p.steer = -p.position.normalized()
		if style == "skirmisher":
			w.cast(2)
		return
	if style == "mixed":
		mixed_t -= DT
		if mixed_t <= 0.0:
			mixed_t = randf_range(3.0, 7.0)
			mixed_style = ["brawler", "spreader", "controller", "skirmisher", "anchor"].pick_random()
		style = mixed_style
	match style:
		"brawler":
			if focus_target == null or focus_target.dead or not is_instance_valid(focus_target):
				focus_target = near
			var ft: Vector2 = focus_target.position - p.position
			p.steer = ft.normalized() if ft.length() > 40.0 else Vector2.ZERO
			if ft.length() < 70.0:
				w.cast(0, focus_target)
		"spreader":
			var pick = near
			if last_target != null and is_instance_valid(last_target) and pick == last_target:
				var other = w.nearest(p.position, 160.0, [last_target])
				if other != null:
					pick = other
			var pt: Vector2 = pick.position - p.position
			p.steer = pt.normalized() if pt.length() > 40.0 else Vector2.ZERO
			if pt.length() < 70.0 and w.cds[0] <= 0.0:
				last_target = pick
				w.cast(0, pick)
		"controller":
			if d < 80.0:
				w.cast(1)
			if d < 60.0:
				p.steer = -to.normalized()
			elif d > 90.0:
				p.steer = to.normalized()
			else:
				p.steer = Vector2.ZERO
				w.cast(0)
			if d < 70.0:
				w.cast(0)
		"skirmisher":
			var side := Vector2(-to.y, to.x).normalized() * orbit_dir
			p.steer = (side + to.normalized() * (0.6 if d > 60.0 else -0.4)).normalized()
			if d < 70.0:
				w.cast(0)
			if d < 140.0 and w.cds[2] <= 0.0:
				p.facing = to.normalized()
				w.cast(2)
				orbit_dir = -orbit_dir
		"anchor":
			if d > 130.0:
				p.steer = to.normalized()
			else:
				p.steer = Vector2.ZERO
				if d < 70.0:
					w.cast(0)
