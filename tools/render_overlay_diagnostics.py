"""Render a fully explored map from the shipped BLPs for visual QA.

Composites the 12 base tiles and all shipped exploration pieces at 2x,
applying the native texcoord crop, and writes the result to QA_DIR (outside
the addon). Pieces without an HD file are left out (the client shows its
native texture there). Run tools/validate_assets.py first; it writes the base
preview used here.

Usage:
  python -B tools/render_overlay_diagnostics.py --map Redridge
  python -B tools/render_overlay_diagnostics.py --all
"""

import sys

from PIL import Image, ImageDraw

from map_geometry import QA_DIR, ZONE_SOURCES, geometry, native_file_size, runtime_file


def visible_crop(overlay, width, height):
    # The native updater keeps SetTexCoord(0, w/fileW, 0, h/fileH) after the
    # addon rebinds the path, so only this part of the file is displayed.
    file_width, file_height = overlay.size
    return overlay.crop((0, 0,
                         file_width * width // native_file_size(width),
                         file_height * height // native_file_size(height)))


def render(map_name):
    composite = Image.open(QA_DIR / f"{map_name.lower()}-base-preview.png").convert("RGBA")
    for name, width, height, x, y in geometry(map_name):
        path = runtime_file(map_name, name)
        if not path.is_file():
            continue
        overlay = Image.open(path).convert("RGBA")
        fitted = visible_crop(overlay, width, height).resize(
            (width * 2, height * 2), Image.Resampling.LANCZOS)
        composite.alpha_composite(fitted, (x * 2, y * 2))
    output = QA_DIR / f"{map_name.lower()}-runtime-composite.png"
    composite.save(output)
    print(f"Wrote {output}")
    return composite


def contact_sheet(rendered):
    columns, thumb_width, thumb_height, label_height = 5, 360, 240, 24
    rows = -(-len(rendered) // columns)
    sheet = Image.new("RGB", (columns * thumb_width,
                              rows * (thumb_height + label_height)), "#161616")
    draw = ImageDraw.Draw(sheet)
    for index, (map_name, composite) in enumerate(rendered):
        row, column = divmod(index, columns)
        x, y = column * thumb_width, row * (thumb_height + label_height)
        # The native 4x3 backing grid is 2048x1536 at runtime, but the map
        # viewport only samples the 1002x668 native area (2004x1336 at 2x).
        # Do not display padded tile bytes that the game never samples.
        preview = composite.crop((0, 0, 2004, 1336)).convert("RGB")
        preview.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        px = x + (thumb_width - preview.width) // 2
        py = y + (thumb_height - preview.height) // 2
        sheet.paste(preview, (px, py))
        draw.text((x + 6, y + thumb_height + 5), map_name, fill="white")
    output = QA_DIR / "zone-runtime-contact-sheet.jpg"
    sheet.save(output, quality=92, subsampling=0)
    print(f"Wrote {output}")


def main():
    if "--all" in sys.argv:
        rendered = [(map_name, render(map_name)) for map_name in ZONE_SOURCES]
        contact_sheet(rendered)
        return
    map_name = sys.argv[sys.argv.index("--map") + 1] if "--map" in sys.argv else "Elwynn"
    render(map_name)


if __name__ == "__main__":
    main()
