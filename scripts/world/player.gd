extends Node2D
## You. Movement, regen and the "low health" tracking for the Last Page chapter.

const Ink := preload("res://scripts/util/ink.gd")

var w
var r := 12.0
var hp := 100.0
var mana := 50.0
var facing := Vector2.RIGHT
var still := 0.0        # seconds since you last moved
var heat := 0           # fire stacks
var heat_t := 0.0
var hurt_t := 0.0
var low := false
var dead_t := 0.0
var dodge_t := 0.0      # >0 while dashing: strikes miss you
var steer := Vector2.ZERO   # set by the balance bot (and later by network input) instead of the keyboard


func _ready() -> void:
	z_index = 2
	hp = Game.max_hp()
	mana = Game.max_mana()


func tick(dt: float) -> void:
	var ch: Dictionary = w.ch
	if dead_t > 0.0:
		dead_t -= dt
		if dead_t <= 0.0:
			position = Vector2(0, 50)
			hp = Game.max_hp()
			mana = Game.max_mana()
			for e in w.enemies:
				e.aggro = false
		queue_redraw()
		return

	var mv := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if steer != Vector2.ZERO:
		mv = steer
	if w.pointer_down:
		var to := get_global_mouse_position() - position
		if to.length() > 10.0:
			mv = to.normalized()
	if mv.length() > 0.01:
		var spd := 170.0 * (1.2 if ch.el == "wind" else 1.0)
		if w.chased and not Game.has_book():
			spd *= 1.0 + float(GameData.STANCES.moving_speed)
		facing = mv.normalized()
		position += facing * spd * dt
		still = 0.0
	else:
		still += dt
	var lim := GameData.WORLD_RADIUS - 12.0
	if position.length() > lim:
		position = position.normalized() * lim

	dodge_t = maxf(0.0, dodge_t - dt)
	var in_town := position.length() < GameData.TOWN_RADIUS
	hp = minf(Game.max_hp(), hp + (30.0 if in_town else 1.2) * dt)
	var regen: Dictionary = GameData.INK_REGEN
	mana = minf(Game.max_mana(), mana + float(regen.hearth if in_town else regen.field) * dt)
	if in_town:
		w.streak = 0
	if w.streak_t > 0.0:
		w.streak_t -= dt
		if w.streak_t <= 0.0:
			w.streak = 0
	if heat_t > 0.0:
		heat_t -= dt
		if heat_t <= 0.0:
			heat = 0
	hurt_t = maxf(0.0, hurt_t - dt)

	var frac := hp / Game.max_hp()
	if frac < 0.25:
		low = true
	elif low and frac > 0.6:
		low = false
		w.chapter.on_recover()
	queue_redraw()


func _draw() -> void:
	if dead_t > 0.0:
		return
	var C: Dictionary = GameData.COLORS
	var bound := Game.has_book()
	var el_c: Color = C[w.ch.el] if bound else C.none
	if w.hint_flash > 0.0:
		var k: float = w.hint_flash / 1.6
		var pulse := 0.6 + 0.4 * sin(w.time * 14.0)
		draw_arc(Vector2.ZERO, r + 14.0 + (1.0 - k) * 20.0, 0, TAU, 40, Color(C.gilt, 0.5 * k * pulse), 2.0)
	if heat > 0:
		draw_arc(Vector2.ZERO, r + 5.0, 0, TAU, 32, Color(C.fire, 0.25 + heat * 0.1), float(heat))
	var shake := Vector2.ZERO
	var strain: float = w.casting.strain_t / float(GameData.OVERCAST.strain_time)
	if strain > 0.0:
		shake = Vector2(sin(w.time * 47.0), cos(w.time * 39.0)) * 1.5 * strain
	# Health shows on your body: the ink fades and cracks as you get hurt.
	var frac: float = clampf(hp / Game.max_hp(), 0.0, 1.0)
	var body: Color = C.danger if hurt_t > 0.0 else el_c
	body.a = 0.35 + 0.65 * frac
	draw_circle(shake, r, body)
	draw_arc(shake, r, 0, TAU, 32, Color(C.ink, 0.5 + 0.5 * frac), 2.5)
	var cracks := int((1.0 - frac) * 7.0)
	for i in cracks:
		var a0 := i * 2.6 + 1.1
		var mid: Vector2 = shake + Vector2.from_angle(a0) * r * 0.55
		draw_polyline(PackedVector2Array([shake + Vector2.from_angle(a0 + 0.5) * r * 0.15, mid, shake + Vector2.from_angle(a0 - 0.25) * r]), Color(C.ink, 0.7), 1.2)
	if strain > 0.0:
		# Overcast strain: cracks across the body and ink dripping off it.
		for i in 3:
			var a0 := i * 2.1 + 0.4
			draw_line(shake + Vector2.from_angle(a0) * r * 0.2, shake + Vector2.from_angle(a0 + 0.3) * r, Color(C.danger, strain), 1.5)
			var drip := fmod(w.time * 20.0 + i * 7.0, 14.0)
			draw_circle(Vector2(-6 + i * 6, r + drip), 1.6, Color(C.ink, strain * (1.0 - drip / 14.0)))
	if dodge_t > 0.0:
		draw_arc(Vector2.ZERO, r + 4.0, 0, TAU, 24, Color(C.paper, 0.8), 2.0)
	if bound:
		draw_rect(Rect2(11, -6, 9, 12), C.ink)       # your book
		draw_rect(Rect2(11, -6, 2, 12), el_c)
	else:
		draw_circle(facing * (r + 5.0), 4.0, C.ink)  # a bare fist
	Ink.text_c(self, Vector2(0, r + 16), w.ch.name, 13, C.ink)
