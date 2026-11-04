extends Node
## Every tunable number and text in Bookbound lives in this file.
## Change a value, press F5 in Godot, and play.

const TOWN_RADIUS := 160.0        # The Hearth: safe zone in the middle of the map
const WORLD_RADIUS := 1500.0      # Edge of the world
const INK_PER_LEVEL := 2          # Ink you get each level, spent to grow spells
const MAX_ENEMIES_NEARBY := 16

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
