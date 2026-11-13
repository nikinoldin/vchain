# SPDX-License-Identifier: GPL-3.0-or-later
"""Renders the README's top picture (assets/readme-hero.png, 2000 × 1240): the BitmapBabe frame turned around (white,
black ink): a small BITMAPBABE over the VCHAIN wordmark across the top, both in the website's type (Terminal
Grotesque for the pixel half, Coconat for the serif half, like the BitmapBabe wordmark), a fully rounded black window,
and the keychain at rest over all of it, most of the picture's height.
The keychain comes from the vector export (scripts/export-vector.sh → <dir>/light/keychain.pdf, via pdftocairo).
Run: WEBSITE=<website repo> uv run --with pillow python scripts/readme/hero.py [vector dir, default build/vector]
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if not os.environ.get("WEBSITE"):
    raise SystemExit("set WEBSITE to the website repo checkout (its public/fonts has the fonts)")
FONTS = os.path.join(os.path.expanduser(os.environ["WEBSITE"]), "public/fonts")
PIXEL = os.path.join(FONTS, "terminal-grotesque.ttf")
SERIF = os.path.join(FONTS, "coconat-400.otf")
VECTOR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build/vector")
INK, PAPER = (0, 0, 0, 255), (255, 255, 255, 255)

S = 2                       # pixels per point
W, H = 1000, 620            # points
LOGO_H = W / 6              # the wordmark's band, as in the BitmapBabe frame
CAP = 0.62 * LOGO_H         # the wordmark's cap height (the BitmapBabe logo's share of its band)
EDGE = 30                   # margin around the window
WIN = (EDGE, LOGO_H, W - EDGE, H - EDGE)


def font(face, cap):
    """The face at the size whose cap height is `cap` points."""
    probe = ImageFont.truetype(face, 1000)
    l, t, r, b = probe.getbbox("H", anchor="ls")
    return ImageFont.truetype(face, round(cap * S * 1000 / -t))


def words(d, base, pixel, serif, cap):
    """pixel + serif side by side, centred, baseline `base` (points), both `cap` points tall in capitals."""
    parts = [(pixel, font(PIXEL, cap)), (serif, font(SERIF, cap))]
    widths = [d.textlength(t, font=f) for t, f in parts]
    gap = 0.04 * cap * S
    x = (W * S - sum(widths) - gap) / 2
    base *= S
    for (t, f), w in zip(parts, widths):
        d.text((x, base), t, font=f, fill=INK, anchor="ls")
        x += w + gap


def keychain(height):
    """The keychain at rest (light), trimmed to what's drawn, `height` points tall."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["pdftocairo", "-png", "-transp", "-r", "144", "-singlefile",
                        os.path.join(VECTOR, "light/keychain.pdf"), os.path.join(tmp, "k")], check=True)
        img = Image.open(os.path.join(tmp, "k.png")).convert("RGBA")
    # The export has a faint full-width rule above the keychain (the gallery's): clear rows that are barely there
    # from edge to edge, keeping what's opaque on them (the ring crosses it).
    alpha = img.getchannel("A")
    faint = alpha.point(lambda a: 255 if 0 < a <= 24 else 0)
    for y in range(img.height):
        if faint.crop((0, y, img.width, y + 1)).histogram()[255] > img.width * 0.6:
            alpha.paste(alpha.crop((0, y, img.width, y + 1)).point(lambda a: 0 if a <= 24 else a), (0, y))
    img.putalpha(alpha)
    img = img.crop(img.getbbox())
    h = round(height * S)
    return img.resize((round(img.width * h / img.height), h), Image.LANCZOS)


img = Image.new("RGBA", (W * S, H * S), PAPER)
d = ImageDraw.Draw(img)
words(d, LOGO_H - 18, "V", "CHAIN", CAP)                # the wordmark, its baseline 18 pt above the window
words(d, LOGO_H - 18 - CAP - 14, "BITMAP", "BABE", 14)  # the maker, small, 14 pt above it
x0, y0, x1, y1 = (v * S for v in WIN)
d.rounded_rectangle((x0, y0, x1, y1), radius=(y1 - y0) / 2, fill=INK)

# The keychain over everything (the wordmark too), most of the picture's height, its charms at the bottom edge.
k = keychain(H * 0.87)
img.alpha_composite(k, (round((W * S - k.width) / 2), round((H - 6) * S - k.height)))

out = os.path.join(ROOT, "assets/readme-hero.png")
img.convert("RGB").save(out, optimize=True)
print("wrote assets/readme-hero.png")
