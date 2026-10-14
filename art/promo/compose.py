#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved, and the mod's
poster, Workshop preview and mod-list icon. Rerun it after editing a layout; recapture only when
the game's look changes:

    art/promo/compose.py

Writes images/*.png, 42/poster.png, 42/hearing_aid_icon.png and the repository's preview.png. The
icon starts from art/drawings/hearing_aid.xcf, the drawing Item_HearingAid.png came from, which
ImageMagick's `magick` flattens. Every README image is 1260 pixels wide, which the Workshop page
shows at 630, so it stays sharp on high-density screens. Interface captures and icons are scaled by
whole numbers with nearest-neighbour sampling, so their pixels stay crisp. Item names and the other
text the game shows come from captures/promo.json, which the game wrote in the last --promo run.
"""
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
CAPTURES = HERE / "captures"
OUT = HERE / "images"
FONT = HERE / "fonts" / "NotoSans.ttf"
REPO = HERE.parent.parent
MOD = REPO / "Contents" / "mods" / "HearingAid" / "42"
DRAWING = HERE.parent / "drawings" / "hearing_aid.xcf"
# The same picture serves as the mod list's poster and the Workshop preview, which takes a square of
# 256 or 512 pixels, at most this many bytes (SteamWorkshopItem.validatePreviewImage).
POSTER_FILES = [MOD / "poster.png", REPO / "preview.png"]
POSTER_SIZE = 512
PREVIEW_BYTES = 1_024_000
PROMO = json.loads((CAPTURES / "promo.json").read_text())
NAMES = PROMO["names"]
STRINGS = PROMO["strings"]

WIDTH = 1260
BACKGROUND = (24, 26, 31)
PANEL = (36, 39, 46)
TEXT = (232, 234, 238)
MUTED = (160, 166, 176)
TIERS = {
    "broken": (150, 150, 150),
    "basic": (190, 184, 110),
    "efficient": (110, 160, 200),
    "boosted": (200, 90, 85),
}
# Each tool with the words before its name.
TOOLS = [("screwdriver", ""), ("tweezers", ""), ("reading_glasses", ""), ("loupe", "or a "),
         ("magnifying_glass", "or a ")]
# Each recipe's title, skill level, source tier, parts with the words after their names, and result.
RECIPES = [
    ("Repair", 2, "broken", [("earbuds", ""), ("alcohol_wipes", ""), ("glue", "")], "basic"),
    ("Optimize", 4, "basic", [("digital_watch", ""), ("electric_wire", ""), ("glue", "")], "efficient"),
    ("Boost", 8, "efficient", [("amplifier", ""), ("microphone", ""), ("electric_wire", " ×2"), ("epoxy", ""),
                               ("scalpel", "\n(kept)")], "boosted"),
]
# Where the aid sits in a back_close head capture, as fractions of its width and height.
EAR_BOX = (0.36, 0.18, 0.96, 0.78)
# The part of world_corpse.png around the corpse, the character and the loot window.
CORPSE_BOX = (120, 90, 1000, 585)


def font(size, weight="Regular"):
    face = ImageFont.truetype(str(FONT), size)
    face.set_variation_by_name(weight)
    return face


def capture(name, border=0):
    """A capture, less `border` pixels at each edge, where a panel's outline can show."""
    image = Image.open(CAPTURES / f"{name}.png").convert("RGBA")
    return image.crop((border, border, image.width - border, image.height - border))


def trim(image, pad=0):
    left, top, right, bottom = image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    return image.crop((left - pad, top - pad, right + pad, bottom + pad))


def fit(image, width, height):
    scale = min(width / image.width, height / image.height)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


def pixels(image, factor):
    return image.resize((image.width * factor, image.height * factor), Image.NEAREST)


def fraction(image, box):
    return image.crop(tuple(round(f * size) for f, size in zip(box, (image.width, image.height) * 2)))


def canvas(height, width=WIDTH):
    """A dark card with a faint vertical gradient."""
    image = Image.new("RGBA", (width, height), BACKGROUND + (255,))
    shade = Image.linear_gradient("L").resize((width, height)).point(lambda v: v * 0.35)
    image.paste(Image.new("RGBA", (width, height), (12, 13, 16, 255)), (0, 0), shade)
    return image


def paste(base, image, centre, shadow=True):
    """Pastes image centred on centre, over a soft shadow of itself."""
    x, y = round(centre[0] - image.width / 2), round(centre[1] - image.height / 2)
    if shadow:
        alpha = image.getchannel("A").point(lambda a: a * 0.6)
        blur = Image.new("RGBA", (image.width + 40, image.height + 40), (0, 0, 0, 0))
        blur.paste(Image.new("RGBA", image.size, (0, 0, 0, 255)), (20, 20), alpha)
        blur = blur.filter(ImageFilter.GaussianBlur(10))
        base.alpha_composite(blur, (x - 20 + 4, y - 20 + 8))
    base.alpha_composite(image, (x, y))


def text(base, xy, string, size, weight="Regular", fill=TEXT, anchor="la"):
    ImageDraw.Draw(base).multiline_text(xy, string, font=font(size, weight), fill=fill, anchor=anchor,
                                        align="center" if anchor[0] == "m" else "left", spacing=4)


def panel(base, box, accent=None):
    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle(box, 18, fill=PANEL + (255,))
    if accent:
        draw.rectangle((box[0] + 28, box[1], box[2] - 28, box[1] + 5), fill=accent + (255,))


def arrow(base, centre, colour=MUTED):
    x, y = centre
    draw = ImageDraw.Draw(base)
    draw.rectangle((x - 22, y - 4, x + 6, y + 4), fill=colour)
    draw.polygon([(x + 4, y - 14), (x + 22, y), (x + 4, y + 14)], fill=colour)


def save(image, name):
    path = OUT / f"{name}.png"
    path.parent.mkdir(exist_ok=True)
    image.convert("RGB").save(path, optimize=True)
    print(f"compose: {path.relative_to(REPO)} {image.width}x{image.height}")


def save_poster(image):
    for path in POSTER_FILES:
        image.convert("RGB").save(path, optimize=True)
        assert path.stat().st_size <= PREVIEW_BYTES, f"{path.name} is over the Workshop's {PREVIEW_BYTES} bytes"
        print(f"compose: {path.relative_to(REPO)} {image.width}x{image.height}")


def wrap(name):
    """Breaks a name of more than one word before its last word."""
    return "\n".join(name.rsplit(" ", 1))


def tier_label(tier):
    """The tier's name, broken before the plain aid's name it ends in."""
    basic = NAMES["basic"]
    return NAMES[tier].replace(" " + basic, "\n" + basic)


# Images ------------------------------------------------------------------------------------------


def banner():
    image = canvas(420)
    text(image, (70, 210), STRINGS["modName"], 88, "Bold", anchor="lm")
    positions = [(770, 130), (910, 280), (1050, 130), (1160, 285)]
    for tier, centre in zip(TIERS, positions):
        paste(image, fit(trim(capture(f"model_{tier}")), 210, 210), centre)
    return image


def poster():
    """The banner's title and four models, stacked for a square. The mod list and the Workshop show
    it at about 196 pixels, so the title is large."""
    image = canvas(POSTER_SIZE, POSTER_SIZE)
    text(image, (POSTER_SIZE / 2, 74), STRINGS["modName"], 76, "Bold", anchor="mm")
    positions = [(140, 215), (372, 215), (140, 390), (372, 390)]
    for tier, centre in zip(TIERS, positions):
        paste(image, fit(trim(capture(f"model_{tier}")), 200, 160), centre)
    return image


# The mod list draws the icon at 22 to 28 pixels with smooth scaling, where the drawing's thin
# outline and tube blur away. These are in pixels of the drawing, which is about 20 times the icon.
ICON_SIZE = 32
TUBE_GROWTH = 10
OUTLINE = 12
OUTLINE_COLOUR = (20, 18, 30, 255)
TUBE_COLOUR = (178, 160, 206, 255)
BODY_COLOUR = (150, 142, 80, 255)
LED_COLOUR = (70, 255, 70, 255)


def over(image, threshold):
    return image.point(lambda v: 255 if v > threshold else 0)


def both(*masks):
    result = masks[0]
    for m in masks[1:]:
        result = ImageChops.multiply(result, m)
    return result


def grow(image, pixels):
    return image.filter(ImageFilter.MaxFilter(2 * pixels + 1))


def icon():
    with tempfile.TemporaryDirectory() as tmp:
        flat = Path(tmp) / "drawing.png"
        subprocess.run(["magick", str(DRAWING), "-background", "none", "-layers", "merge", str(flat)], check=True)
        image = Image.open(flat).convert("RGBA")
    red, green, blue, alpha = image.split()
    solid = over(alpha, 128)
    fill = lambda m, colour: image.paste(Image.new("RGBA", image.size, colour), (0, 0), m)
    # The yellow button would compete with the LED, the one bright spot left at icon size.
    yellow = both(over(red, 170), over(green, 150), over(blue, 60).point(lambda v: 255 - v), solid)
    fill(grow(yellow, 1), BODY_COLOUR)
    led = both(over(green, 180), over(red, 120).point(lambda v: 255 - v), solid)
    fill(grow(led.filter(ImageFilter.MedianFilter(5)), 4), LED_COLOUR)
    # The tube is lavender: bluer than it is red or green. The median drops stray matches on edges.
    tube = both(over(ImageChops.subtract(blue, red), 8), over(ImageChops.subtract(blue, green), 15),
                over(red, 110), over(alpha, 200)).filter(ImageFilter.MedianFilter(9))
    # Thicken only into outline and background, so the tube never covers the body or the earpiece.
    free = ImageChops.lighter(solid.point(lambda v: 255 - v), image.convert("L").point(lambda v: 255 if v < 70 else 0))
    thick = both(grow(tube, TUBE_GROWTH), free)
    fill(thick, TUBE_COLOUR)
    fill(ImageChops.subtract(both(grow(ImageChops.lighter(tube, thick), OUTLINE), free), thick), OUTLINE_COLOUR)
    outlined = Image.new("RGBA", image.size, (0, 0, 0, 0))
    outlined.paste(Image.new("RGBA", image.size, OUTLINE_COLOUR), (0, 0), grow(over(image.getchannel("A"), 128), OUTLINE))
    outlined.alpha_composite(image)
    outlined = outlined.crop(outlined.getbbox())
    side = max(outlined.size)
    result = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    result.paste(outlined, ((side - outlined.width) // 2, (side - outlined.height) // 2))
    return result.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)


def tiers():
    column = WIDTH // len(TIERS)
    image = canvas(720)
    for i, (tier, colour) in enumerate(TIERS.items()):
        x = i * column + column / 2
        panel(image, (i * column + 10, 14, (i + 1) * column - 10, 706), colour)
        paste(image, fit(trim(capture(f"model_{tier}")), 240, 190), (x, 140))
        ear = fraction(capture(f"head_plain_male_right_{tier}_back_close", border=2), EAR_BOX)
        ear = fit(ear, 270, 270)
        mask = Image.new("L", ear.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, ear.width - 1, ear.height - 1), 14, fill=255)
        ear.putalpha(Image.composite(ear.getchannel("A"), mask, mask))
        paste(image, ear, (x, 400), shadow=False)
        paste(image, pixels(capture(f"icon_{tier}"), 3), (x, 600), shadow=False)
        text(image, (x, 674), NAMES[tier], 22, "SemiBold", anchor="mm")
    return image


def ears():
    image = canvas(680)
    sides = [("male", "right", "basic", STRINGS["rightEar"], 330), ("female", "left", "efficient", STRINGS["leftEar"], 930)]
    for sex, ear, tier, label, x in sides:
        head = fit(trim(capture(f"head_styled_{sex}_{ear}_{tier}_side", border=2)), 460, 400)
        paste(image, head, (x, 225), shadow=False)
        text(image, (x, 455), label, 26, "SemiBold", anchor="mm")
    # The Wear row and its submenu: the top of the menu, as tall as the submenu at its right edge.
    menu = trim(capture("menu_wear"))
    submenu_height = menu.getchannel("A").crop((menu.width - 4, 0, menu.width - 3, menu.height)).getbbox()[3]
    menu = pixels(menu.crop((0, 0, menu.width, submenu_height)), 2)
    paste(image, menu, (WIDTH / 2, 560))
    return image


def interface():
    basic, boosted, broken = (pixels(trim(capture(f"tooltip_{name}")), 2) for name in ("basic", "boosted", "broken"))
    gap = 40
    image = canvas(basic.height + broken.height + 3 * gap)
    row = basic.width + gap + boosted.width
    image.alpha_composite(basic, ((WIDTH - row) // 2, gap))
    image.alpha_composite(boosted, ((WIDTH - row) // 2 + basic.width + gap, gap))
    image.alpha_composite(broken, ((WIDTH - broken.width) // 2, 2 * gap + basic.height))
    return image


def item(base, name, label, centre, factor=2):
    icon = pixels(capture(f"icon_{name}"), factor)
    paste(base, icon, centre, shadow=False)
    text(base, (centre[0], centre[1] + icon.height / 2 + 10), label, 19, "Medium", MUTED, "ma")


def recipes():
    row = 210
    image = canvas(230 + row * len(RECIPES))
    panel(image, (20, 20, WIDTH - 20, 210))
    text(image, (50, 82), "Tools", 32, "Bold")
    text(image, (50, 128), "for every recipe, at a\ntable with enough light", 20, "Medium", MUTED)
    for i, (name, before) in enumerate(TOOLS):
        item(image, name, wrap(before + NAMES[name]), (420 + i * 150, 80))
    for r, (name, level, source, parts, result) in enumerate(RECIPES):
        top = 230 + r * row
        panel(image, (20, top, WIDTH - 20, top + row - 20), TIERS[result])
        text(image, (50, top + 62), name, 32, "Bold")
        text(image, (50, top + 108), f"{STRINGS['electrical']} {level}", 22, "Medium", MUTED)
        inputs = [(source, tier_label(source))] + [(part, wrap(NAMES[part]) + after) for part, after in parts]
        for j, (part, label) in enumerate(inputs):
            item(image, part, label, (300 + j * 128, top + 70))
        x = 300 + len(inputs) * 128 - 30
        arrow(image, (x, top + 70))
        item(image, result, tier_label(result), (x + 110, top + 70), factor=3)
    return image


def corpse():
    shot = Image.open(CAPTURES / "world_corpse.png").convert("RGBA").crop(CORPSE_BOX)
    return shot.resize((WIDTH, round(shot.height * WIDTH / shot.width)), Image.LANCZOS)


def main():
    for name, make in [("banner", banner), ("tiers", tiers), ("ears", ears), ("interface", interface),
                       ("recipes", recipes), ("corpse", corpse)]:
        save(make(), name)
    save_poster(poster())
    mod_icon = icon()
    mod_icon.save(MOD / "hearing_aid_icon.png", optimize=True)
    print(f"compose: {(MOD / 'hearing_aid_icon.png').relative_to(REPO)} {mod_icon.width}x{mod_icon.height}")


main()
