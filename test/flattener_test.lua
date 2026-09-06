--[[
  flattener_test.lua -- run with:  lua test/flattener_test.lua   (from repo root)
]]

package.path = "test/?.lua;" .. package.path
local FakeTurtle = require("fake_turtle")

local SCRIPT = "turtles/flattener.lua"
local AREA   = 15

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

-- A hill sitting on a grass plain, with a tree, a boulder poking one block
-- above the plain, and marker blocks just outside the work area.
local function buildWorld(opts)
  opts = opts or {}
  local w = FakeTurtle.new({ fuel = opts.fuel or 20000, opLimit = 500000 })

  -- ground the turtle stands on, one block below it, extending past the area
  w:fill(-2, 16, -2, 16, -1, -1, "minecraft:grass_block")

  -- a 9x9 hill three blocks proud of the plain, mixed dirt and stone
  for x = 3, 11 do
    for y = 3, 11 do
      for z = 0, 2 do
        w:setBlock(x, y, z, (z == 2) and "minecraft:grass_block" or "minecraft:dirt")
      end
    end
  end
  for x = 5, 8 do
    for y = 5, 8 do
      w:setBlock(x, y, 0, "minecraft:stone")
    end
  end

  -- a tree in the far corner, taller than the hill
  for z = 0, 4 do w:setBlock(13, 13, z, "minecraft:oak_log") end
  w:setBlock(13, 13, 5, "minecraft:oak_leaves")

  -- a lone block on the row the turtle starts in
  w:setBlock(0, 6, 0, "minecraft:dirt")

  -- markers outside the 15x15 that must survive untouched
  w:setBlock(15, 7, 0, "minecraft:stone")
  w:setBlock(7, 15, 0, "minecraft:stone")
  w:setBlock(-1, 7, 0, "minecraft:stone")
  w:setBlock(7, -1, 0, "minecraft:stone")

  w.chest = w:placeChest(0, -1, 0, opts.chestCap or 27)
  return w
end

local function run(w)
  local ok, err = w:run(SCRIPT)
  assertTrue(ok, "script errored: " .. tostring(err))
  return w
end

print("flattener")

test("clears every block at and above the start layer inside the 15x15", function()
  local w = run(buildWorld())
  local left = {}
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      for z = 0, 8 do
        local b = w:getBlock(x, y, z)
        if b then left[#left + 1] = b .. "@" .. x .. "," .. y .. "," .. z end
      end
    end
  end
  assertEq(#left, 0, "blocks still standing: " .. table.concat(left, " ", 1, math.min(#left, 8)))
end)

test("leaves the layer it started on intact", function()
  local w = run(buildWorld())
  local holes = {}
  for x = 0, AREA - 1 do
    for y = 0, AREA - 1 do
      if not w:getBlock(x, y, -1) then holes[#holes + 1] = x .. "," .. y end
    end
  end
  assertEq(#holes, 0, "floor was dug at: " .. table.concat(holes, " ", 1, math.min(#holes, 8)))
end)

-- Stronger than checking the floor survived: nothing may even be aimed at
-- below the start layer, whatever route the turtle takes to get home.
test("never aims a dig below the start layer", function()
  local w = run(buildWorld())
  assertTrue(w.minDigZ >= 0, "dug down to layer " .. tostring(w.minDigZ))
end)

test("leaves blocks outside the 15x15 alone", function()
  local w = run(buildWorld())
  for _, m in ipairs({ { 15, 7 }, { 7, 15 }, { -1, 7 }, { 7, -1 } }) do
    assertEq(w:getBlock(m[1], m[2], 0), "minecraft:stone",
             "marker at " .. m[1] .. "," .. m[2] .. " went missing")
  end
end)

test("does not mine the chest", function()
  local w = run(buildWorld())
  assertEq(w:getBlock(0, -1, 0), "minecraft:chest", "chest block")
end)

test("clears an overhang floating above empty air", function()
  local w = FakeTurtle.new({ fuel = 20000 })
  w:fill(-2, 16, -2, 16, -1, -1, "minecraft:grass_block")
  -- a shelf at height 3 with nothing underneath it; a column scan would walk
  -- straight under this and call the job done
  w:fill(4, 9, 4, 9, 3, 3, "minecraft:stone")
  w:placeChest(0, -1, 0, 27)
  run(w)
  local left = 0
  for x = 4, 9 do
    for y = 4, 9 do
      if w:getBlock(x, y, 3) then left = left + 1 end
    end
  end
  assertEq(left, 0, "overhang blocks still floating")
end)

test("delivers the dirt and the stone to the chest", function()
  local w = run(buildWorld())
  assertTrue(w:countInChest(w.chest, "minecraft:dirt") > 0, "no dirt in the chest")
  assertTrue(w:countInChest(w.chest, "minecraft:cobblestone") > 0, "no cobblestone in the chest")
  assertTrue(w:countInChest(w.chest, "minecraft:oak_log") > 0, "no logs in the chest")
end)

test("never scatters items on the ground", function()
  local w = run(buildWorld())
  assertEq(#w.scattered, 0, "items were dropped on the floor")
end)

test("comes home to the start cell facing the way it started", function()
  local w = run(buildWorld())
  assertEq(w.pos.x, 0, "final x")
  assertEq(w.pos.y, 0, "final y")
  assertEq(w.pos.z, 0, "final z")
  assertEq(w.facing, 0, "final facing")
end)

test("empties into the chest partway through a big job", function()
  local w = buildWorld()
  -- 15x15x6 of solid stone is far more than 16 slots can hold at once
  w:fill(0, AREA - 1, 0, AREA - 1, 0, 5, "minecraft:stone")
  w:setBlock(0, 0, 0, nil)
  run(w)
  assertEq(#w.scattered, 0, "items were dropped on the floor")
  assertTrue(w:countInChest(w.chest, "minecraft:cobblestone") > 1000,
             "expected a big cobblestone haul, got " ..
             w:countInChest(w.chest, "minecraft:cobblestone"))
end)

test("halts instead of spinning when the chest fills up", function()
  local w = buildWorld({ chestCap = 1 })
  w:fill(0, AREA - 1, 0, AREA - 1, 0, 5, "minecraft:stone")
  w:setBlock(0, 0, 0, nil)
  run(w)
  assertEq(#w.scattered, 0, "items were dropped on the floor")
  assertTrue(w:logText():find("Halting", 1, true), "expected a halt notice, got:\n" .. w:logText())
end)

test("holds its haul rather than scattering it when no chest is there", function()
  local w = FakeTurtle.new({ fuel = 20000 })
  w:fill(-2, 16, -2, 16, -1, -1, "minecraft:grass_block")
  w:fill(0, AREA - 1, 0, AREA - 1, 0, 0, "minecraft:dirt")
  w:setBlock(0, 0, 0, nil)
  run(w)
  assertEq(#w.scattered, 0, "items were dropped on the floor")
  assertTrue(w:countInInv("minecraft:dirt") > 0, "expected the dirt to still be aboard")
end)

test("mines nothing on ground that is already flat", function()
  local w = FakeTurtle.new({ fuel = 20000 })
  w:fill(-2, 16, -2, 16, -1, -1, "minecraft:grass_block")
  w:placeChest(0, -1, 0, 27)
  run(w)
  assertTrue(w:logText():find("Mined 0 block(s)", 1, true),
             "expected nothing to be mined, got:\n" .. w:logText())
end)

print("")
if #failures > 0 then
  print(#failures .. " of " .. count .. " failed")
  os.exit(1)
end
print("all " .. count .. " passed")
