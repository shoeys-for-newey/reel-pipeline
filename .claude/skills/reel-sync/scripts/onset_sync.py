#!/usr/bin/env python3
"""onset_sync.py - offset via onset-train correlation on prefiltered 8kHz mono WAVs.
Emphasizes sharp transients (arm beep, throttle punch) over smooth wind envelope.
Usage: onset_sync.py REF.wav OTHER.wav [--maxlag 150]
Same sign convention as sync.py: offset_s > 0 means OTHER starts after REF.
"""
import argparse, json
import numpy as np
import wave


def load_wav(path):
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
    return data, rate


def onset_series(data, rate, hop_hz=8):
    hop = rate // hop_hz
    n = len(data) // hop
    rms = np.sqrt(np.mean(data[: n * hop].reshape(n, hop) ** 2, axis=1) + 1e-9)
    logrms = np.log(rms + 1e-6)
    d = np.diff(logrms)
    d[d < 0] = 0  # onsets only
    # soft-clip so one giant transient can't dominate
    d = np.tanh(d * 4)
    return d - d.mean()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("other")
    ap.add_argument("--maxlag", type=float, default=150)
    ap.add_argument("--hop", type=int, default=8)
    args = ap.parse_args()
    da, ra = load_wav(args.ref)
    db, rb = load_wav(args.other)
    a = onset_series(da, ra, args.hop)
    b = onset_series(db, rb, args.hop)
    n = len(a) + len(b) - 1
    nfft = 1 << (n - 1).bit_length()
    cc = np.fft.irfft(np.fft.rfft(a, nfft) * np.conj(np.fft.rfft(b, nfft)), nfft)
    cc = np.concatenate((cc[-(len(b) - 1):], cc[: len(a)]))
    lags = np.arange(-(len(b) - 1), len(a)) / args.hop
    mask = np.abs(lags) <= args.maxlag
    ccm, lagm = cc[mask], lags[mask]
    order = np.argsort(ccm)[::-1]
    peaks = []
    for i in order:
        t = float(lagm[i])
        if all(abs(t - p[0]) > 2.0 for p in peaks):
            peaks.append((t, float(ccm[i])))
        if len(peaks) >= 3:
            break
    ref_level = float(np.abs(ccm[np.argsort(np.abs(ccm))[-max(10, len(ccm) // 100):]]).mean())
    print(json.dumps({
        "ref": args.ref, "other": args.other,
        "offset_s": round(peaks[0][0], 3),
        "confidence": round(peaks[0][1] / (ref_level + 1e-9), 2),
        "top3": [[round(t, 2), round(v, 1)] for t, v in peaks],
    }))


if __name__ == "__main__":
    main()
