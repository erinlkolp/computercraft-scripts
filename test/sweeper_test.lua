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

print("")
if #failures > 0 then
  print(#failures .. " of " .. count .. " failed")
  os.exit(1)
end
print("all " .. count .. " passed")
