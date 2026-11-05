"""Check the alpha atlas used to feather exploration without hard tile seams."""
import importlib.util
from pathlib import Path
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("make_fog", ROOT / "tools/make_fog.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


class FogArtTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.atlas = Image.open(ROOT / "Wayfinder/Media/Fog/Blend.tga")

    def test_delivered_atlas_has_expected_dimensions_and_alpha_values(self):
        self.assertEqual(self.atlas.size, (1024, 1024))
        self.assertEqual(self.atlas.mode, "RGBA")
        for code in range(625):
            ox, oy = code % 32 * 32, code // 32 * 32
            for x, y in ((1, 1), (30, 1), (1, 30), (30, 30), (16, 16)):
                alpha = round(art.blend_alpha(code, (x-1)/29, (y-1)/29) * 255)
                self.assertEqual(self.atlas.getpixel((ox+x, oy+y)), (255, 255, 255, alpha))

    def test_patch_gutters_repeat_edge_texels(self):
        for code in range(625):
            ox, oy = code % 32 * 32, code // 32 * 32
            for i in range(32):
                self.assertEqual(self.atlas.getpixel((ox, oy+i)), self.atlas.getpixel((ox+1, oy+i)))
                self.assertEqual(self.atlas.getpixel((ox+31, oy+i)), self.atlas.getpixel((ox+30, oy+i)))
                self.assertEqual(self.atlas.getpixel((ox+i, oy)), self.atlas.getpixel((ox+i, oy+1)))
                self.assertEqual(self.atlas.getpixel((ox+i, oy+31)), self.atlas.getpixel((ox+i, oy+30)))

    def test_shared_corners_produce_identical_alpha_along_patch_seams(self):
        for code in range(625):
            tl, tr, bl, br = code % 5, code // 5 % 5, code // 25 % 5, code // 125
            right = tr + 5*tl + 25*br + 125*bl
            below = bl + 5*br + 25*tl + 125*tr
            for step in range(9):
                t = step / 8
                self.assertAlmostEqual(art.blend_alpha(code, 1, t), art.blend_alpha(right, 0, t))
                self.assertAlmostEqual(art.blend_alpha(code, t, 1), art.blend_alpha(below, t, 0))


if __name__ == "__main__":
    unittest.main()
