"""Builds the summary tables and charts from the raw logs.
Run:  python3 build_summary.py   (needs pandas, numpy, matplotlib)
Raw logs are read from data/raw_logs/ (the phone Documents folder, copied to the Mac)."""
import csv, glob, os
from pathlib import Path
import numpy as np, pandas as pd
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = Path(__file__).parent
LOGS = HERE / "data" / "raw_logs"      # raw logs copied from the phone (Documents)
plt.rcParams["font.family"] = "Apple SD Gothic Neo"
plt.rcParams["axes.unicode_minus"] = False
BLUE, ORANGE, GRAY, INK, MUTE, GRID = "#2f6fdb", "#d9822b", "#d5dbe3", "#1f2933", "#6b7785", "#e3e7ec"

def clean(ax):
    for s in ("top", "right", "left"): ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(GRID); ax.tick_params(colors=MUTE, length=0)
    ax.grid(axis="x", color=GRID, lw=1); ax.set_axisbelow(True)

def mmss(sec): return f"{int(sec)//60}분 {int(sec)%60:02d}초"

# ---------- Test A: background runs (맥북 Bluetooth를 끈 상태의 실험만) ----------
MODE_NAME = {1: "모드1 아무것도 안 함", 2: "모드2 무음 오디오", 3: "모드3 무음 오디오+재개",
             4: "모드4 위치(정확도 낮음)", 5: "모드5 위치(GPS 최고)"}
VALID = ["mode2_20261009_002959", "mode1_20261009_003309", "mode2_20261009_003613", "mode3_20261009_003922",
         "mode4_20261009_004831", "mode4_20261009_005206", "mode2_20261009_010335", "mode5_20261009_011554"]
rows = []
for key in VALID:
    s = pd.read_csv(LOGS / f"bgtest_{key}.csv")
    ev = list(csv.DictReader(open(LOGS / f"bgtest_{key}_events.csv")))
    start = float(next(e["wall_epoch"] for e in ev if e["event"].startswith("start")))
    stop = float(next(e["wall_epoch"] for e in ev if e["event"].startswith("stop")))
    bg_in = [float(e["wall_epoch"]) for e in ev if "did enter background" in e["event"]]
    bg_out = [float(e["wall_epoch"]) for e in ev if "will enter foreground" in e["event"]]
    t = s.wall_epoch.values
    gaps = [(a, b) for a, b in zip(np.r_[start, t], np.r_[t, stop]) if b - a > 1.0]
    lost = sum(b - a for a, b in gaps)
    total = stop - start
    mode = int(s["mode"].iloc[0])
    rows.append(dict(mode=mode, mode_name=MODE_NAME[mode], run=key, total_s=round(total, 1),
                     background_s=round((bg_out[0] - bg_in[0]) if bg_in and bg_out else 0, 1),
                     data_received_s=round(total - lost, 1), data_lost_s=round(lost, 1),
                     received_pct=round(100 * (total - lost) / total, 1), samples=len(s),
                     longest_gap_s=round(max([b - a for a, b in gaps], default=0), 1)))
bg = pd.DataFrame(rows).sort_values(["mode", "total_s"], ignore_index=True)
bg.to_csv(HERE / "data" / "background_runs.csv", index=False)

fig, ax = plt.subplots(figsize=(10, 4.6), facecolor="white")
for i, r in bg.iterrows():
    y = len(bg) - 1 - i
    ax.barh(y, r.data_received_s, color=BLUE, height=0.62)
    ax.barh(y, r.data_lost_s, left=r.data_received_s, color=GRAY, height=0.62)
    ax.text(r.total_s + 6, y, f"{mmss(r.data_received_s)} 수신 ({r.received_pct:.0f}%)", va="center", fontsize=9.5, color=INK)
ax.set_yticks(range(len(bg))); ax.set_yticklabels([f"{r.mode_name}  ·  전체 {mmss(r.total_s)}" for _, r in bg.iloc[::-1].iterrows()], fontsize=9.5, color=INK)
ax.set_xlim(0, bg.total_s.max() * 1.33); ax.set_xlabel("시간 (초)", color=MUTE)
ax.set_title("앱을 홈/잠금으로 보냈을 때 센서 값이 들어온 시간 (파랑 = 들어옴, 회색 = 안 들어옴)", loc="left", color=INK, fontsize=12)
clean(ax); fig.tight_layout(); fig.savefig(HERE / "charts" / "2_background.png", dpi=150); plt.close(fig)

# ---------- Test B: DTW distances ----------
a = pd.read_csv(HERE / "data" / "stretch_attempts.csv")
names = ["정상 1", "정상 2", "정상 3", "정상 4", "정상 5", "다른: 왼오 기울이기", "다른: 좌우 도리도리", "다른: 꾸벅꾸벅", "다른: 방향 반대로 돌리기", "다른: 앞뒤로 꺾기"]
fig, ax = plt.subplots(figsize=(10, 4.4), facecolor="white")
for i, (_, r) in enumerate(a.iterrows()):
    c = BLUE if r.label == "normal" else ORANGE
    ax.bar(i, r.dist_dtw, color=c, width=0.62)
    ax.text(i, r.dist_dtw + 0.02, f"{r.dist_dtw:.2f}", ha="center", fontsize=9.5, color=INK)
nmax = a[a.label == "normal"].dist_dtw.max(); omin = a[a.label == "other"].dist_dtw.min()
ax.axhspan(nmax, omin, color="#eef1f5", zorder=0)
ax.text(1.9, (nmax + omin) / 2 + 0.03, f"빈 구간\n정상 최대 {nmax:.2f}  ↔  다른 동작 최소 {omin:.2f}\n({omin/nmax:.1f}배 차이)", ha="center", va="center", fontsize=10, color=MUTE, linespacing=1.5)
ax.set_xticks(range(10)); ax.set_xticklabels(names, rotation=28, ha="right", fontsize=9, color=INK)
ax.set_ylabel("기준 동작과의 거리 (DTW, 작을수록 비슷)", color=MUTE); ax.set_ylim(0, 1.3)
ax.set_title("기준 동작과의 거리: 파랑 = 같은 동작, 주황 = 다른 동작", loc="left", color=INK, fontsize=12)
ax.grid(axis="y", color=GRID, lw=1); ax.grid(axis="x", visible=False)
for s_ in ("top", "right", "left"): ax.spines[s_].set_visible(False)
ax.spines["bottom"].set_color(GRID); ax.tick_params(colors=MUTE, length=0)
fig.tight_layout(); fig.savefig(HERE / "charts" / "3_stretch_dtw.png", dpi=150); plt.close(fig)
cmp_rows = []
for col, name in [("dist_simple", "단순 비교"), ("dist_dtw", "DTW")]:
    n = a[a.label == "normal"][col]; o = a[a.label == "other"][col]
    cmp_rows.append(dict(method=name, normal_min=round(n.min(), 3), normal_max=round(n.max(), 3), other_min=round(o.min(), 3),
                         other_max=round(o.max(), 3), separated=bool(n.max() < o.min()), ratio=round(o.min() / n.max(), 2)))
pd.DataFrame(cmp_rows).to_csv(HERE / "data" / "stretch_comparison.csv", index=False)

# ---------- Test D: AlarmKit runs ----------
intent = [float(r["wall_epoch"]) for r in csv.DictReader(open(HERE / "data" / "alarmkit_x_intent_log.csv"))
          if "alarm stopped by X" in r["event"]] if False else []
ik = list(csv.DictReader(open(HERE / "data" / "alarmkit_x_intent_log.csv")))
x_stops = [pd.Timestamp(r["wall_iso"]).timestamp() for r in ik if "alarm stopped by X" in r["event"]]
runs = []
for f in sorted(glob.glob(str(LOGS / "xalarmkit_2*.csv"))):
    rr = list(csv.DictReader(open(f)))
    i = 0
    while i < len(rr):
        if "alarm scheduled" in rr[i]["event"]:
            sched = float(rr[i]["wall_epoch"]); fire = end = None; app = None; how = "-"
            j = i + 1
            while j < len(rr) and "alarm scheduled" not in rr[j]["event"]:
                e = rr[j]
                if "alerting" in e["event"] and fire is None: fire, app = float(e["wall_epoch"]), e["app"]
                if "X pressed in full-screen overlay" in e["event"]: how = "앱 안 전체 화면 X"
                if "finished" in e["event"] and end is None: end = float(e["wall_epoch"])
                j += 1
            if fire and end:
                if how == "-": how = "알람 화면 X 버튼" if any(abs(end - x) < 1.0 for x in x_stops) else "X 외 방법(시스템 기본 끄기 등)"
                runs.append(dict(app_state_when_ringing={"active": "앱 켜 둠", "background": "홈/잠금"}.get(app, app),
                                 seconds_after_schedule=round(fire - sched, 1), ringing_seconds=round(end - fire, 1), stopped_by=how))
            i = j
        else: i += 1
pd.DataFrame(runs).to_csv(HERE / "data" / "alarmkit_runs.csv", index=False)
print(bg.to_string(index=False)); print(pd.DataFrame(cmp_rows).to_string(index=False)); print(pd.DataFrame(runs).to_string(index=False))

# ---------- 센서 값 그래프 (가만히 / 끄덕임 / 자유 움직임, 같은 눈금) ----------
from scipy.signal import savgol_filter, find_peaks
SENS = [("20261008_131758", "가만히: 10°쯤의 작은 흔들림뿐"), ("20261008_131825", "고개 끄덕임: 수십 도씩 크게 출렁임 (점 = 가장 깊이 숙인 지점)"),
        ("20261008_131902", "자유 움직임: 불규칙하게 크게 움직임")]
fig, axs = plt.subplots(3, 1, figsize=(10, 9), sharey=True, facecolor="white")
for ax, (f, title) in zip(axs, SENS):
    d = pd.read_csv(HERE.parent / "csv" / f"{f}_motion.csv"); t = d.Timestamp.values - d.Timestamp.values[0]
    p = np.degrees(np.unwrap(d.AttitudePitch.values))
    if "끄덕임" in title:
        p = savgol_filter(p, 25, 2); tr, _ = find_peaks(-p, prominence=5)
        ax.plot(t[tr], p[tr], "o", color=BLUE, mec="white", mew=2, ms=8, zorder=3)
    ax.plot(t, p, color=BLUE, lw=2)
    ax.set_title(title, loc="left", color=INK, fontsize=12); ax.set_ylabel("앞뒤 기울기 (도)", color=MUTE)
    ax.grid(axis="y", color=GRID, lw=1); ax.set_axisbelow(True)
    for s_ in ("top", "right", "left"): ax.spines[s_].set_visible(False)
    ax.spines["bottom"].set_color(GRID); ax.tick_params(colors=MUTE, length=0)
axs[-1].set_xlabel("시간 (초)", color=MUTE)
fig.tight_layout(); fig.savefig(HERE / "charts" / "1_sensor_pitch.png", dpi=150); plt.close(fig)
