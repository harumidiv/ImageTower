#!/usr/bin/env python3
"""Build 6.9-inch App Store marketing screenshots from Simulator captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"
OUT = ROOT / "final"
ASSETS = ROOT / "game-assets"
APP_ICON = ROOT.parent / "ImageTower" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"

WIDTH = 1320
HEIGHT = 2868

INK = (31, 42, 47)
SECONDARY = (84, 100, 103)
CORAL = (255, 99, 71)
YELLOW = (255, 205, 74)
SKY = (188, 230, 250)
CREAM = (255, 248, 224)


def source_path(name: str) -> Path:
    """Accept Simulator captures saved with either .png or .png.png."""
    path = RAW / name
    if path.exists():
        return path
    doubled_extension = RAW / f"{name}.png"
    if doubled_extension.exists():
        return doubled_extension
    raise FileNotFoundError(f"Screenshot not found: {path}")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT, size=size, index=3 if bold else 1)


def gradient(top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), top)
    draw = ImageDraw.Draw(image)
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        draw.line((0, y, WIDTH, y), fill=color)
    return image


def rounded_image(image: Image.Image, size: tuple[int, int], radius: int) -> Image.Image:
    image = image.convert("RGBA").resize(size, Image.Resampling.LANCZOS)
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    image.putalpha(mask)
    return image


def paste_with_shadow(canvas: Image.Image, image: Image.Image, xy: tuple[int, int], radius: int = 76) -> None:
    x, y = xy
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    box = (x - 12, y + 16, x + image.width + 12, y + image.height + 40)
    shadow_draw.rounded_rectangle(box, radius=radius + 12, fill=(22, 42, 52, 100))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(shadow, (0, 0), shadow)

    frame = Image.new("RGBA", (image.width + 24, image.height + 24), (255, 255, 255, 255))
    frame_mask = Image.new("L", frame.size, 0)
    ImageDraw.Draw(frame_mask).rounded_rectangle((0, 0, frame.width, frame.height), radius=radius + 12, fill=255)
    frame.putalpha(frame_mask)
    canvas.paste(frame, (x - 12, y - 12), frame)
    canvas.paste(image, (x, y), image)


def draw_brand(draw: ImageDraw.ImageDraw, canvas: Image.Image) -> None:
    icon = rounded_image(Image.open(APP_ICON), (82, 82), 20)
    brand_font = font(40, bold=True)
    label = "IMAGE TOWER"
    bbox = draw.textbbox((0, 0), label, font=brand_font)
    total = icon.width + 20 + (bbox[2] - bbox[0])
    x = (WIDTH - total) // 2
    canvas.paste(icon, (x, 68), icon)
    draw.text((x + icon.width + 20, 84), label, font=brand_font, fill=INK)


def draw_headline(draw: ImageDraw.ImageDraw, title: str, subtitle: str) -> None:
    title_font = font(102, bold=True)
    title_bbox = draw.multiline_textbbox((0, 0), title, font=title_font, spacing=12, align="center")
    title_w = title_bbox[2] - title_bbox[0]
    title_h = title_bbox[3] - title_bbox[1]
    draw.multiline_text(
        ((WIDTH - title_w) // 2, 205),
        title,
        font=title_font,
        fill=INK,
        spacing=12,
        align="center",
    )

    sub_font = font(39, bold=True)
    sub_bbox = draw.textbbox((0, 0), subtitle, font=sub_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    draw.text(((WIDTH - sub_w) // 2, 235 + title_h + 30), subtitle, font=sub_font, fill=SECONDARY)


def draw_decorations(draw: ImageDraw.ImageDraw, variant: int) -> None:
    if variant == 1:
        draw.ellipse((1070, 170, 1410, 510), fill=YELLOW)
        draw.ellipse((-120, 390, 145, 655), fill=(255, 255, 255, 110))
        draw.ellipse((1010, 510, 1240, 740), fill=(255, 255, 255, 90))
    elif variant == 2:
        draw.ellipse((-120, 90, 245, 455), fill=(255, 186, 154))
        draw.ellipse((1115, 360, 1385, 630), fill=(142, 220, 177))
        draw.ellipse((1035, 90, 1145, 200), fill=YELLOW)
    elif variant == 3:
        draw.ellipse((1050, 110, 1395, 455), fill=(255, 154, 134))
        draw.ellipse((-80, 470, 190, 740), fill=(124, 205, 237))
    else:
        draw.ellipse((-120, 140, 235, 495), fill=(155, 132, 230))
        draw.ellipse((1070, 330, 1400, 660), fill=YELLOW)


AD_BANNER = (150, 2595, 1170, 2790)


def erase_ad(screen: Image.Image, box: tuple[int, int, int, int] = AD_BANNER) -> None:
    """Paint over the AdMob banner using the background color of each row."""
    left, top, right, bottom = box
    draw = ImageDraw.Draw(screen)
    for y in range(top, bottom):
        draw.line((left, y, right, y), fill=screen.getpixel((60, y)))


def place_cutout(canvas: Image.Image, name: str, width: int, xy: tuple[int, int], angle: float = 0) -> None:
    cutout = Image.open(ASSETS / name).convert("RGBA")
    height = round(cutout.height * width / cutout.width)
    cutout = cutout.resize((width, height), Image.Resampling.LANCZOS)
    if angle:
        cutout = cutout.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    shadow = Image.new("RGBA", cutout.size, (0, 0, 0, 0))
    shadow.putalpha(cutout.getchannel("A").filter(ImageFilter.GaussianBlur(18)))
    black = Image.new("RGBA", cutout.size, (20, 35, 45, 65))
    black.putalpha(shadow.getchannel("A").point(lambda p: min(72, p)))
    canvas.paste(black, (xy[0] + 10, xy[1] + 22), black)
    canvas.paste(cutout, xy, cutout)


def build_page(
    source: str,
    output: str,
    title: str,
    subtitle: str,
    top: tuple[int, int, int],
    bottom: tuple[int, int, int],
    variant: int,
    crop_bottom: int,
    screen_y: int = 770,
    screen_width: int = 1060,
    home_collage: bool = False,
    has_ad: bool = False,
) -> Path:
    canvas = gradient(top, bottom).convert("RGBA")
    draw = ImageDraw.Draw(canvas, "RGBA")
    draw_decorations(draw, variant)
    draw_brand(draw, canvas)
    draw_headline(draw, title, subtitle)

    screen = Image.open(source_path(source)).convert("RGBA")
    if has_ad:
        erase_ad(screen)
    screen = screen.crop((0, 0, 1320, crop_bottom))
    screen_height = round(screen.height * screen_width / screen.width)
    screen = rounded_image(screen, (screen_width, screen_height), 74)
    paste_with_shadow(canvas, screen, ((WIDTH - screen_width) // 2, screen_y))

    if home_collage:
        # The home screen intentionally has open space; use the user's cutouts to show what fills a stage.
        place_cutout(canvas, "01-cat.png", 310, (80, 2260), -8)
        place_cutout(canvas, "02-tomatoes.png", 345, (495, 2290), 6)
        place_cutout(canvas, "04-jump-man.png", 290, (960, 2240), 7)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / output
    canvas.convert("RGB").save(path, quality=96)
    return path


def build_contact_sheet(paths: list[Path]) -> None:
    thumb_width = 330
    thumb_height = 717
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
            "写真が、\nタワーになる。",
            "お気に入りを積み上げる、新感覚ゲーム",
            SKY,
            CREAM,
            1,
            HEIGHT,
            screen_y=760,
            screen_width=920,
            has_ad=True,
        ),
        build_page(
            "02-stage-editor.png",
            "02-create-stage.png",
            "好きな写真で\nステージをつくる",
            "切り抜いた素材を選んで、順番を決めるだけ",
            (255, 231, 187),
            CREAM,
            2,
            2500,
            screen_y=770,
        ),
        build_page(
            "01-home.png",
            "03-my-stages.png",
            "自分だけのステージを\nいつでも遊べる",
            "お気に入りの組み合わせを保存してすぐプレイ",
            (205, 242, 225),
            CREAM,
            3,
            1800,
            screen_y=770,
            home_collage=True,
        ),
        build_page(
            "04-game-over.png",
            "04-share-result.png",
            "どこまで積める？",
            "結果はスクショでかんたんシェア",
            (211, 205, 250),
            (226, 244, 252),
            4,
            HEIGHT,
            screen_y=730,
            screen_width=940,
            has_ad=True,
        ),
    ]
    build_contact_sheet(pages)
    for page in pages:
        print(page)


if __name__ == "__main__":
    main()
