--[[
  MountsRarity/scripts/benchmark.lua

  Standalone benchmark harness for MountsRarity.lua, run outside the WoW
  client via `lua` or `luajit`.

  Usage: lua scripts/benchmark.lua [path/to/MountsRarity.lua] [numLookups]
]]

local TARGET = arg[1] or "MountsRarity.lua"
local NUM_LOOKUPS = tonumber(arg[2]) or 5000

-- The addon's --@debug@ blocks call debugprofilestop(), a WoW client global
-- (high-resolution ms timer) that doesn't exist here. Polyfill it with
-- os.clock() so those blocks still run when loading the raw file outside
-- the client, unless it's already defined (e.g. some other WoW API shim).
_G.debugprofilestop = function()
return os.clock() * 1000
end

local function newLibStub()
  local libs = {}
  return {
    NewLibrary = function(_, major)
      libs[major] = libs[major] or {}
      return libs[major]
    end,
  }
end

-- Loads a brand-new instance of the library under test, with its own
-- LibStub registry, so each measurement starts from a clean slate.
local function loadLibrary(chunk)
  _G.LibStub = newLibStub()
  chunk()
  return LibStub:NewLibrary("MountsRarity-2.0")
end

local function kb()
  collectgarbage("collect")
  return collectgarbage("count")
end

local function fileSize(path)
  local f = assert(io.open(path, "rb"))
  local size = f:seek("end")
  f:close()
  return size
end

print(("Benchmarking %s (%d lookups)"):format(TARGET, NUM_LOOKUPS))
print(("File size: %d bytes"):format(fileSize(TARGET)))

-- 1. Compile time: parsing/bytecode-compiling the file, without running it.
local memBeforeCompile = kb()
local t0 = os.clock()
local chunk = assert(loadfile(TARGET))
local compileTime = os.clock() - t0
local memAfterCompile = kb()

print("\n-- Compile --")
print(("  loadfile (compile-only) time: %.6fs"):format(compileTime))
print(("  Memory: %.1f KB before -> %.1f KB after compiling (chunk not yet run)"):format(memBeforeCompile, memAfterCompile))

-- 2. Sample mount IDs from a throwaway instance (not timed).
local bootstrap = loadLibrary(chunk)
local allData = bootstrap:GetData()
local ids = {}
for id in pairs(allData) do
  ids[#ids + 1] = id
end
table.sort(ids)
assert(#ids > 0, "no mount IDs found in " .. TARGET)

local lookupSequence = {}
for i = 1, NUM_LOOKUPS do
  if i % 10 == 0 then
    lookupSequence[i] = -i -- guaranteed miss; no negative mount IDs exist
  else
    lookupSequence[i] = ids[((i - 1) % #ids) + 1]
  end
end

-- 3. Fresh instance: first access + repeated GetRarityByID only (GetData
--    is never called), to isolate the single-lookup path.
do
  local memBefore = kb()
  local lib = loadLibrary(chunk)

  local t1 = os.clock()
  lib:GetRarityByID(lookupSequence[1])
  local firstAccessTime = os.clock() - t1
  local memAfterFirst = kb()

  local t2 = os.clock()
  local checksum = 0
  for i = 1, NUM_LOOKUPS do
    local r = lib:GetRarityByID(lookupSequence[i])
    if r then
      checksum = checksum + r
    end
  end
  local repeatedTime = os.clock() - t2
  local memAfterLoop = kb()

  print("\n-- GetRarityByID-only path (GetData never called) --")
  print(("  First access time: %.6fs"):format(firstAccessTime))
  print(("  %d calls total: %.6fs (avg %.9fs/call)"):format(NUM_LOOKUPS, repeatedTime, repeatedTime / NUM_LOOKUPS))
  print(("  Memory: %.1f KB before load -> %.1f KB after first access -> %.1f KB after %d calls"):format(
    memBefore, memAfterFirst, memAfterLoop, NUM_LOOKUPS))
  print(("  (checksum %.4f, to avoid dead-code elimination)"):format(checksum))
end

-- 4. Fresh instance: first access + repeated GetData (cache hits after
--    the first call), to isolate the full-dataset path.
do
  local memBefore = kb()
  local lib = loadLibrary(chunk)

  local t1 = os.clock()
  lib:GetData()
  local firstAccessTime = os.clock() - t1
  local memAfterFirst = kb()

  local t2 = os.clock()
  local count = 0
  for _ = 1, NUM_LOOKUPS do
    local d = lib:GetData()
    count = count + (d and 1 or 0)
  end
  local repeatedTime = os.clock() - t2
  local memAfterLoop = kb()

  print("\n-- GetData path --")
  print(("  First access time: %.6fs"):format(firstAccessTime))
  print(("  %d calls total: %.6fs (avg %.9fs/call)"):format(NUM_LOOKUPS, repeatedTime, repeatedTime / NUM_LOOKUPS))
  print(("  Memory: %.1f KB before load -> %.1f KB after first access -> %.1f KB after %d calls"):format(
    memBefore, memAfterFirst, memAfterLoop, NUM_LOOKUPS))
end
