# 🐴 MountsRarity

[![GitHub Release](https://img.shields.io/github/v/release/sgade/MountsRarity?sort=semver&display_name=release&style=for-the-badge&logo=github&color=rgb(20%2C4%2C120))](https://github.com/sgade/MountsRarity/releases) [![CurseForge Game Versions](https://img.shields.io/curseforge/game-versions/918022?style=for-the-badge&logo=battledotnet)](https://www.curseforge.com/wow/addons/mountsrarity) [![CurseForge Downloads](https://img.shields.io/curseforge/dt/918022?style=for-the-badge&logo=curseforge&color=rgb(206%2C109%2C59))](https://www.curseforge.com/wow/addons/mountsrarity)

A World of Warcraft addon library that provides rarity data for mounts among the playerbase.

## 🎯 For players

Download this library addon to provide the most current database. Your addons that use this library will pick it up automatically.

The addon supports World of Warcraft Retail and World of Warcraft: Forever. Each game client only uses its own data.

Internally, only the newest version of this library will be loaded and used for all addons, regardless of where it is provided from.

### Addons using this library

- [Mount Journal Enhanced](https://www.curseforge.com/wow/addons/mount-journal-enhanced)
- [LiteMount](https://www.curseforge.com/wow/addons/litemount)
- [Exquisite](https://www.curseforge.com/wow/addons/exquisite)
- [Master Mounts - World Tour](https://www.curseforge.com/wow/addons/master-mounts-world-tour)
- [MountCollector](https://www.curseforge.com/wow/addons/mountcollector)
- [MountTrail](https://www.curseforge.com/wow/addons/mounttrail)
- [Mount Buff Info](https://www.curseforge.com/wow/addons/mount-buff-info)
- ... yours?

## 🧑‍💻 For addon developers

This library can be included with the deployment of your addon.
I recommend you regularly update the version that you ship with your addon as the data is updated multiple times per week.

Players can opt into installing this addon separately to have a more recent version available as well.

Mount rarities are floating point values between `0` (no player has it) and `100` (every player has it).

### Retail, Forever and other game clients

`MountsRarity.lua` contains the data of all supported game clients. When it loads, it selects the data of the current client:

- Retail: Retail data.
- Forever: Forever data.
- Other clients, for example Classic: no data and no error. `GetData()` returns an empty table, and `GetRarityByID()` and `GetLastUpdated()` return `nil`.

To add Forever to your addon, you do not have to change how you include the library. If the line in your TOC file has a game type condition, permit Forever (`[AllowLoadGameType standard, camelot]`).

Update your included copy before you add Forever to your addon. Older copies do not check the client and give Retail data on Forever.

### Loading the library

To load the library, or access an already initialized instance of it, load it as a [LibStub](https://github.com/lua-wow/LibStub/) library.

```lua
local MountsRarity = LibStub("MountsRarity-2.0")
```

### Get rarity by mount id

To get the rarity value of a mount, call `GetRarityByID(mountID)`.

```lua
local mountId = 6
local rarity = MountsRarity:GetRarityByID(mountId)
```

The value is `nil` if the mount is not tracked.

### Get all rarity data

To get the entire dataset, organized by mount id and its rarity, call `GetData()`.

```lua
local data = MountsRarity:GetData()
```

### Get the data's age

To find out when the shipped rarity data was last generated, call `GetLastUpdated()`. It returns a Unix timestamp (seconds since epoch, UTC), so you can format it yourself (e.g. with `date()`) or compare it against `time()` to show a relative age.

```lua
local lastUpdated = MountsRarity:GetLastUpdated()
print(date("%Y-%m-%d", lastUpdated))
```

## 📊 Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).

Every Thursday and Sunday, a check for new data occurs. If the data changed, the check publishes a new version with updated rarity values.

The same check updates the Retail data and the Forever data. Each client has its own data block in `MountsRarity.lua`.

## ⚙️ Maintenance

The addon interface version in `MountsRarity.toc` is updated from Blizzard's patch CDN.
The updater reads the retail mainline product, the retail PTR and beta products and the Forever product (`wowf`), then writes all different interface versions. Retail and Forever each have their own minimum version.

Run the updater locally:

```bash
./scripts/update-interface-version.sh
```

Verify that the TOC is already current without writing changes:

```bash
./scripts/update-interface-version.sh --check
```

GitHub Actions runs the same updater every Tuesday and commits `MountsRarity.toc` when Blizzard has published a new interface version.

Update the rarity data of one client, or of all clients when you do not give an argument. When the data of a client changes, the updater also sets the version (`MINOR`) to the current UTC date and time:

```bash
./scripts/update-rarities.sh [all|retail|forever]
```

## 🐞 Issues

If you find any issues with this project, feel free to raise them [here](https://github.com/sgade/MountsRarity/issues).
