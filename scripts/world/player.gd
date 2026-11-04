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
	if w.pointer_down:
		var to := get_global_mouse_position() - position
		if to.length() > 10.0:
			mv = to.normalized()
	if mv.length() > 0.01:
		var spd := 170.0 * (1.2 if ch.el == "wind" else 1.0)
		facing = mv.normalized()
		position += facing * spd * dt
		still = 0.0
	else:
		still += dt
	var lim := GameData.WORLD_RADIUS - 12.0
	if position.length() > lim:
		position = position.normalized() * lim

	var in_town := position.length() < GameData.TOWN_RADIUS
	hp = minf(Game.max_hp(), hp + (30.0 if in_town else 1.2) * dt)
	mana = minf(Game.max_mana(), mana + (25.0 if in_town else 6.0) * dt)
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
	draw_circle(Vector2.ZERO, r, C.danger if hurt_t > 0.0 else el_c)
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, C.ink, 2.5)
	if bound:
		draw_rect(Rect2(11, -6, 9, 12), C.ink)       # your book
		draw_rect(Rect2(11, -6, 2, 12), el_c)
	else:
		draw_circle(facing * (r + 5.0), 4.0, C.ink)  # a bare fist
	Ink.text_c(self, Vector2(0, r + 16), w.ch.name, 13, C.ink)
