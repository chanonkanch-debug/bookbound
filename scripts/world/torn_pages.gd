extends RefCounted
## The Unwritten, Phase 2: torn pages (fragments of the great book), found lying in the world.
## Rules only; world.gd draws them and ui/fragments_overlay.gd shows them as torn paper.
## Found pages are the character's (ch.fragments, in the order found); where they lie is data
## (GameData.Lore.FRAGMENTS). Pages that lie at an erasure site appear once it is written back.

var w


func _init(world) -> void:
	w = world


static func by_id(id: String) -> Dictionary:
	for f in GameData.Lore.FRAGMENTS:
		if f.id == id:
			return f
	return {}


func found(id: String) -> bool:
	return id in w.ch.get("fragments", [])


## Where this page lies right now, or null if it isn't in the world (found, in the Stacks,
## or at a site that hasn't been written back yet).
func where(f: Dictionary):
	if found(String(f.id)):
		return null
	match String(f.where):
		"grass", "stone":
			return f.p
		"site":
			var s: Dictionary = w.erasure.site(String(f.site))
			if w.erasure.is_restored(String(f.site)):
				return s.p + GameData.Lore.FRAGMENT_SITE_OFFSET
	return null


## How visible a lying page is from here, 0..1 (grass hides them until you're close).
func seen(f: Dictionary, from: Vector2) -> float:
	var p = where(f)
	if p == null:
		return 0.0
	var reach: float = float(GameData.Lore.FRAGMENT_SEEN.get(String(f.where), 120.0))
	return clampf(1.5 - from.distance_to(p) / reach, 0.0, 1.0)


func tick(_dt: float) -> void:
	if w.player.dead_t > 0.0:
		return
	for f in GameData.Lore.FRAGMENTS:
		var p = where(f)
		if p != null and w.player.position.distance_to(p) < float(GameData.Lore.FRAGMENT_PICKUP):
			pick_up(String(f.id))


func pick_up(id: String) -> void:
	if found(id):
		return
	var f := by_id(id)
	if not w.ch.has("fragments"):
		w.ch.fragments = []
	w.ch.fragments.append(id)
	w.journal("fragment_first", String(GameData.Lore.LINES.fragment_first))
	var at: Vector2 = w.player.position
	w.ring(at, 4.0, 46.0, 0.8, GameData.COLORS.gilt, 2.0)
	w.add_text(at + Vector2(0, -30), String(f.title), GameData.COLORS.gilt, 14, 2.4)
	Game.save_game()


## Found pages, oldest first, as their data rows.
func found_pages() -> Array:
	var out: Array = []
	for id in w.ch.get("fragments", []):
		var f := by_id(String(id))
		if not f.is_empty():
			out.append(f)
	return out


func designer_text() -> String:
	var soft: String = GameData.COLORS.ink_soft.to_html(false)
	var out := "\n[b]Torn pages[/b] (%d of %d found)\n" % [w.ch.get("fragments", []).size(), GameData.Lore.FRAGMENTS.size()]
	for f in GameData.Lore.FRAGMENTS:
		var place := String(f.where)
		match place:
			"grass", "stone":
				place += " at %s" % [Vector2(f.p).round()]
			"site":
				place += " at %s (%s)" % [w.erasure.site(String(f.site)).name, "there now" if where(f) != null else "appears once written back"]
			"stacks":
				place += ", floor %d (Phase 7)" % int(f.floor)
		out += "[color=#%s]%s %s[/color] · %s\n" % [soft, "✓" if found(String(f.id)) else "·", f.title, place]
	return out
