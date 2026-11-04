# The first hour

What a new player's first hour looks like, minute by minute, and what was fixed in
The Unwritten, Phase 1. Written from the first-hour bot (`scripts/dev/first_hour.gd`),
which plays like someone who has never seen the game: it only uses a control once it
would plausibly have found it, from a nudge or by trying keys.

```
godot --headless --path . -- --firsthour                      # all three players, seed 1
godot --headless --path . -- --firsthour --persona=bold --seed=2 --minutes=30
godot --headless --path . -- --balance --only=firsthour      # the same, from the balance bot
```

Three kinds of player, each run with seeds 1, 2 and 3 (nine hours of play in all):

| player | what they do |
|---|---|
| careful | waits about 30 s before trying to attack, backs off when hurt, never presses keys it hasn't been shown |
| curious | presses number keys, J and M out of curiosity, explores |
| bold | attacks at once, stays in fights longer, dies more |

The bot is a better fighter than a real new player (it never misses its aim and kills
about 8 monsters a minute in the first field). Read its times as the fastest a person
would reach each moment. A real first hour will be slower.

---

## Before the fixes

The first runs, before any Phase 1 change, found one problem far worse than the rest:

- **Nobody found resting.** The careful player first rested at 35:18, the curious one at
  25:12 and the bold one at 17:05. Levels are only written when you rest, so for 17 to 35
  minutes nothing changed: no levels, no growth, no ceremony.
  Why: the rest nudge waited for you to be hurt and safe for 30 seconds, but walking back
  into the Hearth heals you before the 30 seconds are up. So the nudge almost never fired.
- **Quiet from minute 9 to minute 29** for the careful player (nothing new at all).
- **Resting was impossible in the Hearth while a monster waited outside it.** Monsters
  that chased you home paced at the edge forever, and that counted as "in danger".
- **All the hidden-chapter hints came at once.** Once a chapter's progress was high
  enough, its three margin hints arrived within ten seconds of each other.
- **Nine growth lines on one rest.** A long first rest wrote every hand growth that had
  built up, all at once, and the whisper at the top of the screen replaced each line
  with the next, so only the last could be read.
- **The first journal line was often a secret.** A discovery about Mira or a spell secret
  could be the very first thing written, before the player had even hit something.
- **The map was rarely opened.** Only the curious player, who presses M by chance, ever
  looked at it.

## The fixes

| problem | fix | where to tune it |
|---|---|---|
| resting not found | a new nudge shows R by any fire (the Hearth counts) once a level is waiting and you've never rested | `NUDGES.rest_fire` |
| monsters waiting at the Hearth | the Hearth is always safe to rest in; a monster pacing at its edge gives up after a few seconds and won't chase again until it has wandered | `MONSTERS.hearth_give_up` |
| hints all at once | each chapter hint waits its turn, at most one every two and a half minutes | `CHAPTER_TUNING.hint_gap` |
| nine lines on one rest | at most one hand growth per rest; the whisper is a queue now, each line gets its own moment | `HAND_REST_MAX`, `WHISPER_QUEUED` |
| first line is a secret | lines about monsters' natures, ground, hands and combos wait until your first kill | `journal()` in world.gd |
| ceremony too soon once resting was found | before the book, kills teach a little less (0.6) | `BARE_XP_MULT` |
| map never opened | an M nudge after the map has been there a minute | `NUDGES.map` |
| fires don't say "rest here" | a fire glows and sparks while levels are waiting to be written | `FEEL.fire_call_range` |

---

## The first hour now

The times below are the range across the nine runs (three players, three seeds).

| time | what happens | how the player finds it |
|---|---|---|
| 0:00 | You wake in the Hearth. "Grass and small things. They come in twos." | the first journal line, in the whisper |
| 0:02 to 0:06 | The journal appears. "The Hearth is warm. Nothing follows me in here." | region line |
| 0:02 to 0:11 | Your hands appear at the bottom of the screen | a monster comes close |
| 0:01 to 0:34 | First attack | bold players at once, careful ones after the attack nudge or by trying Space |
| 0:08 to 0:38 | First kill. A burst of 3 or 4 lines (first kill, an affinity, a combo) | the whisper shows them one after another |
| 0:23 to 1:38 | **R by the fire.** First rest, first level written | the new rest nudge |
| 0:47 to 0:54 | J nudge, journal opened | journal nudge |
| 1:30 to 1:44 | Turning pages (Jab, Shove, Sidestep) | page nudge, or pressing 1 to 3 |
| 1:00 to 2:36 | "The ground goes soft. Something heavy moves out there." First trip toward the Marsh | region line |
| 1:07 to 6:22 | The map, found torn in the Marsh or by walking all three regions | journal line, then the M nudge |
| 2 to 7 | The hands grow: one new feeling per rest, the leaning starts to show ("Two feelings pull at me") | journal, the fist's tint |
| 6:00 to 10:46 | "Something at the Hearth is calling me home." Level 5 is waiting | journal, fire glows |
| **6:36 to 11:26** | **The Book Ceremony** | rest in the Hearth at Lv 5 |
| +0:00 to +0:30 | First lines about the book's element ("Wind caught the wet one…") | combo and affinity lines |
| +0:10 to +1:50 | Margins appear, the first margin hint | the open book shows them |
| +1:50 to +3:00 | B nudge, the book is opened for the first time | book nudge (only if not already opened) |
| +1:00 to +3:00 | "A gold frame grew around the page." First spell growth | spending ink at a rest |
| 15:00 to 17:30 | "A blank page has appeared at the back of your book." | margin |
| **17:16 to 19:30** | **A hidden chapter awakens** (hunger, stillness, echo) | playing the way the chapter wants |
| 20 to 60 | Levels every 2 to 10 minutes, a new journal or margin line every 5 to 15 | |

Two chapters behave differently, on purpose:
- **The Last Page** needs you to nearly die. The curious player got its blank page at 22:10
  and 50:42; one careful run never got it. That's right for the rarest chapter.
- **Echo** needs Mira beside you. It woke at 19:30.

### Deaths

Careful players: none. Curious: 0 to 2. Bold: 0 to 2, most of them in the Marsh between
minutes 2 and 7, before the book. Each death writes "I fell, and woke by the Hearth.
Something was taken from me." That's the only explanation, and it's enough.

---

## What still feels off

### Quiet stretches after minute 20 (not fixed: needs content)

Every run has long stretches with nothing new after about minute 20. For example the
careful player, seed 1: nothing new in minutes 19 to 21, 23 to 26, 29 to 34, 36 to 53,
57 to 60. Every journal line, margin and secret that exists has been found by then,
except the rarest combos. Levels still come every few minutes, but there is nothing new to
learn or see.

This is a content gap, not a tuning problem, and the later phases fill it:
- Phase 2: erasure sites to restore and fragments to find.
- Phase 3: monster inks and branching growth (new things to learn per spell).
- Phase 5 and 6: Hearth people, day and night, weather.

Before the fixes the quiet started at minute 9, so it has moved eleven minutes later.

### Lines arriving in bursts

The first kill can write four lines in one second ("It came apart like wet ink", the
small ones drink water, the third blow splashed, I hit it as it gathered itself). The
whisper now shows them one at a time, 3.5 s apart, so each can be read, but it's still a
lot at once. Kept: it's the moment the world first answers back, and it's short.

### The bot is faster than a person

A careful bot reaches the ceremony in under 7 minutes; a person who stops to look around
will take 10 to 15. The bare-hands balance bot (which fights more like a person) now takes
8.5 to 18 minutes depending on style. See the question on pace in the Phase 1 report.

### Things a player can't easily find

- **Holding R to rest anywhere safe** (not only at a fire). Most players now get the R nudge
  by a fire first, so they may think resting only works there. Found by trying, or from the
  key page in the pause menu once you've rested.
- **Keys 4 to 6 for learned moves.** No nudge yet. The journal line and a new mark on the
  stance bar are the only hints. Deferred: it's a small reward for players who look.
- **The designer view (F1)** is not on the key page, on purpose.

---

## Readability checks (screenshots)

`-- --showcase` (needs a screen, or `xvfb-run`) saves screenshots of every element's
bolts, zones and bursts, monsters at each point of a wind-up, and every reading state.
They're saved in the Godot user folder (`showcase_*.png`).

## 60 FPS in the heaviest scene

`-- --stress` builds the busiest scene the game allows: the most monsters plus three,
every element's biggest zone every third of a second, burning grass, 140 lingering
splatters. Headless on the test machine, over two runs: **rules 1.5 to 2.1 ms, whole frame 6.9 to 7.8 ms
(worst single frame 10 to 16 ms)** with about 110 zones, 50 flying spells, 140 splatters and 8 monsters. 16.7 ms is 60 FPS, so
there's room. Drawing on a real graphics card hasn't been measured here (the test machine
has none); that's worth a check on your own computer with `-- --stress` without `--headless`.
