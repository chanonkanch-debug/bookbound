extends Node2D
## The field. Runs the simulation (spawning, spells, damage) and draws the
## ground and effects. Actors (player, Mira, enemies) draw themselves.
##
## All game rules run here in one place on purpose: when we add multiplayer,
## this is the code that moves to the host/server.

signal quit_to_rite
signal go_to_ceremony   # bare-handed, high enough level, and standing in the Hearth

const Ink := preload("res://scripts/util/ink.gd")
const PlayerScript := preload("res://scripts/world/player.gd")
const EnemyScript := preload("res://scripts/world/enemy.gd")
const AllyScript := preload("res://scripts/world/ally.gd")
const HiddenChapter := preload("res://scripts/world/hidden_chapter.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const BookScript := preload("res://scripts/ui/book_overlay.gd")


## A node that draws with a function from World, so ground and effects can sit
## below and above the actors.
class Drawer extends Node2D:
	var fn: Callable
	func _draw() -> void:
		fn.call(self)


var ch: Dictionary
var C: Dictionary = GameData.COLORS
var player
var ally
var chapter
var hud
var book
var camera: Camera2D
var under: Drawer
var over: Drawer
var actors: Node2D

var enemies: Array = []
var projectiles: Array = []
var zones: Array = []
var rings: Array = []
var splats: Array = []
var texts: Array = []
var chains: Array = []
var delayed: Array = []
var scribbles: Array = []

var cds: Array = [0.0, 0.0, 0.0, 0.0]
var streak := 0
var streak_t := 0.0
var time := 0.0
var hint_flash := 0.0
var awaken_fx := 0.0
var syn_t := 0.0
var mana_warn_t := 0.0
var spawn_t := 0.0
var save_t := 5.0
var paused := false
var pointer_down := false
var last_hit_id := 0        # for the leaning rules before the ceremony
var last_hit_t := -99.0


func _ready() -> void:
	ch = Game.ch
	for i in 900:
		var a := randf() * TAU
		var d := sqrt(randf()) * GameData.WORLD_RADIUS
		scribbles.append({"p": Vector2(cos(a), sin(a)) * d, "a": randf_range(-0.6, 0.6), "l": randf_range(4, 9), "k": randf() < 0.15})

	under = Drawer.new()
	under.fn = _draw_under
	add_child(under)
	actors = Node2D.new()
	add_child(actors)
	over = Drawer.new()
	over.fn = _draw_over
	over.z_index = 5
	add_child(over)

	player = PlayerScript.new()
	player.w = self
	player.position = Vector2(0, 50)
	actors.add_child(player)
	ally = AllyScript.new()
	ally.w = self
	ally.position = Vector2(-40, 60)
	actors.add_child(ally)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.offset = Vector2(155, 0)   # keeps you centred in the area left of the side panel
	player.add_child(camera)
	camera.make_current()

	chapter = HiddenChapter.new(self)
	hud = HudScript.new()
	hud.w = self
	add_child(hud)
	book = BookScript.new()
	book.w = self
	add_child(book)

	for i in 10:
		spawn(true)
	log_msg("%s steps out of the Hearth. Mira (%s) follows." % [ch.name, GameData.ELEMENTS[ally.el].name])
	if not Game.has_book():
		if ceremony_ready():
			log_msg("Your Book Ceremony is ready. Return to the Hearth.")
		else:
			log_msg("You have no book yet. Fight with your bare hands until Lv %d." % GameData.CEREMONY_LEVEL)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_down = event.pressed and not paused


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if Input.is_action_just_pressed("open_book"):
		if book.visible:
			book.close()
		else:
			open_book()
	elif book.visible and Input.is_action_just_pressed("ui_cancel"):
		book.close()
	if not paused:
		for i in 4:
			if Input.is_action_just_pressed("cast_%d" % (i + 1)):
				cast(i)
		_update(dt)
	under.queue_redraw()
	over.queue_redraw()
	hud.refresh(dt)


# ================================================================ Simulation

func _update(dt: float) -> void:
	time += dt
	syn_t -= dt
	mana_warn_t -= dt
	for i in 4:
		if cds[i] > 0.0:
			cds[i] -= dt
	if pointer_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pointer_down = false

	player.tick(dt)
	if ceremony_ready() and player.dead_t <= 0.0 and player.position.length() < GameData.TOWN_RADIUS:
		Game.save_game()
		go_to_ceremony.emit()
		set_process(false)
		return
	ally.tick(dt)

	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = 0.6
		var n := 0
		for e in enemies:
			if e.position.distance_to(player.position) < 900:
				n += 1
		if n < GameData.MAX_ENEMIES_NEARBY:
			spawn(false)

	for e in enemies:
		e.tick(dt)
	_separate_enemies()
	_update_projectiles(dt)
	_update_zones(dt)

	var waiting: Array = []
	for d in delayed:
		d.t -= dt
		if d.t <= 0.0:
			d.fn.call()
		else:
			waiting.append(d)
	delayed = waiting

	var alive: Array = []
	for e in enemies:
		if e.dead or e.position.distance_to(player.position) > 1300:
			e.queue_free()
		else:
			alive.append(e)
	enemies = alive

	for r in rings:
		r.t += dt
	rings = rings.filter(func(r): return r.t < r.life)
	for s in splats:
		s.t += dt
	splats = splats.filter(func(s): return s.t < s.life)
	for t in texts:
		t.age += dt
		t.p.y -= 22.0 * dt
	texts = texts.filter(func(t): return t.age < t.life)
	for c in chains:
		c.t -= dt
	chains = chains.filter(func(c): return c.t > 0.0)
	hint_flash = maxf(0.0, hint_flash - dt)
	awaken_fx = maxf(0.0, awaken_fx - dt)

	save_t -= dt
	if save_t <= 0.0:
		save_t = 5.0
		Game.save_game()


func spawn(initial: bool) -> void:
	for attempt in 5:
		var a := randf() * TAU
		var d := randf_range(240, 560) if initial else randf_range(540, 740)
		var base: Vector2 = Vector2.ZERO if initial else player.position
		var p: Vector2 = base + Vector2(cos(a), sin(a)) * d
		var rd := p.length()
		if rd > GameData.WORLD_RADIUS - 20 or rd < GameData.TOWN_RADIUS + 110:
			continue
		var tier := 0 if rd < 600 else (1 if rd < 1100 else 2)
		if tier > 0 and randf() < 0.2:
			tier -= 1
		var e = EnemyScript.new()
		e.setup(self, tier, p)
		actors.add_child(e)
		enemies.append(e)
		return


func _separate_enemies() -> void:
	var n := enemies.size()
	for i in n:
		var a = enemies[i]
		for j in range(i + 1, n):
			var b = enemies[j]
			var dv: Vector2 = b.position - a.position
			var d := dv.length()
			var m: float = a.r + b.r
			if d > 0.0 and d < m:
				var o := dv / d * (m - d) / 2.0
				a.position -= o
				b.position += o


func _update_projectiles(dt: float) -> void:
	for pj in projectiles:
		pj.p += pj.v * dt
		pj.life -= dt
		for e in enemies:
			if pj.life <= 0.0:
				break
			if e.dead or pj.hit.has(e.get_instance_id()):
				continue
			if pj.p.distance_to(e.position) < e.r + 5.0:
				hit(e, pj.dmg, pj.el, pj.src, String(pj.st.get("move", "")))
				pj.hit.append(e.get_instance_id())
				var st: Dictionary = pj.st
				if st.get("push", 0.0) > 0.0:
					e.knock += pj.v.normalized() * float(st.push) * 2.2
				if st.get("soak", false):
					e.soak = 3.5
				if pj.explode:
					ring(pj.p, 4, 50, 0.3, C[pj.el], 2)
					for o in enemies:
						if o != e and not o.dead and o.position.distance_to(pj.p) < 50.0:
							hit(o, pj.dmg * 0.5, pj.el, pj.src)
				pj.pierce -= 1
				if pj.pierce < 0:
					pj.life = 0.0
	projectiles = projectiles.filter(func(p): return p.life > 0.0)


func _update_zones(dt: float) -> void:
	for z in zones:
		z.t += dt
		z.tt -= dt
		var st: Dictionary = z.st
		for e in enemies:
			if e.dead:
				continue
			var d: float = e.position.distance_to(z.p)
			if d < z.r + e.r:
				if st.get("slow", 0.0) > 0.0:
					e.slow_t = 0.3
					e.slow_f = st.slow
				if st.get("pull", 0.0) > 0.0 and d > 8.0:
					e.position += (z.p - e.position).normalized() * float(st.pull) * dt
		if z.tt <= 0.0:
			z.tt = z.tick
			for e in enemies:
				if not e.dead and e.position.distance_to(z.p) < z.r + e.r:
					hit(e, z.dmg, z.el, z.src)
					if st.get("soak", false):
						e.soak = 3.5
	zones = zones.filter(func(z): return z.t < z.life)


# ================================================================ Combat

func nearest(from: Vector2, max_d: float, exclude: Array = []):
	var best = null
	var bd := max_d
	for e in enemies:
		if e.dead or exclude.has(e):
			continue
		var d: float = from.distance_to(e.position)
		if d < bd:
			bd = d
			best = e
	return best


## Damage one enemy. Element combos (Soaked + X) are applied here.
## `move` is set for bare-hands moves so the hit can count toward a leaning.
func hit(e, base: float, el: String, src: String, move := "") -> void:
	if e.dead:
		return
	if move != "" and src == "player":
		_track_lean(e, move)
	var m := 1.0
	var a: Dictionary = ch.aspect
	if src == "player":
		if ch.el == "fire":
			m *= 1.0 + 0.12 * player.heat
		if a.awakened and a.id == "hunger":
			m *= 1.0 + minf(0.6, 0.04 * streak)
		if a.awakened and a.id == "stillness" and player.still > 0.4:
			m *= 1.2
	if e.soak > 0.0:
		match el:
			"lightning":
				m *= 2.0
				_combo(e, "Conducted x2", el)
			"fire":
				m *= 1.5
				e.soak = 0.0
				_combo(e, "Steam x1.5", el)
			"earth":
				e.slow_t = 2.0
				e.slow_f = 0.4
				_combo(e, "Mud", el)
			"wind":
				for o in enemies:
					if o != e and o.position.distance_to(e.position) < 90.0:
						o.soak = 3.0
				_combo(e, "Spray", el)
	var dmg := maxi(1, roundi(base * m * randf_range(0.9, 1.1)))
	e.hp -= dmg
	e.flash = 0.12
	e.aggro = true
	if src == "ally":
		e.ally_hit = 2.0
	add_text(e.position + Vector2(randf_range(-6, 6), -e.r - 4), str(dmg), C.ink_soft if src == "ally" else C.ink, 13, 0.6)
	if e.hp <= 0:
		kill(e, src)


## Before the ceremony: how you fight quietly leans your future book.
## The rules and numbers are in GameData.LEAN.
func lean(el: String, amount: float) -> void:
	if Game.has_book() or not ch.has("lean"):
		return
	ch.lean[el] = float(ch.lean.get(el, 0.0)) + amount


func _track_lean(e, move: String) -> void:
	var L: Dictionary = GameData.LEAN
	var id: int = e.get_instance_id()
	if player.still >= float(L.planted_time):
		lean("earth", 1.0)
	match move:
		"jab":
			if time - last_hit_t <= float(L.combo_window):
				lean("fire" if id == last_hit_id else "lightning", 1.0)
			last_hit_id = id
			last_hit_t = time
		"shove":
			lean("water", 1.0)


func ceremony_ready() -> bool:
	return not Game.has_book() and int(ch.level) >= GameData.CEREMONY_LEVEL


func _combo(e, label: String, el: String) -> void:
	if syn_t <= 0.0:
		add_text(e.position + Vector2(0, -e.r - 18), label, C[el], 15, 1.1)
		syn_t = 0.4


func kill(e, src: String) -> void:
	e.dead = true
	splats.append({"p": e.position, "r": e.r * 1.5, "t": 0.0, "life": 4.0, "sd": randf() * 9.0})
	streak += 1
	streak_t = 8.0
	chapter.on_kill(e, src)
	gain_xp(e.xp)


func gain_xp(n: int) -> void:
	ch.xp += n
	while ch.xp >= Game.xp_next(ch.level):
		ch.xp -= Game.xp_next(ch.level)
		ch.level += 1
		ch.ink += GameData.INK_PER_LEVEL
		player.hp = Game.max_hp()
		player.mana = Game.max_mana()
		ring(player.position, 10, 120, 0.9, C.gilt, 3)
		add_text(player.position + Vector2(0, -30), "Level %d" % ch.level, C.gilt, 20, 1.6)
		if Game.has_book():
			log_msg("Reached Lv %d. +%d ink to write into your spells." % [ch.level, GameData.INK_PER_LEVEL])
		else:
			log_msg("Reached Lv %d. +%d ink, saved for the book you don't have yet." % [ch.level, GameData.INK_PER_LEVEL])
			var top := Game.top_lean()
			if top != "":
				log_msg(GameData.LEAN_HINTS[top])
			if int(ch.level) == GameData.CEREMONY_LEVEL:
				log_msg("Your Book Ceremony is ready. Return to the Hearth.")
				add_text(player.position + Vector2(0, -52), "Return to the Hearth", C.gilt, 16, 2.5)
		hud.rebuild_spells()
		Game.save_game()


func hurt(d: float) -> void:
	if player.dead_t > 0.0:
		return
	player.hp -= d
	player.hurt_t = 0.25
	if player.hp <= 0.0:
		player.hp = 0.0
		player.dead_t = 2.5
		ch.xp = int(ch.xp * 0.9)
		streak = 0
		player.low = false
		log_msg("You fell. You lost 10% of your XP and wake at the Hearth.")


func _push_soak_slow(e, st: Dictionary, origin: Vector2) -> void:
	if st.get("push", 0.0) > 0.0:
		e.knock += (e.position - origin).normalized() * float(st.push) * 2.2
	if st.get("slow", 0.0) > 0.0:
		e.slow_t = 1.5
		e.slow_f = st.slow
	if st.get("soak", false):
		e.soak = 3.5


## Carries out one spell. `src` is "player" or "ally". Returns false if it fizzled.
func perform(st: Dictionary, target, src: String, mult: float) -> bool:
	var o = ally if src == "ally" else player
	var origin: Vector2 = o.position
	var col: Color = C[st.el]
	var dir: Vector2 = player.facing
	if target != null:
		dir = (target.position - origin).normalized()
	var dmg: float = float(st.dmg) * mult
	var tier: int = int(st.get("tier", 0))
	match st.kind:
		"bolt":
			var n := 5 if tier >= 2 else (3 if tier >= 1 else 1)
			for k in n:
				var ang := dir.angle() + (k - (n - 1) / 2.0) * 0.17
				projectiles.append({
					"p": origin, "v": Vector2.from_angle(ang) * float(st.speed), "life": float(st.get("life", 1.1)),
					"dmg": dmg, "el": st.el, "src": src, "pierce": int(st.get("pierce", 0)),
					"hit": [], "st": st, "explode": tier >= 3,
				})
		"chain":
			if target == null or origin.distance_to(target.position) > float(st.range):
				if src == "player":
					add_text(origin + Vector2(0, -24), "No target", C.ink_soft, 13, 0.8)
				return false
			var done: Array = []
			var from_p := origin
			var cur = target
			for j in int(st.jumps) + 2 * tier + 1:
				if cur == null:
					break
				chains.append({"a": from_p, "b": cur.position, "t": 0.2, "col": col, "wide": false})
				hit(cur, dmg * (0.8 if j > 0 else 1.0), st.el, src)
				done.append(cur)
				from_p = cur.position
				cur = nearest(cur.position, 170.0, done)
		"nova":
			var r: float = float(st.radius) * (1.0 + 0.25 * tier)
			var pulse := func():
				var c: Vector2 = o.position
				ring(c, 8, r, 0.4, col, 3)
				for e in enemies:
					if not e.dead and c.distance_to(e.position) < r + e.r:
						hit(e, dmg, st.el, src, String(st.get("move", "")))
						_push_soak_slow(e, st, c)
			pulse.call()
			if tier >= 3:
				delayed.append({"t": 0.35, "fn": pulse})
		"zone":
			var zp: Vector2 = origin + dir * 80.0
			if target != null:
				zp = origin + dir * minf(origin.distance_to(target.position), float(st.range))
			var zr: float = float(st.radius) * (1.0 + 0.15 * tier)
			zones.append({
				"p": zp, "r": zr, "life": float(st.dur) * (1.0 + 0.3 * tier), "t": 0.0,
				"tick": float(st.get("tick", 0.5)), "tt": 0.0, "dmg": dmg, "st": st, "el": st.el, "src": src,
			})
			ring(zp, 4, zr, 0.35, col, 2)
		"dash":
			var end_p: Vector2 = origin + dir * float(st.dash_len)
			if end_p.length() > GameData.WORLD_RADIUS - 15.0:
				end_p = end_p.normalized() * (GameData.WORLD_RADIUS - 15.0)
			var width := 34.0 + 10.0 * tier
			for e in enemies:
				if e.dead:
					continue
				var closest := Geometry2D.get_closest_point_to_segment(e.position, origin, end_p)
				if e.position.distance_to(closest) < width + e.r:
					hit(e, dmg, st.el, src, String(st.get("move", "")))
					_push_soak_slow(e, {"push": 80.0}, closest)
			chains.append({"a": origin, "b": end_p, "t": 0.25, "col": col, "wide": true})
			o.position = end_p
			ring(end_p, 6, 60, 0.35, col, 2)
	return true


## Cast spell slot i (0–2), or 3 for the hidden Last Page spell.
## Before the ceremony, slots 0–2 are the bare-hands moves.
func cast(i: int) -> void:
	if paused or player.dead_t > 0.0:
		return
	if not Game.has_book():
		_cast_bare(i)
		return
	var a: Dictionary = ch.aspect
	if i == 3:
		if not last_page_ready() or cds[3] > 0.0:
			return
		var prim: Dictionary = Game.spell_stats(ch.spells[0])
		perform({"kind": "nova", "el": ch.el, "dmg": prim.dmg * 3.0 + 40.0, "radius": 200.0, "tier": 0}, null, "player", 1.0)
		ring(player.position, 10, 220, 0.8, C.gilt, 4)
		add_text(player.position + Vector2(0, -34), "Last Page", C.gilt, 20, 1.4)
		cds[3] = 12.0
		return
	if i >= ch.spells.size() or cds[i] > 0.0:
		return
	var st: Dictionary = Game.spell_stats(ch.spells[i])
	var still: bool = player.still > 0.4
	var free: bool = a.awakened and a.id == "stillness" and still
	var cost: float = 0.0 if free else float(st.mana)
	if player.mana < cost:
		if mana_warn_t <= 0.0:
			add_text(player.position + Vector2(0, -24), "Out of mana", C.water, 13, 0.8)
			mana_warn_t = 0.8
		return
	var target = nearest(player.position, 460.0)
	if not perform(st, target, "player", 1.0):
		return
	player.mana -= cost
	cds[i] = st.cd
	if ch.el == "fire":
		player.heat = mini(5, player.heat + 1)
		player.heat_t = 2.5
	chapter.on_cast(still)


func _cast_bare(i: int) -> void:
	if i >= GameData.BARE_HANDS.size() or cds[i] > 0.0:
		return
	var st: Dictionary = Game.bare_stats(i)
	if player.mana < float(st.mana):
		if mana_warn_t <= 0.0:
			add_text(player.position + Vector2(0, -24), "Out of mana", C.water, 13, 0.8)
			mana_warn_t = 0.8
		return
	var target = nearest(player.position, 460.0)
	if st.move == "sidestep" and nearest(player.position, float(GameData.LEAN.dash_near)) != null:
		lean("wind", 1.0)
	if st.move == "sidestep":
		player.still = 0.0   # a dash is movement, so it never counts as standing your ground
	if not perform(st, target, "player", 1.0):
		return
	player.mana -= float(st.mana)
	cds[i] = st.cd


func last_page_ready() -> bool:
	var a: Dictionary = ch.aspect
	return a.awakened and a.id == "lastpage" and player.dead_t <= 0.0 and player.hp / Game.max_hp() < 0.3


func spend_ink(i: int) -> void:
	var s: Dictionary = ch.spells[i]
	if ch.ink < 1 or s.lvl >= Game.max_spell_level():
		return
	var tier_before := int(s.lvl / 4.0)
	s.lvl += 1
	ch.ink -= 1
	if int(s.lvl / 4.0) > tier_before:
		log_msg("%s evolved into %s." % [GameData.SPELLS[ch.el][s.i].name, Game.spell_name(s)])
		ring(player.position, 10, 90, 0.7, C[ch.el], 3)
	hud.rebuild_spells()
	Game.save_game()


# ================================================================ Book, hints, log

func open_book() -> void:
	if paused:
		return
	if not Game.has_book():
		if ceremony_ready():
			log_msg("You have no book yet. Your ceremony is waiting at the Hearth.")
		else:
			log_msg("You have no book yet. It will find you at Lv %d." % GameData.CEREMONY_LEVEL)
		return
	var awakened_now: bool = chapter.try_awaken()
	paused = true
	pointer_down = false
	book.open(awakened_now)
	if awakened_now:
		awaken_fx = 2.5
		log_msg("Your book revealed a hidden chapter: %s." % GameData.ASPECTS[ch.aspect.id].name)
		hud.refresh_margins(true)


func on_hint(_text: String) -> void:
	hint_flash = 1.6
	hud.refresh_margins(true)
	hud.stir_book_button()


func log_msg(t: String) -> void:
	hud.add_log(t)


func ring(p: Vector2, r0: float, r1: float, life: float, col: Color, w: float) -> void:
	rings.append({"p": p, "r0": r0, "r1": r1, "t": 0.0, "life": life, "col": col, "w": w})


func add_text(p: Vector2, s: String, col: Color, size: int, life: float) -> void:
	texts.append({"p": p, "s": s, "col": col, "size": size, "life": life, "age": 0.0})


func give_up_character() -> void:
	Game.delete_save()
	Game.ch = {}
	quit_to_rite.emit()


# Designer tools (F1 panel)
func dev_complete_trigger() -> void:
	if not Game.has_book():
		return
	var a: Dictionary = ch.aspect
	while not a.awakened and a.progress < a.need:
		chapter.progress()


# ================================================================ Drawing

func _view_rect() -> Rect2:
	var c := camera.get_screen_center_position()
	var half := get_viewport_rect().size / 2.0
	return Rect2(c - half - Vector2(20, 20), half * 2.0 + Vector2(40, 40))


func _draw_under(d: Node2D) -> void:
	var view := _view_rect()
	var soft: Color = C.ink_soft
	for s in scribbles:
		if not view.has_point(s.p):
			continue
		var col := Color(soft, 0.35 if s.k else 0.18)
		if s.k:
			d.draw_arc(s.p, s.l * 0.4, 0, TAU, 10, col, 1.2)
		else:
			d.draw_line(s.p, s.p + Vector2(sin(s.a) * s.l * 0.5, -s.l), col, 1.2)
			d.draw_line(s.p + Vector2(4, 0), s.p + Vector2(4 + sin(s.a + 0.4) * s.l * 0.4, -s.l * 0.8), col, 1.2)
	for r in [600.0, 1100.0]:
		Ink.dashed_circle(d, Vector2.ZERO, r, Color(soft, 0.35), 1.0)
	d.draw_arc(Vector2.ZERO, GameData.WORLD_RADIUS, 0, TAU, 256, Color(soft, 0.6), 2.0)

	var town := GameData.TOWN_RADIUS
	d.draw_circle(Vector2.ZERO, town, Color(C.gilt, 0.1))
	d.draw_arc(Vector2.ZERO, town, 0, TAU, 96, Color(C.gilt, 0.8), 2.0)
	Ink.text_c(d, Vector2(0, -town + 32), "The Hearth", 20, Color(C.gilt, 0.85))
	d.draw_colored_polygon(Ink.blob(Vector2.ZERO, 9.0, 1.0, time * 1.5), C.fire)

	for s in splats:
		d.draw_colored_polygon(Ink.blob(s.p, s.r, s.sd, 0.0), Color(C.ink, 0.22 * (1.0 - s.t / s.life)))
	for z in zones:
		var f: float = minf(1.0, (1.0 - z.t / z.life) * 3.0)
		d.draw_circle(z.p, z.r, Color(C[z.el], 0.16 * f))
		Ink.dashed_circle(d, z.p, z.r, Color(C[z.el], 0.6 * f), 1.5, time * 0.5)


func _draw_over(d: Node2D) -> void:
	for pj in projectiles:
		var col: Color = C[pj.el]
		d.draw_line(pj.p, pj.p - pj.v * 0.04, Color(col, 0.35), 3.0)
		d.draw_circle(pj.p, 4.0 if pj.src == "ally" else 5.0, col)
	for c in chains:
		var al := minf(1.0, c.t * 6.0)
		if c.wide:
			d.draw_line(c.a, c.b, Color(c.col, al * 0.4), 6.0)
		else:
			d.draw_polyline(Ink.jag(c.a, c.b), Color(c.col, al), 2.5)
	for r in rings:
		var k: float = r.t / r.life
		d.draw_arc(r.p, lerpf(r.r0, r.r1, k), 0, TAU, 48, Color(r.col, 1.0 - k), r.w)
	if awaken_fx > 0.0:
		var k := 1.0 - awaken_fx / 2.5
		for i in 3:
			var kk := fmod(k + i * 0.18, 1.0)
			d.draw_arc(player.position, 20.0 + kk * 260.0, 0, TAU, 64, Color(C.gilt, (1.0 - kk) * 0.8), 3.0)
	for t in texts:
		Ink.text_c(d, t.p, t.s, t.size, Color(t.col, 1.0 - t.age / t.life))
