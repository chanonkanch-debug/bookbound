extends RefCounted
## Ground patches that react to elements (Phase 3). Rules only; world.gd draws them.
##   grass   dry grass: fire sets it alight, and it burns as a fire zone for a while
##   puddle  water spells grow in it, and anything standing in it is soaked
##   stone   earth zones placed on stones last longer
##   open    bare, windswept ground: wind spells reach further from it
## The layout is the same every time (TERRAIN.seed), so players can learn it.
## Numbers: TERRAIN in game_data.gd.

var patches: Array = []    # {kind, p, r, burnt}


func _init() -> void:
	var T: Dictionary = GameData.TERRAIN
	var rng := RandomNumberGenerator.new()
	rng.seed = int(T.seed)
	for kind in T.patches:
		var d: Dictionary = T.patches[kind]
		var placed := 0
		var tries := 0
		while placed < int(d.count) and tries < 400:
			tries += 1
			var a := rng.randf() * TAU
			var dist := rng.randf_range(float(d.band[0]), float(d.band[1]))
			var p := Vector2.from_angle(a) * dist
			var r := rng.randf_range(float(d.r[0]), float(d.r[1]))
			if p.length() - r < GameData.TOWN_RADIUS + 30.0 or p.length() + r > GameData.WORLD_RADIUS - 20.0:
				continue
			var clash := false
			for o in patches:
				if o.p.distance_to(p) < o.r + r + 20.0:
					clash = true
					break
			if clash:
				continue
			patches.append({"kind": kind, "p": p, "r": r, "burnt": 0.0, "sd": rng.randf() * 9.0})
			placed += 1


func tick(dt: float) -> void:
	for pt in patches:
		pt.burnt = maxf(0.0, pt.burnt - dt)


## The patch of this kind under `pos` (burnt grass doesn't count), or null.
func at(pos: Vector2, kind: String):
	for pt in patches:
		if pt.kind == kind and pos.distance_to(pt.p) < pt.r and not (kind == "grass" and pt.burnt > 0.0):
			return pt
	return null


## Patches of this kind overlapping a circle.
func overlapping(pos: Vector2, r: float, kind: String) -> Array:
	var out: Array = []
	for pt in patches:
		if pt.kind == kind and pos.distance_to(pt.p) < pt.r + r and not (kind == "grass" and pt.burnt > 0.0):
			out.append(pt)
	return out
