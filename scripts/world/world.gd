extends Node2D
## The field. Runs the simulation (spawning, spells, damage) and draws the
## ground and effects. Actors (player, Mira, enemies) draw themselves.
##
## All game rules run here in one place on purpose: when we add multiplayer,
## this is the code that moves to the host/server.

signal quit_to_rite
signal go_to_ceremony   # bare-handed, high enough level, and resting in the Hearth

const Ink := preload("res://scripts/util/ink.gd")
const PlayerScript := preload("res://scripts/world/player.gd")
const EnemyScript := preload("res://scripts/world/enemy.gd")
const AllyScript := preload("res://scripts/world/ally.gd")
const HiddenChapter := preload("res://scripts/world/hidden_chapter.gd")
const Casting := preload("res://scripts/world/casting.gd")
const Terrain := preload("res://scripts/world/terrain.gd")
const Discovery := preload("res://scripts/world/discovery.gd")
const Hands := preload("res://scripts/world/hands.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const BookScript := preload("res://scripts/ui/book_overlay.gd")
const DesignerScript := preload("res://scripts/ui/designer_panel.gd")
const JournalScript := preload("res://scripts/ui/journal_overlay.gd")
const MapScript := preload("res://scripts/ui/map_overlay.gd")
const RestScript := preload("res://scripts/ui/rest_overlay.gd")


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
var casting
var terrain
var discovery
var hands
var hud
var book
var designer
var journal_ui
var map_ui
var rest_ui
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

var last_page_cd := 0.0
var read_held := false      # the read key is down (set from input, or by the balance bot)
var last_page_held := false # the Last Page key is down
var bot_aim = null          # a Vector2 set by the balance bot instead of the mouse
var aim_mouse := false      # true once the mouse has moved; keyboard/gamepad players aim where they face
var resting := false        # Phase 2: levels are only written when you rest
var rest_t := 0.0
var rest_need := 0.0
var rest_at_fire := false
var rest_held := false      # the rest key is down (set from input, or by the balance bot)
var rest_pressed := false   # the rest key was just pressed this frame
var rest_fx := 0.0          # >0 just after a rest was interrupted, for the visuals
var auto_rest_ui := false   # the balance bot skips the end-of-rest screens and writes ink evenly
var nudge_clock := {}
var nudge_id := ""
var nudge_t := 0.0
var streak := 0
var streak_t := 0.0
var time := 0.0
var hint_flash := 0.0
var awaken_fx := 0.0
var syn_t := 0.0
var spawn_t := 0.0
var save_t := 5.0
var paused := false
var pointer_down := false
var last_hit_id := 0        # for the playstyle signals before the ceremony
var last_hit_t := -99.0
var chain_len := 0          # hits in a row on the same enemy
var recent_hits: Array = [] # [time, enemy id] of your recent hits, for "spread"
var action_hits := 0        # enemies caught by the current Shove or Sidestep
var chased := false         # an enemy is chasing you (wind signals and stance)
var last_pos := Vector2.ZERO
var kite_dist := 0.0
# Bare hands growth (see hands.gd)
var last_move := ""         # the last bare-hands move you used
var last_move_t := -99.0
var flank_target = null     # the monster a Flank Step is circling
var clean_id := 0           # the monster you're landing clean Jabs on ("untouched" secret)
var clean_n := 0
var brace_t := 0.0          # Brace: blows from the front are turned aside
var brace_dir := Vector2.RIGHT
var decoy_t := 0.0          # Sidestep decoy: monsters chase this instead of you
var decoy_p := Vector2.ZERO


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
	player.add_child(camera)
	camera.make_current()

	chapter = HiddenChapter.new(self)
	casting = Casting.new(self)
	terrain = Terrain.new()
	discovery = Discovery.new(self)
	hands = Hands.new(self)
	hud = HudScript.new()
	hud.w = self
	add_child(hud)
	book = BookScript.new()
	book.w = self
	add_child(book)
	designer = DesignerScript.new()
	designer.w = self
	add_child(designer)
	journal_ui = JournalScript.new()
	journal_ui.w = self
	add_child(journal_ui)
	map_ui = MapScript.new()
	map_ui.w = self
	add_child(map_ui)
	rest_ui = RestScript.new()
	rest_ui.w = self
	add_child(rest_ui)
	if Game.has_book() and not ch.ui.get("book", false):
		unlock("book")

	for i in int(GameData.MONSTERS.initial):
		spawn(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_down = event.pressed and not paused
	if event is InputEventMouseMotion:
		aim_mouse = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.3:
		aim_mouse = false


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if Input.is_action_just_pressed("designer_view"):
		designer.toggle()
	if Input.is_action_just_pressed("open_book"):
		if book.visible:
			book.close()
		else:
			open_book()
	elif Input.is_action_just_pressed("journal"):
		if journal_ui.visible:
			journal_ui.close_journal()
		elif not paused and ch.ui.get("journal", false):
			ch.opened.journal = true
			journal_ui.open()
	elif Input.is_action_just_pressed("map"):
		if map_ui.visible:
			map_ui.close_map()
		elif not paused and ch.ui.get("map", false):
			map_ui.open()
	elif Input.is_action_just_pressed("ui_cancel"):
		if book.visible:
			book.close()
		elif journal_ui.visible:
			journal_ui.close_journal()
		elif map_ui.visible:
			map_ui.close_map()
	designer.tick(dt)
	if not paused:
		rest_held = Input.is_action_pressed("rest")
		rest_pressed = Input.is_action_just_pressed("rest")
		for i in 3:
			if Input.is_action_just_pressed("page_%d" % (i + 1)):
				casting.turn_to(i)
		if not Game.has_book():
			# Learned moves sit on keys 4 to 6 (4 is the Last Page once you have a book).
			if Input.is_action_just_pressed("cast_4"):
				casting.turn_to(3)
			for i in [4, 5]:
				if Input.is_action_just_pressed("page_%d" % (i + 1)):
					casting.turn_to(i)
		if Input.is_action_just_pressed("page_prev"):
			casting.turn_by(-1)
		if Input.is_action_just_pressed("page_next"):
			casting.turn_by(1)
		read_held = Input.is_action_pressed("read")
		last_page_held = Input.is_action_pressed("cast_4") and Game.has_book()
		_update(dt)
	under.queue_redraw()
	over.queue_redraw()
	hud.refresh(dt)


# ================================================================ Simulation

func _update(dt: float) -> void:
	time += dt
	syn_t -= dt
	last_page_cd = maxf(0.0, last_page_cd - dt)
	if pointer_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		pointer_down = false

	player.tick(dt)
	brace_t = maxf(0.0, brace_t - dt)
	decoy_t = maxf(0.0, decoy_t - dt)
	casting.tick(dt, (read_held or last_page_held) and not resting, 3 if last_page_held else -1)
	if not Game.has_book():
		_track_movement()
	_tick_rest(dt)
	rest_pressed = false
	_tick_unlocks()
	_tick_nudges(dt)
	ally.tick(dt)

	spawn_t -= dt
	if spawn_t <= 0.0:
		spawn_t = float(GameData.MONSTERS.spawn_every)
		var n := 0
		for e in enemies:
			if e.position.distance_to(player.position) < 900:
				n += 1
		if n < int(GameData.MONSTERS.max_nearby):
			spawn(false)

	for e in enemies:
		e.tick(dt)
	terrain.tick(dt)
	_terrain_effects(dt)
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
		if e.behavior == "pair":   # Inklings come in twos
			var e2 = EnemyScript.new()
			e2.setup(self, tier, p + Vector2.from_angle(randf() * TAU) * 30.0)
			e2.side = -1.0
			e.partner = e2
			e2.partner = e
			actors.add_child(e2)
			enemies.append(e2)
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
				if a.crash_t > 0.0 or b.crash_t > 0.0:
					_crash(a, b)


func _update_projectiles(dt: float) -> void:
	for pj in projectiles:
		pj.p += pj.v * dt
		pj.life -= dt
		if pj.el == "fire":
			ignite_at(pj.p, 4.0)
		elif pj.el == "wind":
			_wind_through_fire(pj.p, pj.v)
		for e in enemies:
			if pj.life <= 0.0:
				break
			if e.dead or pj.hit.has(e.get_instance_id()):
				continue
			if pj.p.distance_to(e.position) < e.r + 5.0:
				_secret_on_hit(e, pj.st, pj.src)
				hit(e, pj.dmg, pj.el, pj.src, String(pj.st.get("move", "")))
				pj.hit.append(e.get_instance_id())
				var st: Dictionary = pj.st
				if st.get("push", 0.0) > 0.0:
					e.knock += pj.v.normalized() * float(st.push) * 2.2
					e.interrupt()
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
		_move_zone(z, dt)
		for e in enemies:
			if e.dead:
				continue
			var d: float = e.position.distance_to(z.p)
			if z.get("wall", false) and d < z.r + e.r and d > 0.0:
				# Rampart on stones: nothing gets in.
				e.position = z.p + (e.position - z.p) / d * (z.r + e.r)
				continue
			if d < z.r + e.r:
				if st.get("slow", 0.0) > 0.0:
					e.slow_t = 0.3
					e.slow_f = st.slow
				if st.get("pull", 0.0) > 0.0 and d > 8.0:
					e.position += (z.p - e.position).normalized() * float(st.pull) * dt
		if z.tt <= 0.0:
			z.tt = z.tick
			var forked := false
			for e in enemies:
				if not e.dead and e.position.distance_to(z.p) < z.r + e.r:
					if not forked and String(st.get("name", "")) == "Storm Rod" and e.soak > 0.0:
						forked = true
						_storm_fork(e, z)
					hit(e, z.dmg, z.el, z.src)
					if st.get("soak", false):
						e.soak = 3.5
			if float(z.get("hurts_player", 0.0)) > 0.0 and player.position.distance_to(z.p) < z.r + player.r:
				hurt(float(z.hurts_player))
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
	var m := 1.0
	var force_stagger := 0.0
	if move != "" and src == "player":
		var hm: Array = _hand_hit(e, move, base)
		m *= float(hm[0])
		force_stagger = float(hm[1])
		_track_hit(e, move)
		if player.still >= float(GameData.LEAN.planted_time):
			m *= 1.0 + float(GameData.STANCES.planted_dmg)
		if player.hp / Game.max_hp() < float(GameData.LEAN.brink_hp):
			m *= 1.0 + float(GameData.STANCES.brink_dmg)
	if src == "player" and e.first_hit_t < 0.0:
		e.first_hit_t = time
	m *= _affinity(e, el, src)
	if e.dead:
		return
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
	if dmg >= e.max_hp * float(GameData.MONSTERS.interrupt_frac) or force_stagger > 0.0:
		if e.interrupt() and src == "player":
			journal("first_interrupt")
			hands.lesson(e)
	if force_stagger > 0.0 and not e.dead:
		e.state = "stagger"
		e.state_t = maxf(e.state_t if e.state == "stagger" else 0.0, force_stagger)
	e.aggro = true
	if src == "ally":
		e.ally_hit = float(GameData.CHAPTER_TUNING.echo_window)
	# Show, don't tell: the size of the ink splatter says how hard it hit.
	splats.append({"p": e.position + Vector2(randf_range(-4, 4), randf_range(-4, 4)), "r": 3.0 + sqrt(float(dmg)) * 1.5,
		"t": 0.0, "life": 1.6, "sd": randf() * 9.0, "a": 0.5 if src == "player" else 0.3})
	if Game.show_numbers():
		add_text(e.position + Vector2(randf_range(-6, 6), -e.r - 4), str(dmg), C.ink_soft if src == "ally" else C.ink, 13, 0.6)
	if e.hp <= 0:
		kill(e, src)


## Before the ceremony: how you fight quietly shapes your future book.
## Each signal belongs to one element; see SIGNALS and LEAN in game_data.gd.
func signal_lean(sname: String, amount := 1.0) -> void:
	if Game.has_book():
		return
	if not ch.has("signals"):
		ch.signals = {}
	ch.signals[sname] = float(ch.signals.get(sname, 0.0)) + amount


## Signals from one of your bare-hands hits landing.
func _track_hit(e, move: String) -> void:
	var L: Dictionary = GameData.LEAN
	var id: int = e.get_instance_id()
	if player.still >= float(L.planted_time):
		signal_lean("planted")
	elif player.still <= 0.05:
		signal_lean("moving_hit")
	if player.hp / Game.max_hp() < float(L.brink_hp):
		signal_lean("brink")
	var crowd := 0
	for o in enemies:
		if not o.dead and o.position.distance_to(player.position) < float(L.crowd_radius):
			crowd += 1
	if crowd >= int(L.crowd_count):
		signal_lean("crowd")
	recent_hits.append([time, id])
	while not recent_hits.is_empty() and time - float(recent_hits[0][0]) > float(L.spread_window):
		recent_hits.pop_front()
	var distinct := {}
	for h in recent_hits:
		distinct[h[1]] = true
	if distinct.size() >= int(L.spread_count):
		signal_lean("spread")
	match move:
		"jab":
			if id == last_hit_id and time - last_hit_t <= float(L.combo_window):
				chain_len += 1
			else:
				chain_len = 1
			if chain_len >= 3 and player.still < float(L.planted_time):
				signal_lean("chain")
			# Switching quickly to a new enemy while the last one is still standing.
			var prev = instance_from_id(last_hit_id) if last_hit_id != 0 else null
			if id != last_hit_id and time - last_hit_t <= float(L.snap_window) and prev != null and not prev.dead:
				signal_lean("snap")
		"shove":
			signal_lean("push")
			action_hits += 1
		"sidestep":
			action_hits += 1
	last_hit_id = id
	last_hit_t = time


## Signals from how you move: distance covered while something chases you.
func _track_movement() -> void:
	var L: Dictionary = GameData.LEAN
	chased = false
	for e in enemies:
		if e.aggro and not e.dead and e.position.distance_to(player.position) < float(L.chase_range):
			chased = true
			break
	var step: Vector2 = player.position - last_pos
	last_pos = player.position
	var moved := step.length()
	if not chased or moved <= 0.0 or moved > 60.0:   # ignore standing and teleports (respawn, dashes)
		return
	# Only movement away from (or around) the nearest chaser counts, not running at it.
	var near = nearest(player.position, float(L.chase_range))
	if near != null and step.normalized().dot((near.position - player.position).normalized()) < 0.3:
		kite_dist += moved
		while kite_dist >= float(L.kite_step):
			kite_dist -= float(L.kite_step)
			signal_lean("kite")


## A vague journal line about the player's current leaning. Never shows numbers.
func lean_hint() -> String:
	var top := Game.top_lean()
	if top == "":
		return GameData.LEAN_UNSURE
	if Game.lean_torn():
		return GameData.LEAN_TORN
	var lines: Array = GameData.LEAN_HINTS[top]
	return lines[(int(ch.level) - 2) % lines.size()]


func ceremony_ready() -> bool:
	return not Game.has_book() and int(ch.level) >= GameData.CEREMONY_LEVEL


func _combo(e, label: String, el: String) -> void:
	if syn_t <= 0.0:
		ring(e.position, e.r, e.r + 22.0, 0.45, C[el], 2.5)
		if Game.show_numbers():
			add_text(e.position + Vector2(0, -e.r - 18), label, C[el], 15, 1.1)
		syn_t = 0.4


func kill(e, src: String) -> void:
	e.dead = true
	if src == "player":
		if streak >= int(GameData.LEAN.streak_kills):
			signal_lean("streak_kill")
		if not e.bit_player:
			signal_lean("clean_kill")
	splats.append({"p": e.position, "r": e.r * 1.5, "t": 0.0, "life": 4.0, "sd": randf() * 9.0, "a": 0.22})
	if src == "player":
		unlock("journal")
		journal("first_kill")
	streak += 1
	streak_t = float(GameData.STREAK_WINDOW)
	chapter.on_kill(e, src)
	gain_xp(e.xp)


## XP is earned quietly. Levels are only written when you rest (see finish_rest).
func gain_xp(n: int) -> void:
	ch.xp += n


## A monster's strike lands (or is dodged mid-dash).
func enemy_strike(e) -> void:
	if player.dead_t > 0.0:
		return
	if decoy_t > 0.0 and e.position.distance_to(decoy_p) < e.position.distance_to(player.position):
		# It bit the ink you left behind.
		decoy_t = 0.0
		ring(decoy_p, 6, 26, 0.3, C.ink_soft, 1.5)
		hands.lesson(e)
		return
	if player.dodge_t > 0.0:
		ring(player.position, 6, 30, 0.3, C.ink_soft, 1.5)
		journal("first_dodge")
		hands.lesson(e)
		if last_move == "sidestep":
			hands.use("sidestep")
		return
	e.bit_player = true
	var d: float = e.dmg
	if brace_t > 0.0:
		var B: Dictionary = GameData.LEARNED_MOVES.brace
		var from: Vector2 = (e.position - player.position).normalized()
		if absf(wrapf(from.angle() - brace_dir.angle(), -PI, PI)) <= float(B.brace_arc) / 2.0:
			d *= 1.0 - float(B.brace_guard)
			e.state = "stagger"
			e.state_t = float(B.brace_stagger)
			e.knock += from * 160.0
			ring(player.position + brace_dir * 18.0, 6, 30, 0.3, C.ink, 2.5)
			hands.lesson(e)
	hurt(d)


func hurt(d: float) -> void:
	if player.dead_t > 0.0:
		return
	clean_n = 0
	if player.still >= float(GameData.LEAN.planted_time) and not Game.has_book():
		signal_lean("absorb", d / 10.0)
		d *= 1.0 - float(GameData.STANCES.planted_guard)
	player.hp -= d
	player.hurt_t = 0.25
	casting.on_hurt()
	if resting:
		_break_rest()
	if player.hp > 0.0 and player.hp / Game.max_hp() < float(GameData.UNLOCK.near_death):
		unlock("journal")
		journal("near_death")
	if player.hp <= 0.0:
		_die()


func _die() -> void:
	player.hp = 0.0
	player.dead_t = 2.5
	ch.xp = int(ch.xp * 0.9)
	streak = 0
	player.low = false
	casting.reading = false
	resting = false
	unlock("journal")
	journal("first_death")


## Overcasting: the missing ink was paid in health (see casting.gd).
func on_overcast(_hp_cost: float) -> void:
	player.hurt_t = 0.15
	journal("first_overcast")


func on_fizzle() -> void:
	journal("first_fizzle")


func _push_soak_slow(e, st: Dictionary, origin: Vector2) -> void:
	if st.get("push", 0.0) > 0.0:
		e.knock += (e.position - origin).normalized() * float(st.push) * 2.2
		e.interrupt()
	if st.get("slow", 0.0) > 0.0:
		e.slow_t = 1.5
		e.slow_f = st.slow
	if st.get("soak", false):
		e.soak = 3.5


## Where the player is aiming: the mouse cursor, or straight ahead without a mouse.
## The balance bot sets bot_aim instead.
func aim_point() -> Vector2:
	if bot_aim != null:
		return bot_aim
	if aim_mouse:
		return get_global_mouse_position()
	return player.position + player.facing * 220.0


## The enemy a chain spell jumps to first: closest to the aim point, or the first
## one along the aim line (see AIM in game_data.gd).
func chain_target(origin: Vector2, aim: Vector2, max_range: float):
	var best = null
	var bd := float(GameData.AIM.chain_snap)
	for e in enemies:
		if e.dead or origin.distance_to(e.position) > max_range:
			continue
		var d: float = aim.distance_to(e.position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		return best
	var dir := (aim - origin).normalized()
	var bdist := max_range
	for e in enemies:
		if e.dead:
			continue
		var to: Vector2 = e.position - origin
		if to.length() < bdist and absf(dir.angle_to(to)) < float(GameData.AIM.chain_cone):
			bdist = to.length()
			best = e
	return best


## Carries out one spell aimed at `aim` (a world position). `src` is "player" or "ally".
## Returns false if it found nothing to hit (chains only; the ink is still spent).
## Phase 3: the ground changes some spells (puddles, stones, open ground), and each
## spell has one hidden secret (SECRETS in game_data.gd).
func perform(st_in: Dictionary, aim: Vector2, src: String, mult: float) -> bool:
	var st: Dictionary = st_in.duplicate()
	var o = ally if src == "ally" else player
	var origin: Vector2 = o.position
	var col: Color = C[st.el]
	var dir: Vector2 = (aim - origin).normalized() if aim.distance_to(origin) > 1.0 else player.facing
	var dmg: float = float(st.dmg) * mult
	var tier: int = int(st.get("tier", 0))
	var sname: String = String(st.get("name", ""))
	var mine: bool = src == "player"
	var T: Dictionary = GameData.TERRAIN
	var in_puddle: bool = terrain.at(origin, "puddle") != null
	var on_stone: bool = terrain.at(origin, "stone") != null
	var on_open: bool = terrain.at(origin, "open") != null
	if st.el == "water" and in_puddle and st.kind in ["bolt", "nova"]:
		if st.kind == "bolt":
			dmg *= float(T.puddle_grow)
		else:
			st.radius = float(st.radius) * float(T.puddle_grow)
		_saw_terrain_if(mine, "puddle_grow")
	if st.el == "wind" and on_open:
		match st.kind:
			"bolt":
				st.life = float(st.get("life", 1.1)) * float(T.open_reach)
			"zone":
				st.range = float(st.range) * float(T.open_reach)
			"dash":
				st.dash_len = float(st.dash_len) * float(T.open_reach)
		_saw_terrain_if(mine, "open_reach")
	match st.kind:
		"bolt":
			var n := 5 if tier >= 2 else (3 if tier >= 1 else 1)
			var spread := 0.17
			if sname == "Tide Shot" and in_puddle and mine:
				n += 2
				spread = float(GameData.SECRETS["Tide Shot"].spread)
				discovery.secret(sname)
			if sname == "Stone Shard" and on_stone and mine:
				st.pierce = int(st.get("pierce", 0)) + int(GameData.SECRETS["Stone Shard"].pierce)
				dmg *= float(GameData.SECRETS["Stone Shard"].dmg)
				discovery.secret(sname)
			for k in n:
				var ang := dir.angle() + (k - (n - 1) / 2.0) * spread
				projectiles.append({
					"p": origin, "v": Vector2.from_angle(ang) * float(st.speed), "life": float(st.get("life", 1.1)),
					"dmg": dmg, "el": st.el, "src": src, "pierce": int(st.get("pierce", 0)),
					"hit": [], "st": st, "explode": tier >= 3,
				})
		"chain":
			var target = chain_target(origin, aim, float(st.range))
			if target == null:
				# The spark crackles out along the aim line and grounds itself.
				chains.append({"a": origin, "b": origin + dir * minf(float(st.range), origin.distance_to(aim)), "t": 0.2, "col": col, "wide": false})
				return false
			var pool = terrain.at(target.position, "puddle")
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
			if sname == "Spark" and mine and pool != null:
				# Secret: in water, the spark finds everything standing in that puddle.
				var any := false
				for e in enemies:
					if not e.dead and not done.has(e) and e.position.distance_to(pool.p) < pool.r + e.r:
						chains.append({"a": target.position, "b": e.position, "t": 0.25, "col": col, "wide": false})
						hit(e, dmg * 0.8, st.el, src)
						any = true
				if any or done.size() > 0:
					discovery.secret(sname)
		"nova":
			var r: float = float(st.radius) * (1.0 + 0.25 * tier)
			if sname == "Arc Nova" and in_puddle and mine:
				r *= float(GameData.SECRETS["Arc Nova"].grow)
				hurt(Game.max_hp() * float(GameData.SECRETS["Arc Nova"].self_dmg))
				discovery.secret(sname)
			var crash: bool = sname == "Undertow" and mine
			var pulse := func():
				var c: Vector2 = o.position
				ring(c, 8, r, 0.4, col, 3)
				for e in enemies:
					if not e.dead and c.distance_to(e.position) < r + e.r:
						hit(e, dmg, st.el, src, String(st.get("move", "")))
						_push_soak_slow(e, st, c)
						if crash:
							e.crash_t = float(GameData.SECRETS["Undertow"].window)
							e.crash_kind = "undertow"
							e.crash_dmg = dmg * float(GameData.SECRETS["Undertow"].dmg)
				if st.el == "fire":
					ignite_at(c, r)
			pulse.call()
			if tier >= 3:
				delayed.append({"t": 0.35, "fn": pulse})
			if sname == "Quake" and mine and _inside_own(origin, "Rampart"):
				var Q: Dictionary = GameData.SECRETS["Quake"]
				for k in int(Q.echoes):
					delayed.append({"t": float(Q.gap) * (k + 1), "fn": pulse})
				discovery.secret(sname)
			if sname == "Flare Ring" and mine and player.heat >= 4:
				var F: Dictionary = GameData.SECRETS["Flare Ring"]
				_add_zone(o.position, r, float(F.dur), 0.5, dmg * float(F.dmg), {"el": "fire", "kind": "zone", "name": "Flare Ring fire"}, src)
				discovery.secret(sname)
		"zone":
			var zp: Vector2 = origin + dir * minf(origin.distance_to(aim), float(st.range))
			var zr: float = float(st.radius) * (1.0 + 0.15 * tier)
			var life: float = float(st.dur) * (1.0 + 0.3 * tier)
			var z_extra := {}
			if st.el == "water" and terrain.at(zp, "puddle") != null:
				zr *= float(T.puddle_grow)
				_saw_terrain_if(mine, "puddle_grow")
				if sname == "Still Pool" and mine:
					st.slow = float(GameData.SECRETS["Still Pool"].slow)
					discovery.secret(sname)
			if st.el == "earth" and terrain.at(zp, "stone") != null:
				life *= float(T.stone_last)
				_saw_terrain_if(mine, "stone_last")
				if sname == "Rampart" and mine:
					z_extra.wall = true
					discovery.secret(sname)
			if sname == "Vortex" and mine and terrain.at(zp, "open") != null:
				z_extra.walk = float(GameData.SECRETS["Vortex"].speed)
				life *= float(GameData.SECRETS["Vortex"].last)
				discovery.secret(sname)
			if sname == "Pyre" and mine:
				for oz in zones:
					if oz.src == "player" and String(oz.st.get("name", "")) == "Pyre" and oz.p.distance_to(zp) < oz.r:
						# Secret: two pyres become one great fire.
						oz.t = oz.life
						zr *= float(GameData.SECRETS["Pyre"].grow)
						life *= float(GameData.SECRETS["Pyre"].last)
						zp = (zp + oz.p) / 2.0
						discovery.secret(sname)
						break
			var z := _add_zone(zp, zr, life, float(st.get("tick", 0.5)), dmg, st, src)
			z.merge(z_extra, true)
			if st.el == "fire":
				ignite_at(zp, zr)
		"dash":
			var end_p: Vector2 = origin + dir * float(st.dash_len)
			if end_p.length() > GameData.WORLD_RADIUS - 15.0:
				end_p = end_p.normalized() * (GameData.WORLD_RADIUS - 15.0)
			var width := 34.0 + 10.0 * tier
			var through := 0
			for e in enemies:
				if e.dead:
					continue
				var closest := Geometry2D.get_closest_point_to_segment(e.position, origin, end_p)
				if e.position.distance_to(closest) < width + e.r:
					hit(e, dmg, st.el, src, String(st.get("move", "")))
					_push_soak_slow(e, {"push": float(st.get("push", 80.0))}, closest)
					through += 1
			chains.append({"a": origin, "b": end_p, "t": 0.25, "col": col, "wide": true})
			o.position = end_p
			if mine:
				player.facing = dir
			if src == "player":
				player.dodge_t = float(GameData.DODGE_TIME)
			ring(end_p, 6, 60, 0.35, col, 2)
			if sname == "Cyclone Step" and mine and through >= int(GameData.SECRETS["Cyclone Step"].count):
				var CS: Dictionary = GameData.SECRETS["Cyclone Step"]
				_add_zone(end_p, float(CS.radius), float(CS.dur), 0.5, dmg * 0.2, {"el": "wind", "kind": "zone", "name": "whirlwind", "pull": 110.0}, src)
				discovery.secret(sname)
	return true


func _add_zone(p: Vector2, r: float, life: float, tick: float, dmg: float, st: Dictionary, src: String) -> Dictionary:
	var z := {"p": p, "r": r, "life": life, "t": 0.0, "tick": tick, "tt": 0.0, "dmg": dmg, "st": st, "el": st.el, "src": src}
	zones.append(z)
	ring(p, 4, r, 0.35, C[st.el], 2)
	return z


func _inside_own(p: Vector2, spell: String) -> bool:
	for z in zones:
		if z.src == "player" and String(z.st.get("name", "")) == spell and z.p.distance_to(p) < z.r:
			return true
	return false


func _saw_terrain_if(mine: bool, id: String) -> void:
	if mine:
		discovery.saw_terrain(id)


# ================================================================ Terrain and secrets (Phase 3)

## Fire touching dry grass sets the whole patch alight for a while.
func ignite_at(p: Vector2, r: float) -> void:
	var G: Dictionary = GameData.TERRAIN.grass_fire
	for pt in terrain.overlapping(p, r, "grass"):
		pt.burnt = float(G.regrow)
		var z := _add_zone(pt.p, pt.r, float(G.dur), float(G.tick), float(G.dmg), {"el": "fire", "kind": "zone", "name": "grass fire"}, "world")
		z.hurts_player = float(G.player_dmg)
		z.start = pt.p
		if player.position.distance_to(pt.p) < 500.0:
			discovery.saw_terrain("grass_fire")


## A wind spell passing through fire carries it along.
func _wind_through_fire(p: Vector2, v: Vector2) -> void:
	for z in zones:
		if z.el == "fire" and p.distance_to(z.p) < z.r:
			z.carry = v.normalized() * float(GameData.TERRAIN.wind_carry)
			z.carry_t = float(GameData.TERRAIN.wind_carry_time)


## Fire drifts with the breeze (and anything a wind spell gave it); a walking vortex
## heads for the nearest enemy.
func _move_zone(z: Dictionary, dt: float) -> void:
	if z.el == "fire":
		var breeze := Vector2.from_angle(time * 0.02) * float(GameData.TERRAIN.breeze)
		var v: Vector2 = breeze
		if float(z.get("carry_t", 0.0)) > 0.0:
			z.carry_t = float(z.carry_t) - dt
			v += z.carry
		z.p += v * dt
		if z.has("start") and z.p.distance_to(z.start) > 40.0 and player.position.distance_to(z.p) < 400.0:
			discovery.saw_terrain("wind_carry")
	if float(z.get("walk", 0.0)) > 0.0:
		var e = nearest(z.p, 400.0)
		if e != null:
			z.p += (e.position - z.p).normalized() * float(z.walk) * dt


## Puddles soak whatever wades through them.
func _terrain_effects(_dt: float) -> void:
	for e in enemies:
		if e.dead:
			continue
		if terrain.at(e.position, "puddle") != null:
			e.soak = maxf(e.soak, 1.0)
			if e.position.distance_to(player.position) < 260.0 and player.dead_t <= 0.0:
				discovery.saw_terrain("puddle_soak")


## Secrets that depend on what a projectile hits (checked before the hit lands).
func _secret_on_hit(e, st: Dictionary, src: String) -> void:
	if src != "player":
		return
	var sname: String = String(st.get("name", ""))
	if sname == "Ember Bolt" and e.soak > 0.0:
		var S: Dictionary = GameData.SECRETS["Ember Bolt"]
		_add_zone(e.position, float(S.radius), float(S.dur), 0.5, 0.0, {"el": "water", "kind": "zone", "name": "steam", "slow": float(S.slow)}, "player")
		discovery.secret(sname)
	elif sname == "Gust" and terrain.at(e.position, "puddle") != null:
		var G: Dictionary = GameData.SECRETS["Gust"]
		ring(e.position, 6, float(G.radius), 0.45, C.water, 2)
		for o in enemies:
			if not o.dead and o.position.distance_to(e.position) < float(G.radius):
				o.soak = 3.5
		discovery.secret(sname)


## Storm Rod secret: a strike on a soaked enemy forks to every soaked enemy nearby.
func _storm_fork(first, z: Dictionary) -> void:
	var S: Dictionary = GameData.SECRETS["Storm Rod"]
	for e in enemies:
		if e != first and not e.dead and e.soak > 0.0 and e.position.distance_to(first.position) < float(S.range):
			chains.append({"a": first.position, "b": e.position, "t": 0.25, "col": C.lightning, "wide": false})
			hit(e, z.dmg * float(S.dmg), "lightning", z.src)
	if z.src == "player":
		discovery.secret("Storm Rod")


## Undertow secret: an enemy thrown into another one makes both reel.
func _crash(a, b) -> void:
	var dmg: float = maxf(a.crash_dmg if a.crash_t > 0.0 else 0.0, b.crash_dmg if b.crash_t > 0.0 else 0.0)
	# A tangle needs one thrown monster meeting one that wasn't thrown with it.
	var ta: bool = a.crash_t > 0.0 and a.crash_kind == "tangle"
	var tb: bool = b.crash_t > 0.0 and b.crash_kind == "tangle"
	if ta and tb:
		return
	var tangle: bool = ta or tb
	a.crash_t = 0.0
	b.crash_t = 0.0
	if tangle:
		# Hand secret: a Shove threw one monster into another.
		var T: Dictionary = GameData.HAND_SECRETS.tangle
		for e in [a, b]:
			hit(e, float(T.dmg), "none", "player")
			if not e.dead:
				e.state = "stagger"
				e.state_t = float(T.stagger)
		ring((a.position + b.position) / 2.0, 6, 34, 0.4, C.ink, 2.5)
		hands.secret("tangle")
		return
	for e in [a, b]:
		e.state = "stagger"
		e.state_t = float(GameData.SECRETS["Undertow"].stagger)
		hit(e, dmg, "water", "player")
	ring((a.position + b.position) / 2.0, 6, 40, 0.4, C.water, 2.5)
	discovery.secret("Undertow")


## Monster affinities: weak, resists, enraged or special. Returns the damage multiplier.
## Everyone who sees a reaction (you hit it, or Mira did) counts toward learning it.
func _affinity(e, el: String, src: String) -> float:
	var r: Dictionary = discovery.reaction(e, el)
	if r.is_empty() or src == "world":
		return 1.0
	discovery.saw_reaction(e, el)
	match r.type:
		"weak", "resists":
			return float(r.mult)
		"enraged":
			e.enraged_t = float(r.time)
			e.enrage_speed = float(r.speed)
			return float(r.mult)
		"special":
			match r.effect:
				"split":
					if not e.split_done and e.hp / e.max_hp < float(r.below):
						_split(e)
				"guard_break":
					e.state = "stagger"
					e.state_t = float(r.stagger)
					e.face = -e.face
	return 1.0


## Water splits a hurt Blot into two Inklings.
func _split(e) -> void:
	e.split_done = true
	ring(e.position, 6, 40, 0.4, C.water, 2.5)
	for k in 2:
		var n = EnemyScript.new()
		n.setup(self, 0, e.position + Vector2.from_angle(k * PI + randf()) * 18.0)
		n.side = 1.0 if k == 0 else -1.0
		n.aggro = true
		n.xp = 0   # the Blot's own XP is enough
		actors.add_child(n)
		enemies.append(n)
	kill(e, "world")


## A finished read (see casting.gd): the spell goes off at the aim point.
## `slot` is the page index, or 3 for the hidden Last Page spell.
func on_cast(slot: int, st: Dictionary, mult: float) -> void:
	var aim := aim_point()
	ch.opened.attack = true
	if float(st.get("overcharge", 0.0)) >= 0.9:
		journal("first_charge")
	if not Game.has_book():
		_cast_bare(st, aim)
		return
	if slot == 3:
		perform(st, aim, "player", 1.0)
		ring(player.position, 10, 220, 0.8, C.gilt, 4)
		last_page_cd = 12.0
		return
	var still: bool = player.still > 0.4
	perform(st, aim, "player", mult)
	if ch.el == "fire":
		player.heat = mini(5, player.heat + 1)
		player.heat_t = float(GameData.FIRE_HEAT_WINDOW)
	chapter.on_cast(still)


func _cast_bare(st: Dictionary, aim: Vector2) -> void:
	var L: Dictionary = GameData.LEAN
	if st.move == "sidestep":
		if nearest(player.position, float(L.dash_near)) != null:
			signal_lean("slip")
		player.still = 0.0   # a dash is movement, so it never counts as standing your ground
	if st.move == "shove" and nearest(player.position, float(L.repel_range)) != null:
		signal_lean("repel")
	if st.move == "jab":
		# A punch has short reach: aim it at the enemy nearest the aim line if one is in reach.
		var tgt = chain_target(player.position, aim, 90.0)
		if tgt != null:
			aim = tgt.position
	st = _grow_move(st)
	var from: Vector2 = player.position
	flank_target = null
	if st.move == "flank":
		# Circle to the far side of the nearest monster near the aim.
		var tgt = chain_target(player.position, aim, float(st.reach))
		if tgt != null:
			var away: Vector2 = (tgt.position - player.position).normalized()
			aim = tgt.position + away * (tgt.r + player.r + 16.0)
			st.dash_len = player.position.distance_to(aim)
			flank_target = tgt
	if st.move == "brace":
		brace_t = float(st.brace_time)
		brace_dir = (aim - player.position).normalized() if aim.distance_to(player.position) > 1.0 else player.facing
		player.facing = brace_dir
		player.still = float(GameData.LEAN.planted_time)   # bracing is standing your ground
	else:
		action_hits = 0
		perform(st, aim, "player", 1.0)
		if action_hits >= 2:
			signal_lean("multi", action_hits - 1)
	if st.move == "shove" and action_hits >= 1:
		hands.use("shove")
	if st.move == "sidestep":
		if action_hits >= 1:
			hands.use("sidestep")
		if hands.tier("sidestep") >= 1:
			decoy_t = float(GameData.HAND_GROWTH.sidestep.decoy_time)
			decoy_p = from
	last_move = st.move
	last_move_t = time
	# Fighting time per move ("use_w" weights a Shove like several Jabs).
	if not ch.has("use"):
		ch.use = {}
	ch.use[st.move] = float(ch.use.get(st.move, 0.0)) + float(st.use_w)


func last_page_ready() -> bool:
	var a: Dictionary = ch.aspect
	return a.awakened and a.id == "lastpage" and player.dead_t <= 0.0 and player.hp / Game.max_hp() < 0.3 and last_page_cd <= 0.0


## Writes one writing ink into page i (only while resting, see rest_overlay.gd).
## Returns true if it was written.
func spend_ink(i: int) -> bool:
	var s: Dictionary = ch.spells[i]
	if ch.ink < 1 or s.lvl >= Game.max_spell_level():
		return false
	var tier_before := int(s.lvl / 4.0)
	s.lvl += 1
	ch.ink -= 1
	if int(s.lvl / 4.0) > tier_before:
		ring(player.position, 10, 90, 0.7, C[ch.el], 3)
	hud.rebuild_spells()
	Game.save_game()
	return true


# ================================================================ Rest (Phase 2)

## Safe to rest: nothing hunting you nearby.
func can_rest() -> bool:
	if player.dead_t > 0.0:
		return false
	for e in enemies:
		if not e.dead and e.aggro and e.position.distance_to(player.position) < float(GameData.REST.break_range):
			return false
	return true


func near_campfire() -> bool:
	for f in GameData.CAMPFIRES:
		if player.position.distance_to(f) < float(GameData.REST.campfire_range) + (GameData.TOWN_RADIUS if f == Vector2.ZERO else 0.0):
			return true
	return false


func _tick_rest(dt: float) -> void:
	rest_fx = maxf(0.0, rest_fx - dt)
	var R: Dictionary = GameData.REST
	if not resting:
		if casting.reading or player.dead_t > 0.0:
			return
		var fire := near_campfire()
		if (fire and rest_pressed) or (rest_held and player.still > 0.1):
			if not can_rest():
				rest_fx = 0.6
				return
			resting = true
			rest_t = 0.0
			rest_at_fire = fire
			rest_need = float(R.campfire_time if fire else R.time)
		return
	# Moving, letting go (in the open), or a hunter coming close wakes you.
	if player.still <= 0.0 or (not rest_at_fire and not rest_held) or not can_rest():
		_break_rest()
		return
	player.mana = minf(Game.max_mana(), player.mana + float(R.ink_rate) * dt)
	player.hp = minf(Game.max_hp(), player.hp + float(R.campfire_hp_rate if rest_at_fire else R.hp_rate) * dt)
	rest_t += dt
	if rest_t >= rest_need:
		finish_rest()


func _break_rest() -> void:
	resting = false
	rest_fx = 0.6


## A finished rest: pending levels are written, then (with a book) you may write
## ink into your pages. The first rest in the Hearth at the ceremony level opens the ceremony.
func finish_rest() -> void:
	resting = false
	var in_hearth: bool = player.position.length() < GameData.TOWN_RADIUS
	var hp_frac: float = player.hp / Game.max_hp()
	var n: int = Game.write_levels(ch)
	ch.rested = true
	ch.opened.rest = true
	unlock("journal")   # a rest is when the journal gets written, so it appears by then at the latest
	journal("first_rest")
	if n > 0:
		player.hp = hp_frac * Game.max_hp()
		if Game.has_book():
			journal("woke_stronger")
		else:
			journal("woke_stronger_bare")
			journal("lean_" + lean_hint().md5_text().substr(0, 8), lean_hint())
	for got in hands.on_rest():   # moves learned from monsters, and moves that grew
		journal(String(got[0]), String(got[1]))
		ring(player.position, 8, 70, 0.6, C.ink, 2.5)
	var ceremony: bool = in_hearth and ceremony_ready()
	if ceremony_ready() and not in_hearth:
		journal("ceremony_call")
	Game.save_game()
	if auto_rest_ui:
		_auto_write()
		if ceremony:
			go_to_ceremony.emit()
		return
	if ceremony:
		journal("ceremony_near")
		rest_ui.finished.connect(func():
			Game.save_game()
			go_to_ceremony.emit(), CONNECT_ONE_SHOT)
	rest_ui.show_rest(n)


## Balance bot: write ink into the lowest page, evenly.
func _auto_write() -> void:
	if not Game.has_book():
		return
	while ch.ink > 0:
		var best := -1
		for i in ch.spells.size():
			if ch.spells[i].lvl < Game.max_spell_level() and (best < 0 or ch.spells[i].lvl < ch.spells[best].lvl):
				best = i
		if best < 0 or not spend_ink(best):
			break


# ================================================================ Journal, unlocks, nudges (Phase 2)

## Writes a journal line once ever (text from JOURNAL in game_data.gd unless given).
func journal(id: String, text := "") -> void:
	var ids: Dictionary = ch.journal_ids
	if ids.has(id):
		return
	var t: String = text if text != "" else String(GameData.JOURNAL.get(id, ""))
	if t == "":
		return
	ids[id] = true
	ch.journal.append(t)
	hud.add_log(t)


## Shows one part of the interface for good (it fades in, see hud.gd).
func unlock(part: String) -> void:
	if ch.ui.get(part, false):
		return
	ch.ui[part] = true
	Game.save_game()


func unlock_all_ui() -> void:
	for k in GameData.UI_PARTS:
		unlock(k)


func _tick_unlocks() -> void:
	if player.dead_t > 0.0:
		return
	if not Game.has_book() and not ch.ui.hands and nearest(player.position, float(GameData.UNLOCK.hands_near)) != null:
		unlock("hands")
	if not ch.ui.map and player.position.distance_to(GameData.MAP_SCRAP) < float(GameData.UNLOCK.map_pickup):
		unlock("map")
		journal("map_found")
		ring(GameData.MAP_SCRAP, 4, 40, 0.6, C.gilt, 2)
	if player.still <= 0.0:
		ch.opened.move = true
	if casting.turning():
		ch.opened.page = true
		if Game.has_book() and ch.thick != "thin":
			journal("page_turn")


## Called by the HUD when you cross into another region.
func on_region(reg: int) -> void:
	if reg == 0:
		if ch.left_hearth:
			unlock("journal")
			journal("hearth_return")
		return
	ch.left_hearth = true
	ch.visited[str(reg)] = true
	journal(["", "fields", "marsh", "reach"][reg])
	if ch.visited.size() >= 3 and not ch.ui.map:
		unlock("map")
		journal("all_regions")


## A one-time gentle nudge: a faint key glyph near you, once ever (see NUDGES).
func _tick_nudges(dt: float) -> void:
	nudge_t = maxf(0.0, nudge_t - dt)
	if player.dead_t > 0.0:
		return
	var o: Dictionary = ch.opened
	var conds := {
		"move": not o.get("move", false),
		"attack": not o.get("attack", false) and ch.ui.get("hands", false) and nearest(player.position, 220.0) != null,
		"page": not o.get("page", false) and casting.page_count() > 1 and (Game.has_book() or ch.ui.get("hands", false)),
		"rest": not ch.rested and player.hp / Game.max_hp() < 0.6 and can_rest(),
		"book": Game.has_book() and not o.get("book", false),
		"journal": ch.ui.get("journal", false) and not o.get("journal", false),
	}
	for id in conds:
		if not conds[id] or ch.nudged.get(id, false):
			continue
		nudge_clock[id] = float(nudge_clock.get(id, 0.0)) + dt
		if nudge_clock[id] >= float(GameData.NUDGES[id].after) and nudge_t <= 0.0:
			ch.nudged[id] = true
			nudge_id = id
			nudge_t = float(GameData.NUDGE_SHOW)
			Game.save_game()


# ================================================================ Book, hints, log

func open_book() -> void:
	if paused:
		return
	if not Game.has_book():
		return
	ch.opened.book = true
	var awakened_now: bool = chapter.try_awaken()
	paused = true
	pointer_down = false
	book.open(awakened_now)
	if awakened_now:
		awaken_fx = 2.5


func on_hint(_text: String) -> void:
	hint_flash = 1.6
	unlock("margins")
	hud.refresh_margins(true)
	hud.stir_book_button()


## Every margin note: hidden-chapter hints and spell secrets.
func all_margins() -> Array:
	return ch.aspect.margins + ch.disc.margins


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

	for pt in terrain_patches_for_draw():
		_draw_patch(d, pt)
	for f in GameData.CAMPFIRES:
		if f != Vector2.ZERO:
			_draw_campfire(d, f)
	if not ch.ui.get("map", false):
		# A torn map scrap lying in the grass, with a slow glint.
		var mp: Vector2 = GameData.MAP_SCRAP
		d.draw_colored_polygon(PackedVector2Array([mp + Vector2(-8, -5), mp + Vector2(7, -7), mp + Vector2(9, 5), mp + Vector2(-6, 7)]), C.panel)
		d.draw_polyline(PackedVector2Array([mp + Vector2(-8, -5), mp + Vector2(7, -7), mp + Vector2(9, 5), mp + Vector2(-6, 7), mp + Vector2(-8, -5)]), Color(C.ink_soft, 0.8), 1.0)
		var g := maxf(0.0, sin(time * 1.3))
		d.draw_circle(mp + Vector2(4, -3), 2.0 * g, Color(C.gilt, g))
	for s in splats:
		d.draw_colored_polygon(Ink.blob(s.p, s.r, s.sd, 0.0), Color(C.ink, float(s.get("a", 0.22)) * (1.0 - s.t / s.life)))
	for z in zones:
		var f: float = minf(1.0, (1.0 - z.t / z.life) * 3.0)
		d.draw_circle(z.p, z.r, Color(C[z.el], 0.16 * f))
		Ink.dashed_circle(d, z.p, z.r, Color(C[z.el], 0.6 * f), 1.5, time * 0.5)
	if decoy_t > 0.0:
		# The smear of ink a grown Sidestep leaves behind.
		var k: float = decoy_t / float(GameData.HAND_GROWTH.sidestep.decoy_time)
		var dr: float = float(GameData.HAND_GROWTH.sidestep.decoy_r)
		d.draw_colored_polygon(Ink.blob(decoy_p, dr, 3.0, time * 3.0), Color(C.ink, 0.45 * k))
		d.draw_arc(decoy_p, dr + 2.0, 0, TAU, 20, Color(C.ink_soft, 0.6 * k), 1.0)


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
	_draw_reading(d)
	_draw_rest(d)
	_draw_nudge(d)


## Ground patches, drawn in the same ink style as everything else.
func terrain_patches_for_draw() -> Array:
	var view := _view_rect()
	return terrain.patches.filter(func(pt): return view.grow(pt.r).has_point(pt.p))


func _draw_patch(d: Node2D, pt: Dictionary) -> void:
	var p: Vector2 = pt.p
	var r: float = pt.r
	match pt.kind:
		"grass":
			var burnt: bool = pt.burnt > 0.0
			var col: Color = Color(C.ink_soft, 0.5) if burnt else Color("b59a3c", 0.55)
			for k in int(r / 3.0):
				var a := k * 2.39996 + float(pt.sd)
				var q: Vector2 = p + Vector2.from_angle(a) * r * sqrt(fmod(k * 0.618, 1.0))
				var sway := sin(time * 1.5 + k) * 1.5
				d.draw_line(q, q + Vector2(sway - 2.0, -7.0), col, 1.2)
				d.draw_line(q + Vector2(2, 0), q + Vector2(sway + 3.0, -6.0), col, 1.2)
		"puddle":
			d.draw_colored_polygon(Ink.blob(p, r, float(pt.sd), 0.0), Color(C.water, 0.13))
			d.draw_polyline(Ink.outline(Ink.blob(p, r, float(pt.sd), 0.0)), Color(C.water, 0.35), 1.2)
			var k := fmod(time * 0.4 + float(pt.sd), 1.0)
			d.draw_arc(p + Vector2(r * 0.2, -r * 0.1), r * 0.5 * k, 0, TAU, 24, Color(C.water, 0.3 * (1.0 - k)), 1.0)
		"stone":
			for k in int(r / 9.0):
				var a := k * 2.39996 + float(pt.sd)
				var q: Vector2 = p + Vector2.from_angle(a) * r * sqrt(fmod(k * 0.618 + 0.1, 1.0))
				d.draw_colored_polygon(Ink.blob(q, 4.5 + fmod(k * 1.7, 3.0), float(k), 0.0), Color(C.ink_soft, 0.35))
		"open":
			d.draw_circle(p, r, Color(C.paper.lightened(0.4), 0.45))
			for k in 3:
				var y := (k - 1) * r * 0.4
				var x := fmod(time * 20.0 + k * 37.0, r * 1.2) - r * 0.6
				d.draw_line(p + Vector2(x - 12, y), p + Vector2(x + 12, y - 2), Color(C.wind, 0.3), 1.2)


func _draw_campfire(d: Node2D, f: Vector2) -> void:
	for k in 6:
		d.draw_circle(f + Vector2.from_angle(k * TAU / 6.0) * 13.0, 3.5, Color(C.ink_soft, 0.7))
	d.draw_colored_polygon(Ink.blob(f, 7.0, 2.0, time * 2.0), C.fire)
	d.draw_colored_polygon(Ink.blob(f + Vector2(0, -2), 3.5, 5.0, time * 3.0), C.gilt)


## Resting: a warm ring closes slowly around you. A broken rest flickers grey.
func _draw_rest(d: Node2D) -> void:
	var p: Vector2 = player.position
	if resting:
		var k: float = rest_t / maxf(0.01, rest_need)
		d.draw_circle(p, 30.0 + 10.0 * k, Color(C.gilt, 0.08 + 0.1 * k))
		d.draw_arc(p, 34.0, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(C.gilt, 0.6), 2.0)
	elif rest_fx > 0.0:
		d.draw_arc(p, 30.0, 0, TAU, 32, Color(C.ink_soft, rest_fx), 1.5)


## The one-time control nudge: a faint key glyph beside you.
func _draw_nudge(d: Node2D) -> void:
	if nudge_t <= 0.0 or nudge_id == "":
		return
	var show: float = float(GameData.NUDGE_SHOW)
	var a: float = minf(1.0, minf(nudge_t, show - nudge_t) / 0.8) * 0.55
	var g: String = GameData.NUDGES[nudge_id].glyph
	var f := ThemeDB.fallback_font
	var tw: float = f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var c: Vector2 = player.position + Vector2(0, -38)
	var r := Rect2(c - Vector2(tw / 2.0 + 7.0, 13.0), Vector2(tw + 14.0, 19.0))
	d.draw_rect(r, Color(C.paper, a))
	d.draw_rect(r, Color(C.ink, a), false, 1.0)
	Ink.text_c(d, c + Vector2(0, 1), g, 13, Color(C.ink, a * 1.6))


const GLYPHS := "abcdefghijklmnopqrstuvwxyz"


## Reading shows on the character, never as a bar: letters lift off the book and a
## ring fills around you. Past the read time the ring turns gold and grows (overcharge).
func _draw_reading(d: Node2D) -> void:
	if player.dead_t > 0.0:
		return
	var p: Vector2 = player.position
	var book_p: Vector2 = p + Vector2(15, 0)
	var col: Color = C[ch.el] if Game.has_book() else C.ink
	if casting.fizzle_fx > 0.0:
		var f: float = casting.fizzle_fx / 0.5
		for i in 7:
			var fp: Vector2 = book_p + Vector2(sin(i * 2.1) * 10.0, (1.0 - f) * 26.0 + i * 2.0)
			Ink.text_c(d, fp, GLYPHS[(i * 7) % 26], 10, Color(C.ink_soft, f * 0.7))
	if not casting.reading:
		return
	var k: float = casting.progress()
	var oc: float = casting.overcharge()
	d.draw_arc(p, 22.0, -PI / 2.0, -PI / 2.0 + TAU * k, 40, Color(col, 0.35 + 0.4 * k), 2.5)
	if k >= 1.0:
		d.draw_arc(p, 22.0, 0, TAU, 40, Color(col, 0.8), 2.5)
		if oc > 0.0:
			d.draw_arc(p, 27.0 + 4.0 * oc, -PI / 2.0, -PI / 2.0 + TAU * oc, 40, Color(C.gilt, 0.5 + 0.5 * oc), 1.5 + 2.0 * oc)
	var n := int(2 + 8 * k + 8 * oc)
	for i in n:
		var rise := fmod(time * (26.0 + 10.0 * oc) + i * 11.0, 34.0)
		var lp: Vector2 = book_p + Vector2(sin(time * 2.0 + i * 1.7) * (6.0 + i), -rise)
		var a: float = (1.0 - rise / 34.0) * (0.5 + 0.5 * k)
		Ink.text_c(d, lp, GLYPHS[(i * 5 + int(time * 3.0)) % 26], 10 + int(4.0 * oc), Color(col.lerp(C.gilt, oc), a))
	_draw_aim(d)


## A faint aim line or placement circle, only while reading.
func _draw_aim(d: Node2D) -> void:
	var st: Dictionary = casting.st
	var p: Vector2 = player.position
	var aim := aim_point()
	var dir: Vector2 = (aim - p).normalized() if aim.distance_to(p) > 1.0 else player.facing
	var col := Color(C[st.el] if C.has(st.el) else C.ink, float(GameData.AIM.line_alpha))
	match st.kind:
		"bolt":
			var reach: float = float(st.speed) * float(st.get("life", 1.1))
			Ink.dashed_line(d, p + dir * 24.0, p + dir * reach, col, 1.5)
		"chain":
			Ink.dashed_line(d, p + dir * 24.0, p + dir * minf(float(st.range), p.distance_to(aim)), col, 1.5)
			var tgt = chain_target(p, aim, float(st.range))
			if tgt != null:
				d.draw_arc(tgt.position, tgt.r + 6.0, 0, TAU, 24, col, 1.5)
		"dash":
			Ink.dashed_line(d, p + dir * 24.0, p + dir * float(st.dash_len), col, 3.0)
		"zone":
			var zp: Vector2 = p + dir * minf(p.distance_to(aim), float(st.range))
			Ink.dashed_circle(d, zp, float(st.radius) * (1.0 + 0.15 * int(st.get("tier", 0))), col, 1.5, time * 0.5)
		"nova":
			Ink.dashed_circle(d, p, float(st.radius) * (1.0 + 0.25 * int(st.get("tier", 0))), col, 1.5, time * 0.5)


# ================================================================ Bare hands growth (see hands.gd)

## A basic move after growth (HAND_GROWTH): wider Shove, and so on.
func _grow_move(st: Dictionary) -> Dictionary:
	if st.move == "shove" and hands.tier("shove") >= 2:
		var G: Dictionary = GameData.HAND_GROWTH.shove
		st.radius = float(st.radius) * float(G.radius_mult)
		st.push = float(st.push) * float(G.push_mult)
	return st


## One of your bare-hands moves just landed on `e`. Applies growth and hand secrets.
## Returns [damage multiplier, stagger seconds to force (0 = none)].
func _hand_hit(e, move: String, base: float) -> Array:
	var m := 1.0
	var stagger := 0.0
	var S: Dictionary = GameData.HAND_SECRETS
	var G: Dictionary = GameData.HAND_GROWTH
	var id: int = e.get_instance_id()
	match move:
		"jab":
			if e.aggro:
				hands.use("jab")
			if last_move == "sidestep" and time - last_move_t <= float(S.backhand.window):
				m *= float(S.backhand.mult)
				stagger = maxf(stagger, float(GameData.MONSTERS.stagger))
				hands.secret("backhand")
			if e.state == "windup" and e.state_t <= float(S.counter.late):
				stagger = maxf(stagger, float(S.counter.stagger))
				hands.secret("counter")
			# Clean blows in a row on one monster.
			if id == clean_id:
				clean_n += 1
			else:
				clean_id = id
				clean_n = 1
			if clean_n >= int(S.untouched.count):
				clean_n = 0
				var c: Vector2 = e.position
				ring(c, 6, float(S.untouched.splash_r), 0.35, C.ink, 2.5)
				for o in enemies:
					if o != e and not o.dead and o.position.distance_to(c) < float(S.untouched.splash_r) + o.r:
						delayed.append({"t": 0.05, "fn": func(): hit(o, base * float(S.untouched.splash), "none", "player")})
				hands.secret("untouched")
			var t: int = hands.tier("jab")
			if t >= 1:
				delayed.append({"t": 0.12, "fn": func():
					if not e.dead:
						hit(e, base * float(G.jab.second_hit), "none", "player")})
			if t >= 2 and id == last_hit_id and (chain_len + 1) % 3 == 0 and time - last_hit_t <= float(GameData.LEAN.combo_window):
				e.knock += (e.position - player.position).normalized() * float(G.jab.third_knock)
				stagger = maxf(stagger, float(G.jab.third_stagger))
		"shove":
			if hands.tier("shove") >= 1:
				stagger = maxf(stagger, float(G.shove.stagger))
			e.crash_t = float(S.tangle.window)
			e.crash_kind = "tangle"
		"sidestep":
			if hands.tier("sidestep") >= 2:
				stagger = maxf(stagger, 0.8)
				e.face = -e.face
		"flank":
			if e == flank_target:
				m *= float(GameData.LEARNED_MOVES.flank.behind_mult)
				stagger = maxf(stagger, float(GameData.MONSTERS.stagger))
				e.face = (player.position - e.position).normalized()
	return [m, stagger]


## Where monster `e` should head: your decoy if one is out and closer, else you.
func lure_for(e) -> Vector2:
	if decoy_t > 0.0 and e.position.distance_to(decoy_p) < e.position.distance_to(player.position):
		return decoy_p
	return player.position
