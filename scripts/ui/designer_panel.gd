extends CanvasLayer
## Designer view (F1). Players never see this: it shows every hidden number,
## the hidden chapter, playstyle odds and every discovery, found or not.
## Everything here is tunable in scripts/data/game_data.gd.

const UiTheme := preload("res://scripts/ui/ui_theme.gd")

var w
var C: Dictionary = GameData.COLORS
var panel: PanelContainer
var text: RichTextLabel
var refresh_t := 0.0
var numbers_btn: Button


func _ready() -> void:
	layer = 20
	visible = false
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.make()
	add_child(root)
	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -400
	root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	scroll.add_child(v)
	var head := Label.new()
	head.text = "Designer view (F1) · spoilers"
	head.add_theme_color_override("font_color", C.danger)
	v.add_child(head)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	v.add_child(buttons)
	buttons.add_child(_button("Complete the trigger", func(): w.dev_complete_trigger()))
	buttons.add_child(_button("Gain a level (rest to write it)", func(): w.gain_xp(Game.xp_next(Game.pending_level(w.ch)) - Game.xp_into_level(w.ch))))
	buttons.add_child(_button("Rest now", func(): w.finish_rest()))
	buttons.add_child(_button("Unlock all UI", func(): w.unlock_all_ui()))
	numbers_btn = _button("", _toggle_numbers)
	buttons.add_child(numbers_btn)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.custom_minimum_size = Vector2(360, 0)
	v.add_child(text)


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _toggle_numbers() -> void:
	Game.set_setting("show_numbers", not Game.show_numbers())
	_refresh()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func tick(dt: float) -> void:
	refresh_t -= dt
	if visible and refresh_t <= 0.0:
		refresh_t = 0.3
		_refresh()


func _sec(title: String) -> String:
	return "\n[b]%s[/b]\n" % title


func _refresh() -> void:
	numbers_btn.text = "Show numbers: %s" % ("on" if Game.show_numbers() else "off")
	var ch: Dictionary = w.ch
	var p = w.player
	var soft: String = C.ink_soft.to_html(false)
	var s := ""
	s += "[color=#%s]Players see none of this. Tune it in game_data.gd.[/color]\n" % soft
	s += _sec("Character")
	s += "%s · written Lv %d · pending Lv %d · XP %d / %d this level\n" % [ch.name, ch.level, Game.pending_level(ch), Game.xp_into_level(ch), Game.xp_next(Game.pending_level(ch))]
	s += "HP %d / %d · casting ink %.1f / %d · writing ink %d\n" % [ceili(p.hp), Game.max_hp(), p.mana, Game.max_mana(), ch.ink]
	s += "streak %d · still %.1fs · save version %d\n" % [w.streak, p.still, int(ch.get("save_version", 0))]
	var cs = w.casting
	s += "page %d%s · reading %s %.2fs / %.2fs · overcharge %d%% · strain %.1fs\n" % [
		cs.page + 1, " (turning to %d)" % (cs.turn_target + 1) if cs.turning() else "",
		"yes" if cs.reading else "no", cs.t, float(cs.st.get("read", 0.0)), roundi(100.0 * cs.overcharge()), cs.strain_t]
	s += "casts %d · fizzles %d · resting %s\n" % [cs.casts, cs.fizzles, "%.1fs" % w.rest_t if w.resting else "no"]
	var ui: Dictionary = ch.get("ui", {})
	var shown: Array = []
	for k in GameData.UI_PARTS:
		shown.append("%s %s" % [k, "✓" if ui.get(k, false) else "·"])
	s += "UI unlocked: %s\n" % ", ".join(shown)
	s += _sec("Pages" if Game.has_book() else "Bare hands")
	if Game.has_book():
		var t: Dictionary = GameData.THICKNESS[ch.thick]
		s += "%s %s book · %d pages\n" % [t.name, GameData.ELEMENTS[ch.el].name, ch.pages]
		for i in ch.spells.size():
			var sl: Dictionary = ch.spells[i]
			var st: Dictionary = Game.spell_stats(sl)
			s += "%d · %s Lv %d/%d · %s · %d dmg · %d ink · read %.2fs (+%.2fs overcharge)\n" % [
				i + 1, Game.spell_name(sl), sl.lvl, Game.max_spell_level(), GameData.KIND_LABEL[st.kind], roundi(st.dmg), roundi(st.mana), float(st.read), float(st.over)]
	else:
		for i in Game.bare_moves().size():
			var st: Dictionary = Game.bare_stats(i)
			s += "%d · %s · %d dmg · %d ink · read %.2fs · honed +%d%%\n" % [i + 1, st.name, roundi(st.dmg), roundi(st.mana), float(st.read), roundi(100.0 * float(st.mastery))]
	s += _hidden_chapter() if Game.has_book() else _lean()
	if w.get("discovery") != null:
		s += w.discovery.designer_text()
	if w.get("hands") != null:
		s += w.hands.designer_text()
	s += _sec("Journal (%d lines)" % ch.get("journal", []).size())
	for l in ch.get("journal", []):
		s += "[color=#%s]· %s[/color]\n" % [soft, l]
	text.text = s


func _hidden_chapter() -> String:
	var a: Dictionary = w.ch.aspect
	var as_: Dictionary = GameData.ASPECTS[a.id]
	var soft: String = C.ink_soft.to_html(false)
	return _sec("Hidden chapter") + "[b]%s[/b]: %s\n[color=#%s]Trigger[/color]  %s\n[color=#%s]Progress[/color]  %d / %d · hint %d of 4%s\n[color=#%s]Awaken[/color]  %s\n[color=#%s]Act possible now[/color]  %s\n" % [
		as_.name, as_.effect, soft, w.chapter.trigger_text(),
		soft, a.progress, a.need, a.stage, " · awakened" if a.awakened else "",
		soft, w.chapter.act_text(), soft, "yes" if w.chapter.act_met() else "no"]


## Before the ceremony: playstyle signals and the current book odds.
func _lean() -> String:
	var ch: Dictionary = w.ch
	var soft: String = C.ink_soft.to_html(false)
	var sc := Game.lean_scores(ch)
	var ew := Game.element_weights(ch)
	var tw := Game.thickness_weights(ch)
	var etot := 0.0
	for k in ew:
		etot += ew[k]
	var ttot := 0.0
	for k in tw:
		ttot += tw[k]
	var sig: Dictionary = ch.get("signals", {})
	var temper: Dictionary = ch.get("temper", {})
	var lines: Array = []
	for k in Game.ELS:
		var parts: Array = []
		for sname in GameData.SIGNALS:
			if GameData.SIGNALS[sname].el == k:
				parts.append("%s %d" % [sname, roundi(float(sig.get(sname, 0.0)))])
		lines.append("[color=#%s]%s[/color]  score %d · temper x%.2f · [b]%d%%[/b]\n   [color=#%s]%s[/color]" % [
			C[k].to_html(false), GameData.ELEMENTS[k].name, roundi(sc[k]), float(temper.get(k, 1.0)),
			roundi(100.0 * ew[k] / etot), soft, ", ".join(parts)])
	var sh := Game.move_shares(ch)
	var mv: Array = []
	for m in sh:
		mv.append("%s %d%%" % [m, roundi(100.0 * sh[m])])
	var th: Array = []
	for t in tw:
		th.append("%s %d%%" % [t, roundi(100.0 * tw[t] / ttot)])
	return _sec("Book element (signals, score, chance now)") + "\n".join(lines) + "\n[b]Thickness[/b]  %s\n[color=#%s]Moves %s · focus %.2f · ceremony at Lv %d, on the first rest in the Hearth[/color]\n" % [
		", ".join(th), soft, ", ".join(mv), Game.focus(ch), GameData.CEREMONY_LEVEL]
