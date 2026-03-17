--[[----------------------------------------------------------------------------

  MountsRarity/MountsRarity.lua
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

-- This build version gets automatically updated.
local MINOR = 935
---@class MountsRarity: { GetData: function, GetRarityByID: function }
local MountsRarity = LibStub:NewLibrary("MountsRarity-2.0", MINOR)
if not MountsRarity then return end -- already loaded and no upgrade necessary

local lazyLoadData = function()
  return {}
end
local data

function MountsRarity:GetData()
  if not data then
    data = lazyLoadData()
    --@debug@
    print("MountsRarity: Loaded.")
    --@end-debug@
  end

  ---@type table<number, number|nil>
  return data
end

---Returns the rarity of a mount (0-100) by ID, or `nil`.
---@param mountID number The mount ID.
function MountsRarity:GetRarityByID(mountID)
  return self:GetData()[mountID]
end

-- Everything after this line gets automatically replaced and updated.
lazyLoadData = function() return {
} end
