extends RefCounted
## The hidden chapter every book has. Tracks secret progress, writes hints in
## the margins, and checks the awakening act when the book is opened.
##
## In the online version, this whole file runs on the server only.

var w


func _init(world) -> void:
	w = world


func aspect() -> Dictionary:
	return w.ch.aspect


func progress() -> void:
	var a := aspect()
	if a.awakened:
		return
	a.progress = mini(int(a.need), int(a.progress) + 1)
	var stage := mini(4, int(floor(float(a.progress) / float(a.need) * 4.0)))
	while int(a.stage) < stage:
		a.stage = int(a.stage) + 1
		var hint: String = GameData.FINAL_HINT if a.stage >= 4 else GameData.ASPECTS[a.id].hints[a.stage - 1]
		a.margins.append(hint)
		w.on_hint(hint)
		Game.save_game()


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
