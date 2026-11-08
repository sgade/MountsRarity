--[[----------------------------------------------------------------------------

  MountsRarity/scripts/test-client-selection.lua
  Makes sure that each game client only gets its own rarity data.
  Run from the root of the repository.

  Copyright (c) 2026 Sören Gade
  For the full license, see the LICENSE file.

----------------------------------------------------------------------------]]--

local RETAIL_FILE = "MountsRarity.lua"
local FOREVER_FILE = "MountsRarity_Forever.lua"
local MARKER = "-- Everything after this line gets automatically replaced and updated.\n"
local DATA_START = MARKER .. "lazyLoadData = function() return {\n"

local PROJECT_MAINLINE, PROJECT_CLASSIC, PROJECT_CAMELOT = 1, 2, 18
local SHARED_MOUNT_ID = 6
local RETAIL_ONLY_MOUNT_ID = 3144
local FOREVER_RARITY = 12.5

local loadChunk = loadstring or load

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local content = file:read("*a")
  file:close()
  return content
end

local retailSource = readFile(RETAIL_FILE)
local foreverSource = readFile(FOREVER_FILE)

-- The Forever file has no data until Data for Azeroth publishes it.
local function plainReplace(source, search, replacement)
  local first, last = source:find(search, 1, true)
  assert(first, "Text not found: " .. search)
  return source:sub(1, first - 1) .. replacement .. source:sub(last + 1)
end

local foreverSourceWithData = plainReplace(
  foreverSource,
  DATA_START,
  DATA_START .. ("  [%d] = %s,\n"):format(SHARED_MOUNT_ID, FOREVER_RARITY)
)
foreverSourceWithData = foreverSourceWithData:gsub("local LAST_UPDATED = 0", "local LAST_UPDATED = 1000")

local function setUpClient(project)
  _G.LibStub = nil
  _G.WOW_PROJECT_ID = project
  _G.WOW_PROJECT_MAINLINE = PROJECT_MAINLINE
  _G.WOW_PROJECT_CAMELOT = PROJECT_CAMELOT
  _G.strmatch = string.match
  _G.debugprofilestop = function() return 0 end
  _G.print = function() end
  assert(loadChunk(readFile("Libs/LibStub/LibStub.lua")))()
end

local function run(source, name)
  assert(loadChunk(source, "@" .. name))()
end

local function loadInOrder(sources)
  for _, entry in ipairs(sources) do
    run(entry[1], entry[2])
  end
  return _G.LibStub("MountsRarity-2.0")
end

local retail = { retailSource, RETAIL_FILE }
local forever = { foreverSourceWithData, FOREVER_FILE }

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(("%s: expected %s, got %s"):format(message, tostring(expected), tostring(actual)), 2)
  end
end

local function assertNoData(library, name)
  assertEqual(next(library:GetData()), nil, name .. ": GetData")
  assertEqual(library:GetRarityByID(SHARED_MOUNT_ID), nil, name .. ": GetRarityByID")
  assertEqual(library:GetLastUpdated(), nil, name .. ": GetLastUpdated")
end

local function assertRetail(library, name)
  assertEqual(type(library:GetRarityByID(SHARED_MOUNT_ID)), "number", name .. ": shared mount")
  assertEqual(type(library:GetRarityByID(RETAIL_ONLY_MOUNT_ID)), "number", name .. ": Retail mount")
  assertEqual(type(library:GetLastUpdated()), "number", name .. ": GetLastUpdated")
  assert(library:GetRarityByID(SHARED_MOUNT_ID) ~= FOREVER_RARITY, name .. ": got Forever data")
end

local function assertForever(library, name)
  assertEqual(library:GetRarityByID(SHARED_MOUNT_ID), FOREVER_RARITY, name .. ": shared mount")
  assertEqual(library:GetRarityByID(RETAIL_ONLY_MOUNT_ID), nil, name .. ": Retail mount")
  assertEqual(library:GetLastUpdated(), 1000, name .. ": GetLastUpdated")
end

local function normalizedHeader(source)
  local first = assert(source:find(MARKER, 1, true), "Data marker not found")
  return (source:sub(1, first - 1)
    :gsub("MountsRarity/MountsRarity_?F?o?r?e?v?e?r?%.lua", "FILE")
    :gsub("local MINOR = %d+", "local MINOR = 0")
    :gsub("local LAST_UPDATED = %d+", "local LAST_UPDATED = 0")
    :gsub("WOW_PROJECT_ID == WOW_PROJECT_%u+", "CLIENT"))
end

local tests = {
  ["retail client, Retail file first"] = function()
    setUpClient(PROJECT_MAINLINE)
    assertRetail(loadInOrder({ retail, forever }), "retail")
  end,
  ["retail client, Forever file first"] = function()
    setUpClient(PROJECT_MAINLINE)
    assertRetail(loadInOrder({ forever, retail }), "retail")
  end,
  ["forever client, Retail file first"] = function()
    setUpClient(PROJECT_CAMELOT)
    assertForever(loadInOrder({ retail, forever }), "forever")
  end,
  ["forever client, Forever file first"] = function()
    setUpClient(PROJECT_CAMELOT)
    assertForever(loadInOrder({ forever, retail }), "forever")
  end,
  ["classic client gets no data from both files"] = function()
    setUpClient(PROJECT_CLASSIC)
    assertNoData(loadInOrder({ retail, forever }), "classic")
  end,
  ["forever client with only the Retail file gets no data"] = function()
    setUpClient(PROJECT_CAMELOT)
    assertNoData(loadInOrder({ retail }), "host")
  end,
  ["forever client without published data gets no data"] = function()
    setUpClient(PROJECT_CAMELOT)
    assertNoData(loadInOrder({ { foreverSource, FOREVER_FILE } }), "unpublished")
  end,
  ["forever file replaces an old copy without a client check"] = function()
    setUpClient(PROJECT_CAMELOT)
    local minor = assert(retailSource:match("local MINOR = (%d+)"))
    local old = _G.LibStub:NewLibrary("MountsRarity-2.0", tonumber(minor) - 1)
    function old:GetRarityByID() return 99 end
    assertForever(loadInOrder({ forever }), "upgrade")
  end,
  ["both files have the same structure and version"] = function()
    assertEqual(normalizedHeader(foreverSource), normalizedHeader(retailSource), "header")
    assertEqual(foreverSource:match("local MINOR = (%d+)"), retailSource:match("local MINOR = (%d+)"), "MINOR")
    assert(retailSource:find("WOW_PROJECT_ID == WOW_PROJECT_MAINLINE", 1, true), "Retail client check not found")
    assert(foreverSource:find("WOW_PROJECT_ID == WOW_PROJECT_CAMELOT", 1, true), "Forever client check not found")
  end,
}

local output = io.stdout
local failures = 0
for name, test in pairs(tests) do
  local ok, message = pcall(test)
  if ok then
    output:write("ok   - ", name, "\n")
  else
    failures = failures + 1
    output:write("FAIL - ", name, ": ", tostring(message), "\n")
  end
end

if failures > 0 then
  os.exit(1)
end
