"""Composite native exploration overlays onto stitched zone maps."""

import argparse
import re
import shutil
import zipfile
from pathlib import Path

import cv2
import numpy as np
from PIL import Image


SOURCE_SCALE = 4
MEASURE_SCALE = 2
MARGIN = 64


def normalized(value):
    return re.sub(r"[^A-Z0-9]", "", value.upper())


def directory_by_name(root, name):
    target = name.casefold()
    return next((path for path in root.iterdir() if path.is_dir() and path.name.casefold() == target), None)


def read_geometry(zip_path):
    with zipfile.ZipFile(zip_path) as archive:
        text = archive.read("UnrealPfUI/env/tables.lua").decode("utf-8")
    block = text.split("pfMapOverlayData = {", 1)[1]
    block = block.split("\n}", 1)[0]
    maps = {}
    for match in re.finditer(r'\["([^"]+)"\]\s*=\s*\{(.*?)\}\s*,?', block, re.S):
        overlays = []
        for item in re.findall(r'"([^"]+)"', match.group(2)):
            name, width, height, x, y = item.split(":")
            overlays.append((name, int(width), int(height), int(x), int(y)))
        maps[match.group(1)] = overlays
    alterac_valley = maps.setdefault("AlteracValley", [])
    if not any(normalized(overlay[0]) == "FROSTWOLFKEEP" for overlay in alterac_valley):
        alterac_valley.append(("FROSTWOLFKEEP", 235, 290, 399, 375))
    return maps


def pieces(overlay):
    name, width, height, x, y = overlay
    wide = (width + 255) // 256
    tall = (height + 255) // 256
    result = []
    for row in range(tall):
        piece_height = min(256, height - row * 256)
        for column in range(wide):
            piece_width = min(256, width - column * 256)
            index = row * wide + column + 1
            result.append((f"{name}{index}", piece_width, piece_height,
                           x + column * 256, y + row * 256))
    return result


def stems_by_normalized(directory, suffix):
    result = {}
    if directory is None:
        return result
    for path in directory.glob(f"*.{suffix}"):
        match = re.match(r"^(.*?)(\d+)$", path.stem)
        if match:
            result.setdefault(normalized(match.group(1)), set()).add(match.group(1))
    return result


def resolve_stem(table_stem, source_stems, native_stems):
    key = normalized(table_stem)
    candidates = source_stems.get(key, set())
    if candidates:
        return sorted(candidates, key=lambda value: (value.casefold(), value))[0]
    native = native_stems.get(key, set())
    if native:
        native_stem = sorted(native, key=lambda value: (value.casefold(), value))[0]
        source = source_stems.get(normalized(native_stem), set())
        if source:
            return sorted(source, key=lambda value: (value.casefold(), value))[0]
    alternate = key[3:] if key.startswith("THE") else "THE" + key
    candidates = source_stems.get(alternate, set())
    if candidates:
        return sorted(candidates, key=lambda value: (value.casefold(), value))[0]
    return None


def premultiplied_reduce(pixels, factor):
    height = pixels.shape[0] // factor
    width = pixels.shape[1] // factor
    current = pixels[:height * factor, :width * factor].astype(np.float32)
    alpha = current[..., 3:4] / 255.0
    premultiplied = np.concatenate((current[..., :3] * alpha, current[..., 3:4]), axis=2)
    reduced = premultiplied.reshape(height, factor, width, factor, 4).mean(axis=(1, 3))
    reduced_alpha = reduced[..., 3:4] / 255.0
    colors = np.where(reduced_alpha > 0,
                      reduced[..., :3] / np.maximum(reduced_alpha, 1e-6), 0)
    return np.clip(np.rint(np.concatenate((colors, reduced[..., 3:4]), axis=2)),
                   0, 255).astype(np.uint8)


def load_rgba(path):
    with Image.open(path) as image:
        return np.asarray(image.convert("RGBA"), dtype=np.uint8)


def source_piece(path, width, height, scale):
    pixels = load_rgba(path)
    if scale == MEASURE_SCALE:
        pixels = premultiplied_reduce(pixels, SOURCE_SCALE // MEASURE_SCALE)
    required = (height * scale, width * scale)
    return pixels[:required[0], :required[1]]


def native_piece(path, width, height):
    with Image.open(path) as image:
        image = image.convert("RGBA")
        image = image.resize((image.width * MEASURE_SCALE, image.height * MEASURE_SCALE),
                             Image.Resampling.LANCZOS)
        return np.asarray(image, dtype=np.uint8)[:height * MEASURE_SCALE,
                                                :width * MEASURE_SCALE]


def features(pixels):
    pixels = pixels.astype(np.float32)
    alpha = pixels[..., 3:4] / 255.0
    return np.concatenate((pixels[..., :3] * alpha, pixels[..., 3:4]), axis=2)


def measure_shift(overlay, source_dir, source_stem, native_dir, native_stem):
    _, width, height, x0, y0 = overlay
    supplied = np.zeros((height * MEASURE_SCALE, width * MEASURE_SCALE, 4), np.uint8)
    native = np.zeros_like(supplied)
    present = 0
    for expected, piece_width, piece_height, x, y in pieces(overlay):
        index = re.search(r"(\d+)$", expected).group(1)
        source_path = source_dir / f"{source_stem}{index}.blp"
        native_path = native_dir / f"{native_stem}{index}.png"
        if not source_path.is_file() or not native_path.is_file():
            continue
        row = (y - y0) * MEASURE_SCALE
        column = (x - x0) * MEASURE_SCALE
        supplied_piece = source_piece(source_path, piece_width, piece_height, MEASURE_SCALE)
        native_pixels = native_piece(native_path, piece_width, piece_height)
        supplied[row:row + supplied_piece.shape[0], column:column + supplied_piece.shape[1]] = supplied_piece
        native[row:row + native_pixels.shape[0], column:column + native_pixels.shape[1]] = native_pixels
        present += 1
    if not present or supplied[..., 3].max() == 0 or native[..., 3].max() == 0:
        return (0, 0), present
    reference = cv2.copyMakeBorder(features(native), MARGIN, MARGIN, MARGIN, MARGIN,
                                   cv2.BORDER_CONSTANT, 0)
    result = cv2.matchTemplate(reference, features(supplied), cv2.TM_SQDIFF)
    _, _, location, _ = cv2.minMaxLoc(result)
    shift = (location[0] - MARGIN, location[1] - MARGIN)
    if abs(shift[0]) == MARGIN or abs(shift[1]) == MARGIN:
        return (0, 0), present
    return shift, present


def translated(pixels, dx, dy):
    result = np.zeros_like(pixels)
    height, width = pixels.shape[:2]
    result[max(dy, 0):height + min(dy, 0), max(dx, 0):width + min(dx, 0)] = pixels[
        max(-dy, 0):height - max(dy, 0), max(-dx, 0):width - max(dx, 0)]
    return result


def compose_overlay(base, overlay, source_dir, source_stem, shift, opaque=False,
                    alpha_gamma=1.0):
    _, width, height, x0, y0 = overlay
    group = np.zeros((height * SOURCE_SCALE, width * SOURCE_SCALE, 4), np.uint8)
    used = []
    missing = []
    for expected, piece_width, piece_height, x, y in pieces(overlay):
        index = re.search(r"(\d+)$", expected).group(1)
        path = source_dir / f"{source_stem}{index}.blp"
        if not path.is_file():
            missing.append(path.name)
            continue
        pixels = source_piece(path, piece_width, piece_height, SOURCE_SCALE)
        row = (y - y0) * SOURCE_SCALE
        column = (x - x0) * SOURCE_SCALE
        group[row:row + pixels.shape[0], column:column + pixels.shape[1]] = pixels
        used.append(path.name)
    dx, dy = shift
    group = translated(group, dx * (SOURCE_SCALE // MEASURE_SCALE),
                        dy * (SOURCE_SCALE // MEASURE_SCALE))
    if opaque:
        group[..., 3] = np.where(group[..., 3] > 0, 255, 0).astype(np.uint8)
    elif alpha_gamma != 1.0:
        alpha = group[..., 3].astype(np.float32) / 255.0
        group[..., 3] = np.rint(np.power(alpha, alpha_gamma) * 255.0).astype(np.uint8)
    base.alpha_composite(Image.fromarray(group, "RGBA"),
                         (x0 * SOURCE_SCALE, y0 * SOURCE_SCALE))
    return used, missing


def inventory(source_root, native_root, geometry):
    issues = []
    matched = 0
    for map_name, overlays in geometry.items():
        source_dir = directory_by_name(source_root, map_name)
        if source_dir is None:
            issues.append(f"{map_name}: source folder missing")
            continue
        native_dir = directory_by_name(native_root, map_name)
        source_stems = stems_by_normalized(source_dir, "blp")
        native_stems = stems_by_normalized(native_dir, "png")
        for overlay in overlays:
            stem = resolve_stem(overlay[0], source_stems, native_stems)
            if stem is None:
                issues.append(f"{map_name}/{overlay[0]}: cannot resolve source stem")
                continue
            expected_count = len(pieces(overlay))
            missing = [f"{stem}{index}.blp" for index in range(1, expected_count + 1)
                       if not (source_dir / f"{stem}{index}.blp").is_file()]
            if missing:
                issues.append(f"{map_name}/{stem}: missing {', '.join(missing)}")
            else:
                matched += 1
    return matched, issues


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("base", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("geometry_zip", type=Path)
    parser.add_argument("native", type=Path)
    parser.add_argument("--inventory-only", action="store_true")
    parser.add_argument("--only")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--opaque-overlays", action="store_true")
    parser.add_argument("--alpha-gamma", type=float, default=1.0)
    args = parser.parse_args()

    geometry = read_geometry(args.geometry_zip)
    matched, issues = inventory(args.source, args.native, geometry)
    print(f"Inventory: {matched} overlay groups matched; {len(issues)} issues", flush=True)
    for issue in issues:
        print(f"ISSUE {issue}", flush=True)
    if args.inventory_only:
        return 1 if issues else 0
    if issues:
        raise RuntimeError("Overlay inventory has unresolved issues")

    args.output.mkdir(parents=True, exist_ok=True)
    base_files = sorted(args.base.glob("*.png"),
                        key=lambda path: (path.stem.casefold() != "barrens", path.stem.casefold()))
    if args.only:
        base_files = [path for path in base_files if path.stem.casefold() == args.only.casefold()]
    for map_index, base_path in enumerate(base_files, 1):
        map_name = base_path.stem
        overlays = next((value for key, value in geometry.items()
                         if key.casefold() == map_name.casefold()), [])
        output_path = args.output / base_path.name
        if args.skip_existing and output_path.is_file():
            print(f"{map_index:02d} {map_name}: keeping existing output", flush=True)
            continue
        if not overlays:
            shutil.copy2(base_path, output_path)
            print(f"{map_index:02d} {map_name}: base map has no exploration overlays", flush=True)
            continue

        source_dir = directory_by_name(args.source, map_name)
        native_dir = directory_by_name(args.native, map_name)
        source_stems = stems_by_normalized(source_dir, "blp")
        native_stems = stems_by_normalized(native_dir, "png")
        with Image.open(base_path) as image:
            base = image.convert("RGBA")
        shifts = []
        for overlay in overlays:
            source_stem = resolve_stem(overlay[0], source_stems, native_stems)
            native_candidates = native_stems.get(normalized(overlay[0]), set())
            native_stem = (sorted(native_candidates, key=lambda value: (value.casefold(), value))[0]
                           if native_candidates else None)
            if native_dir is not None and native_stem is not None:
                shift, _ = measure_shift(overlay, source_dir, source_stem,
                                         native_dir, native_stem)
            else:
                shift = (0, 0)
            _, missing = compose_overlay(base, overlay, source_dir, source_stem, shift,
                                         args.opaque_overlays, args.alpha_gamma)
            if missing:
                raise RuntimeError(f"{map_name}/{source_stem}: missing {missing}")
            shifts.append(shift)
        base.save(output_path, format="PNG", optimize=False, compress_level=3)
        largest = max(max(abs(dx), abs(dy)) for dx, dy in shifts)
        print(f"{map_index:02d} {map_name}: {len(overlays)} overlays, "
              f"largest measured shift {largest} at 2x -> {output_path}", flush=True)
    print(f"Completed {len(base_files)} fully explored maps", flush=True)


if __name__ == "__main__":
    main()
