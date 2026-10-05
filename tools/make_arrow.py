"""Render Wayfinder's compass from project-defined geometry, without source images.

python tools/make_arrow.py
python tools/make_arrow.py --preview <directory>

The world-space needle yaws counterclockwise from forward. A fixed orthographic
camera and light project its raised facets and shadow into 128 directional frames.
"""
import argparse
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

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
    rim = [(0, 43, 4), (10, 0, 4), (0, -23, 4), (-10, 0, 4)]
    ridge = (0, 2, 12)
    rim = [yaw(p, angle) for p in rim]
    ridge = yaw(ridge, angle)
    image = Image.new("RGBA", (FRAME * SS, FRAME * SS))
    shadow = Image.new("RGBA", image.size)
    shadow_draw = ImageDraw.Draw(shadow)
    # Project along a fixed light ray onto the compass plane.
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


def compass_base():
    image = Image.new("RGBA", (FRAME * SS, FRAME * SS))
    draw = ImageDraw.Draw(image)

    def ellipse(box, **kwargs):
        draw.ellipse([round(v * SS) for v in box], **kwargs)

    # Elliptical housing: front lip, inset slate face, brushed-metal top edge.
    ellipse((6, 30, 122, 112), fill=(7, 12, 18, 220))
    ellipse((6, 27, 122, 109), fill=(38, 51, 61, 255))
    ellipse((9, 30, 119, 106), fill=(65, 81, 91, 255))
    ellipse((12, 33, 116, 103), fill=(15, 24, 31, 255))
    ellipse((18, 37, 110, 99), outline=(43, 59, 68, 255), width=SS)
    for i in range(32):
        angle = i * math.tau / 32
        outer = project((-49 * math.sin(angle), -49 * math.cos(angle), 0))
        inner_radius = 41 if i % 8 == 0 else 45
        inner = project((-inner_radius * math.sin(angle), -inner_radius * math.cos(angle), 0))
        color = (112, 204, 224, 255) if i % 8 == 0 else (75, 96, 106, 255)
        draw.line([(round(x * SS), round(y * SS)) for x, y in (outer, inner)], fill=color,
                  width=(2 if i % 8 == 0 else 1) * SS)
    # A tiny pivot is visible where the shorter tail meets the needle ridge.
    ellipse((61, 65, 67, 71), fill=(76, 91, 101, 255))
    return image.resize((FRAME, FRAME), Image.Resampling.LANCZOS)


def generate(output=OUT):
    output.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (FRAME * COLUMNS, FRAME * ROWS))
    for index in range(COUNT):
        atlas.paste(needle(index * math.tau / COUNT), ((index % COLUMNS) * FRAME, (index // COLUMNS) * FRAME))
    # Match the uncompressed 32-bit TGA format already used by the addon.
    atlas.save(output / "NeedleAtlas.tga")
    compass_base().save(output / "CompassBase.tga")
    print(f"wrote {output.name}/NeedleAtlas.tga ({atlas.width}x{atlas.height}, {COUNT} headings) and CompassBase.tga")


def preview(output):
    output.mkdir(parents=True, exist_ok=True)
    headings = [("Ahead", 0), ("Left", math.pi / 2), ("Behind", math.pi), ("Right", 3 * math.pi / 2),
                ("Ahead-left", math.pi / 4), ("Ahead-right", 7 * math.pi / 4)]
    sheet = Image.new("RGB", (6 * 200, 244), (20, 25, 31))
    draw = ImageDraw.Draw(sheet)
    for i, (label, angle) in enumerate(headings):
        composed = compass_base()
        head = needle(angle)
        # Match Lua vertex tint: far cyan and near green.
        tint = (.45, .92, .45) if label == "Behind" else (.35, .84, 1)
        channels = head.split()
        tinted = Image.merge("RGBA", tuple(channels[j].point(lambda value, t=tint[j]: round(value * t))
                                          for j in range(3)) + (channels[3],))
        composed.alpha_composite(tinted)
        draw.text((i * 200 + 12, 10), label, fill="white")
        enlarged = composed.resize((192, 192), Image.Resampling.LANCZOS)
        sheet.paste(enlarged, (i * 200 + 4, 24), enlarged)
        draw.rounded_rectangle((i * 200 + 12, 190, i * 200 + 188, 234), 5, fill=(10, 17, 23), outline=(54, 95, 113))
        draw.text((i * 200 + 72, 196), "30 yd" if label == "Behind" else "100 yd", fill=(114, 234, 114) if label == "Behind" else (90, 215, 255))
        draw.text((i * 200 + 66, 216), "Waypoint", fill=(205, 218, 224))
    sheet.save(output / "compass-preview.png")
    # Native-size reference for legibility at the default in-game scale.
    hud = Image.new("RGBA", (130, 128), (20, 25, 31, 255))
    art = compass_base()
    head = needle(math.pi / 4)
    rgb = head.split()
    head = Image.merge("RGBA", tuple(rgb[j].point(lambda v, t=(.35, .84, 1)[j]: round(v * t)) for j in range(3)) + (rgb[3],))
    art.alpha_composite(head)
    art = art.resize((100, 100), Image.Resampling.LANCZOS)
    hud.alpha_composite(art, (15, -5))
    d = ImageDraw.Draw(hud)
    d.rectangle((3, 90, 127, 126), fill=(8, 15, 20), outline=(45, 96, 115))
    d.text((48, 93), "100 yd", fill=(90, 215, 255))
    d.text((38, 112), "Waypoint", fill=(205, 218, 224))
    hud.save(output / "compass-native.png")
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
