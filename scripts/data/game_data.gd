extends Node
## Every tunable number and text in Bookbound lives in this file.
## Change a value, press F5 in Godot, and play.

const TOWN_RADIUS := 160.0        # The Hearth: safe zone in the middle of the map
const WORLD_RADIUS := 1500.0      # Edge of the world
const INK_PER_LEVEL := 2          # Writing ink you get each level, spent to grow spells
# Two different "inks": casting ink (called mana in the code) is spent on every cast and
# refills over time; writing ink (ch.ink) is earned by leveling and grows your spells.
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
		"passive": "Each cast soon after the last burns hotter than the one before."},
	"water": {"name": "Water", "verb": "Redirect",
		"passive": "Your spells push them back and leave them soaked."},
	"earth": {"name": "Earth", "verb": "Persist",
		"passive": "What you raise stays a long time, and slows whatever stands in it."},
	"wind": {"name": "Wind", "verb": "Move",
		"passive": "Your feet are lighter, and your gusts shove them away."},
	"lightning": {"name": "Lightning", "verb": "Chain",
		"passive": "Your sparks jump from one to the next, and love anything wet."},
}

# ---------------------------------------------------------------- Book thickness
# Same total power, spread differently. "chance" values should add up to 1.0.
const THICKNESS := {
	"thin": {"name": "Thin", "slots": 1, "max_level": 12, "chance": 0.30, "pages": [32, 64], "spine": 7,
		"trade": "One spell that never needs a page turned, and grows deep."},
	"medium": {"name": "Medium", "slots": 2, "max_level": 8, "chance": 0.45, "pages": [140, 220], "spine": 16,
		"trade": "Two spells, a page apart."},
	"thick": {"name": "Thick", "slots": 3, "max_level": 5, "chance": 0.25, "pages": [360, 520], "spine": 32,
		"trade": "Three spells to choose from, but every page takes time to turn."},
}

# ---------------------------------------------------------------- Spells
# kind: bolt (projectile), nova (burst around you), zone (lingers), dash, chain.
# Spells evolve every 4 levels (tier 1, 2, 3).
# Phase 1: there are no cooldowns any more. A spell is gated by its read time and by ink.
#   read  = minimum seconds you must hold the cast key ("read the page") before releasing
#   over  = extra seconds of holding that charge it up to OVERCHARGE_CAP more power (0 = no overcharge)
#   mana  = casting ink it costs (paid when you start reading; half back if it fizzles)
const SPELLS := {
	"fire": [
		{"name": "Ember Bolt", "kind": "bolt", "dmg": 15.0, "read": 0.4, "over": 0.6, "mana": 6.0, "speed": 520.0},
		{"name": "Flare Ring", "kind": "nova", "dmg": 24.0, "read": 0.8, "over": 0.8, "mana": 14.0, "radius": 110.0},
		{"name": "Pyre", "kind": "zone", "dmg": 8.5, "read": 1.0, "over": 0.8, "mana": 16.0, "radius": 70.0, "dur": 4.5, "range": 230.0},
	],
	"water": [
		{"name": "Tide Shot", "kind": "bolt", "dmg": 24.0, "read": 0.45, "over": 0.6, "mana": 6.0, "speed": 460.0, "soak": true, "push": 80.0},
		{"name": "Undertow", "kind": "nova", "dmg": 40.0, "read": 0.8, "over": 0.8, "mana": 14.0, "radius": 120.0, "soak": true, "push": 190.0},
		{"name": "Still Pool", "kind": "zone", "dmg": 13.0, "read": 1.0, "over": 0.8, "mana": 15.0, "radius": 85.0, "dur": 5.0, "slow": 0.5, "soak": true, "range": 210.0},
	],
	"earth": [
		{"name": "Stone Shard", "kind": "bolt", "dmg": 26.0, "read": 0.55, "over": 0.7, "mana": 7.0, "speed": 420.0, "pierce": 2},
		{"name": "Quake", "kind": "nova", "dmg": 50.0, "read": 1.0, "over": 0.8, "mana": 15.0, "radius": 100.0, "slow": 0.55},
		{"name": "Rampart", "kind": "zone", "dmg": 14.0, "read": 1.2, "over": 0.6, "mana": 16.0, "radius": 80.0, "dur": 9.0, "slow": 0.35, "range": 180.0},
	],
	"wind": [
		{"name": "Gust", "kind": "bolt", "dmg": 23.0, "read": 0.3, "over": 0.5, "mana": 4.0, "speed": 640.0, "push": 130.0},
		{"name": "Cyclone Step", "kind": "dash", "dmg": 70.0, "read": 0.35, "over": 0.5, "mana": 10.0, "dash_len": 190.0},
		{"name": "Vortex", "kind": "zone", "dmg": 22.0, "read": 1.0, "over": 0.8, "mana": 15.0, "radius": 110.0, "dur": 4.0, "pull": 130.0, "range": 230.0},
	],
	"lightning": [
		{"name": "Spark", "kind": "chain", "dmg": 19.0, "read": 0.5, "over": 0.6, "mana": 7.0, "jumps": 2, "range": 300.0},
		{"name": "Arc Nova", "kind": "nova", "dmg": 29.0, "read": 0.8, "over": 0.8, "mana": 14.0, "radius": 105.0},
		{"name": "Storm Rod", "kind": "zone", "dmg": 14.0, "read": 1.1, "over": 0.6, "mana": 16.0, "radius": 120.0, "dur": 5.0, "tick": 0.6, "range": 210.0},
	],
}

const KIND_LABEL := {
	"bolt": "projectile", "nova": "burst", "zone": "zone", "dash": "dash", "chain": "chain",
}

# ---------------------------------------------------------------- Bare hands
# Everyone starts with no book. These are the moves you fight with until the ceremony.
# Damage grows BARE_DMG_PER_LEVEL per level. "life" is how long a bolt flies (short = melee reach).
# "read" is the hold time before the move goes off (see READ). "use_w" is how much one use counts
# toward fighting time on that move (for thin/thick odds), so a Shove counts like six Jabs.
# "move" tells the world which move made a hit, for the playstyle tracking below.
const BARE_HANDS := [
	{"name": "Jab", "move": "jab", "kind": "bolt", "label": "punch", "dmg": 24.0, "read": 0.3, "over": 0.0, "mana": 0.0, "speed": 520.0, "life": 0.13, "use_w": 0.4},
	{"name": "Shove", "move": "shove", "kind": "nova", "dmg": 22.0, "read": 0.35, "over": 0.0, "mana": 4.0, "radius": 75.0, "push": 170.0, "use_w": 2.4},
	{"name": "Sidestep", "move": "sidestep", "kind": "dash", "dmg": 14.0, "read": 0.05, "over": 0.0, "mana": 3.0, "dash_len": 130.0, "use_w": 1.6},
]
const BARE_DMG_PER_LEVEL := 0.15

# Sticking with a style pays off. Each move gets up to MASTERY_MAX extra damage,
# shared out by how much of your fighting time went into it. Someone who only jabs
# gets the full bonus on Jab; someone who mixes all three gets a third on each.
# Same total power either way, just like thin and thick books.
const MASTERY_MAX := 0.45

# Small built-in perks so every way of fighting can level at a similar pace.
const STANCES := {
	"planted_dmg": 0.8,       # hits after standing still for planted_time deal +80% (was 50%)
	"moving_speed": 0.05,     # +5% move speed while an enemy is chasing you
	"brink_dmg": 0.2,         # +20% damage while below brink_hp health
	"planted_guard": 0.5,     # take 50% less damage while planted (was 30%)
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
	"moving_hit": {"el": "wind", "w": 0.4}, "slip": {"el": "wind", "w": 2.5}, "kite": {"el": "wind", "w": 0.5},
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
	"kite_step": 300.0,
	"snap_window": 1.2,
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

# ================================================================ Phase 1: deliberate combat
# Casting is reading. Hold the cast key (Space or right mouse) to read the open page, release to cast.
const READ := {
	"move_mult": 0.5,          # reading speed while moving (0.5 = half as fast)
	"fizzle_refund": 0.5,      # share of the ink you get back when a read fizzles or breaks
	"recover": 0.2,            # short pause after any cast before the next read can start
	"overcharge_cap": 0.5,     # holding past the read time adds up to +50% power over the spell's "over" seconds
	"overcharge_dash_len": 0.3,# an overcharged dash also travels up to 30% further
	# Chance that a hit breaks your read, by book element ("none" = bare hands).
	"break_chance": {"none": 0.5, "fire": 0.45, "water": 0.35, "earth": 0.2, "wind": 0.4, "lightning": 0.5},
	"last_page_read": 0.6,     # the hidden Last Page spell reads this fast
}

# Page turning. The book is open to one page at a time; turning one page takes turn_time.
# Thin books never turn. Pages don't wrap, so page 1 to page 3 is two turns.
const PAGES := {
	"turn_time": {"thin": 0.0, "medium": 0.35, "thick": 0.4},
	"stance_switch": 0.2,      # bare hands: switching between Jab, Shove and Sidestep
}

# Aiming. Bolts, chains and dashes go toward the cursor (or where you face without a mouse).
const AIM := {
	"chain_snap": 80.0,        # a Spark jumps to the enemy closest to the cursor within this distance...
	"chain_cone": 0.35,        # ...or the first enemy within this angle (radians) of your aim line
	"line_alpha": 0.22,        # how faint the aim line / placement circle is while reading
}

# Casting ink ("mana" in the code). Scarce in the field, quick to refill when safe.
const INK_REGEN := {
	"field": 0.9,              # per second out in the field (was 6)
	"hearth": 25.0,            # per second inside the Hearth
}
const OVERCAST := {
	"hp_per_ink": 1.6,         # casting with too little ink costs this much health per missing ink
	"strain_time": 2.5,        # seconds the strain shows on you and at the screen edges
}

# Player defence while dashing: a Sidestep or Cyclone Step dodges strikes for this long.
const DODGE_TIME := 0.3

# Thickness balance (Phase 1). Thin books never turn pages, so their single spell is only
# a little stronger now. Thick books pay in page-turn time instead of extra ink.
const THICK_BALANCE := {
	"thin_dmg": 0.9,           # was 1.3
	"medium_dmg": 1.05,
	"thick_dmg": 1.3,
	"thick_mana": 1.0,         # was 1.15
}
const FIRE_HEAT_WINDOW := 4.0  # Fire: casts within this many seconds of the last add Heat (was 2.5)
const STREAK_WINDOW := 20.0    # seconds after a kill before your kill streak ends (was 8)

# Hidden chapter pacing (Phase 1). With fewer, tougher monsters and slower casting the old
# trigger counts would take far longer, so these keep each chapter at about the same play time.
# The "need" ranges themselves are in ASPECTS below.
const CHAPTER_TUNING := {
	"hunger_streak": 3,        # Hunger counts kills made while on a streak of this many or more (was 5)
	"hunger_act": [3, 4],      # ...and awakens when opened on a streak this long (rolled per book, was 8-12)
	"echo_window": 4.0,        # seconds after Mira hits an enemy that your kill still counts for Echo (was 2)
}

# ================================================================ Phase 2: minimal interface, slow progression
# The screen starts empty. Each part fades in the first time it matters (no explanation text).
const UI_PARTS := ["hands", "journal", "book", "margins", "map"]
const UI_FADE := 1.6             # seconds a newly unlocked part takes to fade in
const UNLOCK := {
	"hands_near": 150.0,         # stance marks appear when a monster first comes this close
	"near_death": 0.25,          # health share that counts as a near-death (journal unlock)
	"map_pickup": 26.0,          # how close you must walk to pick up the map scrap
}
const MAP_SCRAP := Vector2(-430.0, 250.0)   # where the torn map lies (Inkling Fields)
const WHISPER_TIME := 6.0        # seconds a new journal line or margin note stays before fading

# Resting replaces instant level-ups. XP is earned quietly; levels are only written when you rest.
# Hold R to rest anywhere, or press R once at a campfire (they're in the Hearth and every region).
# Moving, getting hit, or a hunting monster within break_range interrupts it.
const REST := {
	"time": 4.0,                 # seconds of holding R in the open
	"campfire_time": 2.5,        # seconds at a campfire (just press R once)
	"campfire_range": 60.0,
	"break_range": 260.0,        # a hunting monster this close wakes you
	"ink_rate": 30.0,            # casting ink per second while resting (fast)
	"hp_rate": 6.0,              # health per second while resting (slow)
	"campfire_hp_rate": 14.0,    # health per second at a campfire
	"moment_time": 2.2,          # how long "The book writes through the night." stays up
	"moment_text": "The book writes through the night.",
}
# Campfires: the Hearth's own fire, then one in each region.
const CAMPFIRES := [Vector2(0, 0), Vector2(390, 90), Vector2(-700, 540), Vector2(240, -1270)]

# A one-time gentle nudge: a faint key glyph near you, once ever, if you haven't found a control.
#   after = seconds of the situation before the glyph shows; glyph = what it shows
const NUDGES := {
	"move": {"after": 12.0, "glyph": "W A S D"},          # you haven't moved since starting
	"attack": {"after": 60.0, "glyph": "Space"},          # a monster has been near for this long, no attack
	"page": {"after": 90.0, "glyph": "Q  E"},             # you have more than one page/stance and never turned
	"rest": {"after": 30.0, "glyph": "R"},                # you're hurt and safe and have never rested
	"book": {"after": 120.0, "glyph": "B"},               # you have a book and have never opened it
	"journal": {"after": 45.0, "glyph": "J"},             # the journal is there and never opened
}
const NUDGE_SHOW := 6.0          # seconds a nudge glyph stays

# Every journal line, in the world's voice. Each fires once and is saved. No numbers, no game terms.
const JOURNAL := {
	"first_kill": "It came apart like wet ink. My hands are still shaking.",
	"near_death": "Too close. The world went grey at the edges.",
	"first_death": "I fell, and woke by the Hearth. Something was taken from me.",
	"hearth_return": "The Hearth is warm. Nothing follows me in here.",
	"first_rest": "I sat a while, and the ache eased.",
	"woke_stronger": "I woke stronger. The book is heavier.",
	"woke_stronger_bare": "I woke stronger. My hands remember more than I do.",
	"ceremony_near": "The Hearth-keeper watched me rest. Something is waiting for me there.",
	"ceremony_call": "Something at the Hearth is calling me home.",
	"book_received": "The book is mine now. It will not let me put it down.",
	"first_fizzle": "The words slipped before I finished them.",
	"first_overcast": "I read with an empty page. It took something from me instead.",
	"first_interrupt": "I hit it as it gathered itself, and it lost its nerve.",
	"first_dodge": "It struck where I had been.",
	"fields": "Grass and small things. They come in twos.",
	"marsh": "The ground goes soft. Something heavy moves out there.",
	"reach": "Old armour walks these hills. It never turns its back.",
	"map_found": "A torn map, half washed away. Enough to find my way.",
	"all_regions": "I have walked all of it now. I could draw it from memory.",
	"page_turn": "The pages are stiff. Turning them takes time I don't always have.",
	"first_charge": "I held the words longer, and they came out heavier.",
}

# Death screen
const DEATH_TEXT := ["The ink runs dry", "Waking at the Hearth…"]
# Journal screen
const BESTIARY_TITLE := "What I know of them"
const GIVE_UP_TEXT := "Close this book forever"
const GIVE_UP_CONFIRM := "Press again to give up this book"

# Saves. Bump SAVE_VERSION when the save format changes and add a step in Game.migrate().
const SAVE_VERSION := 4
# Hidden settings, saved in user://settings.cfg. show_numbers brings back a small readout
# (for testing and accessibility). Toggle it in the F1 designer view.
const SETTINGS := {"show_numbers": false}

# ================================================================ Phase 3: learning by experimenting
# Monster affinities. Hidden: each monster reacts to some elements in its own way.
#   weak     takes `mult` damage from that element
#   resists  takes `mult` damage from that element
#   enraged  takes `mult` damage but moves `speed` times faster for `time` seconds
#   special  something else happens (see `effect`): split, guard_break
# A reaction is only written into the journal's bestiary once the player has seen it
# DISCOVERY.affinity_seen times (from any source, including Mira).
const AFFINITIES := {
	"Inkling": {
		"fire": {"type": "weak", "mult": 1.3, "line": "The small ones burn quickly."},
		"water": {"type": "resists", "mult": 0.75, "line": "The small ones drink water and are none the worse."},
		"wind": {"type": "enraged", "mult": 1.25, "speed": 1.5, "time": 4.0, "line": "Wind only makes the small ones angrier, and easier to break."},
	},
	"Blot": {
		"fire": {"type": "weak", "mult": 1.3, "line": "The marsh things flinch from fire."},
		"earth": {"type": "resists", "mult": 0.75, "line": "Stone sinks into the marsh things and does little."},
		"water": {"type": "special", "effect": "split", "below": 0.6, "line": "Water splits the marsh things in two."},
	},
	"Smudge Knight": {
		"lightning": {"type": "weak", "mult": 1.3, "line": "Lightning runs through the knights' armour."},
		"fire": {"type": "resists", "mult": 0.75, "line": "The knights do not feel the heat."},
		"earth": {"type": "special", "effect": "guard_break", "stagger": 1.4, "line": "Stone breaks a knight's guard and turns it around."},
		"wind": {"type": "enraged", "mult": 1.25, "speed": 1.5, "time": 3.0, "line": "Wind makes the knights charge, and leaves them open."},
	},
}

const DISCOVERY := {
	"affinity_seen": 4,          # times a reaction must be seen before the journal writes it down
}

# The world reacts to elements. Ground patches, drawn in ink, laid out the same every game.
#   count = how many, r = radius range, band = distance range from the Hearth
const TERRAIN := {
	"seed": 7,
	"patches": {
		"grass": {"count": 16, "r": [45.0, 85.0], "band": [230.0, 800.0]},
		"puddle": {"count": 14, "r": [40.0, 80.0], "band": [560.0, 1200.0]},
		"stone": {"count": 12, "r": [40.0, 75.0], "band": [950.0, 1480.0]},
		"open": {"count": 10, "r": [70.0, 120.0], "band": [250.0, 1450.0]},
	},
	"grass_fire": {"dmg": 6.0, "player_dmg": 3.0, "dur": 6.0, "tick": 0.5, "regrow": 90.0},
	"puddle_grow": 1.4,          # water zones and bursts grow this much in or on a puddle; water bolts hit this much harder
	"stone_last": 2.0,           # earth zones placed on stones last this many times longer
	"open_reach": 1.5,           # wind bolts fly, wind zones reach and wind dashes go this much further from open ground
	"breeze": 14.0,              # px/s that burning ground and fire zones drift with the wind
	"wind_carry": 90.0,          # px/s a fire zone is carried when a wind spell passes through it
	"wind_carry_time": 2.0,
}
const TERRAIN_LINES := {
	"grass_fire": "Flame catches the dry grass.",
	"puddle_soak": "Anything that wades through the puddles comes out soaked.",
	"puddle_grow": "Water spells swell where water already lies.",
	"stone_last": "On the stones, the earth I raise stays longer.",
	"open_reach": "Out in the open, the wind carries my spells further.",
	"wind_carry": "The wind carries fire where it blows.",
}

# Spell secrets: one hidden extra behavior per spell, found by casting it in the right situation.
# Not hidden chapters: smaller, and written into the margins as a short line when first seen.
# The behavior itself happens every time the situation comes up. Numbers per secret are below.
const SECRETS := {
	"Ember Bolt": {"when": "hits a soaked enemy", "does": "leaves a cloud of steam that slows",
		"line": "Fire on wet ink leaves a cloud that slows them.", "radius": 60.0, "dur": 3.0, "slow": 0.5},
	"Flare Ring": {"when": "cast at full Heat", "does": "the ring keeps burning",
		"line": "At full heat, the ring keeps burning.", "dur": 3.0, "dmg": 0.25},
	"Pyre": {"when": "placed on another of your Pyres", "does": "they merge into one great fire",
		"line": "Two pyres become one great fire.", "grow": 1.5, "last": 1.5},
	"Tide Shot": {"when": "cast while you stand in a puddle", "does": "comes out as a wave of three",
		"line": "From a puddle, the tide comes as a wave.", "spread": 0.3},
	"Undertow": {"when": "throws one enemy into another", "does": "both reel",
		"line": "The tide throws them into each other.", "window": 0.6, "stagger": 1.2, "dmg": 0.4},
	"Still Pool": {"when": "placed on a puddle", "does": "holds whatever is inside almost still",
		"line": "On standing water, the pool holds them fast.", "slow": 0.1},
	"Stone Shard": {"when": "cast while you stand on stones", "does": "the shard is heavier and pierces further",
		"line": "Stones lend the shard their weight.", "pierce": 3, "dmg": 1.3},
	"Quake": {"when": "cast inside your own Rampart", "does": "echoes twice more",
		"line": "Inside the wall, the quake echoes.", "echoes": 2, "gap": 0.4},
	"Rampart": {"when": "raised on stones", "does": "becomes a wall nothing can enter",
		"line": "Raised on stone, the rampart becomes a wall."},
	"Gust": {"when": "hits an enemy standing in a puddle", "does": "sprays the water and soaks everything near",
		"line": "Wind across water soaks them all.", "radius": 130.0},
	"Cyclone Step": {"when": "passes through three or more enemies", "does": "leaves a whirlwind behind",
		"line": "Through a crowd, the step leaves a whirlwind.", "count": 3, "dur": 3.0, "radius": 70.0},
	"Vortex": {"when": "placed on open ground", "does": "walks toward the nearest enemy and lasts longer",
		"line": "On open ground, the vortex walks.", "speed": 45.0, "last": 1.5},
	"Spark": {"when": "its first target stands in a puddle", "does": "arcs to everything in that puddle",
		"line": "In water, the spark finds them all."},
	"Arc Nova": {"when": "cast while you stand in a puddle", "does": "reaches much further, and bites you too",
		"line": "Standing in water, the nova reaches far, and bites back.", "grow": 1.8, "self_dmg": 0.15},
	"Storm Rod": {"when": "strikes a soaked enemy", "does": "forks to every soaked enemy nearby",
		"line": "The rod finds every wet thing nearby.", "range": 260.0, "dmg": 0.6},
}

# Mira teaches by example: she prefers targets that show the player a reaction or secret they
# haven't found yet. Each weight is added to her score for a target (distance counts against it).
const MIRA_TEACH := {
	"untaught_affinity": 160.0,  # an enemy whose reaction to Mira's element the player hasn't learned
	"soak_for_player": 120.0,    # soaking an enemy near the player when a "soaked" secret is undiscovered
	"in_puddle": 100.0,          # an enemy in a puddle when a puddle secret is undiscovered
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
# Phase 1: fewer, heavier monsters. Every attack has a visible wind-up you can read and dodge.
#   windup   seconds the monster swells/leans before it strikes (dodge or interrupt it)
#   reach    how far the strike lands, measured from its edge to yours
#   recover  seconds it needs after striking before it can wind up again
#   behavior pair   = Inklings come in twos and try to flank you from both sides
#            charge = Blots wind up, rush in a straight line, then rest (open to punishment)
#            guard  = Smudge Knights turn slowly and only strike in an arc in front of them
const FOES := [
	{"name": "Inkling", "hp": 220.0, "spd": 72.0, "dmg": 14.0, "r": 11.0, "xp": 14, "behavior": "pair",
		"windup": 0.5, "reach": 18.0, "recover": 1.3},
	{"name": "Blot", "hp": 1000.0, "spd": 50.0, "dmg": 40.0, "r": 16.0, "xp": 30, "behavior": "charge",
		"windup": 0.8, "reach": 4.0, "recover": 1.8, "charge_speed": 340.0, "charge_time": 0.55, "charge_from": 190.0},
	{"name": "Smudge Knight", "hp": 3000.0, "spd": 44.0, "dmg": 60.0, "r": 22.0, "xp": 75, "behavior": "guard",
		"windup": 1.0, "reach": 48.0, "recover": 1.2, "arc": 2.1, "turn": 1.5},
]

# How monsters spawn and get interrupted.
const MONSTERS := {
	"max_nearby": 5,           # monsters within 900 px of you (was 16)
	"initial": 4,              # monsters placed when the field opens
	"spawn_every": 3.0,        # seconds between spawn checks
	"interrupt_frac": 0.12,    # a hit for this share of its max health (or any push) breaks a wind-up
	"stagger": 0.6,            # seconds a monster reels after being interrupted
	"pair_offset": 30.0,       # how far apart a pair of Inklings tries to stand when flanking
}

const REGIONS := [
	{"max": 160.0, "name": "The Hearth", "sub": ""},
	{"max": 600.0, "name": "Inkling Fields", "sub": ""},
	{"max": 1100.0, "name": "Blot Marsh", "sub": ""},
	{"max": 99999.0, "name": "Knight's Reach", "sub": ""},
]

# ---------------------------------------------------------------- Hidden chapters
# SECRET. In the online version this table lives on the server only.
# "need" is a [min, max] range rolled per character, so guides can't give exact numbers.
const ASPECTS := {
	"stillness": {
		"name": "Stillness", "need": [10, 18],
		"effect": "Spells cast while standing still cost no mana and hit 20% harder.",
		"told": "When you stand still, the book asks nothing and strikes harder.",
		"trigger": "Cast {need} spells while standing still.",
		"act": "Open the book while standing still with an enemy close by.",
		"hints": ["A page stirred when you stopped moving.", "The ink settles when you do.", "Be still. Then read."],
	},
	"hunger": {
		"name": "Hunger", "need": [3, 5],
		"effect": "Each kill in a streak adds 4% damage, up to 60%. Resting at the Hearth clears it.",
		"told": "Every kill feeds the next. The Hearth makes it go hungry again.",
		"trigger": "Land {need} kills while on a streak of 3 or more.",
		"act": "Open the book while on a streak of {streak}+ kills.",
		"hints": ["The book felt heavier after that kill.", "It does not want you to rest.", "Feed it. Then read, mid-hunt."],
	},
	"lastpage": {
		"name": "Last Page", "need": [1, 2],
		"effect": "Below 30% health, a hidden spell appears: Last Page, a huge burst. Hold 4.",
		"told": "At the edge of falling, the last page can be read. Hold 4.",
		"trigger": "Fall below 25% health and recover past 60%, {need} times.",
		"act": "Open the book while below 25% health.",
		"hints": ["The back cover was warm when you nearly fell.", "Something is written where the pages end.", "Read it only at the edge."],
	},
	"echo": {
		"name": "Echo", "need": [4, 7],
		"effect": "Whenever Mira casts, your book answers with a free spell of its own.",
		"told": "When Mira casts, your book answers her.",
		"trigger": "Finish off {need} enemies that Mira has just hit.",
		"act": "Open the book standing beside Mira, with enemies near.",
		"hints": ["Your pages rustled when Mira cast.", "Two voices read louder than one.", "Read beside her, in the fight."],
	},
}
const FINAL_HINT := "A blank page has appeared at the back of your book."


# ================================================================ Bare hands: learning by fighting
# Before the book, your hands grow in four ways. Rules in world/hands.gd.

# 1. Learn moves from monsters. Every time you dodge a monster's strike (Sidestep through it)
#    or interrupt its wind-up, you've "watched" it once. After `need` lessons from one kind of
#    monster, your next rest writes its move into your hands, and it becomes a new stance
#    (keys 4 to 6, or Q/E). `line` is the journal line when learned.
const HAND_LESSONS := {
	"Inkling": {"move": "flank", "need": 4,
		"line": "I watched the small ones circle. My feet know the way round now."},
	"Blot": {"move": "rush", "need": 3,
		"line": "The marsh things gather themselves, then go. I can do that too."},
	"Smudge Knight": {"move": "brace", "need": 2,
		"line": "The knights turn their shoulder to a blow. I tried it, and it held."},
}
# The learned moves. Same fields as BARE_HANDS. Special fields:
#   flank  circles to the far side of the nearest enemy near the aim, hitting it from behind
#          (behind_mult) and always interrupting it
#   rush   a long read, then a straight charge that knocks everything aside (push)
#   brace  no damage: for brace_time seconds, blows from the front (brace_arc, radians) are
#          mostly turned aside (brace_guard) and the attacker reels (brace_stagger)
const LEARNED_MOVES := {
	"flank": {"name": "Flank Step", "move": "flank", "kind": "dash", "dmg": 20.0, "read": 0.2, "over": 0.0, "mana": 5.0,
		"dash_len": 120.0, "reach": 170.0, "behind_mult": 1.6, "use_w": 1.6},
	"rush": {"name": "Bull Rush", "move": "rush", "kind": "dash", "dmg": 46.0, "read": 0.9, "over": 0.5, "mana": 8.0,
		"dash_len": 230.0, "push": 260.0, "use_w": 3.0},
	"brace": {"name": "Brace", "move": "brace", "kind": "brace", "dmg": 0.0, "read": 0.25, "over": 0.0, "mana": 4.0,
		"brace_time": 2.5, "brace_arc": 2.2, "brace_guard": 0.85, "brace_stagger": 1.2, "use_w": 1.0},
}

# 2. Moves that visibly grow. Only meaningful use counts:
#    jab       a Jab that lands on a monster that's hunting you
#    shove     a Shove that catches at least one monster
#    sidestep  a Sidestep that slips through a strike or a monster
# At each count in `at`, your next rest grows the move one step (two steps in all):
#    Jab       1: every Jab lands twice (second_hit of the damage)   2: every third Jab on the same monster knocks it back and staggers it
#    Shove     1: what it catches reels (stagger seconds)            2: wider (radius_mult) and harder (push_mult)
#    Sidestep  1: leaves an ink decoy monsters chase (decoy_time)    2: slipping through a winding-up monster breaks its wind-up
const HAND_GROWTH := {
	"jab": {"at": [30, 90], "second_hit": 0.45, "third_knock": 220.0, "third_stagger": 0.8,
		"lines": ["My fist comes back before I've thought about it. Twice, now.", "The third blow lands like a door slamming."]},
	"shove": {"at": [12, 36], "stagger": 0.7, "radius_mult": 1.35, "push_mult": 1.4,
		"lines": ["They stagger when I push them, as if they'd forgotten where they were.", "My push carries further. The grass bends with it."]},
	"sidestep": {"at": [8, 24], "decoy_time": 1.6, "decoy_r": 10.0,
		"lines": ["When I step aside, a smear of me stays behind. They bite at it.", "I step through them as they gather, and they lose the thread."]},
}

# 3. Hand secrets: small combos, written into the journal the first time they happen.
#    backhand  a Jab within `window` s after a Sidestep: always interrupts, mult damage
#    counter   a Jab that lands in the last `late` s of a monster's wind-up: long stagger
#    tangle    a Shove that throws one monster into another: both reel (uses the Undertow crash rule)
#    untouched three Jabs on one monster without being hurt in between: the third splashes ink
#              around it (splash_r, splash of the damage)
const HAND_SECRETS := {
	"backhand": {"window": 0.7, "mult": 1.5, "line": "Step aside, then strike back: they never see it coming."},
	"counter": {"late": 0.25, "stagger": 1.6, "line": "I struck just as it moved, and it forgot what it meant to do."},
	"tangle": {"window": 0.6, "dmg": 18.0, "stagger": 1.0, "line": "Pushed into each other, they tangle like wet string."},
	"untouched": {"count": 3, "splash_r": 70.0, "splash": 0.5, "line": "Three clean blows, and the third one splashed. Like ink from a pen."},
}

# 4. Your hands take on the colour of the element your fighting leans toward.
#    It starts once that element's share is above an even split by `start`, and is full at `full`.
const HAND_TINT := {"start": 0.04, "full": 0.25, "max_alpha": 0.85}
