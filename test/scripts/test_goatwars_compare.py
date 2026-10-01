import importlib.util
import pathlib
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
