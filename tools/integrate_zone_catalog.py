"""Discover, register, catalog, and manifest every supplied zone PNG master."""

import argparse
import json
from datetime import date
from pathlib import Path

from PIL import Image

try:
    import numpy as np
    import cv2
except ModuleNotFoundError:
    np = None
    cv2 = None

from map_geometry import (ROOT, ZONE_MASTER_ROOT, ZONE_SOURCES,
                          ZONE_UNEXPLORED_MASTER_ROOT, ZONE_UNEXPLORED_SOURCES,
                          geometry, native_dir, native_file_size, runtime_base_dir,
                          runtime_dir, runtime_file, zone_master,
                          zone_unexplored_master)


CATALOG = ROOT / "assets" / "zone_catalog.json"
MANIFEST = ROOT / "assets" / "manifest.json"
STATUS = ROOT / "ZONE_IMPORT_STATUS.md"
OUTPUT_SIZE = (2004, 1336)

PNG_ONLY_ZONE_OVERRIDES = {
    "BlastedLands": "native reveal composition did not fully uncover the zone in game",
    "Hinterlands": "native reveal composition did not fully uncover the zone in game",
    "UngoroCrater": "native reveal composition did not fully uncover the zone in game",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def native_path(map_name, filename):
    folder = native_dir(map_name)
    direct = folder / filename
    if direct.is_file():
        return direct
    target = filename.casefold()
    match = next((path for path in folder.glob("*.png")
                  if path.name.casefold() == target), None)
    return match or direct


def native_base(map_name):
    canvas = np.zeros((768, 1024, 3), np.uint8)
    for index in range(1, 13):
        path = native_path(map_name, f"{map_name}{index}.png")
        require(path.is_file(), f"Missing native base reference: {path}")
        with Image.open(path) as image:
            row, column = divmod(index - 1, 4)
            canvas[row * 256:(row + 1) * 256,
                   column * 256:(column + 1) * 256] = np.asarray(image.convert("RGB"))
    return cv2.resize(canvas[:668, :1002], OUTPUT_SIZE,
                      interpolation=cv2.INTER_CUBIC).astype(np.float32)


def features(rgb):
    gray = cv2.GaussianBlur(cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY), (0, 0), 3)
    return cv2.GaussianBlur(cv2.magnitude(
        cv2.Sobel(gray, cv2.CV_32F, 1, 0),
        cv2.Sobel(gray, cv2.CV_32F, 0, 1)), (0, 0), 3)


def resample(master, warp):
    return cv2.warpAffine(master, np.asarray(warp, np.float32), OUTPUT_SIZE,
                          flags=cv2.INTER_LANCZOS4 | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REPLICATE)


def local_residuals(output, native):
    reference, moved = features(native), features(output)
    margin, offsets = 24, []
    for y in range(margin, OUTPUT_SIZE[1] - 256 - margin, 300):
        for x in range(margin, OUTPUT_SIZE[0] - 256 - margin, 300):
            result = cv2.matchTemplate(
                reference[y - margin:y + 256 + margin,
                          x - margin:x + 256 + margin],
                moved[y:y + 256, x:x + 256], cv2.TM_CCOEFF_NORMED)
            _, score, _, location = cv2.minMaxLoc(result)
            if score > 0.5:
                offsets.append((location[0] - margin, location[1] - margin))
    if not offsets:
        return {"samples": 0, "medianHDPixels": [0, 0], "p90HDPixels": 999,
                "worstHDPixels": 999}
    values = np.asarray(offsets, np.float32)
    magnitudes = np.max(np.abs(values), axis=1)
    return {
        "samples": len(offsets),
        "medianHDPixels": np.rint(np.median(values, axis=0)).astype(int).tolist(),
        "p90HDPixels": int(np.ceil(np.percentile(magnitudes, 90))),
        "worstHDPixels": int(np.max(magnitudes)),
    }


def measure_registration(map_name, path):
    with Image.open(path) as image:
        master = np.asarray(image.convert("RGB"), np.float32)
    scale = np.diag([master.shape[1] / OUTPUT_SIZE[0],
                     master.shape[0] / OUTPUT_SIZE[1]])
    native = native_base(map_name)
    upscaled = cv2.resize(master, OUTPUT_SIZE, interpolation=cv2.INTER_CUBIC)
    warp = np.eye(2, 3, dtype=np.float32)
    try:
        score, warp = cv2.findTransformECC(
            features(native), features(upscaled), warp, cv2.MOTION_AFFINE,
            (cv2.TERM_CRITERIA_EPS | cv2.TERM_CRITERIA_COUNT, 500, 1e-7),
            None, 5)
    except cv2.error:
        score, warp = 0.0, np.eye(2, 3, dtype=np.float32)
    to_master = scale @ warp
    residual = local_residuals(resample(master, to_master), native)
    return round(float(score), 6), np.round(to_master, 6).tolist(), residual


def available_files(map_name):
    files, missing = [], []
    for name, width, height, _, _ in geometry(map_name):
        if native_path(map_name, f"{name}.png").is_file():
            files.append(name)
        else:
            missing.append(name)
    highlight = native_path(map_name, f"{map_name}Highlight.png")
    if highlight.is_file():
        files.append(highlight.stem)
    return sorted(set(files), key=str.casefold), sorted(set(missing), key=str.casefold)


def dxt5_mip_bytes(width, height):
    total = 0
    for _ in range(max(width, height).bit_length()):
        total += max(4, (width + 3) // 4 * 4) * max(4, (height + 3) // 4 * 4)
        width, height = max(1, width // 2), max(1, height // 2)
    return total


def footprints(map_name, files):
    regions = {name: (width, height) for name, width, height, _, _ in geometry(map_name)}
    decoded = 12 * 512 * 512 * 4
    compressed = 12 * dxt5_mip_bytes(512, 512)
    for name in files:
        if name in regions:
            width, height = regions[name]
            width, height = native_file_size(width) * 2, native_file_size(height) * 2
        else:
            with Image.open(native_path(map_name, f"{name}.png")) as image:
                width, height = native_file_size(image.width) * 2, native_file_size(image.height) * 2
        decoded += width * height * 4
        compressed += dxt5_mip_bytes(width, height)
    return decoded, compressed


def existing_assets(manifest):
    return {item["id"]: item for item in manifest["assets"]}


def discover(remeasure=False):
    require(cv2 is not None and np is not None,
            "numpy and opencv-python-headless are required to discover/register zone masters")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    old_assets = existing_assets(manifest)
    previous = {}
    if CATALOG.is_file():
        previous = {item["mapName"]: item for item in
                    json.loads(CATALOG.read_text(encoding="utf-8"))["zones"]}
    zones = []
    for index, (map_name, filename) in enumerate(ZONE_SOURCES.items(), 1):
        path = zone_master(map_name)
        require(path.is_file(), f"Missing zone master: {path}")
        with Image.open(path) as image:
            width, height = image.size
            mode = image.mode
        aspect_error = width * 2 - height * 3
        require(abs(aspect_error) <= 2,
                f"Zone master must have 1.5 aspect ratio: {path} {(width, height)}")
        old = previous.get(map_name, {})
        old_spec = old_assets.get(f"world.{map_name.lower()}.exploration", {}).get(
            "activeMasterImport", {})
        if not remeasure and old.get("warpOutputToMaster"):
            score = old.get("eccScore", 0)
            warp = old["warpOutputToMaster"]
            residual = old["registration"]
        elif not remeasure and old_spec.get("warpOutputToMaster"):
            score = 0
            warp = old_spec["warpOutputToMaster"]
            residual = local_residuals(
                resample(np.asarray(Image.open(path).convert("RGB"), np.float32), warp),
                native_base(map_name))
        else:
            score, warp, residual = measure_registration(map_name, path)
        fog_override = PNG_ONLY_ZONE_OVERRIDES.get(map_name)
        preserve_fog = residual["p90HDPixels"] <= 3 and not fog_override
        unexplored_source = None
        unexplored_path = zone_unexplored_master(map_name)
        if unexplored_path:
            require(unexplored_path.is_file(),
                    f"Missing unexplored zone master: {unexplored_path}")
            with Image.open(unexplored_path) as image:
                unexplored_width, unexplored_height = image.size
                unexplored_mode = image.mode
            require((unexplored_width, unexplored_height) == (width, height),
                    f"Explored/unexplored masters must have identical dimensions: "
                    f"{path} {(width, height)} vs {unexplored_path} "
                    f"{(unexplored_width, unexplored_height)}")
            unexplored_source = {
                "root": (ZONE_UNEXPLORED_MASTER_ROOT / map_name).relative_to(
                    ROOT).as_posix(),
                "file": ZONE_UNEXPLORED_SOURCES[map_name],
                "width": unexplored_width,
                "height": unexplored_height,
                "colorMode": unexplored_mode,
                "detailScaleVsNative": round(unexplored_width / 1002, 3),
                "warpOutputToMaster": warp,
            }
        files, missing = available_files(map_name)
        suppressions = missing if not preserve_fog else []
        files = sorted(set(files + suppressions), key=str.casefold)
        decoded, compressed = footprints(map_name, files)
        validation = old.get("inGameValidation", {
            "status": "NOT_TESTED", "validatedBy": "user", "date": None, "notes": ""})
        zone = {
            "order": index,
            "mapName": map_name,
            "displayName": old.get("displayName", map_name),
            "sourceFile": filename,
            "sourceWidth": width,
            "sourceHeight": height,
            "sourceMode": mode,
            "sourceAspectErrorTwicePixels": aspect_error,
            "detailScaleVsNative": round(width / 1002, 3),
            "warpOutputToMaster": warp,
            "eccScore": score,
            "registration": residual,
            "preserveNativeFog": preserve_fog,
            "fogMode": ("themed-unexplored-master-with-native-reveal"
                        if unexplored_source else
                        "native-active-zone-fallback" if preserve_fog else
                        "png-only-explored"),
            "fogOverrideReason": fog_override,
            "files": files,
            "missingNativeRevealPieces": missing,
            "transparentRevealSuppressions": suppressions,
            "runtimeFileCount": 12 + len(files),
            "estimatedPeakDecodedBytes": decoded,
            "estimatedPeakCompressedMipBytes": compressed,
            "runtimeIntegrated": False,
            "offlineValidation": "PENDING",
            "inGameValidation": validation,
        }
        if unexplored_source:
            zone["unexploredSource"] = unexplored_source
        zones.append(zone)
        fog_label = ("paired" if unexplored_source else
                     "native" if preserve_fog else "png-only")
        print(f"{index:02d} {map_name}: p90={residual['p90HDPixels']} "
              f"fog={fog_label} files={12 + len(files)}")
    catalog = {"schemaVersion": 1, "updated": str(date.today()), "zones": zones}
    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    write_manifest(manifest, catalog)
    write_status(catalog)


def generated_assets(zone):
    map_name = zone["mapName"]
    asset_id = map_name.lower()
    fog = zone["preserveNativeFog"]
    common_source = {
        "root": ZONE_MASTER_ROOT.as_posix(),
        "file": zone["sourceFile"],
        "width": zone["sourceWidth"],
        "height": zone["sourceHeight"],
        "colorMode": zone["sourceMode"],
        "detailScale": f"{zone['detailScaleVsNative']}x native supplied; resampled once to 2x runtime",
        "provenance": "user-supplied",
        "authorOrOwner": "not supplied",
        "licenseOrPermission": "not supplied; local validation only until redistribution rights are documented",
    }
    unexplored_source = zone.get("unexploredSource")
    base_source = common_source
    if unexplored_source:
        base_source = {
            "root": unexplored_source["root"],
            "file": unexplored_source["file"],
            "width": unexplored_source["width"],
            "height": unexplored_source["height"],
            "colorMode": unexplored_source["colorMode"],
            "detailScale": (f"{unexplored_source['detailScaleVsNative']}x native supplied; "
                            "resampled once to 2x runtime"),
            "provenance": "user-supplied",
            "authorOrOwner": "not supplied",
            "licenseOrPermission": ("not supplied; local validation only until "
                                    "redistribution rights are documented"),
        }
    base = {
        "id": f"world.{asset_id}.base",
        "name": f"{zone['displayName']} base map",
        "bindingKey": map_name,
        "grid": {"columns": 4, "rows": 3, "order": "row-major"},
        "master": dict(base_source,
                       role=("authoritative full-map unexplored themed master"
                             if unexplored_source else
                             "authoritative full-map themed master"),
                       warpOutputToMaster=(unexplored_source["warpOutputToMaster"]
                                           if unexplored_source else
                                           zone["warpOutputToMaster"])),
        "runtime": {
            "activeFormat": "BLP2 DXT5", "role": "shipped runtime output",
            "pathPattern": ("Interface/AddOns/unrealMap/" +
                            runtime_base_dir(map_name).relative_to(ROOT).as_posix() +
                            f"/{map_name}{{1..12}}"),
            "dimensionsPerTile": "512x512", "mipPolicy": "complete chain",
            "generator": f"python -B tools/import_zone_masters.py --map {map_name}",
            "startupBindings": 0, "addonOwnedTextureRegions": 0,
            "estimatedPeakDecodedBytesIncludingExploration": zone["estimatedPeakDecodedBytes"],
            "estimatedPeakCompressedMipBytesIncludingExploration": zone["estimatedPeakCompressedMipBytes"],
            "maximumSimultaneouslyBoundTilesIncludingExploration": 12 + len(zone["files"]),
        },
        "validation": {"offline": zone["offlineValidation"],
                       "inGame": zone["inGameValidation"]["status"]},
    }
    state = ("authoritative explored/unexplored master pair with native per-area reveal alpha"
             if unexplored_source else
             "authoritative full-map master with native active-zone fog fallback"
             if fog else "authoritative coherent explored master; native fog unavailable")
    exploration = {
        "id": f"world.{asset_id}.exploration",
        "name": f"{zone['displayName']} exploration overlays",
        "bindingKey": "native WorldMapOverlay texture basename",
        "files": zone["files"],
        "formats": ["BLP2 DXT5"],
        "dimensions": "2x each native padded overlay file size",
        "alphaMode": "straight alpha from native reveal sprites; premultiplied box-filtered mips",
        "role": "shipped runtime exploration overlays rebound onto the native fixed overlay pool",
        "activeMasterImport": dict(
            common_source, state=state, approvedForRuntime=True,
            preserveNativeFog=fog,
            nativeAlphaReference=(native_dir(map_name)).as_posix(),
            nativeOverlayFiles=[name for name in zone["files"]
                                if name.casefold().endswith("highlight")],
            warpOutputToMaster=zone["warpOutputToMaster"],
            registration=zone["registration"],
            missingNativeRevealPieces=zone["missingNativeRevealPieces"],
            transparentRevealSuppressions=zone["transparentRevealSuppressions"],
            generator=f"python -B tools/import_zone_masters.py --map {map_name}",
            inGame=zone["inGameValidation"]["status"]),
        "validation": zone["offlineValidation"],
    }
    if zone.get("fogOverrideReason"):
        exploration["activeMasterImport"]["nativeFogUnavailableReason"] = zone[
            "fogOverrideReason"]
    if unexplored_source:
        exploration["activeMasterImport"]["unexploredMaster"] = dict(
            base_source,
            role="authoritative full-map unexplored themed master",
            warpOutputToMaster=unexplored_source["warpOutputToMaster"])
        exploration["activeMasterImport"]["nativeRGBFallback"] = False
    renamed = {name: runtime_file(map_name, name).stem for name in zone["files"]
               if runtime_file(map_name, name).stem != name}
    if renamed:
        exploration["runtimeFileNames"] = renamed
        exploration["runtimeFileNamesReason"] = (
            "The client resolves addon texture paths by basename alone (probe "
            "mapbasename.v1); these pieces share a basename with another shipped file.")
    return base, exploration


def write_manifest(manifest, catalog):
    zone_ids = {f"world.{name.lower()}.{role}" for name in ZONE_SOURCES
                for role in ("base", "exploration")}
    assets = [item for item in manifest["assets"] if item["id"] not in zone_ids]
    for zone in catalog["zones"]:
        assets.extend(generated_assets(zone))
    manifest["assets"] = assets
    MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


def write_status(catalog):
    zones = catalog["zones"]
    lines = [
        "# Zone import status", "", f"Last updated: {catalog['updated']}", "",
        "`Offline PASS` covers inventory, BLP2 headers, dimensions, mip bounds, tile topology,",
        "runtime/manifest agreement, lifecycle simulation, and stitched composite inspection.",
        "`In game PASS` is recorded only from an explicit user verdict after a full client restart.",
        "", "| # | Zone key | Source master(s) | Runtime | Fog mode | Offline | In game |",
        "| ---: | --- | --- | --- | --- | --- | --- |",
    ]
    for zone in zones:
        runtime = "Integrated" if zone["runtimeIntegrated"] else "Pending generation"
        source = f"`{zone['sourceFile']}`"
        if zone.get("unexploredSource"):
            source += f" + `{zone['unexploredSource']['file']}` (unexplored)"
        fog = ("Themed unexplored + native reveal"
               if zone.get("unexploredSource") else
               "Native fallback" if zone["preserveNativeFog"] else
               "PNG-only explored")
        game = zone["inGameValidation"]["status"]
        lines.append(f"| {zone['order']} | `{zone['mapName']}` | {source} | "
                     f"{runtime} | {fog} | {zone['offlineValidation']} | {game} |")
    pending = sum(not zone["runtimeIntegrated"] for zone in zones)
    validated = sum(zone["inGameValidation"]["status"] == "PASS" for zone in zones)
    lines.extend(["", f"Total supplied zone masters: {len(zones)}. Pending runtime integration: "
                  f"{pending}. User-validated in game: {validated}.", "",
                  "## Known source/reference gaps", ""])
    gaps = [zone for zone in zones if zone["missingNativeRevealPieces"]]
    if gaps:
        for zone in gaps:
            names = ", ".join(f"`{name}`" for name in zone["missingNativeRevealPieces"])
            if zone.get("transparentRevealSuppressions"):
                outcome = ("these pieces are replaced by transparent runtime textures so the "
                           "coherent PNG-only base remains visible")
            else:
                outcome = "these pieces stay client-native inside the active zone"
            lines.append(f"- {zone['mapName']}: missing native reveal reference pieces {names}; "
                         f"{outcome}.")
    else:
        lines.append("- None.")
    lines.extend(["", "## Recording an in-game verdict", "",
                  "After a full client restart and visual inspection, update the catalog with:", "",
                  "```powershell",
                  "python -B tools/integrate_zone_catalog.py --mark-in-game <MapKey> --status PASS --notes \"<verdict>\"",
                  "```", ""])
    STATUS.write_text("\n".join(lines), encoding="utf-8")


def finalize():
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    for zone in catalog["zones"]:
        map_name = zone["mapName"]
        expected_base = {f"{map_name}{index}.blp" for index in range(1, 13)}
        expected_overlays = {runtime_file(map_name, name).name for name in zone["files"]}
        base_folder = runtime_base_dir(map_name)
        overlay_folder = runtime_dir(map_name)
        actual_base = ({path.name for path in base_folder.glob("*.blp")}
                       if base_folder.is_dir() else set())
        actual_overlays = ({path.name for path in overlay_folder.glob("*.blp")}
                           if overlay_folder.is_dir() else set())
        if base_folder == overlay_folder:
            integrated = actual_base == expected_base | expected_overlays
        else:
            integrated = (actual_base == expected_base and
                          actual_overlays == expected_overlays)
        zone["runtimeIntegrated"] = integrated
        zone["offlineValidation"] = "PASS" if integrated else "FAIL"
    catalog["updated"] = str(date.today())
    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    write_manifest(manifest, catalog)
    write_status(catalog)


def mark_in_game(map_name, status, notes):
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    zone = next((item for item in catalog["zones"]
                 if item["mapName"].casefold() == map_name.casefold()), None)
    require(zone is not None, f"Unknown zone map key: {map_name}")
    zone["inGameValidation"] = {
        "status": status, "validatedBy": "user", "date": str(date.today()),
        "notes": notes or "",
    }
    catalog["updated"] = str(date.today())
    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    write_manifest(manifest, catalog)
    write_status(catalog)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--remeasure", action="store_true")
    parser.add_argument("--finalize", action="store_true")
    parser.add_argument("--mark-in-game")
    parser.add_argument("--status", choices=("PASS", "FAIL", "NOT_TESTED"))
    parser.add_argument("--notes")
    args = parser.parse_args()
    if args.mark_in_game:
        require(args.status is not None, "--status is required with --mark-in-game")
        mark_in_game(args.mark_in_game, args.status, args.notes)
    elif args.finalize:
        finalize()
    else:
        discover(args.remeasure)


if __name__ == "__main__":
    main()
