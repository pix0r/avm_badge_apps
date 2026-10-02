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

    def test_fixed_inputs_allow_policy_changes_but_reject_different_work(self):
        baseline = "GW_BENCH word_bytes=8\nGW_FIXED case=v1_cruise_23x23 cpu_us=20000 frames=1000\nGW_FIXED case=v1_blocked_78x46 cpu_us=40000 frames=1000\n"
        current = baseline.replace("20000", "10000").replace("40000", "80000")
        self.assertEqual(compare.fixed_speedups(baseline, current), {"v1_cruise_23x23": 2, "v1_blocked_78x46": 0.5})
        for invalid in [current.replace("frames=1000", "frames=999"), current.replace("word_bytes=8", "word_bytes=4"),
                        current.replace("v1_blocked", "v2_blocked"), current + "GW_FIXED case=v1_cruise_23x23 cpu_us=10 frames=1000\n",
                        current.replace("cpu_us=10000", "cpu_us=0")]:
            with self.assertRaises(ValueError):
                compare.fixed_speedups(baseline, invalid)

    def test_fixed_raster_comparison_covers_matching_fixture_cases(self):
        baseline = "GW_BENCH word_bytes=8\nGW_FIXED case=v1_cruise_23x23 cpu_us=20000 frames=1000\n"
        current = baseline.replace("20000", "10000")
        before = "GW_FIXED_RASTER case=v1_cruise_23x23 items=27 raster_us=100\n"
        after = before.replace("100", "200")
        self.assertAlmostEqual(compare.fixed_speedups(baseline, current, before, after)["v1_cruise_23x23"], 120/210)
        for invalid in ["", after + after, after.replace("v1", "v2"), after.replace("200", "0")]:
            with self.assertRaises(ValueError):
                compare.fixed_speedups(baseline, current, before, invalid)

    def test_fixed_cli_gates_each_case_with_native_driver_metadata(self):
        with tempfile.TemporaryDirectory() as folder:
            root = pathlib.Path(folder)
            paths = [root / name for name in ["before", "after", "before-raster", "after-raster"]]
            logs = ["GW_BENCH word_bytes=8\nGW_FIXED case=v1_blocked_23x23 cpu_us=20000 frames=1000\n",
                    "GW_BENCH word_bytes=8\nGW_FIXED case=v1_blocked_23x23 cpu_us=10000 frames=1000\n",
                    "GW_FIXED_RASTER case=v1_blocked_23x23 items=27 raster_us=100 checksum=123\n",
                    "GW_FIXED_RASTER case=v1_blocked_23x23 items=33 raster_us=100 checksum=456\n"]
            for path, log in zip(paths, logs):
                path.write_text(log)
            command = [sys.executable, str(PATH), *map(str, paths), "--fixed", "--minimum-speedup"]
            accepted = subprocess.run(command + ["1"], capture_output=True, text=True)
            self.assertEqual(accepted.returncode, 0, accepted.stderr)
            rejected = subprocess.run(command + ["2"], capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)

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
