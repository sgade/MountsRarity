# 🐴 MountsRarity

[![GitHub Release](https://img.shields.io/github/v/release/sgade/MountsRarity?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/MountsRarity/releases) [![CurseForge Game Versions](https://img.shields.io/curseforge/game-versions/918022?style=for-the-badge&logo=battledotnet)](https://www.curseforge.com/wow/addons/mountsrarity) [![CurseForge Downloads](https://img.shields.io/curseforge/dt/918022?style=for-the-badge&logo=curseforge&color=rgb(206%2C109%2C59))](https://www.curseforge.com/wow/addons/mountsrarity)

A World of Warcraft addon library that provides rarity data for mounts among the playerbase.

## 🎯 For players

Download this library addon to provide the most current database. Your addons that use this library will pick it up automatically.

The addon supports World of Warcraft Retail and World of Warcraft: Forever. Each game client only uses its own data. Forever has no rarity data yet, because Data for Azeroth does not publish it.

Internally, only the newest version of this library will be loaded and used for all addons.

### Addons using this library

- [MountJournalEnhanced](https://github.com/exochron/MountJournalEnhanced)
- [LiteMount](https://github.com/xod-wow/LiteMount)
- [Exquisite](https://www.curseforge.com/wow/addons/exquisite)
- [Master Mounts](https://www.curseforge.com/wow/addons/master-mounts-world-tour)
- ... yours?

## 🧑‍💻 For addon developers

This library can be included with the deployment of your addon.
I recommend you regularly update the version that you ship with your addon as the data is updated multiple times per week.

Players can opt into installing this addon separately to have a more recent version available as well.
Interally, only the most recent version will be loaded, regardless of where it is provided from.

Mount rarities are floating point values between `0` (no player has it) and `100` (every player has it).

### Including the library for Retail and Forever

Each game client has its own file with the same functions. `MountsRarity.lua` has the Retail data and `MountsRarity_Forever.lua` has the Forever data.

Load `MountsRarity-2.0.xml` to include both. To load only the file that the client needs, add these lines to the TOC file of your addon:

```toc
Libs\MountsRarity-2.0\MountsRarity.lua [AllowLoadGameType standard]
Libs\MountsRarity-2.0\MountsRarity_Forever.lua [AllowLoadGameType camelot][ExcludeLoadGameType standard, classic]
```

A file that loads on a different client gives no data. If your addon supports Forever and loads only `MountsRarity.lua`, it gets no rarities on Forever.

Update your included copy before you add Forever to your addon. Older copies do not check the client and give Retail data on Forever.

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

The value is `nil` if the mount is not tracked or if there is no data for the current client.

### Get all rarity data

To get the entire dataset, organized by mount id and its rarity, call `GetData()`.

```lua
local data = MountsRarity:GetData()
```

The table is empty if there is no data for the current client.

### Get the data's age

To find out when the shipped rarity data was last generated, call `GetLastUpdated()`. It returns a Unix timestamp (seconds since epoch, UTC), so you can format it yourself (e.g. with `date()`) or compare it against `time()` to show a relative age. It returns `nil` if there is no data for the current client.

```lua
local lastUpdated = MountsRarity:GetLastUpdated()
print(date("%Y-%m-%d", lastUpdated))
```

## 📊 Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).

Each day, there is a check for new data that publishes a new version with updated rarity values. This happens effectively twice a week.

The same check looks for Forever data. Data for Azeroth does not publish Forever rarity data yet. When it does, the check adds the data to `MountsRarity_Forever.lua`.

## ⚙️ Maintenance

The addon interface version in `MountsRarity.toc` is updated from Blizzard's patch CDN.
The updater reads the retail mainline product, the retail PTR/beta product and the Forever product (`wowf`), then writes all different interface versions. Retail and Forever each have their own minimum version.

Run the updater locally:

```bash
./scripts/update-interface-version.sh
```

Verify that the TOC is already current without writing changes:

```bash
./scripts/update-interface-version.sh --check
```

GitHub Actions runs the same updater every Tuesday and commits `MountsRarity.toc` when Blizzard has published a new interface version.

Update the rarity data of one client, or of all clients when you do not give an argument:

```bash
./scripts/update-rarities.sh [retail|forever]
```

Test that each client gets only its own data:

```bash
lua5.1 scripts/test-client-selection.lua
```

## ⚙️ Issues

If you find any issues with this project, feel free to raise them [here](https://github.com/sgade/MountsRarity/issues).
