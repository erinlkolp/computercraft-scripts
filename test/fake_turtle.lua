--[[
  fake_turtle.lua -- a tiny voxel world + turtle API stub for testing scripts
  in turtles/ without a Minecraft server.

  Coordinates match the scripts' own frame:
    x = right of start facing, y = forward, z = up.
  The turtle starts at (0,0,0) facing 0 (+y).

  The world holds loose item entities as well as blocks, so suck() has
  something to pick up. Items sit in a pile at a coordinate, do not block
  movement, and are handed over one stack per suck() the way CC does it.

  Scripts that patrol forever (sweeper) can be stopped cleanly with the
  sleepLimit option: the run ends the moment the script settles in for its
  nth patrol delay. Short retry backoffs do not count.

  There is also a toy computer around the turtle: an in-memory filesystem,
  an http.get served from a route table, and an os.reboot that unwinds the
  script the way a real one would. That is enough to exercise a program that
  downloads a new copy of itself and restarts into it.
]]

local FakeTurtle = {}
FakeTurtle.__index = FakeTurtle

-- What a broken block turns into in your inventory.
local DROPS = {
  ["minecraft:grass_block"] = "minecraft:dirt",
  ["minecraft:stone"]       = "minecraft:cobblestone",
}

local STACK = 64
local DX = { [0] =  0, [1] =  1, [2] =  0, [3] = -1 }
local DY = { [0] =  1, [1] =  0, [2] = -1, [3] =  0 }

function FakeTurtle.new(opts)
  opts = opts or {}
  local self = setmetatable({}, FakeTurtle)
  self.blocks    = {}                       -- ["x,y,z"] = block name
  self.pos       = { x = 0, y = 0, z = 0 }
  self.facing    = 0
  self.fuel      = opts.fuel or 20000
  self.inv       = {}                       -- [1..16] = {name=, count=}
  self.selected  = 1
  self.containers = {}                      -- ["x,y,z"] = {items={}, cap=}
  self.items     = {}                       -- ["x,y,z"] = { {name=,count=}, ... }
  self.scattered = {}                       -- items dropped on the floor
  self.output    = {}
  self.minDigZ   = math.huge                -- lowest layer any dig landed on
  self.ops       = 0
  self.opLimit   = opts.opLimit or 500000
  self.longSleeps = 0
  self.sleepLimit = opts.sleepLimit         -- nil = let it run forever

  -- the computer the turtle is
  self.files     = {}                       -- ["path"] = contents
  self.routes    = {}                       -- ["url"]  = body (absent = offline)
  self.requests  = {}                       -- urls asked for, in order
  self.reboots   = 0
  self.label     = opts.label
  return self
end

-- Raised to unwind a script that would otherwise patrol for ever. run()
-- recognises it and reports a clean finish.
FakeTurtle.STOP = "fake_turtle: stopped at sleep limit"

-- Raised by os.reboot(). A real reboot never returns to the caller either.
FakeTurtle.REBOOT = "fake_turtle: rebooted"

local function key(x, y, z) return x .. "," .. y .. "," .. z end

function FakeTurtle:setBlock(x, y, z, name)
  self.blocks[key(x, y, z)] = name
end

function FakeTurtle:getBlock(x, y, z)
  return self.blocks[key(x, y, z)]
end

-- Fills a solid slab, inclusive on every bound.
function FakeTurtle:fill(x0, x1, y0, y1, z0, z1, name)
  for x = x0, x1 do
    for y = y0, y1 do
      for z = z0, z1 do
        self:setBlock(x, y, z, name)
      end
    end
  end
end

function FakeTurtle:placeChest(x, y, z, cap)
  self:setBlock(x, y, z, "minecraft:chest")
  self.containers[key(x, y, z)] = { items = {}, cap = cap or 27 }
  return self.containers[key(x, y, z)]
end

function FakeTurtle:chestAt(x, y, z)
  return self.containers[key(x, y, z)]
end

-- ---------- loose items on the ground ----------

-- Litter for a sweeper to find. Split across stacks the way a real pile is.
function FakeTurtle:dropItem(x, y, z, name, count)
  local k = key(x, y, z)
  self.items[k] = self.items[k] or {}
  local pile = self.items[k]
  count = count or 1
  while count > 0 do
    local take = math.min(STACK, count)
    pile[#pile + 1] = { name = name, count = take }
    count = count - take
  end
end

function FakeTurtle:itemsAt(x, y, z)
  local n = 0
  local pile = self.items[key(x, y, z)]
  if pile then
    for _, s in ipairs(pile) do n = n + s.count end
  end
  return n
end

function FakeTurtle:looseItemCount()
  local n = 0
  for _, pile in pairs(self.items) do
    for _, s in ipairs(pile) do n = n + s.count end
  end
  return n
end

-- One stack per call, and false when the inventory has no room for it --
-- which is what tells a sweeper it is time to go and empty out.
function FakeTurtle:suckFrom(x, y, z)
  self:tick()
  local k = key(x, y, z)
  local pile = self.items[k]
  if not pile or #pile == 0 then return false end

  local stack    = pile[1]
  local leftover = self:give(stack.name, stack.count)
  if leftover >= stack.count then return false end

  stack.count = leftover
  if stack.count <= 0 then
    table.remove(pile, 1)
    if #pile == 0 then self.items[k] = nil end
  end
  return true
end

-- How long a sleep has to be before it counts as "settling in for a patrol
-- delay" rather than a pause. Retry backoffs are half a second and the beat
-- before a reboot is one second; a patrol delay is measured in minutes.
local LONG_SLEEP = 60

-- A patrol loop only ends when we end it, so only a patrol-sized sleep counts
-- against sleepLimit.
function FakeTurtle:sleepFor(n)
  if (n or 0) < LONG_SLEEP then return end
  self.longSleeps = self.longSleeps + 1
  if self.sleepLimit and self.longSleeps >= self.sleepLimit then
    error(FakeTurtle.STOP, 0)
  end
end

function FakeTurtle:ahead(n)
  n = n or 1
  return self.pos.x + DX[self.facing] * n, self.pos.y + DY[self.facing] * n, self.pos.z
end

function FakeTurtle:countInChest(chest, name)
  local n = 0
  for _, s in ipairs(chest.items) do
    if s.name == name then n = n + s.count end
  end
  return n
end

function FakeTurtle:countInInv(name)
  local n = 0
  for i = 1, 16 do
    local s = self.inv[i]
    if s and s.name == name then n = n + s.count end
  end
  return n
end

-- ---------- inventory helpers ----------

-- Returns the number of items that did NOT fit.
function FakeTurtle:give(name, count)
  for i = 1, 16 do
    local s = self.inv[i]
    if s and s.name == name and s.count < STACK then
      local room = STACK - s.count
      local take = math.min(room, count)
      s.count = s.count + take
      count = count - take
      if count == 0 then return 0 end
    end
  end
  for i = 1, 16 do
    if not self.inv[i] then
      local take = math.min(STACK, count)
      self.inv[i] = { name = name, count = take }
      count = count - take
      if count == 0 then return 0 end
    end
  end
  return count
end

local function chestGive(chest, name, count)
  for _, s in ipairs(chest.items) do
    if s.name == name and s.count < STACK then
      local take = math.min(STACK - s.count, count)
      s.count = s.count + take
      count = count - take
      if count == 0 then return 0 end
    end
  end
  while count > 0 and #chest.items < chest.cap do
    local take = math.min(STACK, count)
    chest.items[#chest.items + 1] = { name = name, count = take }
    count = count - take
  end
  return count
end

-- ---------- movement ----------

function FakeTurtle:tick()
  self.ops = self.ops + 1
  if self.ops > self.opLimit then
    error("fake turtle exceeded " .. self.opLimit .. " operations (runaway loop?)", 0)
  end
end

function FakeTurtle:tryMove(dx, dy, dz)
  self:tick()
  local nx, ny, nz = self.pos.x + dx, self.pos.y + dy, self.pos.z + dz
  if self:getBlock(nx, ny, nz) then return false end
  if self.fuel <= 0 then return false end
  self.fuel = self.fuel - 1
  self.pos.x, self.pos.y, self.pos.z = nx, ny, nz
  return true
end

function FakeTurtle:breakAt(x, y, z)
  self:tick()
  local name = self:getBlock(x, y, z)
  if not name then return false end
  if self.containers[key(x, y, z)] then
    error("turtle dug a container at " .. key(x, y, z), 0)
  end
  self.blocks[key(x, y, z)] = nil
  if z < self.minDigZ then self.minDigZ = z end
  local drop = DROPS[name] or name
  local leftover = self:give(drop, 1)
  if leftover > 0 then
    self.scattered[#self.scattered + 1] = { name = drop, count = leftover }
  end
  return true
end

-- ---------- the computer: files, http, reboot ----------

-- "updater.lua", "/updater.lua" and "//updater.lua" are one file, the way
-- they are on a real computer.
local function path(p) return (tostring(p):gsub("^/+", "")) end

function FakeTurtle:writeFile(p, contents)
  self.files[path(p)] = contents
end

function FakeTurtle:readFile(p)
  return self.files[path(p)]
end

-- Serve a URL. Any URL without a route behaves like the network being down.
-- A function body is called with the request number, so a test can publish a
-- new version partway through a run.
function FakeTurtle:serve(url, body)
  self.routes[url] = body
end

function FakeTurtle:fsApi()
  local w = self
  local fs = {}

  fs.exists  = function(p) return w.files[path(p)] ~= nil end
  fs.getSize = function(p) return #(w.files[path(p)] or "") end
  fs.isDir   = function() return false end
  fs.delete  = function(p) w.files[path(p)] = nil end

  fs.move = function(from, to)
    w.files[path(to)], w.files[path(from)] = w.files[path(from)], nil
  end
  fs.copy = function(from, to) w.files[path(to)] = w.files[path(from)] end

  -- A write handle accumulates and commits on close, so a script that dies
  -- mid-write leaves the old file alone -- which is what a real one does.
  fs.open = function(p, mode)
    local k = path(p)

    if mode:find("r") then
      local contents = w.files[k]
      if not contents then return nil, "No such file" end
      return {
        readAll  = function() return contents end,
        readLine = function() return contents:match("[^\n]*") end,
        close    = function() end,
      }
    end

    local parts = {}
    if mode:find("a") and w.files[k] then parts[1] = w.files[k] end
    return {
      write     = function(text) parts[#parts + 1] = tostring(text) end,
      writeLine = function(text) parts[#parts + 1] = tostring(text) .. "\n" end,
      flush     = function() end,
      close     = function() w.files[k] = table.concat(parts) end,
    }
  end

  return fs
end

function FakeTurtle:httpApi()
  local w = self
  return {
    get = function(url)
      w:tick()
      w.requests[#w.requests + 1] = url
      local body = w.routes[url]
      if type(body) == "function" then body = body(#w.requests) end
      if body == nil then return nil, "Could not connect" end
      return {
        readAll         = function() return body end,
        getResponseCode = function() return 200 end,
        close           = function() end,
      }
    end,
    checkURL = function() return true end,
  }
end

-- ---------- the API the scripts see ----------

function FakeTurtle:api()
  local w = self
  local t = {}

  t.forward = function() return w:tryMove(DX[w.facing], DY[w.facing], 0) end
  t.back    = function() return w:tryMove(-DX[w.facing], -DY[w.facing], 0) end
  t.up      = function() return w:tryMove(0, 0, 1) end
  t.down    = function() return w:tryMove(0, 0, -1) end

  t.turnRight = function() w:tick(); w.facing = (w.facing + 1) % 4; return true end
  t.turnLeft  = function() w:tick(); w.facing = (w.facing + 3) % 4; return true end

  t.detect     = function() return w:getBlock(w:ahead()) ~= nil end
  t.detectUp   = function() return w:getBlock(w.pos.x, w.pos.y, w.pos.z + 1) ~= nil end
  t.detectDown = function() return w:getBlock(w.pos.x, w.pos.y, w.pos.z - 1) ~= nil end

  t.dig     = function() return w:breakAt(w:ahead()) end
  t.digUp   = function() return w:breakAt(w.pos.x, w.pos.y, w.pos.z + 1) end
  t.digDown = function() return w:breakAt(w.pos.x, w.pos.y, w.pos.z - 1) end

  local function inspectAt(x, y, z)
    local name = w:getBlock(x, y, z)
    if not name then return false, "No block to inspect" end
    return true, { name = name, state = {}, tags = {} }
  end
  t.inspect     = function() return inspectAt(w:ahead()) end
  t.inspectUp   = function() return inspectAt(w.pos.x, w.pos.y, w.pos.z + 1) end
  t.inspectDown = function() return inspectAt(w.pos.x, w.pos.y, w.pos.z - 1) end

  t.select       = function(i) w.selected = i; return true end
  t.getSelectedSlot = function() return w.selected end
  t.getItemCount = function(i) local s = w.inv[i or w.selected]; return s and s.count or 0 end
  t.getItemSpace = function(i) local s = w.inv[i or w.selected]; return s and (STACK - s.count) or STACK end
  t.getItemDetail = function(i)
    local s = w.inv[i or w.selected]
    if not s then return nil end
    return { name = s.name, count = s.count, damage = 0 }
  end

  local function dropInto(x, y, z, count)
    w:tick()
    local slot = w.inv[w.selected]
    if not slot then return false end
    count = math.min(count or slot.count, slot.count)
    local chest = w.containers[key(x, y, z)]
    local leftover
    if chest then
      leftover = chestGive(chest, slot.name, count)
    elseif w:getBlock(x, y, z) then
      return false                                  -- solid non-container: drop fails
    else
      -- CC quirk: with nothing in front, items land on the ground and drop()
      -- still reports success. Model that faithfully so tests can catch it.
      w.scattered[#w.scattered + 1] = { name = slot.name, count = count }
      leftover = 0
    end
    local moved = count - leftover
    slot.count = slot.count - moved
    if slot.count <= 0 then w.inv[w.selected] = nil end
    return moved > 0
  end

  t.drop     = function(n)
    local x, y, z = w:ahead()
    return dropInto(x, y, z, n)
  end
  t.dropUp   = function(n) return dropInto(w.pos.x, w.pos.y, w.pos.z + 1, n) end
  t.dropDown = function(n) return dropInto(w.pos.x, w.pos.y, w.pos.z - 1, n) end

  t.getFuelLevel = function() return w.fuel end
  t.getFuelLimit = function() return 100000 end
  t.refuel = function(n)
    local slot = w.inv[w.selected]
    if not slot then return false end
    if slot.name ~= "minecraft:coal" and slot.name ~= "minecraft:charcoal" then return false end
    local take = math.min(n or slot.count, slot.count)
    if take <= 0 then return false end
    slot.count = slot.count - take
    if slot.count <= 0 then w.inv[w.selected] = nil end
    w.fuel = w.fuel + take * 80
    return true
  end

  t.suck     = function() return w:suckFrom(w:ahead()) end
  t.suckUp   = function() return w:suckFrom(w.pos.x, w.pos.y, w.pos.z + 1) end
  t.suckDown = function() return w:suckFrom(w.pos.x, w.pos.y, w.pos.z - 1) end

  return t
end

-- Memoised: every script and module in one world shares one environment, so
-- a file the updater writes is a file the next loadfile() sees.
function FakeTurtle:env()
  if self._env then return self._env end

  local w = self
  local env = {}

  local fakeOs = setmetatable({
    sleep  = function(n) w:sleepFor(n) end,
    reboot = function()
      w.reboots = w.reboots + 1
      error(FakeTurtle.REBOOT, 0)
    end,
    getComputerLabel = function() return w.label end,
    setComputerLabel = function(l) w.label = l end,
  }, { __index = os })
  local fakeTerm = {
    clear = function() end,
    setCursorPos = function() end,
    getSize = function() return 51, 19 end,
  }

  env.turtle = self:api()
  env.os     = fakeOs
  env.term   = fakeTerm
  env.fs     = self:fsApi()
  env.http   = self:httpApi()

  -- loadfile/dofile read the turtle's own disk, not the workstation's, so a
  -- module has to have been installed on it to be loadable.
  env.loadfile = function(p, mode, e)
    local contents = w:readFile(p)
    if not contents then return nil, p .. ": No such file" end
    return load(contents, "@" .. tostring(p), mode or "t", e or w:env())
  end
  env.dofile = function(p)
    local chunk, err = env.loadfile(p)
    if not chunk then error(err, 0) end
    return chunk()
  end

  env.shell = {
    run               = function() return true end,
    resolve           = function(p) return p end,
    getRunningProgram = function() return w.runningProgram or "shell" end,
  }
  env.sleep  = function(n) w:sleepFor(n) end
  env.print  = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    w.output[#w.output + 1] = table.concat(parts, " ")
  end
  env.write = env.print
  env.peripheral = {
    wrap = function(side)
      if side ~= "front" then return nil end
      local chest = w.containers[key(w:ahead())]
      if not chest then return nil end
      return {
        size = function() return chest.cap end,
        list = function() return chest.items end,
        pushItems = function() return 0 end,
      }
    end,
    getType = function(side)
      if side == "front" and w.containers[key(w:ahead())] then return "minecraft:chest" end
      return nil
    end,
  }

  env._G = env
  self._env = setmetatable(env, { __index = _G })
  return self._env
end

-- Load a module off the WORKSTATION (this repo) into the turtle's world, the
-- way `wget`ing it onto the computer would. Returns whatever it returns.
function FakeTurtle:install(diskPath, asName)
  local f = assert(io.open(diskPath, "r"))
  local contents = f:read("*a")
  f:close()
  self:writeFile(asName or diskPath:match("[^/]+$"), contents)
  return contents
end

function FakeTurtle:loadInstalled(name)
  local chunk, err = self:env().loadfile(name)
  if not chunk then error(err, 0) end
  return chunk()
end

-- Run a program from source. Lets a test flip a config constant the program
-- has no runtime setting for, and run the result.
function FakeTurtle:runSource(src, chunkName)
  local chunk, err = load(src, "@" .. (chunkName or "program"), "t", self:env())
  if not chunk then return false, err end
  local ok, runErr = pcall(chunk)
  -- Cutting a patrol loop short on purpose is a finish, not a failure, and
  -- neither is a reboot: both unwind the script by design.
  if not ok and (runErr == FakeTurtle.STOP or runErr == FakeTurtle.REBOOT) then
    return true, nil
  end
  return ok, runErr
end

function FakeTurtle:run(path)
  local f = io.open(path, "r")
  if not f then return false, path .. ": No such file" end
  local src = f:read("*a")
  f:close()
  return self:runSource(src, path)
end

function FakeTurtle:logText()
  return table.concat(self.output, "\n")
end

return FakeTurtle
