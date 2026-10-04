"""Native world-map layout and zone-master catalog shared by asset tools."""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MEDIA_DIR = ROOT / "Media" / "Textures" / "Maps"
SOURCES_DIR = Path(r"C:\Games\Azeroth Launcher\unrealMap-sources")
QA_DIR = Path(r"C:\Games\Azeroth Launcher\diagnostics\unrealmap-qa")
NATIVE_REFERENCE_DIR = Path(
    r"D:\Development\unrealUI_data\wowclassic_illus_maps\WoW Classic Maps\Sprite assets")
NATIVE_WORLD_DIR = Path(
    r"D:\Development\unrealUI_data\mpqeditor_en_v3.6.0.868\x64\Work\Interface\WorldMap\World")
NATIVE_MAP_ROOT = NATIVE_WORLD_DIR.parent
ZONE_MASTER_ROOT = Path(r"D:\Development\unrealUI_data\#Maps\zones")
ZONE_UNEXPLORED_MASTER_ROOT = MEDIA_DIR / "World" / "_Unexplored"

ZONE_SOURCES = {
    "Alterac": "Alterac.png",
    "Arathi": "arathi.png",
    "Ashenvale": "Ashenvale.png",
    "Aszhara": "azshara.png",
    "Badlands": "Badlands.png",
    "Barrens": "Barren.png",
    "BlastedLands": "BlastedLands.png",
    "BurningSteppes": "BurningSteppes.png",
    "Darkshore": "darkshore.png",
    "DeadwindPass": "deadwindpass.png",
    "Desolace": "Desolace.png",
    "DunMorogh": "DunMorogh.png",
    "Durotar": "durotar.png",
    "Duskwood": "duskwood.png",
    "Dustwallow": "dustwallowmarsh.png",
    "EasternPlaguelands": "Eastern_Plaguelands.png",
    "Elwynn": "elwynn.png",
    "Felwood": "felwood.png",
    "Feralas": "Feralas.png",
    "Hilsbrad": "Hillsbrad.png",
    "Hinterlands": "Hinterlands.png",
    "LochModan": "LochModan.png",
    "Moonglade": "Moonglade.png",
    "Mulgore": "mulgore.png",
    "Redridge": "redbridge.png",
    "SearingGorge": "SearingGorge.png",
    "Silithus": "Silithus.png",
    "Silverpine": "silverpine.png",
    "StonetalonMountains": "Stonetalon_Mountains.png",
    "Stranglethorn": "Stranglethorn.png",
    "SwampOfSorrows": "swamp_of_sorrows.png",
    "Tanaris": "Tanaris.png",
    "Teldrassil": "Teldrassil.png",
    "ThousandNeedles": "Thousandneedles.png",
    "Tirisfal": "Tirisfal.png",
    "UngoroCrater": "UngoroCrater.png",
    "WesternPlaguelands": "WesternPlaguelands.png",
    "Westfall": "Westfall.png",
    "Wetlands": "Wetlands.png",
    "Winterspring": "Winterspring.png",
}

ZONE_UNEXPLORED_SOURCES = {
    "Elwynn": "Elwynn.png",
}

NON_ZONE_CATEGORIES = {
    "AlteracValley": "Battlegrounds",
    "ArathiBasin": "Battlegrounds",
    "World": "Continents",
    "Kalimdor": "Continents",
    "Azeroth": "Continents",
    "Darnassis": "Capitals",
    "Ironforge": "Capitals",
    "Ogrimmar": "Capitals",
    "Stormwind": "Capitals",
    "ThunderBluff": "Capitals",
    "Undercity": "Capitals",
    "WarsongGulch": "Battlegrounds",
}


def normalized(value):
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def directory_by_name(root, name):
    target = name.casefold()
    return next((path for path in root.iterdir()
                 if path.is_dir() and path.name.casefold() == target), None)


def native_stems(map_name):
    folder = directory_by_name(NATIVE_REFERENCE_DIR, map_name)
    result = {}
    if folder:
        for path in folder.glob("*.png"):
            match = re.match(r"^(.*?)(\d+)$", path.stem)
            if match:
                result.setdefault(normalized(match.group(1)), match.group(1))
    return result


def canonical_stem(raw, stems):
    key = normalized(raw)
    if key in stems:
        return stems[key]
    alternate = key[3:] if key.startswith("THE") else "THE" + key
    return stems.get(alternate, raw)


def load_overlays():
    text = (ROOT / "MapOverlayData.lua").read_text(encoding="utf-8")
    blocks = {match.group(1): re.findall(r'"([^"]+)"', match.group(2))
              for match in re.finditer(r"^  (\w+) = \{(.*?)^  \},", text,
                                       re.MULTILINE | re.DOTALL)}
    result = {}
    for map_name in ZONE_SOURCES:
        stems = native_stems(map_name)
        overlays = []
        for encoded in blocks[map_name]:
            raw, width, height, x, y = encoded.split(":")
            overlays.append((canonical_stem(raw, stems), int(width), int(height),
                             int(x), int(y)))
        result[map_name] = overlays
    result.update({name: [] for name in NON_ZONE_CATEGORIES})
    return result


OVERLAYS = load_overlays()
MAP_CATEGORIES = {name: "World" for name in ZONE_SOURCES}
MAP_CATEGORIES.update(NON_ZONE_CATEGORIES)
SOURCE_SCALE = {"Barrens": 4}
SOURCE_DIRS = {}


def source_scale(map_name):
    return SOURCE_SCALE.get(map_name, 2)


def runtime_dir(map_name):
    return MEDIA_DIR / MAP_CATEGORIES[map_name] / map_name


def runtime_base_dir(map_name):
    if map_name in ZONE_UNEXPLORED_SOURCES:
        return ZONE_UNEXPLORED_MASTER_ROOT / map_name
    return runtime_dir(map_name)


# The client resolves addon texture paths by basename alone (probe
# mapbasename.v1), so overlay stems shared with another shipped file carry
# their map name on disk. Keep in sync with OVERLAY_FILE_PREFIXED in unrealMap.lua.
RUNTIME_PREFIXED = {
    "BlastedLands": {"AltarOfStorms"},
    "BurningSteppes": {"AltarOfStorms"},
    "DunMorogh": {"Ironforge"},
    "EasternPlaguelands": {"ThondrorilRiver"},
    "Elwynn": {"Stormwind"},
    "Mulgore": {"Thunderbluff"},
    "WesternPlaguelands": {"ThondrorilRiver"},
}


def runtime_stem(map_name, name):
    """Runtime file stem for a native overlay piece name."""
    if name.rstrip("0123456789") in RUNTIME_PREFIXED.get(map_name, ()):
        return map_name + name
    return name


def runtime_file(map_name, name):
    return runtime_dir(map_name) / f"{runtime_stem(map_name, name)}.blp"


def source_dir(map_name):
    return SOURCE_DIRS.get(map_name, SOURCES_DIR / map_name / "supplied-blp")


def zone_master(map_name):
    return ZONE_MASTER_ROOT / ZONE_SOURCES[map_name]


def zone_unexplored_master(map_name):
    filename = ZONE_UNEXPLORED_SOURCES.get(map_name)
    return ZONE_UNEXPLORED_MASTER_ROOT / map_name / filename if filename else None


def native_dir(map_name):
    folder = directory_by_name(NATIVE_REFERENCE_DIR, map_name)
    if folder is None:
        raise RuntimeError(f"Missing native reference directory: {map_name}")
    return folder


def native_base_dir(map_name):
    if map_name == "World":
        return NATIVE_WORLD_DIR
    if NON_ZONE_CATEGORIES.get(map_name) == "Battlegrounds":
        return NATIVE_MAP_ROOT / map_name
    return native_dir(map_name)


def native_file_size(value):
    if value >= 256:
        return 256
    size = 16
    while size < value:
        size *= 2
    return size


def pieces(overlay):
    """Return [(pieceName, width, height, x, y)] for one overlay tuple."""
    name, width, height, x, y = overlay
    wide, tall = -(-width // 256), -(-height // 256)
    result = []
    for row in range(tall):
        piece_height = 256 if row < tall - 1 else height - 256 * row
        for column in range(wide):
            piece_width = 256 if column < wide - 1 else width - 256 * column
            result.append((f"{name}{row * wide + column + 1}", piece_width, piece_height,
                           x + 256 * column, y + 256 * row))
    return result


def geometry(map_name):
    return [piece for overlay in OVERLAYS[map_name] for piece in pieces(overlay)]
