#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow==12.3.0"]
# ///
"""Lays out the README and Workshop images from the captures that --promo saved, and the mod's
poster, Workshop preview and mod-list icon, with the harness's lib/promo.py
(dev/harness/docs/workshop-page.md, "Laying out the images"). Rerun it after editing a layout;
recapture only when the game's look changes:

    art/promo/compose.py

Writes images/*.png, the Workshop gallery, gallery/NN-<name>.jpg in upload order, 42/poster.png,
which is also the Workshop preview, preview.png, and 42/hearing_aid_icon.png. The icon starts from
art/drawings/hearing_aid.xcf, the drawing Item_HearingAid.png came from, which ImageMagick's
`magick` flattens. Item names and the other text the game shows come from captures/promo.json,
which the game wrote in the last --promo run.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "dev" / "harness" / "lib"))
import promo  # noqa: E402
from promo import MUTED, PAGE, POSTER_SIZE, WIDTH  # noqa: E402

HERE = Path(__file__).resolve().parent
CAPTURES = promo.Captures(HERE / "captures")
OUT = HERE / "images"
GALLERY = HERE / "gallery"
MOD = REPO / "Contents" / "mods" / "HearingAid" / "42"
DRAWING = HERE.parent / "drawings" / "hearing_aid.xcf"
POSTER_FILES = [MOD / "poster.png", REPO / "preview.png"]
NAMES = CAPTURES.promo["names"]
STRINGS = CAPTURES.strings

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
# How far a head capture's panel outline reaches in from its edges.
HEAD_BORDER = 2


def head(name):
    """A head capture, less its panel's outline."""
    image = CAPTURES(name)
    return image.crop((HEAD_BORDER, HEAD_BORDER, image.width - HEAD_BORDER, image.height - HEAD_BORDER))


def fraction(image, box):
    return image.crop(tuple(round(f * size) for f, size in zip(box, (image.width, image.height) * 2)))


def last_word_down(name):
    """Breaks a name of more than one word before its last word."""
    return "\n".join(name.rsplit(" ", 1))


def tier_label(tier):
    """The tier's name, broken before the plain aid's name it ends in."""
    basic = NAMES["basic"]
    return NAMES[tier].replace(" " + basic, "\n" + basic)


def model(tier):
    return promo.trim(CAPTURES(f"model_{tier}"))


# Images ------------------------------------------------------------------------------------------


def banner():
    image = promo.canvas(420)
    promo.text(image, (70, 210), STRINGS["modName"], 88, "Bold", anchor="lm")
    positions = [(770, 130), (910, 280), (1050, 130), (1160, 285)]
    for tier, centre in zip(TIERS, positions):
        promo.paste(image, promo.fit(model(tier), 210, 210), centre)
    return image


def poster():
    """The banner's title and four models, stacked for a square. The mod list and the Workshop show
    it at about 196 pixels, so the title is large."""
    image = promo.canvas(POSTER_SIZE, POSTER_SIZE)
    promo.text(image, (POSTER_SIZE / 2, 74), STRINGS["modName"], 76, "Bold", anchor="mm")
    positions = [(140, 215), (372, 215), (140, 390), (372, 390)]
    for tier, centre in zip(TIERS, positions):
        promo.paste(image, promo.fit(model(tier), 200, 160), centre)
    return image


# The mod list draws the icon small with smooth scaling, where the drawing's thin outline and tube
# blur away. These are in pixels of the drawing, which is about 20 times the icon.
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
    return result.resize((promo.MOD_ICON, promo.MOD_ICON), Image.LANCZOS)


def tiers():
    column = WIDTH // len(TIERS)
    image = promo.canvas(720)
    for i, (tier, colour) in enumerate(TIERS.items()):
        x = i * column + column / 2
        promo.panel(image, (i * column + 10, 14, (i + 1) * column - 10, 706), colour)
        promo.paste(image, promo.fit(model(tier), 240, 190), (x, 140))
        promo.paste(image, close_ear(tier, 270), (x, 400), shadow=False)
        promo.paste(image, promo.pixels(CAPTURES(f"icon_{tier}"), 3), (x, 600), shadow=False)
        promo.text(image, (x, 674), NAMES[tier], 22, "SemiBold", anchor="mm")
    return image


def ears():
    image = promo.canvas(680)
    sides = [("male", "right", "basic", STRINGS["rightEar"], 330), ("female", "left", "efficient", STRINGS["leftEar"], 930)]
    for sex, ear, tier, label, x in sides:
        shot = promo.fit(promo.trim(head(f"head_styled_{sex}_{ear}_{tier}_side")), 460, 400)
        promo.paste(image, shot, (x, 225), shadow=False)
        promo.text(image, (x, 455), label, 26, "SemiBold", anchor="mm")
    promo.paste(image, promo.pixels(wear_menu(), 2), (WIDTH / 2, 560))
    return image


def close_ear(tier, size):
    """The aid on the plain head's right ear, seen close from behind, with rounded corners."""
    ear = fraction(head(f"head_plain_male_right_{tier}_back_close"), EAR_BOX)
    return promo.rounded(promo.fit(ear, size, size), 14)


def wear_menu():
    """The Wear row and its submenu: the top of the menu, as tall as the submenu at its right edge."""
    menu = promo.trim(CAPTURES("menu_wear"))
    submenu_height = menu.getchannel("A").crop((menu.width - 4, 0, menu.width - 3, menu.height)).getbbox()[3]
    return menu.crop((0, 0, menu.width, submenu_height))


def tooltip_captures(factor):
    return [promo.pixels(promo.trim(CAPTURES(f"tooltip_{name}")), factor) for name in ("basic", "boosted", "broken")]


def tooltips(base, captures, top, gap):
    """The working tooltips side by side, over the broken one, centred across base."""
    basic, boosted, broken = captures
    left = (base.width - (basic.width + gap + boosted.width)) // 2
    base.alpha_composite(basic, (left, top))
    base.alpha_composite(boosted, (left + basic.width + gap, top))
    base.alpha_composite(broken, ((base.width - broken.width) // 2, top + basic.height + gap))


def interface():
    captures = tooltip_captures(2)
    gap = 40
    image = promo.canvas(captures[0].height + captures[2].height + 3 * gap)
    tooltips(image, captures, gap, gap)
    return image


def item(base, name, label, centre, factor=2, size=19):
    shown = promo.pixels(CAPTURES(f"icon_{name}"), factor)
    promo.paste(base, shown, centre, shadow=False)
    promo.text(base, (centre[0], centre[1] + shown.height / 2 + 10), label, size, "Medium", MUTED, "ma")


def recipe_inputs(source, parts):
    return [(source, tier_label(source))] + [(part, last_word_down(NAMES[part]) + after) for part, after in parts]


def recipes():
    row = 210
    image = promo.canvas(230 + row * len(RECIPES))
    promo.panel(image, (20, 20, WIDTH - 20, 210))
    promo.text(image, (50, 82), "Tools", 32, "Bold")
    promo.text(image, (50, 128), "for every recipe, at a\ntable with enough light", 20, "Medium", MUTED)
    for i, (name, before) in enumerate(TOOLS):
        item(image, name, last_word_down(before + NAMES[name]), (420 + i * 150, 80))
    for r, (name, level, source, parts, result) in enumerate(RECIPES):
        top = 230 + r * row
        promo.panel(image, (20, top, WIDTH - 20, top + row - 20), TIERS[result])
        promo.text(image, (50, top + 62), name, 32, "Bold")
        promo.text(image, (50, top + 108), f"{STRINGS['electrical']} {level}", 22, "Medium", MUTED)
        inputs = recipe_inputs(source, parts)
        for j, (part, label) in enumerate(inputs):
            item(image, part, label, (300 + j * 128, top + 70))
        x = 300 + len(inputs) * 128 - 30
        promo.arrow(image, (x, top + 70))
        item(image, result, tier_label(result), (x + 110, top + 70), factor=3)
    return image


def corpse():
    return promo.full_width(CAPTURES("world_corpse").crop(CORPSE_BOX))


# Gallery -----------------------------------------------------------------------------------------
# Each page is drawn below promo.page's caption band, PAGE in size.


def hero_page():
    image = promo.canvas(PAGE[1], PAGE[0])
    positions = [(330, 390), (750, 550), (1170, 390), (1590, 550)]
    for tier, centre in zip(TIERS, positions):
        promo.paste(image, promo.fit(model(tier), 500, 460), centre)
    return image


def tiers_page():
    image = promo.canvas(PAGE[1], PAGE[0])
    column = PAGE[0] // len(TIERS)
    for i, (tier, colour) in enumerate(TIERS.items()):
        x = i * column + column / 2
        promo.panel(image, (i * column + 14, 0, (i + 1) * column - 14, 900), colour)
        promo.paste(image, promo.fit(model(tier), 300, 210), (x, 125))
        promo.paste(image, close_ear(tier, 370), (x, 430), shadow=False)
        promo.paste(image, promo.pixels(CAPTURES(f"icon_{tier}"), 4), (x, 705), shadow=False)
        promo.text(image, (x, 820), NAMES[tier], 30, "SemiBold", anchor="mm")
    return image


def ears_page():
    image = promo.canvas(PAGE[1], PAGE[0])
    sides = [("male", "right", "basic", STRINGS["rightEar"], 470), ("female", "left", "efficient", STRINGS["leftEar"], 1450)]
    for sex, ear, tier, label, x in sides:
        shot = promo.fit(promo.trim(head(f"head_styled_{sex}_{ear}_{tier}_side")), 560, 540)
        promo.paste(image, shot, (x, 285), shadow=False)
        promo.text(image, (x, 610), label, 36, "SemiBold", anchor="mm")
    promo.paste(image, promo.pixels(wear_menu(), 3), (PAGE[0] / 2, 780))
    return image


def tooltips_page():
    image = promo.canvas(PAGE[1], PAGE[0])
    captures = tooltip_captures(3)
    gap = 60
    height = captures[0].height + gap + captures[2].height
    tooltips(image, captures, (900 - height) // 2, gap)
    return image


def corpse_page():
    # 1.5 times is as far as the world's pixel art scales before it turns soft. The crop is a little
    # taller than CORPSE_BOX, to keep the loot window's title bar.
    shot = promo.scaled(CAPTURES("world_corpse").crop((110, 70, 1010, 576)), 1.5)
    image = promo.canvas(PAGE[1], PAGE[0])
    promo.paste(image, promo.rounded(shot, 18), (PAGE[0] / 2, 450))
    return image


def recipes_page():
    """The recipe sheet with the tools in a column at the left, so the icons fit at three times."""
    image = promo.canvas(PAGE[1], PAGE[0])
    promo.panel(image, (40, 0, 500, 900))
    promo.text(image, (80, 70), "Tools", 44, "Bold")
    promo.text(image, (80, 130), "for every recipe, at a\ntable with enough light", 26, "Medium", MUTED)
    for i, (name, before) in enumerate(TOOLS):
        item(image, name, last_word_down(before + NAMES[name]), (160 + i % 2 * 220, 330 + i // 2 * 200), 3, 24)
    row = (900 + 20) // len(RECIPES)
    for r, (name, level, source, parts, result) in enumerate(RECIPES):
        top = r * row
        promo.panel(image, (530, top, PAGE[0] - 40, top + row - 20), TIERS[result])
        promo.text(image, (570, top + 95), name, 44, "Bold")
        promo.text(image, (570, top + 160), f"{STRINGS['electrical']} {level}", 28, "Medium", MUTED)
        inputs = recipe_inputs(source, parts)
        for j, (part, label) in enumerate(inputs):
            item(image, part, label, (850 + j * 140, top + 115), 3, 22)
        x = 850 + len(inputs) * 140 - 30
        promo.arrow(image, (x, top + 115))
        item(image, result, tier_label(result), (x + 120, top + 115), 4, 22)
    return image


def gallery():
    return [
        ("hero", promo.page(STRINGS["modName"], hero_page())),
        ("tiers", promo.page("From broken to boosted.", tiers_page())),
        ("ears", promo.page("Wear it on either ear.", ears_page())),
        ("tooltips", promo.page("Check the battery before you trust it.", tooltips_page())),
        ("corpse", promo.page("Most are still on their late owners.", corpse_page())),
        ("recipes", promo.page("Repair it, then upgrade it twice.", recipes_page())),
    ]


def main():
    for name, make in [("banner", banner), ("tiers", tiers), ("ears", ears), ("interface", interface),
                       ("recipes", recipes), ("corpse", corpse)]:
        promo.save(make(), OUT / f"{name}.png")
    promo.save_poster(poster(), POSTER_FILES)
    promo.save_gallery(gallery(), GALLERY)
    promo.save_mod_icon(icon(), MOD / "hearing_aid_icon.png")


main()
