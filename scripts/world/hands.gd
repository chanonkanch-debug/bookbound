extends RefCounted
## Bare hands that grow by fighting (before the book). Rules only, no drawing.
##   lessons   dodge or interrupt a monster's attack and you've watched it once; enough
##             lessons and your next rest teaches you its move (HAND_LESSONS, LEARNED_MOVES)
##   growth    meaningful uses of Jab, Shove and Sidestep; at each threshold your next
##             rest grows the move one step (HAND_GROWTH)
##   secrets   small combos, written into the journal the first time (HAND_SECRETS)
##   tint      your fist takes on the colour of the element you lean toward (HAND_TINT)
## Saved in ch.hands. Numbers in the "Bare hands" block of game_data.gd.

var w


func _init(world) -> void:
	w = world
	ensure(w.ch)


static func ensure(ch: Dictionary) -> void:
	if not ch.has("hands"):
		ch.hands = {}
	for k in ["lessons", "uses", "tier", "secrets"]:
		if not ch.hands.has(k):
			ch.hands[k] = {}
	if not ch.hands.has("learned"):
		ch.hands.learned = []


func h() -> Dictionary:
	return w.ch.hands


func active() -> bool:
	return not Game.has_book()


# ---------------------------------------------------------------- Learned moves

## You dodged or interrupted monster `e`: one lesson from its kind.
func lesson(e) -> void:
	if not active() or not GameData.HAND_LESSONS.has(e.foe_name):
		return
	var L: Dictionary = GameData.HAND_LESSONS[e.foe_name]
	if L.move in h().learned:
		return
	h().lessons[e.foe_name] = int(h().lessons.get(e.foe_name, 0)) + 1


func knows(move: String) -> bool:
	return move in h().learned


## Lessons from this kind of monster, 0..1 of what's needed.
func lesson_progress(foe: String) -> float:
	var L: Dictionary = GameData.HAND_LESSONS[foe]
	return clampf(float(h().lessons.get(foe, 0)) / float(L.need), 0.0, 1.0)


# ---------------------------------------------------------------- Growth

## A meaningful use of a basic move.
func use(move: String) -> void:
	if not active() or not GameData.HAND_GROWTH.has(move):
		return
	h().uses[move] = int(h().uses.get(move, 0)) + 1


func tier(move: String) -> int:
	return int(h().tier.get(move, 0))


# ---------------------------------------------------------------- Rest

## Called when a rest finishes. Learns moves and grows old ones. Returns
## [[journal id, line], ...] for what happened, in order.
func on_rest() -> Array:
	var out: Array = []
	if not active():
		return out
	for foe in GameData.HAND_LESSONS:
		var L: Dictionary = GameData.HAND_LESSONS[foe]
		if not knows(L.move) and int(h().lessons.get(foe, 0)) >= int(L.need):
			h().learned.append(L.move)
			out.append(["learned_" + String(L.move), String(L.line)])
	for move in GameData.HAND_GROWTH:
		var G: Dictionary = GameData.HAND_GROWTH[move]
		var t := tier(move)
		while t < G.at.size() and int(h().uses.get(move, 0)) >= int(G.at[t]):
			out.append(["grew_%s_%d" % [move, t + 1], String(G.lines[t])])
			t += 1
		h().tier[move] = t
	return out


# ---------------------------------------------------------------- Secrets

func found(id: String) -> bool:
	return h().secrets.has(id)


func secret(id: String) -> void:
	if found(id) or not GameData.HAND_SECRETS.has(id):
		return
	h().secrets[id] = true
	w.unlock("journal")
	w.journal("hand_" + id, String(GameData.HAND_SECRETS[id].line))


# ---------------------------------------------------------------- Tint

## The colour your fist is tinting toward (alpha = how far), from your leaning so far.
func tint() -> Color:
	if not active():
		return Color(0, 0, 0, 0)
	var sc: Dictionary = Game.lean_scores(w.ch)
	var total := 0.0
	var best := ""
	for k in sc:
		total += float(sc[k])
		if best == "" or float(sc[k]) > float(sc[best]):
			best = k
	if total <= 0.0 or best == "":
		return Color(0, 0, 0, 0)
	var T: Dictionary = GameData.HAND_TINT
	var excess: float = float(sc[best]) / total - 1.0 / float(sc.size())
	var k := clampf((excess - float(T.start)) / (float(T.full) - float(T.start)), 0.0, 1.0)
	var c: Color = GameData.COLORS[best]
	c.a = k * float(T.max_alpha)
	return c


# ---------------------------------------------------------------- Designer view

func designer_text() -> String:
	var t := "\n[b]Bare hands growth[/b]\n"
	t += "[i]Lessons[/i] (dodge or interrupt a monster's attack; learned at the next rest)\n"
	for foe in GameData.HAND_LESSONS:
		var L: Dictionary = GameData.HAND_LESSONS[foe]
		var name: String = GameData.LEARNED_MOVES[L.move].name
		t += "%s %s from %s · %d/%d\n" % ["✓" if knows(L.move) else "·", name, foe, int(h().lessons.get(foe, 0)), int(L.need)]
	t += "[i]Growth[/i] (meaningful uses; grows at the next rest)\n"
	for move in GameData.HAND_GROWTH:
		var G: Dictionary = GameData.HAND_GROWTH[move]
		t += "%s · step %d/%d · %d uses (next at %s)\n" % [move, tier(move), G.at.size(), int(h().uses.get(move, 0)),
			str(G.at[tier(move)]) if tier(move) < G.at.size() else "-"]
	t += "[i]Hand secrets[/i]\n"
	for id in GameData.HAND_SECRETS:
		t += "%s %s\n" % ["✓" if found(id) else "·", id]
	var c := tint()
	t += "Hand tint: %d%%\n" % roundi(100.0 * c.a / float(GameData.HAND_TINT.max_alpha)) if c.a > 0.0 else "Hand tint: none yet\n"
	return t
