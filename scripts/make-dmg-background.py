#!/usr/bin/env python3
"""Draws the DMG install window background at Retina resolution.

Everything is rendered at 2x and the 1x version is downsampled from it, then the
two are combined into a multi-resolution TIFF. A plain 1x PNG gets upscaled by
Finder on a Retina display, which is what made the first version look soft.
"""
import math
import pathlib
import random
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "dmg"
W, H = 720, 480
S = 2                      # render scale

LEAF_LIGHT = (156, 212, 48)
LEAF_MID = (126, 184, 26)
LEAF_DEEP = (88, 138, 14)
PLATE = (62, 92, 22)
INK = (255, 255, 255)
INK_SOFT = (234, 246, 214)

HELV = "/System/Library/Fonts/HelveticaNeue.ttc"
HAND = "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf"


def helv(size, weight="Regular"):
    index = {"Regular": 0, "Bold": 1, "Medium": 10, "Light": 7}[weight]
    return ImageFont.truetype(HELV, size * S, index=index)


def hand(size):
    return ImageFont.truetype(HAND, size * S)


def px(value):
    return value * S


def field():
    base = Image.new("RGB", (px(W), px(H)), LEAF_MID)
    draw = ImageDraw.Draw(base)
    for y in range(px(H)):
        t = y / px(H)
        draw.line([(0, y), (px(W), y)], fill=tuple(
            round(LEAF_LIGHT[i] + (LEAF_DEEP[i] - LEAF_LIGHT[i]) * t) for i in range(3)))

    streaks = Image.new("RGBA", (px(W) * 2, px(H) * 2), (0, 0, 0, 0))
    sd = ImageDraw.Draw(streaks)
    rng = random.Random(11)
    for _ in range(54):
        x = rng.randint(-px(H), px(W) * 2)
        sd.line([(x, 0), (x - px(H) * 2, px(H) * 2)],
                fill=rng.choice([(255, 255, 255, 15), (52, 86, 8, 24), (176, 224, 78, 18)]),
                width=rng.randint(px(5), px(26)))
    streaks = streaks.filter(ImageFilter.GaussianBlur(px(6))).resize((px(W), px(H)), Image.LANCZOS)
    base = Image.alpha_composite(base.convert("RGBA"), streaks)

    vignette = Image.new("L", (px(W), px(H)), 0)
    ImageDraw.Draw(vignette).ellipse(
        [-px(W) * 0.22, -px(H) * 0.32, px(W) * 1.22, px(H) * 1.32], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(px(95)))
    dark = Image.new("RGBA", (px(W), px(H)), (34, 56, 4, 125))
    return Image.composite(base, Image.alpha_composite(base, dark), vignette)


def ink_stroke(draw, points, width, colour, seed):
    """Two offset passes with wobble, so a line reads as ink not as a vector."""
    rng = random.Random(seed)
    jittered = [(x + rng.uniform(-px(0.7), px(0.7)), y + rng.uniform(-px(0.7), px(0.7)))
                for x, y in points]
    draw.line(jittered, fill=colour, width=width, joint="curve")
    draw.line([(x + px(0.6), y + px(0.7)) for x, y in jittered],
              fill=colour[:3] + (90,), width=max(1, width - px(1)), joint="curve")
    return jittered


def bezier(start, end, lift, steps=90):
    cx, cy = (start[0] + end[0]) / 2, (start[1] + end[1]) / 2 - lift
    out = []
    for step in range(steps + 1):
        t = step / steps
        out.append(((1 - t) ** 2 * start[0] + 2 * (1 - t) * t * cx + t ** 2 * end[0],
                    (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * cy + t ** 2 * end[1]))
    return out


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = field()
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Title block. Tight tracking on the eyebrow, generous weight on the name.
    eyebrow = "L E C T U R E   R E C O R D"
    draw.text((px(52), px(44)), eyebrow, font=helv(10, "Medium"), fill=INK_SOFT + (205,))
    draw.text((px(50), px(62)), "LecRec", font=helv(46, "Bold"), fill=INK)
    draw.text((px(53), px(122)), "Record a lecture, get the note.",
              font=helv(15, "Light"), fill=INK_SOFT + (238,))

    # Plates behind the drop targets, with a soft drop shadow.
    for cx in (176, 544):
        shadow = Image.new("RGBA", (px(220), px(220)), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle(
            [px(10), px(14), px(210), px(214)], radius=px(48), fill=(20, 38, 2, 70))
        shadow = shadow.filter(ImageFilter.GaussianBlur(px(9)))
        canvas.alpha_composite(shadow, (px(cx - 110), px(184)))

        plate = Image.new("RGBA", (px(200), px(200)), (0, 0, 0, 0))
        pd = ImageDraw.Draw(plate)
        pd.rounded_rectangle([0, 0, px(200) - 1, px(200) - 1], radius=px(46),
                             fill=PLATE + (96,))
        pd.rounded_rectangle([0, 0, px(200) - 1, px(200) - 1], radius=px(46),
                             outline=(255, 255, 255, 40), width=px(1))
        canvas.alpha_composite(plate, (px(cx - 100), px(188)))

    # The arrow, drawn over the gap between the plates.
    white = INK + (245,)
    path = bezier((px(272), px(276)), (px(448), px(276)), lift=px(50))
    drawn = ink_stroke(draw, path, px(5), white, seed=4)
    tip, prev = drawn[-1], drawn[-8]
    angle = math.atan2(tip[1] - prev[1], tip[0] - prev[0])
    for spread in (0.72, -0.72):
        ink_stroke(draw, [tip, (tip[0] - px(20) * math.cos(angle + spread),
                                tip[1] - px(20) * math.sin(angle + spread))],
                   px(5), white, seed=9)

    draw.text((px(304), px(172)), "drag me", font=hand(31), fill=white)
    draw.text((px(326), px(212)), "over here", font=hand(23), fill=INK_SOFT + (222,))

    # Finder draws the icon names itself, so nothing is painted under the icons.

    # Gatekeeper note, the one thing that trips up a first launch.
    note = Image.new("RGBA", (px(W), px(H)), (0, 0, 0, 0))
    nd = ImageDraw.Draw(note)
    nd.rounded_rectangle([px(40), px(404), px(560), px(462)], radius=px(14),
                         fill=(24, 44, 4, 70))
    canvas.alpha_composite(note)
    draw.text((px(56), px(412)), "first launch gets blocked, that is expected",
              font=hand(18), fill=INK_SOFT + (232,))
    draw.text((px(56), px(436)), "System Settings  >  Privacy & Security  >  Open Anyway",
              font=helv(11, "Medium"), fill=INK_SOFT + (190,))

    flat = canvas.convert("RGB")
    at2x = OUT / "background@2x.png"
    at1x = OUT / "background.png"
    flat.save(at2x)
    flat.resize((W, H), Image.LANCZOS).save(at1x)

    # Finder reads a multi-resolution TIFF and picks the right one per display.
    tiff = OUT / "background.tiff"
    subprocess.run(["tiffutil", "-cathidpicheck", str(at1x), str(at2x), "-out", str(tiff)],
                   check=True, capture_output=True)
    print(f"wrote {tiff} ({tiff.stat().st_size // 1024} KB), plus 1x and 2x PNGs")


if __name__ == "__main__":
    build()
