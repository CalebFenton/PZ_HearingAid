#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow"]
# ///
"""Crops the screenshots that `dev/run-debug-client.sh --promo` saves into the named images that
compose.py lays out. The client script runs it; by hand:

    art/promo/extract.py <cache dir>

Every image in captures/ is replaced. The harness takes each shot of something other than the world
twice, on black and on white: a pixel that reads k on black and w on white has alpha a = 1 - (w - k)
and colour k / a.
"""
import json
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

CAPTURES = Path(__file__).resolve().parent / "captures"


def load(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255


def matte(black, white):
    alpha = np.clip(1 - (white - black).mean(axis=2), 0, 1)[..., None]
    colour = np.clip(black / np.maximum(alpha, 1 / 255), 0, 1)
    return Image.fromarray(np.round(np.dstack([colour, alpha]) * 255).astype(np.uint8), "RGBA")


def main():
    cache = Path(sys.argv[1])
    screenshots = cache / "Screenshots"
    manifest = json.loads((cache / "Lua" / "HearingAidPromo.json").read_text())
    if CAPTURES.exists():
        shutil.rmtree(CAPTURES)
    CAPTURES.mkdir()
    count = 0
    for shot in manifest["shots"]:
        name = shot["name"]
        if shot["matte"]:
            image = matte(load(screenshots / f"promo_{name}_k.png"), load(screenshots / f"promo_{name}_w.png"))
        else:
            image = Image.open(screenshots / f"promo_{name}.png").convert("RGB")
        # Screenshots are in pixels and regions in UI units, which differ on a HiDPI display.
        scale = image.width / manifest["screen"]["w"]
        for r in shot["regions"]:
            box = [round(v * scale) for v in (r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])]
            image.crop(box).save(CAPTURES / f"{r['name']}.png", optimize=True)
            count += 1
    print(f"extract: {count} images in {CAPTURES}")


main()
