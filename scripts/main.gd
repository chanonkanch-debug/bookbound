extends Node
## Switches between the Book Rite (character creation) and the World.

const RiteScreen := preload("res://scripts/rite/rite_screen.gd")
const World := preload("res://scripts/world/world.gd")

var current: Node


func _ready() -> void:
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest()
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
	_swap(w)


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


## Smoke test: `godot --path . -- --autotest` rolls a character, plays a few
## seconds with every spell, awakens the hidden chapter, then quits.
## Add `--shots` to also save screenshots.
func _autotest() -> void:
	var shots := "--shots" in OS.get_cmdline_user_args()
	show_rite()
	await get_tree().create_timer(0.3).timeout
	current._roll()
	await get_tree().create_timer(1.2).timeout
	if shots:
		_shot("test_1_rite")
	Game.ch = Game.new_character("Tester", "orphan")
	Game.ch.thick = "thick"
	Game.ch.spells = [{"i": 0, "lvl": 5}, {"i": 1, "lvl": 5}, {"i": 2, "lvl": 5}]
	print("Autotest book: ", Game.ch.el, " / aspect ", Game.ch.aspect.id)
	show_world()
	var w = current
	for frame in 600:
		await get_tree().process_frame
		Input.action_press("move_right") if frame < 200 else Input.action_release("move_right")
		w.cast(frame % 3)
		if frame == 90 and shots:
			_shot("test_2a_fight")
		if frame == 200:
			w.dev_complete_trigger()
			w.gain_xp(300)
	if shots:
		_shot("test_2_field")
	w.ch.aspect.awakened = true
	w.open_book()
	await get_tree().create_timer(0.3).timeout
	if shots:
		_shot("test_3_book")
	w.book.close()
	for frame in 60:
		await get_tree().process_frame
	print("Autotest finished. Level ", w.ch.level, ", enemies alive ", w.enemies.size())
	Game.delete_save()
	get_tree().quit()
