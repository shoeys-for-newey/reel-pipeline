"""Shake score: RMS of per-frame global-translation residual after removing
a 0.5 s moving-average (intended motion). Higher = shakier. 30 fps, 480px gray."""
import subprocess, sys
import numpy as np

def frames(path, t0, dur, w=480, h=270, fps=30):
    cmd = ["ffmpeg", "-v", "error", "-ss", str(t0), "-t", str(dur), "-i", path,
           "-vf", f"fps={fps},scale={w}:{h}", "-f", "rawvideo", "-pix_fmt", "gray", "-"]
    raw = subprocess.run(cmd, capture_output=True).stdout
    n = len(raw) // (w * h)
    return np.frombuffer(raw[: n * w * h], np.uint8).reshape(n, h, w).astype(np.float32)

def phase_shift(a, b):
    A = np.fft.rfft2(a); B = np.fft.rfft2(b)
    R = A * np.conj(B); R /= np.abs(R) + 1e-9
    c = np.fft.irfft2(R, a.shape)
    iy, ix = np.unravel_index(np.argmax(c), c.shape)
    if iy > a.shape[0] // 2: iy -= a.shape[0]
    if ix > a.shape[1] // 2: ix -= a.shape[1]
    return ix, iy

def score(path, t0, dur):
    f = frames(path, t0, dur)
    if len(f) < 20: return None
    win = np.outer(np.hanning(f.shape[1]), np.hanning(f.shape[2]))
    sh = np.array([phase_shift(f[i] * win, f[i + 1] * win) for i in range(len(f) - 1)], np.float32)
    k = 15  # 0.5 s at 30 fps
    kern = np.ones(k) / k
    res = sh - np.stack([np.convolve(sh[:, 0], kern, "same"), np.convolve(sh[:, 1], kern, "same")], 1)
    res = res[k:-k] if len(res) > 2 * k else res
    return float(np.sqrt((res ** 2).sum(1).mean()))

for spec in sys.argv[1:]:
    name, path, t0, dur = spec.split("::")
    s = score(path, float(t0), float(dur))
    print(f"{name}: shake_rms {s:.2f} px")
