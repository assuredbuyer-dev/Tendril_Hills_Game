# Getting Tendril Hills onto an iPad

Everything here is a one-off except the last section. Budget an
afternoon the first time and about two minutes for every build after.

---

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

1. **Install Xcode** from the App Store. It's large (~10GB) and slow.
   Open it once and let it finish installing components.
2. **Export templates.** In Godot: *Editor → Manage Export
   Templates → Download and Install*. This is a separate ~1GB
   download from Godot itself and is easy to forget.
3. **Sign in.** Xcode → Settings → Accounts → add your Apple ID, the
   one with the paid membership.

---

## 3. Exporting

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

If Godot's export dialog offers a local-network privacy field, set it
there instead so it survives a re-export. Otherwise you'll be
re-adding it in Xcode each time — the docs explain how to link the
Godot folder directly into Xcode so you don't have to re-export at
all.

The first time he taps *Go*, iOS asks permission. He must say yes. If
he says no by accident: Settings → Tendril Hills → Local Network.

---

## 4. How he actually joins

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

## 5. Touch controls

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

## 6. When something goes wrong

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
