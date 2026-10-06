"""Refine a DVR<->hero offset by cross-correlating per-frame motion energy (YDIF)
over a short window around a sharp motion event. Usage:
  python lagfit.py HERO T0H DUR DVR T0D DUR2 [--max-lag 3]
Prints the lag of best alignment and the implied true offset (hero_t - dvr_t).
"""
import argparse, json, subprocess, sys, tempfile, os
import numpy as np

def trace(src, t0, dur):
    # relative path: a drive-letter colon inside -vf breaks ffmpeg's option parser
    out = f"work/_ydif_{os.getpid()}_{t0}.txt"
    cmd = ["ffmpeg", "-v", "error", "-y", "-ss", str(t0), "-t", str(dur), "-i", src,
           "-vf", f"scale=160:-1,signalstats,metadata=print:key=lavfi.signalstats.YDIF:file={out}",
           "-f", "null", "-"]
    subprocess.run(cmd, check=True)
    ts, vs = [], []
    t = None
    with open(out) as f:
        for line in f:
            if line.startswith("frame:"):
                for tok in line.split():
                    if tok.startswith("pts_time:"):
                        t = float(tok.split(":", 1)[1])
            elif "YDIF=" in line and t is not None:
                ts.append(t); vs.append(float(line.strip().split("=", 1)[1]))
    os.unlink(out)
    ts, vs = np.array(ts[2:]), np.array(vs[2:])  # drop seek-artifact frames
    return ts, vs

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hero"); ap.add_argument("t0h", type=float); ap.add_argument("durh", type=float)
    ap.add_argument("dvr"); ap.add_argument("t0d", type=float); ap.add_argument("durd", type=float)
    ap.add_argument("--max-lag", type=float, default=3.0)
    a = ap.parse_args()

    th, vh = trace(a.hero, a.t0h, a.durh)
    td, vd = trace(a.dvr, a.t0d, a.durd)
    grid = np.arange(0, max(th[-1], td[-1]), 0.01)
    H = np.interp(grid, th, vh, left=np.nan, right=np.nan)
    best = []
    for L in np.arange(-a.max_lag, a.max_lag + 0.005, 0.01):
        D = np.interp(grid - L, td, vd, left=np.nan, right=np.nan)
        m = ~(np.isnan(H) | np.isnan(D))
        if m.sum() < 200:
            continue
        h, d = H[m], D[m]
        h = (h - h.mean()) / (h.std() + 1e-9)
        d = (d - d.mean()) / (d.std() + 1e-9)
        best.append((float(np.mean(h * d)), float(L)))
    best.sort(reverse=True)
    (c1, L1) = best[0]
    rival = next((c for c, L in best[1:] if abs(L - L1) > 0.5), 0.0)
    print(json.dumps({
        "lag": round(L1, 3),
        "true_offset": round((a.t0h - a.t0d) + L1, 3),
        "peak_corr": round(c1, 3),
        "rival_corr_beyond_0.5s": round(rival, 3),
    }))

if __name__ == "__main__":
    main()
