# Design notes: slow, deliberate, discovered by playing

This file records every choice made while turning Bookbound into a slower, more
deliberate game: where the brief was unclear, which numbers were picked, and what
was deferred. All numbers live in `scripts/data/game_data.gd`, grouped by phase.

## Where the code differed from the brief

- The brief described the bare-hands moves as "honed" with a perk per style. The code
  matches this (`MASTERY_MAX`, `STANCES`).
- The brief said "ink" both for the resource spent on casting and for the currency
  earned by leveling. The code already had two things: `mana` (spent per cast) and
  `ch.ink` (earned per level, spent to grow spells). They stay separate. In these notes
  and in comments, **casting ink** means `mana` and **writing ink** means `ch.ink`.
- The old balance bot only tested the bare-hands phase. It now also plays every book.

## Hidden chapter pace: the baseline

Before any change, a simple bot with a book (Lv 6, Inkling Fields, 5 minutes) produced
these trigger events per minute. Used to keep chapters unlocking in about the same play time.

| book | casts | still casts | kills | kills on 5+ streak | Mira-assisted kills | near-death recoveries |
|---|---|---|---|---|---|---|
| fire thin | 107 | 3 | 61 | 60 | 7.8 | 0 |
| fire thick | 83 | 34 | 34 | 28 | 12 | 0.4 |
| water thin | 116 | 4 | 54 | 53 | 26 | 0 |
| water thick | 85 | 34 | 29 | 24 | 18 | 0.4 |
| earth thin | 90 | 15 | 56 | 53 | 14 | 0 |
| earth thick | 69 | 40 | 24 | 15 | 11 | 0.8 |
| wind thin | 161 | 0.2 | 57 | 56 | 7.8 | 0 |
| wind thick | 112 | 41 | 26 | 17 | 7 | 0.4 |
| lightning thin | 93 | 37 | 53 | 49 | 13 | 0 |
| lightning thick | 68 | 32 | 34 | 26 | 12 | 0.4 |

Averages: still casts about 24/min, streak kills about 38/min, Mira-assisted kills about
13/min, near-death recoveries about 0.25/min. With the old `need` ranges that means
Stillness took about 0.6 min of fighting, Hunger 0.5 min, Echo 1.3 min and Last Page about
10 min (bot time; people are slower).

---

## Phase 1: Deliberate combat

### Casting is reading
- **Controls.** Hold **Space** or the **right mouse button** (gamepad: A) to read the open page;
  release to cast. **1 / 2 / 3** turn to a page, **Q / E** or the **mouse wheel** turn one page
  back or forward (gamepad: shoulder buttons). **4** reads the hidden Last Page directly (it is
  always "at the back of the book", so it needs no page turn). Left mouse still walks.
  The brief said "a cast key"; I made it one read key plus page keys, because page turning is now
  the main choice and three separate cast keys would skip it.
- **Cooldowns are gone.** A spell is limited only by its read time, ink and position. Every spell
  has `read` (minimum hold, 0.3–1.2 s) and `over` (extra hold that charges it) in `SPELLS`.
- **Ink is paid when you start reading.** That is how "fizzle refunds half" works: releasing early
  or having the read broken gives back `READ.fizzle_refund` (50%) of the ink paid. Health paid by
  overcasting is never refunded.
- **No auto-repeat.** Holding the key casts once; you must let go to start the next read
  (`casting.gd`, `armed`). After any cast there is a `READ.recover` pause of 0.2 s.
- **Overcharge.** Holding past the read time adds power linearly up to `READ.overcharge_cap` (+50%)
  over the spell's `over` seconds. An overcharged dash also goes up to 30% further. Overcharge costs
  no extra ink, so it is the ink-efficient choice and the time-inefficient one.
- **Moving while reading** reads at `READ.move_mult` (0.5×) speed.
- **Hits break reads** with `READ.break_chance` by element: earth 20% (steady), water 35%, wind 40%,
  fire 45%, lightning 50%, bare hands 50%.
- **Bare hands use the same rules.** Jab, Shove and Sidestep are stances, switched with the page keys
  in `PAGES.stance_switch` (0.2 s). Their read times are short (Jab 0.3 s, Shove 0.35 s, Sidestep 0.05 s).
- **Visuals.** While reading, small letters lift off the book and a ring fills around you; past the
  read time the ring closes and a gold ring grows with overcharge. A fizzle drops grey letters.
  No bars or numbers.

### Page turning
- `PAGES.turn_time`: thin 0 (never turns), medium 0.35 s, thick 0.4 s **per page**. Pages don't wrap,
  so page 1 to page 3 on a thick book costs 0.8 s. You can't read while turning.
- Thickness power rebalanced (`THICK_BALANCE`): thin damage ×0.9 (was ×1.3), medium ×1.05,
  thick ×1.3, thick ink cost ×1.0 (was ×1.15). Thick books pay in turn time instead.

### Aiming
- Bolts, chains and dashes go toward the mouse. Without a mouse (keyboard or gamepad) they go where
  you face. The game switches to mouse aim the moment the mouse moves, and back to facing when a
  gamepad stick moves.
- A Spark jumps first to the enemy nearest the cursor within `AIM.chain_snap` (80 px), else the first
  enemy within `AIM.chain_cone` (0.35 rad) of your aim line. If there is none it grounds out and the
  ink is spent.
- Zones land at the cursor, clamped to the spell's range. Novas are around you.
- A Jab still snaps to an enemy in punching reach near your aim line, because a punch that misses by
  a pixel felt bad.
- While reading only: a faint dashed aim line, placement circle or burst radius (`AIM.line_alpha`).

### Scarce ink
- `INK_REGEN.field` 0.9 per second (was 6), `INK_REGEN.hearth` 25 per second. Phase 2 adds resting.
- **Overcast** (`OVERCAST`): reading with too little ink is allowed; each missing ink costs 1.6 health.
  It is refused if it would kill you (the book shudders instead). For 2.5 s the character shakes,
  cracks and drips ink, and the screen edges flush red.

### Monsters
- `FOES` now has `windup`, `reach`, `recover` and a `behavior`; `MONSTERS` holds spawn and interrupt rules.
- Max monsters near you: 5 (was 16). Health is much higher (Inkling 220, Blot 1000, Knight 3000) and hits
  are heavier (14 / 40 / 60). XP per kill went up (10 / 30 / 75) but much less than health, so
  progress is slower overall, as asked.
- Wind-ups: Inkling 0.5 s, Blot 0.8 s, Knight 1.0 s. During a wind-up a monster swells, darkens and
  leans in. Blots show their charge lane, Knights show their striking arc, Inklings a reach ring.
- **Interrupts:** a single hit for 12% or more of the monster's health, or any push, cancels the
  wind-up and staggers it for 0.6 s.
- **Dodging:** dashes (Sidestep, Cyclone Step) make you untouchable for `DODGE_TIME` (0.3 s).
- **Behaviors:** Inklings always spawn in pairs and try to stand on opposite sides of you. Blots wind
  up from up to 190 px, charge in a straight line for 0.55 s, then rest 1.8 s. Smudge Knights turn
  slowly (1.5 rad/s), only start and land strikes inside a 120° front arc, and wear a heavy guard
  stroke on the side they face, so circling behind them is the answer.
- Monster health bars are still shown in Phase 1; Phase 2 replaces them.

### Other pacing numbers
- Fire Heat window 4 s (was 2.5 s), since casts are slower. `FIRE_HEAT_WINDOW`.
- Kill streak lasts 20 s after a kill (was 8 s). `STREAK_WINDOW`.
- Mira casts every 2.6 s (was 1.7 s) for 12 + 3×level damage (was 7 + 2×level).

### Hidden chapters at the new pace
The book bot's trigger rates after Phase 1 (`--balance --only=chapters`), compared with the baseline above:
still casts about 31/min (was 24), kills on a 3+ streak about 1/min (was 38/min on a 5+ streak),
Mira-assisted kills about 4.3/min (was 13), near-death recoveries about 0.04/min (was 0.25).
To keep each chapter at roughly the same play time:
- Stillness unchanged, `need` 10–18.
- Hunger counts kills on a streak of 3+ (`CHAPTER_TUNING.hunger_streak`, was 5), `need` 3–5 (was 14–24),
  and awakens on a streak of 3–4 (`hunger_act`, was 8–12). Hunger is now the slowest to find
  (about 4 min of bot fighting) because a 3-kill streak inside 20 s is rare with so few monsters.
- Echo: Mira's mark lasts 4 s (`echo_window`, was 2 s), `need` 4–7 (was 12–22).
- Last Page: `need` 1–2 (was 2–3). The bot rarely gets that low, but people do.

### Balance bot
`--balance` has three parts now: bare hands (as before), books (every element and thickness in each
region, Lv 5 / 8 / 11, ink spent evenly, Mira along, casting through the real read and page rules,
dodging wind-ups and walking home when hurt or dry), and `--only=chapters`. Use `--el=fire` to test one
element, which lets you run five copies in parallel. The book bot's metric is seconds to earn
150 / 240 / 375 XP in the region; a "fight" lasts while a hunting monster is within 300 px, ending
after 5 s of calm.

Results are in the Phase 1 report in the pull request. With 8 runs per cell the bot's own noise is about
±10%, so a cell just over 20% can flip between runs.

### Deferred or not quite right yet (Phase 1)
- **Bare-hands pace varies a lot by style** (spreader about 3 min to the ceremony, anchor about 15 min in
  bot time). The element each style leans to is right again, but planting and backing away are much
  slower now that there are so few monsters. Worth a dedicated pass.
- The book bot never dies, because it dodges every wind-up perfectly. People will get hit far more.
- Monster health bars are still on (removed in Phase 2).

---

## Phase 2: Minimal interface and slow progression

### What's on screen
- **Nothing at first** but you, Mira and the world. The side panel is gone. Its contents (every number,
  spells, playstyle odds, hidden chapter) moved to the **F1 designer view** (`designer_panel.gd`), which
  also has buttons to gain a level, rest now, unlock all UI and toggle `show_numbers`.
- **Health** shows on your body: the ink fades (down to 35% opacity) and up to seven cracks appear as you
  get hurt. Below 45% health the screen edges darken, deepest near death.
- **Casting ink** shows as how dark the lines on the open book page are (five lines, each fills a fifth),
  plus a soft glow when the page is full.
- **Hits** show as ink splatters sized by damage (radius 3 + 1.5 × √damage). No damage numbers. Element
  combos flash a coloured ring instead of a label.
- **Monster health** shows as pale cracks in the monster, no bar.
- **Page dots** under the book say how many pages there are and which is open; a page visibly lifts
  over the spine while turning.
- Region names fade in for a few seconds when you cross into a region (no "Lv 1–4" subtitle).
- The hidden **`show_numbers`** setting (off by default, saved in `user://settings.cfg`, toggled in F1)
  brings back damage numbers, monster health bars, combo labels and a one-line readout of health, ink,
  level, waiting levels and XP.

### Progressive disclosure (`UI_PARTS`, `UNLOCK`)
| Part | Appears when |
|---|---|
| Stance marks (bare hands) | a monster first comes within 150 px |
| Journal (corner mark, whispered lines, J) | first kill, first near-death (below 25%), first return to the Hearth, **or the first rest** |
| The book (bottom of the screen) | the ceremony |
| Margin notes (beside the book, and in the book with B) | the first hint |
| Map (M) | picking up the torn map scrap in Inkling Fields (`MAP_SCRAP`), or walking all three regions |

Each part fades in over `UI_FADE` (1.6 s) with no explanation. I added "the first rest" to the journal
triggers, because resting is when the journal is written, and it would be odd to rest and get no journal.
Old saves (version 1) start with everything unlocked except the map, and their nudges spent.

### Resting (`REST`, `CAMPFIRES`)
- XP is still earned per kill, but `gain_xp` only adds XP. **Levels are written only at rest**
  (`Game.write_levels`). `ch.level` is the written level; `Game.pending_level()` is what you'd be after resting.
- **Hold R** in a safe spot for 4 s, or **press R once at a campfire** for a 2.5 s rest. Campfires: the Hearth's
  fire (anywhere inside the Hearth counts) and one in each region.
- Moving, letting go of R (in the open), being hit, or a hunting monster within 260 px interrupts it.
  A broken rest flickers grey; a rest in progress shows a warm ring closing around you.
- While resting: casting ink +30/s (fast), health +6/s in the open, +14/s at a campfire.
- When it finishes: pending levels are written ("The book writes through the night." for 2.2 s over a dark
  veil), your health keeps the same share of the new maximum, and if you have a book and writing ink the
  pages open. Each page is drawn as lines of ink, one per level; a gilt frame marks each evolution.
  Click a page to write one ink into it; the inkwell beside the pages empties as you go. No numbers.
- **Writing ink can only be spent while resting.** The old "+ Ink" buttons are gone.
- The Book Ceremony now opens on **the first rest in the Hearth** at Lv 5 or more.
  Reaching Lv 5 while resting elsewhere writes "Something at the Hearth is calling me home."
- Dying still costs 10% of your XP toward the next level, and you wake in the Hearth.

### The journal (`JOURNAL`)
About twenty short entries in the world's voice, each fired once and saved (`ch.journal_ids`), for
example the first kill, near-death, death, return to the Hearth, first rest, first level written (bare or
with a book), each region, finding the map, walking all three regions, the first fizzle, overcast,
overcharge, interrupt, dodge and page turn. The old "lean" hints are still written at rests before the
ceremony, one per distinct line. Open the journal with J; the newest line is darkest.
"Close this book forever" (start a new character) moved into the journal, with the same press-twice guard.

### Nudges (`NUDGES`, `NUDGE_SHOW`)
A faint key glyph appears beside you, once ever, for each of: not moving for 12 s at the start; a monster
near for 60 s without attacking; 90 s with several pages or stances and no page turn; hurt and safe for
30 s without ever resting; having a book for 120 s without opening it; having the journal for 45 s without
opening it. Each shows for 6 s and is saved as spent.

### Saves
`save_version` is now 2 (`GameData.SAVE_VERSION`). `Game.migrate()` adds the new fields to a version-1 save
and keeps the book, spells, levels, writing ink and hidden-chapter progress exactly as they were.
The self-test feeds an old save through it and checks all of this.

### Player-facing text without numbers
Element passives, thickness descriptions, the start screen, the ceremony screen and the open book (B)
no longer show numbers or levels. The open book lists your pages (the open one marked), says when there's
ink to write, and shows all margin notes. An awakened hidden chapter now shows a numberless line
(`ASPECTS[...].told`); the exact `effect` text stays in the F1 view.

### Deferred or not quite right yet (Phase 2)
- The book bot now rests in the field instead of walking home, which makes the bare-hands phase slower
  still for the styles that get hurt most (see the report).
- Gamepad: R is also the Y button, but the journal and map have no gamepad buttons yet.
- The lean hints ("You stood your ground…") are written in second person while the rest of the journal
  is first person. I left them, since they read like the book speaking, but they could be rewritten.
- To keep the bare-hands phase from dragging now that healing is slow, Inklings give 14 XP (was 10 in
  Phase 1) and planting your feet blocks 50% of damage (`STANCES.planted_guard`, was 30%). The bot now
  takes about 4 to 15 minutes to reach the ceremony depending on style (jabbing styles fastest, dodging
  and planting slowest).

## Phase 3: Learning by experimenting

Nothing here is explained. The world reacts, and the journal and margins write down what you saw.
All numbers and lines are in the "Phase 3" block of `scripts/data/game_data.gd`. Rules live in
`world/terrain.gd` and `world/discovery.gd`; `world.gd` only calls them and draws.

### Monster affinities (`AFFINITIES`, `DISCOVERY`)
Every monster has at least two reactions to elements:

| Monster | Weak (×1.3) | Resists (×0.75) | Other |
|---|---|---|---|
| Inkling | fire | water | wind enrages it: faster for 4 s, but takes ×1.25 |
| Blot | fire | earth | water splits it into two Inklings once it's below 60% health |
| Smudge Knight | lightning | fire | earth breaks its guard (stagger 1.4 s, turns it); wind enrages it for 3 s |

A reaction counts as "seen" every time it happens, from your spells or Mira's. After
`DISCOVERY.affinity_seen` sightings (4) the journal writes a line, and the bestiary section of the journal
lists it from then on.

### Terrain (`TERRAIN`, `TERRAIN_LINES`)
The field has fixed patches (same layout every game, `TERRAIN.seed`) so they can be learned:
- **Dry grass** (Inkling Fields): fire sets it alight. It burns as a fire zone for 6 s that hurts monsters
  and, lightly, you; burnt grass regrows after 90 s.
- **Puddles** (Blot Marsh): anything standing in one is soaked; water zones placed on one grow ×1.4.
- **Stones** (Knight's Reach): earth zones placed on stones last twice as long.
- **Open ground** (all regions): wind spells cast from it reach ×1.5 further.
- **Wind carries fire**: a wind spell passing through a fire zone carries it along, and a gentle breeze
  slowly drifts all fire zones.
Each writes a journal line the first time you see it.

### Spell secrets (`SECRETS`)
Each of the 15 spells has one hidden behavior (listed with conditions in F1, and in the `SECRETS` table).
The first time it happens, a short line is written into the book's margins next to the hidden-chapter
hints. These are separate from hidden chapters: smaller, always on, and nothing is "awakened".

### Mira teaches by example (`MIRA_TEACH`)
Mira picks targets by distance, plus a bonus for hitting a monster with an element whose reaction you
haven't learned yet, for soaking monsters near you when you have a secret that needs wet targets, and for
hitting monsters in puddles. She never says anything about it.

### Saves
`save_version` is now 3. Migration from 1 or 2 adds an empty `disc` (discoveries) record and keeps
everything else.

### Balance with affinities
Affinities deliberately make some elements better against some monsters, so the "every element within
±20% in every region" goal now holds only roughly. The bot doesn't use terrain or secrets on purpose,
so its numbers are what a player who ignores them would see. In the Phase 3 run (6 runs per book),
37 of 45 cells were within ±20% and the widest gap was 28% (wind medium/thick are fast in Blot Marsh;
earth thin is slow there because Blots resist earth). Fights last a median 8 to 73 s depending on book and
region. Full table in the Phase 3 report.

### Deferred or not quite right yet (Phase 3)
- Terrain patches are drawn as soft ink stains; they are readable but not pretty. New art was out of scope.
- The balance bot doesn't play around affinities (it never switches book to suit a region), so
  regions where your element is weak or resisted are slower for it than they would be for a curious player.
- Some secrets (Quake inside Rampart, Pyre on Pyre) need deliberate setup, and are likely to be found late
  or by reading F1.

## Bare hands that grow

Before, Jab, Shove and Sidestep looked and played the same from the first fight to the ceremony, and the
only progress was a hidden damage bonus. Now the bare-hands phase has its own small arc, all numberless and
written into the journal. Numbers are in the "Bare hands: learning by fighting" block of `game_data.gd`;
rules are in `world/hands.gd`, with the hooks in `world.gd` (`_hand_hit`, `_cast_bare`, `enemy_strike`).

Ideas researched and chosen: Absolver (learn a move by surviving it), use-based skills with Raph Koster's
warning about grinding (only meaningful use counts), and Sifu (rejected for now: harsher failure would fight
the slow pace). The brainstorm doc lists the others.

### Learning moves from monsters (`HAND_LESSONS`, `LEARNED_MOVES`)
Dodging a monster's strike (Sidestepping through it, or it biting your decoy), interrupting its wind-up, or
Bracing against it counts as one lesson from that kind of monster. After enough lessons, your next rest
teaches you its move, which becomes a new stance on keys 4, 5 and 6 (or Q/E):
- **Flank Step** (Inklings, 4 lessons): circles to the far side of the nearest monster and hits it from
  behind, always interrupting it.
- **Bull Rush** (Blots, 3 lessons): a long read, then a straight charge that knocks everything aside.
  Overcharging makes it go further.
- **Brace** (Smudge Knights, 2 lessons): no damage. For 2.5 s, blows from the front mostly glance off and
  the attacker reels. It counts as standing your ground.

Learned moves only exist before the book. They also share the hidden mastery bonus with the basic three.

### Moves that grow (`HAND_GROWTH`)
Only meaningful uses count, so swinging at the air does nothing: a Jab that lands on a monster hunting you,
a Shove that catches something, a Sidestep that slips through a monster or a strike. At each threshold the
next rest grows the move one step, shown as small dots under its mark:
- **Jab**: 1) every Jab lands a second time; 2) every third Jab in a row on one monster knocks it back and staggers it.
- **Shove**: 1) what it catches reels; 2) wider and harder.
- **Sidestep**: 1) leaves an ink decoy where you stood, which monsters chase and bite; 2) slipping
  through a monster turns it around and leaves it reeling.

### Hand secrets (`HAND_SECRETS`)
Four hidden combos, each written into the journal the first time: **backhand** (Sidestep, then Jab right
away: more damage, always interrupts), **counter** (a Jab right at the end of a wind-up: a long stagger),
**tangle** (a Shove throws one monster into another: both reel) and **untouched** (three Jabs on one
monster without getting hurt: the third splashes onto those nearby).

### Hands tint toward your leaning (`HAND_TINT`)
Your fist slowly takes on the colour of the element your fighting style leans toward, so the ceremony's
book feels like the answer to something you watched build. It reads the same scores the ceremony uses.

### Saves
`save_version` is now 4; migration adds an empty `hands` record.

### Deferred or not quite right yet (bare hands)
- The balance bot doesn't use learned moves, so its bare-hands times only show the effect of growth.
- There's no nudge for the new keys 4 to 6 yet. The journal line and the new mark on the stance bar
  are the only hints.
- Knights live far out, so Brace will be rare before the ceremony. That's on purpose: it's a reward for exploring.

---

# The Unwritten

The milestone after the slow-RPG work. Eight phases, each stopped for the owner's okay.
Numbers for each phase are in their own block at the end of `scripts/data/game_data.gd`
(search for "The Unwritten, Phase").

## The Unwritten, Phase 1: polish what exists

The first hour, minute by minute, and what was fixed in it, is in `docs/FIRST_HOUR.md`.

### New designer tools

| command | what it does |
|---|---|
| `-- --firsthour [--persona=careful\|curious\|bold] [--seed=N] [--minutes=N]` | a new-player bot that only uses what it would have found; prints a timeline, a minute-by-minute table and quiet stretches (`scripts/dev/first_hour.gd`) |
| `-- --balance --only=books\|bare\|chapters\|firsthour [--el=fire] [--runs=N]` | one part of the balance bot |
| `-- --showcase` | screenshots of every element, wind-up and reading state (needs a screen or `xvfb-run`) |
| `-- --stress` | the heaviest scene, timed (`scripts/dev/showcase.gd`) |

### Tuning for the first hour (`NUDGES`, `BARE_XP_MULT`, `HAND_REST_MAX`, `CHAPTER_TUNING.hint_gap`, `MONSTERS.hearth_give_up`)

See `FIRST_HOUR.md` for why each one exists. In short: resting is found in the first two
minutes instead of after 17 to 35; the ceremony moved from 4 to 7 minutes (bot) to 7 to 11;
hints, growth lines and whispers come one at a time.

`BARE_XP_MULT = 0.6`: before the book, XP from everything is multiplied by this. The
bare-hands balance bot now takes these times to Lv 5 (4 runs each, seconds):

| style | before | now |
|---|---|---|
| brawler | 425 to 809 | 1101 |
| spreader | 202 to 519 | 524 |
| controller | 383 to 655 | 646 |
| skirmisher | 436 to 452 | 777 |
| anchor | 201 to 690 | 513 |
| mixed | 414 to 451 | 587 |

("before" is the range between the old version and Phase 1 without the multiplier; four runs
are noisy.) The spread between the fastest and slowest style went from about 3.4 times to
about 2.1 times. Brawler is now the slowest; it also dies the most along with skirmisher.

### Readability (`READABILITY`, `scripts/util/element_fx.gd`)

- Every element has its own shape and motion, not only colour: fire licks upward with
  rising embers, water is round drops and smooth ripples, earth is heavy angular blocks
  that barely move, wind is spinning crescents and spirals, lightning is zigzags that redraw
  every frame. Bolts, zones and bursts all follow this.
- Monster wind-ups: a ring that closes in on the monster as the bite comes.
- Reading: a faint full ring shows how long the read is; the progress line fills it; a flash
  when it's ready; a second, breathing ring while overcharging; a broken read is a split ring
  with a red slash; a fizzle scatters letters.
- Low ink: the book in your hand goes hollow with a red edge when this page costs more than
  you have, and the stance rim turns into a red dashed line.
- Low health: a slow heartbeat darkens the screen edges below `low_hp_pulse`.

### Feel (`FEEL`)

- Hit-pause: the world stops for `hitstop_time` when your hit takes `hitstop_frac` of a
  monster's health or more, when you take `hitstop_hurt` damage or more, and on the Last Page.
  On by default, because it's very short.
- Screen shake: off by default (it fought the quiet mood). When on, it shakes for tier-2
  kills, for taking `shake_hurt` damage or more, and for the Last Page.
- Splatters linger: `splat_life` seconds, `kill_splat_life` for kills, at most `splat_max`.
- Page turn: the page lifts and folds over (`page_turn_lift`).
- The world rules (`World._update`) never see hit-pause or shake, so tests and bots are
  unaffected by either setting.

### Controls and the pause menu (`PAUSE`, `KEY_PAGE`, `SETTINGS`, `UI_SCALES`)

- Gamepad: left stick moves, right stick aims, A reads, Y rests, shoulders turn pages,
  left trigger is the Last Page, D-pad up is the journal, D-pad down the map, Back opens the
  book, Start pauses. X is kept for talking (Phase 5).
- Esc or Start closes whatever is open, or opens the pause menu: back to the world,
  settings, what my hands know (the key page), rest here and leave (saves and quits).
- The key page is drawn like a page of the book and only lists controls you've found
  (`KEY_PAGE` rows say when each appears), so it never gives a secret away.
- Settings, saved in `user://settings.cfg`: hit-pause, shake, UI size (four steps, named in
  words), and show numbers (off; for testing).

### The sweep

Tested by `--autotest` (85 checks now):
- Dying while reading cancels the read.
- Resting twice during the ceremony shows the ceremony once.
- A chapter waking mid-read cancels the read and gives the ink back.
- Holding the read key through a page change doesn't cast again.
- Save and load at every interface unlock stage, with and without a book.
- The pause menu, key page, settings, UI scale, hit-pause on and off, gamepad bindings.
- Every GDScript warning was fixed; the warnings check treats them as errors.

Save version stays 4: Phase 1 adds no saved state except new keys inside existing records
(`nudged.map`, `opened.map`), which load as missing and default to false.

### The voice pass (`JOURNAL`, `LEAN_*`, `BOOK_TEXT`)

Rule: the journal is the character's own hand, first person, past tense, no game words
(level, XP, mana, damage). Margins are the book speaking, second person or bare
instruction. The lean lines and the open-book text were rewritten to match, and the open
book's text moved into `BOOK_TEXT`.

### Book balance after Phase 1

Phase 1 changes no spell, so the book table should match the version before it. It does,
within the noise of four runs. Region averages (seconds): old 85 / 110 / 160, now
82 / 113 / 164. Per element, compared with the average of all fifteen books:

| element | Fields | Marsh | Reach |
|---|---|---|---|
| fire | +7% | +1% | +13% |
| water (8 runs) | +2% | +1% | -6% |
| earth | +6% | +15% | +15% |
| wind (8 runs) | +7% | -15% | -20% |
| lightning | -5% | -9% | -7% |

Wind is a little fast later on, and was before Phase 1 too (-15% and -22%). Single books
swing by up to 30% between runs of four, so the `!` marks in one run aren't meaningful on
their own. Left as it is; Phase 3 (monster inks) changes the fights anyway, and the table
will be re-run then.

### Deferred or not quite right yet (The Unwritten, Phase 1)

- **Quiet stretches after minute 20.** Content, not tuning. Phases 2, 3, 5 and 6.
- **No nudge for keys 4 to 6** (learned moves). Kept as a reward for looking.
- **Drawing speed on a real graphics card** wasn't measured (the test machine has none).
  Run `-- --stress` without `--headless` on a real computer.
- **The first kill writes four lines at once.** They're queued now, so each can be read.
- **The bots fight better than people**, so their times are the fastest a person would see.

---

## The Unwritten, Phase 2: lore, erasure sites, restoring the world

The story is in `docs/LORE.md` (approved by the owner before building). Numbers and words
for this phase are in **`scripts/data/lore_data.gd`**, the first split of the data layer. It
is reached through `game_data.gd` as `GameData.Lore` (for example `GameData.Lore.SITES`), so
`game_data.gd` is still the single entry point. Split rule from now on: a phase with a lot of
text gets its own file under `scripts/data/`, preloaded as a const at the top of `game_data.gd`
and listed in the header comment there.

New code: `world/erasure.gd` (rules for sites, guardians, restoring and re-erasure),
`world/torn_pages.gd` (pages lying in the world), `util/site_fx.gd` (how sites, the wave,
pages and the Hearth's windows look), `ui/fragments_overlay.gd` (reading the pages).

### Erasure sites (`SITES`, `ERASURE`)

Eight sites: two in Inkling Fields, three in Blot Marsh, three in Knight's Reach. Each is
"erased" (bare), "cleared" (guardian beaten, still bare) or "restored".

Near a bare site (full strength inside it, fading to nothing at twice its radius):
- spells read at 0.85 speed (`read_speed`), casting ink comes back at half speed (`ink_regen`);
- ground patches within 1.4 radii lose their nature and their look (`terrain_fade`): grass
  won't burn, puddles don't soak, stones and open ground do nothing;
- 45% of new monsters appear at a bare site within 800 px instead of around you
  (`gather_chance`), but only while its guardian sleeps. During the guardian fight nothing
  else gathers, and once it's beaten the pale stops drawing them.

### Guardians (`GUARDIANS`, `GUARDIAN_WAKE`, `GUARDIAN_LEASH`, `GUARDIAN_INK`)

When you come within 170 px of a bare site's edge, its guardian wakes with 1 to 3 ordinary
monsters of the region: the Scrawl (an Inkling x10 health), the Spill (a Blot x2.5), the
Hollow (a Knight x1.5). They're bigger, hit a little harder, are wrapped in a pale halo, and:
- **have no element affinities** ("made of the pale"), so no book is locked out of a site;
- don't despawn when you walk away, and won't chase you further than 3 site radii;
- don't heal, so a fight can be finished in several goes;
- give 1.5 to 2 times normal XP (first tried at 4 to 6 times: a guardian alone was worth a
  region's whole XP test, which sped the book table up by a third).

`GUARDIAN_INK` multiplies each element's damage against guardians, for single-target balance:
lightning 1.5, the rest 1.0. Chain spells waste their jumps on one big target.

### Restoring

Rest at the centre of a cleared site (hold R, within 0.6 radii) to write it back. The site
gets a campfire (so later rests there are one press), a colour wash for its region, denser
lines, small flowers and its own detail (a fence, grass, a pool, stepping stones, reeds, a
red banner, hill contours, a carved line), and around it 70% of new monsters don't appear
(`calm_skip` within 3 radii). One house in the Hearth lights its window per restored site
(`HEARTH_WINDOWS`); Phase 5 adds people.

The moment itself (`RESTORE_FX`, `site_fx.gd`): a short hit-pause, then over 4.5 s a gilt
front spreads from the centre with ink tendrils racing ahead of it and gilt sparks rising;
the pale drains away behind it and the colour and details are drawn in as the front passes
them. Two journal lines: "I wrote it back. I didn't know I could do that." the first time, and
the site's own line.

### Slow re-erasure (`REERASE`)

A restored site starts to fade once its region has gone 20 minutes of play without a visit
(`grace`), and is bare again 30 minutes after that (`fade_time`). Visiting the region stops
the fading; resting at the site writes it back in full ("I wrote it back again. It remembered
faster this time."). The first fade past a quarter writes "The pale is creeping back where I
haven't been." Fully faded, it loses its fire, its window goes dark and the guardian returns.
Off with `REERASE.enabled`, or the pause-menu setting "The pale returns to forgotten places"
(`Game.settings.reerase`, on by default).

### Torn pages (`FRAGMENTS`)

Twelve pages, the texts from LORE.md. Nine are placed now: two in grass (seen within 110 px),
three behind stones (a stone is always drawn, the page corner shows within 170 px), four at
sites (they appear once the site is written back). The last three wait for the Stacks
(Phase 7) and aren't placed anywhere yet. Walk over one to pick it up (30 px). The first one
writes a journal line; each shows its title briefly where it lay.

They're read as torn paper, one at a time, in the order found, newest first, with a row of
dots instead of a count. With a book they're at the back of the book (a "Torn pages" button,
or Q / E / a shoulder button with the book open); before the book they're kept with the
journal ("I keep them folded with my own page."). The key page lists them once one is found.

### Saves

- **Character save version 5**: `fragments` (ids in the order found). Migration adds an
  empty list; books, levels, discoveries and chapter progress are untouched.
- **A new world save**, `user://bookbound_world.json`, version 1 (`Game.world`): each site's
  state, paleness, times written back and whether its fading was noticed; when each region
  was last visited; and the world's play time. It's apart from the character so a host can
  own it later. A missing world file (any older save) starts a fresh world.
  `Game.migrate_world` adds sites from later versions without touching restored ones.
- A new character starts a new world.

### F1

New sections: every site's state, paleness, how long its region has been left alone,
whether its guardian is awake, and how many times it was written back; the erasure strength,
read speed and ink refill where you stand; every torn page, found or not and where it lies.
New button: "Write back the nearest site".

### Balance after Phase 2

Guardian fights (`--balance --only=sites`, medium books at Lv 5 / 8 / 11, 10 runs; bare hands
at Lv 4 in the Fields), seconds from the guardian waking to its fall:

| | Fields | Marsh | Reach |
|---|---|---|---|
| fire | 22 | 25 | 76 |
| water | 27 | 46 | 65 |
| earth | 41 | 34 | 56 |
| wind | 22 | 42 | 67 |
| lightning | 16 | 59 | 59 |
| average | 26 | 41 | 65 |
| bare hands (Lv 4) | 38 | | |

Every book (and bare hands) writes back every site in every run. Knight's Reach is within
±18% for every book. The Fields and Marsh fights are short and noisy, from -39% to +60%: two
batches of ten runs disagree by about as much, because a medium book gets a random second
page and a 20-second fight swings on a single wind-up. Not yet a ±20% proof; Phase 3's
branch balance re-runs it with more runs per cell.

Book table (`--balance --only=books`, 4 runs): region averages are now 61 / 80 / 122 seconds
(was 82 / 113 / 164 before Phase 2), because bots start in a fresh world each run and the
guardians and gathered monsters near sites are worth XP. Per element, against the average of
all fifteen books: fire -22 / +29 / +18, water 0 / +6 / 0, earth +19 / +1 / -2,
wind -22 / -25 / -17, lightning +25 / -12 / +1. Wind stays a little fast, as before.

### Deferred or not quite right yet (The Unwritten, Phase 2)

- **Bots restore four to eight sites in their first hour.** A person will be slower, but this
  may still be faster than "slow and meaningful" wants. The first Fields site falls at 1 to 5
  minutes, before the ceremony. Tunable with the guardians' health.
- **Guardian fights aren't within ±20% per book yet** (see above).
- **Site names** aren't shown anywhere yet; the Cartographer (Phase 5) marks them on the map.
- **The Stacks' three pages** are written but not placed (Phase 7).
- **Day and night** don't touch sites yet (Phase 6 makes them pulse at night).
