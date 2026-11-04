extends RefCounted
## The Unwritten, Phase 2: erasure sites, restoring, re-erasure and the torn pages.
## Split out of game_data.gd because it is mostly text. Use it through GameData.Lore
## (game_data.gd stays the single entry point): GameData.Lore.SITES, GameData.Lore.FRAGMENTS...
## The story behind all of this is in docs/LORE.md. Rules: scripts/world/erasure.gd.

# ---------------------------------------------------------------- Erasure sites
# Pale, blank patches where the paper is bare. `region` is 1 Fields, 2 Marsh, 3 Reach.
# `detail` is what comes back when it is written back (drawn by scripts/util/site_fx.gd).
# `line` is the journal line the first time it is restored.
const SITES := [
	{"id": "bare_stile", "name": "the Bare Stile", "region": 1, "p": Vector2(-300, -380), "r": 90.0, "detail": "fence",
		"line": "The fence came back, post by post, as if it had only been resting."},
	{"id": "quiet_patch", "name": "the Quiet Patch", "region": 1, "p": Vector2(430, 330), "r": 90.0, "detail": "grass",
		"line": "Grass grew back where there was none. I could hear it."},
	{"id": "dry_pool", "name": "the Dry Pool", "region": 2, "p": Vector2(-850, -300), "r": 100.0, "detail": "pool",
		"line": "Water came up through the paper and remembered where it had been."},
	{"id": "sunk_path", "name": "the Sunk Path", "region": 2, "p": Vector2(700, -600), "r": 100.0, "detail": "stones",
		"line": "The stepping stones were there all along. Someone just had to write them."},
	{"id": "reed_gap", "name": "the Reed Gap", "region": 2, "p": Vector2(100, 900), "r": 100.0, "detail": "reeds",
		"line": "The reeds filled in, and something small started singing in them."},
	{"id": "fallen_post", "name": "the Fallen Post", "region": 3, "p": Vector2(-1100, 700), "r": 110.0, "detail": "banner",
		"line": "A banner, still red. The Knights would have wanted it back."},
	{"id": "white_field", "name": "the White Field", "region": 3, "p": Vector2(1250, 200), "r": 110.0, "detail": "hill",
		"line": "The hill came back under my feet, all at once, like a held breath."},
	{"id": "last_line", "name": "the Last Line", "region": 3, "p": Vector2(-300, -1300), "r": 110.0, "detail": "line",
		"line": "There is a line cut in the stone here. Nobody crossed it while I stood on it."},
]

# What being near an unrestored site does. Strength is 1 inside the site and falls to 0 at
# `aura` times its radius.
const ERASURE := {
	"aura": 2.0,               # effects reach this many radii from the centre
	"read_speed": 0.85,        # reading goes this fast at full strength (1.0 = normal)
	"ink_regen": 0.5,          # casting ink comes back this fast at full strength
	"terrain_fade": 1.4,       # ground patches within this many radii don't react (grass won't burn...)
	"gather_range": 800.0,     # an unrestored site this close to you draws new monsters to it
	"gather_chance": 0.45,     # chance a new monster appears at that site instead of around you
	"calm_radius": 3.0,        # around a restored site (in radii) fewer monsters appear
	"calm_skip": 0.7,          # chance a monster that would appear there doesn't
	"restore_reach": 0.6,      # rest within this many radii of the centre to write it back
	"pulse": 0.9,              # how fast an unrestored site breathes (visual)
}

# Guardians: the tougher knot of smudges that waits at each unrestored site. Built from the
# region's monster (`tier`), made bigger and tougher. `escorts` ordinary monsters come too.
# Guardians are made of the pale, so no element affects them more than another (no affinities),
# which keeps every book's fight with them within reach of the others.
const GUARDIANS := {
	1: {"name": "the Scrawl", "tier": 0, "hp": 10.0, "dmg": 1.5, "size": 1.8, "spd": 1.1, "xp": 2.0, "escorts": 3},
	2: {"name": "the Spill", "tier": 1, "hp": 2.5, "dmg": 1.2, "size": 1.5, "spd": 0.9, "xp": 2.0, "escorts": 2},
	3: {"name": "the Hollow", "tier": 2, "hp": 1.5, "dmg": 1.15, "size": 1.35, "spd": 1.0, "xp": 1.5, "escorts": 1},
}
# How hard each book's spells land on a guardian. Tuned with `--balance --only=sites` so every
# element beats a guardian in about the same time: chain and burst books lose a lot against a
# single tough target, so they get a little back here. Invisible to the player.
const GUARDIAN_INK := {"fire": 1.0, "water": 1.0, "earth": 1.0, "wind": 1.0, "lightning": 1.5, "none": 1.0}
const GUARDIAN_WAKE := 170.0   # the guardian and its escorts appear when you come this close to the edge
const GUARDIAN_LEASH := 3.0    # a guardian won't chase you further than this many site radii from its centre

# The restoring moment (drawing only, scripts/util/site_fx.gd).
const RESTORE_FX := {
	"time": 4.5,               # seconds the ink takes to spread back over the site
	"sparks": 26,              # gilt sparks rising
	"wash": 0.16,              # how strong the colour wash is once restored
}

# Slow re-erasure. A restored site starts to fade once its region has gone unvisited for
# `grace` seconds of play, and is fully erased again `fade_time` seconds later. Visiting the
# region stops the fading; resting at the site writes it back in full. Off with `enabled`
# here, or with the "The pale returns" setting in the pause menu.
const REERASE := {
	"enabled": true,
	"grace": 1200.0,           # 20 minutes away before anything fades
	"fade_time": 1800.0,       # then 30 more minutes to fade completely
	"warn_at": 0.25,           # the first time a site has faded this much, the journal notices
}

# Something in the Hearth changes for each restored site: a window lights up (more in Phase 5).
# One window per site, in SITES order, placed around the Hearth.
const HEARTH_WINDOWS := [
	Vector2(-92, -58), Vector2(96, -50), Vector2(-110, 30), Vector2(112, 38),
	Vector2(-60, 96), Vector2(64, 100), Vector2(-136, -16), Vector2(138, -8),
]

# ---------------------------------------------------------------- Torn pages (fragments)
# Twelve pages from the great book, in other people's hands. Readable in any order; shown
# at the back of the book (or with the journal, before the book) in the order found.
#   where  "grass"  hidden in tall grass, seen only when close
#          "stone"  tucked behind a stone, a corner showing when close
#          "site"   appears at an erasure site once it has been written back
#          "stacks" waits in the Stacks (Phase 7): not placed in the world yet
# Text: "\n" starts a new line, " — —" is where the page is torn.
const FRAGMENTS := [
	{"id": "hymn", "title": "A hymn", "where": "grass", "p": Vector2(250, -330),
		"text": "In the beginning was the page, and the page was full,\nand nothing was blank, and no one was alone,\nfor every word leaned on the word before — —"},
	{"id": "rhyme", "title": "A rhyme", "where": "stone", "p": Vector2(-480, -60),
		"text": "Fold your page and keep it small,\nthe white won't find you, not at all.\nFold it once and fold it twice,\nhold it — —"},
	{"id": "ledger", "title": "The Hearth's ledger", "where": "site", "site": "bare_stile",
		"text": "Tamsin, cooper. Old Bede. The twins from the far mill.\n(Three names crossed out with a pale line, not ink.)\nIlse went out to the edge to look. Did not come back.\nHer page was found. It was blank."},
	{"id": "oath", "title": "An oath", "where": "stone", "p": Vector2(900, 1000),
		"text": "We stand at the last line of the margin.\nWe do not turn our backs to the white.\nIf it takes us, it takes us facing it."},
	{"id": "small_things", "title": "On small things", "where": "grass", "p": Vector2(-600, -650),
		"text": "When a word is rubbed out, the letters are left. They don't know what they were.\nThey go about in pairs, as if two of them might yet spell something.\nBe kind to them. — —"},
	{"id": "spilled_ink", "title": "On spilled ink", "where": "site", "site": "dry_pool",
		"text": "Someone spilled the marsh on purpose, to cover a line they didn't want read.\nThe ink is heavy because of what it hides.\nI have not lifted it. I am afraid of what — —"},
	{"id": "binder", "title": "What the Binder said", "where": "stone", "p": Vector2(850, 250),
		"text": "She said a page can't be unbound from the book, only torn.\nAnd what is torn remembers where it was.\nThat's why we write ourselves down at the fire. So we remember back."},
	{"id": "margin", "title": "In the margin", "where": "site", "site": "fallen_post",
		"text": "Some passages wake only when they are lived.\nWe left them in the margins for whoever came after,\nsince we would not be there to — —"},
	{"id": "letter", "title": "A letter, unsigned", "where": "site", "site": "last_line",
		"text": "I only meant to make it right. You'd have done the same, if you had seen it there on the first page.\nOne word. I took it out.\nBut everything leaned on it. — — I can't stop. Every line I take leaves another one wrong."},
	{"id": "complaint", "title": "A copyist's complaint", "where": "stacks", "floor": 1,
		"text": "Every copy carries the mistakes of the last. Nobody reads the first page any more.\nI did. There is a word on it that shouldn't be there.\nThey tell me to leave it. — —"},
	{"id": "almost_blank", "title": "A page, almost blank", "where": "stacks", "floor": 2,
		"text": "(A whole page of pale paper. One sentence survives near the bottom.)\nThe first word was a name."},
	{"id": "last_leaf", "title": "The last leaf", "where": "stacks", "floor": 3,
		"text": "If you are reading this, you were written after.\nSo it didn't work.\nOr — —\n(The tear is clean, as if someone chose where to stop.)"},
]
const FRAGMENT_PICKUP := 30.0      # walk this close to pick a page up
const FRAGMENT_SEEN := {"grass": 110.0, "stone": 170.0, "site": 9999.0}   # how close before you can see it
const FRAGMENT_SITE_OFFSET := Vector2(34, -26)   # where a site's page lies, from its centre

# ---------------------------------------------------------------- Words
const LINES := {
	"site_first_seen": "The paper is bare here. Even the lines are thinning out.",
	"guardian_first": "The smudges here had knotted into something bigger. It came apart, and the pale stopped moving.",
	"restore_first": "I wrote it back. I didn't know I could do that.",
	"reerase_first": "The pale is creeping back where I haven't been. Places need to be remembered.",
	"rewritten": "I wrote it back again. It remembered faster this time.",
	"fragment_first": "A torn page, not from my book. The hand is older than the Hearth.",
	"fragments_head": "TORN PAGES",
	"fragments_none": "Nothing yet.",
	"fragments_bare": "I keep them folded with my own page.",
	"fragments_button": "Torn pages",
	"fragments_prev": "◂",
	"fragments_next": "▸",
	"fragments_close": "Put them away",
}
