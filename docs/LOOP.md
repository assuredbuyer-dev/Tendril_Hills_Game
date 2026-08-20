# The Loop

How Tendril Hills gets better, one pass at a time. This is written for
Claude in Cowork to follow literally, and for AJ to read over its
shoulder.

The whole idea: **the game photographs itself, Claude looks at the
photographs, Claude changes the code, repeat.** No human has to describe
what's wrong. The screenshots are the description.

---

## Running one pass

```bash
cd ~/path/to/TendrilHills3D
chmod +x tools/shots.sh      # once, ever
./tools/shots.sh
```

Eight PNGs land in `.shots/`. That is the entire loop's input.

### If it does not run

| Symptom | Cause | Fix |
|---|---|---|
| `command not found: godot` | Godot lives inside a `.app` on macOS | The script hunts for it. If it still fails, `GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./tools/shots.sh` |
| Runs, window flashes, no PNGs | `--shots` never reached the game | The bare `--` before it is not optional. `tools/shots.sh` handles this — use the script rather than typing the command |
| Script error on boot | A GDScript parse error | The trace is in the terminal output; fix and rerun |
| Shots look identical | Camera didn't move between framings | `capture.gd` calls `player.snap_camera()` — confirm that method still exists after any player.gd edit |

### Where the shots go

`.shots/` inside the project, **not** the macOS app-data folder. This is
deliberate: Cowork can read the repo, so putting the output in the repo
means Claude sees the screenshots without you moving files. `.shots/` is
wiped at the start of every run, so it is always the current build.

Add it to `.gitignore` — these are scratch, not history.

---

## The pass itself

One pass = one problem. Not four. The reason is that art and feel bugs
interact: fix the fog and the shadow bug looks different, so a batch of
four fixes produces a screenshot you cannot reason about.

**1. Run `./tools/shots.sh`.**

**2. Claude reads all eight PNGs and writes a numbered findings list.**
Each finding is one sentence naming the shot, what is wrong, and the
file most likely responsible. No fixes yet. Example:

> 3. `04_farm` — the fence posts read as a solid picket wall competing
>    with the crops for attention. `world.gd:_build_farm()`, the
>    perimeter loop.

**3. AJ picks one.** Just the number.

**4. Claude changes the code.** One concern, and it names every file it
touched.

**5. Run `./tools/shots.sh` again. Compare the same shot before and
after.** If it did not improve, revert rather than stacking a second
fix on top of a failed one.

**6. If the change was structural, add a line to `docs/DECISIONS.md`.**
Cosmetic tweaks do not earn an entry; anything that would be expensive
to reverse does.

---

## What Claude is looking for

In priority order, because a beautiful game that reads wrong is worse
than a plain one that reads right.

1. **Camera** — is anything between the lens and the Sprite? Is the
   Sprite ever off-centre, cut off, or behind geometry?
2. **Readability** — can you tell, in one glance and with no HUD, what
   is interactive and what is scenery? A seven-year-old is the test.
3. **Composition** — is the frame balanced, or is one corner empty and
   another crowded? Is anything tiling visibly?
4. **Light and colour** — does it still read as *clay* — soft, matte,
   handmade — or has it drifted plastic or muddy?
5. **HUD** — how much of the frame is panels? Does anything overlap?

Things Claude should **not** flag, because they are known and
deliberate — they are in README §6:

- procedural placeholder art quality
- default Godot font
- shortened playtest grow times
- the portal opening onto nothing

---

## Adding a framing

`scenes/dev/capture.gd`, the `_shots` array in `setup()`. Each entry is
a world position, a camera yaw in radians, and how long to settle before
photographing. Add one when you are working on an area the current eight
do not cover — a new building, the inside of the portal, a night pass.

`_seed_demo_state()` in the same file sets up the mid-season farm, 340
coins and three houses that appear in every shot. Change it when you
need the photographs to show a different moment in the game — an empty
first-run farm, or a late-game one.

---

## The other half of the loop

`./tools/selftest.sh` is the loop for *behaviour* rather than looks.
Run it before shipping any change to `game_state.gd`, `player.gd` or
anything in `autoload/`. It is fast enough that there is no reason not
to.

It exists because the screenshot loop is blind to crashes. The first
build shipped with a Godot 3 audio call in it — `can_push_frame()`,
which does not exist in Godot 4 — so every sound in the game threw at
runtime. Eight beautiful screenshots and the first keypress that made
a noise took the game down. Stills cannot catch that; pressing the
buttons can.

## Beyond screenshots

The loop above only sees still frames, which means it cannot see feel:
walk speed, camera lag, how long a grow actually takes. Those need you
at the keyboard for five minutes. The screenshot loop is for the look;
your hands are for the feel. Do not ask Claude to judge feel from a PNG.
