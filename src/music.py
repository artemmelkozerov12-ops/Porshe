"""Dark trap / phonk-style bass track, synthesized from scratch with numpy.

120 BPM, 16th-note grid, bar = 2 s. Arrangement is locked to the video timeline:
  0-4 s   intro (pad swell, riser, pre-drop gap)
  4 s     DROP  (reveal)
  4-20 s  full beat, lead enters at 12 s
  20 s    impact (specs section)
  28 s    impact (outro), beat stops at 30 s
  30-34 s tail
Writes output/audio/track.wav and src/beats.json (hit times used by the video).
"""
import json
import os
import wave

import numpy as np

SR = 48000
BPM = 120
STEP = 60 / BPM / 4          # 16th note = 0.125 s
BAR = STEP * 16              # 2 s
LENGTH = 34.0
N = int(SR * LENGTH)
rng = np.random.default_rng(911)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def fft_filter(x, lo=None, hi=None, slope=1.0):
    """Zero-phase band filter with soft (Butterworth-like) magnitude response."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (4 * slope))
    if lo:
        with np.errstate(divide="ignore"):
            g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (4 * slope))
    return np.fft.irfft(X * g, n=len(x))


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    nfft = 1 << (n - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)
    return y[: len(x)]


def place(buf, sig, t0, gain=1.0):
    i = int(t0 * SR)
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    buf[i:j] += sig[: j - i] * gain


# ---------------------------------------------------------------- instruments
def e808(freq, dur, glide_to=None, drive=2.6):
    t = t_axis(dur)
    f = freq * (1 + 1.6 * np.exp(-t / 0.010))
    if glide_to:
        k = np.clip((t - dur * 0.45) / (dur * 0.4), 0, 1)
        k = k * k * (3 - 2 * k)
        f = f * (1 - k) + glide_to * k
    ph = 2 * np.pi * np.cumsum(f) / SR
    env = np.minimum(1, t / 0.002) * np.exp(-t / 0.75)
    rel = np.clip((dur - t) / 0.02, 0, 1)          # declick at note end
    s = np.sin(ph)
    s = np.tanh(drive * s) / np.tanh(drive)
    return s * env * rel


def kick():
    t = t_axis(0.35)
    f = 48 + 160 * np.exp(-t / 0.022)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.11)
    click = fft_filter(rng.standard_normal(len(t)), lo=2000, hi=9000) * np.exp(-t / 0.003) * 0.35
    return np.tanh(1.8 * (s + click))


def clap():
    t = t_axis(0.45)
    n = rng.standard_normal(len(t))
    env = np.zeros_like(t)
    for k, d in enumerate([0.0, 0.009, 0.018]):
        env += (t >= d) * np.exp(-np.maximum(t - d, 0) / 0.006) * (0.8 if k < 2 else 1)
    env += (t >= 0.018) * np.exp(-np.maximum(t - 0.018, 0) / 0.13) * 0.55
    s = fft_filter(n, lo=900, hi=5500) * env
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04) * 0.4
    return (s + body) * 0.9


def hat(open_=False):
    dur = 0.35 if open_ else 0.08
    t = t_axis(dur)
    n = fft_filter(rng.standard_normal(len(t)), lo=7000, hi=16000)
    return n * np.exp(-t / (0.12 if open_ else 0.018)) * 2.6


def bell(freq, dur=1.2):
    """FM bell: glassy, dark-ish phonk lead."""
    t = t_axis(dur)
    idx = 2.2 * np.exp(-t / 0.18)
    mod = np.sin(2 * np.pi * freq * 3.5 * t) * idx
    s = np.sin(2 * np.pi * freq * t + mod)
    s += 0.35 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t / 0.15)
    return s * np.minimum(1, t / 0.003) * np.exp(-t / 0.42)


def saw(freq, t, detune=0.0):
    ph = (freq * (1 + detune) * t) % 1.0
    return 2 * ph - 1


def impact():
    t = t_axis(2.6)
    f = 30 + 70 * np.exp(-t / 0.06)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.7)
    noise = fft_filter(rng.standard_normal(len(t)), hi=1800) * np.exp(-t / 0.25) * 0.45
    return np.tanh(2.0 * (boom + noise))


def riser(dur):
    t = t_axis(dur)
    x = t / dur
    noise = rng.standard_normal(len(t))
    dark = fft_filter(noise, lo=200, hi=900)
    bright = fft_filter(noise, lo=2500, hi=12000)
    s = dark * (1 - x) + bright * x
    sweep = np.sin(2 * np.pi * np.cumsum(180 + 1400 * x ** 2) / SR) * 0.25
    return (s * 0.6 + sweep) * x ** 2.2


# ------------------------------------------------------------------- buses
drums = np.zeros(N)
bass = np.zeros(N)
padL = np.zeros(N)
padR = np.zeros(N)
lead = np.zeros(N)
fx = np.zeros(N)
hatsL = np.zeros(N)
hatsR = np.zeros(N)
kick_env = np.zeros(N)

hits = {"bass": [], "clap": [], "impact": [], "kick": []}

K, C, HC, HO = kick(), clap(), hat(), hat(True)

# 808 roots per bar in a 4-bar loop (E minor): E1 E1 C1 D1
ROOTS = [41.20, 41.20, 32.70, 36.71]
BASS_STEPS = [(0, 6), (6, 4), (10, 6)]          # (start step, length in steps)

beat_bars = range(2, 15)                         # 4 s .. 30 s
for b in beat_bars:
    t0 = b * BAR
    root = ROOTS[b % 4]
    nxt = ROOTS[(b + 1) % 4]
    last_bar = b == 14
    for k, (st, ln) in enumerate(BASS_STEPS):
        if last_bar and k > 0:
            break
        ts = t0 + st * STEP
        dur = (16 if last_bar else ln) * STEP + 0.05
        glide = nxt if (k == 2 and b % 2 == 1 and not last_bar) else None
        f = root * (2 if (k == 1 and b % 4 == 3) else 1)  # octave jump for movement
        place(bass, e808(f, dur, glide, drive=3.4), ts, 0.85)
        place(drums, K, ts, 0.75)
        place(kick_env, np.exp(-t_axis(0.3) / 0.09), ts)
        hits["bass"].append(round(ts, 4))
        hits["kick"].append(round(ts, 4))
    if not last_bar:
        for st in (4, 12):
            place(drums, C, t0 + st * STEP, 0.85)
            hits["clap"].append(round(t0 + st * STEP, 4))
        # hats: 8ths, 16ths in second half, triplet roll every 2nd bar
        steps = list(range(0, 8, 2)) + list(range(8, 16))
        for i, st in enumerate(steps):
            if b % 2 == 1 and st >= 14:
                continue
            g = 0.22 if st % 2 else 0.32
            place(hatsL if i % 2 else hatsR, HC, t0 + st * STEP, g)
            place(hatsR if i % 2 else hatsL, HC, t0 + st * STEP, g * 0.45)
        if b % 2 == 1:
            for r in range(6):                   # 32nd-triplet roll into next bar
                ts = t0 + 14 * STEP + r * (2 * STEP / 6)
                g = 0.12 + 0.04 * r
                place(hatsL, HC, ts, g)
                place(hatsR, HC, ts, g)
        if b % 4 == 2:
            place(hatsL, HO, t0 + 7 * STEP, 0.18)
            place(hatsR, HO, t0 + 7 * STEP, 0.18)
    else:
        for st in (0, 4, 8, 12):
            place(hatsL, HC, t0 + st * STEP, 0.15)
            place(hatsR, HC, t0 + st * STEP, 0.15)

# final long 808 at 30 s (outro logo)
place(bass, e808(41.20, 4.0), 30.0, 0.9)
hits["bass"].append(30.0)

# impacts
for ti in (4.0, 20.0, 28.0):
    place(fx, impact(), ti, 0.75)
    hits["impact"].append(ti)

# riser into the drop + pre-drop gap 3.75-4.0
place(fx, riser(2.75), 1.0, 0.45)

# reverse swell (reversed noise burst) into 20 s
rev = fft_filter(rng.standard_normal(int(SR * 1.0)), lo=400, hi=8000) * np.exp(-t_axis(1.0) / 0.25)
place(fx, rev[::-1] * 0.5, 19.0)

# ---------------------------------------------------------------- pad
CHORDS = [  # per bar, 4-bar loop: Em, Em, Cmaj7, D
    [164.81, 196.00, 246.94],
    [164.81, 196.00, 246.94],
    [130.81, 164.81, 196.00, 246.94],
    [146.83, 185.00, 220.00],
]
tt = np.arange(N) / SR
for b in range(0, 17):
    t0 = b * BAR
    i0, i1 = int(t0 * SR), min(N, int((t0 + BAR + 0.15) * SR))
    seg_t = tt[i0:i1] - t0
    fade = np.minimum(1, seg_t / 0.15) * np.clip((BAR + 0.15 - seg_t) / 0.15, 0, 1)
    for f in CHORDS[b % 4]:
        padL[i0:i1] += saw(f, tt[i0:i1], -0.004) * fade
        padR[i0:i1] += saw(f, tt[i0:i1], +0.004) * fade
        padL[i0:i1] += saw(f / 2, tt[i0:i1], +0.002) * fade * 0.5
        padR[i0:i1] += saw(f / 2, tt[i0:i1], -0.002) * fade * 0.5

# filter sweep: dark during intro, opens at the drop, darker in the outro
dark_L, dark_R = fft_filter(padL, hi=420), fft_filter(padR, hi=420)
br_L, br_R = fft_filter(padL, hi=2200), fft_filter(padR, hi=2200)
open_ = np.interp(tt, [0, 3.7, 4.0, 27.5, 30, 34], [0.0, 0.55, 1.0, 1.0, 0.2, 0.0])
padL = dark_L * (1 - open_) + br_L * open_
padR = dark_R * (1 - open_) + br_R * open_
pad_gain = np.interp(tt, [0, 2.0, 3.74, 3.76, 3.99, 4.0, 30, 33.8, 34], [0, .9, 1, 0, 0, 1, 1, 0.35, 0])
padL *= pad_gain * 0.07
padR *= pad_gain * 0.07

# ---------------------------------------------------------------- lead
MEL = [(0, 329.63), (3, 392.00), (6, 493.88), (8, 440.00), (11, 392.00), (14, 293.66),
       (16, 329.63), (19, 392.00), (22, 587.33), (24, 493.88), (27, 440.00), (30, 392.00)]
for b in range(6, 14, 2):                        # 12 s .. 28 s, 2-bar phrases
    for st, f in MEL:
        place(lead, bell(f), b * BAR + st * STEP, 0.26)

# ---------------------------------------------------------------- mix
duck = 1 - 0.55 * np.clip(kick_env, 0, 1)
padL *= duck
padR *= duck
lead *= duck

ir_t = t_axis(2.4)
irL = fft_filter(rng.standard_normal(len(ir_t)), hi=6000) * np.exp(-ir_t / 0.55)
irR = fft_filter(rng.standard_normal(len(ir_t)), hi=6000) * np.exp(-ir_t / 0.55)
irL /= np.sqrt(np.sum(irL ** 2))
irR /= np.sqrt(np.sum(irR ** 2))

send = fft_filter(drums, lo=800) * 0.35 + lead * 0.8 + fx * 0.25
revL, revR = convolve(send, irL) * 0.35, convolve(send, irR) * 0.35

lead_L, lead_R = lead * 0.75, lead * 1.0
L = drums + bass + padL + lead_L + fx + hatsL + revL
R = drums + bass + padR + lead_R + fx + hatsR + revR

# pre-drop gap: hard mute 3.75-4.0 except the riser tail
gap = np.ones(N)
gap[int(3.78 * SR):int(4.0 * SR)] = 0.0
L *= gap
R *= gap

# master: low-cut rumble, soft clip, normalize, fade
L, R = fft_filter(L, lo=25), fft_filter(R, lo=25)
L, R = np.tanh(1.25 * L), np.tanh(1.25 * R)
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 0.8, R / peak * 0.8
fade_out = np.interp(tt, [0, 32.5, 34], [1, 1, 0])
L, R = L * fade_out, R * fade_out

os.makedirs(os.path.join(ROOT, "output", "audio"), exist_ok=True)
pcm = (np.stack([L, R], axis=1) * 32767).astype("<i2")
with wave.open(os.path.join(ROOT, "output", "audio", "track.wav"), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())

with open(os.path.join(ROOT, "src", "beats.json"), "w") as fh:
    json.dump({"bpm": BPM, "length": LENGTH, **hits}, fh)

rms = np.sqrt(np.mean(L ** 2))
print(f"wrote track.wav  peak={max(np.abs(L).max(), np.abs(R).max()):.3f}  rms={20*np.log10(rms):.1f} dBFS")
