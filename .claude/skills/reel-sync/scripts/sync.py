#!/usr/bin/env python3
"""sync.py — find the time offset between two recordings by audio cross-correlation.

Usage:
  sync.py REF OTHER [--window 120] [--rate 8000]

Prints JSON: {"offset_s": X, "confidence": C, "ref": ..., "other": ...}
  offset_s > 0  means OTHER starts X seconds AFTER REF (OTHER's t=0 is REF's t=X).
  To cut the same moment from both: ref --start S, other --start S - offset_s.

confidence = peak / (mean of top-1% excluding peak); > 3 is a clean lock, < 1.5 is a guess.
Needs ffmpeg on PATH and numpy.
"""
import argparse, json, subprocess, sys, tempfile, os
import numpy as np


def load_mono(path, rate, window):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as t:
        wav = t.name
    cmd = ["ffmpeg", "-v", "error", "-y", "-t", str(window), "-i", path,
           "-vn", "-ac", "1", "-ar", str(rate), "-f", "wav", wav]
    subprocess.run(cmd, check=True)
    data = np.memmap(wav, dtype=np.int16, mode="r", offset=44).astype(np.float32)
    os.unlink(wav)
    data -= data.mean()
    env = np.abs(data)
    # envelope, 20 ms smoothing: robust to codec differences between cameras
    k = max(1, rate // 50)
    env = np.convolve(env, np.ones(k) / k, mode="same")
    env -= env.mean()
    return env


def xcorr_offset(a, b, rate):
    n = len(a) + len(b) - 1
    nfft = 1 << (n - 1).bit_length()
    A = np.fft.rfft(a, nfft)
    B = np.fft.rfft(b, nfft)
    cc = np.fft.irfft(A * np.conj(B), nfft)
    cc = np.concatenate((cc[-(len(b) - 1):], cc[:len(a)]))  # lags -(len(b)-1) .. len(a)-1
    lags = np.arange(-(len(b) - 1), len(a))
    i = int(np.argmax(cc))
    peak = cc[i]
    top = np.sort(cc)[-max(10, len(cc) // 100):-1]
    conf = float(peak / (np.abs(top).mean() + 1e-9))
    return float(lags[i] / rate), conf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("other")
    ap.add_argument("--window", type=float, default=120, help="seconds of audio to compare")
    ap.add_argument("--rate", type=int, default=8000)
    args = ap.parse_args()
    a = load_mono(args.ref, args.rate, args.window)
    b = load_mono(args.other, args.rate, args.window)
    off, conf = xcorr_offset(a, b, args.rate)
    # cc lag > 0 means b is delayed relative to a, i.e. other starts after ref
    print(json.dumps({"ref": args.ref, "other": args.other,
                      "offset_s": round(off, 3), "confidence": round(conf, 2)}))


if __name__ == "__main__":
    main()
