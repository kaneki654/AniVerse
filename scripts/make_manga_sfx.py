"""Render the manga UI's sound effects (aniverse_mobile/lib/ui_manga).

Paper and ink instead of a sound chip: taps on paper, brush swishes, page
turns, a speech bubble's pop and the heavy "DON" of an impact panel -- noise
shaped by sweeping band-pass filters and smooth decays, with low sine thuds
under the hits. Same names as the pixel set (scripts/make_sfx.py), so a screen
asks for "select" either way, plus page, pop and don.

    python3 scripts/make_manga_sfx.py

Writes aniverse_mobile/android/app/src/main/res/raw/manga_<name>.wav; the app
plays them through Android's SoundPool (MainActivity.kt).
"""
import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "aniverse_mobile", "android", "app", "src", "main", "res", "raw")


def _put(buf, j, v):
    while len(buf) <= j:
        buf.append(0.0)
    buf[j] += v


def rustle(buf, rng, *, at=0.0, dur=0.1, f0=2000.0, f1=None, q=1.2, gain=1.0, attack=0.004):
    """Noise through a band-pass sweeping from f0 to f1: paper, brush, air."""
    f1 = f1 or f0
    start, n = int(at * RATE), int(dur * RATE)
    low = band = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        a = 2 * math.sin(math.pi * min(f, RATE / 4) / RATE)  # state-variable filter
        x = rng.uniform(-1, 1)
        high = x - low - band / q
        band += a * high
        low += a * band
        env = min(1.0, t / attack) * math.exp(-4.5 * t / dur)
        _put(buf, start + i, band * env * 0.5 * gain)


def thud(buf, *, at=0.0, dur=0.2, f0=120.0, f1=45.0, gain=1.0):
    """A sine dropping in pitch: the weight under an impact."""
    start, n = int(at * RATE), int(dur * RATE)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / 0.003) * math.exp(-5 * t / dur)
        _put(buf, start + i, math.sin(phase) * env * 0.8 * gain)


def ping(buf, *, at=0.0, dur=0.3, f=1200.0, gain=1.0):
    """A soft bell partial, for the bright moments (achievements)."""
    start, n = int(at * RATE), int(dur * RATE)
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / 0.002) * math.exp(-6 * t / dur)
        s = math.sin(2 * math.pi * f * t) + 0.35 * math.sin(2 * math.pi * f * 2.76 * t)
        _put(buf, start + i, s * env * 0.25 * gain)


def render(name, recipe):
    buf: list = []
    rng = random.Random("manga-" + name)
    recipe(buf, rng)
    buf.extend([0.0] * int(0.02 * RATE))
    peak = max(1e-9, max(abs(s) for s in buf))
    scale = min(4.0, 0.95 / peak)
    path = os.path.join(OUT, f"manga_{name}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32000)) for s in buf))
    return path, len(buf) / RATE


def _page(b, r, at=0.0):
    rustle(b, r, at=at, dur=0.16, f0=900, f1=4200, q=0.9, gain=0.8)        # the sheet lifting
    rustle(b, r, at=at + 0.13, dur=0.12, f0=5200, f1=1400, q=1.4, gain=0.9)  # and settling
    thud(b, at=at + 0.2, dur=0.06, f0=180, f1=90, gain=0.25)


SOUNDS = {
    "click": lambda b, r: (rustle(b, r, dur=0.035, f0=3500, q=2.5, gain=0.9), thud(b, dur=0.03, f0=260, f1=180, gain=0.3)),
    "select": lambda b, r: rustle(b, r, dur=0.11, f0=1200, f1=5200, q=1.8),
    "splat": lambda b, r: (rustle(b, r, dur=0.18, f0=2600, f1=500, q=0.8), thud(b, dur=0.16, f0=140, f1=50, gain=0.7)),
    "slash": lambda b, r: rustle(b, r, dur=0.14, f0=7000, f1=900, q=3.0, gain=1.1),
    "start": lambda b, r: _page(b, r),
    "skip": lambda b, r: (rustle(b, r, dur=0.09, f0=800, f1=6000, q=2.2), rustle(b, r, at=0.07, dur=0.09, f0=900, f1=6500, q=2.2)),
    "error": lambda b, r: (thud(b, dur=0.12, f0=150, f1=110, gain=0.8), thud(b, at=0.14, dur=0.2, f0=110, f1=70, gain=0.8)),
    "achieve": lambda b, r: (thud(b, dur=0.25, f0=110, f1=40), rustle(b, r, dur=0.2, f0=3000, f1=600, q=0.7, gain=0.6),
                             ping(b, at=0.12, f=1319), ping(b, at=0.24, f=1760), ping(b, at=0.36, dur=0.5, f=2093)),
    "hit": lambda b, r: (thud(b, dur=0.12, f0=160, f1=60), rustle(b, r, dur=0.06, f0=4000, f1=1200, q=1.0, gain=0.6)),
    "boss": lambda b, r: (thud(b, dur=0.6, f0=70, f1=32, gain=1.2), rustle(b, r, dur=0.5, f0=400, f1=150, q=0.7, gain=0.8)),
    "page": lambda b, r: _page(b, r),
    "pop": lambda b, r: (thud(b, dur=0.05, f0=520, f1=900, gain=0.5), rustle(b, r, dur=0.03, f0=4000, q=3, gain=0.4)),
    "don": lambda b, r: (thud(b, dur=0.7, f0=90, f1=30, gain=1.3), rustle(b, r, dur=0.35, f0=1800, f1=200, q=0.6),
                         thud(b, at=0.01, dur=0.08, f0=400, f1=120, gain=0.5)),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, recipe in SOUNDS.items():
        path, secs = render(name, recipe)
        print(f"{os.path.relpath(path, ROOT)}  {secs:.2f}s  {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    main()
