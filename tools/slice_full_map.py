"""Cut a single full-map master image into the validated 12 base tiles.

The master (any size with the 1.5 aspect of the 1002x668 visible map) is
resampled once to 2004x1336 (2x) through the affine warp recorded in the
manifest (`world.<map>.base.master.warpOutputToMaster`, output px -> master
px), placed top-left on a 2048x1536 canvas whose padding repeats the last
column/row, cut into twelve 512x512 row-major tiles `<Map>1..12` and encoded
as BLP2 DXT5 with the same header and 11-level mip layout as the validated
base tiles.

A master may instead be a supplied tile set at an integer multiple of the
native scale (`master.tileScale`, e.g. the 4x Barrens1..12 BLPs in
map_geometry.source_dir). Its tiles are stitched row-major and cropped to the
visible 1002x668 area times that scale. With `master.resample` = "area" the
master is reduced by an exact area filter instead of the warp; use it only
when --measure shows no residual offset.

Usage:
  python -B tools/slice_full_map.py --map Stormwind --measure   (print warp)
  python -B tools/slice_full_map.py --map Stormwind             (generate)
--measure registers the master against the native base sprites (verification
reference) and prints the warp to record in the manifest plus residuals.
Requires Pillow, numpy, etcpak (and opencv-python-headless).
"""

import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from map_geometry import (SOURCES_DIR, native_base_dir, runtime_base_dir,
                          runtime_dir, source_dir)
from realign_overlays import HEADER_SIZE, MANIFEST, blp_bytes, load_rgba, map_argument

OUTPUT_SIZE = (2004, 1336)
CANVAS_SIZE = (2048, 1536)
TILE = 512
BASE_MIP_COUNT = 11  # matches the in-game validated supplied base tiles
TEMPLATE_TILE = runtime_base_dir("Elwynn") / "Elwynn1.blp"


def load_master(map_name, base):
    master = base["master"]
    if "tileScale" in master:
        size = 256 * master["tileScale"]
        canvas = np.zeros((3 * size, 4 * size, 3), np.uint8)
        for index in range(12):
            row, column = divmod(index, 4)
            canvas[row * size:(row + 1) * size, column * size:(column + 1) * size] =                 load_rgba(source_dir(map_name) / f"{map_name}{index + 1}.blp")[..., :3]
        scale = master["tileScale"]
        return canvas[:668 * scale, :1002 * scale].astype(np.float32)
    root = Path(master.get("root", SOURCES_DIR))
    with Image.open(root / master["file"]) as image:
        return np.asarray(image.convert("RGB"), np.float32)


def native_base_2x(map_name):
    folder = native_base_dir(map_name)
    tiles = []
    for index in range(12):
        path = folder / f"{map_name}{index + 1}.png"
        if not path.exists():
            path = path.with_suffix(".blp")
        tiles.append(load_rgba(path)[..., :3])
    tile_size = tiles[0].shape[0]
    if any(tile.shape[:2] != (tile_size, tile_size) for tile in tiles):
        raise RuntimeError(f"{map_name}: native base tiles do not share one square size")
    canvas = np.zeros((3 * tile_size, 4 * tile_size, 3), np.uint8)
    for index, tile in enumerate(tiles):
        row, column = divmod(index, 4)
        canvas[row * tile_size:(row + 1) * tile_size,
               column * tile_size:(column + 1) * tile_size] = tile
    scale = tile_size / 256
    visible = canvas[:round(668 * scale), :round(1002 * scale)]
    return cv2.resize(visible, OUTPUT_SIZE, interpolation=cv2.INTER_CUBIC).astype(np.float32)


def features(rgb):
    gray = cv2.GaussianBlur(cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY), (0, 0), 3)
    magnitude = cv2.magnitude(cv2.Sobel(gray, cv2.CV_32F, 1, 0), cv2.Sobel(gray, cv2.CV_32F, 0, 1))
    return cv2.GaussianBlur(magnitude, (0, 0), 3)


def area_reduce(master):
    return cv2.resize(master, OUTPUT_SIZE, interpolation=cv2.INTER_AREA)


def resample(master, warp):
    return cv2.warpAffine(master, np.asarray(warp, np.float32), OUTPUT_SIZE,
                          flags=cv2.INTER_LANCZOS4 | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REPLICATE)


def local_residuals(output, native):
    reference, moved = features(native), features(output)
    margin, offsets = 24, []
    for y in range(margin, OUTPUT_SIZE[1] - 256 - margin, 300):
        for x in range(margin, OUTPUT_SIZE[0] - 256 - margin, 300):
            result = cv2.matchTemplate(reference[y - margin:y + 256 + margin, x - margin:x + 256 + margin],
                                       moved[y:y + 256, x:x + 256], cv2.TM_CCOEFF_NORMED)
            _, score, _, location = cv2.minMaxLoc(result)
            if score > 0.5:
                offsets.append((location[0] - margin, location[1] - margin))
    values = np.asarray(offsets, np.float32)
    magnitudes = np.max(np.abs(values), axis=1)
    return {
        "count": len(offsets),
        "median": np.rint(np.median(values, axis=0)).astype(int).tolist(),
        "p90": int(np.ceil(np.percentile(magnitudes, 90))),
        "worst": int(np.max(magnitudes)),
    }


def measure(map_name, base):
    master = load_master(map_name, base)
    scale = np.diag([master.shape[1] / OUTPUT_SIZE[0], master.shape[0] / OUTPUT_SIZE[1]])
    native = native_base_2x(map_name)
    upscaled = cv2.resize(master, OUTPUT_SIZE, interpolation=cv2.INTER_CUBIC)
    warp = np.eye(2, 3, dtype=np.float32)
    score, warp = cv2.findTransformECC(features(native), features(upscaled), warp, cv2.MOTION_AFFINE,
                                       (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 500, 1e-7),
                                       None, 5)
    to_master = scale @ warp
    print(f"ecc={score:.3f}")
    print("warpOutputToMaster =", json.dumps(np.round(to_master, 6).tolist()))
    print("local residual after warp:", local_residuals(resample(master, to_master), native))
    print("local residual without warp:",
          local_residuals(resample(master, scale @ np.eye(2, 3)), native))
    if base["master"].get("resample") == "area":
        print("local residual with area reduction:", local_residuals(area_reduce(master), native))


def generate(map_name, base):
    master = load_master(map_name, base)
    if base["master"].get("resample") == "area":
        output = area_reduce(master)
    else:
        output = resample(master, base["master"]["warpOutputToMaster"])
    canvas = np.empty((CANVAS_SIZE[1], CANVAS_SIZE[0], 3), np.float32)
    canvas[:OUTPUT_SIZE[1], :OUTPUT_SIZE[0]] = output
    canvas[:OUTPUT_SIZE[1], OUTPUT_SIZE[0]:] = output[:, -1:]
    canvas[OUTPUT_SIZE[1]:] = canvas[OUTPUT_SIZE[1] - 1:OUTPUT_SIZE[1]]
    rgba = np.concatenate((np.clip(np.rint(canvas), 0, 255).astype(np.uint8),
                           np.full(canvas.shape[:2] + (1,), 255, np.uint8)), axis=2)
    template = TEMPLATE_TILE.read_bytes()[:HEADER_SIZE]
    base_folder = runtime_base_dir(map_name)
    overlay_folder = runtime_dir(map_name)
    base_folder.mkdir(parents=True, exist_ok=True)
    overlay_folder.mkdir(parents=True, exist_ok=True)
    for index in range(12):
        row, column = divmod(index, 4)
        tile = np.ascontiguousarray(rgba[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE])
        data = blp_bytes(tile, BASE_MIP_COUNT, template)
        (base_folder / f"{map_name}{index + 1}.blp").write_bytes(data)
        print(f"{map_name}{index + 1}.blp {len(data)} bytes")
    native_folder = native_base_dir(map_name)
    for name in base["runtime"].get("transparentOverlaySuppressions", []):
        source = native_folder / f"{name}.blp"
        with Image.open(source) as image:
            width, height = image.size
        pixels = np.zeros((height, width, 4), np.uint8)
        original = source.read_bytes()
        count = sum(1 for level in range(16)
                    if int.from_bytes(original[84 + level * 4:88 + level * 4], "little"))
        data = blp_bytes(pixels, count, original[:HEADER_SIZE])
        (overlay_folder / f"{name}.blp").write_bytes(data)
        print(f"{name}.blp {width}x{height} transparent {len(data)} bytes")


def main():
    map_name = map_argument()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    base = next(asset for asset in manifest["assets"] if asset["id"] == f"world.{map_name.lower()}.base")
    if "--measure" in sys.argv:
        measure(map_name, base)
    else:
        generate(map_name, base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
