#!/usr/bin/env python3
"""Build 13-inch iPad App Store marketing screenshots from Simulator captures."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

import generate_screenshots as base


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw-ipad"
OUT = ROOT / "final-ipad"

WIDTH = 2064
HEIGHT = 2752

# The shared drawing helpers read the canvas size from module globals.
base.WIDTH = WIDTH
base.HEIGHT = HEIGHT
base.RAW = RAW
base.OUT = OUT

SCREEN_Y = 560
SCREEN_WIDTH = 1560

# AdMob banner on the iPad gameplay screens.
AD_BANNER = (700, 2592, 1364, 2712)
# iPadOS window resize grabber in the bottom-right corner of every capture.
RESIZE_GRABBER = (1996, 2686, 2064, 2752)


def erase_rows(screen: Image.Image, box: tuple[int, int, int, int], sample_x: int) -> None:
    """Paint over a region using the background color of each row at sample_x."""
    left, top, right, bottom = box
    draw = ImageDraw.Draw(screen)
    for y in range(top, bottom):
        draw.line((left, y, right, y), fill=screen.getpixel((sample_x, y)))


def draw_decorations(draw: ImageDraw.ImageDraw, variant: int) -> None:
    # Keep circles at the edges so they never sit behind the one-line headline.
    if variant == 1:
        draw.ellipse((1800, -140, 2260, 320), fill=base.YELLOW)
        draw.ellipse((-200, 380, 160, 740), fill=(255, 255, 255, 110))
        draw.ellipse((1840, 420, 2140, 720), fill=(255, 255, 255, 90))
    elif variant == 2:
        draw.ellipse((-220, -120, 240, 340), fill=(255, 186, 154))
        draw.ellipse((1820, 380, 2200, 760), fill=(142, 220, 177))
        draw.ellipse((1880, 60, 2000, 180), fill=base.YELLOW)
    elif variant == 3:
        draw.ellipse((1800, -160, 2280, 320), fill=(255, 154, 134))
        draw.ellipse((-200, 400, 180, 780), fill=(124, 205, 237))
    else:
        draw.ellipse((-220, -100, 260, 380), fill=(155, 132, 230))
        draw.ellipse((1820, 340, 2240, 760), fill=base.YELLOW)


def build_page(
    source: str,
    output: str,
    title: str,
    subtitle: str,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    variant: int,
    has_ad: bool = False,
) -> Path:
    canvas = base.gradient(top, bottom).convert("RGBA")
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_decorations(draw, variant)
    base.draw_brand(draw, canvas)
    base.draw_headline(draw, title, subtitle)

    screen = Image.open(base.source_path(source)).convert("RGBA")
    erase_rows(screen, RESIZE_GRABBER, sample_x=1980)
    if has_ad:
        erase_rows(screen, AD_BANNER, sample_x=60)
    screen_height = round(screen.height * SCREEN_WIDTH / screen.width)
    screen = base.rounded_image(screen, (SCREEN_WIDTH, screen_height), 56)
    base.paste_with_shadow(canvas, screen, ((WIDTH - SCREEN_WIDTH) // 2, SCREEN_Y), radius=56)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / output
    canvas.convert("RGB").save(path)
    return path


def build_contact_sheet(paths: list[Path]) -> None:
    thumb_width = 516
    thumb_height = 688
    sheet = Image.new("RGB", (thumb_width * len(paths), thumb_height), (235, 238, 240))
    for index, path in enumerate(paths):
        thumb = Image.open(path).resize((thumb_width, thumb_height), Image.Resampling.LANCZOS)
        sheet.paste(thumb, (index * thumb_width, 0))
    sheet.save(OUT / "preview-contact-sheet.png")


def main() -> None:
    pages = [
        build_page(
            "03-gameplay.png",
            "01-photo-tower.png",
            "写真が、タワーになる。",
            "お気に入りを積み上げる、新感覚ゲーム",
            base.SKY,
            base.CREAM,
            1,
            has_ad=True,
        ),
        build_page(
            "02-stage-editor.png",
            "02-create-stage.png",
            "好きな写真でステージをつくる",
            "切り抜いた素材を選んで、順番を決めるだけ",
            (255, 231, 187),
            base.CREAM,
            2,
        ),
        build_page(
            "01-home.png",
            "03-my-stages.png",
            "自分だけのステージをいつでも遊べる",
            "お気に入りの組み合わせを保存してすぐプレイ",
            (205, 242, 225),
            base.CREAM,
            3,
        ),
        build_page(
            "04-game-over.png",
            "04-share-result.png",
            "どこまで積める？",
            "結果はスクショでかんたんシェア",
            (211, 205, 250),
            (226, 244, 252),
            4,
            has_ad=True,
        ),
    ]
    build_contact_sheet(pages)
    for page in pages:
        print(page)


if __name__ == "__main__":
    main()
