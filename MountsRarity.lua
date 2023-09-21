---@class MountsRarity: { GetData: function, GetRarityByID: function }
local MountsRarity = LibStub:NewLibrary("MountsRarity-2.0", 1)
-- TODO: automatically upgrade the minor version on changes
if not MountsRarity then print("no") return end -- already loaded and no upgrade necessary

local _, namespace = ...

function MountsRarity:GetData()
  ---@type table<number, number|nil>
  return namespace.data
end

---Returns the rarity of a mount (0-100) by ID, or `nil`.
---@param mountID number The mount ID.
function MountsRarity:GetRarityByID(mountID)
  return self:GetData()[mountID]
end
