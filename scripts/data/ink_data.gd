extends RefCounted
## The Unwritten, Phase 3: monster inks and branching growth.
## Split out of game_data.gd because it is a big table of branches and their words. Use it
## through GameData.Inks (game_data.gd stays the single entry point): GameData.Inks.INKS...
## Rules: scripts/world/inks.gd. Drawing: element_fx.gd (marks), rest_overlay.gd (pots),
## book_overlay.gd (branch paths), hud.gd (vials).
##
## Monsters leave a drop of their own ink when they come apart. You carry it in vials
## (no counts: a vial only looks fuller or emptier). When you rest and write a level into
## a page, you choose which pot to dip into. Each time a spell evolves (every 4 levels), it
## branches toward the monster ink used most since its last evolution. Plain ink (the
## book's own) never competes: one dose of monster ink is enough to steer a step.

# ---------------------------------------------------------------- The inks
#   from    which monster leaves it ("guardian" = any erasure-site guardian)
#   chance  chance a kill leaves a drop
#   cap     how many doses one vial holds (a full vial leaves new drops lying)
#   shape   how its drops and vial look (so they can be told apart without colour)
const INKS := {
	"quick": {"name": "quick ink", "from": "Inkling", "chance": 0.12, "cap": 5, "shape": "tall",
		"color": Color("6a4c9c"), "about": "It won't sit still in the vial."},
	"heavy": {"name": "heavy ink", "from": "Blot", "chance": 0.2, "cap": 5, "shape": "round",
		"color": Color("3b2a20"), "about": "It sinks to the bottom and stays there."},
	"stubborn": {"name": "stubborn ink", "from": "Smudge Knight", "chance": 0.3, "cap": 5, "shape": "square",
		"color": Color("4a6358"), "about": "It clings to the glass, and to anything it touches."},
	"pale": {"name": "pale ink", "from": "guardian", "chance": 1.0, "cap": 2, "shape": "cracked",
		"color": Color("b3b9c0"), "about": "Barely there. It writes the way the blank does."},
}
const INK_ORDER := ["quick", "heavy", "stubborn", "pale"]   # pots and vials, left to right

# Drops lying on the ground.
const DROP := {
	"pickup": 30.0,      # walk this close to take a drop
	"pull": 110.0,       # within this, a drop slides toward you (if its vial has room)
	"pull_speed": 160.0, # px/s
	"life": 50.0,        # seconds a drop lies before it soaks into the paper
	"scatter": 14.0,     # how far from the monster it lands
}

# ---------------------------------------------------------------- Spell branches
# One table per spell kind. Rampart (an earth zone) branches as a "wall" (its `branch_kind`
# in SPELLS). Each step multiplies or adds on top of the plain evolution (bolt shots, nova
# reach, zone size and so on, in world.gd's perform). Steps stack: Quick then Heavy is both.
#   name     the word the spell takes ("Splintered Ember Bolt II"), newest step's word shown
#   line     journal line the first time any spell takes this branch of this kind
# Multipliers (x1.0 = unchanged): read, dmg, mana, speed, radius, dur, dash_len, range,
#   tick (seconds between a zone's bites), life (how long a bolt flies), width (a dash's
#   breadth), dodge (how long a dash dodges), size (how big it is drawn), spread (how far
#   apart a volley's shots fly), push_x (the knockback the spell already had)
# Additions: count (extra shots for bolts), jumps (chain), pierce, push (knockback),
#   slow (negative = slows more), guard (share of harm turned aside for guard_time seconds
#   after casting), guard_in (share turned aside while you stand in your own zone),
#   echo (a second pulse at this share of the damage), linger (the chain bites each target
#   again at this share), raise_push (a wall throws out what stands where it rises)
const BRANCHES := {
	"bolt": {
		"quick": {"name": "Splintered", "read": 0.85, "dmg": 0.74, "count": 1, "spread": 0.8, "push_x": 0.65, "speed": 1.2, "size": 0.72,
			"line": "The quick ink broke the shot into splinters. They fly before I've finished the word."},
		"heavy": {"name": "Leaden", "read": 1.1, "dmg": 1.38, "count": -1, "speed": 0.88, "push": 90.0, "size": 1.45,
			"line": "With heavy ink the shot comes out slow and fat, and whatever it hits goes backwards."},
		"stubborn": {"name": "Unbroken", "dmg": 0.88, "pierce": 2, "life": 1.3, "size": 1.0,
			"line": "The stubborn ink won't stop at the first thing it meets. Or the second."},
	},
	"chain": {
		"quick": {"name": "Skittering", "read": 0.82, "dmg": 0.86, "jumps": 1, "mana": 0.9, "size": 0.72,
			"line": "Written quick, the spark skitters further, and lighter."},
		"heavy": {"name": "Thunderous", "read": 1.12, "dmg": 1.35, "jumps": -1, "push": 70.0, "size": 1.45,
			"line": "Heavy ink makes the spark land like a blow. Fewer of them, and they reel."},
		"stubborn": {"name": "Lingering", "dmg": 0.8, "linger": 0.45, "range": 1.15, "size": 1.0,
			"line": "The stubborn spark stays in them a moment, and bites again."},
	},
	"nova": {
		"quick": {"name": "Snapping", "read": 0.75, "radius": 0.88, "dmg": 0.88, "mana": 0.85, "push_x": 0.7, "size": 0.72,
			"line": "Quick ink snaps the burst out before I've drawn breath. It doesn't reach as far."},
		"heavy": {"name": "Crushing", "read": 1.15, "radius": 1.25, "push": 100.0, "dmg": 1.0, "size": 1.45,
			"line": "With heavy ink the burst is wide and slow, and throws them off their feet."},
		"stubborn": {"name": "Steadfast", "dmg": 0.78, "echo": 0.4, "guard": 0.4, "guard_time": 3.0, "size": 1.0,
			"line": "The stubborn burst comes back a second time, and something stands in front of me after."},
	},
	"zone": {
		"quick": {"name": "Flickering", "read": 0.8, "tick": 0.7, "dur": 0.75, "dmg": 0.9, "size": 0.72,
			"line": "Quick ink makes the ground bite faster, and give up sooner."},
		"heavy": {"name": "Swallowing", "read": 1.12, "radius": 1.25, "slow": -0.15, "dmg": 0.9, "size": 1.45,
			"line": "Heavy ink makes it wide and deep. They wade through it like mud."},
		"stubborn": {"name": "Abiding", "dur": 1.5, "dmg": 0.75, "guard_in": 0.35, "size": 1.0,
			"line": "The stubborn ink stays. While I stand in it, blows come softer."},
	},
	"wall": {
		"quick": {"name": "Hasty", "read": 0.7, "dur": 0.75, "mana": 0.85, "size": 0.72,
			"line": "Quick ink raises the wall almost as I think it, though it won't stand as long."},
		"heavy": {"name": "Shoving", "radius": 1.2, "raise_push": 200.0, "dmg": 1.05, "read": 1.1, "size": 1.45,
			"line": "With heavy ink the wall shoulders everything out of where it rises."},
		"stubborn": {"name": "Unyielding", "dur": 1.5, "dmg": 0.8, "guard_in": 0.35, "size": 1.0,
			"line": "The stubborn wall won't fall, and inside it I feel the same."},
	},
	"dash": {
		"quick": {"name": "Darting", "read": 0.8, "mana": 0.8, "dash_len": 0.9, "dmg": 0.88, "size": 0.72,
			"line": "Quick ink and I'm gone before I've meant to be."},
		"heavy": {"name": "Trampling", "read": 1.12, "width": 1.4, "push": 120.0, "dmg": 1.2, "dash_len": 0.9, "size": 1.45,
			"line": "With heavy ink I go through them like a cart, and they scatter."},
		"stubborn": {"name": "Weathering", "dodge": 2.0, "dmg": 0.9, "guard": 0.4, "guard_time": 1.5, "size": 1.0,
			"line": "Written stubborn, the step keeps the blows off me a while after."},
	},
}

# Pale ink: one odd branch per book (on whichever page takes it first). After that the book
# won't take the pale again, and guardians stop leaving it. If any pale is written into a
# step, that step goes pale, whatever else was used.
#   margin   the margin note written when it takes (the book speaks to you)
#   flags: returns (bolts fly back to you through anything in the way; `back` is their share
#   of damage on the way home), loops (the chain goes back to where it started), inward (the
#   burst pulls them in instead of pushing), follows (the zone sits on you and walks with you),
#   cages (the wall rises on the nearest enemy, and nothing inside can leave), echo_dash (you
#   are pulled back along the line, hitting again, `echo_delay` seconds later)
const PALE := {
	"bolt": {"name": "Returning", "returns": true, "back": 0.7, "dmg": 0.85,
		"margin": "The pale taught this page to come home. What you throw comes back through them."},
	"chain": {"name": "Circling", "loops": true, "dmg": 0.92,
		"margin": "Pale in the spark: it remembers where it began, and goes back there."},
	"nova": {"name": "Inward", "inward": true, "radius": 1.1,
		"margin": "The pale turned this burst inside out. It gathers them to you now."},
	"zone": {"name": "Following", "follows": true, "dur": 0.85,
		"margin": "Written in pale, the ground forgot where it was. It goes where you go."},
	"wall": {"name": "Caging", "cages": true, "dur": 0.8,
		"margin": "The pale wall rises around them, not you. Nothing written inside it gets out."},
	"dash": {"name": "Echoing", "echo_dash": 0.6, "echo_delay": 0.45,
		"margin": "The pale step goes, and then remembers it should have stayed."},
}

# ---------------------------------------------------------------- Bare hands
# Your hands can be steered too. When a move grows at a rest (HAND_GROWTH in game_data.gd)
# and you carry monster ink, you may dip your hands into a pot first. Same fields as above.
# Your hands won't hold the pale: it waits for a book.
const HAND_BRANCHES := {
	"jab": {
		"quick": {"name": "flicking", "read": 0.75, "dmg": 0.9,
			"line": "I dipped my fist in the quick ink. It comes back before I've finished throwing it."},
		"heavy": {"name": "hammering", "read": 1.2, "dmg": 1.35, "push": 90.0, "size": 1.4,
			"line": "Heavy ink in my knuckles. They land like stones now."},
		"stubborn": {"name": "driving", "dmg": 1.0, "pierce": 1, "life": 1.3,
			"line": "With stubborn ink my fist goes through the first one and finds the next."},
	},
	"shove": {
		"quick": {"name": "snapping", "read": 0.7, "radius": 0.9,
			"line": "Quick ink in my palms. The push comes out like a slap."},
		"heavy": {"name": "heaving", "read": 1.2, "radius": 1.1, "push": 110.0, "size": 1.4,
			"line": "Heavy ink in my palms. What I push stays pushed."},
		"stubborn": {"name": "bracing", "dmg": 1.0, "guard": 0.4, "guard_time": 2.0,
			"line": "With stubborn ink, after I push I stand like a door."},
	},
	"sidestep": {
		"quick": {"name": "darting", "dash_len": 0.9, "mana": 0.7,
			"line": "Quick ink on my feet. I'm somewhere else before I've decided to be."},
		"heavy": {"name": "barging", "dmg": 1.3, "push": 150.0, "width": 1.3, "size": 1.4,
			"line": "Heavy ink on my feet. I don't step round them now, I go through."},
		"stubborn": {"name": "weathering", "dodge": 1.8,
			"line": "Stubborn ink on my feet. Their blows keep missing a while after I've stopped."},
	},
}

# ---------------------------------------------------------------- Words (no numbers)
const LINES := {
	"first_drop": "It left a drop of itself behind when it came apart. I kept it.",
	"first_pale": "The knot left something pale behind. My hands won't hold it. It wants a book.",
	"vials_full": "My vial is full of it. The rest soaks into the paper.",
	"first_branch": "The page grew toward the ink I fed it. It isn't the spell it was going to be.",
	"pale_refused": "The book won't take the pale again.",
	"pots_head": "Which ink?",
	"pot_plain": "the book's own ink",
	"dip_head": "My hands are ready to change. Dip them first?",
	"dip_none": "Leave them as they are",
	"path_then": "then",          # "quick, then heavy"
	"path_plain": "plain",        # a step written in the book's own ink only
	"path_none": "not grown yet",
	"written_head": "Written in",
}
