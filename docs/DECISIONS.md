# Decisions behind this build

Short record of the choices that would be expensive to reverse later,
and why they went the way they did. Written 17 Aug 2026.

---

## Godot 3D, not Roblox, not Unreal

**Roblox is out.** The contractor route ended, and Roblox also caps
where this can go — no Steam, no premium pricing, and its art pipeline
fights the clay aesthetic rather than serving it.

**Unreal is out for this title.** It has the highest visual ceiling
and the best clay materials out of the box, but for a solo designer
working with Claude it costs more than it returns: C++/Blueprints,
multi-gigabyte builds, slow iteration, and a genuinely painful mobile
export. The bottleneck on this project is iterations-per-evening, and
Unreal makes each iteration slower. Godot's whole project is text on
disk, which is also what makes it easy for Claude to edit precisely.

**Godot 3D it is** — Steam, Mac, browser, and mobile later, from one
codebase.

## gl_compatibility renderer

Godot's Forward+ renderer looks better on desktop, but browsers can't
run it (it needs WebGPU, which Godot 4.5 doesn't ship). The
`gl_compatibility` renderer runs on both the Mac and WebGL2 in a
browser, from the same project, with no branching.

**Don't change this casually.** It rules out SSAO, SDFGI, volumetric
fog and GPU particles — the look is built to not need them. If browser
support is ever dropped, Forward+ becomes available and the world will
get noticeably richer for free.

## Procedural art instead of placeholder art

Everything is generated at runtime from two mesh functions
(superellipsoid, lathe) and one shader. No image or model files.

The argument for it: the game is fully playable and *good-looking*
before a single asset is commissioned, it costs nothing per object, it
diffs cleanly in Git, and — most importantly — art can be replaced one
object at a time. `Props.mushroom_house()` can become a Tripo3D `.glb`
load next week while everything else stays procedural.

The cost: no hand-sculpted character. That's a real limit and the
right time to spend money.

## One-button farming

Interacting with a plot always does the obvious next thing rather than
requiring the player to select a tool first. Kids find it without
instruction, and it removes the tool-selection UI entirely from the
MVP. Tool *tiers* (Art Bible §4.3) can still exist later as passive
upgrades — bigger watering can waters four plots — without adding a
selection step.

## Timestamps, never countdowns

Crops store the unix time they were watered. Elapsed real time is
recomputed on load, so growth continues while the game is closed and
the save file survives clock changes and version bumps. Carried
forward from the 2D scaffold and the Roblox TDD.

## Portal at 5 quests, not 10

The GDD says 10. In a slice with 6 quests, 10 is unreachable, and a
locked door you can never open is worse than no door. Restore to 10
when the quest board fills out.

## Camera on a SpringArm3D, not flown by hand (17 Aug, pass 2)

The first camera lerped to a fixed offset behind the Sprite, which put
the lens inside the market stall and the big mushroom caps whenever you
walked behind them. It now hangs off a `SpringArm3D` that sweeps a
sphere out from the Sprite's chest and pulls in to the first thing it
hits.

The part worth knowing: props carry an invisible cylinder on **physics
layer 3**, which *nothing* in the game collides with except the camera
arm. So a tall prop can push the lens out of its own geometry without
becoming a wall the Sprite has to walk around. Adding a blocker never
changes how the game plays — see `world.gd:_blocker()`.

Only the pivot is smoothed; the arm resolves instantly. A lens that
eases *into* a wall is worse than one that snaps clear of it.

**The arm is a sensor, not the camera's parent.** Parenting the camera
to a `SpringArm3D` and letting it do the placing has no floor: the
moment the arm's origin is inside any shape it collapses to zero and
you spend the next ten seconds looking at the back of the Sprite's
head. That is exactly what happened near the treeline. So the arm now
only reports `get_hit_length()`, and `player.gd:_place_camera()` puts
the camera along it, clamped to `CAM_MIN_LENGTH` (6.2m) and eased
asymmetrically — instant on the way in, slow on the way out, because
being shoved out of a wall should be invisible and drifting back should
not punch the frame every time you brush a bush.

That floor is also what makes generous blockers safe. Trees carry them
too: without blockers the canopy sat in front of the Sprite, with
blockers and no floor the lens hit his head, and with both the camera
simply rides in to 6.2m near the woods and back out after.

## Hunger rebalanced 6s → 22s, and turned into a bonus (17 Aug, pass 2)

At 1 point per 6 seconds a full belly emptied in 10 minutes. A carrot
restores 20 points = 200 seconds of belly, but at the GDD's shipping
grow time it takes 300 seconds to produce. **The loop was negative
sum** — you could farm perfectly and still starve, and it would only
have shown up after restoring the real timers, long after anyone would
think to look at hunger.

At 22 seconds a carrot buys 440 seconds for 300 seconds of growing, so
one plot sustains you and every plot after it is surplus to sell.
Radish is deliberately the tightest crop (220s bought for 180s grown):
the cheap seed is a stopgap, not a living.

The second half matters more than the number. Hunger no longer punishes
anything — there is no death, no penalty at zero. Instead a full belly
pays: above 70 you walk 12% faster and have a 25% chance of pulling up
two crops. Same mechanic, inverted. A seven-year-old who wanders off to
look at the portal for ten minutes should not come back to a
punishment.

## Sound fails silent, always (17 Aug, pass 3)

The first build crashed on the first action that made a noise:
`sfx.gd` was carried over from the 2D scaffold and still called
`can_push_frame()`, which is Godot 3's API and does not exist in
Godot 4. Every `Sfx.play()` threw.

Two rules came out of it:

1. **Audio can never take gameplay down.** Every entry point in
   `sfx.gd` is guarded and fails silent. No audio device, a busy
   buffer, a playback object that never materialises — the game goes
   quiet and keeps running. A cozy farming game is playable without a
   carrot pop; it is not playable if a missing sound card throws on
   the first keypress.
2. **The playback object is acquired lazily, not in `_ready()`.**
   `get_stream_playback()` can legitimately return null immediately
   after `play()`, and how long it takes varies by platform. Caching
   it once at startup means a slow audio device permanently silences
   the game.

Worth noting how this hid for so long: the sandbox Claude tests in has
no sound card, so `get_stream_playback()` returned null, the null
guard fired, and the broken line was never reached. The bug was only
reachable on hardware that actually works. Any code path that depends
on a device the test machine lacks needs deliberate exercising —
`tools/selftest.sh` now fires every sound in the game on purpose.

## Jump — and Space stops being an interact key (18 Aug, pass 4)

Added because AJ's son asked for it, which is the right reason.

**Space moved off interact.** It used to be a third way to press "do
the thing" alongside E and Enter. Every kid who has played anything
expects Space to jump, and a key that both tills soil and hops in the
same frame is worse than either. Interact is E and Enter now, and
`tools/selftest.sh` asserts Space belongs to jump alone so nobody
quietly re-adds it.

**The height ceiling is deliberate.** 9.0 launch against gravity 24
clears about 1.7m — enough to hop a rock, a fence post, or a
toadstool, not enough to land on a mushroom house roof. There is
nothing built up there yet, and a player who can reach a place the
game has not finished will find the seams. Raise it when roofs are
worth standing on.

**Coyote time (0.12s) and jump buffering (0.14s).** Both are invisible
when they work: you can still jump for a moment after walking off a
ledge, and a press that lands just before you touch down still fires.
Without them a jump feels broken to a child long before they could
tell you why.

Belly bonus applies, damped to 60%. Jump height scales with the
*square* of launch velocity, so handing the 12% speed bonus straight
to the jump would have made a well-fed Sprite jump 25% higher — a much
louder difference than intended.

## Mushroom spots go through one function (18 Aug, pass 4)

Also AJ's son: the scattered toadstools had bare caps. They were the
most numerous mushroom in the game and the only ones without spots,
because house caps got hand-placed spots and the little ones got
skipped.

Every mushroom now calls `Props.cap_spots()`, which walks the dome's
actual curve rather than guessing positions near it, and takes a seed
so no two are stamped identically. One function means the species
stays consistent as more mushrooms get added.

The spots are CREAM (#F5EFE0), not white. Art Bible §3.1 — pure white
punches a hole in a warm palette, and next to it every other colour
reads as dirty.

## Solid props, and what stays walk-through (18 Aug, pass 5)

Feedback: the Sprite walked through everything. Now he does not — but
"make it all solid" would have been the wrong fix, so the rule is:

**Solid if it is taller than a knee.** Trees, mushroom houses, the
landmark, fence posts, the stall, the workbench, the quest board, the
trough, Old Sprout.

**Not solid, deliberately:**
- *The Root Portal.* It is an archway. Walking under it is the point,
  and it is the one thing in the world that has to stay passable for
  the update where it opens.
- *Toadstools and pebbles.* They are pickups now. Ankle-height scenery
  you snag on is miserable, and you can already hop over them.
- *Tree canopies.* Only the trunk is solid. The canopy keeps its
  camera-only blocker, so foliage pushes the lens without becoming an
  invisible wall six metres from the trunk.

That last one is why the two-layer split from pass 2 was worth
building. `world.gd:_solid()` puts a body on layer 1 (Sprite + camera);
`_blocker()` puts one on layer 3 (camera only). A tree gets both, at
different sizes.

`tools/selftest.sh` raycasts these — solid things must block, the
portal must not, canopies must not. Collision is invisible in a
screenshot; it needed a real test.

## Gathering and crafting, and why building stopped costing coins (18 Aug, pass 5)

Feedback: pick up small mushrooms and rocks, craft with them.

**Materials replace coins for building.** Coins come from farming and
buy seeds; materials come from walking around and build things. Two
currencies with clean, separate jobs. Before this the whole world
outside the farm fence was scenery — pretty, and pointless. Now the
meadow is the reason to leave.

This *is* a real economy change: the mushroom house used to cost 120
coins and now costs 10 toadstools, 8 branches and 6 stones. To put the
old cost back, add a `coins` key to a recipe in `definitions.gd`. One
file, no logic changes.

**Everything regrows.** Always, on a timestamp, like crops — so the
meadow refills while the game is closed. A cozy world that can be
stripped bare and never recovers is a world you stop wanting to walk
around in.

**Pickup ids come from their own counter, not the loop index.** The
scatter loop skips positions it does not like, so its index would
shift the moment the scatter rules changed, and every id in an
existing save would start pointing at a different bush. The counter
only advances when a pickup is actually created.

**Placement refuses with a reason, not a buzz.** `placement_problem()`
returns a sentence — "Stand back a little", "Too close to what you
already built" — because a seven-year-old told only "no" learns
nothing. It also refuses to build on top of the Sprite, which is the
one placement that could genuinely trap a player now that buildings
are solid.

**Save format went to v2**, with a migration: v1 stored a bare
`houses` list, v2 stores everything you build in one `placed` list
tagged by recipe. Old villages carry across. `selftest.sh` loads a
hand-written v1 save and checks the house survives.

## One registry for craftables, because the kids are building now (19 Aug, pass 6)

AJ's kids have Godot on their laptops and want to contribute. The
blocker was never ideas — it was that adding one craftable meant
editing four files: a recipe, a Props function, a case in
`world.gd:_rebuild_placed()`, and another case in
`player.gd:_spawn_ghost()`. Miss the last one and your thing has no
placement preview, which looks like the game is broken.

Now the recipe row names its own sculptor (`"build": "lantern"`) and
both the world and the ghost resolve it through `Props.build()`. Adding
a craftable is a function in `props.gd` and a row in `definitions.gd`.
Collision, camera blocking, clearance, cost and the workbench button
all come off that row.

Two special cases survive on purpose — the house picks a cap colour and
the hive swaps its look when full, so both need a value passed in.
Eight cases down to two, and neither is on the path a kid takes.

`Props.build()` needs a live instance to `call()` a static function;
`Props.call(...)` on the class itself does not compile. Hence the
cached `_instance`.

`selftest.sh` now builds every recipe and asserts it produces a
non-empty node. A typo in `"build"` used to mean spending materials to
place an invisible nothing; now it fails a test in three seconds.

## Placeables that pay you back (19 Aug, pass 6)

A decoration you put down once and never think about again is a weak
reward, so two of the new craftables do something:

**Scarecrow** — crops within 7m grow 50% faster, capped at +100% so a
field of forty scarecrows is not a cheat. The bonus is **baked into
the plot when you water it**, not recomputed. Growth runs off stored
timestamps, so recomputing would mean moving a scarecrow could rewind
a crop that was nearly ripe.

**Bee hive** — fills over four minutes and hands you honey. Honey is
the first food you cannot plant: `plantable: false` in `CROPS` keeps it
out of the seed pouch, the shop and the planting code while it still
eats and sells like anything else. Worth more than any crop, because
the hive costs materials up front and then asks you to come back.

Both use the same stored-timestamp trick as crops and gathering, so
both keep working while the game is closed.

---

## Open questions worth deciding soon

1. **Does the Sprite need a hand-sculpted model?** The procedural one
   is charming, but it's the single object players look at most. This
   is the first place real art money is worth spending.
2. **Touch controls.** The 2D scaffold was portrait mobile; this is
   landscape desktop. Mobile needs a different input scheme (tap to
   move, tap to interact) — a fork in the design, not a port.
3. **Steam or itch first?** itch.io hosts the Web export free and is
   the fastest way to put a link in front of friends and family. Steam
   is $100 and a bigger commitment; worth doing after the loop has
   survived contact with a few real kids.
4. **How much does the world need to grow?** The current diorama is
   ~68 metres across. Tendril Valley could be a second area in the
   same scene rather than a separate load — cheaper, and the portal
   walk-through would be seamless.

---

## Four times the land, with somewhere to go in it

*Added 21 Aug 2026, when the kids asked for the open land to be
three or four times bigger.*

`Terrain.HALF_SIZE` went from 34 to 68 — twice as wide, so four
times the area. The straightforward version of that request is a
bigger square with four times as much scenery in it, and it is
worse than what it replaces: the same walk, longer. A map is not
made bigger by adding metres, it is made bigger by adding
destinations.

So the new land is not filler. It has:

- **Four homestead clearings**, on the diagonals, one per player.
  Flat, buildable, ringed with stones, named on a signpost, each
  with its own patch of soil. The village in the middle stays
  shared — Old Sprout, the stall, the workbench, the quest board
  and the portal belong to everyone.
- **Four resource pockets**, on the axes between the homesteads.
  Each is generous with one material and stingy with the rest, so
  "I need stone" has an answer that is a direction.

They alternate, so walking the ring goes clearing, pocket,
clearing, pocket. That is the whole layout, and it lives in two
lists: `Terrain.HOMESTEADS` and `World.POCKETS`. Add a fifth
homestead and a fifth clearing appears, terrain flattening and
soil grid and signpost and all, with no other edit.

**The homesteads are also the multiplayer layout**, decided
before the networking exists so the networking does not have to
argue with the map later.

### What the size actually cost

Measured, not guessed — `./tools/bench.sh` was written for this
change and is worth running before and after anything that adds
scenery:

| | old map | new map |
|---|---|---|
| land | 4,624 m² | 18,496 m² |
| mesh instances built | 2,968 | 5,727 |
| **draw calls per frame** | **1,927** | **2,111** |

Four times the land for 10% more work per frame. Three things
did that:

1. **Distance culling** (`World._fade`). Scenery stops being
   drawn past a set range — 72 m for trees, 44 m for ankle-height
   clutter. Hard cutoff, no fade, because fading needs
   transparency and the clay shader is deliberately opaque. Fog
   hides the cutoff, which means `fog_density` and those two
   distances are really one setting written in three places.
2. **The shadow distance came down**, 70 m → 58 m. Every object
   inside that radius is drawn a second time into the shadow map,
   which makes it the most expensive single number in
   `_build_environment`. By 58 m the fog has taken most of the
   contrast out of a shadow anyway.
3. **The forest ring scales with circumference, not area.** It is
   a border. A border twice as far out needs twice as many trees,
   not four times as many. Only the open-field scatter scales
   with area, because that is the one that is actually a field.

### Terrain resolution is a resolution, not a size

`World.TERRAIN_RES` went 84 → 168 alongside `HALF_SIZE`. It has
to move with the map or the ground goes visibly blocky; at 168
across 136 m the quads are ~0.8 m, the same as they always were.

### Plot indices are append-only

`GameState.plots` is a flat array and saves store plots **by
index**. The shared farm keeps indices 0..19 forever and the
homestead grids are appended after it. Insert a plot anywhere
earlier and every existing save wakes up with its crops in
somebody else's field. `_test_homesteads` in the self-test guards
this.

### What did NOT change

The village, the farm, the portal, spawn, and the whole first
half-hour of the game are exactly where they were. A kid who has
been playing this all week walks out of the meadow into the same
scene. Everything new is somewhere they have not been yet.
