# MountsRarity

World of Warcraft addon that provides rarity data of mounts among the playerbase.

## Accessing the data

Mount data can be accessed in other addons as a `LibStub` library.
Use the functions `GetData()` and `GetRarityByID(mountID)` to get to the actual rarity data. The rarity is defined as a number from `0` (no player has it) to `100` (every player has it).

Example:

```lua
local MountsRarity = LibStub("MountsRarity-2.0")
local rarity = MountsRarity:GetRarityByID(6)
```

## Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).
