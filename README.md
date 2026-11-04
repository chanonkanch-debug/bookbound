# Bookbound

Every mage is bound to a grimoire. It decides how you fight, never how strong you are.

You start with bare hands. At **Lv 5** you return to the Hearth for the **Book Ceremony**, where a
random book chooses you. The game quietly watches *how* you fight until then (pressing one enemy,
hopping between enemies, keeping them off, never standing still, or planting your feet) and that
strongly tilts which element and thickness you get. A clear style gets its element most of the time;
a mixed style stays close to even. Moves you favour also grow "honed", so sticking with a style pays.

This is milestone 1: a single-player version of the browser prototype, built in Godot 4.
It is set up so co-op multiplayer can be added next.

---

## 1. Open and play (5 minutes)

1. Download **Godot 4.4 or newer** (the standard version, not .NET) from https://godotengine.org/download.
   It's a single program; there's nothing to install.
2. Unzip this folder somewhere you'll keep it, for example `Documents/bookbound`.
3. Open Godot. In the Project Manager, click **Import**, pick the `project.godot` file in this folder, then **Import & Edit**.
4. Press **F5** (or the ▶ button at the top right) to play.

The first time you open it, Godot spends a few seconds importing. That's normal.

### Controls

| Action | Keys |
|---|---|
| Move | WASD or arrow keys, or hold the left mouse button on the map |
| Read (cast) | Hold Space or the right mouse button, release to cast. Aims at the mouse (or where you face) |
| Turn the page | 1, 2, 3 to go to a page, Q / E or the mouse wheel for one page back / forward |
| Bare hands, before your book | The same keys: 1 Jab, 2 Shove, 3 Sidestep, then hold Space |
| Hidden spell (if you unlock it) | Hold 4 |
| Open your book | B (Esc or B to close) |
| Rest (writes your levels) | Hold R in a safe spot, or press R once at a campfire |
| Journal / map, once you have them | J / M |
| Designer view (spoilers) | F1 |
| Screenshot | F12 |

The screen starts empty on purpose: things appear as you need them. Levels are only written when you rest.
Casting takes time now: hold to read, release too early and it fizzles, hold longer to charge it.
See `docs/DESIGN_NOTES.md` for every rule and number.

---

## 2. Your first change (try this now)

Open `scripts/data/game_data.gd` in Godot (double-click it in the FileSystem panel, bottom-left).
**Every number in the game is in this one file.** For example:

- Find `"Ember Bolt"` and change `"dmg": 14.0` to `"dmg": 40.0`.
- Change `INK_PER_LEVEL := 2` to `5`.
- Change the `"chance"` values under `THICKNESS` to make thin books rarer.
- Change `CEREMONY_LEVEL := 5` to `2` to get your book almost straight away (rest in the Hearth to receive it).
- Change `"strength"` under `LEAN` to `0.0` to make the book fully random again, or `300.0` to make
  your fighting style almost decide it.

Press F5 again and play. That's the whole loop: change, play, repeat.

---

## 3. Where everything is

```
project.godot              Project settings (window size, which scripts load first)
scenes/main.tscn           The starting scene. It only holds main.gd.
scripts/
  data/game_data.gd        ★ All numbers and text: elements, spells, books, monsters, hidden chapters
  game.gd                  Rolls books (with leaning), works out spell stats, saves and loads
  main.gd                  Switches between creation, the world and the ceremony; also the self-test
  dev/balance.gd           The balance bot (see below)
  rite/rite_screen.gd      Character creation (name and background, bare hands)
  rite/ceremony_screen.gd  The Book Ceremony: the book reveal at Lv 3
  world/world.gd           The field: spawning, spells, damage, element combos, drawing effects
  world/player.gd          You: movement, healing at the Hearth
  world/enemy.gd           Ink monsters: wander, chase, bite
  world/ally.gd            Mira, the AI stand-in for a second player
  world/hidden_chapter.gd  ★ The secret: progress, margin hints, awakening
  ui/hud.gd                Side panel, spell buttons, journal, designer view
  ui/book_overlay.gd       The open book you see when pressing B
  ui/book_cover.gd         Draws a book cover (used by both rite screens)
  ui/ui_theme.gd           Colours and button styles
  util/ink.gd              Drawing helpers for the ink-blob look
```

Everything is drawn with code (circles, blobs, lines), so there are no art files yet.
When you want real art, we swap the `_draw()` functions for sprites one at a time.

**Why is the UI made in code instead of in the editor?** So we can work on it together
through text: I can read and change every line. Later, once you're comfortable in the
editor, we can move screens into `.tscn` scenes you edit visually.

---

## 4. How we work together

1. You play, then tell me what felt wrong or what you want next.
2. I write the change and send you updated files (or push them to GitHub, below).
3. You replace the files, press F5, and check.

**Strongly recommended:** put this project on GitHub. Create a free account, make a private
repository called `bookbound`, upload this folder, and connect GitHub to Claude. Then I can
make changes directly and you just pull them, and every version is saved so nothing breaks
for good. The `.gitignore` file is already set up.

### Self-test

From a terminal you can run the automatic smoke test, which plays for a few seconds,
fights bare-handed, attends the Book Ceremony, uses every spell, awakens a hidden chapter, and quits:

```
godot --headless --path . -- --autotest
```

If it prints `Autotest finished`, the game logic works end to end.

### Balance bot

To check that every playstyle levels at a similar pace and gets the book it should, run:

```
godot --headless --path . -- --balance
```

Five scripted players (brawler, spreader, controller, skirmisher, anchor) plus one that mixes
everything each play the bare-hands phase several times. It prints how long each took to reach
the ceremony, how often it died, and its book odds. Add `--signals` to see the raw playstyle
signals, or `--runs=20` for more runs. Run it after changing numbers in game_data.gd.

---

## 5. Roadmap

| Milestone | What | Status |
|---|---|---|
| 1. Single-player core | Book Rite, field, 5 elements, 3 book sizes, leveling and ink, 4 hidden chapters, Mira | ✅ This version |
| 2. Feel and content | Sound, hit effects, real sprites, item drops, a second map, more hidden chapters | Next |
| 3. Co-op (host a game) | One player hosts, friends join by IP. Mira is replaced by real players. Shared XP in parties. | After 2 |
| 4. Online | A dedicated server keeps books and hidden chapters secret, with accounts and a persistent world | Later |

### Design rules we're keeping

- The book never changes how strong you are, only how you play.
- Nobody picks their book. It's random at the ceremony, tilted by background and by how you fought
  bare-handed. Players never see the playstyle numbers (only the F1 designer view does).
- Every playstyle should reach the ceremony at about the same pace. The balance bot checks this.
- Every book has a hidden chapter. Players must find it; the game never tells them it exists.
- Hidden chapter details (`ASPECTS` in game_data.gd, and hidden_chapter.gd) move to the server in milestone 4 so they can't be datamined.
