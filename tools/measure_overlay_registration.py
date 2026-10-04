"""Measure each overlay group's offset against the native sprites.

Stitches every overlay group at 2x from the HD files and from the native
sprites (verification reference only; the generator never reads them) and
prints the integer HD-pixel translation that best aligns them, matching
premultiplied color and alpha together, plus the mean absolute RGBA error
after that alignment.

Usage: python -B tools/measure_overlay_registration.py --map Redridge [--source]
--source measures the untouched supplied files (reduced to 2x first when the
set is 4x) (the shifts recorded in
assets/manifest.json); shipped files must report [0, 0] (at most 1 HD px).
Requires Pillow, numpy and opencv-python-headless.
"""

import sys

import cv2
import numpy as np
from PIL import Image

from map_geometry import (NATIVE_REFERENCE_DIR, OVERLAYS, pieces, runtime_file,
                          source_dir)
from realign_overlays import SCALE, load_rgba, load_source, map_argument

MARGIN = 128  # search window in HD pixels


def native_2x(map_name, name):
    with Image.open(NATIVE_REFERENCE_DIR / map_name / f"{name}.png") as image:
        image = image.convert("RGBA")
        return np.asarray(image.resize((image.width * SCALE, image.height * SCALE),
                                       Image.Resampling.LANCZOS), dtype=np.uint8)


def stitch(overlay, loader):
    _, width, height, x0, y0 = overlay
    canvas = np.zeros((height * SCALE, width * SCALE, 4), np.uint8)
    present = []
    for name, piece_width, piece_height, x, y in pieces(overlay):
        pixels = loader(name)
        if pixels is None:
            continue
        present.append(name)
        visible = pixels[:piece_height * SCALE, :piece_width * SCALE]
        row, column = (y - y0) * SCALE, (x - x0) * SCALE
        canvas[row:row + visible.shape[0], column:column + visible.shape[1]] = visible
    return canvas, present


def features(pixels):
    pixels = pixels.astype(np.float32)
    alpha = pixels[..., 3:4] / 255.0
    return np.concatenate((pixels[..., :3] * alpha, pixels[..., 3:4]), axis=2)


def main():
    map_name = map_argument()
    supplied = "--source" in sys.argv

    def hd_loader(name):
        path = (source_dir(map_name) / f"{name}.blp" if supplied
                else runtime_file(map_name, name))
        if not path.is_file():
            return None
        return load_source(map_name, name) if supplied else load_rgba(path)

    worst = 0
    for overlay in OVERLAYS[map_name]:
        hd, present = stitch(overlay, hd_loader)
        native, _ = stitch(overlay, lambda name: native_2x(map_name, name)
                           if name in present else None)
        reference = cv2.copyMakeBorder(features(native), MARGIN, MARGIN, MARGIN, MARGIN,
                                       cv2.BORDER_CONSTANT, 0)
        result = cv2.matchTemplate(reference, features(hd), cv2.TM_SQDIFF)
        _, _, location, _ = cv2.minMaxLoc(result)
        dx, dy = location[0] - MARGIN, location[1] - MARGIN
        aligned = native.astype(np.int16)[max(dy, 0):, max(dx, 0):]
        moved = hd.astype(np.int16)[max(-dy, 0):, max(-dx, 0):]
        rows = min(aligned.shape[0], moved.shape[0])
        columns = min(aligned.shape[1], moved.shape[1])
        error = np.abs(aligned[:rows, :columns] - moved[:rows, :columns]).mean()
        worst = max(worst, abs(dx), abs(dy))
        print(f"{'+'.join(present):72s} shiftHDPixels=[{dx}, {dy}] meanAbsError={error:.2f}")
    print(f"largest offset: {worst} HD px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
