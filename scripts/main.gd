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


## Smoke test: `godot --path . -- --autotest` starts a bare-handed character,
## fights with every move, attends the Book Ceremony, then plays a few seconds
## with every spell, awakens the hidden chapter, and quits.
## Add `--shots` to also save screenshots.
func _autotest() -> void:
	var shots := "--shots" in OS.get_cmdline_user_args()
	show_rite()
	await get_tree().create_timer(0.3).timeout
	if shots:
		_shot("test_0_rite")
	current.begin_new()
	await get_tree().process_frame
	var w = current
	assert(not Game.has_book(), "new characters should start without a book")
	# Bare hands: walk out, then jab, shove and sidestep at whatever is near.
	for frame in 420:
		await get_tree().process_frame
		Input.action_press("move_right") if frame < 90 else Input.action_release("move_right")
		if frame == 90:   # pull a few monsters close so every move connects
			for k in mini(4, w.enemies.size()):
				w.enemies[k].position = w.player.position + Vector2.from_angle(k * 1.6) * 40.0
		if frame > 90:
			w.cast(frame % 3)
		if frame == 300 and shots:
			_shot("test_1_bare_hands")
			w.hud.toggle_dev()
			await get_tree().process_frame
			_shot("test_1b_designer_view")
			w.hud.toggle_dev()
	print("Playstyle signals: ", Game.ch.signals)
	print("Book odds now: ", Game.element_weights(), " thickness ", Game.thickness_weights())
	w.gain_xp(400)
	assert(w.ceremony_ready(), "ceremony should be ready at Lv %d" % GameData.CEREMONY_LEVEL)
	w.player.position = Vector2(0, 50)   # walk into the Hearth
	for frame in 5:
		await get_tree().process_frame
	assert(current.has_method("open_book") and not Game.has_book(), "standing in the Hearth should open the ceremony")
	if shots:
		_shot("test_2_ceremony")
	current.open_book()
	await get_tree().create_timer(1.0).timeout
	if shots:
		_shot("test_3_book_received")
	assert(Game.has_book(), "the ceremony should give a book")
	print("Ceremony book: ", Game.ch.el, " / ", Game.ch.thick, " / aspect ", Game.ch.aspect.id)

	# With a book: make it thick and grown so every spell gets used.
	Game.ch.thick = "thick"
	Game.ch.spells = [{"i": 0, "lvl": 5}, {"i": 1, "lvl": 5}, {"i": 2, "lvl": 5}]
	show_world()
	w = current
	for frame in 600:
		await get_tree().process_frame
		Input.action_press("move_right") if frame < 200 else Input.action_release("move_right")
		w.cast(frame % 3)
		if frame == 90 and shots:
			_shot("test_4_fight")
		if frame == 200:
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
	for frame in 60:
		await get_tree().process_frame
	print("Autotest finished. Level ", w.ch.level, ", enemies alive ", w.enemies.size())
	Game.delete_save()
	get_tree().quit()
