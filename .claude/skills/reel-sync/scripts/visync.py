#!/usr/bin/env python3
"""visync.py - offset between two recordings of the SAME flight (e.g. onboard HD vs goggle DVR)
by cross-correlating per-frame video motion energy (signalstats YDIF). Works when audio sync
fails, because both cameras ride the same airframe and see identical motion patterns.

Usage: visync.py REF OTHER [--fps 5]
Prints JSON like sync.py: offset_s > 0 means OTHER starts after REF.
"""
import argparse, json, re, subprocess
import numpy as np


def motion_series(path, fps):
    vf = (f"fps={fps},scale=240:-2,signalstats,"
          "metadata=print:key=lavfi.signalstats.YDIF:file=-")
    cmd = ["ffmpeg", "-v", "info", "-nostats", "-i", path, "-an", "-vf", vf, "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    vals = []
    for line in out.splitlines():
        m = re.match(r"lavfi\.signalstats\.YDIF=([\d.\-]+)", line)
        if m:
            vals.append(float(m.group(1)))
    return np.array(vals, dtype=np.float32)


def xcorr(a, b, fps):
    a = a - a.mean()
    b = b - b.mean()
    n = len(a) + len(b) - 1
    nfft = 1 << (n - 1).bit_length()
    cc = np.fft.irfft(np.fft.rfft(a, nfft) * np.conj(np.fft.rfft(b, nfft)), nfft)
    cc = np.concatenate((cc[-(len(b) - 1):], cc[:len(a)]))
    lags = np.arange(-(len(b) - 1), len(a))
    i = int(np.argmax(cc))
    peak = cc[i]
    top = np.sort(cc)[-max(10, len(cc) // 100):-1]
    conf = float(peak / (np.abs(top).mean() + 1e-9))
    return float(lags[i] / fps), conf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("other")
    ap.add_argument("--fps", type=float, default=5)
    args = ap.parse_args()
    a = motion_series(args.ref, args.fps)
    b = motion_series(args.other, args.fps)
    if len(a) < 10 or len(b) < 10:
        raise SystemExit(f"too few frames parsed: ref={len(a)} other={len(b)}")
    off, conf = xcorr(a, b, args.fps)
    print(json.dumps({"ref": args.ref, "other": args.other,
                      "offset_s": round(off, 3), "confidence": round(conf, 2),
                      "frames": [len(a), len(b)]}))


if __name__ == "__main__":
    main()
