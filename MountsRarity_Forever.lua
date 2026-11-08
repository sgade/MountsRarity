--[[----------------------------------------------------------------------------

  MountsRarity/MountsRarity_Forever.lua
  Provides rarity data for mounts among the playerbase.

  Copyright (c) 2023 Sören Gade

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.

----------------------------------------------------------------------------]]--

---@alias MountsRarity.RarityData table<number, number> Mount ID to rarity percentage (0-100) mapping.

-- This build version gets automatically updated to the current UTC date and time (YYYYMMDDHHMM).
-- Using a timestamp instead of e.g. a CI run number keeps this reproducible across forks and git hosts.
local MINOR = 202611080622
-- This data is only valid for one game client. Host addons can load this file on any client,
-- so it registers at version 0 on other clients. The library is then available without data,
-- and the file for the current client always replaces it.
local IS_MATCHING_CLIENT = WOW_PROJECT_ID == WOW_PROJECT_CAMELOT
---@class MountsRarity
local MountsRarity = LibStub:NewLibrary("MountsRarity-2.0", IS_MATCHING_CLIENT and MINOR or 0)
if not MountsRarity then return end -- already loaded and no upgrade necessary

-- The UTC time this data was last generated, as a Unix timestamp (seconds since epoch).
-- Gets automatically updated whenever the data changes. 0 means that there is no data.
local LAST_UPDATED = 0

---@type fun(): MountsRarity.RarityData
local lazyLoadData = function()
  return {}
end
---@type MountsRarity.RarityData?
local data

---Returns the rarity data, organized by mount ID. Lazily parses the data on first call.
---@return MountsRarity.RarityData data
function MountsRarity:GetData()
  if not data then
    --@debug@
    local debugParseStartTime = debugprofilestop()
    local debugMemBefore = collectgarbage("count")
    --@end-debug@
    data = IS_MATCHING_CLIENT and lazyLoadData() or {}

    --@debug@
    local debugCount = 0
    for _ in pairs(data) do
      debugCount = debugCount + 1
    end
    local debugMemAfter = collectgarbage("count")
    print(("MountsRarity: Parsed %d entries in %.3fms (%.1fKB -> %.1fKB, +%.1fKB)"):format(
    debugCount, debugprofilestop() - debugParseStartTime, debugMemBefore, debugMemAfter, debugMemAfter - debugMemBefore))
    --@end-debug@
  end

  return data
end

---Returns the rarity of a mount (0-100) by ID, or `nil` if this mount is not tracked.
---@param mountID number The mount ID.
---@return number|nil rarity The rarity percentage (0-100), or `nil` if unknown.
function MountsRarity:GetRarityByID(mountID)
  return self:GetData()[mountID]
end

---Returns the UTC time this library's data was last generated, as a Unix timestamp
---(seconds since epoch). Pass it to `date()` for formatting, or compare it against
---`time()` to derive a relative age.
---@return number|nil timestamp Unix timestamp (seconds since epoch, UTC), or `nil` if there is no data for this client.
function MountsRarity:GetLastUpdated()
  if not IS_MATCHING_CLIENT or LAST_UPDATED == 0 then
    return nil
  end

  return LAST_UPDATED
end

-- Everything after this line gets automatically replaced and updated.
lazyLoadData = function() return {
} end
