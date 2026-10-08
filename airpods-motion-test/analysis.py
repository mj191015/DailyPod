"""AirPods Pro motion sensor test: summary tables + pitch graph.

Run:  python3 analysis.py      (needs numpy, pandas, scipy, matplotlib)
csv/ holds three recordings, one per motion type.
"""
from pathlib import Path
import numpy as np, pandas as pd
from scipy.signal import find_peaks, savgol_filter
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).parent
FILES = {"still": "20261008_131758_motion.csv",   # 가만히
         "nod":   "20261008_131825_motion.csv",   # 끄덕임
         "free":  "20261008_131902_motion.csv"}   # 자유 움직임
D = {k: pd.read_csv(HERE / "csv" / v) for k, v in FILES.items()}
deg = np.degrees

def tsec(d): return d.Timestamp.values - d.Timestamp.values[0]

print("== update interval (ms)")
for k, d in D.items():
    dt = np.diff(d.Timestamp.values) * 1e3
    print(f"{k:5} n={len(d)} mean={dt.mean():.1f} min={dt.min():.1f} max={dt.max():.1f}")

print("== axis range / std (deg)")
for k, d in D.items():
    print(k, " | ".join(f"{n} [{deg(d[c]).min():.1f},{deg(d[c]).max():.1f}] sd={deg(d[c]).std():.2f}"
          for n, c in [("pitch", "AttitudePitch"), ("roll", "AttitudeRoll"), ("yaw", "AttitudeYaw")]))

d = D["still"]; t = tsec(d); p = deg(d.AttitudePitch.values)
slope = np.polyfit(t, p, 1)[0]
print(f"== still: pitch sd={p.std():.2f} p2p={np.ptp(p):.2f} drift={slope:.3f} deg/s")

d = D["nod"]; tn = tsec(d)
pn = savgol_filter(deg(np.unwrap(d.AttitudePitch.values)), 25, 2)
pk, _ = find_peaks(pn, prominence=5); tr, _ = find_peaks(-pn, prominence=5)
ev = sorted([(i, "P") for i in pk] + [(i, "T") for i in tr])
sw = [(abs(pn[b] - pn[a]), tn[b] - tn[a]) for (a, x), (b, y) in zip(ev, ev[1:]) if x != y]
amp = np.array([s[0] for s in sw]); dur = np.array([s[1] for s in sw])
print(f"== nod: {len(sw)} half-swings, dpitch mean {amp.mean():.1f} deg, duration mean {dur.mean():.2f} s")

# ---- graph: one series (pitch) per panel, shared y-scale
ink, mute, line, grid = "#1f2933", "#6b7785", "#2f6fdb", "#e3e7ec"
fig, ax = plt.subplots(3, 1, figsize=(10, 9.2), sharey=True, facecolor="white")
pstill = deg(D["still"].AttitudePitch.values)
ax[0].plot(t, pstill, color=line, lw=2)
ax[0].set_title("Still: pitch stays within about 10°", loc="left", color=ink, fontsize=12)
ax[1].plot(tn, pn, color=line, lw=2)
ax[1].plot(tn[tr], pn[tr], "o", color=line, mec="white", mew=2, ms=8)
ax[1].axhline(np.median(pn), color=mute, lw=1, ls=(0, (4, 3)))
ax[1].text(tn[-1], np.median(pn) + 2, "resting pitch", color=mute, ha="right", fontsize=9)
ax[1].set_title("Nodding: pitch swings by tens of degrees (dots = deepest points)", loc="left", color=ink, fontsize=12)
df = D["free"]; tf = tsec(df); pf = deg(np.unwrap(df.AttitudePitch.values))
ax[2].plot(tf, pf, color=line, lw=2)
ax[2].set_title("Free movement: pitch ranges about 95° with no regular rhythm", loc="left", color=ink, fontsize=12)
for a in ax:
    a.set_facecolor("white"); a.set_ylabel("pitch (deg)", color=mute)
    a.grid(axis="y", color=grid, lw=1); a.set_axisbelow(True)
    for s in ("top", "right", "left"): a.spines[s].set_visible(False)
    a.spines["bottom"].set_color(grid); a.tick_params(colors=mute, length=0)
ax[2].set_xlabel("time (s)", color=mute)
fig.tight_layout()
fig.savefig(HERE / "pitch_three_motions.png", dpi=150)
print("saved pitch_three_motions.png")
