# MountsRarity

World of Warcraft addon that provides rarity data of mounts among the playerbase.

## Accessing the data

Mount data can be accessed in other addons using the global `MountsRarityAddon.MountsRarity`.
It is a table with the key being the mountID (type `string`) and the percentage of players owning that mount (type `number`) from `0` to `100`.

Example:

```lua
MountsRarityAddon.MountsRarity = {
  ["6"] = 64.29413294823611,
  ["9"] = 67.45575717348211,
  ["11"] = 66.22915676267188,
  ["14"] = 66.21875196211218,
  ["17"] = 0.59227533254999,
  ...
}
```

## Data source

The data source for the rarity data is [Data for Azeroth](https://www.dataforazeroth.com/collections/mounts).
