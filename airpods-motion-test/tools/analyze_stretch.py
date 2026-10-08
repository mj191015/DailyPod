#!/usr/bin/env python3
"""Test B analysis: can the distance to the reference separate correct attempts from other motions?

Usage: python3 tools/analyze_stretch.py stretch_attempts.csv
Prints, for both distance measures (simple, DTW), mean/min/max per label, whether
max(normal) < min(other), and the ratio min(other) / max(normal).
"""
import csv, sys
from statistics import mean

MEASURES = [("dist_simple", "(a) simple"), ("dist_dtw", "(b) DTW")]


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    by = {"normal": [], "other": []}
    with open(sys.argv[1], newline="") as f:
        for r in csv.DictReader(f):
            if r["label"] in by:
                by[r["label"]].append(r)
    print(f"attempts: normal={len(by['normal'])} other={len(by['other'])}")
    if not by["normal"] or not by["other"]:
        print("need at least one attempt of each label")
        return 1
    for col, name in MEASURES:
        print(f"\n== {name}")
        vals = {k: [float(r[col]) for r in v] for k, v in by.items()}
        print(f"  {'label':<8} {'n':>3} {'mean':>10} {'min':>10} {'max':>10}")
        for k in ("normal", "other"):
            v = vals[k]
            print(f"  {k:<8} {len(v):>3} {mean(v):>10.5f} {min(v):>10.5f} {max(v):>10.5f}")
        nmax, omin = max(vals["normal"]), min(vals["other"])
        ratio = omin / nmax if nmax > 0 else float("inf")
        print(f"  max(normal) < min(other): {'YES' if nmax < omin else 'NO'}   "
              f"ratio min(other)/max(normal) = {ratio:.2f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
