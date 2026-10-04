"""Import the catalogued Vanilla dungeon BLP tiles without TGA companions."""

import argparse
import filecmp
import json
import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = ROOT / "assets" / "dungeon_catalog.json"
DESTINATION = ROOT / "Media" / "Textures" / "Maps" / "Dungeons"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source")
    args = parser.parse_args()

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    source_root = Path(args.source or catalog["source"]["root"])
    map_names = [map_name for dungeon in catalog["dungeons"]
                 for map_name in dungeon["maps"]]
    require(len(map_names) == len(set(map_names)), "Duplicate dungeon map in catalog")
    require(source_root.is_dir(), f"Dungeon source root is missing: {source_root}")

    DESTINATION.mkdir(parents=True, exist_ok=True)
    copied = 0
    unchanged = 0
    for map_name in map_names:
        source_folder = source_root / map_name
        destination_folder = DESTINATION / map_name
        require(source_folder.is_dir(), f"Missing source folder: {source_folder}")
        source_files = {path.name for path in source_folder.iterdir()
                        if path.is_file() and path.suffix.lower() == ".blp"}
        source_expected = {f"{map_name}{index}.blp" for index in range(1, 13)}
        require(source_files == source_expected, f"{map_name}: source BLP inventory mismatch")
        destination_folder.mkdir(parents=True, exist_ok=True)
        for index in range(1, 13):
            source = source_folder / f"{map_name}{index}.blp"
            destination = destination_folder / f"Dungeon{map_name}{index}.blp"
            if destination.is_file() and filecmp.cmp(source, destination, shallow=False):
                unchanged += 1
            else:
                shutil.copy2(source, destination)
                copied += 1
            legacy = destination_folder / f"{map_name}{index}.blp"
            if legacy != destination and legacy.is_file():
                legacy.unlink()

    expected_folders = set(map_names)
    actual_folders = {path.name for path in DESTINATION.iterdir() if path.is_dir()}
    require(actual_folders == expected_folders,
            "Destination contains a missing or undeclared dungeon folder")
    for map_name in map_names:
        folder = DESTINATION / map_name
        actual = {path.name for path in folder.iterdir() if path.is_file()}
        expected = {f"Dungeon{map_name}{index}.blp" for index in range(1, 13)}
        require(actual == expected, f"{map_name}: destination is not BLP-only and exact")
    print(f"Imported {len(map_names)} dungeon maps: {copied} copied, "
          f"{unchanged} already identical, 660 BLP files total")


if __name__ == "__main__":
    main()
