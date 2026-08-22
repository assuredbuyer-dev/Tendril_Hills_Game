# Getting Tendril Hills onto an iPad

Everything here is a one-off except the last section. Budget an
afternoon the first time and about two minutes for every build after.

---

> You've shipped to Apple before, so this skips the App Store Connect
> basics and covers the parts that are specific to **Godot** and to
> **this project**. The Godot-side gotchas are section 3 onward.

## 1. The account question, settled

**Your son does not need a developer account.** Your paid membership
signs the app for *any* device you put it on. There are two ways to
get it onto his iPad:

**Cable, via Xcode.** Plug his iPad into your Mac once. Xcode offers
to register it as a development device; say yes. Build, and the app
installs and stays working for a year. Simple, and the right choice
for the first attempt because it fails loudly when something is
wrong.

**Over the air, via TestFlight.** Upload a build from Xcode, invite
his Apple ID as a tester, and he installs the TestFlight app and taps
Install. No cable, and future updates arrive on his iPad without you
chasing him around the house. Builds expire after 90 days, and the
first external build needs a short beta review from Apple.

Start with the cable. Move to TestFlight once you're pushing updates
regularly, because that's when walking to his room with a cable gets
old.

A free Apple ID would also work, but apps signed with one **stop
working after seven days**. With more than one device that becomes a
weekly ritual, and the game is dead every time a kid picks it up
unprompted. You have the paid account — use it.

---

## 2. One-off setup on your Mac

1. **Xcode**, if it isn't already there. Open it once so it finishes
   installing components.
2. **Godot's iOS export templates** — *Editor → Manage Export
   Templates → Download and Install*. This is the step people miss:
   it's a separate ~1GB download from Godot itself, it is **not**
   included with the editor, and without it the iOS preset shows a
   red "export templates not found" and nothing else explains why.
   The version must match your Godot exactly — 4.7.1 templates for a
   4.7.1 editor.
3. **Xcode → Settings → Accounts** → your paid Apple ID.

---

## 3. What's already done for you

Three things that would otherwise bite, already in the repo:

**The app icon.** `icon_1024.png` in the project root — 1024×1024,
RGB with no alpha, which is what Apple requires. Point the iOS
preset's App Store icon field at it and Godot generates every other
size.

It is the **only image file in this project**, and it is generated
rather than drawn: `./tools/icon.sh` renders it from the same mesh
generators and the same shader as the game. Change `data/palette.gd`,
re-run it, and the icon follows the game instead of drifting away
from it.

**Landscape is locked.** `display/window/handheld/orientation` is set
to `sensor_landscape` in `project.godot`. The camera rig and HUD are
both built wide and the game is genuinely unplayable in portrait;
this lets him hold the iPad either way up but never turns it
sideways.

**The mobile renderer is already right.**
`renderer/rendering_method.mobile="gl_compatibility"` — the same
choice that makes the browser build work. Don't switch this to
Forward+ for iOS; the whole art style is built to not need what
Forward+ adds.

---

## 4. Exporting

In Godot: *Project → Export → Add… → iOS*, then fill in:

| Field | What to put |
|---|---|
| App Store Team ID | from developer.apple.com → Membership |
| Bundle Identifier | e.g. `com.tendrelstudios.tendrilhills` |

Both are **required** — Godot refuses to export with either blank,
and the error doesn't say which one it means.

Export. You get an Xcode project, not a finished app. Open the
`.xcodeproj`, pick your son's iPad from the device list at the top,
and press ▶.

### The one setting that isn't obvious

iOS blocks an app from touching the local network until the user
agrees, and it will only ask if the app explains why. Without this,
**the iPad will silently fail to join and there will be no error
message.**

Add to the Info.plist in the generated Xcode project:

```
Key:   NSLocalNetworkUsageDescription
Value: Tendril Hills uses your local network so you can play
       together with people in this house.
```

**This is now automatic** — `addons/ios_plist` adds the key on every
iOS export, because Godot 4.7's exporter has privacy fields for
camera, microphone and photo library but none for local network, and
adding it by hand after every export is one forgotten step away from
a silent failure.

You should see `[ios_plist] added NSLocalNetworkUsageDescription` in
Godot's output panel when you export. If you don't, the plugin isn't
enabled: Project → Project Settings → Plugins → tick **iOS Info.plist
extras**, and check the key by hand in Xcode for that build.

The first time he taps *Go*, iOS asks permission. He must say yes. If
he says no by accident: Settings → Tendril Hills → Local Network.

---

## 5. How he actually joins

**The host list does not work on iPad, and cannot be made to.**

Apple requires the `com.apple.developer.networking.multicast`
entitlement to send *or receive* a UDP broadcast — that's the thing
that makes your name appear in his list — and it's a restricted
entitlement you have to apply to Apple for. Bonjour doesn't get
around it either. So the iPad gets in by **join number** instead:

1. Someone on a MacBook clicks **Host Tendril Hills**.
2. The host's screen shows a number — usually two or three digits.
3. On the iPad, type that number in the box at the bottom of the join
   screen and tap **Go**.

The number is the last part of the host's network address. His iPad
glues it onto its own, which works because everything in one house is
on the same network. If it ever doesn't — a mesh router putting some
devices on a different range — the box also accepts the full address,
which the host shows underneath the number.

The MacBooks keep using the click-a-name list. Both paths land in the
same place.

---

## 6. Touch controls

They appear automatically on a touch device and never on a MacBook.
Left thumb walks, **E** does the obvious thing, **Jump** jumps,
**< >** swing the camera, and **Eat / Seed / Build** are the 1/2/3
keys. The help card rewrites itself for touch — tap it to hide it.

To see the tablet layout on your Mac without an iPad:

```bash
./tools/shots.sh --touch
```

or run the game with `-- --touch`.

---

---

## 7. TestFlight, when you want it

Worth doing the cable route first — it fails loudly and locally, and
you want to know the game runs before you involve Apple's servers.

Once it does, TestFlight is the same archive with a different
destination, and the only Godot-specific notes are:

- **Bump `application/version` and `application/short_version` in the
  iOS export preset** before each upload. App Store Connect rejects a
  duplicate build number, and Godot does not increment it for you —
  this is the single most common way a Godot TestFlight upload fails
  after the first one.
- **Export as Release, not Debug.** A debug export embeds the remote
  debugger and will be rejected.
- **Strip the dev scenes.** Set the iOS preset's exclude filter to
  `scenes/dev/*`, the same as the macOS preset already does. The
  self-test, the screenshot harness and the icon maker have no
  business in a shipped build.

Everything after that is the App Store Connect flow you already know.

---

---

## 8. Testing on an old iPad first

Sensible — but an old iPad can mislead you in two directions, so
know both before you draw conclusions from it.

**It must be arm64.** Godot 4 builds arm64 only; there is no armv7.
In practice that means iPad Air (1st gen), iPad mini 2, or iPad
5th generation and newer. Plug it in and pick it as the destination
in Xcode: if it is too old, Xcode greys it out and says so
immediately. Thirty seconds, not an afternoon.

**⚠ The discovery list may work on an old iPad and NOT on a new
one.** Apple's own note on the local-network rules says the
restrictions are "not enforced on iOS 14 and 15" and "should be
correctly enforced by iOS 16 and later."

So if your old iPad runs iOS 15 or earlier, it may well see the host
list — and your son's newer iPad will not, no matter what you do.
Do not test with the list and conclude it works.

**Test with the join number.** That is the path that works on every
device, and it is the one he will actually use. If the number works
on the old iPad, it will work on his.

**Judging whether it is fast enough.** Tap the **?** button
(bottom row) to bring up the controls card. At the foot of it is a
live readout: frames per second, draw calls, and how many people are
playing. There is no console on an iPad and no way to pass it a
flag, so this is the only way to get a real answer from the device.

Roughly: 60 fps is fine, 30 is playable for a cosy game, below 20 is
not. If it struggles, the numbers to change are `TREE_FADE` and
`CLUTTER_FADE` in `scenes/world/world.gd` and the shadow distance in
`_build_environment` — `docs/DECISIONS.md` explains what each costs.
An old iPad may simply not have the fill rate, in which case that
tells you something useful about your son's iPad too, depending on
which is newer.

---

## 9. When something goes wrong

**The iPad joins and immediately drops.** Almost always the local
network permission. Settings → Tendril Hills → Local Network.

**"That did not look like a join number."** He typed something that
isn't a number or a full address. Get the number off the host's
screen again.

**It connects but nothing moves.** Different wifi networks — guest
networks in particular can't see each other. Both devices must be on
the same one. 5GHz and 2.4GHz bands of the *same* network are fine.

**The app stopped working after a week.** It was signed with a free
Apple ID, not your paid one. Check the signing team in Xcode.

**Everything is tiny, or the buttons are off-screen.** Tell me the
iPad model and I'll fix the layout — the HUD is laid out in code and
sizes are one file.
