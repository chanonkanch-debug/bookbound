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
