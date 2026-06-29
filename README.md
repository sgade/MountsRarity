# 🐴 MountsRarity

[![GitHub Release](https://img.shields.io/github/v/release/sgade/MountsRarity?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/MountsRarity/releases) [![CurseForge Game Versions](https://img.shields.io/curseforge/game-versions/918022?style=for-the-badge&logo=battledotnet)](https://www.curseforge.com/wow/addons/mountsrarity) [![CurseForge Downloads](https://img.shields.io/curseforge/dt/918022?style=for-the-badge&logo=curseforge&color=rgb(206%2C109%2C59))](https://www.curseforge.com/wow/addons/mountsrarity)

A World of Warcraft addon library that provides rarity data for mounts among the playerbase.

## 🎯 For players

Download this library addon to provide the most current database. Your addons that use this library will pick it up automatically.

Internally, only the newest version of this library will be loaded and used for all addons.

### Addons using this library

- [MountJournalEnhanced](https://github.com/exochron/MountJournalEnhanced)
- [LiteMount](https://github.com/xod-wow/LiteMount)

## 🧑‍💻 For addon developers

This library can be included with the deployment of your addon.
I recommend you regularly update the version that you ship with your addon as the data is updated multiple times per week.

Players can opt into installing this addon separately to have a more recent version available as well.
Interally, only the most recent version will be loaded, regardless of where it is provided from.

Mount rarities are floating point values between `0` (no player has it) and `100` (every player has it).

### Loading the library

To load the library, or access an already initialized instance of it, load it as a [LibStub](https://github.com/lua-wow/LibStub/) library.

```lua
local MountsRarity = LibStub("MountsRarity-2.0")
```

### Get rarity by mount id

To get the rarity value of a mount, call `GetRarityById(mountID)`.

```lua
local mountId = 6
local rarity = MountsRarity:GetRarityByID(mountId)
```

### Get all rarity data

To get the entire dataset, organized by mount id and its rarity, call `GetData()`.

```lua
local data = MountsRarity:GetData()
```

## 📊 Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).

Each day, there is a check for new data that publishes a new version with updated rarity values. This happens effectively twice a week.

## ⚙️ Maintenance

The addon interface version in `MountsRarity.toc` is updated from Blizzard's patch CDN.
The updater reads the retail mainline product and the retail PTR/beta product, then writes both interface versions when they differ.

Run the updater locally:

```bash
./scripts/update-interface-version.sh
```

Verify that the TOC is already current without writing changes:

```bash
./scripts/update-interface-version.sh --check
```

GitHub Actions runs the same updater every Tuesday and commits `MountsRarity.toc` when Blizzard has published a new interface version.

## ⚙️ Issues

If you find any issues with this project, feel free to raise them [here](https://github.com/sgade/MountsRarity/issues).
