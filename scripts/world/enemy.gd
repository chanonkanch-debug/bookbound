extends Node2D
## An ink monster. Wanders until you come close, then chases you.

const Ink := preload("res://scripts/util/ink.gd")

var w
var tier := 0
var foe_name := ""
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
var flash := 0.0
var atk := 0.0
var knock := Vector2.ZERO
var aggro := false
var wander := 0.0
var sd := 0.0
var dead := false


func setup(world, t: int, pos: Vector2) -> void:
	w = world
	tier = t
	position = pos
	var f: Dictionary = GameData.FOES[t]
	foe_name = f.name
	hp = f.hp
	max_hp = f.hp
	spd = float(f.spd) * randf_range(0.9, 1.1)
	dmg = f.dmg
	r = f.r
	xp = f.xp
	wander = randf() * TAU
	sd = randf() * 9.0


func tick(dt: float) -> void:
	if dead:
		return
	soak -= dt
	slow_t -= dt
	ally_hit -= dt
	flash -= dt
	atk -= dt
	var p = w.player
	var to_p: Vector2 = p.position - position
	var d := to_p.length()
	var target_alive: bool = p.dead_t <= 0.0
	if d < 330.0 and target_alive:
		aggro = true
	if d > 700.0 or not target_alive:
		aggro = false

	var s := spd * (slow_f if slow_t > 0.0 else 1.0)
	var v := Vector2.ZERO
	if aggro and d > 0.0:
		v = to_p / d * s
	else:
		wander += randf_range(-1.5, 1.5) * dt
		v = Vector2.from_angle(wander) * s * 0.35
	position += (v + knock) * dt
	knock *= pow(0.02, dt)

	var dc := position.length()
	var town_r := GameData.TOWN_RADIUS + r
	if dc < town_r:   # monsters can't enter the Hearth
		position = position.normalized() * town_r if dc > 0.0 else Vector2(town_r, 0)
	if dc > GameData.WORLD_RADIUS:
		position = position.normalized() * GameData.WORLD_RADIUS
		wander += PI
	if d < r + p.r + 2.0 and atk <= 0.0 and target_alive:
		w.hurt(dmg)
		atk = 0.9
	queue_redraw()


func _draw() -> void:
	var C: Dictionary = GameData.COLORS
	draw_colored_polygon(Ink.blob(Vector2.ZERO, r, sd, w.time), C.danger if flash > 0.0 else C.ink)
	if tier == 2:
		draw_polyline(Ink.outline(Ink.blob(Vector2.ZERO, r + 3.0, sd, w.time)), C.danger, 2.0)
	if soak > 0.0:
		draw_arc(Vector2.ZERO, r + 5.0, 0, TAU, 32, Color(C.water, 0.8), 2.0)
	if slow_t > 0.0 and slow_f < 1.0:
		draw_arc(Vector2.ZERO, r + 8.0, 0, TAU * 0.6, 24, Color(C.earth, 0.6), 1.5)
	var look: Vector2 = (w.player.position - position).normalized() * r * 0.3
	draw_circle(look + Vector2(-r * 0.32, -r * 0.15), r * 0.2, C.paper)
	draw_circle(look + Vector2(r * 0.32, -r * 0.15), r * 0.2, C.paper)
	if hp < max_hp:
		draw_rect(Rect2(-r, -r - 9.0, r * 2.0, 3.0), C.rule)
		draw_rect(Rect2(-r, -r - 9.0, r * 2.0 * maxf(0.0, hp / max_hp), 3.0), C.danger)
