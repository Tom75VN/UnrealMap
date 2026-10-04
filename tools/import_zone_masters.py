"""Import zone PNG masters as authoritative full-map runtime assets.

When a matching unexplored master is declared, it supplies the complete base
and the explored master supplies color through native reveal alpha. Other
zones keep their declared native-fog fallback or coherent explored base.
"""

import argparse
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from map_geometry import (ROOT, geometry, native_dir, native_file_size,
                          runtime_base_dir, runtime_dir, runtime_file)
from realign_overlays import HEADER_SIZE, blp_bytes


MANIFEST = ROOT / "assets" / "manifest.json"
OUTPUT_SIZE = (2004, 1336)
CANVAS_SIZE = (2048, 1536)
TILE = 512
SCALE = 2
BASE_MIP_COUNT = 11
TEMPLATE_TILE = runtime_base_dir("Elwynn") / "Elwynn1.blp"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def asset(manifest, asset_id):
    return next(item for item in manifest["assets"] if item["id"] == asset_id)


def source_path(spec):
    root = Path(spec["root"])
    if not root.is_absolute():
        root = ROOT / root
    return root / spec["file"]


def aligned_master(spec):
    path = source_path(spec)
    with Image.open(path) as image:
        require(abs(image.size[0] * 2 - image.size[1] * 3) <= 2,
                f"Master must have a 1.5 aspect ratio: {path} {image.size}")
        master = np.asarray(image.convert("RGB"), np.float32)
    warp = np.asarray(spec["warpOutputToMaster"], np.float32)
    return cv2.warpAffine(master, warp, OUTPUT_SIZE,
                          flags=cv2.INTER_LANCZOS4 | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REPLICATE)


def complete_mip_count(width, height):
    return max(width, height).bit_length()


def native_composites(map_name):
    references = native_dir(map_name)
    base = Image.new("RGBA", (1024, 768))
    for index in range(1, 13):
        path = references / f"{map_name}{index}.png"
        if not path.is_file():
            path = next((candidate for candidate in references.glob(f"*{index}.png")
                         if candidate.stem.casefold() == f"{map_name}{index}".casefold()), path)
        require(path.is_file(), f"Missing native base reference: {path}")
        with Image.open(path) as image:
            base.alpha_composite(image.convert("RGBA"),
                                 (((index - 1) % 4) * 256,
                                  ((index - 1) // 4) * 256))
    base = base.crop((0, 0, OUTPUT_SIZE[0] // SCALE, OUTPUT_SIZE[1] // SCALE))
    explored = base.copy()
    for name, width, height, x, y in geometry(map_name):
        path = references / f"{name}.png"
        if not path.is_file():
            continue
        with Image.open(path) as image:
            piece = image.convert("RGBA").crop((0, 0, width, height))
        explored.alpha_composite(piece, (x, y))
    resize = (OUTPUT_SIZE[0], OUTPUT_SIZE[1])
    return (np.asarray(base.convert("RGB").resize(resize, Image.Resampling.LANCZOS),
                       np.float32),
            np.asarray(explored.convert("RGB").resize(resize, Image.Resampling.LANCZOS),
                       np.float32))


def fog_aware_base(master, map_name, spec):
    if not spec.get("preserveNativeFog", True):
        return master
    native_base, native_explored = native_composites(map_name)
    settings = spec.get("nativeFogFallback", {})
    low = float(settings.get("differenceLow", 8))
    high = float(settings.get("differenceHigh", 32))
    require(high > low, f"Invalid nativeFogFallback thresholds for {map_name}")
    difference = np.max(np.abs(native_explored - native_base), axis=2)
    zone = np.clip((difference - low) / (high - low), 0, 1).astype(np.float32)
    dilate = int(settings.get("dilateHDPixels", 0))
    if dilate > 0:
        zone = cv2.dilate(zone, None, iterations=dilate)
    blur = float(settings.get("edgeBlurHDPixels", 0))
    if blur > 0:
        zone = cv2.GaussianBlur(zone, (0, 0), blur)
    zone = np.clip(zone, 0, 1)[..., None]
    return native_base * zone + master * (1 - zone)


def write_base_tiles(map_name, pixels, template):
    canvas = np.empty((CANVAS_SIZE[1], CANVAS_SIZE[0], 3), np.float32)
    canvas[:OUTPUT_SIZE[1], :OUTPUT_SIZE[0]] = pixels
    canvas[:OUTPUT_SIZE[1], OUTPUT_SIZE[0]:] = pixels[:, -1:]
    canvas[OUTPUT_SIZE[1]:] = canvas[OUTPUT_SIZE[1] - 1:OUTPUT_SIZE[1]]
    rgba = np.concatenate((np.clip(np.rint(canvas), 0, 255).astype(np.uint8),
                           np.full(canvas.shape[:2] + (1,), 255, np.uint8)), axis=2)
    folder = runtime_base_dir(map_name)
    folder.mkdir(parents=True, exist_ok=True)
    for index in range(12):
        row, column = divmod(index, 4)
        tile = np.ascontiguousarray(
            rgba[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE])
        destination = folder / f"{map_name}{index + 1}.blp"
        destination.write_bytes(blp_bytes(tile, BASE_MIP_COUNT, template))


def native_overlay(map_name, name, width, height):
    path = native_dir(map_name) / f"{name}.png"
    require(path.is_file(), f"Missing native overlay reference: {path}")
    file_width = native_file_size(width) * SCALE
    file_height = native_file_size(height) * SCALE
    with Image.open(path) as image:
        source = image.convert("RGBA").resize(
            (image.width * SCALE, image.height * SCALE), Image.Resampling.LANCZOS)
    output = np.zeros((file_height, file_width, 4), np.uint8)
    source_pixels = np.asarray(source, np.uint8)
    copy_height = min(file_height, source_pixels.shape[0])
    copy_width = min(file_width, source_pixels.shape[1])
    output[:copy_height, :copy_width] = source_pixels[:copy_height, :copy_width]
    return output


def master_overlay(master, map_name, name, width, height, x, y):
    native = native_dir(map_name) / f"{name}.png"
    require(native.is_file(), f"Missing native alpha reference: {native}")
    file_width = native_file_size(width) * SCALE
    file_height = native_file_size(height) * SCALE
    output = np.zeros((file_height, file_width, 4), np.uint8)
    color = master[y * SCALE:(y + height) * SCALE,
                   x * SCALE:(x + width) * SCALE]
    color_height, color_width = color.shape[:2]
    output[:color_height, :color_width, :3] = np.clip(
        np.rint(color), 0, 255).astype(np.uint8)
    with Image.open(native) as image:
        alpha = image.convert("RGBA").getchannel("A").resize(
            (file_width, file_height), Image.Resampling.LANCZOS)
    output[..., 3] = np.asarray(alpha, np.uint8)
    return output


def transparent_overlay(width, height):
    """Suppress a native overlay when the authoritative base is fully explored."""
    return np.zeros((native_file_size(height) * SCALE,
                     native_file_size(width) * SCALE, 4), np.uint8)


def import_map(map_name, manifest, template):
    exploration = asset(manifest, f"world.{map_name.lower()}.exploration")
    spec = exploration["activeMasterImport"]
    master = aligned_master(spec)
    unexplored = spec.get("unexploredMaster")
    base = aligned_master(unexplored) if unexplored else fog_aware_base(
        master, map_name, spec)
    base_folder = runtime_base_dir(map_name)
    overlay_folder = runtime_dir(map_name)
    base_folder.mkdir(parents=True, exist_ok=True)
    overlay_folder.mkdir(parents=True, exist_ok=True)

    write_base_tiles(map_name, base, template)

    regions = {name: (width, height, x, y)
               for name, width, height, x, y in geometry(map_name)}
    native_only = set(spec.get("nativeOverlayFiles", spec.get("copiedFiles", [])))
    transparent = set(spec.get("transparentRevealSuppressions", []))
    themed = spec.get("approvedForRuntime", False) or not spec.get("preserveNativeFog", True)
    for name in exploration["files"]:
        if name in regions:
            width, height, x, y = regions[name]
            if name in transparent:
                pixels = transparent_overlay(width, height)
            else:
                pixels = (master_overlay(master, map_name, name, width, height, x, y)
                          if themed and name not in native_only
                          else native_overlay(map_name, name, width, height))
        else:
            require(name in native_only,
                    f"No native geometry or native-only declaration for {map_name}/{name}")
            native = native_dir(map_name) / f"{name}.png"
            require(native.is_file(), f"Missing native overlay reference: {native}")
            with Image.open(native) as image:
                width, height = image.size
            pixels = native_overlay(map_name, name, width, height)
        destination = runtime_file(map_name, name)
        height, width = pixels.shape[:2]
        data = blp_bytes(pixels, complete_mip_count(width, height), template)
        destination.write_bytes(data)
        mode = ("transparent suppression" if name in transparent else
                "themed" if themed and name not in native_only else
                "native fog fallback")
        print(f"{map_name}/{destination.name}: {width}x{height}, {mode}, {len(data)} bytes")

    expected_base = {f"{map_name}{index}.blp" for index in range(1, 13)}
    expected_overlays = {runtime_file(map_name, name).name
                         for name in exploration["files"]}
    if base_folder == overlay_folder:
        expected = expected_base | expected_overlays
        actual = {path.name for path in base_folder.glob("*.blp")}
        require(actual == expected, f"{map_name} inventory mismatch: "
                f"missing={sorted(expected - actual)}, "
                f"unexpected={sorted(actual - expected)}")
    else:
        actual_base = {path.name for path in base_folder.glob("*.blp")}
        actual_overlays = {path.name for path in overlay_folder.glob("*.blp")}
        require(actual_base == expected_base, f"{map_name} base inventory mismatch: "
                f"missing={sorted(expected_base - actual_base)}, "
                f"unexpected={sorted(actual_base - expected_base)}")
        require(actual_overlays == expected_overlays,
                f"{map_name} overlay inventory mismatch: "
                f"missing={sorted(expected_overlays - actual_overlays)}, "
                f"unexpected={sorted(actual_overlays - expected_overlays)}")
        expected = expected_base | expected_overlays
    overlay_mode = "themed" if themed else "native fallback"
    base_mode = "paired unexplored master" if unexplored else "PNG-authored base"
    print(f"{map_name}: imported {base_mode} and {overlay_mode} overlays "
          f"({len(expected)} runtime BLP files)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", action="append", dest="maps")
    args = parser.parse_args()
    from map_geometry import ZONE_SOURCES
    maps = args.maps or list(ZONE_SOURCES)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    require(TEMPLATE_TILE.is_file(), f"Missing validated BLP template: {TEMPLATE_TILE}")
    template = TEMPLATE_TILE.read_bytes()[:HEADER_SIZE]
    for map_name in maps:
        import_map(map_name, manifest, template)


if __name__ == "__main__":
    main()
