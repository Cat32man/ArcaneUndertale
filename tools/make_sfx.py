"""Generates assets/sfx/*.wav - original chiptune-style sound effects (no external assets).

Run:   python tools/make_sfx.py
Edit a recipe below and re-run to retune a sound, or drop your own .wav with the same name into
assets/sfx/ (just don't re-run this script afterwards, or it will overwrite it).

Every recipe returns a float array in [-1, 1] at 22.05 kHz. Needs numpy.
"""
import os
import wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)   # fixed seed: the noise is the same every run


# ------------------------------------------------------------------ building blocks
def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def osc(kind, freq, duty=0.5):
    """freq: scalar or per-sample array (Hz). Returns the raw waveform."""
    n = len(freq) if hasattr(freq, "__len__") else None
    ph = np.cumsum(np.asarray(freq, dtype=float) / SR)
    frac = ph % 1.0
    if kind == "square":
        return np.where(frac < duty, 1.0, -1.0)
    if kind == "saw":
        return 2.0 * frac - 1.0
    if kind == "tri":
        return 4.0 * np.abs(frac - 0.5) - 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * ph)
    raise ValueError(kind)


def sweep(f0, f1, dur, curve=1.0):
    t = np.linspace(0, 1, int(SR * dur)) ** curve
    return f0 + (f1 - f0) * t


def env(n, attack=0.004, power=2.0):
    """quick attack, then a decay to zero over the rest of the sound"""
    x = np.linspace(0, 1, n)
    a = np.minimum(1.0, np.arange(n) / max(1, attack * SR))
    return a * (1.0 - x) ** power


def noise(dur):
    return rng.uniform(-1, 1, int(SR * dur))


def lowpass(x, a):
    out = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += a * (v - acc)
        out[i] = acc
    return out


def highpass(x, a):
    return x - lowpass(x, a)


def mix(*parts):
    n = max(len(p[0]) + int(p[1] * SR) for p in parts)
    out = np.zeros(n)
    for sig, at, vol in parts:
        s = int(at * SR)
        out[s:s + len(sig)] += sig * vol
    return out


def seq(notes, step, wave_kind="square", duty=0.5, power=1.5, vol=1.0):
    """a quick arpeggio / melody: list of Hz, each `step` seconds long"""
    parts = []
    for i, f in enumerate(notes):
        n = int(SR * step)
        sig = osc(wave_kind, np.full(n, f), duty) * env(n, 0.002, power)
        parts.append((sig, i * step, vol))
    return mix(*parts)


# ------------------------------------------------------------------ the sounds
def blip():
    n = int(SR * 0.05)
    return osc("square", np.full(n, 880), 0.5) * env(n, 0.002, 1.5) * 0.5


def select():
    return seq([660, 990], 0.06, "square", 0.5, 1.2, 0.5)


def cancel():
    return seq([440, 330], 0.05, "square", 0.5, 1.2, 0.5)


def text():
    n = int(SR * 0.03)
    return osc("square", np.full(n, 310), 0.25) * env(n, 0.001, 1.0) * 0.45


def bar_stop():
    n = int(SR * 0.05)
    click = osc("square", np.full(n, 1300), 0.5) * env(n, 0.001, 2.0)
    return mix((click, 0, 0.5), (noise(0.03) * env(int(SR * 0.03), 0.001, 2.0), 0, 0.3))


def slash():
    f = lowpass(noise(0.22), 0.5) * env(int(SR * 0.22), 0.02, 1.3)
    s = osc("saw", sweep(1800, 500, 0.22)) * env(int(SR * 0.22), 0.01, 2.0)
    return mix((f, 0, 0.5), (s, 0, 0.18))


def hit():
    t = osc("sine", sweep(180, 55, 0.16, 0.6)) * env(int(SR * 0.16), 0.002, 1.6)
    n = noise(0.1) * env(int(SR * 0.1), 0.001, 2.5)
    return mix((t, 0, 0.9), (n, 0, 0.35))


def crit():
    ding = osc("sine", np.full(int(SR * 0.4), 1760)) * env(int(SR * 0.4), 0.002, 2.2)
    ding2 = osc("sine", np.full(int(SR * 0.4), 2637)) * env(int(SR * 0.4), 0.002, 2.6)
    return mix((hit(), 0, 0.9), (ding, 0.02, 0.35), (ding2, 0.02, 0.2))


def miss():
    f = lowpass(noise(0.18), 0.25) * env(int(SR * 0.18), 0.03, 1.2)
    s = osc("sine", sweep(420, 160, 0.18)) * env(int(SR * 0.18), 0.01, 1.5)
    return mix((f, 0, 0.5), (s, 0, 0.25))


def shock():
    f = lowpass(noise(0.45), 0.2) * env(int(SR * 0.45), 0.08, 1.0)
    s = osc("saw", sweep(180, 1100, 0.45, 1.4)) * env(int(SR * 0.45), 0.05, 1.3)
    return mix((f, 0, 0.5), (s, 0, 0.22))


def cast():
    return seq([523, 659, 784, 1047, 1319], 0.045, "square", 0.25, 1.4, 0.45)


def heal():
    return seq([523, 659, 784, 1047, 1319, 1568], 0.075, "tri", 0.5, 1.2, 0.7)


def hurt():
    s = osc("square", sweep(260, 70, 0.22), 0.5) * env(int(SR * 0.22), 0.002, 1.4)
    n = noise(0.12) * env(int(SR * 0.12), 0.001, 2.0)
    return mix((s, 0, 0.55), (n, 0, 0.4))


def spare():
    parts = []
    for i, f in enumerate([659, 784, 988]):
        n = int(SR * 0.6)
        parts.append((osc("sine", np.full(n, f)) * env(n, 0.01, 1.6), i * 0.09, 0.4))
    return mix(*parts)


def flee():
    return seq([700, 600, 500, 420, 350], 0.04, "square", 0.5, 1.5, 0.45)


def win():
    return seq([523, 659, 784, 1047, 784, 1047, 1319], 0.11, "square", 0.25, 1.1, 0.5)


def lose():
    n = int(SR * 1.0)
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 9 * t_axis(1.0))
    return osc("saw", sweep(440, 90, 1.0, 0.8)) * env(n, 0.01, 0.8) * trem * 0.55


def impact():
    t = osc("sine", sweep(110, 35, 0.4, 0.5)) * env(int(SR * 0.4), 0.002, 1.8)
    n = lowpass(noise(0.3), 0.15) * env(int(SR * 0.3), 0.001, 2.0)
    return mix((t, 0, 1.0), (n, 0, 0.8))


def thump():
    t = osc("sine", sweep(140, 55, 0.14, 0.6)) * env(int(SR * 0.14), 0.002, 1.8)
    return t * 0.9


def throw():
    f = highpass(noise(0.26), 0.2) * env(int(SR * 0.26), 0.08, 1.2)
    s = osc("saw", sweep(500, 1500, 0.26, 1.3)) * env(int(SR * 0.26), 0.04, 1.4)
    return mix((f, 0, 0.35), (s, 0, 0.18))


def stab():
    s = osc("square", sweep(1900, 700, 0.12), 0.25) * env(int(SR * 0.12), 0.001, 1.6)
    n = highpass(noise(0.08), 0.3) * env(int(SR * 0.08), 0.001, 2.0)
    return mix((s, 0, 0.4), (n, 0, 0.4))


def swoosh():
    f = lowpass(noise(0.4), 0.18) * env(int(SR * 0.4), 0.12, 1.0)
    return f * 0.8


def powerup():
    n = int(SR * 0.7)
    trem = 0.8 + 0.2 * np.sin(2 * np.pi * 16 * t_axis(0.7))
    return osc("saw", sweep(180, 1300, 0.7, 1.6)) * env(n, 0.02, 0.7) * trem * 0.5


def flash():
    s = osc("square", sweep(2200, 350, 0.13), 0.25) * env(int(SR * 0.13), 0.001, 1.5)
    n = highpass(noise(0.08), 0.3) * env(int(SR * 0.08), 0.001, 2.0)
    return mix((s, 0, 0.45), (n, 0, 0.3))


def fire():
    f = lowpass(noise(0.32), 0.3) * env(int(SR * 0.32), 0.03, 1.2)
    crack = (rng.uniform(0, 1, int(SR * 0.32)) > 0.985) * noise(0.32) * env(int(SR * 0.32), 0.0, 1.0)
    return mix((f, 0, 0.55), (crack, 0, 0.5))


def pillar():
    s = osc("sine", sweep(280, 900, 0.26, 1.2)) * env(int(SR * 0.26), 0.01, 1.4)
    n = lowpass(noise(0.2), 0.3) * env(int(SR * 0.2), 0.005, 1.5)
    return mix((s, 0, 0.5), (n, 0, 0.35))


def beam():
    n = int(SR * 0.16)
    vib = 1500 + 60 * np.sin(2 * np.pi * 40 * t_axis(0.16))
    return osc("saw", vib) * env(n, 0.003, 1.3) * 0.4


def dash():
    f = highpass(noise(0.2), 0.15) * env(int(SR * 0.2), 0.07, 1.2)
    return f * 0.7


def cut():
    n = int(SR * 0.24)
    ring = osc("sine", sweep(3200, 2100, 0.24)) * env(n, 0.001, 2.2)
    f = highpass(noise(0.24), 0.2) * env(n, 0.001, 2.0)
    return mix((ring, 0, 0.35), (f, 0, 0.5))


def cut_big():
    return mix((cut(), 0, 0.9), (impact(), 0.04, 0.8))


def sever():
    return mix((cut(), 0, 0.8),
               (osc("square", sweep(900, 300, 0.4), 0.5) * env(int(SR * 0.4), 0.01, 1.6), 0.05, 0.25))


def draw():
    n = int(SR * 0.55)
    f = highpass(noise(0.55), 0.12) * env(n, 0.15, 0.9)
    s = osc("saw", sweep(700, 3600, 0.55, 1.5)) * env(n, 0.1, 1.1)
    return mix((f, 0, 0.45), (s, 0, 0.15))


def dim():
    n = int(SR * 0.7)
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * 7 * t_axis(0.7))
    return osc("sine", sweep(90, 55, 0.7)) * env(n, 0.05, 0.9) * trem * 0.9


def boing():
    f = np.concatenate([sweep(200, 520, 0.11), sweep(520, 300, 0.11)])
    return osc("sine", f) * env(len(f), 0.003, 1.3) * 0.6


SOUNDS = {
    "blip": blip, "select": select, "cancel": cancel, "text": text, "bar_stop": bar_stop,
    "slash": slash, "hit": hit, "crit": crit, "miss": miss, "shock": shock, "cast": cast,
    "heal": heal, "hurt": hurt, "spare": spare, "flee": flee, "win": win, "lose": lose,
    "impact": impact, "thump": thump, "throw": throw, "stab": stab, "swoosh": swoosh,
    "powerup": powerup, "flash": flash, "fire": fire, "pillar": pillar, "beam": beam,
    "dash": dash, "cut": cut, "cut_big": cut_big, "sever": sever, "draw": draw, "dim": dim,
    "boing": boing,
}


def write(path, x):
    peak = float(np.max(np.abs(x))) or 1.0
    x = x / peak * 0.85                   # every sound peaks at the same level; the game sets per-use volume
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
    os.makedirs(out, exist_ok=True)
    total = 0
    for name, fn in SOUNDS.items():
        sig = fn()
        write(os.path.join(out, name + ".wav"), sig)
        total += len(sig)
    print("wrote %d sounds to %s (%.1f s of audio, ~%d KB)" % (len(SOUNDS), os.path.normpath(out), total / SR, total * 2 // 1024))
