"""Check the delivered compass atlas, geometric direction and texture gutters."""
import hashlib
import importlib.util
import math
from pathlib import Path
import unittest
from PIL import Image
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("make_arrow", ROOT / "tools/make_arrow.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


class ArrowArtTest(unittest.TestCase):
    def test_missing_new_artwork_uses_a_working_pointer_at_startup(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute((ROOT / "tests/wowmock.lua").read_text(encoding="utf-8"))
        lua.execute('''
            local prototype = getmetatable(UIParent)
            local setTexture = prototype.SetTexture
            function prototype:SetTexture(path)
                if path and path:find("NeedleAtlas", 1, true) then
                    self.texture = nil
                    return false
                end
                return setTexture(self, path)
            end
        ''')
        ns = lua.table()
        for line in (ROOT / "Wayfinder/Wayfinder.toc").read_text(encoding="utf-8").splitlines():
            if line.endswith(".lua"):
                lua.execute((ROOT / "Wayfinder" / line.replace("\\", "/")).read_text(encoding="utf-8"), "Wayfinder", ns)
        lua.execute('mock.Fire("ADDON_LOADED", "Wayfinder"); mock.Fire("PLAYER_LOGIN")')
        arrow = lua.globals().WayfinderArrow
        self.assertFalse(arrow.useAtlas)
        self.assertFalse(arrow.base.shown)
        self.assertTrue(arrow.head.texture.endswith("PlayerArrow"))
        self.assertIn("Restart the game", lua.globals().mock.printed)
        lua.globals().mock.facing = 0
        ns.Navigation.SetWaypointOnMap(ns.Navigation, 1429, .52, .65, "Fallback destination")
        self.assertTrue(arrow.head.shown)
        self.assertAlmostEqual(arrow.head.rotation, -math.pi / 2)
        self.assertIn("yd", arrow.distance.text)

    def test_texture_format_and_atlas_dimensions_are_client_compatible(self):
        for name, size in (("NeedleAtlas", (2048, 1024)), ("CompassBase", (128, 128))):
            path = ROOT / "Wayfinder/Media/Arrow" / (name + ".tga")
            header = path.read_bytes()[:18]
            self.assertEqual(header[2], 2, "uncompressed true-color TGA")
            self.assertEqual(header[16], 32, "32-bit texture with alpha")
            with Image.open(path) as image:
                self.assertEqual(image.size, size)
                self.assertEqual(image.mode, "RGBA")

    def test_every_heading_is_distinct_and_has_a_transparent_gutter(self):
        hashes = set()
        with Image.open(ROOT / "Wayfinder/Media/Arrow/NeedleAtlas.tga") as atlas:
            for index in range(128):
                x, y = (index % 16) * 128, (index // 16) * 128
                frame = atlas.crop((x, y, x + 128, y + 128))
                bounds = frame.getchannel("A").getbbox()
                self.assertIsNotNone(bounds)
                self.assertGreaterEqual(bounds[0], 4)
                self.assertGreaterEqual(bounds[1], 4)
                self.assertLessEqual(bounds[2], 124)
                self.assertLessEqual(bounds[3], 124)
                hashes.add(hashlib.sha256(frame.tobytes()).digest())
        self.assertEqual(len(hashes), 128)

    def test_projection_points_forward_left_behind_and_right(self):
        tip = (0, 43, 4)
        expected = [(0, -1), (-1, 0), (0, 1), (1, 0)]
        for i, (dx, dy) in enumerate(expected):
            point = art.project(art.yaw(tip, i * math.pi / 2))
            if dx:
                self.assertGreater((point[0] - art.ORIGIN[0]) * dx, 40)
            if dy:
                self.assertGreater((point[1] - art.ORIGIN[1]) * dy, 25)
        # The raised ridge must project above a point on the compass surface.
        self.assertLess(art.project((0, 0, 12))[1], art.project((0, 0, 0))[1] - 8)


if __name__ == "__main__":
    unittest.main()
