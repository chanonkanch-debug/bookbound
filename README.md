# Bookbound

Every mage is born holding a grimoire. It decides how you fight, never how strong you are.

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
| Cast spells | 1, 2, 3 (aims at the nearest enemy) |
| Hidden spell (if you unlock it) | 4 |
| Open your book | B (Esc or B to close) |
| Designer view (spoilers) | F1 |
| Screenshot | F12 |

---

## 2. Your first change (try this now)

Open `scripts/data/game_data.gd` in Godot (double-click it in the FileSystem panel, bottom-left).
**Every number in the game is in this one file.** For example:

- Find `"Ember Bolt"` and change `"dmg": 14.0` to `"dmg": 40.0`.
- Change `INK_PER_LEVEL := 2` to `5`.
- Change the `"chance"` values under `THICKNESS` to make thin books rarer.

Press F5 again and play. That's the whole loop: change, play, repeat.

---

## 3. Where everything is

```
project.godot              Project settings (window size, which scripts load first)
scenes/main.tscn           The starting scene. It only holds main.gd.
scripts/
  data/game_data.gd        ★ All numbers and text: elements, spells, books, monsters, hidden chapters
  game.gd                  Rolls new books, works out spell stats, saves and loads
  main.gd                  Switches between the Book Rite and the world; also the self-test
  rite/rite_screen.gd      Character creation and the book reveal
  world/world.gd           The field: spawning, spells, damage, element combos, drawing effects
  world/player.gd          You: movement, healing at the Hearth
  world/enemy.gd           Ink monsters: wander, chase, bite
  world/ally.gd            Mira, the AI stand-in for a second player
  world/hidden_chapter.gd  ★ The secret: progress, margin hints, awakening
  ui/hud.gd                Side panel, spell buttons, journal, designer view
  ui/book_overlay.gd       The open book you see when pressing B
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
uses every spell, awakens a hidden chapter, and quits:

```
godot --path . -- --autotest
```

If it prints `Autotest finished`, the game logic works end to end.

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
- Every book has a hidden chapter. Players must find it; the game never tells them it exists.
- Hidden chapter details (`ASPECTS` in game_data.gd, and hidden_chapter.gd) move to the server in milestone 4 so they can't be datamined.
