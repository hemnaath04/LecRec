#!/usr/bin/env python3
"""Draws the DMG install window background.

Green palette taken from the reference design: a vivid leaf green field with
darker diagonal streaks, and hand-drawn guidance so the drag is obvious.
"""
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "build" / "dmg"
W, H = 720, 480

LEAF_LIGHT = (150, 206, 44)
LEAF_MID = (124, 181, 24)
LEAF_DEEP = (96, 148, 16)
PANEL = (74, 103, 33)
INK = (255, 255, 255)
INK_SOFT = (232, 243, 210)

FONTS = "/System/Library/Fonts/Supplemental/"


def hand(size):
    return ImageFont.truetype(FONTS + "Bradley Hand Bold.ttf", size)


def clean(size, bold=True):
    return ImageFont.truetype(FONTS + f"Arial{' Bold' if bold else ''}.ttf", size)


def field():
    """Vivid green with diagonal streaks, echoing the reference backdrop."""
    base = Image.new("RGB", (W, H), LEAF_MID)
    draw = ImageDraw.Draw(base)

    for y in range(H):
        t = y / H
        colour = tuple(round(LEAF_LIGHT[i] + (LEAF_DEEP[i] - LEAF_LIGHT[i]) * t) for i in range(3))
        draw.line([(0, y), (W, y)], fill=colour)

    streaks = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0))
    sd = ImageDraw.Draw(streaks)
    rng = random.Random(7)
    for _ in range(46):
        x = rng.randint(-H, W * 2)
        width = rng.randint(6, 30)
        shade = rng.choice([(255, 255, 255, 16), (60, 96, 10, 26), (170, 220, 70, 20)])
        sd.line([(x, 0), (x - H * 2, H * 2)], fill=shade, width=width)
    streaks = streaks.filter(ImageFilter.GaussianBlur(7)).resize((W, H), Image.LANCZOS)
    base = Image.alpha_composite(base.convert("RGBA"), streaks)

    # A soft vignette keeps attention on the middle.
    vignette = Image.new("L", (W, H), 0)
    ImageDraw.Draw(vignette).ellipse(
        [-W * 0.25, -H * 0.35, W * 1.25, H * 1.35], fill=255)
    vignette = vignette.filter(ImageFilter.GaussianBlur(110))
    dark = Image.new("RGBA", (W, H), (40, 62, 6, 120))
    base = Image.composite(base, Image.alpha_composite(base, dark), vignette)
    return base


def wobble(points, amount, seed):
    """Nudges a path so a drawn line never looks machine-straight."""
    rng = random.Random(seed)
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount))
            for x, y in points]


def curve(draw, start, end, lift, width, colour, seed):
    points = []
    for step in range(61):
        t = step / 60
        # Quadratic bezier through a lifted control point.
        cx = (start[0] + end[0]) / 2
        cy = (start[1] + end[1]) / 2 - lift
        x = (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * cx + t ** 2 * end[0]
        y = (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * cy + t ** 2 * end[1]
        points.append((x, y))
    points = wobble(points, 1.1, seed)
    # Two passes with slight offset reads as ink rather than a vector stroke.
    draw.line(points, fill=colour, width=width, joint="curve")
    draw.line([(x + 0.8, y + 0.8) for x, y in points],
              fill=colour[:3] + (110,), width=max(1, width - 2), joint="curve")
    return points


def arrowhead(draw, tip, previous, size, colour, seed):
    angle = math.atan2(tip[1] - previous[1], tip[0] - previous[0])
    for spread in (2.5, -2.5):
        end = (tip[0] - size * math.cos(angle + spread / 3.4),
               tip[1] - size * math.sin(angle + spread / 3.4))
        draw.line(wobble([tip, end], 0.9, seed), fill=colour, width=5, joint="curve")


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = field()
    draw = ImageDraw.Draw(canvas, "RGBA")

    # Title block, top left, echoing the reference's eyebrow plus bold title.
    draw.text((52, 40), "LECTURE RECORD", font=clean(12), fill=INK_SOFT + (210,))
    draw.text((50, 58), "LecRec", font=clean(42), fill=INK)
    draw.text((54, 112), "Record a lecture, get the note.",
              font=clean(14, bold=False), fill=INK_SOFT + (235,))

    # The two drop targets sit on soft plates so the icons read on green.
    for cx in (176, 544):
        plate = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        ImageDraw.Draw(plate).rounded_rectangle(
            [0, 0, 199, 199], radius=46, fill=PANEL + (92,))
        plate = plate.filter(ImageFilter.GaussianBlur(1.2))
        canvas.alpha_composite(plate, (cx - 100, 188))

    # Hand-drawn arrow between them.
    ink = INK + (240,)
    path = curve(draw, (268, 268), (450, 268), lift=54, width=6, colour=ink, seed=3)
    arrowhead(draw, path[-1], path[-6], 22, ink, seed=5)

    draw.text((312, 176), "drag me", font=hand(30), fill=ink)
    draw.text((330, 214), "over here", font=hand(24), fill=INK_SOFT + (225,))

    # No labels drawn here: Finder writes the icon names itself, directly under
    # each icon, and anything drawn there would collide with them.

    # The Gatekeeper note, which is the one thing that trips up a first launch.
    draw.text((50, 418), "first launch gets blocked, that is expected",
              font=hand(19), fill=INK_SOFT + (215,))
    draw.text((50, 442), "System Settings > Privacy & Security > Open Anyway",
              font=hand(16), fill=INK_SOFT + (180,))

    out = OUT / "background.png"
    canvas.convert("RGB").save(out)
    canvas.convert("RGB").resize((W * 2, H * 2), Image.LANCZOS).save(OUT / "background@2x.png")
    print(f"wrote {out}")
    return out


if __name__ == "__main__":
    build()
