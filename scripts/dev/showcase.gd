extends Node
## Designer tools for looking and measuring, not for players.
##
## `-- --showcase` (run without --headless, or under xvfb-run) sets up busy scenes and saves
##   screenshots to the user folder: every element's bolts, zones and bursts side by side,
##   monsters at each point of a wind-up, and every reading state (reading, ready, overcharged,
##   fizzled, broken, too little ink, nearly dead), an erasure site in every state (bare,
##   cleared, the restoring wave, restored, fading), a torn page and the Hearth's windows.
## `-- --stress` builds the heaviest scene the game allows (most monsters, burning grass,
##   puddle combos, every zone at once, lingering splatters) and prints how long the rules
##   and a full frame take. 16.7 ms per frame is 60 FPS.

const World := preload("res://scripts/world/world.gd")
const Enemy := preload("res://scripts/world/enemy.gd")
const DT := 1.0 / 60.0

var w


func _book(el: String, thick := "thick") -> void:
	var c := Game.new_character("Arin", "orphan")
	c.el = el
	c.thick = thick
	c.level = 9
	c.spells = [{"i": 0, "lvl": 5}, {"i": 1, "lvl": 5}, {"i": 2, "lvl": 5}] if thick == "thick" else [{"i": 0, "lvl": 5}]
	c.aspect = {"id": "stillness", "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 99, "streak": 9}
	for k in GameData.UI_PARTS:
		c.ui[k] = true
	for k in GameData.NUDGES:
		c.nudged[k] = true
	c.rested = true
	Game.ch = c


func _world_at(pos: Vector2):
	if w != null:
		w.queue_free()
		await get_tree().process_frame
	w = World.new()
	add_child(w)
	await get_tree().process_frame
	w.set_process(false)
	w.player.position = pos
	w.ally.position = pos + Vector2(-40, 30)
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	w.camera.reset_smoothing()
	return w


func _foe(tier: int, p: Vector2):
	var e = Enemy.new()
	e.setup(w, tier, p)
	w.actors.add_child(e)
	w.enemies.append(e)
	e.spd = 0.0
	return e


func _frames(n: int) -> void:
	for k in n:
		w.time += DT
		w.under.queue_redraw()
		w.over.queue_redraw()
		for e in w.enemies:
			e.queue_redraw()
		w.player.queue_redraw()
		w.hud.refresh(DT)
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir().path_join(file_name + ".png")
	img.save_png(path)
	print("Saved ", path)


func run_showcase() -> void:
	# 1. Every element side by side: a bolt, a zone and a burst each, in a column.
	_book("fire")
	await _world_at(Vector2(0, 900))
	var base: Vector2 = w.player.position + Vector2(-480, -250)
	w.ally.position = w.player.position + Vector2(0, 300)
	w.player.position += Vector2(0, 290)
	for i in Game.ELS.size():
		var el: String = Game.ELS[i]
		var x: Vector2 = base + Vector2(i * 240, 0)
		w.projectiles.append({"p": x, "v": Vector2(480, 0), "life": 99.0, "dmg": 0.0, "el": el, "src": "player", "pierce": 0, "hit": [], "st": {}, "explode": false})
		w.zones.append({"p": x + Vector2(0, 140), "r": 75.0, "life": 99.0, "t": 1.0, "tick": 99.0, "tt": 99.0, "dmg": 0.0, "st": {"el": el}, "el": el, "src": "player", "sd": 0.3})
		w.rings.append({"p": x + Vector2(0, 330), "r0": 60.0, "r1": 61.0, "t": 0.0, "life": 99.0, "col": GameData.COLORS[el], "w": 3.0, "el": el})
	w.camera.global_position = base + Vector2(480, 200)
	w.camera.position_smoothing_enabled = false
	await _frames(20)
	await _shot("showcase_1_elements")
	w.camera.zoom = Vector2(2.5, 2.5)
	w.camera.global_position = base + Vector2(0, 150)
	await _frames(2)
	await _shot("showcase_1b_fire_water_close")
	# 2. Monsters at the start, middle and end of a wind-up, and staggered.
	_book("earth")
	await _world_at(Vector2(0, 900))
	var p0: Vector2 = w.player.position
	var row := [0.05, 0.5, 0.95]
	for t in 3:
		for i in 3:
			var e = _foe(t, p0 + Vector2(-260 + i * 140, -200 + t * 140))
			e.aggro = true
			e.state = "windup"
			e.state_t = float(e.f.windup) * (1.0 - row[i])
			e.face = Vector2.DOWN
			e.lunge = Vector2.DOWN
		var s = _foe(t, p0 + Vector2(220, -200 + t * 140))
		s.state = "stagger"
		s.state_t = 99.0
		s.hp = s.max_hp * 0.4
	w.player.position = p0 + Vector2(0, 230)
	await _frames(4)
	for e in w.enemies:
		e.state_t += 4.0 * DT   # keep the pose: undo the frames that ran
	await _shot("showcase_2_windups")
	# 3. Reading states, one screenshot each.
	_book("water")
	await _world_at(Vector2(0, 900))
	var cs = w.casting
	var states := ["half", "ready", "full", "fizzle", "broken", "short", "hurt"]
	for st_name in states:
		cs.reading = false
		cs.fizzle_fx = 0.0
		w.player.mana = Game.max_mana()
		w.player.hp = Game.max_hp()
		cs.st = cs.stats_for(0)
		match st_name:
			"half":
				cs.reading = true
				cs.t = float(cs.st.read) * 0.5
			"ready":
				cs.reading = true
				cs.t = float(cs.st.read) + 0.01
				cs.ready_fx = float(GameData.READABILITY.ready_flash) * 0.6
			"full":
				cs.reading = true
				cs.t = float(cs.st.read) + float(cs.st.over)
			"fizzle":
				cs.last_result = "fizzle"
				cs.fizzle_fx = 0.3
			"broken":
				cs.last_result = "broken"
				cs.fizzle_fx = 0.3
			"short":
				w.player.mana = 1.0
			"hurt":
				w.player.hp = Game.max_hp() * 0.15
		w.camera.zoom = Vector2(2.5, 2.5)
		await _frames(2)
		await _shot("showcase_3_read_%s" % st_name)
	w.camera.zoom = Vector2.ONE
	# 4. The Unwritten, Phase 2: an erasure site bare, cleared, mid-restore, restored, fading.
	var L = GameData.Lore
	var s0: Dictionary = L.SITES[0]
	for look in ["bare", "cleared", "wave_1", "wave_2", "wave_3", "restored", "fading"]:
		_book("earth")
		await _world_at(s0.p + Vector2(0, 160))
		var er = w.erasure
		var st: Dictionary = er.state(s0.id)
		match look:
			"cleared":
				st.state = "cleared"
			"wave_1", "wave_2", "wave_3":
				er.restore(s0.id)
				er.fx[s0.id] = float(L.RESTORE_FX.time) * {"wave_1": 0.15, "wave_2": 0.4, "wave_3": 0.75}[look]
			"restored":
				er.restore(s0.id)
				er.fx.clear()
			"fading":
				er.restore(s0.id)
				er.fx.clear()
				st.pale = 0.5
		for e in w.enemies:
			e.queue_free()
		w.enemies.clear()
		er.guardians.clear()
		w.camera.global_position = s0.p
		w.camera.position_smoothing_enabled = false
		w.camera.zoom = Vector2(1.6, 1.6)
		await _frames(2)
		await _shot("showcase_4_site_%s" % look)
	# 5. A torn page in the grass, one behind a stone, and the Hearth with two windows lit.
	_book("earth")
	var hymn: Dictionary = L.FRAGMENTS[0]
	await _world_at(hymn.p + Vector2(40, 0))
	w.camera.global_position = hymn.p
	w.camera.position_smoothing_enabled = false
	w.camera.zoom = Vector2(3, 3)
	await _frames(2)
	await _shot("showcase_5_page_grass")
	w.erasure.restore(L.SITES[0].id)
	w.erasure.restore(L.SITES[3].id)
	w.erasure.fx.clear()
	w.player.position = Vector2(0, 40)
	w.camera.global_position = Vector2.ZERO
	w.camera.zoom = Vector2(2.2, 2.2)
	await _frames(2)
	await _shot("showcase_5_hearth_windows")
	w.ch.fragments = ["hymn", "letter"]
	w.camera.zoom = Vector2.ONE
	w.fragments_ui.open(null)
	await _frames(2)
	await _shot("showcase_5_torn_pages")
	w.fragments_ui.close()
	w.camera.zoom = Vector2.ONE
	print("showcase done")


# ================================================================ Stress

func run_stress() -> void:
	_book("fire")
	# Blot Marsh, near the most puddles and grass the terrain has: the heaviest place.
	var best := Vector2(0, 700)
	var best_n := -1
	var probe = await _world_at(Vector2.ZERO)
	for pt in probe.terrain.patches:
		var n := 0
		for o in probe.terrain.patches:
			if o.p.distance_to(pt.p) < 400.0:
				n += 1
		if n > best_n:
			best_n = n
			best = pt.p
	await _world_at(best)
	print("Stress scene at %s with %d ground patches within 400 px" % [best.round(), best_n])
	var frames := 600
	var rules_us := 0
	var frame_us := 0
	var worst := 0
	for f in frames:
		# Keep it as busy as the game can get: the most monsters, fires, zones and splatters.
		while w.enemies.size() < int(GameData.MONSTERS.max_nearby) + 3:
			var e = _foe(randi() % 3, w.player.position + Vector2.from_angle(randf() * TAU) * randf_range(60, 260))
			e.spd = float(e.f.spd)
			e.aggro = true
		if f % 20 == 0:
			for el in Game.ELS:
				var st: Dictionary = GameData.SPELLS[el][2].duplicate()
				st.el = el
				st.tier = 2
				w.perform(st, w.player.position + Vector2.from_angle(randf() * TAU) * 150.0, "player", 1.0)
				var b: Dictionary = GameData.SPELLS[el][0].duplicate()
				b.el = el
				b.tier = 2
				w.perform(b, w.enemies[0].position, "player", 1.0)
			w.ignite_at(w.player.position, 400.0)
		while w.splats.size() < int(GameData.FEEL.splat_max):
			w._splat(w.player.position + Vector2(randf_range(-500, 500), randf_range(-300, 300)), randf_range(4, 18), 30.0, 0.3)
		w.player.hp = Game.max_hp()
		var t0 := Time.get_ticks_usec()
		w._update(DT)
		var t1 := Time.get_ticks_usec()
		w.under.queue_redraw()
		w.over.queue_redraw()
		w.hud.refresh(DT)
		await get_tree().process_frame
		var t2 := Time.get_ticks_usec()
		rules_us += t1 - t0
		frame_us += t2 - t0
		if f > 30:
			worst = maxi(worst, t2 - t0)
	print("Stress: %d frames · rules %.2f ms/frame · whole frame %.2f ms (worst %.2f ms) · zones %d · projectiles %d · splats %d · monsters %d" % [
		frames, rules_us / 1000.0 / frames, frame_us / 1000.0 / frames, worst / 1000.0, w.zones.size(), w.projectiles.size(), w.splats.size(), w.enemies.size()])
	print("(16.7 ms per frame is 60 FPS. Under xvfb the drawing is done by the CPU, so a real GPU is faster.)")
