extends Node2D
## An ink monster. Wanders until you come close, then hunts you.
## Every attack has a visible wind-up (it swells, darkens and leans in) so you can
## read it and step away, or hit it hard enough to interrupt it.
## Behaviors (see FOES in game_data.gd):
##   pair    Inklings come in twos and try to reach you from opposite sides.
##   charge  Blots wind up, rush in a straight line, then rest.
##   guard   Smudge Knights turn slowly and only strike in an arc in front of them.

const Ink := preload("res://scripts/util/ink.gd")

var w
var tier := 0
var foe_name := ""
var behavior := "pair"
var f: Dictionary = {}       # this monster's row in GameData.FOES
var hp := 1.0
var max_hp := 1.0
var spd := 60.0
var dmg := 5.0
var r := 11.0
var xp := 1

var soak := 0.0
var slow_t := 0.0
var slow_f := 1.0
var ally_hit := 0.0     # >0 means Mira hit this recently (Echo chapter)
var first_hit_t := -1.0 # world time you first hit it (playstyle signals)
var bit_player := false # it has hurt you at least once (playstyle signals)
var flash := 0.0
var knock := Vector2.ZERO
var aggro := false
var wander := 0.0
var sd := 0.0
var dead := false

# Attack state machine: "hunt" -> "windup" -> ("charge") -> "recover" -> "hunt".
# "stagger" happens when a wind-up is interrupted.
var state := "hunt"
var state_t := 0.0
var face := Vector2.RIGHT    # where it looks (Knights turn slowly)
var lunge := Vector2.ZERO    # locked direction of a Blot's charge
var partner = null           # the other Inkling of a pair
var side := 1.0              # which flank this Inkling takes
var charge_hit := false
var enraged_t := 0.0         # Phase 3: an enraging element makes it faster for a while
var enrage_speed := 1.0
var crash_t := 0.0           # Undertow secret: thrown, and will crash into the next one it touches
var crash_dmg := 0.0
var crash_kind := ""         # "undertow" (spell secret) or "tangle" (hand secret)
var split_done := false
var bored := 0.0             # seconds spent hunting someone who is safe inside the Hearth


func setup(world, t: int, pos: Vector2) -> void:
	w = world
	tier = t
	position = pos
	f = GameData.FOES[t]
	foe_name = f.name
	behavior = f.behavior
	hp = f.hp
	max_hp = f.hp
	spd = float(f.spd) * randf_range(0.9, 1.1)
	dmg = f.dmg
	r = f.r
	xp = f.xp
	wander = randf() * TAU
	sd = randf() * 9.0
	face = Vector2.from_angle(randf() * TAU)


func winding_up() -> bool:
	return state == "windup"


## Called by the world when a hit is hard enough (or pushes it): the strike is cancelled.
func interrupt() -> bool:
	if state != "windup":
		return false
	state = "stagger"
	state_t = float(GameData.MONSTERS.stagger)
	flash = 0.2
	return true


func tick(dt: float) -> void:
	if dead:
		return
	soak -= dt
	slow_t -= dt
	ally_hit -= dt
	flash -= dt
	state_t -= dt
	enraged_t -= dt
	crash_t -= dt
	var p = w.player
	var to_p: Vector2 = w.lure_for(self) - position
	var d := to_p.length()
	var target_alive: bool = p.dead_t <= 0.0
	if d < 330.0 and target_alive and bored <= float(GameData.MONSTERS.hearth_give_up):
		aggro = true
	# Nothing can enter the Hearth. A monster left pacing at its edge gives up after a while
	# and wanders off, instead of waiting there for you forever.
	if p.position.length() < GameData.TOWN_RADIUS:
		if aggro or bored > 0.0:
			bored += dt
		if aggro and bored > float(GameData.MONSTERS.hearth_give_up):
			aggro = false
			wander = position.angle()
	else:
		bored = 0.0
	if d > 700.0 or not target_alive:
		aggro = false
		if state != "hunt" and state != "recover":
			state = "hunt"
	var s := spd * (slow_f if slow_t > 0.0 else 1.0) * (enrage_speed if enraged_t > 0.0 else 1.0)
	var v := Vector2.ZERO
	var dir: Vector2 = to_p / d if d > 0.0 else Vector2.RIGHT
	var gap: float = d - r - p.r   # distance between edges

	match state:
		"hunt":
			if not aggro:
				wander += randf_range(-1.5, 1.5) * dt
				v = Vector2.from_angle(wander) * s * 0.35
				face = face.slerp(v.normalized(), minf(1.0, dt * 2.0)) if v.length() > 0.1 else face
			else:
				v = _hunt_move(dir, d, s, dt)
				if _can_start(dir, gap):
					state = "windup"
					state_t = float(f.windup)
					lunge = dir
		"windup":
			# Leans in, slowly tracking you. Knights keep turning at their slow rate.
			if behavior == "guard":
				_turn_toward(dir, dt)
			elif behavior == "pair":
				face = face.slerp(dir, minf(1.0, dt * 3.0))
			if state_t <= 0.0:
				_strike(dir, gap)
		"charge":
			v = lunge * float(f.charge_speed)
			if not charge_hit and target_alive and position.distance_to(p.position) < r + p.r + float(f.reach):
				charge_hit = true
				w.enemy_strike(self)
			if state_t <= 0.0:
				state = "recover"
				state_t = float(f.recover)
		"recover", "stagger":
			if aggro and behavior == "guard":
				_turn_toward(dir, dt * 0.5)
			if state_t <= 0.0:
				state = "hunt"
	position += (v + knock) * dt
	knock *= pow(0.02, dt)

	var dc := position.length()
	var town_r := GameData.TOWN_RADIUS + r
	if dc < town_r:   # monsters can't enter the Hearth
		position = position.normalized() * town_r if dc > 0.0 else Vector2(town_r, 0)
		if state == "charge":
			state = "recover"
			state_t = float(f.recover)
	if dc > GameData.WORLD_RADIUS:
		position = position.normalized() * GameData.WORLD_RADIUS
		wander += PI
	queue_redraw()


## Movement while hunting, by behavior.
func _hunt_move(dir: Vector2, d: float, s: float, dt: float) -> Vector2:
	match behavior:
		"pair":
			face = face.slerp(dir, minf(1.0, dt * 4.0))
			# Flank: aim for a spot beside you, on this Inkling's side.
			var goal: Vector2 = w.player.position + Vector2(-dir.y, dir.x) * side * float(GameData.MONSTERS.pair_offset)
			var to_goal: Vector2 = goal - position
			if d < r + w.player.r + float(f.reach) + 4.0:
				return Vector2.ZERO
			return to_goal.normalized() * s if to_goal.length() > 2.0 else Vector2.ZERO
		"charge":
			face = face.slerp(dir, minf(1.0, dt * 3.0))
			if d > float(f.charge_from) * 0.8:
				return dir * s
			return Vector2.ZERO
		"guard":
			_turn_toward(dir, dt)
			if d > r + w.player.r + float(f.reach) * 0.8:
				return face * s
			return Vector2.ZERO
	return dir * s


func _turn_toward(dir: Vector2, dt: float) -> void:
	var a := face.angle()
	var b := dir.angle()
	var diff := wrapf(b - a, -PI, PI)
	var step := float(f.turn) * dt
	face = Vector2.from_angle(a + clampf(diff, -step, step))


func _in_arc(dir: Vector2) -> bool:
	return absf(wrapf(dir.angle() - face.angle(), -PI, PI)) <= float(f.arc) / 2.0


func _can_start(dir: Vector2, gap: float) -> bool:
	if w.player.dead_t > 0.0:
		return false
	match behavior:
		"charge":
			return gap < float(f.charge_from)
		"guard":
			return gap < float(f.reach) and _in_arc(dir)
	return gap < float(f.reach)


func _strike(dir: Vector2, gap: float) -> void:
	match behavior:
		"charge":
			state = "charge"
			state_t = float(f.charge_time)
			charge_hit = false
			return
		"guard":
			if gap < float(f.reach) + 6.0 and _in_arc(dir):
				w.enemy_strike(self)
		_:
			if gap < float(f.reach) + 6.0:
				w.enemy_strike(self)
	state = "recover"
	state_t = float(f.recover)


func _draw() -> void:
	var C: Dictionary = GameData.COLORS
	var k := 0.0   # wind-up progress 0..1
	if state == "windup":
		k = clampf(1.0 - state_t / float(f.windup), 0.0, 1.0)
	var swell := 1.0 + 0.28 * k
	var lean: Vector2 = (lunge if behavior == "charge" else face) * r * 0.35 * k
	var body: Color = C.ink.lerp(C.danger, 0.55 * k)
	if flash > 0.0:
		body = C.danger
	if state == "stagger":
		body = C.ink.lerp(C.paper, 0.35)
	# Telegraph shapes, drawn under the body.
	if state == "windup":
		match behavior:
			"charge":
				var length := float(f.charge_speed) * float(f.charge_time)
				draw_line(Vector2.ZERO, lunge * length, Color(C.danger, 0.12 + 0.25 * k), r * 1.6)
			"guard":
				var reach: float = r + float(f.reach) + 12.0
				var a0 := face.angle() - float(f.arc) / 2.0
				var pts := PackedVector2Array([Vector2.ZERO])
				for i in 13:
					pts.append(Vector2.from_angle(a0 + float(f.arc) * i / 12.0) * reach)
				draw_colored_polygon(pts, Color(C.danger, 0.08 + 0.22 * k))
			_:
				draw_arc(Vector2.ZERO, r + float(f.reach), 0, TAU, 32, Color(C.danger, 0.1 + 0.3 * k), 1.5)
		# Every wind-up: a ring that closes in on the monster. When it touches, the blow lands.
		# Its size (not its colour) says how long you have, so it reads in a crowd.
		var closing: float = r * swell + 3.0 + float(GameData.READABILITY.windup_ring) * (1.0 - k)
		draw_arc(lean, closing, 0, TAU, 32, Color(C.danger, 0.35 + 0.55 * k), 1.5 + 2.0 * k)
	draw_colored_polygon(Ink.blob(lean, r * swell, sd, w.time * (1.0 + 2.0 * k)), body)
	if tier == 2:
		draw_polyline(Ink.outline(Ink.blob(lean, r * swell + 3.0, sd, w.time)), C.danger, 2.0)
		# A Knight's guard: a thick stroke on the side it faces.
		var fa := face.angle()
		draw_arc(lean, r * swell + 7.0, fa - float(f.arc) / 2.0, fa + float(f.arc) / 2.0, 16, C.ink, 4.0)
	if soak > 0.0:
		draw_arc(Vector2.ZERO, r + 5.0, 0, TAU, 32, Color(C.water, 0.8), 2.0)
	if slow_t > 0.0 and slow_f < 1.0:
		draw_arc(Vector2.ZERO, r + 8.0, 0, TAU * 0.6, 24, Color(C.earth, 0.6), 1.5)
	if enraged_t > 0.0:
		for i in 4:
			var a: float = w.time * 6.0 + i * PI / 2.0
			draw_line(Vector2.from_angle(a) * (r + 3.0), Vector2.from_angle(a) * (r + 9.0), Color(C.danger, 0.8), 2.0)
	var look: Vector2 = face * r * 0.3 + lean
	var eye := r * (0.2 + 0.08 * k)
	draw_circle(look + Vector2(-r * 0.32, -r * 0.15), eye, C.paper)
	draw_circle(look + Vector2(r * 0.32, -r * 0.15), eye, C.paper)
	# No health bar: a hurt monster cracks and its ink thins.
	var hurt := 1.0 - clampf(hp / max_hp, 0.0, 1.0)
	if hurt > 0.15:
		var n := int(hurt * 6.0)
		for i in n:
			var a0 := sd + i * 2.4
			draw_line(lean + Vector2.from_angle(a0) * r * 0.25, lean + Vector2.from_angle(a0 + 0.35) * r * swell, Color(C.paper, 0.55), 1.2)
	if Game.show_numbers() and hp < max_hp:
		draw_rect(Rect2(-r, -r - 9.0, r * 2.0, 3.0), C.rule)
		draw_rect(Rect2(-r, -r - 9.0, r * 2.0 * maxf(0.0, hp / max_hp), 3.0), C.danger)
