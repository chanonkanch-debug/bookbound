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
	print("Rest (Phase 2):")
	w.auto_rest_ui = true
	w.gain_xp(1400)
	_check(int(Game.ch.level) == 1 and Game.pending_level() >= GameData.CEREMONY_LEVEL, "XP is earned, but no level is written before resting")
	for e in w.enemies:
		e.queue_free()
	w.enemies.clear()
	w.player.position = Vector2(300, 300)
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
