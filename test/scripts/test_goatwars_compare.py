import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest

PATH = pathlib.Path(__file__).resolve().parents[2] / "scripts/goatwars_compare.py"
spec = importlib.util.spec_from_file_location("compare", PATH)
compare = importlib.util.module_from_spec(spec)

class ComparisonTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        spec.loader.exec_module(compare)

    def test_tenfold_threshold_uses_whole_round_and_matching_work(self):
        baseline = "GW_BENCH word_bytes=8\nGW_ROUND cpu_us=100000 ticks=1035 rounds=5\n"
        fast = "GW_BENCH word_bytes=8\nGW_ROUND cpu_us=9999 ticks=1035 rounds=5\n"
        self.assertGreater(compare.speedup(baseline, fast), 10)
        self.assertLess(compare.speedup(baseline, fast.replace("9999", "10001")), 10)
        with self.assertRaises(ValueError):
            compare.speedup(baseline, fast.replace("1035", "1030"))
        with self.assertRaises(ValueError):
            compare.speedup(baseline, fast.replace("word_bytes=8", "word_bytes=4"))
        with self.assertRaises(ValueError):
            compare.speedup(baseline, "missing result")

    def test_overall_cpu_includes_every_frame_of_the_driver(self):
        baseline = "GW_BENCH word_bytes=8\nGW_ROUND cpu_us=100000 ticks=100 rounds=5\n"
        current = "GW_BENCH word_bytes=8\nGW_ROUND cpu_us=5000 ticks=100 rounds=5\n"
        self.assertAlmostEqual(compare.overall_speedup(baseline, current, "raster_us=100\n"*20, "raster_us=10\n"*20), 1100/60)
        with self.assertRaises(ValueError):
            compare.overall_speedup(baseline, current, "raster_us=100\n"*20, "raster_us=10\n"*19)

    def test_cli_can_enforce_a_new_fivefold_target_without_weakening_default(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            baseline, current = root / "before.log", root / "after.log"
            baseline.write_text("GW_BENCH word_bytes=8\nGW_ROUND cpu_us=100000 ticks=100 rounds=5\n")
            current.write_text("GW_BENCH word_bytes=8\nGW_ROUND cpu_us=20000 ticks=100 rounds=5\n")
            command = [sys.executable, str(PATH), str(baseline), str(current)]
            default = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(default.returncode, 0)
            five = subprocess.run(command + ["--minimum-speedup", "5"], capture_output=True, text=True)
            self.assertEqual(five.returncode, 0, five.stderr)
            invalid = subprocess.run(command + ["--minimum-speedup", "0"], capture_output=True, text=True)
            self.assertEqual(invalid.returncode, 2)
