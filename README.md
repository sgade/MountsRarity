# MountsRarity

Provides rarity data for mounts among the playerbase.

## For players

Download this library addon to provide the most current database. Your addons that use this library will pick it up automatically.

Internally, only the newest version of this library will be loaded and used for all addons.

### Addons using this library

- [MountJournalEnhanced](https://github.com/exochron/MountJournalEnhanced)
- [LiteMount](https://github.com/xod-wow/LiteMount)

## For addon developers

This library can be included with the deployment of your addon.

Interally, only the most recent version will be loaded, regardless of where it is provided from.
Players can opt into installing this addon separately to have a more recent version available as well.

### Accessing the data

Mount data can be accessed as a [LibStub](https://github.com/lua-wow/LibStub/) library.
Use the functions `GetData()` and `GetRarityByID(mountID)` to get to the actual rarity data. The rarity is defined as a number from `0` (no player has it) to `100` (every player has it).

Example:

```lua
local MountsRarity = LibStub("MountsRarity-2.0")
local rarity = MountsRarity:GetRarityByID(6)
```

## Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).

## Issues

If you find any issues with this project, feel free to raise them [here](https://github.com/sgade/MountsRarity/issues).
