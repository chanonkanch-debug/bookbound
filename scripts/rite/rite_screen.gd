extends Control
## Character creation: name + background. You start with bare hands; your book
## comes later, at the Book Ceremony (see ceremony_screen.gd).

signal enter_world

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const BookCover := preload("res://scripts/ui/book_cover.gd")

var C: Dictionary = GameData.COLORS
var bg_key := "sailor"
var name_edit: LineEdit
var note: Label
var cover: BookCover
var continue_btn: Button
var saved: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.make()
	var bg := ColorRect.new()
	bg.color = C.paper
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 64)
	center.add_child(row)

	# ---- Left column: who you were
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(_label("PLAYABLE PROTOTYPE · GODOT", 12, C.gilt))
	left.add_child(_label("Bookbound", 64, C.ink))
	left.add_child(_label("Every mage is bound to a grimoire. It decides how you fight, never how strong you are. You can't trade it, and it may be keeping a secret.", 15, C.ink_soft, true))
	left.add_child(HSeparator.new())
	left.add_child(_label("Who were you?", 30, C.ink))
	left.add_child(_label("Choose your name and where you came from. Your book will find you later.", 15, C.ink))
	left.add_child(_label("NAME", 12, C.ink_soft))
	name_edit = LineEdit.new()
	name_edit.text = "Arin"
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(260, 0)
	name_edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(name_edit)
	left.add_child(_label("BACKGROUND", 12, C.ink_soft))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for k in GameData.BACKGROUNDS:
		var b := Button.new()
		b.text = GameData.BACKGROUNDS[k].name
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = k == bg_key
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_pick_bg.bind(k))
		flow.add_child(b)
	left.add_child(flow)
	note = _label(GameData.BACKGROUNDS[bg_key].note, 14, C.ink_soft, true)
	left.add_child(note)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var begin := Button.new()
	begin.text = "Begin with bare hands"
	begin.theme_type_variation = "PrimaryButton"
	begin.pressed.connect(begin_new)
	actions.add_child(begin)
	continue_btn = Button.new()
	continue_btn.visible = false
	continue_btn.pressed.connect(_continue)
	actions.add_child(continue_btn)
	left.add_child(actions)

	# ---- Right column: the book you don't have yet
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	cover = BookCover.new()
	cover.custom_minimum_size = Vector2(240, 290)
	cover.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cover.modulate.a = 0.45
	right.add_child(cover)
	right.add_child(_label("THE BOOK CEREMONY", 12, C.ink_soft))
	right.add_child(_label("Nobody is born with a book. You'll fight with your bare hands until Lv %d, then return to the Hearth, where a book chooses you." % GameData.CEREMONY_LEVEL, 15, C.ink, true))
	right.add_child(_label("Which book is up to chance, but books are said to notice how you fight.", 15, C.ink_soft, true))

	saved = Game.load_game()
	if not saved.is_empty():
		var what := "bare hands"
		if Game.has_book(saved):
			what = GameData.ELEMENTS[saved.el].name
		continue_btn.text = "Continue as %s (Lv %d, %s)" % [saved.name, saved.level, what]
		continue_btn.visible = true


func _label(text: String, size: int, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _pick_bg(k: String) -> void:
	bg_key = k
	note.text = GameData.BACKGROUNDS[k].note


func begin_new() -> void:
	Game.ch = Game.new_character(name_edit.text.strip_edges(), bg_key)
	Game.save_game()
	enter_world.emit()


func _continue() -> void:
	Game.ch = saved
	enter_world.emit()
