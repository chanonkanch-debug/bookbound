extends Control
## The Book Ceremony. Opens when a bare-handed character reaches
## GameData.CEREMONY_LEVEL and walks into the Hearth. The book is random, but
## weighted by background and by how they fought (Game.element_weights).
## There is no reroll: the book is you.

signal enter_world

const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const BookCover := preload("res://scripts/ui/book_cover.gd")

var C: Dictionary = GameData.COLORS
var cover: BookCover
var intro: Label
var open_btn: Button
var traits: RichTextLabel
var enter_btn: Button


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

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(440, 0)
	left.add_theme_constant_override("separation", 12)
	row.add_child(left)
	left.add_child(_label("THE HEARTH", 12, C.gilt))
	left.add_child(_label("The Book Ceremony", 48, C.ink))
	intro = _label(_intro_text(), 15, C.ink, true)
	left.add_child(intro)
	open_btn = Button.new()
	open_btn.text = "Open the book"
	open_btn.theme_type_variation = "PrimaryButton"
	open_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	open_btn.pressed.connect(open_book)
	left.add_child(open_btn)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(460, 0)
	right.add_theme_constant_override("separation", 14)
	row.add_child(right)
	cover = BookCover.new()
	cover.custom_minimum_size = Vector2(240, 290)
	cover.pivot_offset = Vector2(100, 140)
	cover.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(cover)
	traits = RichTextLabel.new()
	traits.bbcode_enabled = true
	traits.fit_content = true
	traits.scroll_active = false
	traits.custom_minimum_size = Vector2(440, 0)
	traits.visible = false
	right.add_child(traits)
	enter_btn = Button.new()
	enter_btn.text = "Enter the field"
	enter_btn.theme_type_variation = "PrimaryButton"
	enter_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	enter_btn.visible = false
	enter_btn.pressed.connect(func(): enter_world.emit())
	right.add_child(enter_btn)


func _label(text: String, size: int, col: Color, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _intro_text() -> String:
	var ch: Dictionary = Game.ch
	var t := "The Hearth-keeper sets a closed book in front of %s. It is warm, and it was waiting for you." % ch.name
	var top := Game.top_lean(ch)
	if top != "":
		var lines: Array = GameData.LEAN_HINTS[top]
		t += "\n\nIt seems to know you already. " + String(lines[0])
	t += "\n\nWhatever is inside, it will be yours for life."
	return t


## Rolls the book (once) and reveals it.
func open_book() -> void:
	open_btn.disabled = true
	if not Game.has_book():
		Game.bind_book(Game.ch)
		Game.save_game()
	var tw := create_tween()
	tw.tween_property(cover, "rotation", -0.07, 0.12)
	tw.tween_property(cover, "rotation", 0.07, 0.15)
	tw.tween_property(cover, "rotation", -0.04, 0.15)
	tw.tween_property(cover, "rotation", 0.0, 0.15)
	tw.tween_callback(_reveal)


func _reveal() -> void:
	var p: Dictionary = Game.ch
	var t: Dictionary = GameData.THICKNESS[p.thick]
	var e: Dictionary = GameData.ELEMENTS[p.el]
	cover.el = p.el
	cover.spine = float(t.spine)
	cover.queue_redraw()
	var names: Array = []
	for s in p.spells:
		names.append(GameData.SPELLS[p.el][s.i].name)
	var soft: String = C.ink_soft.to_html(false)
	traits.text = "[color=#%s]BINDING[/color]\n[b]%s[/b] · %s\n[color=#%s]%s[/color]\n\n[color=#%s]THICKNESS[/color]\n[b]%s[/b], %d pages\n[color=#%s]%s[/color]\n\n[color=#%s]SPELLS[/color]\n%s" % [
		soft, e.name, e.verb, soft, e.passive,
		soft, t.name, p.pages, soft, t.trade,
		soft, ", ".join(names),
	]
	if int(p.ink) > 0:
		traits.text += "\n\n[color=#%s]You saved %d ink while bare-handed. Spend it on your spells.[/color]" % [soft, p.ink]
	traits.visible = true
	enter_btn.visible = true
	open_btn.visible = false
