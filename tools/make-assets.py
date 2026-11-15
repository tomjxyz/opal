#!/usr/bin/env python3
"""Generate Opal's UI assets from the brand images in art/.

    python3 tools/make-assets.py          (needs Pillow)

Writes assets/*.png: the opal-pattern signature button (normal/pressed, with
camera or search glyph), the logo, the rainbow strips for the ask-field border,
and white line icons for the bar and the overflow panel. Everything is drawn
4x supersampled and downscaled, so the output is anti-aliased.
"""
import math
import os
import sys

import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets")
ART = os.path.join(ROOT, "art")
SS = 4
WHITE = (255, 255, 255, 255)


def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)


# ---------------------------------------------------------------- glyphs
# Each glyph draws into a square of side z (supersampled). u = z/96.

def g_camera(d, u, w):
    d.rounded_rectangle([18*u, 34*u, 78*u, 74*u], radius=5*u, outline=WHITE, width=w)
    d.polygon([(34*u, 34*u), (40*u, 24*u), (56*u, 24*u), (62*u, 34*u)], fill=WHITE)
    d.ellipse([36*u, 42*u, 60*u, 66*u], outline=WHITE, width=w)


def g_search(d, u, w):
    d.ellipse([22*u, 20*u, 62*u, 60*u], outline=WHITE, width=w)
    d.line([(56*u, 54*u), (76*u, 74*u)], fill=WHITE, width=int(w * 1.4))


def g_back(d, u, w):
    d.line([(58*u, 20*u), (32*u, 48*u), (58*u, 76*u)], fill=WHITE, width=w, joint="curve")


def g_new(d, u, w):
    d.rectangle([22*u, 22*u, 74*u, 74*u], outline=WHITE, width=w)
    d.line([(48*u, 34*u), (48*u, 62*u)], fill=WHITE, width=w)
    d.line([(34*u, 48*u), (62*u, 48*u)], fill=WHITE, width=w)


def g_plus(d, u, w):
    d.line([(48*u, 20*u), (48*u, 76*u)], fill=WHITE, width=w)
    d.line([(20*u, 48*u), (76*u, 48*u)], fill=WHITE, width=w)


def g_chats(d, u, w):
    d.rectangle([16*u, 24*u, 62*u, 56*u], outline=WHITE, width=w)
    d.line([(28*u, 56*u), (24*u, 68*u), (38*u, 56*u)], fill=WHITE, width=w)
    d.line([(68*u, 36*u), (80*u, 36*u), (80*u, 66*u), (72*u, 66*u), (72*u, 76*u), (62*u, 66*u),
            (44*u, 66*u), (44*u, 60*u)], fill=WHITE, width=w)


def g_more(d, u, w):
    for y in (26, 48, 70):
        d.ellipse([42*u, (y-6)*u, 54*u, (y+6)*u], fill=WHITE)


def g_menu(d, u, w):
    for y in (30, 48, 66):
        d.line([(18*u, y*u), (78*u, y*u)], fill=WHITE, width=w)


def g_export(d, u, w):
    d.polygon([(26*u, 16*u), (60*u, 16*u), (72*u, 28*u), (72*u, 80*u), (26*u, 80*u)], outline=WHITE, width=w)
    d.line([(49*u, 34*u), (49*u, 64*u)], fill=WHITE, width=w)
    d.line([(38*u, 53*u), (49*u, 65*u), (60*u, 53*u)], fill=WHITE, width=w, joint="curve")


def g_copy(d, u, w):
    d.rectangle([34*u, 18*u, 76*u, 64*u], outline=WHITE, width=w)
    d.line([(22*u, 32*u), (22*u, 78*u), (62*u, 78*u)], fill=WHITE, width=w)


def g_settings(d, u, w):
    d.ellipse([36*u, 36*u, 60*u, 60*u], outline=WHITE, width=w)
    for k in range(8):
        a = k * math.pi / 4
        d.line([(48*u + 18*u*math.cos(a), 48*u + 18*u*math.sin(a)),
                (48*u + 28*u*math.cos(a), 48*u + 28*u*math.sin(a))], fill=WHITE, width=w)


def g_log(d, u, w):
    d.rectangle([22*u, 16*u, 74*u, 80*u], outline=WHITE, width=w)
    for y in (34, 48, 62):
        d.line([(32*u, y*u), (64*u, y*u)], fill=WHITE, width=max(1, w // 2 + 2))


def g_text(d, u, w):
    d.line([(24*u, 22*u), (72*u, 22*u)], fill=WHITE, width=w)
    d.line([(48*u, 22*u), (48*u, 76*u)], fill=WHITE, width=w)
    d.line([(36*u, 76*u), (60*u, 76*u)], fill=WHITE, width=w)


def g_flip(d, u, w):
    d.arc([18*u, 18*u, 78*u, 78*u], 200, 340, fill=WHITE, width=w)
    d.arc([18*u, 18*u, 78*u, 78*u], 20, 160, fill=WHITE, width=w)
    d.polygon([(72*u, 26*u), (80*u, 42*u), (64*u, 40*u)], fill=WHITE)
    d.polygon([(24*u, 70*u), (16*u, 54*u), (32*u, 56*u)], fill=WHITE)


def g_flash(d, u, w):
    d.polygon([(54*u, 12*u), (28*u, 52*u), (46*u, 52*u), (40*u, 84*u), (68*u, 40*u), (50*u, 40*u)],
              outline=WHITE, width=max(1, w // 2 + 2))


def g_gallery(d, u, w):
    d.rectangle([16*u, 22*u, 80*u, 74*u], outline=WHITE, width=w)
    d.line([(22*u, 68*u), (42*u, 46*u), (56*u, 60*u), (64*u, 52*u), (76*u, 66*u)], fill=WHITE, width=w)
    d.ellipse([60*u, 30*u, 70*u, 40*u], fill=WHITE)


def g_translate(d, u, w):
    # globe: outline, a meridian ellipse, the equator and two parallels
    d.ellipse([16*u, 16*u, 80*u, 80*u], outline=WHITE, width=w)
    d.ellipse([34*u, 16*u, 62*u, 80*u], outline=WHITE, width=w)
    d.line([(16*u, 48*u), (80*u, 48*u)], fill=WHITE, width=w)
    d.line([(22*u, 32*u), (74*u, 32*u)], fill=WHITE, width=max(1, w * 2 // 3))
    d.line([(22*u, 64*u), (74*u, 64*u)], fill=WHITE, width=max(1, w * 2 // 3))


def g_edit(d, u, w):
    # pencil at 45 degrees: body outline, tip, and a line under it
    d.polygon([(62*u, 18*u), (78*u, 34*u), (38*u, 74*u), (22*u, 58*u)], outline=WHITE, width=w)
    d.polygon([(22*u, 58*u), (38*u, 74*u), (16*u, 80*u)], fill=WHITE)
    d.line([(54*u, 26*u), (70*u, 42*u)], fill=WHITE, width=w)


def g_close(d, u, w):
    d.line([(24*u, 24*u), (72*u, 72*u)], fill=WHITE, width=w)
    d.line([(72*u, 24*u), (24*u, 72*u)], fill=WHITE, width=w)


ACCENT = (107, 82, 168, 255)    # Opal's purple (#6B52A8), lifted a little for icons
ACCENT_ICON = (150, 120, 235, 255)


def tint(src, dst, colour):
    """Recolour a white icon (keeps its alpha) - used for 'on' states (flash, translate)."""
    img = Image.open(os.path.join(OUT, src)).convert("RGBA")
    solid = Image.new("RGBA", img.size, colour)
    solid.putalpha(img.getchannel("A"))
    save(solid, dst)


def icon(name, glyph, size=96, weight=4.5, margin=0.04):
    """Draw, crop to the glyph's own bounds, then centre it in a square with a small
    margin, so every icon fills its box the same way regardless of its drawn size."""
    z = size * SS
    img = Image.new("RGBA", (z, z), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(img), z / 96.0, int(weight * z / 96.0))
    img = img.crop(img.getchannel("A").getbbox())
    side = int(max(img.size) * (1 + 2 * margin))
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(img, ((side - img.size[0]) // 2, (side - img.size[1]) // 2), img)
    save(sq.resize((size, size), Image.LANCZOS), name)


# ---------------------------------------------------------------- opal button

def opal_button(pattern, name, glyph, dim):
    n = 200
    z = n * SS
    img = pattern.resize((z, z), Image.LANCZOS)
    if dim:
        img = ImageEnhance.Brightness(img).enhance(0.6)
    img = img.convert("RGBA")
    layer = Image.new("RGBA", (z, z), (0, 0, 0, 0))
    # glyph in the centre, ~62% of the button box
    gz = int(z * 0.62)
    g = Image.new("RGBA", (gz, gz), (0, 0, 0, 0))
    glyph(ImageDraw.Draw(g), gz / 96.0, int(8 * gz / 96.0))
    layer.paste(g, ((z - gz) // 2, (z - gz) // 2), g)
    img = Image.alpha_composite(img, layer)
    mask = Image.new("L", (z, z), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, z - 1, z - 1], fill=255)
    img.putalpha(mask)
    ImageDraw.Draw(img).ellipse([0, 0, z - 1, z - 1], outline=(18, 18, 18, 255), width=3 * SS)
    save(img.resize((n, n), Image.LANCZOS), name)


# ---------------------------------------------------------------- animated opal button
# The button is a stack: a dark base, LAYERS colour layers (each = soft blobs of a different crop and
# rotation of the pattern, so colours reappear in new places), and the glyph on top. OpalButton.qml
# fades each colour layer in and out on its own period, so colour flows in and out across the stone.

LAYERS = 6


def circle_mask(z):
    m = Image.new("L", (z, z), 0)
    ImageDraw.Draw(m).ellipse([0, 0, z - 1, z - 1], fill=255)
    return m


def opal_layers(full):
    n, ss = 200, 2
    z = n * ss
    rnd = random.Random(7)            # fixed seed: the same assets on every run
    circ = circle_mask(z)
    w, h = full.size

    # dark base: the pattern, very dim, with a dark rim
    base = ImageEnhance.Brightness(full.resize((z, z), Image.LANCZOS)).enhance(0.16).convert("RGBA")
    base.putalpha(circ)
    ImageDraw.Draw(base).ellipse([0, 0, z - 1, z - 1], outline=(18, 18, 18, 255), width=3 * ss)
    save(base.resize((n, n), Image.LANCZOS), "opal-base.png")

    for i in range(LAYERS):
        crop = int(min(w, h) * rnd.uniform(0.38, 0.55))
        x0, y0 = rnd.randint(0, w - crop), rnd.randint(0, h - crop)
        src = full.crop((x0, y0, x0 + crop, y0 + crop)).rotate(rnd.choice([0, 90, 180, 270]))
        src = ImageEnhance.Color(src.resize((z, z), Image.LANCZOS)).enhance(1.15)
        # crush the pattern's dark grey to black so only colour (not a grey haze) fades in
        src = src.point(lambda v: 0 if v < 70 else int((v - 70) * 255 / 185)).convert("RGBA")
        mask = Image.new("L", (z, z), 0)
        d = ImageDraw.Draw(mask)
        for _ in range(3):
            r = rnd.uniform(0.16, 0.30) * z
            ang = rnd.uniform(0, 6.283)
            dist = rnd.uniform(0, 0.33) * z
            cx, cy = z / 2 + dist * math.cos(ang), z / 2 + dist * math.sin(ang)
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(z * 0.07))
        alpha = Image.composite(mask, Image.new("L", (z, z), 0), circ)
        src.putalpha(alpha)
        save(src.resize((n, n), Image.LANCZOS), "opal-layer-%d.png" % i)

    press = Image.new("RGBA", (z, z), (0, 0, 0, 0))     # dark disc for the pressed state
    ImageDraw.Draw(press).ellipse([0, 0, z - 1, z - 1], fill=(0, 0, 0, 255))
    save(press.resize((n, n), Image.LANCZOS), "opal-press.png")

    for name, glyph in (("camera", g_camera), ("search", g_search)):
        g = Image.new("RGBA", (z, z), (0, 0, 0, 0))
        gz = int(z * 0.62)
        gi = Image.new("RGBA", (gz, gz), (0, 0, 0, 0))
        glyph(ImageDraw.Draw(gi), gz / 96.0, int(8 * gz / 96.0))
        g.paste(gi, ((z - gz) // 2, (z - gz) // 2), gi)
        save(g.resize((n, n), Image.LANCZOS), "opal-glyph-%s.png" % name)


# ---------------------------------------------------------------- rainbow border strips
# The ask field border: a dark rim with soft colour glints. Drawn as four
# strips that the UI stretches along each edge (no nine-slice needed).

RIM = (58, 58, 58)


def strip(length, stops, horizontal, name, thickness=4):
    """stops: list of (pos 0..1, (r,g,b), strength 0..1) glints over the rim colour."""
    img = Image.new("RGBA", (length, 1) if horizontal else (1, length))
    px = img.load()
    for i in range(length):
        t = i / (length - 1)
        r, g, b = RIM
        for pos, col, width in stops:
            k = max(0.0, 1.0 - abs(t - pos) / width)
            k = k * k * (3 - 2 * k)
            r, g, b = (r + (col[0] - r) * k, g + (col[1] - g) * k, b + (col[2] - b) * k)
        c = (int(r), int(g), int(b), 255)
        if horizontal:
            px[i, 0] = c
        else:
            px[0, i] = c
    img = img.resize((length, thickness) if horizontal else (thickness, length), Image.NEAREST)
    save(img, name)


BLUE, ORANGE, GOLD, PURPLE, GREEN, RED = (70, 90, 230), (240, 130, 30), (235, 180, 40), (130, 80, 230), (40, 200, 110), (225, 45, 45)


def main():
    os.makedirs(OUT, exist_ok=True)
    pat = Image.open(os.path.join(ART, "pattern.jpeg")).convert("RGB")
    w, h = pat.size
    s = min(w, h)
    pat = pat.crop(((w - s) // 2, (h - s) // 2, (w + s) // 2, (h + s) // 2))
    opal_layers(pat)
    # The button shows big colour blobs: zoom into the middle of the pattern.
    zoom = int(s * 0.45)
    pat = pat.crop(((s - zoom) // 2, (s - zoom) // 2, (s + zoom) // 2, (s + zoom) // 2))

    logo = Image.open(os.path.join(ART, "opal-logo.png")).convert("RGBA")
    logo = logo.crop(logo.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    logo.thumbnail((96, 96), Image.LANCZOS)
    save(logo, "logo.png")
    # app icon: art/opal-logo.png trimmed to its visible pixels, square canvas, 110 px (Classic home screen)
    big = Image.open(os.path.join(ART, "opal-logo.png")).convert("RGBA")
    big = big.crop(big.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox())
    side = max(big.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(big, ((side - big.size[0]) // 2, (side - big.size[1]) // 2))
    canvas.resize((110, 110), Image.LANCZOS).save(os.path.join(ROOT, "icon.png"), optimize=True)

    strip(512, [(0.12, BLUE, 0.12), (0.5, ORANGE, 0.12), (0.88, GOLD, 0.1), (1.0, PURPLE, 0.06)], True, "rim-top.png")
    strip(512, [(0.0, GREEN, 0.05), (0.3, GREEN, 0.14), (0.75, RED, 0.12), (1.0, RIM, 0.01)], True, "rim-bottom.png")
    strip(128, [(1.0, GREEN, 0.5)], False, "rim-left.png")
    strip(128, [(0.0, PURPLE, 0.6)], False, "rim-right.png")

    for name, glyph in (("back", g_back), ("new", g_new), ("plus", g_plus), ("chats", g_chats),
                        ("more", g_more), ("menu", g_menu), ("export", g_export), ("copy", g_copy),
                        ("settings", g_settings), ("log", g_log), ("camera", g_camera),
                        ("search", g_search), ("flip", g_flip), ("flash", g_flash),
                        ("gallery", g_gallery), ("translate", g_translate), ("close", g_close), ("edit", g_edit)):
        icon("ic-%s.png" % name, glyph)
    tint("ic-flash.png", "ic-flash-on.png", ACCENT_ICON)
    tint("ic-translate.png", "ic-translate-on.png", ACCENT_ICON)
    tint("ic-close.png", "ic-close-dim.png", (110, 110, 110, 255))   # delete-chat cross
    # tap-to-focus square on the camera screen: white while focusing, purple when locked
    z = 96 * SS
    sq = Image.new("RGBA", (z, z), (0, 0, 0, 0))
    ImageDraw.Draw(sq).rectangle([3 * SS, 3 * SS, z - 3 * SS, z - 3 * SS], outline=WHITE, width=4 * SS)
    save(sq.resize((96, 96), Image.LANCZOS), "focus-square.png")
    tint("focus-square.png", "focus-square-locked.png", ACCENT_ICON)

    # purple focus ring drawn around the opal button when the trackpad is on it
    z = 220 * SS
    ring = Image.new("RGBA", (z, z), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([3 * SS, 3 * SS, z - 3 * SS, z - 3 * SS], outline=ACCENT_ICON, width=9 * SS)
    save(ring.resize((220, 220), Image.LANCZOS), "opal-focus-ring.png")
    print("assets written to", OUT)


if __name__ == "__main__":
    sys.exit(main())
