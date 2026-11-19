"""Generates Bloom Desk's calm background sounds (no recordings, no licenses).

    python tool/make_sounds.py

Writes seamless 40-second mono loops to assets/sounds/:
  rain.wav   soft rain: filtered noise with gentle drops
  waves.wav  sea waves: noise that rises and falls slowly
  deep.wav   deep calm: low brown noise
The end of each loop is crossfaded into its start, so it repeats without a click.
"""

import math
import os
import random
import struct
import wave

RATE = 22050
SECONDS = 40
FADE = 2 * RATE  # 2 s crossfade for a seamless loop
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sounds")


def white(n, seed):
    rnd = random.Random(seed)
    return [rnd.uniform(-1, 1) for _ in range(n)]


def lowpass(xs, a):
    out, y = [], 0.0
    for x in xs:
        y += a * (x - y)
        out.append(y)
    return out


def brown(n, seed):
    rnd = random.Random(seed)
    out, y = [], 0.0
    for _ in range(n):
        y = (y + rnd.uniform(-1, 1) * 0.02) * 0.998
        out.append(y)
    return out


def normalize(xs, peak=0.6):
    m = max(abs(x) for x in xs) or 1.0
    return [x / m * peak for x in xs]


def loop(xs):
    # take FADE extra samples and blend them into the start
    body, tail = xs[:-FADE], xs[-FADE:]
    for i in range(FADE):
        t = i / FADE
        body[i] = body[i] * t + tail[i] * (1 - t)
    return body


def write(name, xs):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in xs))
    print(f"{path}  {os.path.getsize(path) // 1024} KB")


n = RATE * SECONDS + FADE

# Rain: soft hiss + random drops
hiss = lowpass(white(n, 1), 0.35)
rnd = random.Random(2)
drops = [0.0] * n
for _ in range(SECONDS * 18):
    at, amp = rnd.randrange(n - 600), rnd.uniform(0.2, 0.9)
    for k in range(600):
        drops[at + k] += amp * math.exp(-k / 70) * rnd.uniform(-1, 1)
rain = [h * 0.7 + d * 0.25 for h, d in zip(hiss, lowpass(drops, 0.5))]
write("rain.wav", loop(normalize(rain, 0.5)))

# Waves: low noise whose loudness rises and falls every ~8 s
surf = lowpass(white(n, 3), 0.08)
waves = [
    s * (0.25 + 0.75 * (0.5 - 0.5 * math.cos(2 * math.pi * i / (RATE * 8)))) ** 2
    for i, s in enumerate(surf)
]
write("waves.wav", loop(normalize(waves, 0.6)))

# Deep calm: brown noise
write("deep.wav", loop(normalize(lowpass(brown(n, 4), 0.3), 0.6)))
