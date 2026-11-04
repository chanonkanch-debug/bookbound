extends Node
## Every tunable number and text in Bookbound lives in this file.
## Change a value, press F5 in Godot, and play.

const TOWN_RADIUS := 160.0        # The Hearth: safe zone in the middle of the map
const WORLD_RADIUS := 1500.0      # Edge of the world
const INK_PER_LEVEL := 2          # Ink you get each level, spent to grow spells
const MAX_ENEMIES_NEARBY := 16
const CEREMONY_LEVEL := 5         # Level at which the Book Ceremony opens (walk into the Hearth)

const COLORS := {
	"paper": Color("e7eae1"),
	"panel": Color("f2f4ee"),
	"ink": Color("1c2233"),
	"ink_soft": Color("5b6476"),
	"rule": Color("c6ccbf"),
	"gilt": Color("94701c"),
	"danger": Color("b0271f"),
	"good": Color("2d7a4c"),
	"on_el": Color("fbfaf4"),
	"none": Color("5b6476"),      # bare hands, before you have a book
	"fire": Color("c8471f"),
	"water": Color("2669b8"),
	"earth": Color("83602e"),
	"wind": Color("2a8b70"),
	"lightning": Color("a88204"),
}

# ---------------------------------------------------------------- Elements
# Each element is a verb: it changes HOW you play, not how strong you are.
const ELEMENTS := {
	"fire": {"name": "Fire", "verb": "Escalate",
		"passive": "Each cast within 2.5 s of the last adds Heat: +12% damage, up to 5 stacks."},
	"water": {"name": "Water", "verb": "Redirect",
		"passive": "Your spells push enemies back and leave them Soaked."},
	"earth": {"name": "Earth", "verb": "Persist",
		"passive": "Your zones last a long time and slow whatever stands in them."},
	"wind": {"name": "Wind", "verb": "Move",
		"passive": "You move 20% faster, and your gusts shove enemies away."},
	"lightning": {"name": "Lightning", "verb": "Chain",
		"passive": "Your sparks jump between enemies. Soaked enemies take double."},
}

# ---------------------------------------------------------------- Book thickness
# Same total power, spread differently. "chance" values should add up to 1.0.
const THICKNESS := {
	"thin": {"name": "Thin", "slots": 1, "max_level": 12, "chance": 0.30, "pages": [32, 64], "spine": 7,
		"trade": "One spell, 30% stronger, that evolves three times."},
	"medium": {"name": "Medium", "slots": 2, "max_level": 8, "chance": 0.45, "pages": [140, 220], "spine": 16,
		"trade": "Two spells, each evolving twice."},
	"thick": {"name": "Thick", "slots": 3, "max_level": 5, "chance": 0.25, "pages": [360, 520], "spine": 32,
		"trade": "Three spells. Each costs 15% more mana and evolves once."},
}

# ---------------------------------------------------------------- Spells
# kind: bolt (projectile), nova (burst around you), zone (lingers), dash, chain.
# Spells evolve every 4 levels (tier 1, 2, 3).
const SPELLS := {
	"fire": [
		{"name": "Ember Bolt", "kind": "bolt", "dmg": 14.0, "cd": 0.45, "mana": 4.0, "speed": 520.0},
		{"name": "Flare Ring", "kind": "nova", "dmg": 22.0, "cd": 3.0, "mana": 14.0, "radius": 110.0},
		{"name": "Pyre", "kind": "zone", "dmg": 7.0, "cd": 6.0, "mana": 18.0, "radius": 70.0, "dur": 4.0, "range": 200.0},
	],
	"water": [
		{"name": "Tide Shot", "kind": "bolt", "dmg": 11.0, "cd": 0.5, "mana": 4.0, "speed": 460.0, "soak": true, "push": 70.0},
		{"name": "Undertow", "kind": "nova", "dmg": 16.0, "cd": 3.2, "mana": 14.0, "radius": 120.0, "soak": true, "push": 170.0},
		{"name": "Still Pool", "kind": "zone", "dmg": 4.0, "cd": 6.0, "mana": 16.0, "radius": 85.0, "dur": 5.0, "slow": 0.5, "soak": true, "range": 180.0},
	],
	"earth": [
		{"name": "Stone Shard", "kind": "bolt", "dmg": 16.0, "cd": 0.6, "mana": 5.0, "speed": 420.0, "pierce": 2},
		{"name": "Quake", "kind": "nova", "dmg": 24.0, "cd": 3.6, "mana": 15.0, "radius": 100.0, "slow": 0.55},
		{"name": "Rampart", "kind": "zone", "dmg": 6.0, "cd": 7.0, "mana": 18.0, "radius": 80.0, "dur": 8.0, "slow": 0.35, "range": 150.0},
	],
	"wind": [
		{"name": "Gust", "kind": "bolt", "dmg": 10.0, "cd": 0.35, "mana": 3.0, "speed": 640.0, "push": 120.0},
		{"name": "Cyclone Step", "kind": "dash", "dmg": 18.0, "cd": 2.4, "mana": 10.0, "dash_len": 190.0},
		{"name": "Vortex", "kind": "zone", "dmg": 5.0, "cd": 6.5, "mana": 16.0, "radius": 110.0, "dur": 4.0, "pull": 130.0, "range": 200.0},
	],
	"lightning": [
		{"name": "Spark", "kind": "chain", "dmg": 12.0, "cd": 0.55, "mana": 5.0, "jumps": 2, "range": 280.0},
		{"name": "Arc Nova", "kind": "nova", "dmg": 20.0, "cd": 3.0, "mana": 14.0, "radius": 105.0},
		{"name": "Storm Rod", "kind": "zone", "dmg": 10.0, "cd": 7.0, "mana": 18.0, "radius": 120.0, "dur": 5.0, "tick": 0.6, "range": 180.0},
	],
}

const KIND_LABEL := {
	"bolt": "projectile", "nova": "burst", "zone": "zone", "dash": "dash", "chain": "chain",
}

# ---------------------------------------------------------------- Bare hands
# Everyone starts with no book. These are the moves you fight with until the ceremony.
# Damage grows BARE_DMG_PER_LEVEL per level. "life" is how long a bolt flies (short = melee reach).
# "move" tells the world which move made a hit, for the playstyle tracking below.
const BARE_HANDS := [
	{"name": "Jab", "move": "jab", "kind": "bolt", "label": "punch", "dmg": 9.0, "cd": 0.4, "mana": 0.0, "speed": 520.0, "life": 0.13},
	{"name": "Shove", "move": "shove", "kind": "nova", "dmg": 6.0, "cd": 2.4, "mana": 8.0, "radius": 75.0, "push": 170.0},
	{"name": "Sidestep", "move": "sidestep", "kind": "dash", "dmg": 4.0, "cd": 1.6, "mana": 6.0, "dash_len": 130.0},
]
const BARE_DMG_PER_LEVEL := 0.15

# Sticking with a style pays off. Each move gets up to MASTERY_MAX extra damage,
# shared out by how much of your fighting time went into it. Someone who only jabs
# gets the full bonus on Jab; someone who mixes all three gets a third on each.
# Same total power either way, just like thin and thick books.
const MASTERY_MAX := 0.45

# Small built-in perks so every way of fighting can level at a similar pace.
const STANCES := {
	"planted_dmg": 0.5,       # hits after standing still for planted_time deal +50%
	"moving_speed": 0.05,     # +5% move speed while an enemy is chasing you
	"brink_dmg": 0.2,         # +20% damage while below brink_hp health
	"planted_guard": 0.3,     # take 30% less damage while planted
}

# ---------------------------------------------------------------- Playstyle (how you fought before the ceremony)
# While bare-handed, the game quietly watches HOW you fight, not which button you press.
# Every move can feed any element depending on the situation. Each "signal" below
# belongs to one element. Its raw count is softened with ^LEAN.power, so repeating
# one trick gives less and less, while living a whole style (all of its signals) counts most.
#
#   fire       Escalate  chain        3rd+ hit in a row on the same enemy, each within combo_window,
#                                     while pressing in (not planted)
#                        streak_kill  a kill while on a streak of streak_kills+
#                        brink        a hit landed while below brink_hp health
#   water      Redirect  push         an enemy shoved away
#                        repel        a Shove used while an enemy is within repel_range
#                        clean_kill   a kill on an enemy that never hurt you
#   earth      Persist   planted      a hit landed after standing still for planted_time
#                        absorb       every 10 damage taken while standing your ground
#                        crowd        a hit landed with crowd_count+ enemies around you
#   wind       Move      moving_hit   a hit landed while moving
#                        slip         a Sidestep used with an enemy within dash_near
#                        kite         every kite_step pixels moved away from or around a chasing enemy
#   lightning  Chain     spread       a hit while you've struck spread_count+ different enemies in spread_window s
#                        multi        each extra enemy caught by one Shove or Sidestep
#                        snap         a Jab on a different enemy within snap_window s of your last hit,
#                                     while that last one is still standing
#
# "w" scales a signal so each one matters about equally for a committed player.
const SIGNALS := {
	"chain": {"el": "fire", "w": 1.4}, "streak_kill": {"el": "fire", "w": 1.5}, "brink": {"el": "fire", "w": 1.0},
	"push": {"el": "water", "w": 1.3}, "repel": {"el": "water", "w": 2.5}, "clean_kill": {"el": "water", "w": 1.6},
	"planted": {"el": "earth", "w": 0.8}, "absorb": {"el": "earth", "w": 1.6}, "crowd": {"el": "earth", "w": 1.0},
	"moving_hit": {"el": "wind", "w": 0.8}, "slip": {"el": "wind", "w": 2.5}, "kite": {"el": "wind", "w": 1.0},
	"spread": {"el": "lightning", "w": 0.6}, "multi": {"el": "lightning", "w": 2.0}, "snap": {"el": "lightning", "w": 3.5},
}

# How the ceremony turns your playstyle into odds. For each element:
#   score  = sum over its signals of  w * count ^ power,  times your hidden temperament
#   share  = score / all scores
#   excess = how far share is above an even split (1/5), or 0
#   weight = 1 + background bonus + strength * excess ^ sharpness
# Only elements you lean toward MORE than average get a boost, so a clear style is
# rewarded a lot and a mixed style stays close to even.
# temperament is rolled once per character in [min, max] and never shown to players,
# so two people who fight the same way can still drift apart. Set strength to 0 for pure luck.
const LEAN := {
	"strength": 120.0,
	"sharpness": 1.5,
	"power": 0.7,
	"temperament": [0.75, 1.25],
	"combo_window": 1.2,
	"planted_time": 1.5,
	"streak_kills": 5,
	"spread_window": 3.0,
	"spread_count": 3,
	"brink_hp": 0.4,
	"repel_range": 80.0,
	"crowd_radius": 130.0,
	"crowd_count": 3,
	"dash_near": 250.0,
	"chase_range": 220.0,
	"kite_step": 200.0,
	"snap_window": 0.6,
}

# Book thickness follows focus. Your fighting time on each move is compared:
# one move only (focus 1) makes thin books likelier, an even mix (focus 0) makes thick likelier.
#   thin weight  = THICKNESS.thin.chance  * (1 + strength * focus)
#   thick weight = THICKNESS.thick.chance * (1 + strength * (1 - focus))
const FOCUS := {"strength": 2.5}

# Vague journal lines, shown at level-ups before the ceremony for the element you lean
# toward most (a different line each level). Never show numbers to players.
const LEAN_HINTS := {
	"fire": ["Your fists remember the heat of a long combo.", "You don't let go once you start. Something warm approves.", "The air shimmers when you refuse to back off."],
	"water": ["The way you push them back feels like a tide.", "You keep the fight at arm's length, like a current around a stone.", "They never quite reach you. Something cool approves."],
	"earth": ["You stood your ground. The ground noticed.", "You took the hits and stayed. Something old and heavy approves.", "When they crowd you, you only grow steadier."],
	"wind": ["Your feet are quicker than your hands. Something likes that.", "You never stand still long enough to be caught.", "A breeze follows you from fight to fight."],
	"lightning": ["You jump from foe to foe like a spark looking for a path.", "They drop fast when you strike. The air crackles.", "You never hit the same thing twice if you can help it."],
}
const LEAN_TORN := "Two feelings pull at you, and neither will let go."
const LEAN_UNSURE := "Nothing in you has chosen a shape yet."

# ---------------------------------------------------------------- Backgrounds
# Weights are added to a base of 1 per element, so nothing is ever impossible.
const BACKGROUNDS := {
	"sailor": {"name": "Sailor", "note": "Raised on the tide. Water and wind books come easier.", "weights": {"water": 3, "wind": 2}},
	"smith": {"name": "Smith's child", "note": "Grew up by the forge. Fire and earth books come easier.", "weights": {"fire": 3, "earth": 2}},
	"shepherd": {"name": "Hill shepherd", "note": "Walked the high pastures. Earth and wind books come easier.", "weights": {"earth": 3, "wind": 2}},
	"lamplighter": {"name": "Lamplighter", "note": "Kept the city lamps. Lightning and fire books come easier.", "weights": {"lightning": 3, "fire": 2}},
	"orphan": {"name": "No one in particular", "note": "No past to lean on. Any book is equally likely.", "weights": {}},
}

# ---------------------------------------------------------------- Monsters
const FOES := [
	{"name": "Inkling", "hp": 22.0, "spd": 62.0, "dmg": 6.0, "r": 11.0, "xp": 4},
	{"name": "Blot", "hp": 72.0, "spd": 52.0, "dmg": 11.0, "r": 16.0, "xp": 11},
	{"name": "Smudge Knight", "hp": 210.0, "spd": 58.0, "dmg": 18.0, "r": 22.0, "xp": 28},
]

const REGIONS := [
	{"max": 160.0, "name": "The Hearth", "sub": "safe · you heal here"},
	{"max": 600.0, "name": "Inkling Fields", "sub": "Lv 1–4"},
	{"max": 1100.0, "name": "Blot Marsh", "sub": "Lv 4–8"},
	{"max": 99999.0, "name": "Knight's Reach", "sub": "Lv 8+"},
]

# ---------------------------------------------------------------- Hidden chapters
# SECRET. In the online version this table lives on the server only.
# "need" is a [min, max] range rolled per character, so guides can't give exact numbers.
const ASPECTS := {
	"stillness": {
		"name": "Stillness", "need": [10, 18],
		"effect": "Spells cast while standing still cost no mana and hit 20% harder.",
		"trigger": "Cast {need} spells while standing still.",
		"act": "Open the book while standing still with an enemy close by.",
		"hints": ["A page stirred when you stopped moving.", "The ink settles when you do.", "Be still. Then read."],
	},
	"hunger": {
		"name": "Hunger", "need": [14, 24],
		"effect": "Each kill in a streak adds 4% damage, up to 60%. Resting at the Hearth clears it.",
		"trigger": "Land {need} kills while on a streak of 5 or more.",
		"act": "Open the book while on a streak of {streak}+ kills.",
		"hints": ["The book felt heavier after that kill.", "It does not want you to rest.", "Feed it. Then read, mid-hunt."],
	},
	"lastpage": {
		"name": "Last Page", "need": [2, 3],
		"effect": "Below 30% health, a hidden spell appears: Last Page, a huge burst. Press 4.",
		"trigger": "Fall below 25% health and recover past 60%, {need} times.",
		"act": "Open the book while below 25% health.",
		"hints": ["The back cover was warm when you nearly fell.", "Something is written where the pages end.", "Read it only at the edge."],
	},
	"echo": {
		"name": "Echo", "need": [12, 22],
		"effect": "Whenever Mira casts, your book answers with a free spell of its own.",
		"trigger": "Finish off {need} enemies that Mira has just hit.",
		"act": "Open the book standing beside Mira, with enemies near.",
		"hints": ["Your pages rustled when Mira cast.", "Two voices read louder than one.", "Read beside her, in the fight."],
	},
}
const FINAL_HINT := "A blank page has appeared at the back of your book."
