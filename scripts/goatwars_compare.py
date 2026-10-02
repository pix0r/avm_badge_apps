#!/usr/bin/env python3
"""Compare identical deterministic rounds on the same native AtomVM runtime."""
import pathlib
import argparse
import math
import re
import sys


def result(log):
    word = re.search(r"GW_BENCH word_bytes=(\d+)", log)
    round_result = re.search(r"GW_ROUND cpu_us=(\d+) ticks=(\d+) rounds=(\d+)", log)
    if not word or not round_result:
        raise ValueError("missing complete benchmark result")
    cpu, ticks, rounds = map(int, round_result.groups())
    if min(cpu, ticks, rounds) <= 0:
        raise ValueError("empty benchmark workload")
    return int(word[1]), cpu, ticks, rounds


def speedup(baseline, current):
    before, after = result(baseline), result(current)
    if (before[0], before[2], before[3]) != (after[0], after[2], after[3]):
        raise ValueError("benchmarks used different runtimes or workloads")
    return before[1] / after[1]


def overall_speedup(baseline, current, before_raster, after_raster):
    speedup(baseline, current)
    before, after = result(baseline), result(current)
    raster = [list(map(float, re.findall(r"raster_us=([0-9.]+)", log)))
              for log in [before_raster, after_raster]]
    expected = before[2] // before[3]
    if any(len(values) != expected or min(values) <= 0 for values in raster):
        raise ValueError("raster benchmark did not cover every round frame")
    costs = [cpu / ticks + sum(values) / len(values)
             for (_, cpu, ticks, _), values in zip([before, after], raster)]
    return costs[0] / costs[1]


def fixed_speedups(baseline, current, before_raster=None, after_raster=None):
    logs = [baseline, current]
    words = [re.findall(r"GW_BENCH word_bytes=(\d+)", log) for log in logs]
    if any(len(word) != 1 for word in words) or words[0] != words[1]:
        raise ValueError("fixed fixtures used different or missing runtimes")
    fixtures = []
    for log in logs:
        rows = re.findall(r"GW_FIXED case=(\S+) cpu_us=(\d+) frames=(\d+)", log)
        values = {case: (int(cpu), int(frames)) for case, cpu, frames in rows}
        if not values or len(values) != len(rows) or any(min(value) <= 0 for value in values.values()):
            raise ValueError("missing, duplicate or empty fixed fixture")
        fixtures.append(values)
    before, after = fixtures
    if before.keys() != after.keys() or any(before[case][1] != after[case][1] for case in before):
        raise ValueError("fixed fixtures used different workloads")
    raster = [{case: 0 for case in before} for _ in logs]
    if before_raster is not None or after_raster is not None:
        for index, log in enumerate([before_raster, after_raster]):
            rows = re.findall(r"GW_FIXED_RASTER case=(\S+)[^\n]*? raster_us=([0-9.]+)", log or "")
            values = {case: float(cost) for case, cost in rows}
            if values.keys() != before.keys() or len(values) != len(rows) or any(not math.isfinite(cost) or cost <= 0 for cost in values.values()):
                raise ValueError("raster did not cover every fixed fixture exactly once")
            raster[index] = values
    return {case: (before[case][0] / before[case][1] + raster[0][case]) /
                  (after[case][0] / after[case][1] + raster[1][case]) for case in before}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+")
    parser.add_argument("--minimum-speedup", type=float, default=10)
    parser.add_argument("--fixed", action="store_true", help="compare matching immutable input fixtures across AI policy changes")
    args = parser.parse_args()
    if len(args.logs) not in (2, 4):
        parser.error("supply two VM logs, optionally followed by two raster logs")
    if not math.isfinite(args.minimum_speedup) or args.minimum_speedup <= 0:
        parser.error("minimum speedup must be positive and finite")
    try:
        logs = [pathlib.Path(path).read_text() for path in args.logs]
        if args.fixed:
            ratios = fixed_speedups(*logs)
            for case, value in ratios.items():
                print(f"Fixed-input {case} CPU improvement: {value:.2f}x")
            ratio = min(ratios.values())
        else:
            ratio = speedup(*logs) if len(logs) == 2 else overall_speedup(*logs)
        label = "advance + render" if len(logs) == 2 else "advance + render + native raster"
        if not args.fixed:
            print(f"Whole-round {label} CPU improvement: {ratio:.2f}x")
        if ratio < args.minimum_speedup:
            sys.exit(f"performance gate failed: require at least {args.minimum_speedup:g}x")
    except (ValueError, OSError, TypeError) as error:
        sys.exit(str(error))
