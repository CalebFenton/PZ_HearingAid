#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Lays out the README and Workshop images from the captures that extract.py saved. Rerun it after
editing a layout; recapture only when the game's look changes:

    art/promo/compose.py

Writes images/*.png. Every image is 1260 pixels wide, which the Workshop page shows at 630, so it
stays sharp on high-density screens. Interface captures and icons are scaled by whole numbers with
nearest-neighbour sampling, so their pixels stay crisp.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
CAPTURES = HERE / "captures"
OUT = HERE / "images"
FONT = HERE / "fonts" / "NotoSans.ttf"

WIDTH = 1260
BACKGROUND = (24, 26, 31)
PANEL = (36, 39, 46)
TEXT = (232, 234, 238)
MUTED = (160, 166, 176)
TIERS = {
    "broken": ("Broken Hearing Aid", (150, 150, 150)),
    "basic": ("Hearing Aid", (190, 184, 110)),
    "efficient": ("Efficient Hearing Aid", (110, 160, 200)),
    "boosted": ("Boosted Hearing Aid", (200, 90, 85)),
}
TOOLS = [
    ("screwdriver", "Screwdriver"),
    ("tweezers", "Tweezers"),
    ("reading_glasses", "Reading\nGlasses"),
    ("loupe", "or a\nLoupe"),
    ("magnifying_glass", "or a Magnifying\nGlass"),
]
RECIPES = [
    ("Repair", 2, "broken", [("earbuds", "Earbuds"), ("alcohol_wipes", "Alcohol\nWipes"), ("glue", "Glue")], "basic"),
    ("Optimize", 4, "basic", [("digital_watch", "Digital\nWatch"), ("electric_wire", "Electrical\nWire"), ("glue", "Glue")],
     "efficient"),
    ("Boost", 8, "efficient", [("amplifier", "Amplifier"), ("microphone", "Microphone"),
                               ("electric_wire", "Electrical\nWire ×2"), ("epoxy", "Epoxy"), ("scalpel", "Scalpel\n(kept)")],
     "boosted"),
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


def canvas(height):
    """A dark card with a faint vertical gradient."""
    image = Image.new("RGBA", (WIDTH, height), BACKGROUND + (255,))
    shade = Image.linear_gradient("L").resize((WIDTH, height)).point(lambda v: v * 0.35)
    image.paste(Image.new("RGBA", (WIDTH, height), (12, 13, 16, 255)), (0, 0), shade)
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
    OUT.mkdir(exist_ok=True)
    image.convert("RGB").save(OUT / f"{name}.png", optimize=True)
    print(f"compose: images/{name}.png {image.width}x{image.height}")


# Images ------------------------------------------------------------------------------------------


def banner():
    image = canvas(420)
    text(image, (70, 120), "Hearing Aid", 88, "Bold")
    text(image, (74, 238), "Battery-powered hearing aids\nfor Project Zomboid Build 42", 30, "Medium", MUTED)
    positions = [(770, 130), (910, 280), (1050, 130), (1160, 285)]
    for tier, centre in zip(TIERS, positions):
        paste(image, fit(trim(capture(f"model_{tier}")), 210, 210), centre)
    return image


def tiers():
    column = WIDTH // len(TIERS)
    image = canvas(720)
    for i, (tier, (name, colour)) in enumerate(TIERS.items()):
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
        text(image, (x, 674), name, 22, "SemiBold", anchor="mm")
    return image


def ears():
    image = canvas(680)
    sides = [("male", "right", "basic", "on Right Ear", 330), ("female", "left", "efficient", "on Left Ear", 930)]
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
    for i, (name, label) in enumerate(TOOLS):
        item(image, name, label, (420 + i * 150, 80))
    for r, (name, level, source, parts, result) in enumerate(RECIPES):
        top = 230 + r * row
        panel(image, (20, top, WIDTH - 20, top + row - 20), TIERS[result][1])
        text(image, (50, top + 62), name, 32, "Bold")
        text(image, (50, top + 108), f"Electrical {level}", 22, "Medium", MUTED)
        inputs = [(source, TIERS[source][0].replace(" Hearing Aid", "\nHearing Aid"))] + parts
        for j, (part, label) in enumerate(inputs):
            item(image, part, label, (300 + j * 128, top + 70))
        x = 300 + len(inputs) * 128 - 30
        arrow(image, (x, top + 70))
        item(image, result, TIERS[result][0].replace(" Hearing Aid", "\nHearing Aid"), (x + 110, top + 70), factor=3)
    return image


def corpse():
    shot = Image.open(CAPTURES / "world_corpse.png").convert("RGBA").crop(CORPSE_BOX)
    return shot.resize((WIDTH, round(shot.height * WIDTH / shot.width)), Image.LANCZOS)


def main():
    for name, make in [("banner", banner), ("tiers", tiers), ("ears", ears), ("interface", interface),
                       ("recipes", recipes), ("corpse", corpse)]:
        save(make(), name)


main()
