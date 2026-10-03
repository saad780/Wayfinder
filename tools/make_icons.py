"""Draw Wayfinder's own map icons (Media/*.tga).

Most categories use the game's own minimap-tracking icons at runtime; these cover the
categories the minimap has no icon for (boats, zeppelins, the tram, portals, generic
vendors, weapon masters, spirit healers) and act as fallbacks if a game texture is
missing. Everything is drawn at 4x and downsampled for clean edges.
"""

import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Wayfinder", "Media")
SIZE = 64
SS = 4
S = SIZE * SS

WHITE = (255, 255, 255, 255)
DARK = (20, 16, 10, 255)


def badge(color):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = 2 * SS
    d.ellipse([pad, pad, S - pad, S - pad], fill=DARK)
    inner = 6 * SS
    # simple vertical gradient for a little depth
    r, g, b = color
    for i in range(inner, S - inner):
        t = (i - inner) / (S - 2 * inner)
        shade = 1.15 - 0.35 * t
        c = (min(255, int(r * shade)), min(255, int(g * shade)), min(255, int(b * shade)), 255)
        # clip each row to the circle
        cy = S / 2
        rad = S / 2 - inner
        dy = abs(i + 0.5 - cy)
        if dy <= rad:
            half = math.sqrt(rad * rad - dy * dy)
            d.line([(cy - half, i), (cy + half, i)], fill=c)
    ring = 5 * SS
    d.ellipse([ring, ring, S - ring, S - ring], outline=(235, 210, 150, 255), width=SS)
    return img, d


def u(v):
    """Design coordinates are on a 64-unit grid."""
    return int(round(v * SS))


def poly(d, pts, fill=WHITE):
    d.polygon([(u(x), u(y)) for x, y in pts], fill=fill)


def save(img, name):
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(os.path.join(OUT, name + ".tga"))
    print("wrote", name)


def boat():
    img, d = badge((40, 110, 190))
    poly(d, [(15, 39), (49, 39), (44, 47), (20, 47)])          # hull
    d.rectangle([u(31), u(14), u(33), u(39)], fill=WHITE)      # mast
    poly(d, [(34, 15), (34, 36), (47, 36)])                    # main sail
    poly(d, [(30, 19), (30, 36), (19, 36)])                    # jib
    return img


def zeppelin():
    img, d = badge((165, 60, 40))
    d.ellipse([u(12), u(17), u(50), u(35)], fill=WHITE)        # envelope
    poly(d, [(46, 26), (54, 18), (54, 34)])                    # tail fins
    d.rectangle([u(25), u(37), u(37), u(43)], fill=WHITE)      # gondola
    d.line([(u(27), u(34)), (u(27), u(38))], fill=WHITE, width=SS * 2)
    d.line([(u(35), u(34)), (u(35), u(38))], fill=WHITE, width=SS * 2)
    return img


def tram():
    img, d = badge((105, 105, 115))
    d.rounded_rectangle([u(16), u(16), u(48), u(42)], radius=u(5), fill=WHITE)
    for x0 in (20, 30, 40):
        d.rectangle([u(x0) - u(1), u(20), u(x0) + u(5), u(28)], fill=(105, 105, 115, 255))
    d.ellipse([u(20), u(40), u(28), u(48)], fill=WHITE)
    d.ellipse([u(36), u(40), u(44), u(48)], fill=WHITE)
    d.rectangle([u(13), u(47), u(51), u(49)], fill=WHITE)      # rail
    return img


def portal():
    img, d = badge((110, 60, 170))
    for i, r in enumerate((18, 13, 8)):
        c = (255, 255, 255, 255) if i % 2 == 0 else (190, 150, 255, 255)
        d.ellipse([u(32 - r), u(32 - r), u(32 + r), u(32 + r)], outline=c, width=u(2.5))
    return img


def vendor():
    img, d = badge((170, 130, 30))
    d.ellipse([u(17), u(24), u(47), u(50)], fill=WHITE)        # sack body
    poly(d, [(26, 25), (38, 25), (42, 15), (22, 15)])          # neck
    d.rectangle([u(24), u(24), u(40), u(27)], fill=(170, 130, 30, 255))  # tie
    return img


def weaponmaster():
    img, d = badge((150, 40, 40))
    def sword(angle):
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        poly(ld, [(30.5, 14), (33.5, 14), (33.5, 37), (30.5, 37)])  # blade
        poly(ld, [(30.5, 14), (33.5, 14), (32, 10)])  # tip
        ld.rectangle([u(25), u(37), u(39), u(40)], fill=WHITE)              # guard
        ld.rectangle([u(30.5), u(40), u(33.5), u(48)], fill=WHITE)          # grip
        ld.ellipse([u(29.5), u(47), u(34.5), u(52)], fill=WHITE)            # pommel
        return layer.rotate(angle, resample=Image.BICUBIC, center=(S / 2, S / 2))
    img.alpha_composite(sword(42))
    img.alpha_composite(sword(-42))
    return img


def spirit():
    img, d = badge((60, 140, 200))
    d.ellipse([u(25), u(12), u(39), u(26)], outline=WHITE, width=u(3))   # ankh loop
    d.rectangle([u(30), u(25), u(34), u(52)], fill=WHITE)
    d.rectangle([u(20), u(30), u(44), u(34)], fill=WHITE)
    return img


def generic():
    img, d = badge((90, 90, 90))
    d.ellipse([u(25), u(25), u(39), u(39)], fill=WHITE)
    return img


def quest():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    outline, gold = DARK, (255, 210, 40, 255)
    for grow, colour in ((3, outline), (0, gold)):
        poly(d, [(27 - grow, 8 - grow), (37 + grow, 8 - grow), (35 + grow, 40 + grow), (29 - grow, 40 + grow)], colour)
        d.ellipse([u(27 - grow), u(44 - grow), u(37 + grow), u(54 + grow)], fill=colour)
    return img


def arrow():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    poly(d, [(32, 4), (54, 56), (32, 44), (10, 56)], DARK)
    poly(d, [(32, 10), (49, 51), (32, 41), (15, 51)], (255, 220, 60, 255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [
        ("Boat", boat), ("Zeppelin", zeppelin), ("Tram", tram), ("Portal", portal),
        ("Vendor", vendor), ("WeaponMaster", weaponmaster), ("Spirit", spirit),
        ("Generic", generic), ("Quest", quest), ("PlayerArrow", arrow),
    ]:
        save(fn(), name)


if __name__ == "__main__":
    main()
