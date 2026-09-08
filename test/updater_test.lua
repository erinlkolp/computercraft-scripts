--[[
  updater_test.lua -- run with:  lua test/updater_test.lua   (from repo root)

  The updater is exercised as a module loaded onto the fake computer, the way
  it would be after a wget, so it reads and writes that computer's disk and
  fetches over its http stub rather than the workstation's.
]]

package.path = "test/?.lua;" .. package.path
local FakeTurtle = require("fake_turtle")

local MODULE = "lib/updater.lua"

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

-- A believable installed program: a VERSION line and some code under it.
local function program(version, body)
  return 'local VERSION = "' .. version .. '"\n' ..
         (body or 'local function main() end\nmain()\n')
end

-- A computer with sweeper.lua installed at `installed`, and the updater
-- module loaded and ready to use.
local function boot(installed)
  local w = FakeTurtle.new({})
  w:install(MODULE, "updater.lua")
  local upd = w:loadInstalled("updater.lua")
  if installed then w:writeFile("sweeper.lua", program(installed)) end
  return w, upd
end

local function urlFor(upd, name)
  return upd.rawUrl(upd.SOURCES[name])
end

print("updater")

test("installs a strictly newer version", function()
  local w, upd = boot("1.0.0")
  local fresh = program("1.1.0", 'print("new")\n')
  w:serve(urlFor(upd, "sweeper.lua"), fresh)

  local status = upd.check("sweeper.lua", "1.0.0")
  assertEq(status, "updated", "status")
  assertEq(w:readFile("sweeper.lua"), fresh, "the new version should be on disk")
end)

test("leaves an identical version alone", function()
  local w, upd = boot("1.0.0")
  w:serve(urlFor(upd, "sweeper.lua"), program("1.0.0", 'print("same")\n'))

  assertEq(upd.check("sweeper.lua", "1.0.0"), "current", "status")
  assertEq(w:readFile("sweeper.lua"), program("1.0.0"), "the file should be untouched")
end)

test("refuses to install an older version", function()
  local w, upd = boot("2.0.0")
  w:serve(urlFor(upd, "sweeper.lua"), program("1.9.9", 'print("old")\n'))

  assertEq(upd.check("sweeper.lua", "2.0.0"), "current", "status")
  assertEq(w:readFile("sweeper.lua"), program("2.0.0"), "the file should be untouched")
end)

test("compares version numbers numerically, not as text", function()
  local _, upd = boot()
  assertTrue(upd.isNewer("1.10.0", "1.9.0"), "1.10.0 is newer than 1.9.0")
  assertTrue(not upd.isNewer("1.9.0", "1.10.0"), "1.9.0 is not newer than 1.10.0")
  assertTrue(upd.isNewer("1.2.1", "1.2"), "1.2.1 is newer than 1.2")
  assertTrue(not upd.isNewer("1.2", "1.2.0"), "1.2 is not newer than 1.2.0")
end)

test("refuses a download that does not compile, and keeps the old file", function()
  -- The realistic network failure: a body that arrives truncated. Writing it
  -- over the program leaves a turtle someone has to walk to.
  local w, upd = boot("1.0.0")
  w:serve(urlFor(upd, "sweeper.lua"), 'local VERSION = "9.9.9"\nlocal function main(')

  assertEq(upd.check("sweeper.lua", "1.0.0"), "rejected", "status")
  assertEq(w:readFile("sweeper.lua"), program("1.0.0"), "the old version must survive")
end)

test("refuses a download with no VERSION line", function()
  local w, upd = boot("1.0.0")
  w:serve(urlFor(upd, "sweeper.lua"), 'print("perfectly valid, but unversioned")\n')

  assertEq(upd.check("sweeper.lua", "1.0.0"), "rejected", "status")
  assertEq(w:readFile("sweeper.lua"), program("1.0.0"), "the old version must survive")
end)

test("refuses a download that compiles but is a fraction of the size", function()
  -- A truncation that happens to land on a statement boundary still parses.
  -- What gives it away is that a release is never half the file it replaces.
  local w, upd = boot("1.0.0")
  local full = program("1.0.0", string.rep('local pad = "..."\n', 200))
  w:writeFile("sweeper.lua", full)
  w:serve(urlFor(upd, "sweeper.lua"), program("1.1.0", 'local pad = "..."\n'))

  assertEq(upd.check("sweeper.lua", "1.0.0"), "rejected", "status")
  assertEq(w:readFile("sweeper.lua"), full, "the old version must survive")
end)

test("reports being offline rather than throwing", function()
  local w, upd = boot("1.0.0")           -- no route served at all
  assertEq(upd.check("sweeper.lua", "1.0.0"), "offline", "status")
  assertEq(w:readFile("sweeper.lua"), program("1.0.0"), "the file should be untouched")
end)

test("copes with the HTTP API being switched off entirely", function()
  -- Plenty of servers run with http_enable false. The global is then simply
  -- absent, and looking a program up in it must not throw.
  local w, upd = boot("1.0.0")
  w:env().http = nil

  assertEq(upd.check("sweeper.lua", "1.0.0"), "offline", "status")
  assertEq(w:readFile("sweeper.lua"), program("1.0.0"), "the file should be untouched")
end)

test("does not know how to update a program it has no source for", function()
  local _, upd = boot()
  assertEq(upd.check("someone_elses_program.lua", "1.0.0"), "unknown", "status")
end)

test("keeps a backup that restore puts back", function()
  local w, upd = boot("1.0.0")
  local old = w:readFile("sweeper.lua")
  w:serve(urlFor(upd, "sweeper.lua"), program("1.1.0", 'print("new")\n'))

  assertEq(upd.check("sweeper.lua", "1.0.0"), "updated", "status")
  assertEq(w:readFile("sweeper.lua.bak"), old, "the old version should be backed up")

  assertTrue(upd.restore("sweeper.lua"), "restore should report success")
  assertEq(w:readFile("sweeper.lua"), old, "restore should put the old version back")
end)

test("can update itself", function()
  -- Serve the real module back with its version bumped: the updater is in
  -- SOURCES like anything else, so it has to be able to replace itself.
  local w, upd = boot()
  local fresh = (w:readFile("updater.lua")
                  :gsub('local VERSION = "[%d%.]+"', 'local VERSION = "9.9.9"', 1))
  assertTrue(upd.parseVersion(fresh) == "9.9.9",
             "the updater must declare its version where parseVersion can see it")
  w:serve(urlFor(upd, "updater.lua"), fresh)

  assertEq(upd.check("updater.lua", upd.VERSION), "updated", "status")
  assertEq(w:readFile("updater.lua"), fresh, "the updater should have replaced itself")
end)

test("writes a startup file that relaunches the program", function()
  local w, upd = boot("1.0.0")
  assertEq(upd.ensureStartup("sweeper.lua"), "written", "status")

  local startup = w:readFile("startup.lua")
  assertTrue(startup, "a startup file should exist")
  assertTrue(startup:find("sweeper.lua", 1, true), "it should launch sweeper.lua")
  assertTrue(load(startup, "startup", "t", {}), "it should be valid Lua")
end)

test("rewrites its own startup file without complaint", function()
  local w, upd = boot("1.0.0")
  upd.ensureStartup("sweeper.lua")
  assertEq(upd.ensureStartup("sweeper.lua"), "current", "second call")
  assertEq(upd.ensureStartup("flattener.lua"), "written", "pointing it elsewhere")
  assertTrue(w:readFile("startup.lua"):find("flattener.lua", 1, true), "should relaunch flattener")
end)

test("never clobbers a startup file somebody else wrote", function()
  local w, upd = boot("1.0.0")
  local mine = 'print("my own startup, thanks")\n'
  w:writeFile("startup.lua", mine)

  assertEq(upd.ensureStartup("sweeper.lua"), "foreign", "status")
  assertEq(w:readFile("startup.lua"), mine, "a hand-written startup must survive")
end)

print("")
if #failures > 0 then
  print(#failures .. " of " .. count .. " failed")
  os.exit(1)
end
print("all " .. count .. " passed")
