# Playing together

Same house, same wifi, up to eight of you. Mac only — see the last
section for why.

---

## For the kids: how to play together

**One person hosts.** Whoever's laptop is "home" for Tendril Hills
opens the game, types their name, and clicks **Host Tendril Hills**.

**Everyone else joins.** Open the game, type your name, and your
brother's or sister's game appears in the list at the bottom. Click
it. That's it — there is no address to type and nothing to set up.

**Claim a clearing.** Walk out to a corner of the map until you find
a signpost with a name on it. If nobody owns it, press **E** and it's
yours. Your name goes on the sign, the grass turns your colour, and
you spawn there next time.

**What's yours and what's everyone's:**

| | who it belongs to |
|---|---|
| Your coins, seeds, basket, pouch, belly | **only you** |
| Your clearing's soil | you plant it, you pull it up |
| The big farm to the east | everybody |
| Toadstools, stones, branches | first one there gets it |
| Houses, lanterns, fences you build | everybody can see them |
| Old Sprout, the stall, the workbench, the portal | everybody |

Anyone can **water** anyone's crops, anywhere. Helping is always
allowed. But only you can harvest from your own clearing, so nobody
can pull up your turnips.

### If something goes wrong

**"Looking... (nobody is hosting yet)"** — the host hasn't clicked
Host yet, or they're on a different wifi. Both machines have to be on
the same network. Guest networks often can't see each other.

**"The host closed the game."** — they quit. You drop back to your
own single-player world and nothing is lost; their world is safe on
their machine.

**Your clearing isn't yours any more.** — ownership is stored by
name, so if you typed it differently (`Sam` vs `sam`) the game thinks
you're someone new. Retype it exactly and it comes back. The game
remembers your name between sessions so this shouldn't happen twice.

---

## For AJ: how it actually works

### The one rule

> **The host owns the world. Every player owns their own pockets.**

Shared, and only the host may change it:

- `plots` — every patch of soil, everywhere
- `gathered` — which pickups are picked, and when they come back
- `placed` — everything anyone has built
- `homestead_owner` — who claimed which clearing

Private, never sent anywhere:

- coins, seeds, larder, materials, build bag, hunger, quests,
  onboarding, portal progress

That split is why this was an evening's work rather than a rewrite,
and it's a direct payoff from the day-one decision that **GameState
holds every rule** while the world and HUD only listen. GameState
became the host's authority almost unchanged. If the rules had been
scattered across `world.gd` and `hud.gd`, every one of them would
have needed finding and moving first.

### Three kinds of function

Every networked function in `game_state.gd` is one of three things,
and the prefix tells you which:

- `request_*` — runs on **your** machine. Asks the host, or just does
  it if you *are* the host.
- `_host_*` — runs on the **host** only. Decides, changes the world,
  tells everyone. This is where the rules live.
- `_set_*` / `_apply_*` — runs on **everyone**. Carries out what the
  host said. Never decides anything.

A guest never writes to shared state directly. It asks, the host
rules on it, and the answer comes back to everybody.

### Why actions return "personal effects"

Tilling a plot is shared. The seed it costs is not — and the host
cannot see your pouch. So the actor sends what it has
(`{seed, seed_n, well_fed}`), the host decides what happens to the
world, and it replies with what the actor should do to its own
basket: `{"spend_seed": "carrot"}`, `{"gain_crop": "turnip",
"gain_n": 2}`. `_apply_personal()` carries that out on the actor's
machine only.

This is also why harvesting somebody else's crop fails cleanly: the
host simply doesn't send back a `gain_crop`.

### Finding the host without an IP address

A seven-year-old cannot be asked for `192.168.1.47`, so they never
see one. The host shouts a small JSON packet onto the local network
once a second (UDP broadcast, port 27016). Every other copy listens
and turns each name it hears into a button. Hosts that go quiet for
four seconds drop off the list.

Broadcast doesn't leave the house — routers don't forward it — so
this is invisible to the internet and needs no ports opened.

### There is no anti-cheat, deliberately

A guest is trusted about its own pockets. It could lie about how many
seeds it has. This is four siblings on one wifi; the failure we're
designing against is confusion, not fraud, and every line spent on
validation here would be a line not spent on the game.

### Save files

The **host's** save is the world. Guests keep their own save for
their own pockets, and joining somebody's world never touches it.

This is the one real constraint of the design: Tendril Hills exists
when the host machine is running it. Choose the host once and keep it
— if different machines host on different days, you get diverging
worlds with no way to merge them.

`player_name.txt` sits beside the save and holds the name, because
homestead ownership is keyed by name rather than by network id. Ids
are handed out fresh every session; a kid expects to walk back into
the same clearing tomorrow.

### Testing it

```bash
./tools/nettest.sh
```

Starts a real host and a real guest as two processes with separate
save directories, and makes the **guest** prove things about the
**host's** world. That indirection is the point: a guest's plot only
changes when the host broadcasts it, so "the guest can see the soil
is tilled" proves the request crossed a real socket, the host applied
its own rules, and the result came back.

`./tools/selftest.sh` cannot catch a networking bug — running on one
machine, every request short-circuits to "I have authority, just do
it". Both run in CI on every push.

Discovery is *reported* by the network test but not asserted, because
whether a UDP broadcast returns to you depends on the network, and a
CI runner is not a living room. Failing builds over that would teach
everyone to ignore red X's.

### Why no browser multiplayer

ENet is UDP, and a browser can't open a UDP socket. The web export
still builds and still works — it just runs single-player. Making it
multiplayer would mean WebSockets or WebRTC plus a signalling server,
which is a lot of machinery for a build nobody in this house uses.

### What isn't done yet

- **Quests and the portal are per-player.** Everyone gets their own
  onboarding and their own portal countdown. Shared quests would need
  a decision about what "we did it" means with four people.
- **No chat.** They're in the same room.
- **No player collision.** You walk through each other. Solid players
  push each other off cliffs, and that is a different game.
- **The host can't hand over.** If the host quits, everyone drops to
  single-player until it comes back.

---

## iPads

They can play. Two things are different, and one of them is Apple's
decision rather than a choice made here.

**They join by number, not from the list.** iOS requires the
`com.apple.developer.networking.multicast` restricted entitlement to
send *or receive* a UDP broadcast, and it must be applied for. That
broadcast is what fills the host list, so an iPad cannot see it —
however the code is written. Instead the host displays a two- or
three-digit join number and the iPad types it. It's the last part of
the host's address; the iPad glues it onto its own, which works
because a house is one network. The full address is shown too, for
the rare setup where that assumption breaks.

Ordinary connecting is fine — a direct connection to a known address
is normal traffic. iOS shows a one-time "allow local network access"
prompt, which must be accepted or the join silently fails.

**Touch controls appear automatically**, and only on touch devices.
The buttons synthesise real input actions
(`Input.action_press`/`action_release`), so every
`Input.is_action_pressed` already in the game works on a tablet with
no second code path. Only the thumbstick needs a back channel
(`Controls.touch_move`), because an action is on or off and analog
walking is the entire point of a stick.

Getting a build onto an iPad — Xcode, signing, the Info.plist entry
that makes the permission prompt appear — is in `docs/IPAD.md`.
