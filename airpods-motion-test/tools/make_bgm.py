#!/usr/bin/env python3
"""Synthesizes the test BGM loop (original, no copyrighted material) and converts it for the app.

Kick drum + clap + hi-hat + bass + fast arpeggio, 120 BPM, 24 bars = 48 s, mono 48 kHz.
Every sound wraps around the end of the buffer, so the loop is seamless.
The app plays techtest-app/Audio/bgm.caf. To use another song, replace that one file
(any of bgm.caf / .m4a / .mp3 / .wav / .aac works) and rebuild.

Usage: python3 tools/make_bgm.py        (needs numpy, scipy; macOS afconvert)
"""
import subprocess, wave, sys
from pathlib import Path
import numpy as np
from scipy.signal import butter, lfilter

SR = 48000
BPM = 120
STEP = SR * 60 // BPM // 4          # one 16th note = 6000 samples (exact)
BARS = 24
N = STEP * 16 * BARS                # 2,304,000 samples = 48.0 s
rng = np.random.default_rng(7)
buf = np.zeros(N)

def add(start, sig, gain=1.0):
    """Mix `sig` in at `start`, wrapping around the end so the loop has no seam."""
    idx = (start + np.arange(len(sig))) % N
    np.add.at(buf, idx, sig * gain)

def hp(x, f): b, a = butter(2, f / (SR / 2), "high"); return lfilter(b, a, x)
def lp(x, f): b, a = butter(2, f / (SR / 2), "low"); return lfilter(b, a, x)
def env(n, decay): return np.exp(-np.arange(n) / (SR * decay))
def midi(m): return 440.0 * 2 ** ((m - 69) / 12)

def kick():
    n = int(SR * 0.38); t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * env(n, 0.16) + 0.4 * rng.standard_normal(n) * env(n, 0.004))

def clap():
    n = int(SR * 0.22)
    return hp(rng.standard_normal(n), 1200) * env(n, 0.06)

def hat():
    n = int(SR * 0.07)
    return hp(rng.standard_normal(n), 7000) * env(n, 0.018)

def saw(f, n, detune=0.004):
    t = np.arange(n) / SR
    return sum(2 * ((t * f * (1 + d)) % 1.0) - 1 for d in (-detune, 0, detune)) / 3

def bass_note(f, n):
    return lp(saw(f, n, 0.002), 500) * env(n, 0.22)

def arp_note(f, n):
    t = np.arange(n) / SR
    sq = np.sign(np.sin(2 * np.pi * f * t)) * 0.6 + saw(f, n) * 0.4
    return lp(sq, 5200) * env(n, 0.075)

# chord progression per 2 bars: Am - F - C - G  (root MIDI, chord tones)
CHORDS = [(45, [57, 60, 64]), (41, [53, 57, 60]), (48, [55, 60, 64]), (43, [55, 59, 62])]
KICK, CLAP, HAT = kick(), clap(), hat()

for bar in range(BARS):
    root, tones = CHORDS[(bar // 2) % 4]
    base = bar * 16 * STEP
    for beat in range(4):
        add(base + beat * 4 * STEP, KICK, 1.0)                    # four on the floor
        if beat in (1, 3): add(base + beat * 4 * STEP, CLAP, 0.55)
        add(base + beat * 4 * STEP + 2 * STEP, HAT, 0.35)          # off-beat hat
    for s8 in range(8):                                            # rolling 8th-note bass
        n = int(STEP * 2 * 0.95)
        add(base + s8 * 2 * STEP, bass_note(midi(root if s8 % 4 != 3 else root + 12), n), 0.75)
    if bar >= 8:                                                   # fast arpeggio from bar 9
        pattern = [0, 1, 2, 1] if bar < 16 else [0, 1, 2, 3]
        seq = tones + [tones[0] + 12]
        for s16 in range(16):
            note = seq[pattern[s16 % 4]] + (12 if bar >= 16 and s16 % 8 >= 4 else 0)
            add(base + s16 * STEP, arp_note(midi(note + 12), int(STEP * 1.6)), 0.34)
    if bar >= 16:                                                  # extra hats in the last third
        for s16 in range(16):
            if s16 % 2: add(base + s16 * STEP, HAT, 0.2)

# loud master: soft clip, then peak at -1 dBFS
buf = np.tanh(buf * 1.6)
buf *= 0.89 / np.max(np.abs(buf))
pcm = (buf * 32767).astype("<i2")

here = Path(__file__).resolve().parent.parent
out_dir = here / "techtest-app" / "Audio"
out_dir.mkdir(parents=True, exist_ok=True)
wav_path = out_dir / "bgm_source.wav"
with wave.open(str(wav_path), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
caf_path = out_dir / "bgm.caf"
subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", str(wav_path), str(caf_path)], check=True)
print(f"{N / SR:.1f} s, peak {np.max(np.abs(buf)):.2f}, rms {np.sqrt(np.mean(buf ** 2)):.3f} -> {caf_path} ({caf_path.stat().st_size / 1e6:.1f} MB)")
