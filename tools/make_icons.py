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


def locate():
    """Crosshair for the 'show my location' map button."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for colour, grow in ((DARK, 2.5), ((255, 214, 90, 255), 0)):
        w = u(3 + grow)
        d.ellipse([u(16), u(16), u(48), u(48)], outline=colour, width=w)
        for x0, y0, x1, y1 in ((32, 4, 32, 20), (32, 44, 32, 60), (4, 32, 20, 32), (44, 32, 60, 32)):
            d.line([(u(x0), u(y0)), (u(x1), u(y1))], fill=colour, width=w)
        r = 5 + grow
        d.ellipse([u(32 - r), u(32 - r), u(32 + r), u(32 + r)], fill=colour)
    return img


def waypoint_pin():
    """Teardrop map pin marking the waypoint."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for colour, grow in ((DARK, 3), ((255, 200, 40, 255), 0)):
        d.ellipse([u(16 - grow), u(4 - grow), u(48 + grow), u(36 + grow)], fill=colour)
        poly(d, [(18 - grow, 26), (46 + grow, 26), (32, 60 + grow)], colour)
    d.ellipse([u(25), u(13), u(39), u(27)], fill=(120, 60, 10, 255))
    return img


# The floating waypoint arrow is built from four 128x128 layers, tinted in game.
BIG = 128


def soft_disc(radius, feather, colour):
    """A filled disc whose alpha falls off over `feather` pixels (at 4x)."""
    size = BIG * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            dist = math.hypot(x + 0.5 - c, y + 0.5 - c)
            t = min(max((radius - dist) / feather, 0.0), 1.0)
            if t > 0:
                px[x, y] = colour[:3] + (int(colour[3] * t * t * (3 - 2 * t)),)
    return img


def save_big(img, name):
    img = img.resize((BIG, BIG), Image.LANCZOS)
    path = os.path.join(OUT, "Arrow")
    os.makedirs(path, exist_ok=True)
    img.save(os.path.join(path, name + ".tga"))
    print("wrote Arrow/" + name)


def arrow_glow():
    return soft_disc(64 * SS, 34 * SS, (255, 255, 255, 255))


def arrow_disc():
    # deep slate disc with a soft rim shadow and a slightly lighter top
    size = BIG * SS
    img = soft_disc(52 * SS, 6 * SS, (10, 12, 18, 235))
    shade = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for i in range(40):
        a = int(26 * (1 - i / 40))
        r = (46 - i * 0.6) * SS
        sd.ellipse([size / 2 - r, size / 2 - r - 10 * SS, size / 2 + r, size / 2 + r - 10 * SS], fill=(70, 90, 130, a))
    img.alpha_composite(shade)
    mask = soft_disc(48 * SS, 2 * SS, (255, 255, 255, 255)).getchannel("A")
    inner = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner.paste(img, (0, 0), mask)
    base = soft_disc(52 * SS, 6 * SS, (10, 12, 18, 235))
    base.alpha_composite(inner)
    return base


def arrow_ring():
    size = BIG * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, r = size / 2, 50 * SS
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 255, 255, 255), width=3 * SS)
    r2 = 44 * SS
    d.ellipse([c - r2, c - r2, c + r2, c + r2], outline=(255, 255, 255, 90), width=1 * SS)
    return img


def arrow_head():
    """Notched navigation arrowhead, lit from the left."""
    size = BIG * SS
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    def p(x, y):
        return (x * SS * 2, y * SS * 2)  # design grid is 64 wide
    # corners stay inside the inner ring at any rotation
    tip, left, notch, right = p(32, 15), p(19.5, 45), p(32, 38.5), p(44.5, 45)
    shadow = [(x + 2 * SS, y + 3 * SS) for x, y in (tip, left, notch, right)]
    d.polygon(shadow, fill=(0, 0, 0, 110))
    d.polygon([tip, left, notch], fill=(255, 255, 255, 255))
    d.polygon([tip, notch, right], fill=(196, 196, 196, 255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in [
        ("Boat", boat), ("Zeppelin", zeppelin), ("Tram", tram), ("Portal", portal),
        ("Vendor", vendor), ("WeaponMaster", weaponmaster), ("Spirit", spirit),
        ("Generic", generic), ("Quest", quest), ("PlayerArrow", arrow),
        ("Locate", locate), ("Waypoint", waypoint_pin),
    ]:
        save(fn(), name)
    for name, fn in [("Glow", arrow_glow), ("Disc", arrow_disc), ("Ring", arrow_ring), ("Head", arrow_head)]:
        save_big(fn(), name)


if __name__ == "__main__":
    main()
