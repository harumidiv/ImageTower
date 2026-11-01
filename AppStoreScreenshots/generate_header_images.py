#!/usr/bin/env python3
"""Build wide header artwork (5244x2950 and 3840x1646) from the iPhone Duo Simulator captures."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

import generate_screenshots as base
from generate_duo_screenshots import AD_BANNER, erase_rows


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw-duo"
OUT = ROOT / "final-header"
CUTOUTS = ROOT / "source-cutouts"

SIZES = [(5244, 2950), (3840, 1646)]

# Every element sits within this many units of the center horizontally.
CONTENT_HALF_WIDTH = 0.95

base.RAW = RAW

TITLE = "写真が、\nタワーになる。"
SUBTITLE = "お気に入りを積み上げる、新感覚ゲーム"


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size, top)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / (height - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line((0, y, width, y), fill=color)
    return image


def phone_card(source: str, height: int, angle: float, has_ad: bool) -> Image.Image:
    """A screen capture in a white rounded frame, rotated, with a soft drop shadow."""
    screen = Image.open(base.source_path(source)).convert("RGBA")
    if has_ad:
        erase_rows(screen, AD_BANNER, sample_x=60)
    width = round(screen.width * height / screen.height)
    radius = round(width * 0.045)
    border = round(width * 0.018)
    screen = base.rounded_image(screen, (width, height), radius)

    card = Image.new("RGBA", (width + border * 2, height + border * 2), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle(
        (0, 0, card.width, card.height), radius=radius + border, fill=(255, 255, 255, 255)
    )
    card.paste(screen, (border, border), screen)

    pad = round(height * 0.08)
    framed = Image.new("RGBA", (card.width + pad * 2, card.height + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", framed.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (pad, pad + round(height * 0.02), pad + card.width, pad + card.height + round(height * 0.02)),
        radius=radius + border,
        fill=(22, 42, 52, 90),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(round(height * 0.025)))
    framed.alpha_composite(shadow)
    framed.alpha_composite(card, (pad, pad))
    return framed.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)


def cutout(name: str, width: int, angle: float) -> Image.Image:
    image = Image.open(CUTOUTS / name).convert("RGBA")
    image = image.crop(image.getbbox())
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    if angle:
        image = image.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)

    pad = round(width * 0.1)
    framed = Image.new("RGBA", (image.width + pad * 2, image.height + pad * 2), (0, 0, 0, 0))
    alpha = Image.new("L", framed.size, 0)
    alpha.paste(image.getchannel("A").point(lambda p: min(72, p)), (pad + round(width * 0.02), pad + round(width * 0.05)))
    shadow = Image.new("RGBA", framed.size, (20, 35, 45, 255))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(round(width * 0.04))))
    framed.alpha_composite(shadow)
    framed.alpha_composite(image, (pad, pad))
    return framed


def paste_centered(canvas: Image.Image, image: Image.Image, center: tuple[float, float]) -> None:
    canvas.alpha_composite(image, (round(center[0] - image.width / 2), round(center[1] - image.height / 2)))


def draw_text_block(canvas: Image.Image, center_x: float, center_y: float, unit: int) -> None:
    draw = ImageDraw.Draw(canvas)
    icon = base.rounded_image(Image.open(base.APP_ICON), (round(unit * 0.11), round(unit * 0.11)), round(unit * 0.026))
    brand_font = base.font(round(unit * 0.05), bold=True)
    title_font = base.font(round(unit * 0.115), bold=True)
    sub_font = base.font(round(unit * 0.042), bold=True)
    spacing = round(unit * 0.016)

    brand = "のっけタワー"
    brand_box = draw.textbbox((0, 0), brand, font=brand_font)
    title_box = draw.multiline_textbbox((0, 0), TITLE, font=title_font, spacing=spacing, align="center")
    sub_box = draw.textbbox((0, 0), SUBTITLE, font=sub_font)

    gap = round(unit * 0.05)
    block_height = icon.height + gap + (title_box[3] - title_box[1]) + gap + (sub_box[3] - sub_box[1])
    y = round(center_y - block_height / 2)

    brand_width = icon.width + round(unit * 0.024) + (brand_box[2] - brand_box[0])
    x = round(center_x - brand_width / 2)
    canvas.alpha_composite(icon, (x, y))
    draw.text(
        (x + icon.width + round(unit * 0.024), y + (icon.height - (brand_box[3] - brand_box[1])) // 2 - brand_box[1]),
        brand,
        font=brand_font,
        fill=base.INK,
    )
    y += icon.height + gap

    title_width = title_box[2] - title_box[0]
    draw.multiline_text(
        (round(center_x - title_width / 2), y - title_box[1]),
        TITLE,
        font=title_font,
        fill=base.INK,
        spacing=spacing,
        align="center",
    )
    y += title_box[3] - title_box[1] + gap

    sub_width = sub_box[2] - sub_box[0]
    draw.text((round(center_x - sub_width / 2), y - sub_box[1]), SUBTITLE, font=sub_font, fill=base.SECONDARY)


def build_header(size: tuple[int, int]) -> Path:
    width, height = size
    # Lay everything out around the center in units of the height, so the wide
    # variant just gains more sky on the left and right. Shrink the unit when the
    # canvas is too narrow to hold the content.
    unit = min(height, round(width / 2 / CONTENT_HALF_WIDTH))
    cx, cy = width / 2, height / 2

    canvas = gradient(size, base.SKY, base.CREAM).convert("RGBA")
    draw = ImageDraw.Draw(canvas, "RGBA")
    for (x, y, r), fill in [
        ((-0.62, -0.38, 0.17), base.YELLOW),
        ((0.95, -0.36, 0.13), (255, 255, 255, 120)),
        ((-0.98, 0.34, 0.12), (255, 186, 154)),
        ((1.02, 0.30, 0.16), (142, 220, 177)),
        ((0.12, 0.44, 0.06), (255, 255, 255, 110)),
    ]:
        px, py, pr = cx + x * unit, cy + y * unit, r * unit
        draw.ellipse((px - pr, py - pr, px + pr, py + pr), fill=fill)

    draw_text_block(canvas, cx - 0.50 * unit, cy, unit)

    phone_height = round(unit * 0.66)
    paste_centered(canvas, phone_card("04-game-over.png", round(phone_height * 0.88), -7, True), (cx + 0.64 * unit, cy + 0.03 * unit))
    paste_centered(canvas, phone_card("03-gameplay.png", phone_height, 4, True), (cx + 0.27 * unit, cy - 0.01 * unit))

    paste_centered(canvas, cutout("01-cat.png", round(unit * 0.20), 10), (cx - 0.04 * unit, cy + 0.34 * unit))
    paste_centered(canvas, cutout("02-tomatoes.png", round(unit * 0.15), -8), (cx + 0.86 * unit, cy + 0.36 * unit))
    paste_centered(canvas, cutout("04-jump-man.png", round(unit * 0.13), -12), (cx + 0.86 * unit, cy - 0.33 * unit))

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"header-{width}x{height}.png"
    canvas.convert("RGB").save(path)
    return path


def main() -> None:
    for size in SIZES:
        print(build_header(size))


if __name__ == "__main__":
    main()
