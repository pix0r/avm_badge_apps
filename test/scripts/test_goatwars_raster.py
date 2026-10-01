import os
import pathlib
import struct
import subprocess
import tempfile
import unittest

EXE = os.environ.get("GOATWARS_RASTER_EXE")

@unittest.skipUnless(EXE, "Set GOATWARS_RASTER_EXE to test the pinned native display driver")
class CroppedRasterTest(unittest.TestCase):
    def test_opaque_text_covers_blank_glyph_pixels(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            scene = root / "opaque.scene"
            scene.write_text("2\n3 4 4 0 0 16777215 32 A\n0 0 0 320 240 65280 \n")
            output = root / "frame.rgb565"
            env = dict(os.environ, GOATWARS_FRAME_DUMP=str(output))
            result = subprocess.run([EXE, str(scene)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            pixels = output.read_bytes()
            colors = [struct.unpack_from(">H", pixels, (y*320+x)*2)[0]
                      for y in range(4, 20) for x in range(4, 12)]
            self.assertEqual(set(colors), {0xFFFF, 0x0004})
            self.assertEqual(struct.unpack_from(">H", pixels, (2*320+2)*2)[0], 0x07E0)

    def test_artwork_transparency_uses_its_declared_background(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            image = root / "transparent.rgba"
            image.write_bytes(bytes([255, 0, 0, 0]))
            scene = root / "art.scene"
            scene.write_text(f"2\n2 4 4 2 2 2364210 0 0 2 2 1 1 {image}\n0 0 0 320 240 65280 \n")
            output = root / "frame.rgb565"
            result = subprocess.run([EXE, str(scene)], env=dict(os.environ, GOATWARS_FRAME_DUMP=str(output)), capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            pixels = output.read_bytes()
            self.assertEqual(struct.unpack_from(">H", pixels, (4*320+4)*2)[0], 0x2086)

    def test_crop_scale_and_rgba_colors_reach_the_actual_driver(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            image = root / "colors.rgba"
            image.write_bytes(bytes([0,0,0,255])*4 + bytes([0,255,0,255, 0,0,255,255,
                                  0,0,0,255, 255,255,0,255, 255,0,0,255]))
            scene = root / "crop.scene"
            scene.write_text(f"2\n2 4 4 8 8 0 1 1 4 4 3 3 {image}\n0 0 0 320 240 0 \n")
            output = root / "frame.rgb565"
            env = dict(os.environ, GOATWARS_FRAME_DUMP=str(output))
            result = subprocess.run([EXE, str(scene)], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output.exists(), "native raster must expose its rendered pixels")
            pixels = output.read_bytes()
            self.assertEqual(len(pixels), 320*240*2)
            for x,y,color in [(6,6,0x07E0),(10,6,0x001F),(6,10,0xFFE0),(10,10,0xF800),(2,2,0)]:
                self.assertEqual(struct.unpack_from(">H", pixels, (y*320+x)*2)[0], color)
