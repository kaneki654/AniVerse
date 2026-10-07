"""Render the 8-bit sound effects for the Android app.

The website synthesises these live with WebAudio (app/static/pixel/js/sfx.js);
the app plays the same sounds from small WAV files through Android's SoundPool.
This renders each one from the same recipe -- square/triangle/saw voices with a
stepped decay, and filtered noise bursts -- so the two sound alike.

    python3 scripts/make_sfx.py

Writes aniverse_mobile/android/app/src/main/res/raw/sfx_<name>.wav. Change a
recipe here and in sfx.js together.
"""
import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "aniverse_mobile", "android", "app", "src", "main", "res", "raw")


def steps(t: float, dur: float, levels) -> float:
    """Stepped decay: hold each level for a third of the sound, like a sound chip."""
    i = min(len(levels) - 1, int(3 * t / dur)) if dur > 0 else len(levels) - 1
    return levels[i]


def tone(buf, *, type_="square", f0, f1=None, at=0.0, dur=0.08, gain=1.0):
    f1 = f1 or f0
    start = int(at * RATE)
    n = int(dur * RATE)
    phase = 0.0
    for i in range(n):
        t = i / RATE
        # Exponential sweep from f0 to f1, as exponentialRampToValueAtTime does.
        f = f0 * (f1 / f0) ** (t / dur) if f1 != f0 else f0
        phase = (phase + f / RATE) % 1.0
        if type_ == "square":
            s = 1.0 if phase < 0.5 else -1.0
        elif type_ == "triangle":
            s = 4 * abs(phase - 0.5) - 1
        else:  # sawtooth
            s = 2 * phase - 1
        v = 0.22 * gain * steps(t, dur, (1, 0.6, 0.3, 0))
        j = start + i
        while len(buf) <= j:
            buf.append(0.0)
        buf[j] += s * v


def burst(buf, rng, *, at=0.0, dur=0.12, cutoff=1800.0, gain=1.0):
    start = int(at * RATE)
    n = int(dur * RATE)
    y = 0.0
    for i in range(n):
        t = i / RATE
        fc = cutoff * (200 / cutoff) ** (t / dur)  # the low-pass closes down to 200 Hz
        a = 1 - math.exp(-2 * math.pi * fc / RATE)
        y += a * (rng.uniform(-1, 1) - y)
        v = 0.35 * gain * steps(t, dur, (1, 0.5, 0.2, 0))
        j = start + i
        while len(buf) <= j:
            buf.append(0.0)
        buf[j] += y * v


def render(name, recipe):
    buf: list = []
    rng = random.Random(name)
    recipe(buf, rng)
    buf.extend([0.0] * int(0.02 * RATE))
    peak = max(1e-9, max(abs(s) for s in buf))
    scale = min(1.0, 0.95 / peak)  # full level here; the app sets the volume
    path = os.path.join(OUT, f"sfx_{name}.wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32000)) for s in buf))
    return path, len(buf) / RATE


SOUNDS = {
    "click": lambda b, r: tone(b, f0=880, dur=0.04, gain=0.6),
    "select": lambda b, r: (tone(b, f0=660, dur=0.05), tone(b, f0=990, at=0.05, dur=0.06)),
    "splat": lambda b, r: (burst(b, r, dur=0.16, cutoff=2400), tone(b, type_="triangle", f0=220, f1=70, dur=0.14, gain=0.8)),
    "slash": lambda b, r: (burst(b, r, dur=0.09, cutoff=6000, gain=0.7), tone(b, f0=1400, f1=300, dur=0.09, gain=0.5)),
    "start": lambda b, r: [tone(b, f0=f, at=i * 0.07, dur=0.07) for i, f in enumerate((523, 659, 784, 1047))],
    "skip": lambda b, r: tone(b, f0=440, f1=1320, dur=0.12),
    "error": lambda b, r: (tone(b, f0=196, dur=0.12), tone(b, f0=147, at=0.13, dur=0.22)),
    "achieve": lambda b, r: [tone(b, f0=f, at=i * 0.08, dur=0.09) for i, f in enumerate((784, 988, 1175, 1568, 1319, 1568))],
    "hit": lambda b, r: (burst(b, r, dur=0.07, cutoff=3200), tone(b, f0=330, f1=110, dur=0.07, gain=0.7)),
    "boss": lambda b, r: [tone(b, type_="sawtooth", f0=f, at=i * 0.11, dur=0.12, gain=0.7) for i, f in enumerate((392, 311, 262, 196))],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, recipe in SOUNDS.items():
        path, secs = render(name, recipe)
        print(f"{os.path.relpath(path, ROOT)}  {secs:.2f}s  {os.path.getsize(path)} bytes")


if __name__ == "__main__":
    main()
