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
| Programs | 2 |
| External dependencies | 0 |
| Tests | 25, all passing |
| Blocks dug outside the work area | 0 |

## Requirements

- Minecraft with [CC:Tweaked](https://tweaked.cc/) (or ComputerCraft)
- A mining turtle for `flattener`, any turtle for `sweeper`
- A chest placed directly behind the turtle's starting position
- Coal or charcoal in the turtle's inventory — both programs refuel themselves
  and neither will ever dump fuel into the chest
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

---

## Tests

`test/fake_turtle.lua` stubs the CC turtle API over a toy voxel world, so the
programs can be exercised on a workstation without a server. It carries blocks,
loose item entities, and containers, and it models the awkward parts
faithfully — including the CC quirk where `turtle.drop()` with nothing in
front throws your inventory on the floor and reports success.

From the repository root:

```
lua test/flattener_test.lua    # 13 cases
lua test/sweeper_test.lua      # 12 cases
```

Twenty-five cases between them, covering coverage, containment, and the
failure modes that cost real dirt: nothing dug below the start layer, nothing
dug outside the footprint, the chest never mined, fuel never posted into the
chest, nothing scattered on the ground, and a clean halt instead of a livelock
when the chest fills.

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
