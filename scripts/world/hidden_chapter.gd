extends RefCounted
## The hidden chapter every book has. Tracks secret progress, writes hints in
## the margins, and checks the awakening act when the book is opened.
##
## In the online version, this whole file runs on the server only.

var w
var hint_gap := 0.0     # seconds before the next margin hint may appear (not saved)


func _init(world) -> void:
	w = world


func aspect() -> Dictionary:
	return w.ch.aspect


func progress() -> void:
	var a := aspect()
	if a.awakened:
		return
	a.progress = mini(int(a.need), int(a.progress) + 1)


## The stage the progress has earned (0..4). Hints are revealed one at a time, at least
## CHAPTER_TUNING.hint_gap seconds apart, so a fast trigger never dumps every hint at once.
func earned_stage() -> int:
	var a := aspect()
	return mini(4, int(floor(float(a.progress) / maxf(1.0, float(a.need)) * 4.0)))


func tick(dt: float) -> void:
	hint_gap = maxf(0.0, hint_gap - dt)
	var a := aspect()
	if a.id == "" or a.awakened or hint_gap > 0.0 or int(a.stage) >= earned_stage():
		return
	_next_hint()
	hint_gap = float(GameData.CHAPTER_TUNING.hint_gap)


func _next_hint() -> void:
	var a := aspect()
	a.stage = int(a.stage) + 1
	var hint: String = GameData.FINAL_HINT if a.stage >= 4 else GameData.ASPECTS[a.id].hints[a.stage - 1]
	a.margins.append(hint)
	w.on_hint(hint)
	Game.save_game()


## Designer tool: reveal every earned hint right away.
func flush_hints() -> void:
	while int(aspect().stage) < earned_stage():
		_next_hint()


# ---- Triggers (called by the world)

func on_kill(e, src: String) -> void:
	var a := aspect()
	if a.id == "hunger" and w.streak >= int(GameData.CHAPTER_TUNING.hunger_streak):
		progress()
	if a.id == "echo" and src == "player" and e.ally_hit > 0.0:
		progress()


func on_cast(was_still: bool) -> void:
	if aspect().id == "stillness" and was_still:
		progress()


func on_recover() -> void:
	if aspect().id == "lastpage":
		progress()


func on_ally_cast(target) -> void:
	var a := aspect()
	if not (a.awakened and a.id == "echo") or w.player.dead_t > 0.0:
		return
	var prim: Dictionary = Game.spell_stats(w.ch.spells[0])
	var echo: Dictionary
	if prim.kind == "bolt" or prim.kind == "chain":
		echo = prim.duplicate()
		echo.tier = 0
	else:
		echo = {"kind": "bolt", "el": w.ch.el, "dmg": prim.dmg, "speed": 520.0, "tier": 0}
	w.perform(echo, target.position, "player", 0.5)
	w.add_text(w.player.position + Vector2(0, -26), "Echo", GameData.COLORS.gilt, 13, 0.8)


# ---- Awakening

func act_met() -> bool:
	var a := aspect()
	var p = w.player
	var ne = w.nearest(p.position, 400.0)
	var nd: float = p.position.distance_to(ne.position) if ne != null else 9999.0
	match a.id:
		"stillness":
			return p.still > 0.5 and nd < 240.0
		"hunger":
			return w.streak >= int(a.streak)
		"lastpage":
			return p.dead_t <= 0.0 and p.hp / Game.max_hp() < 0.25
		"echo":
			return p.position.distance_to(w.ally.position) < 110.0 and nd < 300.0
	return false


func try_awaken() -> bool:
	var a := aspect()
	if a.awakened or int(a.stage) < 4 or not act_met():
		return false
	a.awakened = true
	a.margins.append("%s. The chapter is written." % GameData.ASPECTS[a.id].name)
	Game.save_game()
	return true


func trigger_text() -> String:
	var a := aspect()
	return String(GameData.ASPECTS[a.id].trigger).format({"need": a.need, "streak": a.streak})


func act_text() -> String:
	var a := aspect()
	return String(GameData.ASPECTS[a.id].act).format({"need": a.need, "streak": a.streak})
