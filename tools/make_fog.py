"""Draw the soft fog-of-war edge pieces (Media/Fog/Fog0..Fog15.tga).

The detail view lays a fog overlay on a grid offset by half a cell, so each piece's
four corners sit on four exploration cells. Which corners are explored gives 16 cases
(bit 1 = top-left, 2 = top-right, 4 = bottom-left, 8 = bottom-right); each case's
texture holds fog in its alpha channel: 1 - smoothstep of the bilinear blend of the
corners. Neighbouring pieces therefore join seamlessly, straight edges fade over one
cell and corners come out rounded.

Blend.tga provides five filtered exploration levels at each corner for the wider
continuous-map fade. Its 625 patches have replicated gutters to prevent seams.

    python tools/make_fog.py [--preview out.png]
"""

import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Wayfinder", "Media", "Fog")
SIZE = 64
BLEND_LEVELS = 4
BLEND_SIZE = 1024
BLEND_PATCH = 32
BLEND_COLUMNS = 32


def smoothstep(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def fog_alpha(case, u, v):
    tl, tr = case & 1, (case >> 1) & 1
    bl, br = (case >> 2) & 1, (case >> 3) & 1
    explored = (tl * (1 - u) * (1 - v) + tr * u * (1 - v) + bl * (1 - u) * v + br * u * v)
    return 1.0 - smoothstep(explored)


def make_case(case):
    img = Image.new("RGBA", (SIZE, SIZE))
    px = img.load()
    for y in range(SIZE):
        v = y / (SIZE - 1)  # edge texels sit exactly on the corners, so pieces join seamlessly
        for x in range(SIZE):
            u = x / (SIZE - 1)
            px[x, y] = (255, 255, 255, int(round(fog_alpha(case, u, v) * 255)))
    return img


def blend_alpha(code, u, v):
    corners = []
    for _ in range(4):
        corners.append((code % 5) / BLEND_LEVELS)
        code //= 5
    tl, tr, bl, br = corners
    explored = tl * (1-u)*(1-v) + tr*u*(1-v) + bl*(1-u)*v + br*u*v
    return 1.0 - smoothstep(explored)


def make_blend():
    """Five coverage levels per corner, with replicated one-texel gutters."""
    img = Image.new("RGBA", (BLEND_SIZE, BLEND_SIZE), (255, 255, 255, 0))
    px = img.load()
    for code in range(5**4):
        ox, oy = code % BLEND_COLUMNS * BLEND_PATCH, code // BLEND_COLUMNS * BLEND_PATCH
        for y in range(BLEND_PATCH):
            v = min(max((y-1)/(BLEND_PATCH-3), 0), 1)
            for x in range(BLEND_PATCH):
                u = min(max((x-1)/(BLEND_PATCH-3), 0), 1)
                px[ox+x, oy+y] = (255, 255, 255, round(blend_alpha(code,u,v)*255))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    cases = [make_case(case) for case in range(16)]
    for case, img in enumerate(cases):
        img.save(os.path.join(OUT, f"Fog{case}.tga"))
    make_blend().save(os.path.join(OUT, "Blend.tga"))
    print(f"wrote 16 fog pieces and the blend atlas to {os.path.normpath(OUT)}")

    if "--preview" in sys.argv:
        target = sys.argv[sys.argv.index("--preview") + 1]
        sheet = Image.new("RGBA", (4 * (SIZE + 8), 4 * (SIZE + 8)), (200, 170, 110, 255))
        for case, img in enumerate(cases):
            fog = Image.new("RGBA", img.size, (26, 28, 36, 255))
            fog.putalpha(img.getchannel("A"))
            sheet.alpha_composite(fog, ((case % 4) * (SIZE + 8) + 4, (case // 4) * (SIZE + 8) + 4))
        sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST).save(target)
        print("preview:", target)


if __name__ == "__main__":
    main()
