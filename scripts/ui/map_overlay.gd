extends CanvasLayer
## A hand-drawn map (press M once you have one). Appears only after you find a
## map scrap or have walked all three regions. No numbers, just ink.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var ui_root: Control
var C: Dictionary = GameData.COLORS
var canvas: Control


class MapCanvas extends Control:
	var w
	func _draw() -> void:
		var C: Dictionary = GameData.COLORS
		var Ink := preload("res://scripts/util/ink.gd")
		var c := size / 2.0
		var sc: float = minf(size.x, size.y) * 0.42 / GameData.WORLD_RADIUS
		draw_rect(Rect2(c - Vector2(1, 1) * GameData.WORLD_RADIUS * sc * 1.12, Vector2(2, 2) * GameData.WORLD_RADIUS * sc * 1.12), C.panel)
		draw_arc(c, GameData.WORLD_RADIUS * sc, 0, TAU, 128, Color(C.ink, 0.7), 2.0)
		for r in GameData.REGIONS:
			if r.max < 99999.0 and r.max > GameData.TOWN_RADIUS:
				Ink.dashed_circle(self, c, r.max * sc, Color(C.ink_soft, 0.6), 1.0)
		draw_circle(c, GameData.TOWN_RADIUS * sc, Color(C.gilt, 0.25))
		var names := [[0.0, "The Hearth"], [380.0, GameData.REGIONS[1].name], [850.0, GameData.REGIONS[2].name], [1300.0, GameData.REGIONS[3].name]]
		for n in names:
			Ink.text_c(self, c + Vector2(0, -float(n[0]) * sc - 6.0), n[1], 13, C.ink_soft)
		for fire in GameData.CAMPFIRES:
			var fp: Vector2 = c + fire * sc
			draw_colored_polygon(Ink.blob(fp, 4.0, 1.0, 0.0), C.fire)
		var pp: Vector2 = c + w.player.position * sc
		draw_circle(pp, 5.0, C[w.ch.el] if Game.has_book() else C.none)
		draw_arc(pp, 5.0, 0, TAU, 16, C.ink, 1.5)


func _ready() -> void:
	layer = 10
	visible = false
	ui_root = Control.new()
	var root := ui_root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.08, 0.1, 0.14, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	canvas = MapCanvas.new()
	canvas.w = w
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	UiTheme.fit(self, ui_root)


func open() -> void:
	visible = true
	w.paused = true
	canvas.queue_redraw()


func close_map() -> void:
	visible = false
	w.paused = false
