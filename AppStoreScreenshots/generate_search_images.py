#!/usr/bin/env python3
"""Build App Store search-result artwork (5244x2950, 3840x2560, 1920x1280).

The App Store search result shows only roughly the central half of the
artwork (measured from a device capture: ~47% of the width and height), so
the title and app screens are packed into a small centered 3:2 safe area.
The rest of the canvas only carries decoration that is fine to lose.
"""

from __future__ import annotations

from pathlib import Path

from PIL import ImageDraw

import generate_header_images as header
from generate_header_images import base, cutout, draw_text_block, gradient, paste_centered, phone_card


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "final-search"

SIZES = [(5244, 2950), (3840, 2560), (1920, 1280)]

# Important content must stay inside a centered 3:2 box, shrunk by this factor.
SAFE_ASPECT = 3 / 2
SAFE_SCALE = 0.42

# Extent of the content around the center, in units.
CONTENT_HALF_WIDTH = 0.86
CONTENT_HALF_HEIGHT = 0.47


def layout_unit(width: int, height: int) -> int:
    safe_w = min(width, height * SAFE_ASPECT) * SAFE_SCALE
    safe_h = min(height, width / SAFE_ASPECT) * SAFE_SCALE
    return round(min(safe_w / (2 * CONTENT_HALF_WIDTH), safe_h / (2 * CONTENT_HALF_HEIGHT)))


def build_search_image(size: tuple[int, int], debug: bool = False) -> Path:
    width, height = size
    unit = layout_unit(width, height)
    cx, cy = width / 2, height / 2

    canvas = gradient(size, base.SKY, base.CREAM).convert("RGBA")
    draw = ImageDraw.Draw(canvas, "RGBA")
    # Decorative circles: placed relative to the canvas edges so wide canvases stay balanced.
    hw, hh = width / 2, height / 2
    for (x, y, r), fill in [
        ((-0.66, -0.70, 0.17), base.YELLOW),
        ((0.92, -0.80, 0.13), (255, 255, 255, 120)),
        ((-0.98, 0.70, 0.12), (255, 186, 154)),
        ((0.98, 0.62, 0.16), (142, 220, 177)),
        ((0.10, 0.86, 0.06), (255, 255, 255, 110)),
    ]:
        px, py, pr = cx + x * hw, cy + y * hh, r * unit
        draw.ellipse((px - pr, py - pr, px + pr, py + pr), fill=fill)

    draw_text_block(canvas, cx - 0.44 * unit, cy, unit)

    phone_height = round(unit * 0.66)
    paste_centered(canvas, phone_card("04-game-over.png", round(phone_height * 0.88), -7, True), (cx + 0.53 * unit, cy + 0.03 * unit))
    paste_centered(canvas, phone_card("03-gameplay.png", phone_height, 4, True), (cx + 0.19 * unit, cy - 0.01 * unit))

    paste_centered(canvas, cutout("01-cat.png", round(unit * 0.19), 10), (cx - 0.08 * unit, cy + 0.33 * unit))
    paste_centered(canvas, cutout("02-tomatoes.png", round(unit * 0.13), -8), (cx + 0.70 * unit, cy + 0.33 * unit))
    paste_centered(canvas, cutout("04-jump-man.png", round(unit * 0.12), -12), (cx + 0.70 * unit, cy - 0.33 * unit))

    # Decoration outside the safe area, positioned relative to the canvas edges.
    for name, w, angle, (x, y) in [
        ("03-cone-man.png", 0.10, -10, (-0.80, -0.62)),
        ("08-vr-man.png", 0.10, 8, (-0.84, 0.60)),
        ("05-excited-man.png", 0.10, 6, (0.82, -0.62)),
        ("06-eagle-man.png", 0.11, -6, (0.80, 0.62)),
        ("07-sign.png", 0.08, 12, (-0.22, 0.80)),
    ]:
        paste_centered(canvas, cutout(name, round(min(width, height) * w), angle), (cx + x * hw, cy + y * hh))

    if debug:
        safe_w = min(width, height * SAFE_ASPECT) * SAFE_SCALE
        safe_h = min(height, width / SAFE_ASPECT) * SAFE_SCALE
        ImageDraw.Draw(canvas).rectangle(
            (cx - safe_w / 2, cy - safe_h / 2, cx + safe_w / 2, cy + safe_h / 2), outline=(255, 0, 0), width=max(2, width // 600)
        )

    OUT.mkdir(parents=True, exist_ok=True)
    suffix = "-debug" if debug else ""
    path = OUT / f"search-{width}x{height}{suffix}.png"
    canvas.convert("RGB").save(path)
    return path


def main() -> None:
    import sys

    debug = "--debug" in sys.argv
    for size in SIZES:
        print(build_search_image(size, debug=debug))


if __name__ == "__main__":
    main()
