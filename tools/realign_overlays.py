"""Rebuild a map's exploration overlays registered to the native map.

Every supplied HD overlay is an exact 2x rendition of its native sprite, but
translated up/left by a few HD pixels (a different amount per overlay group),
which shows up in game as doubled labels and coastlines wherever overlays
overlap. Narrow edge strips additionally hold 2x content cropped to the
native (1x) file width instead of the columns the native texcoords display.

Each overlay group (pieces the native updater tiles side by side) is stitched
at 2x, translated by the integer HD-pixel shift recorded in
assets/manifest.json, and re-cut into the native padded layout at exactly 2x
the native file size. Only supplied HD pixels are used: pixels the supplied
art never covered (the vacated band after the shift and missing strip
columns) stay transparent. Pieces with no supplied HD file are not generated;
the client keeps its native texture for them. Output is BLP2 DXT5 with
straight alpha.

A map whose supplied set is 4x (map_geometry.SOURCE_SCALE) is first reduced
to 2x by an exact premultiplied box filter; shifts are measured and applied
in 2x HD pixels after that reduction.

Usage: python -B tools/realign_overlays.py --map Elwynn|Redridge|Barrens
Input: the untouched supplied BLPs (map_geometry.source_dir). Outputs overwrite
the shipped runtime files. Requires Pillow, numpy and etcpak.
"""

import json
import sys

import etcpak
import numpy as np
from PIL import Image

from map_geometry import (ROOT, geometry, native_file_size, runtime_file, source_dir,
                          source_scale)

MANIFEST = ROOT / "assets" / "manifest.json"
SCALE = 2  # HD pixels per native pixel
HEADER_SIZE = 1172


def map_argument():
    return sys.argv[sys.argv.index("--map") + 1] if "--map" in sys.argv else "Elwynn"


def load_rgba(path):
    with Image.open(path) as image:
        return np.asarray(image.convert("RGBA"), dtype=np.uint8)


def reduce_premultiplied(pixels, factor):
    """Exact box reduction by an integer factor without dark alpha fringes."""
    height, width = pixels.shape[0] // factor, pixels.shape[1] // factor
    current = pixels.astype(np.float32)
    alpha = current[..., 3:4] / 255.0
    premultiplied = np.concatenate((current[..., :3] * alpha, current[..., 3:4]), axis=2)
    reduced = premultiplied[:height * factor, :width * factor].reshape(
        height, factor, width, factor, 4).mean(axis=(1, 3))
    reduced_alpha = reduced[..., 3:4] / 255.0
    color = np.where(reduced_alpha > 0, reduced[..., :3] / np.maximum(reduced_alpha, 1e-6), 0)
    return np.clip(np.rint(np.concatenate((color, reduced[..., 3:4]), axis=2)), 0, 255).astype(np.uint8)


def load_source(map_name, name):
    """Load one supplied file at the 2x runtime scale."""
    pixels = load_rgba(source_dir(map_name) / f"{name}.blp")
    factor = source_scale(map_name) // SCALE
    return reduce_premultiplied(pixels, factor) if factor > 1 else pixels


def region_table(map_name):
    return {name: (width, height, x, y) for name, width, height, x, y in geometry(map_name)}


def build_group(map_name, names, shift):
    region = region_table(map_name)
    source = source_dir(map_name)
    names = [name for name in names if (source / f"{name}.blp").is_file()]
    left = min(region[name][2] for name in names)
    top = min(region[name][3] for name in names)
    right = max(region[name][2] + region[name][0] for name in names)
    bottom = max(region[name][3] + region[name][1] for name in names)
    size = ((bottom - top) * SCALE, (right - left) * SCALE)
    supplied = np.zeros(size + (4,), np.uint8)

    for name in names:
        width, height, x, y = region[name]
        pixels = load_source(map_name, name)
        visible = pixels[:height * SCALE, :width * SCALE]
        row, column = (y - top) * SCALE, (x - left) * SCALE
        supplied[row:row + visible.shape[0], column:column + visible.shape[1]] = visible

    dx, dy = shift
    canvas = np.zeros_like(supplied)
    canvas[max(dy, 0):size[0] + min(dy, 0), max(dx, 0):size[1] + min(dx, 0)] = \
        supplied[max(-dy, 0):size[0] - max(dy, 0), max(-dx, 0):size[1] - max(dx, 0)]

    outputs = {}
    for name in names:
        width, height, x, y = region[name]
        output = np.zeros((native_file_size(height) * SCALE,
                           native_file_size(width) * SCALE, 4), np.uint8)
        output[:height * SCALE, :width * SCALE] = canvas[
            (y - top) * SCALE:(y - top + height) * SCALE,
            (x - left) * SCALE:(x - left + width) * SCALE]
        outputs[name] = output
    return outputs


def mip_chain(pixels, count):
    levels = [pixels]
    current = pixels.astype(np.float32)
    while len(levels) < count:
        height = max(current.shape[0] // 2, 1)
        width = max(current.shape[1] // 2, 1)
        alpha = current[..., 3:4] / 255.0
        premultiplied = np.concatenate((current[..., :3] * alpha, current[..., 3:4]), axis=2)
        image = Image.fromarray(np.clip(premultiplied, 0, 255).astype(np.uint8), "RGBA")
        reduced = np.asarray(image.resize((width, height), Image.Resampling.BOX), np.float32)
        reduced_alpha = reduced[..., 3:4] / 255.0
        color = np.where(reduced_alpha > 0, reduced[..., :3] / np.maximum(reduced_alpha, 1e-6), 0)
        current = np.concatenate((color, reduced[..., 3:4]), axis=2)
        levels.append(np.clip(np.rint(current), 0, 255).astype(np.uint8))
    return levels


def encode_dxt5(pixels):
    height, width = pixels.shape[:2]
    padded_height, padded_width = max(4, -(-height // 4) * 4), max(4, -(-width // 4) * 4)
    padded = np.zeros((padded_height, padded_width, 4), np.uint8)
    padded[:height, :width] = pixels
    padded[height:, :width] = pixels[-1:, :]
    padded[:, width:] = padded[:, width - 1:width]
    return etcpak.compress_to_dxt5(padded.tobytes(), padded_width, padded_height)


def write_blp(map_name, name, pixels):
    original = (source_dir(map_name) / f"{name}.blp").read_bytes()
    height, width = pixels.shape[:2]
    original_size = (int.from_bytes(original[12:16], "little"),
                     int.from_bytes(original[16:20], "little"))
    if original_size == (width, height):
        # Same dimensions: mirror the supplied, in-game validated mip count
        # (square tiles carry one extra trailing 1x1 entry).
        count = sum(1 for level in range(16)
                    if int.from_bytes(original[84 + level * 4:88 + level * 4], "little"))
    else:
        count = max(width, height).bit_length()  # complete chain down to 1x1
    data = blp_bytes(pixels, count, original[:HEADER_SIZE])
    runtime_file(map_name, name).write_bytes(data)
    return len(data), count


def blp_bytes(pixels, count, template_header):
    """Encode RGBA pixels as BLP2 DXT5 using a validated file's header."""
    header = bytearray(template_header[:HEADER_SIZE])
    # The payload is always DXT5: compression 2, alpha depth 8, alpha type 7,
    # mips present (a 4x source may carry a DXT1/DXT3 header).
    header[8:12] = bytes((2, 8, 7, 1))
    height, width = pixels.shape[:2]
    header[12:16] = width.to_bytes(4, "little")
    header[16:20] = height.to_bytes(4, "little")
    payloads = [encode_dxt5(level) for level in mip_chain(pixels, count)]
    offset = HEADER_SIZE
    for level in range(16):
        size = len(payloads[level]) if level < count else 0
        header[20 + level * 4:24 + level * 4] = (offset if size else 0).to_bytes(4, "little")
        header[84 + level * 4:88 + level * 4] = size.to_bytes(4, "little")
        offset += size
    return bytes(header) + b"".join(payloads)


def main():
    map_name = map_argument()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    exploration = next(asset for asset in manifest["assets"]
                       if asset["id"] == f"world.{map_name.lower()}.exploration")
    registration = exploration.get("legacyRegistration", exploration.get("registration"))
    if not registration:
        raise RuntimeError(f"No supplied-overlay registration for {map_name}")
    for group in registration["groups"]:
        outputs = build_group(map_name, group["pieces"], group["shiftHDPixels"])
        for name, pixels in outputs.items():
            size, mips = write_blp(map_name, name, pixels)
            with Image.open(runtime_file(map_name, name)) as check:
                decoded = np.asarray(check.convert("RGBA"), np.int16)
            error = np.abs(decoded - pixels.astype(np.int16)).mean()
            print(f"{name:24s} {pixels.shape[1]}x{pixels.shape[0]} mips={mips} bytes={size} "
                  f"dxtMeanAbsError={error:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
