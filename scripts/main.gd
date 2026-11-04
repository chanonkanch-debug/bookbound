extends Node
## Switches between character creation, the World and the Book Ceremony.

const RiteScreen := preload("res://scripts/rite/rite_screen.gd")
const CeremonyScreen := preload("res://scripts/rite/ceremony_screen.gd")
const World := preload("res://scripts/world/world.gd")

var current: Node


func _ready() -> void:
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest()
		return
	for mode in ["--showcase", "--stress"]:
		if mode in OS.get_cmdline_user_args():
			var sc := preload("res://scripts/dev/showcase.gd").new()
			add_child(sc)
			if mode == "--showcase":
				await sc.run_showcase()
			else:
				await sc.run_stress()
			get_tree().quit()
			return
	if "--firsthour" in OS.get_cmdline_user_args():
		var fh := preload("res://scripts/dev/first_hour.gd").new()
		add_child(fh)
		await fh.run_first_hour()
		get_tree().quit()
		return
	if "--balance" in OS.get_cmdline_user_args():
		var bot := preload("res://scripts/dev/balance.gd").new()
		add_child(bot)
		await bot.run()
		get_tree().quit()
		return
	show_rite()


func _unhandled_key_input(event: InputEvent) -> void:
	# F12 saves a screenshot to the game's user folder.
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_shot("screenshot_%d" % Time.get_unix_time_from_system())


func show_rite() -> void:
	var r := RiteScreen.new()
	r.enter_world.connect(show_world)
	_swap(r)


func show_world() -> void:
	var w := World.new()
	w.quit_to_rite.connect(show_rite)
	w.go_to_ceremony.connect(show_ceremony)
	_swap(w)


func show_ceremony() -> void:
	var c := CeremonyScreen.new()
	c.enter_world.connect(show_world)
	_swap(c)


func _swap(n: Node) -> void:
	if current:
		current.queue_free()
	current = n
	add_child(n)


func _shot(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := OS.get_user_data_dir().path_join(file_name + ".png")
	img.save_png(path)
	print("Saved ", path)


## Smoke test: `godot --headless --path . -- --autotest` starts a bare-handed character,
## fights with every stance, attends the Book Ceremony, then checks the Phase 1 rules
## (reading, fizzles, page turns, overcast, broken reads), plays a while with every spell,
## awakens the hidden chapter, and quits. Add `--shots` (without --headless) to save screenshots.
const DT := 1.0 / 30.0


## Runs the world for n simulation steps without real time passing.
func _step(w, n: int) -> void:
	for k in n:
		w._update(DT)
	w.hud.refresh(DT)
	w.under.queue_redraw()
	w.over.queue_redraw()
	await get_tree().process_frame


## Holds the read key for `hold` seconds, then lets go. Returns the result.
func _read(w, hold: float) -> String:
	w.read_held = true
	await _step(w, 1)
	await _step(w, maxi(0, roundi(hold / DT) - 1))
	w.read_held = false
	await _step(w, 1)
	return w.casting.last_result


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		push_error("FAILED: " + what)
		print("  FAIL ", what)
		failures += 1


var failures := 0


func _autotest() -> void:
	var shots := "--shots" in OS.get_cmdline_user_args()
	show_rite()
	await get_tree().create_timer(0.3).timeout
	if shots:
		_shot("test_0_rite")
	current.begin_new()
	await get_tree().process_frame
	var w = current
	w.set_process(false)
	_check(not Game.has_book(), "new characters start without a book")
	print("Interface (Phase 2):")
	var nothing := true
	for k in GameData.UI_PARTS:
		if Game.ch.ui[k]:
			nothing = false
	_check(nothing and w.hud.dock.modulate.a < 0.01, "a new player sees only the world: no interface parts yet")
	_check(not Game.show_numbers(), "show_numbers is off by default")
	# The journal starts with your first kill: a discovery noticed before it waits for it.
	var early_line: String = GameData.TERRAIN_LINES.open_reach
	w.unlock("journal")
	w.discovery.saw_terrain("open_reach")
	var waited: bool = not (early_line in Game.ch.journal)
	w.journal("first_kill")
	var jl: Array = Game.ch.journal
	_check(waited and jl.find(early_line) > jl.find(GameData.JOURNAL.first_kill), "a discovery before the first kill waits, then follows it")
	Game.ch.ui.journal = false
	print("Bare hands:")
	# Walk out, pull a few monsters close, then use every stance on them.
	w.player.steer = Vector2.RIGHT
	await _step(w, 90)
	w.player.steer = Vector2.ZERO
	for k in mini(4, w.enemies.size()):
		w.enemies[k].position = w.player.position + Vector2.from_angle(k * 1.6) * 40.0
	await _step(w, 1)
	_check(Game.ch.ui.hands, "the stance marks appear once a monster comes close")
	_check(await _read(w, 0.03) == "fizzle", "releasing a Shove too early fizzles")
	var turned_at := -1
	w.casting.turn_to(1)
	for f in 20:
		await _step(w, 1)
		if w.casting.page == 1 and turned_at < 0:
			turned_at = f
	_check(turned_at >= 4, "switching stance takes a moment (%d frames)" % turned_at)
	for round_i in 9:
		w.casting.turn_to(round_i % 3)
		await _step(w, 10)
		var near = w.nearest(w.player.position, 400.0)
		w.bot_aim = near.position if near != null else null
		w.player.mana = Game.max_mana()
		w.player.hp = Game.max_hp()
		await _read(w, 0.5)
	if shots:
		_shot("test_1_bare_hands")
		w.designer.toggle()
		await get_tree().process_frame
		_shot("test_1b_designer_view")
		w.designer.toggle()
	print("  signals: ", Game.ch.signals)
	print("  book odds: ", Game.element_weights(), " thickness ", Game.thickness_weights())
	_check(w.splats.size() > 0, "hits leave ink splatters instead")
	var texts_with_digits := 0
	for t in w.texts:
		if String(t.s).is_valid_int():
			texts_with_digits += 1
	_check(texts_with_digits == 0, "no damage numbers in normal play")
	print("Bare hands growth:")
	await _test_hands(w)
	print("Rest (Phase 2):")
	w.auto_rest_ui = true
	w.gain_xp(1400)
	_check(int(Game.ch.level) == 1 and Game.pending_level() >= GameData.CEREMONY_LEVEL, "XP is earned, but no level is written before resting")
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	w.player.position = Vector2(0, 300)
	w.player.hp = Game.max_hp() * 0.5
	w.rest_held = true
	w.player.steer = Vector2.ZERO
	await _step(w, roundi(float(GameData.REST.time) * 0.5 / DT))
	_check(w.resting, "holding R in a safe spot starts a rest")
	w.player.steer = Vector2.LEFT
	await _step(w, 2)
	w.player.steer = Vector2.ZERO
	_check(not w.resting and int(Game.ch.level) == 1, "moving interrupts the rest, nothing is written")
	await _step(w, 2)
	await _step(w, roundi(float(GameData.REST.time) / DT) + 5)
	w.rest_held = false
	_check(int(Game.ch.level) >= GameData.CEREMONY_LEVEL, "a full rest writes the pending levels (now Lv %d)" % Game.ch.level)
	_check(Game.ch.journal.size() > 0 and Game.ch.ui.journal, "the journal has appeared and has entries")
	print("  journal: ", Game.ch.journal)
	_check(not Game.has_book(), "the ceremony waits for a rest in the Hearth")
	w.player.position = Vector2(0, 40)   # into the Hearth, then rest at its fire
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	await _step(w, 3)
	w.rest_pressed = true
	w.rest_held = true
	for f in roundi(float(GameData.REST.campfire_time) / DT) + 10:
		if current != w:
			break
		w._update(DT)
	w.rest_held = false
	await get_tree().process_frame
	_check(current is CeremonyScreen and not Game.has_book(), "the first rest in the Hearth opens the ceremony")
	if shots:
		_shot("test_2_ceremony")
	current.open_book()
	await get_tree().create_timer(1.0).timeout
	if shots:
		_shot("test_3_book_received")
	_check(Game.has_book(), "the ceremony gives a book")
	print("  ceremony book: ", Game.ch.el, " / ", Game.ch.thick, " / aspect ", Game.ch.aspect.id)

	_check(Game.ch.ui.book, "the book appears at the ceremony")
	print("Reading (Phase 1):")
	Game.ch.thick = "thick"
	Game.ch.spells = [{"i": 0, "lvl": 5}, {"i": 1, "lvl": 5}, {"i": 2, "lvl": 5}]
	show_world()
	w = current
	w.set_process(false)
	w.player.position = Vector2(0, 260)
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	await _step(w, 2)
	var cs = w.casting
	var st0: Dictionary = cs.stats_for(0)
	w.player.mana = 40.0
	var before: float = w.player.mana
	_check(await _read(w, 0.05) == "fizzle", "releasing before the read time fizzles")
	_check(absf(w.player.mana - (before - float(st0.mana) * 0.5)) < 1.5, "a fizzle refunds half the ink")
	await _step(w, 10)
	_check(await _read(w, float(st0.read) + 0.1) == "cast", "holding past the read time casts")
	var n_before: int = cs.casts
	w.read_held = true
	await _step(w, 150)
	w.read_held = false
	await _step(w, 1)
	_check(cs.casts - n_before == 1, "holding the key for 5 s casts once (no spam, got %d)" % (cs.casts - n_before))
	await _step(w, 10)
	# Page turns: page 1 -> 3 is two turns on a thick book.
	cs.turn_to(2)
	var tt: float = float(GameData.PAGES.turn_time.thick)
	await _step(w, roundi(tt * 1.5 / DT))
	_check(cs.page != 2, "page 1 to 3 is not done after one and a half turns")
	await _step(w, roundi(tt / DT) + 2)
	_check(cs.page == 2, "page 1 to 3 is done after two turns")
	# Moving slows the read.
	w.player.steer = Vector2.LEFT
	w.read_held = true
	var st2: Dictionary = cs.stats_for(2)
	await _step(w, roundi(float(st2.read) / DT) + 1)
	_check(cs.reading and not cs.ready_to_cast(), "moving while reading slows it")
	w.read_held = false
	w.player.steer = Vector2.ZERO
	await _step(w, 10)
	# Overcast: no ink, so the cost comes out of health.
	w.player.mana = 0.0
	w.player.hp = Game.max_hp()
	_check(await _read(w, float(st2.read) + 0.05) == "cast" and w.player.hp < Game.max_hp() - 5.0, "overcasting with no ink costs health")
	_check(cs.strain_t > 0.0, "overcasting shows strain")
	await _step(w, 10)
	# A hit can break the read.
	var broke := false
	for tries in 30:
		w.player.mana = Game.max_mana()
		w.player.hp = Game.max_hp()
		w.read_held = true
		await _step(w, 2)
		w.hurt(1.0)
		if cs.last_result == "broken":
			broke = true
		w.read_held = false
		await _step(w, 8)
		if broke:
			break
	_check(broke, "taking a hit can break a read")
	# Monsters telegraph: an Inkling next to you winds up before it bites.
	_clear(w)   # no lingering zone from the casts above may stagger it
	w.spawn(true)
	var foe = w.enemies[0]
	foe.position = w.player.position + Vector2(30, 0)
	foe.aggro = true
	var saw_windup := false
	for f in 40:
		await _step(w, 1)
		if foe.state == "windup":
			saw_windup = true
			break
	_check(saw_windup, "monsters wind up before they strike")

	print("Writing ink at rest (Phase 2):")
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	Game.ch.ink = 3
	Game.ch.spells[0].lvl = 2
	var lvl0: int = Game.ch.spells[0].lvl
	w.finish_rest()
	await get_tree().create_timer(2.0).timeout
	_check(w.rest_ui.writing, "a rest with writing ink opens the pages")
	if shots:
		_shot("test_4b_writing")
	w.rest_ui.write_into(0)
	_check(Game.ch.spells[0].lvl == lvl0 + 1 and Game.ch.ink == 2, "clicking a page writes ink into it")
	w.rest_ui.close()
	await get_tree().create_timer(0.8).timeout
	_check(not w.paused, "closing the book returns to the field")
	w.spawn(true)
	w.spawn(true)
	print("Field:")
	cs.turn_to(0)
	for k in 30:
		var near = w.nearest(w.player.position, 500.0)
		if near != null:
			w.bot_aim = near.position
		cs.turn_to(k % 3)
		w.player.mana = Game.max_mana()
		await _step(w, 12)
		await _read(w, float(cs.stats_for(cs.page).read) + 0.2)
		if k == 10 and shots:
			_shot("test_4_fight")
	w.dev_complete_trigger()
	w.gain_xp(300)
	if shots:
		_shot("test_5_field")
	w.ch.aspect.awakened = true
	w.open_book()
	await get_tree().create_timer(0.3).timeout
	if shots:
		_shot("test_6_book")
	w.book.close()
	await _step(w, 30)
	print("Discoveries (Phase 3):")
	await _test_discoveries(w)
	print("Polish (The Unwritten, Phase 1):")
	var keep_world: Dictionary = Game.world
	await _test_polish(w)
	print("The Unwritten (Phase 2):")
	await _test_unwritten(w)
	Game.world = keep_world
	print("The Unwritten (Phase 3): monster inks and branching growth:")
	await _test_inks(w)
	Game.world = keep_world
	print("Saves (Phase 2):")
	_test_migration()
	print("Autotest finished with %d failure(s). Level %d, enemies alive %d" % [failures, w.ch.level, w.enemies.size()])
	Game.delete_save()
	get_tree().quit(1 if failures > 0 else 0)


## An old (version 1) save must load with its book, levels and hidden chapter intact.
func _test_migration() -> void:
	var old := {
		"name": "Old", "bg": "sailor", "el": "earth", "thick": "medium", "pages": 180,
		"spells": [{"i": 0, "lvl": 6}, {"i": 2, "lvl": 4}], "ink": 3, "level": 9, "xp": 40,
		"aspect": {"id": "echo", "progress": 5, "stage": 2, "awakened": false, "margins": ["a", "b"], "need": 9, "streak": 10},
		"signals": {}, "use": {}, "temper": {},
	}
	var d: Dictionary = Game.parse_save(JSON.stringify(old))
	_check(int(d.get("save_version", 0)) == GameData.SAVE_VERSION, "an old save is migrated to version %d" % GameData.SAVE_VERSION)
	_check(d.el == "earth" and d.thick == "medium" and int(d.level) == 9 and d.spells.size() == 2 and int(d.spells[0].lvl) == 6, "the migrated save keeps its book and levels")
	_check(d.aspect.id == "echo" and int(d.aspect.progress) == 5 and d.aspect.margins.size() == 2, "the migrated save keeps hidden-chapter progress")
	_check(d.ui.book and d.ui.journal and d.ui.margins and not d.ui.map, "an old player's interface starts unlocked (except the map)")


func _clear(w) -> void:
	w.spawn_t = 60.0   # no new monster wanders into the middle of a test
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	w.zones.clear()
	w.projectiles.clear()


func _spawn_at(w, tier: int, p: Vector2):
	var e = preload("res://scripts/world/enemy.gd").new()
	e.setup(w, tier, p)
	w.actors.add_child(e)
	w.enemies.append(e)
	return e


func _spell(el: String, i: int) -> Dictionary:
	var st: Dictionary = GameData.SPELLS[el][i].duplicate()
	st.el = el
	st.tier = 0
	return st


func _test_discoveries(w) -> void:
	# Content counts.
	var aff_ok := true
	for foe in GameData.FOES:
		if GameData.AFFINITIES.get(foe.name, {}).size() < 2:
			aff_ok = false
	_check(aff_ok, "every monster type has at least 2 affinities")
	var sec_ok := true
	for el in GameData.SPELLS:
		for sp in GameData.SPELLS[el]:
			if not GameData.SECRETS.has(sp.name):
				sec_ok = false
	_check(sec_ok and GameData.SECRETS.size() == 15, "every spell has a secret (15)")
	_check(GameData.TERRAIN_LINES.size() >= 4 and GameData.TERRAIN.patches.size() == 4, "4 kinds of ground react to elements")
	# Terrain: an Ember Bolt fired across dry grass sets it alight.
	_clear(w)
	w.paused = false
	var grass: Dictionary = {}
	for pt in w.terrain.patches:
		if pt.kind == "grass":
			grass = pt
			break
	w.player.position = grass.p + Vector2(-grass.r - 60.0, 0)
	w.perform(_spell("fire", 0), grass.p, "player", 1.0)
	await _step(w, 20)
	var burning := false
	for z in w.zones:
		if String(z.st.get("name", "")) == "grass fire":
			burning = true
	_check(burning and grass.burnt > 0.0, "fire on dry grass starts a burning zone")
	_check(GameData.TERRAIN_LINES.grass_fire in Game.ch.journal, "the journal writes it down once: \"%s\"" % GameData.TERRAIN_LINES.grass_fire)
	# Affinity: after seeing Blots flinch from fire a few times, it's in the bestiary.
	_clear(w)
	var blot = _spawn_at(w, 1, w.player.position + Vector2(200, 0))
	for k in int(GameData.DISCOVERY.affinity_seen):
		w.hit(blot, 1.0, "fire", "player")
	_check(w.discovery.knows("Blot", "fire") and GameData.AFFINITIES.Blot.fire.line in w.discovery.bestiary_lines(), "a seen affinity reaches the bestiary")
	_check(w.discovery.mira_bonus(blot, "water") > 0.0, "Mira favors showing an untaught reaction")
	# Spell secret: a Spark into a puddle arcs to everything standing in it.
	_clear(w)
	var pool: Dictionary = {}
	for pt in w.terrain.patches:
		if pt.kind == "puddle":
			pool = pt
			break
	var a = _spawn_at(w, 0, pool.p + Vector2(-8, 0))
	var _b = _spawn_at(w, 0, pool.p + Vector2(pool.r * 0.6, pool.r * 0.4))
	var far = _spawn_at(w, 0, pool.p + Vector2(0, -pool.r * 0.7))
	w.player.position = pool.p + Vector2(-pool.r - 120.0, 0)
	var hp_far: float = far.hp
	w.perform(_spell("lightning", 0), a.position, "player", 1.0)
	_check(w.discovery.found("Spark") and far.hp < hp_far, "Spark into a puddle reaches everything in it (a spell secret)")
	_check(GameData.SECRETS.Spark.line in w.all_margins(), "the secret is written into the margins")
	var dv: String = w.discovery.designer_text()
	_check(dv.contains("✓ Spark") and dv.contains("· Gust"), "F1 lists discovered and undiscovered secrets")
	_clear(w)


func _turn_and_read(w, page: int, aim: Vector2, hold: float) -> String:
	w.casting.turn_to(page)
	await _step(w, 30)
	w.bot_aim = aim
	w.player.mana = Game.max_mana()
	return await _read(w, hold)


func _test_hands(w) -> void:
	var keep_signals: Dictionary = Game.ch.signals.duplicate()
	var keep_auto: bool = w.auto_rest_ui
	w.auto_rest_ui = true
	_clear(w)
	w.player.hp = Game.max_hp()
	var home: Vector2 = w.player.position
	# Learn a move from a monster: dodge an Inkling's strike enough times, then rest.
	var ink = _spawn_at(w, 0, home + Vector2(40, 0))
	for k in int(GameData.HAND_LESSONS.Inkling.need):
		w.player.dodge_t = 0.3
		w.enemy_strike(ink)
	_check(not w.hands.knows("flank"), "a lesson isn't learned until you rest")
	w.finish_rest()
	_check(w.hands.knows("flank") and w.casting.page_count() == 4, "after a rest, dodging Inklings has taught Flank Step (a 4th stance)")
	_check(GameData.HAND_LESSONS.Inkling.line in Game.ch.journal, "the journal says so: \"%s\"" % GameData.HAND_LESSONS.Inkling.line)
	# Flank Step circles behind the monster.
	_clear(w)
	w.player.position = home
	var foe = _spawn_at(w, 0, home + Vector2(110, 0))
	foe.spd = 0.0
	await _turn_and_read(w, 3, foe.position, 0.4)
	_check(w.player.position.x > home.x + 110.0 and foe.hp < foe.max_hp, "Flank Step ends behind the monster and hits it")
	# Growth: enough meaningful Jabs and the next rest makes every Jab land twice.
	Game.ch.hands.uses.jab = int(GameData.HAND_GROWTH.jab.at[0])
	w.finish_rest()
	_check(w.hands.tier("jab") == 1 and GameData.HAND_GROWTH.jab.lines[0] in Game.ch.journal, "enough real Jabs grow the Jab at the next rest")
	_clear(w)
	w.player.position = home
	foe = _spawn_at(w, 0, home + Vector2(45, 0))
	foe.spd = 0.0
	foe.hp = 5000.0
	foe.max_hp = 5000.0
	w.casting.turn_to(0)
	await _step(w, 30)
	w.bot_aim = foe.position
	w.read_held = true
	await _step(w, roundi(GameData.BARE_HANDS[0].read / DT) + 2)
	w.read_held = false
	await _step(w, 2)
	var after_first: float = foe.hp
	await _step(w, 12)
	_check(foe.hp < after_first and after_first < foe.max_hp, "a grown Jab lands a second time")
	# Sidestep grows a decoy that monsters bite instead of you.
	Game.ch.hands.tier.sidestep = 1
	_clear(w)
	w.player.position = home
	await _turn_and_read(w, 2, home + Vector2(200, 0), 0.2)
	_check(w.decoy_t > 0.0 and w.decoy_p.distance_to(home) < 5.0, "a grown Sidestep leaves an ink decoy where you stood")
	var biter = _spawn_at(w, 0, w.decoy_p + Vector2(-20, 0))
	var hp0: float = w.player.hp
	w.player.dodge_t = 0.0
	w.enemy_strike(biter)
	_check(w.player.hp == hp0 and w.decoy_t <= 0.0, "a monster closer to the decoy bites it instead of you")
	# Brace, learned from a Knight: blows from the front glance off.
	Game.ch.hands.learned.append("brace")
	_clear(w)
	w.player.position = home
	var knight = _spawn_at(w, 2, home + Vector2(60, 0))
	knight.aggro = false
	await _turn_and_read(w, 4, knight.position, 0.4)
	hp0 = w.player.hp
	w.enemy_strike(knight)
	_check(w.brace_t > 0.0 and hp0 - w.player.hp < knight.dmg * 0.3 and knight.state == "stagger", "Brace turns a blow from the front aside, and the attacker reels")
	# A hand secret: Sidestep then Jab is a backhand.
	_clear(w)
	var b = _spawn_at(w, 1, home + Vector2(40, 0))
	w.last_move = "sidestep"
	w.last_move_t = w.time
	w.hit(b, 10.0, "none", "player", "jab")
	_check(w.hands.found("backhand") and GameData.HAND_SECRETS.backhand.line in Game.ch.journal, "a hand secret (Sidestep, then Jab) goes in the journal")
	# Hands tint toward the leaning element.
	Game.ch.signals = {"chain": 40.0, "streak_kill": 10.0}
	var tint: Color = w.hands.tint()
	_check(tint.a > 0.0 and tint.is_equal_approx(Color(GameData.COLORS.fire, tint.a)), "your fist tints toward the element you lean to (fire here)")
	_check(w.designer.has_method("toggle") and w.hands.designer_text().contains("Flank Step"), "F1 lists lessons, growth and hand secrets")
	# Put things back for the rest of the test.
	Game.ch.signals = keep_signals
	Game.ch.hands = Game._hands_fields()
	w.decoy_t = 0.0
	w.brace_t = 0.0
	w.bot_aim = null
	w.casting.turn_to(0)
	await _step(w, 30)
	w.auto_rest_ui = keep_auto
	_clear(w)


# ================================================================ The Unwritten, Phase 1: polish

## A separate world with no scene switching attached, for tests that would otherwise
## jump to the ceremony screen.
func _side_world():
	var sw = World.new()
	add_child(sw)
	await get_tree().process_frame
	sw.set_process(false)
	_clear(sw)
	return sw


func _bare_char(level := 1) -> Dictionary:
	var c := Game.new_character("Test", "orphan")
	c.level = level
	return c


func _book_char(el := "earth", aspect := "stillness") -> Dictionary:
	var c := Game.new_character("Test", "orphan")
	c.el = el
	c.thick = "medium"
	c.level = 6
	c.spells = [{"i": 0, "lvl": 3}, {"i": 1, "lvl": 2}]
	c.aspect = {"id": aspect, "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 4, "streak": 3}
	c.ui.book = true
	return c


func _test_polish(main_w) -> void:
	var keep: Dictionary = Game.ch
	var keep_settings: Dictionary = Game.settings.duplicate()
	main_w.set_process(false)
	main_w.visible = false
	main_w.hud.visible = false

	# -- Settings and the pause menu
	Game.ch = _bare_char()
	var w = await _side_world()
	w.pause_ui.open()
	_check(w.pause_ui.visible and w.paused, "Esc / Start opens the pause menu and the world waits")
	var lines: Array = w.pause_ui.key_lines(Game.ch)
	var labels: Array = lines.map(func(l): return l[0])
	_check("Walk" in labels and not ("The last page" in labels) and not ("Open my book" in labels), "the key page lists only what this character has found (no book, no last page yet)")
	var lp := _book_char("fire", "lastpage")
	lp.aspect.awakened = true
	_check("The last page" in w.pause_ui.key_lines(lp).map(func(l): return l[0]), "the last page appears on the key page only once it has awakened")
	var shake0: bool = Game.settings.shake
	w.pause_ui._cycle("shake")
	_check(Game.settings.shake != shake0, "a setting changes from the pause menu")
	var cf := ConfigFile.new()
	_check(cf.load(Game.SETTINGS_PATH) == OK and bool(cf.get_value("settings", "shake")) == Game.settings.shake, "settings are saved to the settings file")
	w.pause_ui._cycle("ui_scale")
	_check(not is_equal_approx(w.hud.scale.x, 1.0) and is_equal_approx(w.hud.scale.x, float(Game.settings.ui_scale)), "the page size setting scales the interface")
	w.pause_ui.close()
	_check(not w.paused, "closing the pause menu returns to the world")
	_check(not GameData.SETTINGS.shake and GameData.SETTINGS.hitstop, "shake starts off and hit-pause starts on")
	Game.settings.hitstop = true
	var foe = _spawn_at(w, 1, w.player.position + Vector2(60, 0))
	w.hit(foe, foe.max_hp * 0.3, "none", "player")
	_check(w.hitstop > 0.0, "a heavy hit holds the world still for a moment (hit-pause on)")
	w.hitstop = 0.0
	Game.settings.hitstop = false
	w.hit(foe, foe.max_hp * 0.3, "none", "player")
	_check(w.hitstop == 0.0, "no hit-pause when the setting is off")
	_clear(w)

	# -- Gamepad
	var pad_ok := true
	for pair in [["journal", JOY_BUTTON_DPAD_UP], ["map", JOY_BUTTON_DPAD_DOWN], ["pause", JOY_BUTTON_START], ["open_book", JOY_BUTTON_BACK], ["read", JOY_BUTTON_A], ["rest", JOY_BUTTON_Y]]:
		var found := false
		for ev in InputMap.action_get_events(pair[0]):
			if ev is InputEventJoypadButton and ev.button_index == pair[1]:
				found = true
		pad_ok = pad_ok and found
	var stick := false
	for ev in InputMap.action_get_events("move_left"):
		if ev is InputEventJoypadMotion:
			stick = true
	_check(pad_ok and stick, "a gamepad can move, read, rest, and open the journal, map, book and pause menu")

	# -- First hour fixes
	w.player.position = Vector2(0, 40)
	Game.ch.xp = Game.xp_next(1) + 1
	for f in roundi(float(GameData.NUDGES.rest_fire.after) / DT) + 10:
		w._update(DT)
	_check(Game.ch.nudged.get("rest", false), "with a level waiting, sitting by the Hearth fire shows the R nudge")
	Game.ch.ui.map = true
	Game.ch.opened.erase("map")
	w.nudge_t = 0.0
	for f in roundi(float(GameData.NUDGES.map.after) / DT) + 10:
		w._update(DT)
	_check(Game.ch.nudged.get("map", false), "a map that was never opened gets an M nudge")
	w.designer._refresh()
	_check(w.designer.text.text.contains("Pacing and feel") and w.designer.text.text.contains("map ✓"), "F1 shows the Phase 1 pacing values")
	var lurker = _spawn_at(w, 0, Vector2(GameData.TOWN_RADIUS + 30.0, 0))
	lurker.aggro = true
	_check(w.can_rest(), "nothing can wake you inside the Hearth")
	for f in roundi((float(GameData.MONSTERS.hearth_give_up) + 1.0) / DT):
		w._update(DT)
	_check(not lurker.aggro, "a monster pacing at the Hearth's edge gives up and wanders off")
	_clear(w)
	Game.ch.hands.lessons = {"Inkling": 99, "Blot": 99}
	Game.ch.hands.uses = {"jab": 999}
	var got: Array = w.hands.on_rest()
	_check(got.size() == int(GameData.HAND_REST_MAX), "only one new move or growth per rest; the rest wait for the next one")
	w.unlock("journal")
	w.hud.whisper_queue.clear()
	w.hud.whispering = false
	for t in ["one", "two", "three"]:
		w.hud.add_log(t)
	_check(w.hud.whisper.text == "one" and w.hud.whisper_queue.size() == 2, "journal lines that arrive together wait their turn")
	for k in int(GameData.FEEL.splat_max) + 20:
		w._splat(Vector2.ZERO, 5.0, 30.0, 0.3)
	_check(w.splats.size() == int(GameData.FEEL.splat_max), "lingering splatters are capped")
	w.queue_free()
	await get_tree().process_frame

	# -- Hidden chapter hints are spaced out
	Game.ch = _book_char()
	w = await _side_world()
	for k in 4:
		w.chapter.progress()
	w._update(DT)
	var st1: int = int(Game.ch.aspect.stage)
	for f in 30:
		w._update(DT)
	var st2: int = int(Game.ch.aspect.stage)
	for f in roundi(float(GameData.CHAPTER_TUNING.hint_gap) / DT) + 2:
		w.chapter.tick(DT)
	_check(st1 == 1 and st2 == 1 and int(Game.ch.aspect.stage) == 2, "margin hints come one at a time, well apart")

	# -- Edge case: the hidden chapter awakens in the middle of a read
	w.chapter.flush_hints()
	var near_foe = _spawn_at(w, 0, w.player.position + Vector2(120, 0))
	near_foe.spd = 0.0
	w.player.mana = Game.max_mana()
	w.read_held = true
	await _step(w, 4)
	var mana_mid: float = w.player.mana
	_check(w.casting.reading and mana_mid < Game.max_mana(), "(setup) reading has started and ink was paid")
	w.player.still = 1.0
	w.open_book()
	_check(Game.ch.aspect.awakened, "(setup) the chapter awakened when the book was opened")
	_check(not w.casting.reading and w.casting.last_result == "cancelled" and absf(w.player.mana - Game.max_mana()) < 0.01, "opening the book mid-read closes the page and gives the ink back")
	w.book.close()
	var casts0: int = w.casting.casts
	await _step(w, 20)
	_check(w.casting.casts == casts0 and not w.casting.reading, "still holding the key afterwards doesn't cast by itself")
	w.read_held = false
	await _step(w, 2)

	# -- Edge case: dying while reading
	w.read_held = true
	await _step(w, 3)
	w.hurt(99999.0)
	_check(w.player.dead_t > 0.0 and not w.casting.reading, "dying in the middle of a read ends it")
	await _step(w, roundi(3.0 / DT))
	_check(w.player.dead_t <= 0.0 and not w.casting.reading and w.casting.casts == casts0, "after waking, holding the key from before doesn't cast")
	w.read_held = false
	await _step(w, 2)
	w.queue_free()
	await get_tree().process_frame

	# -- Edge case: resting again while the ceremony is opening
	Game.ch = _bare_char(GameData.CEREMONY_LEVEL)
	w = await _side_world()
	var calls := [0]
	w.go_to_ceremony.connect(func(): calls[0] += 1)
	w.player.position = Vector2(0, 30)
	w.finish_rest()
	w.finish_rest()
	w.rest_ui.close()
	await get_tree().create_timer(0.8).timeout
	_check(calls[0] == 1, "resting twice while the ceremony is opening opens it once (%d)" % calls[0])
	w.queue_free()
	await get_tree().process_frame

	# -- Saves at every stage of the interface appearing
	var stages := [[], ["hands"], ["hands", "journal"], ["hands", "journal", "margins"], ["hands", "journal", "margins", "map"]]
	var all_ok := true
	for book_too in [false, true]:
		for stg in stages:
			var c: Dictionary = _book_char() if book_too else _bare_char(3)
			for k in GameData.UI_PARTS:
				c.ui[k] = k in stg or (k == "book" and book_too)
			Game.ch = c
			Game.save_game()
			var back: Dictionary = Game.load_game()
			var same := true
			for k in GameData.UI_PARTS:
				same = same and bool(back.ui[k]) == bool(c.ui[k])
			Game.ch = back
			var lw = await _side_world()
			await get_tree().process_frame
			var dock_on: bool = lw.hud.dock.modulate.a > 0.5
			var want_dock: bool = (book_too and back.ui.book) or (not book_too and back.ui.hands)
			var mark_on: bool = lw.hud.journal_mark.modulate.a > 0.5
			if not (same and dock_on == want_dock and mark_on == bool(back.ui.journal)):
				all_ok = false
				print("    stage %s (book %s): same %s dock %s/%s mark %s" % [stg, book_too, same, dock_on, want_dock, mark_on])
			lw.queue_free()
			await get_tree().process_frame
	_check(all_ok, "saving and loading at every stage of the interface keeps exactly what had appeared")

	Game.settings = keep_settings
	Game.set_setting("shake", keep_settings.shake)
	Game.ch = keep
	main_w.visible = true
	main_w.hud.visible = true
	await get_tree().process_frame


# ================================================================ The Unwritten, Phase 2

func _test_unwritten(main_w) -> void:
	var keep: Dictionary = Game.ch
	var keep_settings: Dictionary = Game.settings.duplicate()
	main_w.set_process(false)
	main_w.visible = false
	main_w.hud.visible = false
	var L = GameData.Lore
	Game.ch = _book_char("fire", "stillness")
	var w = await _side_world()
	var er = w.erasure
	var all_bare := true
	for s in L.SITES:
		all_bare = all_bare and String(er.state(s.id).state) == "erased" and er.paleness(s.id) == 1.0
	_check(all_bare and L.SITES.size() >= 6, "a new world starts with every erasure site bare (%d sites)" % L.SITES.size())
	var per_region := {1: 0, 2: 0, 3: 0}
	for s in L.SITES:
		per_region[int(s.region)] += 1
	_check(per_region.values().all(func(n): return n >= 2 and n <= 3), "each region has two or three sites")

	# -- Near a bare site
	var st0: Dictionary = L.SITES[0]
	_check(er.strength(st0.p) > 0.99 and er.read_speed(st0.p) < 1.0 and er.ink_regen(st0.p) < 1.0 and er.read_speed(Vector2(0, 0)) == 1.0,
		"near a bare site spells read slower and ink comes back slower, and nowhere else")
	w.terrain.patches.append({"kind": "grass", "p": st0.p + Vector2(10, 0), "r": 40.0, "burnt": 0.0, "sd": 0.0, "faded": false})
	er._fade_patches()
	_check(w.terrain.at(st0.p + Vector2(10, 0), "grass") == null, "ground near a bare site has faded: grass there won't burn")
	var gathered := 0
	for k in 200:
		var gp = er.gather_point(st0.p + Vector2(300, 0))
		if gp != null and gp.distance_to(st0.p) < float(st0.r) * 1.2:
			gathered += 1
	_check(gathered > 15 and gathered < 160, "monsters gather at a bare site close by (%d of 200 new ones)" % gathered)

	# -- The guardian
	w.player.position = st0.p + Vector2(float(st0.r) + 120.0, 0)
	w._update(DT)
	var g = er.guardians.get(st0.id)
	_check(er.guardian_alive(st0.id) and g.hp > float(GameData.FOES[int(L.GUARDIANS[1].tier)].hp) * 2.0 and w.enemies.size() >= 2,
		"coming close wakes the site's guardian and its escorts")
	var during := 0
	for k in 100:
		var gp2 = er.gather_point(st0.p + Vector2(300, 0))
		if gp2 != null and gp2.distance_to(st0.p) < float(st0.r) * 1.2:
			during += 1
	_check(during == 0, "while its guardian is awake, no more monsters gather at that site")
	_check(is_equal_approx(w._affinity(g, "fire", "player"), 1.0) and is_equal_approx(w._affinity(g, "water", "player"), 1.0), "guardians are made of the pale: no element moves them more than another")
	g.position = st0.p + Vector2(float(st0.r) * float(L.GUARDIAN_LEASH) + 40.0, 0)
	w.player.position = st0.p + Vector2(float(st0.r) * float(L.GUARDIAN_LEASH) + 400.0, 0)
	g.tick(DT)
	_check(not g.aggro, "a guardian won't chase you far from its site")
	w.player.position = st0.p
	_check(not w.can_rest(), "you can't rest at a site while its guardian is awake")
	w.kill(g, "player")
	_check(String(er.state(st0.id).state) == "cleared" and Game.ch.journal_ids.has("guardian_first"), "beating the guardian clears the site, and the journal notices")
	_clear(w)
	w._update(DT)
	_check(not er.guardian_alive(st0.id) and w.enemies.size() == 0, "a cleared site doesn't wake another guardian")

	# -- Writing it back
	w.auto_rest_ui = true
	w.player.steer = Vector2.ZERO
	w.player.position = st0.p
	w.rest_held = true
	for f in roundi((float(GameData.REST.time) + 0.5) / DT):
		w._update(DT)
	w.rest_held = false
	_check(er.is_restored(st0.id) and er.paleness(st0.id) == 0.0, "resting at the centre of a cleared site writes it back")
	_check(Game.ch.journal_ids.has("restore_first") and Game.ch.journal_ids.has("site_" + st0.id), "the journal remembers writing it back")
	_check(st0.p in er.campfires() and er.fx.has(st0.id), "a campfire appears there, and the ink spreads back over it")
	var calm := 0
	for k in 400:
		if er.calm(st0.p + Vector2(20, 0)):
			calm += 1
	_check(calm > 200, "fewer monsters appear around a restored site (%d of 400 kept away)" % calm)
	er._fade_patches()
	_check(w.terrain.at(st0.p + Vector2(10, 0), "grass") != null, "the ground there reacts again once it is written back")
	_check(er.read_speed(st0.p) == 1.0, "spells read normally at a restored site")
	w.designer._refresh()
	var dtxt: String = w.designer.text.text
	_check(dtxt.contains("Erasure sites") and dtxt.contains("Torn pages") and dtxt.contains("restored"), "F1 shows the sites, their state and the torn pages")

	# -- Torn pages
	var pg = w.pages
	var ledger: Dictionary = pg.by_id("ledger")
	_check(String(ledger.site) == st0.id and pg.where(ledger) != null, "a torn page appears at the site once it is written back")
	_check(pg.where(pg.by_id("spilled_ink")) == null, "pages at sites still bare aren't there yet")
	w.player.position = pg.where(ledger)
	w._update(DT)
	_check(Game.ch.fragments == ["ledger"] and Game.ch.journal_ids.has("fragment_first"), "walking over a torn page picks it up, and the first one writes a journal line")
	var hymn: Dictionary = pg.by_id("hymn")
	w.player.position = hymn.p
	w._update(DT)
	_check(Game.ch.fragments == ["ledger", "hymn"], "pages are kept in the order found, not in story order")
	var stacks := 0
	var placed_in_stacks := 0
	for f in L.FRAGMENTS:
		if String(f.where) == "stacks":
			stacks += 1
			if pg.where(f) != null:
				placed_in_stacks += 1
	_check(L.FRAGMENTS.size() == 12 and stacks == 3 and placed_in_stacks == 0, "twelve torn pages; the last three wait in the Stacks and aren't lying anywhere yet")
	_check("Torn pages I found" in w.pause_ui.key_lines(Game.ch).map(func(l): return l[0]), "the key page lists the torn pages once one is found")
	w.open_book()
	_check(w.book.visible and w.book.pages_btn.visible, "the book has its torn pages at the back")
	w.book.pages_btn.pressed.emit()
	_check(w.fragments_ui.visible and not w.book.visible, "turning to them shows the torn pages")
	w.close_overlays()
	_check(w.book.visible and not w.fragments_ui.visible, "putting them away goes back to the book")
	w.close_overlays()
	w.fragments_ui.open(null)
	_check(w.fragments_ui.visible and w.fragments_ui.sheet.title == String(hymn.title), "the torn pages open on the newest one")
	w.fragments_ui.turn(-1)
	_check(w.fragments_ui.sheet.title == String(ledger.title), "and turn back to the older ones")
	_check(not w.fragments_ui.sheet.body.is_valid_int() and not w.fragments_ui.counter.text.contains("1"), "no numbers on the torn pages")
	w.close_overlays()
	_check(not w.fragments_ui.visible and not w.paused, "Esc puts the torn pages away")

	# -- Slow re-erasure
	var ws: Dictionary = Game.world
	var R: Dictionary = L.REERASE
	w.region = 2
	ws.seen["1"] = float(ws.time) - float(R.grace) * 0.5
	er.tick(1.0)
	_check(er.paleness(st0.id) == 0.0, "a restored site doesn't fade while its region was visited recently")
	ws.seen["1"] = float(ws.time) - float(R.grace) - 1.0
	for k in 20:
		er.tick(float(R.fade_time) * float(R.warn_at) / 10.0)
	_check(er.paleness(st0.id) > float(R.warn_at) and Game.ch.journal_ids.has("reerase_first") and er.is_restored(st0.id),
		"left alone long enough, a restored site starts to fade, and the journal notices")
	w.region = 1
	var p1: float = er.paleness(st0.id)
	er.tick(60.0)
	_check(is_equal_approx(er.paleness(st0.id), p1), "visiting the region stops the fading")
	w.region = 2
	Game.settings.reerase = false
	ws.seen["1"] = float(ws.time) - float(R.grace) - 1.0
	er.tick(float(R.fade_time))
	_check(is_equal_approx(er.paleness(st0.id), p1), "with the setting off, nothing fades")
	Game.settings.reerase = true
	for k in 10:
		er.tick(float(R.fade_time) / 4.0)
	_check(String(er.state(st0.id).state) == "erased" and not (st0.p in er.campfires()), "fully faded, the site is bare again and its fire goes out")
	w.player.position = st0.p + Vector2(float(st0.r) + 100.0, 0)
	er.tick(DT)
	_check(er.guardian_alive(st0.id), "and its guardian comes back")
	_check(Game.ch.fragments.size() == 2, "torn pages already found stay found")

	# -- Saves
	var st1: Dictionary = L.SITES[1]
	er.restore(String(st1.id))
	Game.save_game()
	var back: Dictionary = Game.load_game()
	_check(back.fragments == ["ledger", "hymn"] and String(Game.world.sites[st1.id].state) == "restored" and String(Game.world.sites[st0.id].state) == "erased",
		"saving and loading keeps the world (sites written back, faded) and the torn pages")
	var old := _book_char("water", "echo")
	old.erase("fragments")
	old.save_version = 4
	old.level = 9
	var mig: Dictionary = Game.migrate(old.duplicate(true))
	_check(int(mig.save_version) == GameData.SAVE_VERSION and mig.fragments == [] and int(mig.level) == 9 and String(mig.el) == "water" and String(mig.aspect.id) == "echo",
		"an older save gains torn pages without losing its book, level or chapter")
	var fresh: Dictionary = Game.migrate_world({"sites": {st1.id: {"state": "restored", "pale": 0.2}}})
	_check(String(fresh.sites[st1.id].state) == "restored" and fresh.sites.size() == L.SITES.size(), "an older world keeps what was written back and gains any new sites")
	w.queue_free()
	await get_tree().process_frame

	Game.settings = keep_settings
	Game.ch = keep
	main_w.visible = true
	main_w.hud.visible = true
	await get_tree().process_frame


# ================================================================ The Unwritten, Phase 3: inks

## True if `t` has no digits in it (players never see numbers).
func _no_digits(t: String) -> bool:
	for c in t:
		if c >= "0" and c <= "9":
			return false
	return true


## A book character whose page i is at `lvl`, for the branch tests.
func _ink_char(el: String, thick: String, lvls: Array) -> Dictionary:
	var c := _book_char(el, "stillness")
	c.thick = thick
	c.spells = []
	var idx: Array = [0, 1, 2]
	for k in lvls.size():
		c.spells.append({"i": idx[k], "lvl": int(lvls[k]), "inks": [], "branch": []})
		for j in int(lvls[k]) - 1:
			c.spells[k].inks.append("plain")
	c.ink = 30
	c.ui.vials = true
	c.journal_ids.first_kill = true
	return c


## How many projectiles a cast of page i makes, and the first one.
func _cast_count(w, i: int) -> Array:
	w.projectiles.clear()
	w.perform(Game.spell_stats(w.ch.spells[i]), w.player.position + Vector2(200, 0), "player", 1.0)
	return [w.projectiles.size(), w.projectiles[0] if not w.projectiles.is_empty() else {}]


func _test_inks(main_w) -> void:
	var keep: Dictionary = Game.ch
	main_w.set_process(false)
	main_w.visible = false
	main_w.hud.visible = false
	var I = GameData.Inks
	var IR = preload("res://scripts/world/inks.gd")

	# -- The data: every monster has its ink, every kind of spell its branches
	var from := {}
	for k in I.INKS:
		from[String(I.INKS[k].from)] = k
	_check(from.get("Inkling") == "quick" and from.get("Blot") == "heavy" and from.get("Smudge Knight") == "stubborn" and from.get("guardian") == "pale",
		"Inklings leave quick ink, Blots heavy, Knights stubborn, and guardians the rare pale")
	var kinds_ok := true
	for kind in ["bolt", "chain", "nova", "zone", "wall", "dash"]:
		for ink in ["quick", "heavy", "stubborn"]:
			var b: Dictionary = I.BRANCHES.get(kind, {}).get(ink, {})
			kinds_ok = kinds_ok and String(b.get("name", "")) != "" and String(b.get("line", "")) != "" and _no_digits(String(b.line))
		kinds_ok = kinds_ok and String(I.PALE.get(kind, {}).get("margin", "")) != "" and String(I.PALE[kind].get("name", "")) != ""
	_check(kinds_ok, "bolt, chain, nova, zone, wall and dash each branch three ways (named, with a line) and have one pale branch")
	var every_spell := true
	for el in GameData.SPELLS:
		for sp in GameData.SPELLS[el]:
			every_spell = every_spell and I.BRANCHES.has(IR.kind_of(sp))
	_check(every_spell and IR.kind_of(GameData.SPELLS.earth[2]) == "wall", "every spell has a branch table (Rampart grows as a wall)")
	var hands_ok := true
	for mv in ["jab", "shove", "sidestep"]:
		for ink in ["quick", "heavy", "stubborn"]:
			hands_ok = hands_ok and I.HAND_BRANCHES.get(mv, {}).has(ink)
	_check(hands_ok, "Jab, Shove and Sidestep can each be dipped in quick, heavy or stubborn ink")

	# -- Drops and vials
	Game.ch = _bare_char(2)
	Game.ch.journal_ids.first_kill = true
	Game.ch.ui.journal = true
	var w = await _side_world()
	var inks = w.inks
	var e = _spawn_at(w, 0, w.player.position + Vector2(300, 0))
	for k in 80:
		if not inks.drops.is_empty():
			break
		inks.on_kill(e)
	_check(not inks.drops.is_empty() and String(inks.drops[0].ink) == "quick", "an Inkling that comes apart can leave a drop of quick ink")
	var dr: Dictionary = inks.drops[0]
	inks.drops = [dr]
	dr.p = w.player.position + Vector2(float(I.DROP.pull) - 10.0, 0)
	var d0: float = dr.p.distance_to(w.player.position)
	inks.tick(0.1)
	_check(dr.p.distance_to(w.player.position) < d0, "a drop close by slides toward you")
	for k in 30:
		inks.tick(0.1)
	_check(inks.dose("quick") == 1 and inks.drops.is_empty() and w.ch.ui.vials, "walking over it puts it in a vial, and the vials appear")
	_check(w.ch.journal_ids.has("ink_first_drop") and w.ch.journal_ids.has("ink_quick"), "the journal notices the first drop, and what the quick ink is like")
	w.ch.vials.quick = int(I.INKS.quick.cap)
	inks.drops = [{"p": w.player.position, "ink": "quick", "t": 0.0}]
	inks.tick(0.1)
	_check(inks.drops.size() == 1 and inks.dose("quick") == int(I.INKS.quick.cap), "a full vial leaves new drops lying")
	var gd = _spawn_at(w, 0, w.player.position + Vector2(300, 0))
	gd.guardian = "bare_stile"
	inks.drops.clear()
	inks.on_kill(gd)
	_check(inks.drops.size() == 1 and String(inks.drops[0].ink) == "pale", "a guardian always leaves pale ink (until the book has had its pale)")
	inks.pick_up(inks.drops[0])
	_check(inks.dose("pale") == 1 and "pale" in inks.carried() and not "pale" in inks.dip_pots() and w.ch.journal_ids.has("ink_first_pale"),
		"bare hands are never offered the pale: it waits for a book")
	w.hud.refresh(DT)
	_check(w.hud.vials.modulate.a >= 0.0 and _no_digits(w.hud.whisper.text), "the vials show how full they are, with no numbers")

	# -- Bare hands steered by ink
	w.ch.vials = {"quick": 0, "heavy": 2, "stubborn": 0, "pale": 1}
	w.ch.hands.uses.jab = int(GameData.HAND_GROWTH.jab.at[0])
	var plain_jab: Dictionary = Game.bare_stats(0)
	w.finish_rest()
	_check(inks.dip_waiting() == "jab" and w.rest_ui.visible, "when a move grows and you carry monster ink, the rest asks whether to dip your hands")
	await get_tree().create_timer(4.5).timeout
	_check(w.rest_ui.dipping and w.rest_ui.pots_box.visible and w.rest_ui.pots_row.get_child_count() == 1 and _no_digits(w.rest_ui.pots_lbl.text),
		"the pots stand there (heavy only: never the pale), with no numbers")
	w.rest_ui.dip_into("heavy")
	var heavy_jab: Dictionary = Game.bare_stats(0)
	_check(w.ch.hands.branch.jab == ["heavy"] and inks.dose("heavy") == 1 and float(heavy_jab.dmg) > float(plain_jab.dmg) * 1.2 and float(heavy_jab.read) > float(plain_jab.read),
		"dipped in heavy ink, the Jab hits harder and reads slower")
	_check(w.ch.journal_ids.has("dip_jab_heavy"), "and the journal says how it changed")
	await get_tree().create_timer(0.7).timeout
	w.ch.vials = {}
	w.ch.hands.uses.shove = int(GameData.HAND_GROWTH.shove.at[0])
	w.finish_rest()
	_check(inks.dip_waiting() == "" and w.ch.hands.branch.shove == ["plain"], "with no monster ink, a growing move stays plain and nothing is asked")
	await get_tree().create_timer(4.5).timeout
	if w.rest_ui.visible:
		w.rest_ui.close()
	await get_tree().create_timer(0.7).timeout
	w.queue_free()
	await get_tree().process_frame

	# -- Writing with a pot, and the first branch
	Game.ch = _ink_char("fire", "thin", [3])
	w = await _side_world()
	inks = w.inks
	w.ch.vials = {"quick": 3, "heavy": 3, "stubborn": 3, "pale": 1}
	var plain_st: Dictionary = Game.spell_stats(w.ch.spells[0])
	_check(w.spend_ink(0, "quick") and w.ch.spells[0].inks[-1] == "quick" and inks.dose("quick") == 2, "writing a level from the quick pot spends a dose and is remembered")
	_check(w.ch.spells[0].branch == ["quick"] and Game.spell_name(w.ch.spells[0]).begins_with(String(I.BRANCHES.bolt.quick.name)),
		"at the evolution the page branches toward the ink it was fed, and takes a new name (%s)" % Game.spell_name(w.ch.spells[0]))
	var q_st: Dictionary = Game.spell_stats(w.ch.spells[0])
	_check(float(q_st.read) < float(plain_st.read) and int(q_st.get("count", 0)) >= 1 and float(q_st.size) < 1.0, "quick: a shorter read, more and smaller shots")
	_check(w.ch.journal_ids.has("first_branch") and w.ch.journal_ids.has("branch_bolt_quick"), "the journal notices the first branch")
	# Heavy most used in the next window, with a quick in it too.
	for pot in ["heavy", "quick", "heavy", "plain"]:
		w.spend_ink(0, pot)
	_check(w.ch.spells[0].branch == ["quick", "heavy"], "the next evolution takes the ink used most since the last one (heavy over quick)")
	var h_st: Dictionary = Game.spell_stats(w.ch.spells[0])
	_check(Game.spell_name(w.ch.spells[0]).begins_with(String(I.BRANCHES.bolt.heavy.name)) and float(h_st.size) > float(q_st.size) and float(h_st.get("push", 0.0)) > 0.0,
		"heavy on top: bigger, and it knocks them back")
	_check(IR.choose(["quick", "heavy"], false) == "heavy" and IR.choose(["heavy", "quick"], false) == "quick" and IR.choose(["plain", "plain"], false) == "plain",
		"a tie goes to the newest ink, and plain ink alone makes a plain step")
	# The pale.
	for pot in ["plain", "pale", "stubborn", "stubborn"]:
		w.spend_ink(0, pot)
	_check(w.ch.spells[0].branch[-1] == "pale" and w.ch.pale_used and w.ch.disc.margins.has(String(I.PALE.bolt.margin)),
		"any pale in an evolution makes it the pale branch, with a margin line")
	_check(not "pale" in inks.pots() and Game.spell_name(w.ch.spells[0]).begins_with(String(I.PALE.bolt.name)), "after that the book won't take the pale again")
	var g2 = _spawn_at(w, 0, w.player.position + Vector2(300, 0))
	g2.guardian = "x"
	inks.drops.clear()
	inks.on_kill(g2)
	_check(inks.drops.is_empty(), "and guardians stop leaving it")
	w.queue_free()
	await get_tree().process_frame

	# -- Branches look and play differently (bolts)
	Game.ch = _ink_char("earth", "thin", [8])
	w = await _side_world()
	w.ch.spells[0].branch = ["plain", "plain"]
	var pl: Array = _cast_count(w, 0)
	w.ch.spells[0].branch = ["quick", "quick"]
	var qk: Array = _cast_count(w, 0)
	w.ch.spells[0].branch = ["heavy", "heavy"]
	var hv: Array = _cast_count(w, 0)
	w.ch.spells[0].branch = ["stubborn", "stubborn"]
	var sb: Array = _cast_count(w, 0)
	_check(qk[0] > pl[0] and hv[0] < pl[0], "quick shots are more numerous, heavy ones fewer (%d / %d / %d)" % [qk[0], pl[0], hv[0]])
	_check(float(qk[1].size) < 1.0 and float(hv[1].size) > 1.0 and qk[1].v.length() > pl[1].v.length() and hv[1].v.length() < pl[1].v.length(),
		"quick shots are small and fast, heavy ones big and slow")
	_check(int(sb[1].pierce) > int(pl[1].pierce) and float(sb[1].life) > float(pl[1].life) and String(sb[1].mark) == "stubborn", "stubborn shots pierce further and fly longer")
	w.ch.spells[0].branch = ["pale", "plain"]
	var pa: Array = _cast_count(w, 0)
	w.player.position = Vector2(0, 300)
	for k in 45:
		w._update_projectiles(DT)
	_check(bool(pa[1].turned) and pa[1].v.dot(w.player.position - pa[1].p) > 0.0, "a pale shot turns at the end of its flight and comes back")
	w.queue_free()
	await get_tree().process_frame

	# -- Bursts: heavy throws further, stubborn guards you, pale pulls in
	Game.ch = _ink_char("water", "medium", [5, 5])
	Game.ch.spells[1].i = 1
	w = await _side_world()
	var far := {}
	for b in ["plain", "heavy", "pale"]:
		_clear(w)
		w.player.position = Vector2(0, 400)
		var t = _spawn_at(w, 1, w.player.position + Vector2(60, 0))
		t.hp = 99999.0
		t.max_hp = 99999.0
		w.ch.spells[1].branch = [b]
		w.perform(Game.spell_stats(w.ch.spells[1]), t.position, "player", 1.0)
		for k in 20:
			t.tick(DT)
		far[b] = t.position.distance_to(w.player.position)
	_check(far.heavy > far.plain and far.pale < far.plain, "a heavy burst throws them further; a pale one gathers them in (%d / %d / %d)" % [far.heavy, far.plain, far.pale])
	w.ch.spells[1].branch = ["stubborn"]
	w.guard_t = 0.0
	w.perform(Game.spell_stats(w.ch.spells[1]), w.player.position, "player", 1.0)
	var hp0: float = w.player.hp
	w.hurt(20.0)
	_check(w.guard_share() > 0.3 and hp0 - w.player.hp < 15.0, "a stubborn burst turns some harm aside after the cast")
	var before_n: int = w.delayed.size()
	w.perform(Game.spell_stats(w.ch.spells[1]), w.player.position, "player", 1.0)
	_check(w.delayed.size() > before_n, "and comes back a second time")
	w.queue_free()
	await get_tree().process_frame

	# -- Zones and walls
	Game.ch = _ink_char("earth", "thick", [5, 5, 5])
	w = await _side_world()
	w.ch.spells[2].branch = ["pale"]
	var cage_t = _spawn_at(w, 1, w.player.position + Vector2(140, 0))
	w.perform(Game.spell_stats(w.ch.spells[2]), cage_t.position, "player", 1.0)
	var cz: Dictionary = w.zones[-1]
	cage_t.position = cz.p + Vector2(cz.r + 40.0, 0)
	w._update_zones(DT)
	_check(cz.p.distance_to(w.player.position) > 60.0 and cage_t.position.distance_to(cz.p) < cz.r, "a pale wall rises on the enemy, and it can't get out")
	w.ch.spells[2].branch = ["stubborn"]
	w.zones.clear()
	w.perform(Game.spell_stats(w.ch.spells[2]), w.player.position, "player", 1.0)
	_check(w.guard_share() > 0.2 and float(w.zones[-1].life) > float(GameData.SPELLS.earth[2].dur), "a stubborn wall lasts longer, and inside it blows come softer")
	Game.ch.el = "fire"
	w.ch.spells[2].branch = ["pale"]
	w.zones.clear()
	w.perform(Game.spell_stats(w.ch.spells[2]), w.player.position + Vector2(150, 0), "player", 1.0)
	w.player.position += Vector2(0, 80)
	w._update_zones(DT)
	_check(w.zones[-1].p.distance_to(w.player.position) < 1.0, "a pale zone sits on you and walks with you")
	w.queue_free()
	await get_tree().process_frame

	# -- Chains and dashes
	Game.ch = _ink_char("lightning", "thin", [5])
	w = await _side_world()
	var a1 = _spawn_at(w, 1, w.player.position + Vector2(120, 0))
	var a2 = _spawn_at(w, 1, w.player.position + Vector2(200, 0))
	a1.hp = 99999.0
	a2.hp = 99999.0
	w.ch.spells[0].branch = ["stubborn"]
	var n0: int = w.delayed.size()
	w.perform(Game.spell_stats(w.ch.spells[0]), a1.position, "player", 1.0)
	_check(w.delayed.size() >= n0 + 2, "a stubborn spark bites each of them again a moment later")
	w.ch.spells[0].branch = ["pale"]
	var hp_a1: float = a1.hp
	w.chains.clear()
	w.perform(Game.spell_stats(w.ch.spells[0]), a1.position, "player", 1.0)
	_check(w.chains.any(func(c): return c.get("mark", "") == "pale" and c.b.distance_to(a1.position) < 1.0) and a1.hp < hp_a1, "a pale spark goes back to where it began")
	Game.ch.el = "wind"
	w.ch.spells[0].i = 1
	_clear(w)
	w.ch.spells[0].branch = ["pale"]
	var start: Vector2 = w.player.position
	w.perform(Game.spell_stats(w.ch.spells[0]), start + Vector2(150, 0), "player", 1.0)
	_check(w.player.position.distance_to(start) > 100.0, "a dash still goes")
	await _step(w, roundi(0.6 / DT))
	_check(w.player.position.distance_to(start) < 5.0, "and a pale one pulls you back along the line")
	w.ch.spells[0].branch = ["quick"]
	_check(float(Game.spell_stats(w.ch.spells[0]).read) < float(GameData.SPELLS.wind[1].read), "a quick dash reads faster")
	w.queue_free()
	await get_tree().process_frame

	# -- The rest screen, the book page and F1
	Game.ch = _ink_char("fire", "medium", [3, 3])
	Game.ch.spells[1].i = 2
	Game.ch.journal_ids.first_kill = true
	w = await _side_world()
	w.ch.vials = {"quick": 0, "heavy": 2, "stubborn": 1}
	w.ch.ink = 2
	w.finish_rest()
	await get_tree().create_timer(1.8).timeout
	_check(w.rest_ui.writing and w.rest_ui.pots_box.visible and w.rest_ui.pots_row.get_child_count() == 3, "at a rest the pots stand above the pages: the book's own ink, then heavy and stubborn")
	w.rest_ui.pick_pot("heavy")
	_check(_no_digits(w.rest_ui.pots_lbl.text) and w.rest_ui.pots_lbl.text.to_lower().contains(String(I.INKS.heavy.name)), "the chosen pot is named, without numbers")
	w.rest_ui.write_into(0)
	_check(w.ch.spells[0].branch == ["heavy"] and w.ch.spells[0].inks[-1] == "heavy", "writing from the heavy pot grows that page the heavy way")
	w.rest_ui.pick_pot("stubborn")
	w.rest_ui.write_into(1)
	_check(w.rest_ui.pot == "plain" and w.ch.spells[1].branch == ["stubborn"], "a vial that runs dry falls back to the book's own ink")
	w.rest_ui.close()
	await get_tree().create_timer(0.7).timeout
	w.open_book()
	await get_tree().process_frame
	var paths := 0
	var words_ok := true
	var found_written := false
	for c in w.book.left.get_children():
		if c.get_script() != null and c.has_method("_draw") and c.get("path") != null:
			paths += 1
		if c is Label:
			words_ok = words_ok and (_no_digits(c.text) or c.text.contains("'s book"))
			found_written = found_written or c.text.contains(String(I.LINES.written_head))
	_check(paths == 2 and found_written, "the open book draws each page's branch path and says what it was written in")
	_check(words_ok, "no numbers on the book page")
	w.book.close()
	_check(w.inks.designer_text().contains("Monster inks") and w.inks.designer_text().contains("path"), "F1 shows the vials, every page's path and what its next step would take")
	var keys: Array = preload("res://scripts/ui/pause_menu.gd").key_lines(w.ch)
	_check(keys.any(func(r): return r[3] == "vials"), "the key page lists choosing an ink once you carry some")

	# -- Saves
	Game.save_game()
	var back: Dictionary = Game.load_game()
	_check(back.spells[0].branch == ["heavy"] and int(back.vials.heavy) == 1 and back.spells[0].inks.size() == 3, "saving and loading keeps the vials, the inks written and the branches")
	var old := _book_char("earth", "echo")
	old.spells = [{"i": 0, "lvl": 6}, {"i": 2, "lvl": 9}]
	old.erase("vials")
	old.erase("pale_used")
	old.ui.erase("vials")
	old.hands.erase("branch")
	old.save_version = 5
	var mig: Dictionary = Game.migrate(old.duplicate(true))
	_check(int(mig.save_version) == 6 and mig.vials == {} and not mig.pale_used and mig.ui.vials == false
		and mig.spells[0].branch == ["plain"] and mig.spells[1].branch == ["plain", "plain"] and mig.spells[1].inks.size() == 8,
		"an older save gains empty vials, and every evolution it already had is a plain step")
	w.queue_free()
	await get_tree().process_frame

	Game.ch = keep
	main_w.visible = true
	main_w.hud.visible = true
	await get_tree().process_frame
