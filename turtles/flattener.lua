--[[
  flattener.lua -- ComputerCraft / CC:Tweaked terrain flattening turtle

  Strips a WIDTH x LENGTH area down to the elevation the turtle was started
  at, hauling everything it mines back to a chest behind the start position.
  Hills, grass, boulders and trees standing above that elevation come off;
  the block the turtle is standing on, and everything below it, is never
  touched. Holes already below the start layer are left as holes.

  It works layer by layer rather than column by column: sweep the whole area
  at the start layer, rise one block, sweep it again, and keep going until
  there is nothing left overhead. That costs a little more walking than
  chasing each column upwards, but it clears overhangs and floating leaves
  that a column scan would walk straight underneath.

  Knowing when to stop is the interesting part, since a turtle can only see
  the block directly above it. Every cell it stands on gets a free
  detectUp(), so finishing a layer tells us whether the NEXT layer is empty
  too -- which is what lets a tree's leaves keep the turtle climbing even
  though the leaf layers sit over thin air. That only reaches one block up,
  so the first SCAN_MIN layers are swept unconditionally to catch anything
  floating with a wider gap under it.

  SETUP
    - Place the turtle at a corner of the area, standing on the surface,
      facing along the first row. Its own block is cell (0,0).
    - Everything at the turtle's layer and above, inside the area, gets mined.
    - Place a chest DIRECTLY BEHIND the turtle, on the turtle's own layer.
      An ender chest works well; a plain one will fill up on a big job.
    - Give it coal or charcoal; it refuels itself and keeps FUEL_KEEP items
      back as a reserve. Coal it mines beyond that is posted to the chest
      like any other spoil, so a coal seam cannot fill all sixteen slots
      with material it refuses to put down.

  UPDATES
    Optional. With lib/updater.lua installed alongside it, this program looks
    for a newer version of itself at startup, before the first move, and
    restarts into it. Without that file nothing changes. Startup only: a
    one-shot job has no safe point in the middle, because the position below
    is held in memory only and a turtle that rebooted partway through would
    measure its next area from wherever it happened to be standing. See
    VERSION and AUTOSTART in CONFIG below.

  RUN
    flattener
]]

-- ============================================================
-- CONFIG
-- ============================================================

-- Bumping this is what rolls an update out to a fleet. See lib/updater.lua.
local VERSION      = "1.0.0"
local PROGRAM      = "flattener.lua" -- what we are installed as, for updates
local AUTOSTART    = true -- keep a startup.lua so a reboot comes back here

local WIDTH        = 15   -- columns (sideways, to the turtle's right)
local LENGTH       = 15   -- rows (forward, the way the turtle starts facing)
local MAX_HEIGHT   = 32   -- never climb higher than this above the start layer
local SCAN_MIN     = 4    -- always sweep this many layers before trusting
                          -- "nothing above me"; raise it if you have debris
                          -- floating more than a block clear of everything
                          -- else, lower it to save walking on flat ground
local FUEL_MIN     = 200  -- top up when fuel drops below this
local FUEL_MARGIN  = 16   -- keep at least this much on top of the trip home
local MAX_STUCK    = 6    -- give up on a move after this many failed attempts
local DIG_RETRY    = 8    -- re-digs per block, so gravel columns can't win
local FUEL_KEEP    = 64   -- fuel items held back; the rest goes in the chest

local FUEL_ITEMS = {
  ["minecraft:coal"]       = true,
  ["minecraft:charcoal"]   = true,
  ["minecraft:coal_block"] = true,
  ["minecraft:blaze_rod"]  = true,
}

-- Block names that are safe to drop into. Used only as a fallback when the
-- peripheral API can't tell us what's in front.
local INVENTORY_HINTS = { "chest", "barrel", "shulker_box", "hopper", "drawer" }

-- ============================================================
-- STATE
-- ============================================================

-- facing: 0 = start direction (+Y), 1 = right (+X), 2 = back (-Y), 3 = left (-X)
-- pos.z is height above the layer the turtle was placed on. It never goes
-- negative: z = 0 is the floor we are levelling to, and we do not dig it.
local pos    = { x = 0, y = 0, z = 0 }
local facing = 0
local digs   = 0   -- running total, used to spot an empty layer

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

-- Dig the same spot several times over. Gravel and sand fall into the gap
-- the instant we clear it, so a single dig() leaves the way still blocked.
local function digRepeatedly(digFn, detectFn)
  local n = 0
  while n < DIG_RETRY and detectFn() do
    if not digFn() then break end
    digs = digs + 1
    n = n + 1
  end
  return not detectFn()
end

-- Every dig in this script goes through one of these three, and each one is
-- only ever reachable while the turtle is inside the work area, so we can't
-- chew a hole in someone's build next door.
local function digForward() return digRepeatedly(turtle.dig,     turtle.detect)     end
local function digAbove()   return digRepeatedly(turtle.digUp,   turtle.detectUp)   end
local function digBelow()   return digRepeatedly(turtle.digDown, turtle.detectDown) end

-- Move one block forward, mining whatever is in the way.
local function moveForward()
  if stepForward() then return true end
  if digForward() then return stepForward() end
  return false
end

-- One step towards a target height, mining if needed. z = 0 is the floor we
-- are levelling to, so digBelow() is off limits at that height.
local function stepToward(tz)
  if pos.z < tz then
    if stepUp() then return true end
    if digAbove() then return stepUp() end
    return false
  elseif pos.z > tz then
    if stepDown() then return true end
    if pos.z - 1 >= 0 and digBelow() then return stepDown() end
    return false
  end
  return true
end

-- Walk to a cell, mining through anything in the way. Height is settled
-- first so that climbing to the next layer happens before we start walking
-- it, and so the trip home descends through ground we already cleared.
--
-- Targets always sit inside the area and every leg is axis-aligned, so the
-- turtle can never dig its way outside the 15x15 -- including into the chest,
-- which sits one block behind the y = 0 edge.
local function navigateTo(tx, ty, tz)
  local stuck = 0
  while pos.x ~= tx or pos.y ~= ty or pos.z ~= tz do
    local moved = false

    if pos.z ~= tz then
      moved = stepToward(tz)
    end

    if not moved and pos.y ~= ty then
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
      if stuck >= MAX_STUCK then return false end
      os.sleep(0.5)
    end
  end
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

-- Assumes the turtle is already at (0,0). Drops to the chest's layer, empties
-- everything that isn't fuel, then faces forward again.
-- Returns (stacks dumped, whether everything non-fuel got out).
local function dumpToChest()
  if not navigateTo(0, 0, 0) then
    print("  ! Could not get down to the chest layer")
    return 0, false
  end
  faceDir(2)

  if not inventoryInFront() then
    print("  ! No container behind me - holding items rather than dropping them")
    faceDir(0)
    return 0, false
  end

  -- Fuel is held back, but only FUEL_KEEP of it. A coal seam is ordinary
  -- spoil, and treating every block of it as untouchable fuel is how a
  -- turtle ends up with sixteen slots it refuses to put down, halfway
  -- through a job it then abandons.
  local dumped, blocked, kept = 0, false, 0
  for i = 1, 16 do
    local item = turtle.getItemDetail(i)
    if item then
      local count, keep = turtle.getItemCount(i), 0
      if FUEL_ITEMS[item.name] and kept < FUEL_KEEP then
        keep = math.min(count, FUEL_KEEP - kept)
        kept = kept + keep
      end

      if keep < count then
        turtle.select(i)
        turtle.drop(count - keep)
        if turtle.getItemCount(i) <= keep then
          dumped = dumped + 1
        else
          print("  ! Chest is full - holding the rest")
          blocked = true
          break
        end
      end
    end
  end

  turtle.select(1)
  faceDir(0)
  return dumped, not blocked
end

-- ============================================================
-- FLATTEN
-- ============================================================

-- Serpentine cell order: down one column, up the next, so consecutive cells
-- are always neighbours.
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

local function reversed(cells)
  local out = {}
  for i = #cells, 1, -1 do out[#out + 1] = cells[i] end
  return out
end

local function chestRun(resume)
  print("  Inventory full - returning to chest")
  if not navigateTo(0, 0, 0) then
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
  if resume and not navigateTo(resume.x, resume.y, resume.z) then
    print("  ! Could not get back to " .. resume.x .. "," .. resume.y ..
          " at height " .. resume.z)
    return false
  end
  return true
end

-- Sweep one horizontal layer.
-- Returns (completed, blocks mined, cells skipped, saw anything overhead).
-- Alternating the walk direction each layer means we start the next layer
-- where the last one ended instead of trekking back to the corner.
local function sweepLayer(z, backwards)
  local cells    = buildPath()
  if backwards then cells = reversed(cells) end
  local before   = digs
  local skipped  = 0
  local sawAbove = false

  for i = 1, #cells do
    local cell = cells[i]

    refuelIfNeeded()
    if not fuelOk() then
      print("  ! Fuel too low to keep going. Heading home.")
      navigateTo(0, 0, 0)
      return false, digs - before, skipped, sawAbove
    end

    -- Never start a cell with a full inventory: a dig with nowhere to put the
    -- block scatters it on the ground.
    if freeSlots() == 0 then
      if not chestRun({ x = cell.x, y = cell.y, z = z }) then
        return false, digs - before, skipped, sawAbove
      end
    end

    if navigateTo(cell.x, cell.y, z) then
      -- Free lookahead: standing here tells us whether the layer above this
      -- cell is occupied, which is how we know there is more work up there.
      if turtle.detectUp() then sawAbove = true end
    else
      skipped = skipped + 1
      if skipped <= 3 then
        print("  ~ Skipped cell " .. cell.x .. "," .. cell.y .. " (blocked)")
      elseif skipped == 4 then
        print("  ~ ...more blocked cells, suppressing further notices")
      end
    end
  end

  return true, digs - before, skipped, sawAbove
end

-- ============================================================
-- SELF-UPDATE
-- ============================================================

-- lib/updater.lua if it happens to be installed. Optional on purpose: a
-- turtle with nothing but this one file wget'd onto it still runs, it just
-- never picks up a new version by itself.
local function loadUpdater()
  if type(fs) ~= "table" or type(fs.exists) ~= "function" then return nil end
  for _, path in ipairs({ "updater.lua", "/updater.lua", "lib/updater.lua" }) do
    if fs.exists(path) then
      local ok, mod = pcall(dofile, path)
      if ok and type(mod) == "table" and type(mod.check) == "function" then
        return mod
      end
    end
  end
  return nil
end

-- Look for a newer copy of ourselves and restart into it.
--
-- ONLY EVER CALL THIS SOMEWHERE STOPPING IS FREE. Position is tracked in
-- memory and nothing is written to disk, so a turtle that reboots mid-job
-- wakes up believing it is back at (0,0) facing the way it started -- and
-- would work the wrong patch of ground from there.
local function updateCheck()
  local upd = loadUpdater()
  if not upd then return end

  -- Make sure a reboot brings us back up running, rather than dropping the
  -- turtle to a prompt somewhere nobody is going to walk to.
  if AUTOSTART then
    local st, detail = upd.ensureStartup(PROGRAM)
    if st == "foreign" then print("  ~ " .. tostring(detail)) end
  end

  local status, detail = upd.check(PROGRAM, VERSION)
  if status == "updated" then
    print("Updated " .. tostring(detail) .. " - restarting.")
    os.sleep(1)
    os.reboot()
  elseif status == "rejected" then
    print("! Update refused: " .. tostring(detail))
  end
end

-- ============================================================
-- MAIN
-- ============================================================

local function main()
  term.clear()
  term.setCursorPos(1, 1)
  print("=== Turtle Flattener v" .. VERSION .. " ===")
  print("Area: " .. WIDTH .. " x " .. LENGTH .. "  (" .. (WIDTH * LENGTH) .. " cells)")
  print("Levelling to my current elevation. Nothing below it is touched.")
  print("Fuel: " .. tostring(turtle.getFuelLevel()))
  print("Chest expected directly behind. Ctrl+T to stop.")
  print("")

  -- Safe: nothing has moved yet, so we are exactly where we were placed.
  -- This is a one-shot job with no safe interior point, so it is the only
  -- update check the flattener makes -- it picks up new versions when you
  -- start a job, not during one.
  updateCheck()

  refuelIfNeeded()

  local mined = 0

  for z = 0, MAX_HEIGHT do
    local ok, layerDigs, skipped, sawAbove = sweepLayer(z, z % 2 == 1)
    mined = mined + layerDigs

    print("Layer +" .. z .. ": mined " .. layerDigs ..
          (skipped > 0 and (", " .. skipped .. " cell(s) unreachable") or ""))

    if not ok then
      print("Stopped early on layer +" .. z .. ".")
      break
    end

    -- Stop once this layer came up empty AND nothing was spotted overhead,
    -- but never before SCAN_MIN layers have actually been walked. A cell we
    -- could not reach is not a cell we know to be empty, so a layer with
    -- skipped cells is never grounds for calling the job done.
    if z + 1 >= SCAN_MIN and layerDigs == 0 and not sawAbove and skipped == 0 then
      print("Nothing left up here. Done.")
      break
    end

    if z == MAX_HEIGHT then
      print("! Hit the " .. MAX_HEIGHT .. " block height limit with blocks left.")
    end
  end

  if not navigateTo(0, 0, 0) then
    print("! Lost - could not get home. Halting.")
    return
  end
  dumpToChest()

  print("")
  print("Mined " .. mined .. " block(s). Fuel left: " .. tostring(turtle.getFuelLevel()))
end

main()
