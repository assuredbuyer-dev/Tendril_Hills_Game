# How to add your own craftable

**You need two files. That's it.** Write the shape, then tell the game
it exists. Everything else — the workbench button, the see-through
preview, saving it, the cost, bumping into it — happens on its own.

Try it with something silly first. A giant carrot statue is a perfectly
good first craftable.

---

## Step 1 — sculpt it, in `art/props.gd`

Everything in this game is made from two shapes. That's not a limit,
it's the whole trick:

- **`ClayKit.blob(size, colour, where)`** — an egg. Heads, berries,
  rocks, leaves, bee bodies.
- **`ClayKit.slab(size, colour, where)`** — a rounded box. Tables,
  boards, walls.
- **`ClayKit.stalk(size, colour, where)`** — a rounded pole. Stems,
  posts, handles.
- **`ClayKit.dome(radius, height, colour, where)`** — half a ball.
  Mushroom caps, hats, hills.
- **`ClayKit.lathe(profile, colour, where)`** — spin a shape on a
  pottery wheel. Pots, carrots, tree trunks.

`size` is `Vector3(wide, tall, deep)`. `where` is
`Vector3(left-right, up-down, forward-back)` and `0, 0, 0` is the
ground at the middle of your thing.

Colours live in `data/palette.gd` — use those, don't invent new ones.
`Palette.DEEP_RED`, `Palette.MOSS`, `Palette.WARM_YELLOW`, and so on.
That's what keeps everything looking like the same world.

Add your function at the bottom of the craftables section:

```gdscript
## A birdhouse on a pole.
static func birdhouse() -> Node3D:
	var n := Node3D.new()
	n.name = "Birdhouse"

	# the pole
	n.add_child(ClayKit.stalk(Vector3(0.14, 1.6, 0.14), Palette.EARTH_DARK,
		Vector3(0, 0.8, 0)))

	# the box on top
	n.add_child(ClayKit.slab(Vector3(0.7, 0.6, 0.6), Palette.CREAM,
		Vector3(0, 1.85, 0)))

	# the roof
	n.add_child(ClayKit.dome(0.55, 0.35, Palette.DEEP_RED,
		Vector3(0, 2.15, 0)))

	# the little round door
	n.add_child(ClayKit.blob(Vector3(0.22, 0.22, 0.14), Palette.EARTH_DARK,
		Vector3(0, 1.85, -0.3)))

	# a perch to stand on
	n.add_child(ClayKit.stalk(Vector3(0.06, 0.2, 0.06), Palette.EARTH_DARK,
		Vector3(0, 1.7, -0.36)))

	return n
```

**One rule:** your function has to work when called with no arguments.
If you want a setting, give it a default — `func birdhouse(tall := 1.6)`.

---

## Step 2 — add one row, in `data/definitions.gd`

Find `const RECIPES` and add your thing:

```gdscript
	"birdhouse": {
		"name": "Birdhouse",
		"cost": {"branch": 4, "stone": 1},
		"build": "birdhouse",
		"solid": [0.25, 2.0],
		"space": 1.0,
		"desc": "Somebody might move in.",
	},
```

| What | Means |
|---|---|
| `name` | what the workbench calls it |
| `cost` | what it eats. Only `toadstool`, `stone` and `branch` exist |
| `build` | the **exact name** of your function from step 1 |
| `solid` | `[how wide, how tall]` you bump into. Leave it out for something flat you walk over |
| `block` | same, but only the camera bumps into it. Only for tall things |
| `space` | how much room it needs, and how far you have to stand back |
| `desc` | one line shown under it at the workbench |

**Done.** Press ▶, walk to the workbench, and it's there.

---

## Step 3 — check you didn't break anything

```bash
./tools/selftest.sh
```

It builds every recipe and checks each one makes a real object. If you
typo'd the function name in `build`, this is what tells you — instead
of you spending the materials and placing an invisible nothing.

---

## Things worth knowing

**Start small.** Get a pole and a box on screen, run it, *then* make it
nice. Waiting until it's perfect before you look at it is how you end
up with a mess you can't untangle.

**Steal from what's there.** Open `props.gd` and read `lantern()` or
`planter()`. They're short. Copy one, change the numbers, see what
moves.

**Nothing is precious.** If it looks wrong, change a number and run it
again. The whole game rebuilds itself every time you press play — you
can't damage anything.

**If it doesn't show up:** the name in `"build"` has to match your
function name letter for letter. `birdhouse` is not `birdHouse`.

**If it's floating or buried:** `0` on the up-down axis is the ground.
Something at `Vector3(0, 2, 0)` is two metres in the air.

**If Godot goes red:** read the bottom panel. The line number it names
is usually the line above the real problem — a missing bracket on the
line before. Ask Claude and paste the red text.

---

## Ideas, if you want them

Easy: birdhouse · bench · barrel · stack of crates · mailbox · flag ·
stone lantern · bird bath · haystack · little bridge · picnic blanket

Harder, and worth it: a **well** (there's a hint in README §3) · a
**windmill** whose sails turn · a **fountain** with water · a **market
umbrella** · a **kite** on a string

Something that *does* a thing: look at how the scarecrow speeds up
crops (`game_state.gd`, `growth_speed_at`) or how the bee hive fills
over time (`hive_progress`). Copy that pattern and invent your own.
