--[[
  sweeper_test.lua -- run with:  lua test/sweeper_test.lua   (from repo root)

  The sweeper patrols for ever by design, so every run here is capped with
  sleepLimit = 1: the script is cut loose the moment it settles in for its
  first patrol delay, which is exactly one completed pass.
]]

package.path = "test/?.lua;" .. package.path
local FakeTurtle = require("fake_turtle")

local SCRIPT = "turtles/sweeper.lua"
local AREA   = 10          -- matches WIDTH/LENGTH in the script

local failures, count = {}, 0

local function test(name, fn)
  count = count + 1
  local ok, err = pcall(fn)
  if ok then
    print("  ok   " .. name)
  else
    print("  FAIL " .. name)
    print("       " .. tostring(err))
    failures[#failures + 1] = name
  end
end

local function assertTrue(cond, msg)
  if not cond then error(msg or "assertion failed", 2) end
end

local function assertEq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "values differ") .. ": expected " .. tostring(expected) ..
          ", got " .. tostring(actual), 2)
  end
end

local function chestTotal(chest)
  local n = 0
  for _, s in ipairs(chest.items) do n = n + s.count end
  return n
end

-- A flat plain with the turtle standing on it, a chest behind, and litter
-- lying on every cell of the 10x10. Markers sit well outside the area.
local function buildWorld(opts)
  opts = opts or {}
  local w = FakeTurtle.new({
    fuel       = opts.fuel or 20000,
    opLimit    = 500000,
    sleepLimit = 1,
  })

  -- ground the turtle stands on, extending past the area
  w:fill(-3, 13, -3, 13, -1, -1, "minecraft:grass_block")

  if opts.roof then
    w:fill(0, AREA - 1, 0, AREA - 1, 1, 1, "minecraft:stone")
  end

  -- litter on the turtle's own layer, one item per cell
  local n = 0
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      n = n + 1
      w:dropItem(x, y, 0, opts.distinct and ("minecraft:widget_" .. n)
                                         or "minecraft:dirt", 1)
    end
  end
  w.littered = n

  -- litter outside the 10x10 that must still be there afterwards
  for _, m in ipairs({ { AREA, 5 }, { -2, 5 }, { 5, AREA }, { 5, -2 } }) do
    w:dropItem(m[1], m[2], 0, "minecraft:gold_ingot", 1)
  end

  if not opts.noChest then
    w.chest = w:placeChest(0, -1, 0, opts.chestCap or 128)
  end
  return w
end

local function run(w)
  local ok, err = w:run(SCRIPT)
  assertTrue(ok, "script errored: " .. tostring(err))
  return w
end

print("sweeper")

test("picks up every loose stack inside the 10x10", function()
  local w = run(buildWorld())
  local left = {}
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      if w:itemsAt(x, y, 0) > 0 then left[#left + 1] = x .. "," .. y end
    end
  end
  assertEq(#left, 0, "litter still lying at: " .. table.concat(left, " ", 1, math.min(#left, 8)))
end)

test("delivers the haul to the chest", function()
  local w = run(buildWorld())
  assertEq(w:countInChest(w.chest, "minecraft:dirt"), w.littered, "dirt in the chest")
end)

test("leaves litter outside the 10x10 alone", function()
  local w = run(buildWorld())
  for _, m in ipairs({ { AREA, 5 }, { -2, 5 }, { 5, AREA }, { 5, -2 } }) do
    assertEq(w:itemsAt(m[1], m[2], 0), 1,
             "marker at " .. m[1] .. "," .. m[2] .. " went missing")
  end
end)

test("never scatters items on the ground", function()
  local w = run(buildWorld())
  assertEq(#w.scattered, 0, "items were dropped on the floor")
end)

test("never digs anything", function()
  local w = run(buildWorld())
  assertEq(w.minDigZ, math.huge, "the sweeper mined something at layer " .. tostring(w.minDigZ))
end)

test("empties into the chest partway through and resumes the pass", function()
  -- 100 different items cannot stack, so 16 slots fill several times over
  local w = run(buildWorld({ distinct = true }))
  assertEq(w:looseItemCount(), 4, "only the four outside markers should be left")
  assertEq(chestTotal(w.chest), w.littered, "everything should have reached the chest")
  assertTrue(w:logText():find("returning to chest", 1, true),
             "expected a chest run, got:\n" .. w:logText())
end)

test("halts instead of spinning when the chest fills up", function()
  local w = run(buildWorld({ distinct = true, chestCap = 1 }))
  assertEq(#w.scattered, 0, "items were dropped on the floor")
  assertTrue(w:logText():find("Halting", 1, true),
             "expected a halt notice, got:\n" .. w:logText())
end)

test("holds its haul rather than scattering it when no chest is there", function()
  local w = run(buildWorld({ noChest = true }))
  assertEq(#w.scattered, 0, "items were dropped on the floor")
  assertTrue(w:countInInv("minecraft:dirt") > 0, "expected the dirt to still be aboard")
  assertTrue(w:logText():find("No container behind me", 1, true),
             "expected a missing-chest notice, got:\n" .. w:logText())
end)

test("keeps its fuel instead of posting it into the chest", function()
  local w = buildWorld()
  w:give("minecraft:coal", 8)
  run(w)
  assertEq(w:countInChest(w.chest, "minecraft:coal"), 0, "coal in the chest")
  assertEq(w:countInInv("minecraft:coal"), 8, "coal still aboard")
end)

test("comes home to the start cell facing the way it started", function()
  local w = run(buildWorld())
  assertEq(w.pos.x, 0, "final x")
  assertEq(w.pos.y, 0, "final y")
  assertEq(w.pos.z, 0, "final z")
  assertEq(w.facing, 0, "final facing")
end)

test("warns and keeps sweeping when there is no headroom", function()
  local w = run(buildWorld({ roof = true }))
  assertTrue(w:logText():find("No headroom", 1, true),
             "expected a headroom warning, got:\n" .. w:logText())
  assertTrue(chestTotal(w.chest) > 0, "expected a partial haul at ground level")
  assertEq(#w.scattered, 0, "items were dropped on the floor")
end)

test("finishes a pass on a yard with nothing lying about", function()
  local w = FakeTurtle.new({ fuel = 20000, sleepLimit = 1 })
  w:fill(-3, 13, -3, 13, -1, -1, "minecraft:grass_block")
  local chest = w:placeChest(0, -1, 0, 27)
  run(w)
  assertEq(chestTotal(chest), 0, "nothing should have reached the chest")
  assertTrue(w:logText():find("Pass 1 complete", 1, true),
             "expected a completed pass, got:\n" .. w:logText())
end)

test("posts swept fuel to the chest instead of seizing up on it", function()
  -- A yard littered with coal is ordinary loot for a sweeper. Holding every
  -- scrap of it back as "fuel" fills all 16 slots and bricks the turtle.
  local w = FakeTurtle.new({ fuel = 20000, opLimit = 2000000, sleepLimit = 1 })
  w:fill(-3, 13, -3, 13, -1, -1, "minecraft:grass_block")
  local littered = 0
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      w:dropItem(x, y, 0, "minecraft:coal", 64)
      littered = littered + 64
    end
  end
  local chest = w:placeChest(0, -1, 0, 256)
  run(w)

  assertEq(w:looseItemCount(), 0, "coal left lying about")
  assertTrue(w:countInChest(chest, "minecraft:coal") > 0, "no coal reached the chest")
  assertTrue(w:countInInv("minecraft:coal") > 0, "kept no coal back as fuel")
  assertEq(w:countInChest(chest, "minecraft:coal") + w:countInInv("minecraft:coal"),
           littered, "coal went missing")
  assertTrue(w:logText():find("Pass 1 complete", 1, true),
             "expected a completed pass, got:\n" .. w:logText())
end)

test("leaves the row behind the start edge alone at ground level", function()
  -- With no headroom the sweep drops to ground level and starts using the
  -- forward suck, which reaches a cell OUTSIDE the area -- including the row
  -- the chest sits in.
  local w = FakeTurtle.new({ fuel = 20000, opLimit = 500000, sleepLimit = 1 })
  w:fill(-3, 13, -3, 13, -1, -1, "minecraft:grass_block")
  w:fill(0, AREA - 1, 0, AREA - 1, 1, 1, "minecraft:stone")   -- low roof
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      w:dropItem(x, y, 0, "minecraft:dirt", 1)
    end
  end
  local markers = { { 5, -1 }, { 5, AREA }, { -1, 5 }, { AREA, 5 } }
  for _, m in ipairs(markers) do w:dropItem(m[1], m[2], 0, "minecraft:gold_ingot", 1) end
  w:placeChest(0, -1, 0, 128)
  run(w)

  for _, m in ipairs(markers) do
    assertEq(w:itemsAt(m[1], m[2], 0), 1,
             "marker at " .. m[1] .. "," .. m[2] .. " was vacuumed from outside the area")
  end
end)

test("comes back for litter it had no room for", function()
  -- Twenty non-stacking items per cell means the 16 slots run out PART WAY
  -- through a cell. Whatever is left has to still be there when we return.
  local w = FakeTurtle.new({ fuel = 200000, opLimit = 2000000, sleepLimit = 1 })
  w:fill(-3, 13, -3, 13, -1, -1, "minecraft:grass_block")
  local littered = 0
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      for k = 1, 20 do
        w:dropItem(x, y, 0, string.format("minecraft:widget_%d_%d_%d", x, y, k), 1)
        littered = littered + 1
      end
    end
  end
  local chest = w:placeChest(0, -1, 0, 4096)
  run(w)

  assertEq(w:looseItemCount(), 0, "litter abandoned mid-cell")
  assertEq(chestTotal(chest), littered, "everything should have reached the chest")
end)

-- ---------- self-update ----------

-- The sweeper's source as it sits in this repo, with the version line
-- rewritten, standing in for a release published to the server.
local function published(version)
  local f = assert(io.open(SCRIPT, "r"))
  local src = f:read("*a")
  f:close()
  return (src:gsub('local VERSION%s*=%s*"[%d%.]+"',
                   'local VERSION      = "' .. version .. '"', 1))
end

local function withUpdater(w)
  w:install("lib/updater.lua", "updater.lua")
  local upd = w:loadInstalled("updater.lua")
  return upd.rawUrl(upd.SOURCES["sweeper.lua"])
end

test("runs perfectly well with no updater installed", function()
  local w = run(buildWorld())
  assertEq(#w.requests, 0, "should not have gone looking for the network")
  assertEq(w.reboots, 0, "should not have rebooted")
  assertTrue(w:logText():find("Pass 1 complete", 1, true), "expected a completed pass")
end)

test("checks for a new version at startup and again between passes", function()
  local w = buildWorld()
  local url = withUpdater(w)
  w:serve(url, published("1.0.0"))          -- same version we are running
  run(w)

  assertEq(#w.requests, 2, "expected a check at startup and one between passes")
  assertEq(w.reboots, 0, "nothing newer was published, so no restart")
  assertTrue(w:logText():find("Pass 1 complete", 1, true), "the pass should still finish")
end)

test("installs a new version published between passes and restarts", function()
  local w = buildWorld()
  local url = withUpdater(w)
  local fresh = published("2.0.0")
  -- Current at the startup check, newer by the time the pass is done.
  w:serve(url, function(n) return n == 1 and published("1.0.0") or fresh end)
  run(w)

  assertEq(w.reboots, 1, "expected exactly one restart")
  assertEq(w:readFile("sweeper.lua"), fresh, "the new version should be installed")
  local log = w:logText()
  assertTrue(log:find("Pass 1 complete", 1, true), "the pass must finish before restarting")
  assertTrue(log:find("restarting", 1, true), "expected a restart notice")
  -- The whole point of only updating here: we are home, empty and level.
  assertEq(w.pos.x, 0, "restarted away from home x")
  assertEq(w.pos.y, 0, "restarted away from home y")
  assertEq(w.pos.z, 0, "restarted away from home z")
  assertEq(w.facing, 0, "restarted facing the wrong way")
end)

test("leaves a startup file so a restarted turtle comes back up sweeping", function()
  local w = buildWorld()
  local url = withUpdater(w)
  w:serve(url, published("1.0.0"))
  run(w)

  local startup = w:readFile("startup.lua")
  assertTrue(startup, "expected a startup.lua")
  assertTrue(startup:find("sweeper.lua", 1, true), "it should relaunch the sweeper")
end)

test("carries on sweeping when the update check cannot reach the network", function()
  local w = buildWorld()
  withUpdater(w)                            -- updater present, nothing served
  run(w)

  assertTrue(#w.requests > 0, "it should have tried")
  assertEq(w.reboots, 0, "being offline is not a reason to restart")
  assertEq(chestTotal(w.chest), w.littered, "the pass should have run normally")
end)

test("refuses a broken release and keeps sweeping with the version it has", function()
  local w = buildWorld()
  local url = withUpdater(w)
  w:serve(url, 'local VERSION      = "9.9.9"\nthis is not lua (((')
  run(w)

  assertEq(w.reboots, 0, "must not restart into a program that will not load")
  assertTrue(w:logText():find("Update refused", 1, true), "expected a refusal notice")
  assertEq(chestTotal(w.chest), w.littered, "the pass should have run normally")
end)

print("")
if #failures > 0 then
  print(#failures .. " of " .. count .. " failed")
  os.exit(1)
end
print("all " .. count .. " passed")
