extends RefCounted
## Learning by experimenting (Phase 3). Tracks what the player has seen and found:
##   affinities  how each monster reacts to each element (AFFINITIES); written into the
##               journal's bestiary after DISCOVERY.affinity_seen sightings
##   terrain     how the ground reacts to elements (TERRAIN_LINES); journal line on first sight
##   secrets     one hidden behavior per spell (SECRETS); a margin line on first trigger
## It also helps Mira pick targets that teach the player something new.
## Rules only, no drawing. Everything is saved in ch.disc.

var w


func _init(world) -> void:
	w = world
	var ch: Dictionary = w.ch
	if not ch.has("disc"):
		ch.disc = {}
	for k in ["seen", "known", "terrain", "secrets"]:
		if not ch.disc.has(k):
			ch.disc[k] = {}
	if not ch.disc.has("margins"):
		ch.disc.margins = []


func d() -> Dictionary:
	return w.ch.disc


# ---------------------------------------------------------------- Affinities

## The hidden reaction of monster `e` to element `el`, or {} if none.
func reaction(e, el: String) -> Dictionary:
	return GameData.AFFINITIES.get(e.foe_name, {}).get(el, {})


## Someone just saw `e` react to `el` (any source: you or Mira).
func saw_reaction(e, el: String) -> void:
	if reaction(e, el).is_empty():
		return
	var key: String = "%s|%s" % [e.foe_name, el]
	var seen: Dictionary = d().seen
	seen[key] = int(seen.get(key, 0)) + 1
	if not d().known.has(key) and int(seen[key]) >= int(GameData.DISCOVERY.affinity_seen):
		d().known[key] = true
		w.unlock("journal")
		w.journal("aff_" + key, String(reaction(e, el).line))


func knows(foe_name: String, el: String) -> bool:
	return d().known.has("%s|%s" % [foe_name, el])


func bestiary_lines() -> Array:
	var out: Array = []
	for foe in GameData.AFFINITIES:
		for el in GameData.AFFINITIES[foe]:
			if knows(foe, el):
				out.append(GameData.AFFINITIES[foe][el].line)
	return out


# ---------------------------------------------------------------- Terrain

func saw_terrain(id: String) -> void:
	if d().terrain.has(id):
		return
	d().terrain[id] = true
	w.unlock("journal")
	w.journal("terrain_" + id, String(GameData.TERRAIN_LINES[id]))


# ---------------------------------------------------------------- Spell secrets

func found(spell: String) -> bool:
	return d().secrets.has(spell)


## A spell's secret just happened. The first time, it's written into the margins.
func secret(spell: String) -> void:
	if found(spell) or not GameData.SECRETS.has(spell):
		return
	d().secrets[spell] = true
	d().margins.append(String(GameData.SECRETS[spell].line))
	w.on_hint(String(GameData.SECRETS[spell].line))
	Game.save_game()


## The player's spells whose secret isn't found yet.
func undiscovered_secrets() -> Array:
	var out: Array = []
	if not Game.has_book():
		return out
	for s in w.ch.spells:
		var n: String = GameData.SPELLS[w.ch.el][int(s.i)].name
		if not found(n):
			out.append(n)
	return out


# ---------------------------------------------------------------- Mira teaches by example

const SOAK_SECRETS := ["Ember Bolt", "Storm Rod", "Spark"]
const PUDDLE_SECRETS := ["Spark", "Gust", "Tide Shot", "Arc Nova", "Still Pool"]


## Extra score for Mira hitting `e` with `el`: favors showing the player something new.
func mira_bonus(e, el: String) -> float:
	var T: Dictionary = GameData.MIRA_TEACH
	var bonus := 0.0
	if not reaction(e, el).is_empty() and not knows(e.foe_name, el):
		bonus += float(T.untaught_affinity)
	var todo := undiscovered_secrets()
	if el == "water" and e.soak <= 0.0 and e.position.distance_to(w.player.position) < 260.0:
		for s in SOAK_SECRETS:
			if s in todo:
				bonus += float(T.soak_for_player)
				break
	if w.terrain.at(e.position, "puddle") != null:
		for s in PUDDLE_SECRETS:
			if s in todo:
				bonus += float(T.in_puddle)
				break
	return bonus


# ---------------------------------------------------------------- Designer view

func designer_text() -> String:
	var t := "\n[b]Discoveries[/b]\n"
	var soft: String = GameData.COLORS.ink_soft.to_html(false)
	t += "[i]Affinities[/i] (seen / needed %d)\n" % int(GameData.DISCOVERY.affinity_seen)
	for foe in GameData.AFFINITIES:
		for el in GameData.AFFINITIES[foe]:
			var a: Dictionary = GameData.AFFINITIES[foe][el]
			var key: String = "%s|%s" % [foe, el]
			t += "%s %s + %s: %s · %d%s\n" % ["✓" if knows(foe, el) else "·", foe, el, a.type, int(d().seen.get(key, 0)),
				"" if knows(foe, el) else "  [color=#%s]%s[/color]" % [soft, a.line]]
	t += "[i]Terrain[/i]\n"
	for id in GameData.TERRAIN_LINES:
		t += "%s %s\n" % ["✓" if d().terrain.has(id) else "·", id]
	t += "[i]Spell secrets[/i] (★ = in this book)\n"
	var mine: Array = []
	if Game.has_book():
		for s in w.ch.spells:
			mine.append(GameData.SPELLS[w.ch.el][int(s.i)].name)
	for el in GameData.SPELLS:
		for sp in GameData.SPELLS[el]:
			var n: String = sp.name
			var sec: Dictionary = GameData.SECRETS[n]
			t += "%s %s%s: when it %s, it %s\n" % ["✓" if found(n) else "·", n, " ★" if n in mine else "", sec.when, sec.does]
	return t
