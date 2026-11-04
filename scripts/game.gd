extends Node
## Autoload "Game": holds the current character, rolls new ones, and saves/loads.
## The character is a plain Dictionary so it saves straight to JSON
## (and later can be sent over the network as-is).

const SAVE_PATH := "user://bookbound_save.json"
const WORLD_PATH := "user://bookbound_world.json"   # The Unwritten, Phase 2: the world's own save

const SETTINGS_PATH := "user://settings.cfg"

var ch: Dictionary = {}
## The world's state, kept apart from the character so a host can own it later (co-op):
## which erasure sites are restored, how pale each one is, when each region was last visited.
## Rules: scripts/world/erasure.gd.
var world: Dictionary = {}
var settings: Dictionary = GameData.SETTINGS.duplicate()


func _ready() -> void:
	randomize()
	_setup_input()
	_load_settings()


# ---------------------------------------------------------------- Hidden settings

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in GameData.SETTINGS:
		settings[k] = cf.get_value("settings", k, GameData.SETTINGS[k])


func set_setting(k: String, v) -> void:
	settings[k] = v
	var cf := ConfigFile.new()
	for key in settings:
		cf.set_value("settings", key, settings[key])
	cf.save(SETTINGS_PATH)


## The hidden `show_numbers` setting (off by default): a small readout for testing and accessibility.
func show_numbers() -> bool:
	return bool(settings.get("show_numbers", false))


## Default controls. If you add these actions in Project Settings > Input Map,
## your version wins and this is skipped.
func _setup_input() -> void:
	var map := {
		"move_up": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)], "move_down": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)], "move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		# Gamepad aiming with the right stick (the mouse aims on a computer).
		"aim_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)], "aim_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
		"aim_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)], "aim_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
		"last_page_pad": [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
		"page_1": [_key(KEY_1)], "page_2": [_key(KEY_2)], "page_3": [_key(KEY_3)], "cast_4": [_key(KEY_4)],
		"page_5": [_key(KEY_5)], "page_6": [_key(KEY_6)],
		"page_prev": [_key(KEY_Q), _mouse(MOUSE_BUTTON_WHEEL_UP), _pad(JOY_BUTTON_LEFT_SHOULDER)],
		"page_next": [_key(KEY_E), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _pad(JOY_BUTTON_RIGHT_SHOULDER)],
		"read": [_key(KEY_SPACE), _mouse(MOUSE_BUTTON_RIGHT), _pad(JOY_BUTTON_A)],
		"rest": [_key(KEY_R), _pad(JOY_BUTTON_Y)],
		"journal": [_key(KEY_J), _pad(JOY_BUTTON_DPAD_UP)], "map": [_key(KEY_M), _pad(JOY_BUTTON_DPAD_DOWN)],
		"open_book": [_key(KEY_B), _pad(JOY_BUTTON_BACK)], "designer_view": [_key(KEY_F1)],
		"pause": [_key(KEY_ESCAPE), _pad(JOY_BUTTON_START)],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for ev in map[action]:
			InputMap.action_add_event(action, ev)


func _key(k: Key) -> InputEvent:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	return ev


func _mouse(b: MouseButton) -> InputEvent:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	return ev


func _axis(a: JoyAxis, dir: float) -> InputEvent:
	var ev := InputEventJoypadMotion.new()
	ev.axis = a
	ev.axis_value = dir
	return ev


func _pad(b: JoyButton) -> InputEvent:
	var ev := InputEventJoypadButton.new()
	ev.button_index = b
	return ev


# ---------------------------------------------------------------- Rolling a book

const ELS := ["fire", "water", "earth", "wind", "lightning"]


## A fresh character with bare hands and no book yet.
## "signals" counts playstyle signals, "use" counts fighting time per move, and
## "temper" is the hidden temperament (see LEAN in game_data.gd).
## A new character also starts a new world (every site erased, nothing found).
func new_character(char_name: String, bg: String) -> Dictionary:
	world = new_world()
	var temper := {}
	var t_range: Array = GameData.LEAN.temperament
	for k in ELS:
		temper[k] = randf_range(t_range[0], t_range[1])
	return {
		"name": char_name if char_name != "" else "Arin", "bg": bg,
		"el": "", "thick": "", "pages": 0, "spells": [],
		"ink": 0, "level": 1, "xp": 0,
		"aspect": {"id": "", "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 0, "streak": 0},
		"signals": {}, "use": {}, "temper": temper,
		"fragments": [],           # torn pages found, in the order found (save version 5)
	}.merged(_phase2_fields())


## Fields added in save version 2 (Phase 2). Also used to migrate older saves.
func _phase2_fields() -> Dictionary:
	var ui := {}
	for k in GameData.UI_PARTS:
		ui[k] = false
	return {
		"save_version": GameData.SAVE_VERSION,
		"ui": ui,                  # which parts of the interface have appeared
		"journal": [],             # journal lines, oldest first
		"journal_ids": {},         # which JOURNAL entries have fired
		"nudged": {},              # which one-time control nudges have shown
		"visited": {},             # regions walked (for the map)
		"rested": false,
		"left_hearth": false,
		"opened": {},              # controls used at least once ("book", "journal", "page"...)
		"disc": {"seen": {}, "known": {}, "terrain": {}, "secrets": {}, "margins": []},   # Phase 3 discoveries
		"hands": _hands_fields(),  # bare hands growth (lessons, learned moves, growth, secrets)
	}


func _hands_fields() -> Dictionary:
	return {"lessons": {}, "learned": [], "uses": {}, "tier": {}, "secrets": {}}


func has_book(c: Dictionary = ch) -> bool:
	return String(c.get("el", "")) != ""


## Playstyle score per element for a bare-handed character (see SIGNALS and
## LEAN in game_data.gd). Includes the hidden temperament.
func lean_scores(c: Dictionary = ch) -> Dictionary:
	var out := {}
	for k in ELS:
		out[k] = 0.0
	var sig: Dictionary = c.get("signals", {})
	for sname in sig:
		if not GameData.SIGNALS.has(sname):
			continue
		var d: Dictionary = GameData.SIGNALS[sname]
		out[d.el] += float(d.w) * pow(maxf(0.0, float(sig[sname])), float(GameData.LEAN.power))
	var temper: Dictionary = c.get("temper", {})
	for k in ELS:
		out[k] *= float(temper.get(k, 1.0))
	return out


## The element this character leans toward most so far ("" if none yet).
func top_lean(c: Dictionary = ch) -> String:
	var sc := lean_scores(c)
	var best := ""
	var bv := 0.0
	for k in sc:
		if sc[k] > bv:
			bv = sc[k]
			best = k
	return best


## True when the top two elements are close (within 15%), for the journal.
func lean_torn(c: Dictionary = ch) -> bool:
	var v: Array = lean_scores(c).values()
	v.sort()
	return v[-1] > 0.0 and v[-2] >= v[-1] * 0.85


## Chance weight per element at the ceremony: 1 each, plus background bonus,
## plus playstyle (strength * excess ^ sharpness, see LEAN in game_data.gd).
func element_weights(c: Dictionary = ch) -> Dictionary:
	var w := {}
	for k in ELS:
		w[k] = 1.0
	var bonus: Dictionary = GameData.BACKGROUNDS[c.bg].weights
	for k in bonus:
		w[k] += float(bonus[k])
	var sc := lean_scores(c)
	var total := 0.0
	for k in sc:
		total += sc[k]
	if total > 0.0:
		var even := 1.0 / ELS.size()
		for k in ELS:
			var excess := maxf(0.0, sc[k] / total - even)
			w[k] += float(GameData.LEAN.strength) * pow(excess, float(GameData.LEAN.sharpness))
	return w


## Share of fighting time spent on each bare-hands move (adds up to 1, or all 0 at the start).
func move_shares(c: Dictionary = ch) -> Dictionary:
	var use: Dictionary = c.get("use", {})
	var total := 0.0
	for k in use:
		total += float(use[k])
	var out := {}
	for m in bare_moves(c):
		out[m.move] = float(use.get(m.move, 0.0)) / total if total > 0.0 else 0.0
	return out


## 0 = an even mix of all moves, 1 = one move only, 0.5 before any fighting.
func focus(c: Dictionary = ch) -> float:
	var sh := move_shares(c)
	var n := float(sh.size())
	var top := 0.0
	for k in sh:
		top = maxf(top, sh[k])
	if top <= 0.0:
		return 0.5
	return clampf((top - 1.0 / n) / (1.0 - 1.0 / n), 0.0, 1.0)


## Chance weight per thickness at the ceremony: focus tilts thin vs thick.
func thickness_weights(c: Dictionary = ch) -> Dictionary:
	var f := focus(c)
	var k := float(GameData.FOCUS.strength)
	var w := {}
	for t in GameData.THICKNESS:
		w[t] = float(GameData.THICKNESS[t].chance)
	w.thin *= 1.0 + k * f
	w.thick *= 1.0 + k * (1.0 - f)
	return w


func _pick(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return w.keys()[0]


## The Book Ceremony: rolls a book (weighted by background and leaning) into `c`.
func bind_book(c: Dictionary) -> void:
	var el := _pick(element_weights(c))
	var thick := _pick(thickness_weights(c))
	var t: Dictionary = GameData.THICKNESS[thick]
	var spell_idx: Array = [0]
	if thick == "medium":
		spell_idx = [0, [1, 2].pick_random()]
	elif thick == "thick":
		spell_idx = [0, 1, 2]
	var spells: Array = []
	for i in spell_idx:
		spells.append({"i": i, "lvl": 1})
	var aspect_id: String = GameData.ASPECTS.keys().pick_random()
	var need_range: Array = GameData.ASPECTS[aspect_id].need
	var aspect := {
		"id": aspect_id, "progress": 0, "stage": 0, "awakened": false, "margins": [],
		"need": randi_range(need_range[0], need_range[1]),
		"streak": randi_range(GameData.CHAPTER_TUNING.hunger_act[0], GameData.CHAPTER_TUNING.hunger_act[1]),
	}
	c.el = el
	c.thick = thick
	c.pages = randi_range(t.pages[0], t.pages[1])
	c.spells = spells
	c.aspect = aspect


# ---------------------------------------------------------------- Stats

func xp_next(level: int) -> int:
	return roundi(18.0 * pow(level, 1.55))


## XP is earned quietly; levels are only written when you rest. This is the level the
## character would be after resting now (ch.level is the level already written).
func pending_level(c: Dictionary = ch) -> int:
	var lvl := int(c.level)
	var x := int(c.xp)
	while x >= xp_next(lvl):
		x -= xp_next(lvl)
		lvl += 1
	return lvl


## XP earned toward the next pending level.
func xp_into_level(c: Dictionary = ch) -> int:
	var lvl := int(c.level)
	var x := int(c.xp)
	while x >= xp_next(lvl):
		x -= xp_next(lvl)
		lvl += 1
	return x


## Writes every pending level (called when a rest finishes). Returns how many.
func write_levels(c: Dictionary = ch) -> int:
	var n := 0
	while int(c.xp) >= xp_next(int(c.level)):
		c.xp = int(c.xp) - xp_next(int(c.level))
		c.level = int(c.level) + 1
		c.ink = int(c.ink) + GameData.INK_PER_LEVEL
		n += 1
	return n


func max_hp() -> int:
	return 80 + int(ch.level) * 14


func max_mana() -> int:
	return 50 + int(ch.level) * 6


func max_spell_level() -> int:
	return int(GameData.THICKNESS[ch.thick].max_level)


## The moves your bare hands know: the basic three, then any learned from monsters.
func bare_moves(c: Dictionary = ch) -> Array:
	var out: Array = GameData.BARE_HANDS.duplicate()
	for m in c.get("hands", {}).get("learned", []):
		out.append(GameData.LEARNED_MOVES[m])
	return out


## Final numbers for bare-hands move i (before the ceremony).
func bare_stats(i: int) -> Dictionary:
	var st: Dictionary = bare_moves()[i].duplicate()
	st.el = "none"
	st.tier = 0
	var mastery: float = GameData.MASTERY_MAX * float(move_shares().get(st.move, 0.0))
	st.mastery = mastery
	st.dmg = float(st.dmg) * (1.0 + GameData.BARE_DMG_PER_LEVEL * (int(ch.level) - 1)) * (1.0 + mastery)
	return st


## Final numbers for one spell slot after level, evolution tier and book thickness.
func spell_stats(slot: Dictionary) -> Dictionary:
	var st: Dictionary = GameData.SPELLS[ch.el][int(slot.i)].duplicate()
	var lvl := int(slot.lvl)
	var dmg: float = float(st.dmg) * (1.0 + 0.2 * (lvl - 1))
	dmg *= float(GameData.THICK_BALANCE[ch.thick + "_dmg"])
	st.el = ch.el
	st.lvl = lvl
	st.tier = int(lvl / 4.0)
	st.dmg = dmg
	st.mana = float(st.mana) * (float(GameData.THICK_BALANCE.thick_mana) if ch.thick == "thick" else 1.0)
	return st


func spell_name(slot: Dictionary) -> String:
	var tier := int(int(slot.lvl) / 4.0)
	var n: String = GameData.SPELLS[ch.el][int(slot.i)].name
	return n if tier == 0 else n + " " + ["", "II", "III", "IV"][tier]


# ---------------------------------------------------------------- Save / load

func save_game() -> void:
	if ch.is_empty():
		return
	ch.save_version = GameData.SAVE_VERSION
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(ch, "\t"))
	if not world.is_empty():
		var wf := FileAccess.open(WORLD_PATH, FileAccess.WRITE)
		if wf:
			wf.store_string(JSON.stringify(world, "\t"))


## A fresh world: every erasure site erased.
func new_world() -> Dictionary:
	return migrate_world({})


## Brings a saved world up to date (or fills in an empty one). Sites added in later
## versions start erased; restored ones stay restored.
func migrate_world(d: Dictionary) -> Dictionary:
	if not d.has("sites"):
		d.sites = {}
	for s in GameData.Lore.SITES:
		if not d.sites.has(s.id):
			d.sites[s.id] = {"state": "erased", "pale": 1.0, "times": 0, "warned": false}
		var site: Dictionary = d.sites[s.id]
		site.pale = float(site.get("pale", 1.0))
		site.times = int(site.get("times", 0))
		if not site.has("warned"):
			site.warned = false
	if not d.has("seen"):
		d.seen = {}            # region index (as text) -> play time it was last visited
	d.time = float(d.get("time", 0.0))   # seconds of play in this world
	d.save_version = GameData.WORLD_SAVE_VERSION
	return d


func load_world() -> Dictionary:
	if not FileAccess.file_exists(WORLD_PATH):
		return new_world()
	var f := FileAccess.open(WORLD_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	return migrate_world(d if typeof(d) == TYPE_DICTIONARY else {})


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d := parse_save(f.get_as_text())
	if not d.is_empty():
		world = load_world()
	return d


## Turns saved text back into a character, migrating older saves. {} if it isn't one.
func parse_save(text: String) -> Dictionary:
	var d = JSON.parse_string(text)
	if typeof(d) != TYPE_DICTIONARY or not d.has("el") or not d.has("aspect"):
		return {}
	d = migrate(d)
	# JSON turns every number into a float; turn the counters back into ints.
	for k in ["pages", "ink", "level", "xp"]:
		d[k] = int(d[k])
	for s in d.spells:
		s.i = int(s.i)
		s.lvl = int(s.lvl)
	for k in ["progress", "stage", "need", "streak"]:
		d.aspect[k] = int(d.aspect[k])
	return d


## Brings an older save up to SAVE_VERSION without losing the book, levels or
## hidden-chapter progress. Version 1 is any save without a "save_version" field.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("save_version", 1))
	if v < 2:
		# Phase 2: add the new fields. Someone who already played has seen the basics,
		# so their interface starts unlocked (except the map) and the nudges are spent.
		var add := _phase2_fields()
		for k in add:
			if not d.has(k):
				d[k] = add[k]
		var played: bool = int(d.level) > 1 or int(d.xp) > 0 or has_book(d)
		d.ui.hands = played
		d.ui.journal = played
		d.ui.book = has_book(d)
		d.ui.margins = not d.aspect.get("margins", []).is_empty()
		if played:
			for n in GameData.NUDGES:
				d.nudged[n] = true
			d.rested = true
			d.left_hearth = true
		d.save_version = 2
	if v < 3:
		# Phase 3: discoveries (affinities seen, terrain, spell secrets) start empty.
		if not d.has("disc"):
			d.disc = {"seen": {}, "known": {}, "terrain": {}, "secrets": {}, "margins": []}
		d.save_version = 3
	if v < 4:
		# Bare hands growth starts empty.
		if not d.has("hands"):
			d.hands = _hands_fields()
		d.save_version = 4
	if v < 5:
		# The Unwritten, Phase 2: torn pages. An older save has found none, and its world
		# starts fresh (load_world makes one if there is no world file).
		if not d.has("fragments"):
			d.fragments = []
		d.save_version = 5
	return d


func delete_save() -> void:
	for path in [SAVE_PATH, WORLD_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
