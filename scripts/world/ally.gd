extends Node2D
## Mira: an AI stand-in for a second player. She follows you and casts on
## nearby enemies. She uses Water (or Lightning if your book is Water) so
## you can feel element combos. In multiplayer, a real player replaces her.

const Ink := preload("res://scripts/util/ink.gd")

var w
var el := "water"
var r := 11.0
var cd := 1.2
var flash := 0.0


func _ready() -> void:
	z_index = 1
	el = "lightning" if w.ch.el == "water" else "water"


func tick(dt: float) -> void:
	var p = w.player
	var f: Vector2 = p.facing
	var spot: Vector2 = p.position - f * 46.0 + Vector2(f.y, -f.x) * 24.0
	var to := spot - position
	var d := to.length()
	if d > 520.0:
		position = spot
	elif d > 18.0:
		position += to / d * minf(d, (260.0 if d > 120.0 else 190.0) * dt)
	cd -= dt
	flash = maxf(0.0, flash - dt)
	if cd <= 0.0:
		cd = 2.6 if try_cast() else 0.3
	queue_redraw()


func try_cast() -> bool:
	var t = w.nearest(position, 300.0)
	if t == null:
		return false
	var dmg := 12.0 + 3.0 * int(w.ch.level)
	var st: Dictionary
	if el == "water":
		st = {"kind": "bolt", "el": "water", "dmg": dmg, "speed": 480.0, "soak": true, "push": 40.0, "tier": 0}
	else:
		st = {"kind": "chain", "el": "lightning", "dmg": dmg, "jumps": 2, "range": 300.0, "tier": 0}
	w.perform(st, t.position, "ally", 1.0)
	flash = 0.3
	w.chapter.on_ally_cast(t)
	return true


func _draw() -> void:
	var C: Dictionary = GameData.COLORS
	draw_circle(Vector2.ZERO, r, C[el])
	draw_arc(Vector2.ZERO, r, 0, TAU, 32, C.ink, 2.0)
	if flash > 0.0:
		draw_arc(Vector2.ZERO, r + 7.0, 0, TAU, 32, Color(C[el], flash / 0.3 * 0.7), 2.0)
	Ink.text_c(self, Vector2(0, r + 15), "Mira", 12, Color(C.ink, 0.8))
