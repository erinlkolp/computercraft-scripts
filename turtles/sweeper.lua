--[[
  sweeper.lua -- ComputerCraft / CC:Tweaked item sweeper turtle

  Patrols a WIDTH x LENGTH area on a single layer, vacuuming up loose item
  drops. Returns to a chest behind its start position when the inventory
  fills, then resumes exactly where it left off.

  A turtle cannot suck up items that share its own block, so the sweep is
  flown one block ABOVE the litter layer and every cell is cleared with
  suckDown(). That keeps coverage independent of which way the turtle
  happens to be facing, and keeps it from reaching outside the area.

  SETUP
    - Place the turtle at a corner of the area, standing on the surface you
      want swept, facing along the first row.
    - Leave the layer ABOVE the area clear if you can; the turtle hovers so
      that suckDown() can clear the block it is standing on. Under a low roof
      it drops to ground level automatically and sweeps sideways instead,
      which still works but misses some cells.
    - Place a chest DIRECTLY BEHIND the turtle, on the turtle's own layer.
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
local FUEL_MIN     = 200   -- top up when fuel drops below this
local FUEL_MARGIN  = 16    -- keep at least this much on top of the trip home
local MAX_STUCK    = 3     -- give up on a cell after this many failed moves
local CLIMB_LIMIT  = 3     -- how many blocks we'll climb to get over something
local SUCK_LIMIT   = 64    -- max suck() calls per cell, so we can't spin forever
local SWEEP_ALT    = 1     -- blocks above the start layer that we cruise at

local FUEL_ITEMS = {
  ["minecraft:coal"]        = true,
  ["minecraft:charcoal"]    = true,
  ["minecraft:coal_block"]  = true,
  ["minecraft:blaze_rod"]   = true,
}

-- Block names that are safe to drop into. Used only as a fallback when the
-- peripheral API can't tell us what's in front.
local INVENTORY_HINTS = { "chest", "barrel", "shulker_box", "hopper", "drawer" }

-- ============================================================
-- STATE
-- ============================================================

-- facing: 0 = start direction (+Y), 1 = right (+X), 2 = back (-Y), 3 = left (-X)
-- pos.z is height above the layer the turtle was placed on.
local pos    = { x = 0, y = 0, z = 0 }
local facing = 0

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

-- Raw steps that keep pos in sync. Every move in this script goes through
-- one of these, so pos never drifts from where the turtle actually is.
local function stepForward()
  if turtle.forward() then
    pos.x = pos.x + DX[facing]
    pos.y = pos.y + DY[facing]
    return true
  end
  return false
end

local function stepUp()
  if turtle.up() then pos.z = pos.z + 1; return true end
  return false
end

local function stepDown()
  if turtle.down() then pos.z = pos.z - 1; return true end
  return false
end

-- Climb or drop to a given height. Returns false if something is in the way,
-- but pos.z still reflects wherever we actually stopped.
local function goToAlt(target)
  while pos.z < target do
    if not stepUp() then return false end
  end
  while pos.z > target do
    if not stepDown() then return false end
  end
  return true
end

-- Move one block forward at cruising height. If blocked, climb over.
local function moveForward(cruise)
  if stepForward() then
    goToAlt(cruise)
    return true
  end

  -- Obstacle: try to get over it, remembering how high we went so we can
  -- put ourselves back if there's no way through.
  local startZ  = pos.z
  local climbed = 0
  while climbed < CLIMB_LIMIT and stepUp() do
    climbed = climbed + 1
    if stepForward() then
      goToAlt(cruise)
      return true
    end
  end

  goToAlt(startZ)
  return false
end

-- Walk to a grid cell, preferring the Y axis then falling back to X.
local function navigateTo(tx, ty, cruise)
  local stuck = 0
  while pos.x ~= tx or pos.y ~= ty do
    local moved = false

    if pos.y ~= ty then
      faceDir(pos.y < ty and 0 or 2)
      moved = moveForward(cruise)
    end

    if not moved and pos.x ~= tx then
      faceDir(pos.x < tx and 1 or 3)
      moved = moveForward(cruise)
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
  goToAlt(cruise)
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

-- Blocks of fuel we'd burn just getting back to the chest from here.
local function fuelToHome()
  return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

local function fuelOk()
  local level = turtle.getFuelLevel()
  if level == "unlimited" then return true end
  return level > fuelToHome() + FUEL_MARGIN
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

-- Vacuum the cell we are hovering over, plus whatever is within reach.
-- suckDown() is the one that matters: it clears the cell we are standing on
-- regardless of facing, which is what makes coverage complete. The forward
-- and upward sucks are a bonus and may pull in a neighbouring row.
local function sweepCell()
  local got = 0
  while got < SUCK_LIMIT and turtle.suckDown() do got = got + 1 end
  while got < SUCK_LIMIT and turtle.suck()     do got = got + 1 end
  while got < SUCK_LIMIT and turtle.suckUp()   do got = got + 1 end
  return got
end

-- turtle.drop() throws items on the FLOOR when there's no inventory in front
-- and still reports success, so we have to check for a real container first
-- or a missing chest silently scatters the whole haul.
local function inventoryInFront()
  if peripheral and peripheral.wrap then
    local ok, p = pcall(peripheral.wrap, "front")
    if ok and type(p) == "table" and (p.size or p.list or p.pushItems) then
      return true
    end
  end

  local found, data = turtle.inspect()
  if not found or type(data) ~= "table" or not data.name then return false end
  for _, hint in ipairs(INVENTORY_HINTS) do
    if string.find(data.name, hint, 1, true) then return true end
  end
  return false
end

-- Assumes the turtle is already over (0,0). Drops to the chest's layer,
-- empties out, then returns to cruising height facing forward.
-- Returns (stacks dumped, whether everything non-fuel got out).
local function dumpToChest()
  goToAlt(0)
  faceDir(2)

  if not inventoryInFront() then
    print("  ! No container behind me - holding items rather than dropping them")
    faceDir(0)
    return 0, false
  end

  local dumped, blocked = 0, false
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item and not FUEL_ITEMS[item.name] then
      turtle.select(i)
      turtle.drop()
      if turtle.getItemCount(i) == 0 then
        dumped = dumped + 1
      else
        print("  ! Chest is full - holding the rest")
        blocked = true
        break
      end
    end
  end

  turtle.select(1)
  faceDir(0)
  return dumped, not blocked
end

-- ============================================================
-- SWEEP
-- ============================================================

-- Hovering one block up is what lets suckDown() clear the cell we are
-- standing on. A low roof (mob farm floors, 2-high rooms) makes that
-- impossible, so fall back to ground level and sweep sideways rather than
-- refusing to work and reporting every single cell as blocked.
local function pickCruiseAlt()
  if goToAlt(SWEEP_ALT) then return SWEEP_ALT end
  goToAlt(0)
  print("! No headroom above me - sweeping at ground level.")
  print("  Coverage will be partial. Clear the layer above for a full sweep.")
  return 0
end

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

local function chestRun(resume, cruise)
  print("  Inventory full - returning to chest")
  if not navigateTo(0, 0, cruise) then
    print("  ! Could not reach home. Stopping.")
    return false
  end

  local n, emptied = dumpToChest()
  print("  Dumped " .. n .. " stack(s)")

  -- If we came home full and go back out still full we'd just bounce off the
  -- chest once per cell forever, so stop instead.
  if not emptied or freeSlots() == 0 then
    print("  ! No inventory space freed. Halting so we don't spin.")
    return false
  end

  refuelIfNeeded()
  if resume and not navigateTo(resume.x, resume.y, cruise) then
    print("  ! Could not return to " .. resume.x .. "," .. resume.y)
    return false
  end
  return true
end

local function doPass(cruise)
  local cells   = buildPath()
  local skipped = 0
  local i       = 1

  while i <= #cells do
    refuelIfNeeded()
    if not fuelOk() then
      print("  ! Fuel too low to keep going. Heading home.")
      navigateTo(0, 0, cruise)
      return false
    end

    local cell = cells[i]
    if navigateTo(cell.x, cell.y, cruise) then
      -- Sweep from wherever we actually ended up. If a local overhang pushed
      -- us below cruising height we still get the sideways sucks.
      sweepCell()
    else
      skipped = skipped + 1
      if skipped <= 3 then
        print("  ~ Skipped cell " .. cell.x .. "," .. cell.y .. " (blocked)")
      elseif skipped == 4 then
        print("  ~ ...more blocked cells, suppressing further notices")
      end
    end

    i = i + 1

    if freeSlots() == 0 and i <= #cells then
      if not chestRun(cells[i], cruise) then return false end
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
  local cruise = pickCruiseAlt()

  local passNum = 1
  while true do
    print("Pass " .. passNum .. " starting...")

    local ok = doPass(cruise)

    if not navigateTo(0, 0, cruise) then
      print("! Lost - could not get home. Halting.")
      return
    end
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
