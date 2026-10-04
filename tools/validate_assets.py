"""Validate the shipped map BLPs against the manifest and native layout.

For every map in map_geometry.OVERLAYS: the runtime base and overlay folders
must contain exactly the 12 base tiles, the highlight texture and the
manifest's exploration files; every file must be BLP2 DXT5 with in-bounds
mips; base tiles must be 512x512 and overlay pieces exactly 2x their native file size.
Writes a stitched base preview per map to QA_DIR (outside the addon).
"""

import json
import re
import sys
from pathlib import Path

from PIL import Image

from map_geometry import (MEDIA_DIR, OVERLAYS, QA_DIR, ROOT, RUNTIME_PREFIXED, ZONE_SOURCES,
                          geometry, native_base_dir, native_dir, native_file_size,
                          runtime_base_dir, runtime_dir, runtime_file)

TILE_SIZE = (512, 512)
GRID = (4, 3)
VISIBLE_SIZE = (2004, 1336)
DUNGEON_DIR = MEDIA_DIR / "Dungeons"
RAID_DIR = MEDIA_DIR / "Raids"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_blp(blp_path):
    data = blp_path.read_bytes()
    header = data[:148]
    require(header[:4] == b"BLP2", f"Unexpected signature: {blp_path}")
    require(header[8:12] == bytes((2, 8, 7, 1)),
            f"Unexpected BLP2 encoding: {blp_path} {tuple(header[8:12])}")
    width = int.from_bytes(header[12:16], "little")
    height = int.from_bytes(header[16:20], "little")
    require(width > 0 and height > 0, f"Invalid dimensions: {blp_path}")
    mip_levels = 0
    for level in range(16):
        offset = int.from_bytes(header[20 + level * 4:24 + level * 4], "little")
        size = int.from_bytes(header[84 + level * 4:88 + level * 4], "little")
        if offset and size:
            require(offset + size <= len(data), f"Mip outside file: {blp_path} level {level}")
            mip_levels += 1
    require(mip_levels > 0, f"No mip payloads: {blp_path}")
    with Image.open(blp_path) as source:
        image = source.convert("RGBA")
    require(image.size == (width, height),
            f"Header/decoder size mismatch: {blp_path} {(width, height)} {image.size}")
    return image


def exploration_files(manifest, map_name):
    # City maps have no exploration asset.
    exploration = next((asset for asset in manifest["assets"]
                        if asset["id"] == f"world.{map_name.lower()}.exploration"), None)
    return set(exploration["files"]) if exploration else set()


def validate_map(map_name, manifest):
    base_folder = runtime_base_dir(map_name)
    overlay_folder = runtime_dir(map_name)
    expected_base = {f"{map_name}{index}.blp" for index in range(1, 13)}
    expected_overlays = {runtime_file(map_name, name).name
                         for name in exploration_files(manifest, map_name)}
    if base_folder == overlay_folder:
        expected = expected_base | expected_overlays
        actual = {path.name for path in base_folder.glob("*.blp")}
        require(actual == expected, f"{map_name} BLP inventory mismatch: "
                f"missing={sorted(expected - actual)}, "
                f"unexpected={sorted(actual - expected)}")
    else:
        actual_base = {path.name for path in base_folder.glob("*.blp")}
        actual_overlays = {path.name for path in overlay_folder.glob("*.blp")}
        require(actual_base == expected_base, f"{map_name} base BLP inventory mismatch: "
                f"missing={sorted(expected_base - actual_base)}, "
                f"unexpected={sorted(actual_base - expected_base)}")
        require(actual_overlays == expected_overlays,
                f"{map_name} overlay BLP inventory mismatch: "
                f"missing={sorted(expected_overlays - actual_overlays)}, "
                f"unexpected={sorted(actual_overlays - expected_overlays)}")
        expected = expected_base | expected_overlays

    images = {name: read_blp(base_folder / name) for name in sorted(expected_base)}
    images.update({name: read_blp(overlay_folder / name)
                   for name in sorted(expected_overlays)})
    base = next(asset for asset in manifest["assets"]
                if asset["id"] == f"world.{map_name.lower()}.base")
    exploration = next((asset for asset in manifest["assets"]
                        if asset["id"] == f"world.{map_name.lower()}.exploration"), None)
    paired = exploration and exploration.get("activeMasterImport", {}).get(
        "unexploredMaster")
    if paired:
        declared = base["master"]
        require(declared["root"] == paired["root"] and
                declared["file"] == paired["file"],
                f"{map_name}: base and declared unexplored master differ")
        source_root = Path(paired["root"])
        if not source_root.is_absolute():
            source_root = ROOT / source_root
        path = source_root / paired["file"]
        require(path.is_file(), f"{map_name}: missing unexplored master {path}")
        with Image.open(path) as image:
            require(image.size == (paired["width"], paired["height"]),
                    f"{map_name}: unexplored master dimensions differ from manifest")
        require(exploration["activeMasterImport"].get("nativeRGBFallback") is False,
                f"{map_name}: paired unexplored master must disable native RGB fallback")
    declared_suppressions = base["runtime"].get("transparentOverlaySuppressions")
    if declared_suppressions is not None:
        suppressions = set(declared_suppressions)
        require(suppressions == exploration_files(manifest, map_name),
                f"{map_name}: transparent suppressions differ from exploration inventory")
        for name in suppressions:
            with Image.open(native_base_dir(map_name) / f"{name}.blp") as native:
                require(images[f"{name}.blp"].size == native.size,
                        f"{map_name}/{name}: suppression dimensions differ from native path")
            require(images[f"{name}.blp"].getchannel("A").getextrema() == (0, 0),
                    f"{map_name}/{name}: suppression is not fully transparent")
    for name, width, height, _, _ in geometry(map_name):
        file_name = runtime_file(map_name, name).name
        if file_name in images:
            size = (native_file_size(width) * 2, native_file_size(height) * 2)
            require(images[file_name].size == size,
                    f"{file_name}: {images[file_name].size}, expected {size}")

    preview = Image.new("RGBA", (TILE_SIZE[0] * GRID[0], TILE_SIZE[1] * GRID[1]),
                        (24, 24, 24, 255))
    for index in range(1, 13):
        tile = images[f"{map_name}{index}.blp"]
        require(tile.size == TILE_SIZE, f"Unexpected base tile size: {map_name}{index} {tile.size}")
        preview.alpha_composite(tile, (((index - 1) % GRID[0]) * TILE_SIZE[0],
                                       ((index - 1) // GRID[0]) * TILE_SIZE[1]))
    QA_DIR.mkdir(parents=True, exist_ok=True)
    path = QA_DIR / f"{map_name.lower()}-base-preview.png"
    preview.crop((0, 0, *VISIBLE_SIZE)).convert("RGB").save(
        path, format="PNG", optimize=False)
    return len(expected), path


def validate_unique_basenames():
    # The client resolves addon texture paths by basename alone (probe
    # mapbasename.v1): two shipped files with one basename draw the same image.
    seen = {}
    for path in MEDIA_DIR.rglob("*"):
        if path.is_file():
            key = path.stem.lower()
            require(key not in seen, f"Duplicate runtime basename: {seen.get(key)} and {path}")
            seen[key] = path


def validate_dungeons(manifest):
    catalog_path = ROOT / "assets" / "dungeon_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    declared = next((asset for asset in manifest["assets"]
                     if asset["id"] == "world.vanilla-dungeons.base"), None)
    require(declared is not None, "Dungeon asset declaration missing from manifest")
    require(declared.get("catalog") == "assets/dungeon_catalog.json",
            "Dungeon manifest does not reference the authoritative catalog")

    map_names = []
    for dungeon in catalog["dungeons"]:
        require(dungeon["defaultMap"] in dungeon["maps"],
                f"{dungeon['id']}: default map is not in its map inventory")
        map_names.extend(dungeon["maps"])
    require(len(map_names) == len(set(map_names)), "Duplicate dungeon map key in catalog")
    require(not any(name.lower().startswith("turtle_") for name in map_names),
            "Custom Turtle WoW dungeon map included in Vanilla catalog")

    actual_folders = {path.name for path in DUNGEON_DIR.iterdir() if path.is_dir()}
    expected_folders = set(map_names)
    require(actual_folders == expected_folders,
            "Dungeon folder inventory mismatch: "
            f"missing={sorted(expected_folders - actual_folders)}, "
            f"unexpected={sorted(actual_folders - expected_folders)}")

    for map_name in map_names:
        folder = DUNGEON_DIR / map_name
        expected = {f"Dungeon{map_name}{index}.blp" for index in range(1, 13)}
        actual = {path.name for path in folder.iterdir() if path.is_file()}
        require(actual == expected, f"{map_name} dungeon BLP inventory mismatch: "
                f"missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}")
        images = [read_blp(folder / f"Dungeon{map_name}{index}.blp")
                  for index in range(1, 13)]
        require(all(image.size == TILE_SIZE for image in images),
                f"{map_name}: one or more dungeon tiles are not 512x512")

        preview = Image.new("RGBA", (TILE_SIZE[0] * GRID[0], TILE_SIZE[1] * GRID[1]),
                            (24, 24, 24, 255))
        for index, image in enumerate(images):
            preview.alpha_composite(image, ((index % GRID[0]) * TILE_SIZE[0],
                                            (index // GRID[0]) * TILE_SIZE[1]))
        QA_DIR.mkdir(parents=True, exist_ok=True)
        preview.crop((0, 0, *VISIBLE_SIZE)).convert("RGB").save(
            QA_DIR / f"dungeon-{map_name.lower()}-base-preview.jpg",
            format="JPEG", quality=90, subsampling=0)
    return len(map_names), len(map_names) * 12


def validate_raids(manifest):
    catalog_path = ROOT / "assets" / "raid_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    declared = next((asset for asset in manifest["assets"]
                     if asset["id"] == "world.vanilla-raids.base"), None)
    require(declared is not None, "Raid asset declaration missing from manifest")
    require(declared.get("catalog") == "assets/raid_catalog.json",
            "Raid manifest does not reference the authoritative catalog")

    map_names = []
    for raid in catalog["raids"]:
        require(raid["defaultMap"] in raid["maps"],
                f"{raid['id']}: default map is not in its map inventory")
        map_names.extend(raid["maps"])
    require(len(map_names) == len(set(map_names)), "Duplicate raid map key in catalog")
    require(not any(name.lower().startswith("turtle_") for name in map_names),
            "Custom Turtle WoW raid map included in Vanilla catalog")

    actual_folders = {path.name for path in RAID_DIR.iterdir() if path.is_dir()}
    expected_folders = set(map_names)
    require(actual_folders == expected_folders,
            "Raid folder inventory mismatch: "
            f"missing={sorted(expected_folders - actual_folders)}, "
            f"unexpected={sorted(actual_folders - expected_folders)}")

    for map_name in map_names:
        folder = RAID_DIR / map_name
        expected = {f"Raid{map_name}{index}.blp" for index in range(1, 13)}
        actual = {path.name for path in folder.iterdir() if path.is_file()}
        require(actual == expected, f"{map_name} raid BLP inventory mismatch: "
                f"missing={sorted(expected - actual)}, unexpected={sorted(actual - expected)}")
        images = [read_blp(folder / f"Raid{map_name}{index}.blp")
                  for index in range(1, 13)]
        require(all(image.size == TILE_SIZE for image in images),
                f"{map_name}: one or more raid tiles are not 512x512")

        preview = Image.new("RGBA", (TILE_SIZE[0] * GRID[0], TILE_SIZE[1] * GRID[1]),
                            (24, 24, 24, 255))
        for index, image in enumerate(images):
            preview.alpha_composite(image, ((index % GRID[0]) * TILE_SIZE[0],
                                            (index // GRID[0]) * TILE_SIZE[1]))
        QA_DIR.mkdir(parents=True, exist_ok=True)
        preview.crop((0, 0, *VISIBLE_SIZE)).convert("RGB").save(
            QA_DIR / f"raid-{map_name.lower()}-base-preview.jpg",
            format="JPEG", quality=90, subsampling=0)
    return len(map_names), len(map_names) * 12


def validate_lua(manifest):
    source = (ROOT / "unrealMap.lua").read_text(encoding="utf-8")
    for map_name, stems in RUNTIME_PREFIXED.items():
        for stem in stems:
            pattern = rf"^  {map_name} = {{[^}}]* {stem.lower()} = true"
            require(re.search(pattern, source, re.MULTILINE),
                    f"unrealMap.lua OVERLAY_FILE_PREFIXED lacks {map_name}/{stem}")
    require("pairs(unrealMapOverlayData)" in source,
            "unrealMap.lua does not derive zone overlays from MapOverlayData.lua")
    catalog = json.loads((ROOT / "assets" / "zone_catalog.json").read_text(encoding="utf-8"))
    require([zone["mapName"] for zone in catalog["zones"]] == list(ZONE_SOURCES),
            "zone_catalog.json map order differs from map_geometry.ZONE_SOURCES")
    for zone in catalog["zones"]:
        map_name = zone["mapName"]
        files = exploration_files(manifest, map_name)
        require(files == set(zone["files"]),
                f"{map_name}: manifest exploration files differ from zone catalog")
        suppressions = set(zone.get("transparentRevealSuppressions", []))
        for missing in zone["missingNativeRevealPieces"]:
            if missing in suppressions:
                require(missing in files,
                        f"{map_name}/{missing}: transparent suppression not shipped")
            else:
                require(f"{missing.lower()} = true" in source,
                        f"{map_name}/{missing}: missing runtime exclusion")


def main():
    manifest = json.loads((ROOT / "assets" / "manifest.json").read_text(encoding="utf-8"))
    validate_lua(manifest)
    validate_unique_basenames()
    dungeon_maps, dungeon_files = validate_dungeons(manifest)
    print(f"Dungeons: validated {dungeon_maps} maps and {dungeon_files} BLP files; "
          f"wrote stitched previews to {QA_DIR}")
    raid_maps, raid_files = validate_raids(manifest)
    print(f"Raids: validated {raid_maps} maps and {raid_files} BLP files; "
          f"wrote stitched previews to {QA_DIR}")
    maps = [sys.argv[sys.argv.index("--map") + 1]] if "--map" in sys.argv else OVERLAYS
    for map_name in maps:
        require(map_name in OVERLAYS, f"Unknown map: {map_name}")
        count, path = validate_map(map_name, manifest)
        print(f"{map_name}: validated {count} BLP files, mip bounds and piece sizes; wrote {path}")


if __name__ == "__main__":
    main()
