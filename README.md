<p align="center">
  <img src="https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/logo.png" alt="Unreal Map logo" width="160">
</p>

<h1 align="center">Unreal Map</h1>

High-definition world, dungeon and raid maps for World of Warcraft 1.12
(vanilla) clients.

Unreal Map replaces the map textures with sharper, twice-resolution artwork
while keeping everything else exactly where it was: labels, icons, player
arrow, coordinates, click areas, zoom and controls are untouched.

![Dustwallow Marsh and Eastern Plaguelands, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/01-dustwallow-eastern-plaguelands-hd-vs-native.jpg)

## Features

### Exclusive HD world maps

Generated specifically for this addon from full-zone masters at twice the
native resolution, then registered on the game's own map so nothing shifts.

- **40 zones**: every Eastern Kingdoms and Kalimdor zone, from Elwynn Forest
  and Durotar to Silithus and Winterspring, with HD base tiles and HD
  exploration overlays.
- **6 capitals**: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff
  and Undercity.
- **3 battlegrounds**: Alterac Valley, Arathi Basin and Warsong Gulch.
- **3 continent views**: the world map, Eastern Kingdoms and Kalimdor.

### HD dungeon and raid maps

HD maps for the original vanilla instances, from Turtle WoW's map artwork.
The correct map is picked automatically from the instance name (English,
Russian or Chinese clients) and can also be chosen by hand.

- **19 dungeons, 55 maps** including every floor and entrance: Ragefire
  Chasm, The Deadmines, Wailing Caverns, Shadowfang Keep, The Stockade,
  Blackfathom Deeps, Gnomeregan, Razorfen Kraul, Razorfen Downs, Scarlet
  Monastery, Uldaman, Zul'Farrak, Maraudon, the Sunken Temple, Blackrock
  Depths, Blackrock Spire, Dire Maul, Scholomance and Stratholme.
- **7 raids, 13 maps**: Molten Core, Onyxia's Lair, Blackwing Lair,
  Zul'Gurub, Ruins of Ahn'Qiraj, Temple of Ahn'Qiraj and Naxxramas.

### Options

- Optional fog-of-war removal: show the unexplored areas of every zone.
- Minimap button to open the settings (can be hidden).
- English, Russian and Chinese translations, with a language picker.
- Integrates into unrealUI's settings window when unrealUI is installed;
  works fully on its own otherwise. Neither addon requires the other.

### Lightweight

- Nothing is loaded at login. HD textures are loaded only while the map is
  open, and only for the map you are looking at.
- A single fixed set of texture slots is reused for every map, so memory does
  not grow as you browse.
- Compressed textures with mipmaps; only the files the game actually uses are
  shipped.

## Screenshots

**Stranglethorn Vale and Warsong Gulch**

![Stranglethorn Vale and Warsong Gulch, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/02-stranglethorn-warsong-gulch-hd-vs-native.jpg)

**Stonetalon Mountains and Elwynn Forest**

![Stonetalon Mountains and Elwynn Forest, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/03-stonetalon-elwynn-hd-vs-native.jpg)

**Orgrimmar and Stormwind**

![Orgrimmar and Stormwind, HD vs native](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/04-orgrimmar-stormwind-hd-vs-native.jpg)

**Dungeon: The Deadmines**

![The Deadmines HD map](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/05-dungeon-the-deadmines-hd.jpg)

**Raid: Molten Core**

![Molten Core HD map](https://raw.githubusercontent.com/Tom75VN/UnrealMap/readme-assets/06-raid-molten-core-hd.jpg)

## Installation

1. Download the latest release.
2. Extract it into `Interface/AddOns/` so the folder is
   `Interface/AddOns/unrealMap/` (the folder must be named exactly
   `unrealMap`).
3. Restart the game client.

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
