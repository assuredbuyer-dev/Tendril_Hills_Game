# Putting Tendril Hills on GitHub

The whole project is **51 files and about 440 KB**. There are no art
binaries, no models, no audio — everything is generated in code — so
this repo is small enough to clone in a second and read end to end.

---

## What goes in

**Everything except four things.** `.gitignore` already handles them:

| Ignored | Why |
|---|---|
| `.godot/` | Godot's cache — the shader cache, imported assets, the class registry. Regenerated on first open, different on every machine, and the single biggest cause of pointless merge conflicts. |
| `.shots/` | Screenshot scratch from `tools/shots.sh`. Always the current build, never history. |
| `export/`, `build/` | Compiled game builds. |
| `.DS_Store` | macOS folder litter. |

Two that people wrongly delete — **keep both**:

- **`*.uid` files.** Godot 4.4+ writes one next to every script. They
  are how Godot tracks a file's identity across renames. Leave them
  out and everyone's Godot invents new ones, which shows up as
  phantom changes in every pull.
- **`icon.svg.import`.** The import *settings*. The imported binary it
  produces lives in `.godot/` and is correctly ignored.

`export_presets.cfg` is committed and is safe here — ours holds no
passwords or signing keys. If you ever turn on codesigning for a Mac
or iOS release, check it again before pushing, because that is where
those credentials would land.

---

## Setting it up

On your Mac, in the `TendrilHills3D` folder:

```bash
cd "/Users/ajsohn/Documents/Developer/Games/Tendril Hills/TendrilHills3D"
git init
git add .
git commit -m "Tendril Hills — first commit"
```

Then make an **empty** repo on github.com (no README, no .gitignore —
you already have both) and:

```bash
git remote add origin https://github.com/YOURNAME/tendril-hills.git
git branch -M main
git push -u origin main
```

Sanity check before that first push:

```bash
git status --short       # should list ~51 files, none of them .godot/
```

If you see `.godot/` in there, the `.gitignore` did not take — make
sure it is in the `TendrilHills3D` folder, not the folder above it.

---

## For the kids

**Use GitHub Desktop, not the terminal.** It is free, it shows changes
as a readable list, and Pull / Commit / Push are three buttons. The
command line is a worse first experience and teaches nothing extra at
this stage.

Their loop is:

1. **Pull** before starting. Every time.
2. Change something. Press ▶. See it.
3. `./tools/selftest.sh` if they touched anything beyond colours.
4. **Commit** with a sentence about what they did.
5. **Push.**

### Your saves are safe

Godot keeps the save file *outside* the project, in
`~/Library/Application Support/Godot/app_userdata/Tendril Hills/`.
Pulling can never wipe anyone's village, and nobody's save gets pushed
over anyone else's. Each kid keeps their own world.

### Two people editing the same file

Everyone adding craftables will be in `props.gd` and `definitions.gd`,
so this *will* happen. Two habits make it almost painless:

- **Add at the end.** New function at the bottom of the craftables
  section; new recipe row at the bottom of `RECIPES`. Git handles two
  people appending in different places far better than two people
  editing the same line.
- **Small and often.** One craftable, one commit, one push. A week of
  work in a single commit is where conflicts get ugly.

If a conflict does happen, GitHub Desktop marks the file and shows both
versions with `<<<<<<<` markers. Usually both people's work should
stay — delete the marker lines, keep both functions. Paste it to Claude
if it looks scary.

---

## Worth knowing before you invite them

GitHub's terms require account holders to be **13 or older**. If any of
your kids are younger, they cannot have their own account. Options:

- They work on your machine under your account (simplest).
- You push for them at the end of a session — they still get the loop
  of change-it, run-it, see-it, which is the part that matters.
- Skip GitHub for the youngest and use a shared folder; add them to the
  repo when they are old enough.

---

## Later, if you want it

- **Branches and pull requests.** A genuinely good thing to teach, but
  after they are comfortable with pull/commit/push. One habit at a time.
- **Run the self-test automatically on every push.** A GitHub Action
  that runs `tools/selftest.sh` in headless Godot would catch a broken
  recipe before anyone else pulls it. Worth doing once there are enough
  people committing that a break would cost someone an evening.
- **Releases.** Export a Mac build or a web build and attach it to a
  GitHub Release, so relatives can play without installing Godot.
