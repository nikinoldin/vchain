# SPDX-License-Identifier: GPL-3.0-or-later
"""Renders the DMG background: the BitmapBabe frame (assets/dmg/background.svg, via rsvg-convert) plus a drag arrow,
its caption and the first-launch steps in the website's type (bitmapbabe.com: Terminal Grotesque for the pixel half, Coconat for
the serif half, like the wordmark). Writes assets/dmg/background.png (660 × 508) and background@2x.png.
The fonts come from the website repo (WEBSITE=<path to its checkout>, required); icon positions in settings.py.
Run: WEBSITE=… uv run --with pillow python scripts/dmg/background.py
"""
import os
import subprocess

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
if not os.environ.get("WEBSITE"):
    raise SystemExit("set WEBSITE to the website repo checkout (its public/fonts has the DMG fonts)")
FONTS = os.path.join(os.path.expanduser(os.environ["WEBSITE"]), "public/fonts")
PIXEL = os.path.join(FONTS, "terminal-grotesque.ttf")
SERIF = os.path.join(FONTS, "coconat-400.otf")
INK = (0, 0, 0)


def width(d, parts, size, s):
    """The width of words() in points."""
    return sum(d.textlength(t, font=ImageFont.truetype(f, round(size * s * (1.11 if f == PIXEL else 1))))
               for t, f in parts) / s


def words(d, x, y, parts, size, s, anchor="m"):
    """Draws [(text, font path)] side by side, centred on x (anchor "m"), starting at x ("l") or ending at x ("r")."""
    # The pixel face runs small next to the serif: scaled so both have the same cap height, like the wordmark.
    fonts = [ImageFont.truetype(f, round(size * s * (1.11 if f == PIXEL else 1))) for _, f in parts]
    widths = [d.textlength(t, font=f) for (t, _), f in zip(parts, fonts)]
    total = sum(widths)
    cx = {"m": x * s - total / 2, "l": x * s, "r": x * s - total}[anchor]
    for (t, _), f, w in zip(parts, fonts, widths):
        d.text((cx, y * s), t, font=f, fill=INK, anchor="ls")
        cx += w


def pixel_arrow(d, x, y, s, block, left=False):
    """A stepped arrow in square blocks (the pixel font has no arrow), its middle at (x, y), pointing right (or left)."""
    cells = [(c, r) for c in range(0, 12) for r in (-1, 0)]                 # the shaft, two blocks thick
    for k in range(6):                                                        # the head, narrowing to the tip
        cells += [(12 + k, r) for r in range(-(5 - k), 5 - k)]
    width = 18
    for c, r in cells:
        c = width - 1 - c if left else c
        x0, y0 = (x - width * block / 2 + c * block) * s, (y + r * block) * s
        d.rectangle([x0, y0, x0 + block * s - 1, y0 + block * s - 1], fill=INK)


def render(s):
    out = os.path.join(ROOT, "assets/dmg", "background@2x.png" if s == 2 else "background.png")
    subprocess.run(["rsvg-convert", "-w", str(660 * s), "-h", str(508 * s),
                    os.path.join(ROOT, "assets/dmg/background.svg"), "-o", out], check=True)
    img = Image.open(out).convert("RGB")
    d = ImageDraw.Draw(img)
    # Between vChain (215, 245) and Applications (445, 245): the arrow and what to do.
    words(d, 330, 226, [("DRAG ", PIXEL), ("TO INSTALL", SERIF)], 12, s)
    pixel_arrow(d, 330, 246, s, 3)
    # Under the icons: getting past Gatekeeper the first time (vChain isn't notarized).
    words(d, 330, 362, [("macOS ", PIXEL), ("blocks vChain once:", SERIF)], 14, s)
    # The two steps left-aligned as a block, centred on the longer one.
    step1 = [("1 ", PIXEL), ("Open vChain and click Done", SERIF)]
    step2 = [("2 ", PIXEL), ("System Settings › Privacy & Security › Open Anyway", SERIF)]
    left = 330 - width(d, step2, 13, s) / 2
    words(d, left, 390, step1, 13, s, anchor="l")
    words(d, left, 412, step2, 13, s, anchor="l")
    img.save(out)


for scale in (1, 2):
    render(scale)
print("wrote assets/dmg/background.png and background@2x.png")
