"""映像に付ける音を numpy だけで合成する部品（楽器・効果音・仕上げ）。作品ごとの <作品>_audio.py から
`from synth import *` で使い、place(bus, 音, 時刻, 大きさ, 左右) で並べて、最後に master() で書き出す。
乱数（rng）は読み込んだときに一度だけ作り、呼んだ順に使うので、同じ順に呼べば毎回同じ音になる。

  リズム   kick snare hat(open_) crash thump taiko
  音程     saw（倍音を足すのこぎり波）brass bass_note pad chime
  効果音   whoosh pop boing slide_whistle growl breath gaan riser ticks sparkle_run
  仕上げ   reverb limiter tone_shape master
"""
import math
import os

import numpy as np

SR = 48000
rng = np.random.default_rng(23)
NOTE = {n: 440.0 * 2 ** ((i - 57) / 12) for i, n in enumerate(
    [f"{p}{o}" for o in range(0, 9) for p in ("C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B")])}


# ================================================================ 道具
def tt(length):
    return np.arange(int(length * SR)) / SR


def smooth(x):
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)


def spectral(x, lo=None, hi=None, slope=1.0):
    """FFT で帯域を切る（なだらかな肩）。"""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (4 * slope))
    if hi:
        g *= 1 / (1 + (f / hi) ** (4 * slope))
    return np.fft.irfft(X * g, len(x))


def noise(length, lo=None, hi=None):
    x = spectral(rng.standard_normal(int(length * SR)), lo, hi)
    return x / (np.sqrt((x ** 2).mean()) + 1e-12)


def norm(x):
    return x / (np.abs(x).max() + 1e-12)


def fade_in(x, sec=0.003):
    k = min(len(x), int(sec * SR))
    x[:k] *= np.linspace(0, 1, k)
    return x


def pan_gains(p):
    th = (np.clip(p, -1, 1) * 0.7 + 1) * math.pi / 4
    return math.cos(th), math.sin(th)


def place(bus, sig, t, gain=1.0, pan=0.0):
    n = bus.shape[0]
    i = int(round(t * SR))
    if i >= n or i + len(sig) <= 0:
        return
    if i < 0:
        sig, i = sig[-i:], 0
    sig = sig[: n - i]
    gl, gr = pan_gains(pan)
    bus[i:i + len(sig), 0] += sig * gain * gl
    bus[i:i + len(sig), 1] += sig * gain * gr


def saw(freq, length, cutoff, detune=(0.0,), phase_rng=True):
    """帯域を制限したのこぎり波（倍音を足し合わせる）。cutoff は時間とともに変わってよい（配列）。"""
    t = tt(length)
    out = np.zeros(len(t))
    fc = np.broadcast_to(np.asarray(cutoff, dtype=float), t.shape)
    for dc in detune:
        f = freq * 2 ** (dc / 1200)
        ph0 = rng.uniform(0, 2 * math.pi) if phase_rng else 0.0
        for k in range(1, int(16000 / f) + 1):
            amp = (1 / k) / np.sqrt(1 + (k * f / fc) ** 4)
            if amp.max() < 2e-4:
                break
            out += amp * np.sin(2 * math.pi * k * f * t + k * ph0)
    return out / len(detune)


# ================================================================ 楽器
def kick(length=0.45, f0=165, f1=54):
    t = tt(length)
    f = f1 + (f0 - f1) * np.exp(-t / 0.03)
    body = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.13)
    click = noise(length, 1500, 8000) * np.exp(-t / 0.003) * 0.25
    return fade_in(norm(body + click), 0.001)


def snare(length=0.32):
    t = tt(length)
    tone = 0.55 * np.sin(2 * math.pi * 188 * t) * np.exp(-t / 0.05) + 0.25 * np.sin(2 * math.pi * 330 * t) * np.exp(-t / 0.03)
    nz = noise(length, 1400, 9000) * np.exp(-t / 0.1) * 0.35
    return fade_in(norm(tone + nz), 0.001)


def hat(open_=False):
    length = 0.35 if open_ else 0.08
    t = tt(length)
    x = noise(length, 7000, 14000) * np.exp(-t / (0.12 if open_ else 0.022))
    return fade_in(norm(x), 0.0005)


def crash(length=2.4, bright=1.0):
    t = tt(length)
    x = noise(length, 3200, 11000 * bright) * np.exp(-t / 0.8)
    for f in rng.uniform(3000, 7000, 9):
        x += 0.15 * np.sin(2 * math.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / 0.5)
    return fade_in(norm(x), 0.002)


def thump(f0=120, f1=62, length=0.4, decay=0.14, noise_amt=0.3):
    """叩きつける「ドン」。"""
    t = tt(length)
    f = f1 + (f0 - f1) * np.exp(-t / 0.04)
    body = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    hit = noise(length, 200, 3000) * np.exp(-t / 0.012) * noise_amt
    return fade_in(norm(body + hit), 0.001)


def taiko():
    t = tt(1.2)
    f = 62 + 40 * np.exp(-t / 0.05)
    body = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.42)
    skin = noise(1.2, 80, 900) * np.exp(-t / 0.06) * 0.5
    return fade_in(norm(body + skin), 0.001)


def brass(freqs, length, bright=1.0, attack=0.012, release=0.12):
    """シンセのブラスの「ジャッ」。フィルターが開いてから閉じていく。"""
    t = tt(length)
    fc = (900 + 3200 * bright * np.exp(-t / 0.09)) * (1 + 0.1 * np.sin(2 * math.pi * 5.5 * t) * smooth(t / 0.3))
    out = sum(saw(f, length, fc, detune=(-9, 0, 8)) for f in freqs)
    env = smooth(t / attack) * (0.72 + 0.28 * np.exp(-t / 0.08)) * (1 - smooth((t - (length - release)) / release))
    return norm(out * env)


def bass_note(f, length=0.19):
    t = tt(length)
    fc = 350 + 900 * np.exp(-t / 0.05)
    x = saw(f, length, fc, detune=(-4, 4)) + 0.5 * np.sin(2 * math.pi * f * t)
    env = smooth(t / 0.004) * np.exp(-t / 0.22) * (1 - smooth((t - (length - 0.03)) / 0.03))
    return norm(x * env)


def pad(freqs, length, cutoff=1400):
    t = tt(length)
    out = sum(saw(f, length, cutoff, detune=(-12, 0, 11)) for f in freqs)
    env = smooth(t / 0.25) * (1 - smooth((t - (length - 0.4)) / 0.4))
    return norm(out * env)


def whoosh(length, f0, f1, bands=14):
    m = int(length * SR)
    t = np.arange(m) / m
    fc = f0 * (f1 / f0) ** smooth(t)
    out = np.zeros(m)
    for f in np.geomspace(120, 7000, bands):
        g = np.exp(-0.5 * (np.log(f / fc) / 0.45) ** 2)
        out += g * noise(length, f / 1.25, f * 1.25)[:m]
    env = np.sin(np.pi * t) ** 2
    return norm(out * env)


def pop(f_lo=260, f_hi=1020, length=0.14):
    t = tt(length)
    f = f_lo + (f_hi - f_lo) * (1 - np.exp(-t / 0.018))
    s = np.sin(2 * math.pi * np.cumsum(f) / SR) * np.exp(-t / 0.035)
    return fade_in(norm(s), 0.001)


def chime(f, length=1.6):
    t = tt(length)
    parts = [(1.0, 1.0, 1.0), (2.0, 0.3, 0.5), (3.01, 0.12, 0.3), (4.18, 0.06, 0.2)]
    s = sum(a * np.exp(-t / tau) * np.sin(2 * math.pi * f * r * t) for r, a, tau in parts)
    return fade_in(norm(s), 0.003)


def boing(f0=240, f1=620, length=0.45):
    """💢 の「びよーん」。"""
    t = tt(length)
    f = f0 + (f1 - f0) * (1 - np.exp(-t / 0.06)) + 60 * np.sin(2 * math.pi * 17 * t) * np.exp(-t / 0.18)
    s = np.sin(2 * math.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * math.pi * np.cumsum(f) / SR)
    return fade_in(norm(s * np.exp(-t / 0.16)), 0.002)


def slide_whistle(f0, f1, length):
    t = tt(length)
    u = smooth(t / length)
    f = f0 * (f1 / f0) ** u * (1 + 0.012 * np.sin(2 * math.pi * 6 * t))
    s = np.sin(2 * math.pi * np.cumsum(f) / SR) + 0.08 * noise(length, 1500, 5000)
    env = smooth(t / 0.04) * (1 - smooth((t - length + 0.12) / 0.12))
    return norm(s * env)


def growl(length=0.7):
    """お腹の「グゥ〜」: 低い雑音をゆらして、うなりの音程を下げる。"""
    t = tt(length)
    f = 95 - 35 * t / length
    lfo = 0.5 + 0.5 * np.sin(2 * math.pi * (7 + 5 * t) * t) ** 2
    tone = np.sin(2 * math.pi * np.cumsum(f) / SR) + 0.6 * np.sin(2 * math.pi * np.cumsum(2.02 * f) / SR)
    rumble = noise(length, 60, 320) * 0.8
    env = smooth(t / 0.08) * (1 - smooth((t - length + 0.25) / 0.25))
    return norm((tone + rumble) * lfo * env)


def breath(length=0.9):
    """ため息: 息の音（声のこもった帯域が下がっていく）。"""
    t = tt(length)
    x = rng.standard_normal(len(t))
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.exp(-0.5 * (np.log(np.maximum(f, 1) / 900) / 0.6) ** 2) + 0.5 * np.exp(-0.5 * (np.log(np.maximum(f, 1) / 2400) / 0.5) ** 2)
    y = np.fft.irfft(X * g, len(x))
    env = smooth(t / 0.12) * np.exp(-np.maximum(t - 0.2, 0) / 0.3)
    lp = spectral(y * env, 150, 5000)
    return norm(lp)


def gaan():
    """「ガーン」: 低い音を重ねた不協和音。"""
    t = tt(2.2)
    out = np.zeros(len(t))
    for n in ("C2", "C#2", "F#2", "C3", "C#3"):
        f = NOTE[n]
        for k, a in ((1, 1.0), (2, 0.5), (3, 0.3), (4.02, 0.15), (5.05, 0.08)):
            out += a * np.sin(2 * math.pi * f * k * t) * np.exp(-t / (0.9 / k ** 0.5))
    return fade_in(norm(out), 0.002)


def riser(length):
    t = tt(length)
    u = t / length
    fc = 300 * (6000 / 300) ** u
    x = np.zeros(len(t))
    for f in np.geomspace(200, 8000, 12):
        x += np.exp(-0.5 * (np.log(f / fc) / 0.4) ** 2) * noise(length, f / 1.3, f * 1.3)
    tone = np.sin(2 * math.pi * np.cumsum(200 * (4 ** u)) / SR) * 0.25
    return norm((x + tone) * u ** 2)


def ticks(t0, t1, rate0, rate1):
    """距離計のカチカチ（だんだんゆっくり）。"""
    out, times, t = [], [], t0
    while t < t1:
        times.append(t)
        u = (t - t0) / (t1 - t0)
        t += 1 / (rate0 + (rate1 - rate0) * u)
    click = noise(0.01, 2000, 8000) * np.exp(-tt(0.01) / 0.0015)
    return times, norm(click)


def sparkle_run(notes, gap=0.045):
    out = np.zeros(int((gap * len(notes) + 1.2) * SR))
    for i, n in enumerate(notes):
        c = chime(NOTE[n], 1.0)
        k = int(i * gap * SR)
        out[k:k + len(c)] += c * (0.6 + 0.4 * i / len(notes))
    return norm(out)


# ================================================================ 仕上げ
def reverb(x, length=1.6, decay=0.45):
    t = tt(length)
    out = np.zeros_like(x)
    for ch in range(2):
        ir = rng.standard_normal(len(t)) * np.exp(-t / decay)
        ir = spectral(ir, 200, 6000)
        ir[: int(0.012 * SR)] = 0
        ir /= np.sqrt((ir ** 2).sum())
        m = len(x) + len(ir)
        size = 1 << (m - 1).bit_length()
        out[:, ch] = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(ir, size), size)[: len(x)]
    return out


def limiter(x, ceiling, look=0.002, release=0.08):
    a = np.abs(x).max(axis=1)
    w = int(look * SR)
    ahead = np.lib.stride_tricks.sliding_window_view(np.pad(a, (0, w)), w + 1).max(axis=1)
    target = np.minimum(1.0, ceiling / np.maximum(ahead, 1e-9))
    g = np.empty_like(target)
    rel = 1 - math.exp(-1 / (release * SR))
    cur = 1.0
    for i, tg in enumerate(target):
        cur = tg if tg < cur else cur + (tg - cur) * rel
        g[i] = cur
    g = np.convolve(g, np.ones(w) / w, mode="same")
    return x * np.minimum(g, target)[:, None]


def tone_shape(x):
    """重低音を抑え（70 Hz 以下を約 −4 dB、35 Hz 以下は切る）、3.5 kHz あたりの抜けを +3 dB。"""
    X = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / SR), 1e-3)
    g = 1 / (1 + (35 / f) ** 6) * (1 - 0.4 / (1 + (f / 70) ** 4))
    g *= (1 + 0.41 * np.exp(-0.5 * (np.log2(f / 3500) / 0.8) ** 2)) / (1 + (f / 16000) ** 2)
    return np.fft.irfft(X * g, len(x))


def master(mix, path, rms_db=-16.0, ceiling_db=-1.0, fade_sec=0.03):
    """重低音を抑えて抜けを足し（tone_shape）、平均の音量をそろえ、ピークをリミッターで抑えて 16 bit の WAV に書く。"""
    import wave
    mix = np.stack([tone_shape(mix[:, ch]) for ch in range(2)], axis=1)
    mix *= 10 ** (rms_db / 20) / np.sqrt((mix ** 2).mean())
    mix = limiter(mix, 10 ** (ceiling_db / 20))
    k = int(fade_sec * SR)
    mix[-k:] *= np.linspace(1, 0, k)[:, None]
    pcm = np.clip(np.round(mix * 32767 + rng.uniform(-0.5, 0.5, mix.shape)), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    rms = 20 * math.log10(np.sqrt((mix ** 2).mean()))
    print(f"wrote {os.path.basename(path)} rms {rms:.1f} dBFS peak {20 * math.log10(np.abs(mix).max()):.1f} dBFS")
    return mix
