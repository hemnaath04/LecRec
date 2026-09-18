#!/usr/bin/env python3
"""Draws the LecRec app icon and writes Resources/AppIcon.icns.

The mark is a waveform whose centre bar is a record dot: "record" and "audio"
in one shape, and it still reads at 32 points in the Finder.
"""
import math
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUILD = ROOT / "build" / "icon"
CANVAS = 1024
# macOS app icons sit inside the canvas with room for the system shadow.
TILE = 824
RADIUS = 185

INK_TOP = (44, 46, 54)
INK_BOTTOM = (22, 23, 28)
BAR = (236, 238, 243)
DOT = (255, 69, 58)


def rounded_mask(size, radius, supersample=4):
    big = Image.new("L", (size * supersample, size * supersample), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [0, 0, size * supersample - 1, size * supersample - 1],
        radius=radius * supersample, fill=255)
    return big.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        # Ease the ramp so the tile does not look like a flat two-tone band.
        t = t * t * (3 - 2 * t)
        gradient.putpixel((0, y), tuple(
            round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return gradient.resize((size, size), Image.BICUBIC)


def draw_mark(tile_size):
    """Waveform bars, centre bar replaced by the record dot."""
    scale = 4
    size = tile_size * scale
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    heights = [0.34, 0.62, 0.86, 0.62, 0.34]   # symmetric, peaks at the centre
    count = len(heights)
    bar_w = size * 0.082
    gap = size * 0.083
    span = count * bar_w + (count - 1) * gap
    left = (size - span) / 2
    mid_y = size / 2

    for index, height in enumerate(heights):
        x = left + index * (bar_w + gap)
        if index == count // 2:
            continue                            # the dot takes this slot
        h = size * height * 0.52
        draw.rounded_rectangle(
            [x, mid_y - h / 2, x + bar_w, mid_y + h / 2],
            radius=bar_w / 2, fill=BAR)

    dot_r = size * 0.098
    draw.ellipse([size / 2 - dot_r, mid_y - dot_r, size / 2 + dot_r, mid_y + dot_r],
                 fill=DOT)

    return layer.resize((tile_size, tile_size), Image.LANCZOS)


def build_icon():
    tile = vertical_gradient(TILE, INK_TOP, INK_BOTTOM).convert("RGBA")
    tile.putalpha(rounded_mask(TILE, RADIUS))

    mark = draw_mark(TILE)
    # A soft glow under the dot gives the tile depth without looking like a sticker.
    glow = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gr = TILE * 0.20
    gd.ellipse([TILE / 2 - gr, TILE / 2 - gr, TILE / 2 + gr, TILE / 2 + gr],
               fill=DOT + (70,))
    glow = glow.filter(ImageFilter.GaussianBlur(TILE * 0.06))
    tile = Image.alpha_composite(tile, Image.composite(
        glow, Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0)), glow.split()[3]))
    tile = Image.alpha_composite(tile, mark)

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    offset = (CANVAS - TILE) // 2
    canvas.paste(tile, (offset, offset), tile)
    return canvas


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    icon = build_icon()
    master = BUILD / "icon-1024.png"
    icon.save(master)

    iconset = BUILD / "AppIcon.iconset"
    iconset.mkdir(exist_ok=True)
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = size * scale
            suffix = "" if scale == 1 else "@2x"
            icon.resize((px, px), Image.LANCZOS).save(
                iconset / f"icon_{size}x{size}{suffix}.png")

    out = ROOT / "Resources" / "AppIcon.icns"
    result = subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        return 1
    print(f"wrote {out} ({out.stat().st_size // 1024} KB) and {master}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
