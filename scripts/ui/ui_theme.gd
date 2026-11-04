extends RefCounted
## Builds the shared UI look (buttons, panels, text colours) in code.
## Later you can replace this with a Theme resource made in the editor.


static func box(bg: Color, border: Color, bw: int = 1, radius: int = 3, padx: float = 12.0, pady: float = 7.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = padx
	s.content_margin_right = padx
	s.content_margin_top = pady
	s.content_margin_bottom = pady
	return s


static func make() -> Theme:
	var C: Dictionary = GameData.COLORS
	var clear := Color(0, 0, 0, 0)
	var t := Theme.new()
	t.default_font_size = 16

	t.set_color("font_color", "Label", C.ink)
	t.set_color("default_color", "RichTextLabel", C.ink)

	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "Button", C.ink)
	t.set_color("font_disabled_color", "Button", Color(C.ink_soft, 0.6))
	t.set_stylebox("normal", "Button", box(clear, C.ink))
	t.set_stylebox("hover", "Button", box(Color(C.ink, 0.08), C.ink))
	t.set_stylebox("pressed", "Button", box(C.panel, C.gilt, 2))
	t.set_stylebox("hover_pressed", "Button", box(C.panel, C.gilt, 2))
	t.set_stylebox("disabled", "Button", box(clear, C.rule))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())

	t.set_type_variation("PrimaryButton", "Button")
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(k, "PrimaryButton", C.paper)
	t.set_stylebox("normal", "PrimaryButton", box(C.ink, C.ink, 1, 3, 18, 9))
	t.set_stylebox("hover", "PrimaryButton", box(C.ink.lerp(C.gilt, 0.25), C.ink, 1, 3, 18, 9))
	t.set_stylebox("pressed", "PrimaryButton", box(C.ink.lerp(C.gilt, 0.4), C.ink, 1, 3, 18, 9))

	t.set_stylebox("normal", "LineEdit", box(C.panel, C.rule))
	var focus := box(clear, C.gilt, 2)
	focus.draw_center = false
	t.set_stylebox("focus", "LineEdit", focus)
	t.set_color("font_color", "LineEdit", C.ink)
	t.set_color("caret_color", "LineEdit", C.ink)
	t.set_color("selection_color", "LineEdit", Color(C.gilt, 0.3))

	t.set_stylebox("panel", "PanelContainer", box(C.panel, C.rule, 1, 4, 16, 16))
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	return t
