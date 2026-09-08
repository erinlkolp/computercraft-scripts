# SipsCo — Autonomous Extraction Unit Programs

**A SipsCo company.** Published by [SipsCo Research & Development](https://dirt.incantationjunction.com/rnd/).
*Premium dirt, engineered to grow.*

---

The two programs that run our extraction units, released as source. One
flattens a pad. One sweeps a face clean. Between them they cover the whole of
what Unit 7 does on the north face, minus the pickaxe.

Both are ComputerCraft / CC:Tweaked turtle programs, written in Lua, with no
dependencies beyond a turtle, a chest, and some coal. A test harness is
included so you can run them without a server, and without a hole.

R&D publishes these because they are not a trade secret. Run them on your own
fleet. We ask only that you tell us what we got wrong.

## At a glance

| | |
|---|---|
| Programs | 2, plus an optional self-update library |
| External dependencies | 0 |
| Tests | 58, all passing |
| Blocks dug outside the work area | 0 |

## Requirements

- Minecraft with [CC:Tweaked](https://tweaked.cc/) (or ComputerCraft)
- A mining turtle for `flattener`, any turtle for `sweeper`
- A chest placed directly behind the turtle's starting position
- Coal or charcoal in the turtle's inventory — both programs refuel themselves
  and hold a stack back as a reserve
- HTTP enabled, only if you want the programs to update themselves. It is on
  by default in CC:Tweaked, and everything works without it
- Lua 5.3+ on your workstation, if you want to run the tests

---

## `turtles/flattener.lua`

Levels a 15x15 area down to the elevation the turtle is started at, hauling
everything it mines back to the chest. Hills, boulders, trees and floating
leaves above that elevation come off. The block the turtle is standing on, and
everything below it, is never touched — holes stay holes.

It works layer by layer rather than column by column: sweep the area at the
start layer, rise one block, sweep it again, repeat until nothing is left
overhead. That costs a little more walking than chasing each column upward,
and it is the only way to catch an overhang the turtle would otherwise stroll
straight underneath.

**Install**

```
wget https://raw.githubusercontent.com/erinlkolp/computercraft-scripts/refs/heads/main/turtles/flattener.lua
```

**Setup**

1. Place the turtle at a corner of the area, standing on the surface, facing
   along the first row. Its own block is cell (0,0).
2. Place a chest directly behind it, on the turtle's own layer. An ender chest
   is recommended; a plain one will fill on a big job, at which point the
   turtle halts rather than scattering the haul.
3. Give it coal or charcoal.
4. Run `flattener`.

**Configuration** — edit the constants at the top of the file.

| Setting | Default | Notes |
|---|---|---|
| `WIDTH` / `LENGTH` | `15` | Area footprint, in blocks |
| `MAX_HEIGHT` | `32` | Never climbs higher than this above the start layer |
| `SCAN_MIN` | `4` | Layers always swept before trusting "nothing above me" |
| `FUEL_MIN` | `200` | Top up below this |
| `FUEL_MARGIN` | `16` | Reserve held on top of the trip home |
| `MAX_STUCK` | `6` | Failed moves before a cell is abandoned |
| `DIG_RETRY` | `8` | Re-digs per block, so a gravel column cannot win |
| `FUEL_KEEP` | `64` | Fuel held back; mined coal beyond that goes in the chest |
| `VERSION` | `1.0.0` | Bump to roll an update out to a fleet |
| `AUTOSTART` | `false` | Set true to keep a `startup.lua`, so a reboot comes back up working |

---

## `turtles/sweeper.lua`

Patrols a 10x10 area on a single layer, vacuuming up loose item drops and
stashing them in the chest. When the inventory fills it runs home, empties,
and resumes exactly where it left off. Then it sleeps an hour and does it
again.

A turtle cannot pick up items sharing its own block, so the sweep is flown one
block above the litter layer and every cell is cleared with `suckDown()`. That
keeps coverage independent of which way the turtle happens to be facing. Under
a low roof it drops to ground level and sweeps sideways instead — partial
coverage, but it does not refuse to work.

**Install**

```
wget https://raw.githubusercontent.com/erinlkolp/computercraft-scripts/refs/heads/main/turtles/sweeper.lua
```

**Setup**

1. Place the turtle at a corner of the area, standing on the surface you want
   swept, facing along the first row. Its own block is cell (0,0).
2. Leave the layer above the area clear if you can.
3. Place a chest directly behind it, on the turtle's own layer.
4. Give it coal or charcoal.
5. Run `sweeper`.

**Configuration** — edit the constants at the top of the file.

| Setting | Default | Notes |
|---|---|---|
| `WIDTH` / `LENGTH` | `10` | Area footprint, in blocks |
| `PATROL_DELAY` | `3600` | Seconds between full passes |
| `SWEEP_ALT` | `1` | Cruising height above the start layer |
| `SUCK_LIMIT` | `64` | Max sucks per cell, so a cell cannot spin forever |
| `CLIMB_LIMIT` | `3` | Blocks it will climb to get over an obstacle |
| `FUEL_MIN` | `200` | Top up below this |
| `FUEL_MARGIN` | `16` | Reserve held on top of the trip home |
| `MAX_STUCK` | `3` | Failed moves before a cell is abandoned |
| `FUEL_KEEP` | `64` | Fuel held back; swept coal beyond that goes in the chest |
| `CELL_RETRY` | `8` | Chest runs made for one heavily littered cell |
| `VERSION` | `1.0.0` | Bump to roll an update out to a fleet |
| `AUTOSTART` | `false` | Set true to keep a `startup.lua`, so a reboot comes back up sweeping |

## Keeping them up to date

Both programs can fetch a newer copy of themselves and restart into it. It is
optional in the way that matters: with no `updater.lua` on the turtle, nothing
happens and the program runs exactly as it always did.

**Install**

```
wget https://raw.githubusercontent.com/erinlkolp/computercraft-scripts/refs/heads/main/lib/updater.lua
```

**How it decides.** Each program carries its version on a line of its own:

```lua
local VERSION      = "1.0.0"
```

The updater fetches the copy on `main`, reads the `VERSION` line out of the
downloaded text, and installs it only if that number is higher — compared
component by component, so `1.10.0` beats `1.9.0` the way string comparison
would not. Bumping that line is what rolls an update out to a fleet.
Everything else you push to `main` — a comment, a typo, an edit to this file
— goes out to nobody.

**When it checks.** Only where stopping is free, because neither program
writes its position to disk:

| | |
|---|---|
| `flattener` | Once at startup, before the first move. A one-shot job has no safe point in the middle. |
| `sweeper` | At startup, and again between passes — parked on (0,0), hold empty, facing the way it started, which is exactly the state a fresh run expects to boot into. |

A turtle that rebooted halfway through a layer would wake up convinced it was
back at the corner, and measure its next 15x15 from wherever it happened to be
standing. That is why there is no mid-job update, and why adding one means
persisting position first.

**What it refuses.** Anything it is not sure of. It says so and carries on
with the version it has:

- a download that does not compile — the realistic shape of a truncated
  response, and the one failure that would otherwise strand a turtle
- a download that compiles but is less than half the size of the file it
  replaces — a truncation that happened to land on a statement boundary
- a copy with no `VERSION` line at all
- no network, no HTTP API, a 404, a timeout

The previous version is kept alongside as `<program>.bak`. There is no
automatic rollback: a startup shim that catches a crash and restores the
backup trades a bricked turtle for a possible reboot loop, which is worse. To
undo an update by hand:

```
updater restore sweeper.lua
```

**Coming back up.** A reboot with no startup file leaves the turtle sitting at
a prompt, which at the bottom of a hole is no better than bricked. So a
program only ever restarts itself when it knows it will come back up running:

| `AUTOSTART` | What happens when an update lands |
|---|---|
| `false` *(default)* | The new version is installed and the turtle carries on with the one it is running. The update takes effect the next time you start the program yourself. Nothing is written to the computer beyond the program and its backup. |
| `true` | The updater keeps a `startup.lua` that relaunches the program, and the turtle restarts into the new version straight away. |

`AUTOSTART` never starts anything on its own initiative — it only relaunches
the program the turtle was already running. It ships off because switching it
on writes a `startup.lua`, and a program should not quietly change how a
computer boots.

When it is on, the updater writes a marker comment into that file and will
only ever overwrite a file carrying it; a `startup.lua` you wrote yourself is
reported and left alone. The side benefit of turning it on is that turtles
then also come back from chunk unloads and server restarts, not just
updates.

**Running it by hand**

```
updater                       check everything installed
updater sweeper.lua           check just the one
updater restore sweeper.lua   put the previous version back
```

---

## Tests

`test/fake_turtle.lua` stubs the CC turtle API over a toy voxel world, so the
programs can be exercised on a workstation without a server. It carries blocks,
loose item entities, and containers, and it models the awkward parts
faithfully — including the CC quirk where `turtle.drop()` with nothing in
front throws your inventory on the floor and reports success.

From the repository root:

```
lua test/flattener_test.lua    # 20 cases
lua test/sweeper_test.lua      # 23 cases
lua test/updater_test.lua      # 15 cases
```

Fifty-eight cases between them, covering coverage, containment, and the failure
modes that cost real dirt: nothing dug below the start layer, nothing dug
outside the footprint, nothing vacuumed from outside it either, the chest never
mined, nothing scattered on the ground, no litter abandoned on a cell the hold
filled up on, a fuel reserve that is a reserve rather than a hoard, and a clean
halt instead of a livelock when the chest fills.

The harness also stubs a small computer around the turtle — an in-memory
filesystem, an `http.get` served from a route table, and an `os.reboot` — so
the self-update path is exercised end to end: a release published between two
sweeper passes is installed and restarted into, from (0,0) with an empty hold,
and a truncated one is refused while the turtle carries on working.

The sweeper patrols for ever by design, so its suite caps each run with the
harness's `sleepLimit`: the script is cut loose the moment it settles in for
its first patrol delay, which is exactly one completed pass.

## Licence

MIT. See [LICENSE](LICENSE). Run them on your own fleet.

## Contributing

Bug reports and pull requests are welcome at
[erinlkolp/computercraft-scripts](https://github.com/erinlkolp/computercraft-scripts).
Please run the test suite before opening a pull request, and add a case for
anything that lost you a stack.

## Contact

| | |
|---|---|
| General | hello@dirt.incantationjunction.com |
| Bulk orders | orders@dirt.incantationjunction.com |
| Press | press@dirt.incantationjunction.com |

Wholesale partners can put a formulation request straight to the department.
We will tell you honestly whether it is soil science or a landscaping problem.

---

<sub>**Big Money, Big Women, Big Fun™**</sub>

<sub>© 2026 SipsCo. Source released under the MIT Licence. ComputerCraft and
CC:Tweaked are the work of their respective authors. Minecraft is a trademark
of Mojang Studios; SipsCo is not affiliated with or endorsed by Mojang
Studios.</sub>
