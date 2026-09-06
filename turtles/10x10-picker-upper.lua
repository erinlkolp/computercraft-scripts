--[[
  sweeper.lua -- ComputerCraft / CC:Tweaked item sweeper turtle

  Patrols a WIDTH x LENGTH area on a single layer, vacuuming up loose item
  drops. Returns to a chest behind its start position when the inventory
  fills, then resumes exactly where it left off.

  SETUP
    - Place the turtle at a corner of the area, facing along the first row.
    - Place a chest DIRECTLY BEHIND the turtle.
    - The turtle's starting block is cell (0,0) and is included in the sweep.
    - Give it some coal or charcoal; it will refuel itself and will never
      dump fuel into the chest.

  RUN
    sweeper
]]

-- ============================================================
-- CONFIG
-- ============================================================

local WIDTH        = 10    -- columns (sideways, to the turtle's right)
local LENGTH       = 10    -- rows (forward, the way the turtle starts facing)
local PATROL_DELAY = 60    -- seconds to wait between full passes
local FUEL_MIN     = 200   -- refuel when fuel drops below this
local MAX_STUCK    = 3     -- give up on a cell after this many failed moves

local FUEL_ITEMS = {
  ["minecraft:coal"]        = true,
  ["minecraft:charcoal"]    = true,
  ["minecraft:coal_block"]  = true,
  ["minecraft:blaze_rod"]   = true,
}

-- ============================================================
-- STATE
-- ============================================================

-- facing: 0 = start direction (+Y), 1 = right (+X), 2 = back (-Y), 3 = left (-X)
local pos    = { x = 0, y = 0 }
local facing = 0
local alt    = 0   -- how many blocks above the sweep layer we currently are

local DX = { [0] =  0, [1] =  1, [2] =  0, [3] = -1 }
local DY = { [0] =  1, [1] =  0, [2] = -1, [3] =  0 }

-- ============================================================
-- MOVEMENT
-- ============================================================

local function turnRight()
  turtle.turnRight()
  facing = (facing + 1) % 4
end

local function turnLeft()
  turtle.turnLeft()
  facing = (facing + 3) % 4
end

local function faceDir(d)
  local diff = (d - facing) % 4
  if diff == 1 then
    turnRight()
  elseif diff == 2 then
    turnRight(); turnRight()
  elseif diff == 3 then
    turnLeft()
  end
end

-- Raw step that keeps pos in sync.
local function stepForward()
  if turtle.forward() then
    pos.x = pos.x + DX[facing]
    pos.y = pos.y + DY[facing]
    return true
  end
  return false
end

-- Drop back down to the sweep layer if we hopped over something.
local function descend()
  while alt > 0 do
    if turtle.down() then
      alt = alt - 1
    else
      return false   -- sitting on top of an obstruction; keep going anyway
    end
  end
  return true
end

-- Move one block forward. If blocked, try hopping up and over.
local function moveForward()
  if stepForward() then
    descend()
    return true
  end

  -- Obstacle: go around by climbing over it.
  if turtle.up() then
    alt = alt + 1
    if stepForward() then
      descend()
      return true
    end
    if turtle.down() then alt = alt - 1 end
  end

  return false
end

-- Walk to a grid cell, preferring the Y axis then falling back to X.
local function navigateTo(tx, ty)
  local stuck = 0
  while pos.x ~= tx or pos.y ~= ty do
    local moved = false

    if pos.y ~= ty then
      faceDir(pos.y < ty and 0 or 2)
      moved = moveForward()
    end

    if not moved and pos.x ~= tx then
      faceDir(pos.x < tx and 1 or 3)
      moved = moveForward()
    end

    if moved then
      stuck = 0
    else
      stuck = stuck + 1
      if stuck >= MAX_STUCK then
        return false
      end
      os.sleep(0.5)
    end
  end
  descend()
  return true
end

-- ============================================================
-- INVENTORY & FUEL
-- ============================================================

local function freeSlots()
  local n = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then n = n + 1 end
  end
  return n
end

local function refuelIfNeeded()
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return true end
  if level >= FUEL_MIN then return true end

  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and FUEL_ITEMS[item.name] then
      turtle.select(i)
      while turtle.getFuelLevel() < FUEL_MIN and turtle.getItemCount(i) > 0 do
        if not turtle.refuel(1) then break end
      end
    end
    if turtle.getFuelLevel() >= FUEL_MIN then break end
  end

  turtle.select(1)
  return turtle.getFuelLevel() >= FUEL_MIN
end

-- Vacuum the block in front, above, and below the current position.
local function sweepCell()
  local got = false
  local guard = 0
  while turtle.suck()     and guard < 64 do got = true; guard = guard + 1 end
  guard = 0
  while turtle.suckUp()   and guard < 64 do got = true; guard = guard + 1 end
  guard = 0
  while turtle.suckDown() and guard < 64 do got = true; guard = guard + 1 end
  return got
end

-- Assumes the turtle is already at (0,0). Faces the chest, empties out,
-- then restores the original facing.
local function dumpToChest()
  faceDir(2)

  local dumped = 0
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and not FUEL_ITEMS[item.name] then
      turtle.select(i)
      if turtle.drop() then
        dumped = dumped + 1
      else
        print("  ! Chest full or missing - holding items")
        break
      end
    end
  end

  turtle.select(1)
  faceDir(0)
  return dumped
end

-- ============================================================
-- SWEEP
-- ============================================================

-- Serpentine cell order: down one column, up the next.
local function buildPath()
  local cells = {}
  for c = 0, WIDTH - 1 do
    if c % 2 == 0 then
      for r = 0, LENGTH - 1 do
        cells[#cells + 1] = { x = c, y = r }
      end
    else
      for r = LENGTH - 1, 0, -1 do
        cells[#cells + 1] = { x = c, y = r }
      end
    end
  end
  return cells
end

local function chestRun(resume)
  print("  Inventory full - returning to chest")
  if not navigateTo(0, 0) then
    print("  ! Could not reach home. Stopping.")
    return false
  end
  local n = dumpToChest()
  print("  Dumped " .. n .. " stack(s)")
  refuelIfNeeded()
  if resume and not navigateTo(resume.x, resume.y) then
    print("  ! Could not return to " .. resume.x .. "," .. resume.y)
    return false
  end
  return true
end

local function doPass()
  local cells   = buildPath()
  local skipped = 0
  local i       = 1

  while i <= #cells do
    if not refuelIfNeeded() then
      print("  ! Out of fuel. Heading home.")
      navigateTo(0, 0)
      return false
    end

    local cell = cells[i]
    if navigateTo(cell.x, cell.y) then
      sweepCell()
    else
      print("  ~ Skipped cell " .. cell.x .. "," .. cell.y .. " (blocked)")
      skipped = skipped + 1
    end

    i = i + 1

    if freeSlots() == 0 then
      local resume = cells[math.min(i, #cells)]
      if not chestRun(resume) then return false end
    end
  end

  if skipped > 0 then
    print("  " .. skipped .. " cell(s) unreachable this pass")
  end
  return true
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  print("=== Turtle Sweeper ===")
  print("Area: " .. WIDTH .. " x " .. LENGTH .. "  (" .. (WIDTH * LENGTH) .. " cells)")
  print("Fuel: " .. tostring(turtle.getFuelLevel()))
  print("Chest expected directly behind. Ctrl+T to stop.")
  print("")

  refuelIfNeeded()

  local passNum = 1
  while true do
    print("Pass " .. passNum .. " starting...")

    local ok = doPass()

    if not navigateTo(0, 0) then
      print("! Lost - could not get home. Halting.")
      return
    end
    faceDir(0)
    dumpToChest()

    if not ok then
      print("Pass ended early. Halting.")
      return
    end

    print("Pass " .. passNum .. " complete. Sleeping " .. PATROL_DELAY .. "s.")
    print("")
    passNum = passNum + 1
    os.sleep(PATROL_DELAY)
  end
end

main()
