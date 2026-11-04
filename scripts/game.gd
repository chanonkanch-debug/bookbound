extends Node
## Autoload "Game": holds the current character, rolls new ones, and saves/loads.
## The character is a plain Dictionary so it saves straight to JSON
## (and later can be sent over the network as-is).

const SAVE_PATH := "user://bookbound_save.json"

var ch: Dictionary = {}


func _ready() -> void:
	randomize()
	_setup_input()


## Default controls. If you add these actions in Project Settings > Input Map,
## your version wins and this is skipped.
func _setup_input() -> void:
	var map := {
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"cast_1": [KEY_1], "cast_2": [KEY_2], "cast_3": [KEY_3], "cast_4": [KEY_4],
		"open_book": [KEY_B], "designer_view": [KEY_F1],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---------------------------------------------------------------- Rolling a book

## Chance weight per element: 1 each, plus background bonus, plus how you
## fought before the ceremony (see LEAN in game_data.gd).
func element_weights(bg: String, lean: Dictionary = {}) -> Dictionary:
	var w := {"fire": 1.0, "water": 1.0, "earth": 1.0, "wind": 1.0, "lightning": 1.0}
	var bonus: Dictionary = GameData.BACKGROUNDS[bg].weights
	for k in bonus:
		w[k] += float(bonus[k])
	var lean_total := 0.0
	for k in lean:
		lean_total += float(lean[k])
	if lean_total > 0.0:
		for k in lean:
			if w.has(k):
				w[k] += float(GameData.LEAN.strength) * float(lean[k]) / lean_total
	return w


func roll_element(bg: String, lean: Dictionary = {}) -> String:
	var w := element_weights(bg, lean)
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "fire"


func roll_thickness() -> String:
	var r := randf()
	var acc := 0.0
	for k in GameData.THICKNESS:
		acc += float(GameData.THICKNESS[k].chance)
		if r <= acc:
			return k
	return "medium"


## A fresh character with bare hands and no book yet.
func new_character(char_name: String, bg: String) -> Dictionary:
	return {
		"name": char_name if char_name != "" else "Arin", "bg": bg,
		"el": "", "thick": "", "pages": 0, "spells": [],
		"ink": 0, "level": 1, "xp": 0,
		"aspect": {"id": "", "progress": 0, "stage": 0, "awakened": false, "margins": [], "need": 0, "streak": 0},
		"lean": {"fire": 0.0, "water": 0.0, "earth": 0.0, "wind": 0.0, "lightning": 0.0},
	}


func has_book(c: Dictionary = ch) -> bool:
	return String(c.get("el", "")) != ""


## The element this character has leaned toward most so far ("" if none yet).
func top_lean(c: Dictionary = ch) -> String:
	var best := ""
	var bv := 0.0
	var lean: Dictionary = c.get("lean", {})
	for k in lean:
		if float(lean[k]) > bv:
			bv = float(lean[k])
			best = k
	return best


## The Book Ceremony: rolls a book (weighted by background and leaning) into `c`.
func bind_book(c: Dictionary) -> void:
	var el := roll_element(c.bg, c.get("lean", {}))
	var thick := roll_thickness()
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
		"need": randi_range(need_range[0], need_range[1]), "streak": randi_range(8, 12),
	}
	c.el = el
	c.thick = thick
	c.pages = randi_range(t.pages[0], t.pages[1])
	c.spells = spells
	c.aspect = aspect


# ---------------------------------------------------------------- Stats

func xp_next(level: int) -> int:
	return roundi(18.0 * pow(level, 1.55))


func max_hp() -> int:
	return 80 + int(ch.level) * 14


func max_mana() -> int:
	return 50 + int(ch.level) * 6


func max_spell_level() -> int:
	return int(GameData.THICKNESS[ch.thick].max_level)


## Final numbers for bare-hands move i (before the ceremony).
func bare_stats(i: int) -> Dictionary:
	var st: Dictionary = GameData.BARE_HANDS[i].duplicate()
	st.el = "none"
	st.tier = 0
	st.dmg = float(st.dmg) * (1.0 + GameData.BARE_DMG_PER_LEVEL * (int(ch.level) - 1))
	return st


## Final numbers for one spell slot after level, evolution tier and book thickness.
func spell_stats(slot: Dictionary) -> Dictionary:
	var st: Dictionary = GameData.SPELLS[ch.el][int(slot.i)].duplicate()
	var lvl := int(slot.lvl)
	var dmg: float = float(st.dmg) * (1.0 + 0.2 * (lvl - 1))
	if ch.thick == "thin":
		dmg *= 1.3
	st.el = ch.el
	st.lvl = lvl
	st.tier = int(lvl / 4.0)
	st.dmg = dmg
	st.mana = float(st.mana) * (1.15 if ch.thick == "thick" else 1.0)
	st.cd = float(st.cd) * maxf(0.6, 1.0 - 0.03 * (lvl - 1))
	return st


func spell_name(slot: Dictionary) -> String:
	var tier := int(int(slot.lvl) / 4.0)
	var n: String = GameData.SPELLS[ch.el][int(slot.i)].name
	return n if tier == 0 else n + " " + ["", "II", "III", "IV"][tier]


# ---------------------------------------------------------------- Save / load

func save_game() -> void:
	if ch.is_empty():
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(ch, "\t"))


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not d.has("el") or not d.has("aspect"):
		return {}
	# JSON turns every number into a float; turn the counters back into ints.
	for k in ["pages", "ink", "level", "xp"]:
		d[k] = int(d[k])
	for s in d.spells:
		s.i = int(s.i)
		s.lvl = int(s.lvl)
	for k in ["progress", "stage", "need", "streak"]:
		d.aspect[k] = int(d.aspect[k])
	return d


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
