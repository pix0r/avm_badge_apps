#!/usr/bin/env python3
"""Compare identical deterministic rounds on the same native AtomVM runtime."""
import pathlib
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


if __name__ == "__main__":
    try:
        logs = [pathlib.Path(path).read_text() for path in sys.argv[1:]]
        ratio = speedup(*logs) if len(logs) == 2 else overall_speedup(*logs)
        label = "advance + render" if len(logs) == 2 else "advance + render + native raster"
        print(f"Whole-round {label} CPU improvement: {ratio:.2f}x")
        if ratio < 10:
            sys.exit("performance gate failed: require at least 10x")
    except (ValueError, OSError, TypeError) as error:
        sys.exit(str(error))
