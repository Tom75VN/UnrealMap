<p align="center">
  <img src="https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/logo.png" alt="Unreal Map logo" width="160">
</p>

<h1 align="center">Unreal Map</h1>

<p align="center">
  <b>See Azeroth in high definition.</b><br>
  Sharper world, dungeon and raid maps for World of Warcraft 1.12 (vanilla).
</p>

<p align="center">
  <a href="https://github.com/Tom75VN/UnrealMap/releases/latest"><b>⬇ Download the latest release</b></a>
</p>

- **Exclusive HD world maps, available only in Unreal Map**: created for this
  addon and found nowhere else
- **2x resolution** for every zone, capital, battleground and continent
- **19 dungeons and 7 raids** in HD, every floor included
- **Nothing moves**: labels, icons, coordinates and clicks stay in place
- **Low memory**: nothing loads at login, only the map you open
- **Optional fog-of-war removal** in one click
- **Install and play**: no setup needed

![Dustwallow Marsh, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/01-dustwallow-marsh-hd-vs-native.jpg)

![Stormwind, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/08-stormwind-hd-vs-native.jpg)

## Why Unreal Map

The original maps were drawn for screens from 2004. On a modern display they
look blurry and washed out. Unreal Map swaps them for sharp, richly colored
artwork at twice the resolution, while everything you rely on stays exactly
where it was: labels, quest and town icons, your player arrow, coordinates,
click areas, zoom and controls.

## Features

### Exclusive HD world maps

Every world map was generated specifically for Unreal Map at twice the native
resolution, then carefully lined up with the game's own map, so labels and
map icons sit exactly where you expect them.

- **40 zones**: all of Eastern Kingdoms and Kalimdor, from Elwynn Forest and
  Durotar to Silithus and Winterspring, including the explored areas you
  uncover as you travel.
- **6 capitals**: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff
  and Undercity.
- **3 battlegrounds**: Alterac Valley, Arathi Basin and Warsong Gulch.
- **3 continent views**: the world map, Eastern Kingdoms and Kalimdor.

### HD dungeon and raid maps

Find your way through every classic instance. The right map opens
automatically when you are inside, on English, Russian and Chinese clients,
and you can also pick one by hand.

- **19 dungeons, 55 maps** including every floor and entrance: Ragefire
  Chasm, The Deadmines, Wailing Caverns, Shadowfang Keep, The Stockade,
  Blackfathom Deeps, Gnomeregan, Razorfen Kraul, Razorfen Downs, Scarlet
  Monastery, Uldaman, Zul'Farrak, Maraudon, the Sunken Temple, Blackrock
  Depths, Blackrock Spire, Dire Maul, Scholomance and Stratholme.
- **7 raids, 13 maps**: Molten Core, Onyxia's Lair, Blackwing Lair,
  Zul'Gurub, Ruins of Ahn'Qiraj, Temple of Ahn'Qiraj and Naxxramas.

### Low memory use

Better visuals without weighing down your game.

- Nothing is loaded at login: no impact on loading time or memory until you
  open the map.
- HD textures are loaded only while the map is open, and only for the map you
  are looking at.
- A single fixed set of texture slots is reused for every map, so the addon
  does not grow as you browse from map to map.
- Compressed textures with mipmaps; only the files the game actually uses are
  shipped.

### Simple options

- Remove the fog of war to see the unexplored areas of every zone.
- Minimap button for quick access to the settings (can be hidden).
- Available in English, Russian and Chinese, with a language picker.
- Fits into unrealUI's settings window when unrealUI is installed, and works
  fully on its own otherwise.

## Screenshots

**Eastern Plaguelands**

![Eastern Plaguelands, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/02-eastern-plaguelands-hd-vs-native.jpg)

**Stranglethorn Vale**

![Stranglethorn Vale, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/03-stranglethorn-hd-vs-native.jpg)

**Warsong Gulch**

![Warsong Gulch, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/04-warsong-gulch-hd-vs-native.jpg)

**Stonetalon Mountains**

![Stonetalon Mountains, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/05-stonetalon-mountains-hd-vs-native.jpg)

**Elwynn Forest**

![Elwynn Forest, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/06-elwynn-hd-vs-native.jpg)

**Orgrimmar**

![Orgrimmar, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/07-orgrimmar-hd-vs-native.jpg)

**Dungeon: Ragefire Chasm**

![Ragefire Chasm, HD map](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/09-dungeon-ragefire-chasm-hd.jpg)

**Raid: Molten Core**

![Molten Core, HD map](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/10-raid-molten-core-hd.jpg)

## Installation

Install from the Emberveil launcher: add **unrealMap**, then its data packs.
Each data pack is its own launcher entry.

| Data pack | Maps | |
| --- | --- | --- |
| `unrealMap_World` | Zones, continents, capitals and battlegrounds | Required |
| `unrealMap_Unexplored` | Themed unexplored zones, shown while fog of war is kept (more zones coming) | Optional |
| `unrealMap_Instances` | Dungeons and raids | Optional |

A map whose data pack is missing stays in standard definition, and the chat
names the pack to install.

Manual install: [download the latest release](https://github.com/Tom75VN/UnrealMap/releases/latest)
and extract each archive into `Interface/AddOns/`, so the folders are
`Interface/AddOns/unrealMap/`, `Interface/AddOns/unrealMap_World/`, and so on.
Keep the folder names exactly as they are, then restart the game client.

## Commands

| Command | Effect |
| --- | --- |
| `/umap` | Open the settings |
| `/umap fog on` / `/umap fog off` | Remove or restore the fog of war |
| `/umap minimap` | Show or hide the minimap button |
| `/umap dungeon <map>` / `/umap dungeon off` | Choose the dungeon map manually, or return to automatic |
| `/umap raid <map>` / `/umap raid off` | Choose the raid map manually, or return to automatic |

The world map cannot be used while typing commands: close it first.

## Credits

- Author: Thomas.
- Dungeon and raid map artwork: Turtle WoW.
- World of Warcraft is a trademark of Blizzard Entertainment. This project is
  not affiliated with or endorsed by Blizzard Entertainment.
