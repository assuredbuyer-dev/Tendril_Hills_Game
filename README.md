# Tendril Hills — 3D clay build
**Tendrel Studios** · Godot 4.5 · runs on your Mac and in a browser

A walkable, playable slice of Tendril Hills in 3D. You are the Sprite.
You walk out of the meadow, meet Old Sprout, turn over soil, plant a
carrot, water it, wait, pull it up, eat it, sell the rest, and build a
mushroom house. The Root Portal sits dormant in the west, counting
your quests.

**There is not one image file in this project.** Every mushroom,
carrot, tree and eyeball is sculpted at runtime from two mesh
generators and one shader. That is deliberate — it means the game is
fully playable *today*, it lives in Git as readable text, and each
object can be swapped for real Tripo3D art one at a time without
touching a line of game logic.

---

## 1. Run it (about five minutes, once)

1. Download **Godot 4.5 or newer, standard edition** (not .NET) from
   godotengine.org. It's a single app — no installer, runs natively on
   your M4 MacBook Air.
2. Open Godot → **Import** → choose this folder's `project.godot`.
3. Press **▶** (F5). That is the entire build process.

First launch spends a few seconds generating meshes; after that it's
instant.

### Controls

| Key | Does |
|---|---|
| **WASD** or arrows | walk |
| **Space** | jump |
| **Q / R** | swing the camera around |
| **E** / Enter / left-click | do the obvious thing to whatever you're standing next to |
| **1** | eat the most filling thing in your basket |
| **2** | switch seed — or, while building, switch what you're placing |
| **3** | place something you crafted, **E** to put it down, **3** to cancel |
| **H** | show/hide the controls card |
| **F9** | wipe the save and start over |

**Your belly is a carrot, not a stick.** Nothing bad happens at zero.
Above 70 the Sprite walks a little faster and sometimes pulls up two
crops instead of one; below 20 it trudges. That's the whole system —
this is a cozy game and nobody gets punished for wandering off.

**The map, and your corner of it.** The village in the middle is
shared — Old Sprout, Pip's stall, the workbench, the quest board and
the Root Portal. Walk out to any corner and you find a clearing with a
name on a signpost: Bramblewick, Honeyhollow, Thistledown, Mosswood.
Each is flat, ringed with stones, has its own patch of soil, and is
otherwise empty on purpose — it is somewhere to build, not somewhere
to look at. Between them, on the compass points, are four places thick
with one material each: **Stonefall** north, the **Long Grove** east,
**Toadfen** south, the **Old Quarry** west. Needing stone is a
direction, not a search.

All of it is two lists — `Terrain.HOMESTEADS` and `World.POCKETS`. Add
a row to either and a whole new place appears, terrain and signpost and
soil included.

**Two economies, two jobs.** Coins come from farming and buy seeds.
Materials come from walking around — toadstools, stones and fallen
branches you pick up with **E** — and build things at the workbench.
Before this, everything outside the fence was scenery. Picked spots
regrow after a couple of minutes, including while the game is closed,
so the meadow can never be stripped bare.

**What you can bump into.** Trees, houses, the stall, the workbench,
the quest board, fence posts and Old Sprout are all solid. The Root
Portal is deliberately not — you walk under an archway. Neither are
toadstools and pebbles, because those are pickups and snagging on
ankle-height scenery is miserable. Tree *canopies* are not walls
either; only the trunk is.

The farming loop is one button on purpose. Standing on a plot and
pressing **E** repeatedly walks you through
grass → till → plant → water → *wait* → harvest. A seven-year-old can
find that without being told; a menu of tools is a wall.

---

## 2. What's in the box

```
TendrilHills3D/
├── project.godot          Config. Registers autoloads, sets the
│                          gl_compatibility renderer (the one that
│                          works on Mac AND in a browser).
│
├── data/                  ── everything you'd want to tune ──
│   ├── palette.gd         The Art Bible as code. Every colour in the
│   │                      game comes from here. Change one constant
│   │                      and the whole world reskins.
│   ├── definitions.gd     Crops, grow times, prices, quests, Old
│   │                      Sprout's dialogue, MATERIALS and RECIPES.
│   │                      Rebalance the entire economy — including
│   │                      what everything costs to craft — here.
│   └── terrain.gd         "How high is the ground at (x, z)?" The
│                          terrain mesh and everything standing on it
│                          ask this same function, so nothing floats.
│                          Also HALF_SIZE (how big the world is) and
│                          HOMESTEADS (whose clearing is where).
│
├── art/                   ── how it looks ──
│   ├── clay.gdshader      The clay look. Three tricks: vertex wobble,
│   │                      surface grain, wrapped light. Read the
│   │                      header comment — it explains each one.
│   ├── clay_alpha.gdshader  Transparent twin (ghost house, portal veil).
│   ├── clay_core.gdshaderinc  Shared guts of both.
│   ├── clay_kit.gd        The sculpting toolkit. TWO generators:
│   │                      superellipsoid (rounded cube ↔ egg ↔ dome)
│   │                      and lathe (spin a silhouette). That's it.
│   └── props.gd           Every object in the game, built from those
│                          two. Houses, trees, the portal, the Sprite.
│
├── autoload/              ── global services ──
│   ├── controls.gd        Key bindings, in readable code.
│   ├── game_state.gd      ★ THE GAME. Every rule lives here.
│   ├── save_manager.gd    JSON save, autosave, save-on-background.
│   └── sfx.gd             Procedural sounds. Drop real .wav files in
│                          assets/sfx/ and they take over automatically.
│
└── scenes/
    ├── main.gd/.tscn      Entry point. Builds the three layers.
    ├── world/world.gd     Terrain, lighting, village, farm, forest.
    ├── world/plot_view.gd One patch of soil and whatever's in it.
    ├── player/player.gd   Movement, camera, interaction, build mode.
    ├── ui/hud.gd          The clay interface.
    └── dev/
        ├── capture.gd     Screenshot harness (see §7).
        └── selftest.gd    Presses every button, checks the result (§6).
```

### The one architectural rule

`GameState` holds every rule. The world and the HUD **never** change
game values — they call methods on GameState and listen to its
signals. Same "server is authority" split as the Roblox TDD.

This is why the art can be replaced wholesale, why the HUD can be
rebuilt for touch, and why a save file written today will still load
after either of those happen.

---

## 3. Your first five changes

Each of these is a real change to the shipped game, in order of
increasing depth. They're how to learn this codebase.

1. **Rebalance.** In `data/definitions.gd`, change carrot `grow` to
   `10.0` and `coins` to `9`. Run. You just did a live-ops tuning pass.
2. **Reskin.** In `data/palette.gd`, change `MOSS` to a dusty blue.
   Run. The whole world changes season. Nothing else needed.
3. **Add a crop.** Copy the `turnip` block in `CROPS`, make a
   "starberry" in Deep Red. It appears in the shop, the seed pouch,
   the planting code, the quests and the save file automatically. Then
   give it a shape: add a case in `Props.crop()`.
4. **Sculpt something.** In `art/props.gd`, add a `well()` function
   using `ClayKit.lathe()` and `ClayKit.slab()`, then place it from
   `world.gd`'s `_build_village()`. This is the whole art pipeline.
5. **Real art.** Make one house in Tripo3D, export .glb, drop it in
   `assets/models/`, and replace the body of `Props.mushroom_house()`
   with a `load(...).instantiate()`. Nothing else in the game notices.

Steps 3 and 4 are good ones to hand to the kids.

**If the kids want to add their own craftable**, point them at
`docs/MAKE_A_THING.md` instead. It's written for them, not for you: two
files, one worked example, and a list of what to try when it doesn't
show up. Adding a craftable is genuinely two edits — a function in
`props.gd` and a row in `definitions.gd` — and the workbench button,
the placement preview, the collision and the save all follow from that
row. `./tools/selftest.sh` builds every recipe, so a typo'd function
name gets caught before anyone spends materials on an invisible
nothing.

---

## 4. Sharing it on GitHub

`docs/GITHUB.md` — what to commit, what to ignore, and how the kids
pull each other's work without stepping on it. Short version:
everything is source except `.godot/` and `.shots/`, and it is all
about 440 KB.

---

## 5. Exporting

**Mac desktop:** Project → Export → macOS. Godot will offer to
download export templates the first time (~1GB, one-off).

**Browser:** Project → Export → Web. The project already uses the
`gl_compatibility` renderer, which is the one that works in WebGL2 —
that choice was made for this reason and shouldn't be changed casually.
Note that a Web export must be served over HTTP, not opened as a
`file://` page; `python3 -m http.server` in the export folder is
enough for testing, and itch.io works out of the box for sharing with
family.

---

## 6. Checking it still works

```bash
./tools/selftest.sh
```

Runs headless in a few seconds. It presses every button the game
has — till, plant, water, harvest, eat, buy, sell, build, save,
reload — and checks what comes back, including the cases that should
politely refuse (planting with no seeds, buying with no coins, a house
on top of a house). Run it before you trust a change.

It fails on any script error, not just a failed assertion. GDScript
prints a runtime error and then *keeps going*, so a game can throw on
every single action while every test still reports green. That is
exactly how a Godot 3 audio call survived into the first build.

---

## 7. Iterating on the look with Claude

```bash
chmod +x tools/shots.sh    # once, ever
./tools/shots.sh
```

Boots the game, sets up a mid-season farm, walks the camera through
eight framings, and drops eight PNGs in `.shots/` — inside the project,
so Claude can read them straight out of the folder without you moving
anything.

`docs/LOOP.md` is the full workflow: one problem per pass, compare the
same shot before and after, revert rather than stack a second fix on a
failed one. That loop is how the current look got made — the first pass
was fogged into milk, the soil looked like bread, and the HUD had
exploded across the screen.

## 7b. Checking it still runs fast

```bash
./tools/bench.sh
```

Prints how many meshes the world builds, how many draw calls a frame
actually costs, and the frame time. Run it before and after anything
that adds scenery, and compare the two on the same machine — the
absolute number means very little, the ratio means everything.

Draw calls are the figure that matters. The `gl_compatibility`
renderer runs out of those before it runs out of anything else, and
unlike frame time it is a property of the scene rather than of your
laptop. Quadrupling the map cost 10% more draw calls; `docs/DECISIONS.md`
has how.

---

## 8. Known limits of this slice (all deliberate)

- Grow times are shortened for playtesting (carrot 45s, radish 25s,
  turnip 70s) against the GDD's 300/180. Restore before ship.
- Fences and the market stall are decoration; only the mushroom house
  is placeable.
- The Root Portal opens at 5 quests instead of the GDD's 10, and opens
  onto nothing — Tendril Valley is the next build.
- Audio is procedural synth blips. Drop real files in `assets/sfx/`
  named `pop / coin / chime / water / munch / deny / portal` and they
  take over with no code change.
- The font is Godot's default. A rounded friendly face (Art Bible §6)
  is a one-line theme change once you pick one.
- No touch controls yet — this build targets Mac and browser.
- **Single player.** The four homesteads are laid out for four
  players and the shared/private split is already drawn on the map,
  but nobody can join yet. Same-house co-op over the local network is
  the next build.
