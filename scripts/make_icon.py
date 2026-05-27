#!/usr/bin/env python3
"""Generate caip app icon following Apple HIG.

Squircle background with subtle gradient. Centered AI sparkle (✦) glyph
in white, with a paste-clipboard motif behind it. Inset following
Apple's macOS Sonoma/Tahoe icon grid (~10% margin).

Output: build/AppIcon.iconset/ ready for iconutil.
"""
from __future__ import annotations
import os, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT_DIR = Path(__file__).resolve().parent.parent / "build" / "AppIcon.iconset"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Apple icon dimensions (lo, hi) for filename suffixes
SIZES = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]


def squircle_mask(size: int, radius_ratio: float = 0.225) -> Image.Image:
    """Apple's macOS icon shape — rounded rectangle (squircle approximation)."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    r = int(size * radius_ratio)
    d.rounded_rectangle((0, 0, size - 1, size - 1), radius=r, fill=255)
    return m


def vertical_gradient(size: int, top: tuple, bottom: tuple) -> Image.Image:
    g = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(top[0] * (1 - t) + bottom[0] * t)
        gn = int(top[1] * (1 - t) + bottom[1] * t)
        b = int(top[2] * (1 - t) + bottom[2] * t)
        g.putpixel((0, y), (r, gn, b))
    return g.resize((size, size))


def draw_sparkle(canvas: Image.Image, cx: float, cy: float, r: float,
                 fill=(255, 255, 255, 255)):
    """Draw a four-pointed star/sparkle (✦) centered on (cx, cy) with radius r."""
    d = ImageDraw.Draw(canvas, "RGBA")
    inner = r * 0.22
    pts = [
        (cx, cy - r),
        (cx + inner, cy - inner),
        (cx + r, cy),
        (cx + inner, cy + inner),
        (cx, cy + r),
        (cx - inner, cy + inner),
        (cx - r, cy),
        (cx - inner, cy - inner),
    ]
    d.polygon(pts, fill=fill)


def make_icon(size: int) -> Image.Image:
    # Background gradient — indigo → violet → pink (Apple-ish AI mood)
    top = (52, 89, 230)      # vivid blue
    mid = (124, 73, 235)     # purple
    bot = (216, 76, 198)     # magenta
    bg = Image.new("RGB", (size, size), top)

    # Two-stop gradient via diagonal interpolation
    grad = Image.new("RGB", (size, size))
    px = grad.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            if t < 0.5:
                u = t / 0.5
                r = int(top[0] * (1 - u) + mid[0] * u)
                g = int(top[1] * (1 - u) + mid[1] * u)
                b = int(top[2] * (1 - u) + mid[2] * u)
            else:
                u = (t - 0.5) / 0.5
                r = int(mid[0] * (1 - u) + bot[0] * u)
                g = int(mid[1] * (1 - u) + bot[1] * u)
                b = int(mid[2] * (1 - u) + bot[2] * u)
            px[x, y] = (r, g, b)

    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    base.paste(grad, (0, 0))

    # Soft inner highlight (top sheen)
    sheen = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sheen)
    sd.ellipse(
        (int(size * 0.05), int(-size * 0.55), int(size * 0.95), int(size * 0.55)),
        fill=(255, 255, 255, 60),
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=size * 0.05))
    base = Image.alpha_composite(base, sheen)

    # Clipboard motif (subtle background)
    clip_w = size * 0.42
    clip_h = size * 0.54
    cx = size / 2
    cy = size / 2 + size * 0.02
    clip_x0 = cx - clip_w / 2
    clip_y0 = cy - clip_h / 2 + size * 0.02
    clip_x1 = cx + clip_w / 2
    clip_y1 = cy + clip_h / 2 + size * 0.02
    cd = ImageDraw.Draw(base)
    cd.rounded_rectangle(
        (clip_x0, clip_y0, clip_x1, clip_y1),
        radius=size * 0.06,
        fill=(255, 255, 255, 38),
    )
    # Clip top (notch)
    notch_w = clip_w * 0.42
    notch_h = size * 0.07
    cd.rounded_rectangle(
        (cx - notch_w / 2, clip_y0 - notch_h * 0.4,
         cx + notch_w / 2, clip_y0 + notch_h * 0.6),
        radius=size * 0.022,
        fill=(255, 255, 255, 70),
    )

    # Main sparkle (✦) — large, centered, white with soft glow
    spark_r = size * 0.30
    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_sparkle(glow, cx, cy, spark_r * 1.10, fill=(255, 255, 255, 90))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=size * 0.025))
    base = Image.alpha_composite(base, glow)
    draw_sparkle(base, cx, cy, spark_r, fill=(255, 255, 255, 250))

    # Small accent sparkle bottom-right
    draw_sparkle(base, cx + size * 0.22, cy + size * 0.22,
                 size * 0.06, fill=(255, 255, 255, 220))

    # Mask to squircle
    mask = squircle_mask(size)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(base, (0, 0), mask)

    # Crisp inner edge stroke for definition
    edge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ed = ImageDraw.Draw(edge)
    r = int(size * 0.225)
    ed.rounded_rectangle(
        (1, 1, size - 2, size - 2),
        radius=r,
        outline=(255, 255, 255, 28),
        width=max(1, size // 256),
    )
    out = Image.alpha_composite(out, edge)
    return out


def main():
    print(f"Writing to {OUT_DIR}")
    # Render once at 1024, then downscale for crisp small sizes.
    master = make_icon(1024)
    master.save(OUT_DIR / "_master_1024.png")
    for size, name in SIZES:
        if size == 1024:
            img = master
        else:
            img = master.resize((size, size), Image.LANCZOS)
        img.save(OUT_DIR / name, optimize=True)
        print(f"  {name}  ({size}x{size})")
    print("done.")


if __name__ == "__main__":
    main()
