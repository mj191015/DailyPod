#!/usr/bin/env python3
"""Test A analysis: find gaps (> --min-gap seconds) between samples in bgtest_*.csv.

Usage: python3 tools/analyze_bgtest.py bgtest_mode2_*.csv [--min-gap 1.0]
If the matching *_events.csv sits next to the sample file, the time from the start event to the first
sample and from the last sample to the stop event is also counted (a run whose samples simply stop
has no gap *between* samples, so it would otherwise look clean).
Each gap row: last sample before the gap, first sample after it, length by wall clock and by
monotonic uptime (uptime stops while the device sleeps, so wall > uptime means the phone slept).
"""
import argparse, csv, sys


def load(path):
    rows = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            try:
                rows.append((float(r["wall_epoch"]), float(r["uptime_s"]), r["wall_iso"], r["mode"]))
            except (KeyError, ValueError):
                continue
    rows.sort(key=lambda x: x[0])
    return rows


def run_bounds(path):
    """(start_epoch, stop_epoch) from the paired events file, or None."""
    ev = path[:-4] + "_events.csv"
    start = stop = None
    try:
        with open(ev, newline="") as f:
            for r in csv.DictReader(f):
                t = float(r["wall_epoch"])
                if r["event"].startswith("start") and start is None:
                    start = t
                if r["event"].startswith("stop"):
                    stop = t
    except (OSError, KeyError, ValueError):
        return None
    return (start, stop) if start is not None and stop is not None else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--min-gap", type=float, default=1.0, help="gap threshold in seconds (default 1.0)")
    args = ap.parse_args()
    for path in args.files:
        rows = load(path)
        print(f"\n== {path}")
        if len(rows) < 2:
            print("  not enough samples")
            continue
        total = rows[-1][0] - rows[0][0]
        gaps = []
        bounds = run_bounds(path)
        if bounds:
            total = bounds[1] - bounds[0]
            iso = lambda t: __import__("datetime").datetime.utcfromtimestamp(t).isoformat(timespec="milliseconds") + "Z"
            if rows[0][0] - bounds[0] > args.min_gap:
                gaps.append((iso(bounds[0]) + " (start)", rows[0][2], rows[0][0] - bounds[0], rows[0][0] - bounds[0]))
            if bounds[1] - rows[-1][0] > args.min_gap:
                gaps.append((rows[-1][2], iso(bounds[1]) + " (stop)", bounds[1] - rows[-1][0], bounds[1] - rows[-1][0]))
        for a, b in zip(rows, rows[1:]):
            wall = b[0] - a[0]
            if wall > args.min_gap:
                gaps.append((a[2], b[2], wall, b[1] - a[1]))
        gaps.sort(key=lambda g: g[0])
        lost = sum(g[2] for g in gaps)
        print(f"  mode={rows[0][3]} samples={len(rows)} duration={total:.1f}s gaps>{args.min_gap}s: {len(gaps)} "
              f"total_gap={lost:.1f}s ({100 * lost / total:.1f}% of run)")
        if gaps:
            print(f"  {'gap_start(UTC)':<26} {'gap_end(UTC)':<32} {'wall_s':>9} {'uptime_s':>9}")
            for g in gaps:
                print(f"  {g[0]:<26} {g[1]:<32} {g[2]:>9.1f} {g[3]:>9.1f}")
        else:
            print("  no gaps: samples kept arriving the whole time")


if __name__ == "__main__":
    sys.exit(main())
