"""Render Wayfinder's standalone arrow from geometry, without source images.

python tools/make_arrow.py
python tools/make_arrow.py --preview <directory>

The world-space needle yaws counterclockwise from forward. A fixed orthographic
camera and light project its raised facets and shadow into 128 directional frames.
"""
import argparse
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "Wayfinder/Media/Arrow"
FRAME = 128
COUNT = 128
COLUMNS = 16
ROWS = 8
SS = 4
PITCH = math.radians(42)
ORIGIN = (64, 69)
LIGHT = (-.45, -.6, .85)


def yaw(vertex, angle):
    """Model coordinates are right, forward, and height."""
    right, forward, height = vertex
    return (right * math.cos(angle) - forward * math.sin(angle),
            -right * math.sin(angle) - forward * math.cos(angle), height)


def project(vertex):
    x, y, z = vertex
    return (ORIGIN[0] + x, ORIGIN[1] + y * math.sin(PITCH) - z * math.cos(PITCH))


def polygon(draw, vertices, fill):
    draw.polygon([(round(x * SS), round(y * SS)) for x, y in vertices], fill=fill)


def shade(vertices, base):
    a, b, c = vertices[:3]
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    normal = (u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0])
    length = math.sqrt(sum(n * n for n in normal))
    light_length = math.sqrt(sum(n * n for n in LIGHT))
    diffuse = max(0, sum(normal[i] * LIGHT[i] for i in range(3)) / (length * light_length))
    brightness = .48 + .52 * diffuse
    return tuple(round(channel * brightness) for channel in base) + (255,)


def needle(angle):
    # Long directional tip, short counterweight, raised ridge and bevel walls.
    rim = [(0, 43, 4), (16, 0, 4), (0, -23, 4), (-16, 0, 4)]
    ridge = (0, 2, 12)
    rim = [yaw(p, angle) for p in rim]
    ridge = yaw(ridge, angle)
    image = Image.new("RGBA", (FRAME * SS, FRAME * SS))
    shadow = Image.new("RGBA", image.size)
    shadow_draw = ImageDraw.Draw(shadow)
    # A subtle cast shadow reinforces depth without a solid backing.
    shadow_points = []
    for x, y, z in rim:
        shadow_points.append(project((x - LIGHT[0] / LIGHT[2] * z,
                                      y - LIGHT[1] / LIGHT[2] * z, 0)))
    polygon(shadow_draw, shadow_points, (0, 0, 0, 155))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(1.3 * SS)))
    draw = ImageDraw.Draw(image)
    faces = []
    for i in range(4):
        a, b = rim[i], rim[(i + 1) % 4]
        floor_a, floor_b = (a[0], a[1], 0), (b[0], b[1], 0)
        # Outward-facing walls and upward-facing top facets.
        wall = [a, floor_a, floor_b, b]
        top = [a, b, ridge]
        base = (245, 250, 255) if i in (0, 3) else (122, 142, 157)
        faces.append((wall, (92, 111, 126)))
        faces.append((top, base))
    # Farther faces first; the same fixed camera is used for every heading.
    faces.sort(key=lambda face: sum(v[1] * math.cos(PITCH) + v[2] * math.sin(PITCH)
                                    for v in face[0]) / len(face[0]))
    for vertices, base in faces:
        polygon(draw, [project(v) for v in vertices], shade(vertices, base))
    # A narrow highlight marks the raised forward ridge, not a flat outline.
    a, b = project(ridge), project(rim[0])
    draw.line([(round(a[0] * SS), round(a[1] * SS)), (round(b[0] * SS), round(b[1] * SS))],
              fill=(248, 253, 255, 205), width=SS)
    return image.resize((FRAME, FRAME), Image.Resampling.LANCZOS)


def generate(output=OUT):
    output.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (FRAME * COLUMNS, FRAME * ROWS))
    for index in range(COUNT):
        atlas.paste(needle(index * math.tau / COUNT), ((index % COLUMNS) * FRAME, (index // COLUMNS) * FRAME))
    # Match the uncompressed 32-bit TGA format already used by the addon.
    atlas.save(output / "NeedleAtlas.tga")
    print(f"wrote {output.name}/NeedleAtlas.tga ({atlas.width}x{atlas.height}, {COUNT} headings)")


def tinted_needle(angle, near=False):
    head = needle(angle)
    tint = (.45, .92, .45) if near else (.35, .84, 1)
    channels = head.split()
    return Image.merge("RGBA", tuple(channels[j].point(lambda v, t=tint[j]: round(v * t))
                                     for j in range(3)) + (channels[3],))


def preview_hud(angle, near=False):
    # Match the runtime's 110x94 widget, 80x62 hub, and 100px texture.
    hud = Image.new("RGBA", (110, 94))
    hud.alpha_composite(tinted_needle(angle, near).resize((100, 100), Image.Resampling.LANCZOS), (5, -19))
    draw = ImageDraw.Draw(hud)
    font_path = Path("C:/Windows/Fonts/segoeui.ttf")
    large = ImageFont.truetype(str(font_path), 14) if font_path.exists() else ImageFont.load_default()
    small = ImageFont.truetype(str(font_path), 10) if font_path.exists() else ImageFont.load_default()
    for text, y, font, color in (("30 yd" if near else "100 yd", 63, large,
                                   (114, 234, 114) if near else (90, 215, 255)),
                                  ("Waypoint", 81, small, (235, 235, 235))):
        draw.text((56, y + 1), text, font=font, anchor="mt", fill=(0, 0, 0, 255))
        draw.text((55, y), text, font=font, anchor="mt", fill=color)
    return hud


def preview(output):
    output.mkdir(parents=True, exist_ok=True)
    headings = [("Ahead", 0), ("Left", math.pi / 2), ("Behind", math.pi), ("Right", 3 * math.pi / 2),
                ("Ahead-left", math.pi / 4), ("Ahead-right", 7 * math.pi / 4)]
    sheet = Image.new("RGB", (6 * 200, 220), (20, 25, 31))
    draw = ImageDraw.Draw(sheet)
    for i, (label, angle) in enumerate(headings):
        draw.text((i * 200 + 12, 10), label, fill="white")
        hud = preview_hud(angle, label == "Behind").resize((198, 169), Image.Resampling.LANCZOS)
        sheet.paste(hud, (i * 200 + 1, 35), hud)
    sheet.save(output / "arrow-preview.png")
    preview_hud(math.pi / 4).save(output / "arrow-native.png")
    print(f"previews: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    generate()
    if args.preview:
        preview(args.preview)


if __name__ == "__main__":
    main()
