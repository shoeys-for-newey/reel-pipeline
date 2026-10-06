#!/usr/bin/env python3
"""shotlist.py — rank the action in a clip and flag static / dead screens.

Usage:
  shotlist.py CLIP [--fps 5] [--win 1.0] [--clip-len 12] [--top 5] [--json OUT.json]

Metrics per frame from ffmpeg signalstats (luma plane):
  YDIF   frame-to-frame change  -> motion energy
  YAVG   mean brightness
  SATAVG mean chroma saturation (0..181)

Classes per window:
  static  YDIF very high AND saturation near zero (analog snow / signal loss)
  dead    YDIF near zero (stats screen, quad sitting on the ground)
  action  everything else, ranked by mean YDIF

Prints a markdown table plus the top N candidate windows of --clip-len seconds
(start, end, mean motion). Thresholds are tuned on 720x480 analog DVR; for HD
sources pass --static-ydif 60 --dead-ydif 3 and expect lower numbers overall.
"""
import argparse, json, re, subprocess, sys
from collections import defaultdict


def probe_metrics(path, fps):
    vf = (f"fps={fps},scale=360:-1,signalstats,"
          "metadata=print:key=lavfi.signalstats.YDIF:file=-,"
          "metadata=print:key=lavfi.signalstats.YAVG:file=-,"
          "metadata=print:key=lavfi.signalstats.SATAVG:file=-")
    cmd = ["ffmpeg", "-v", "info", "-nostats", "-i", path, "-an", "-vf", vf, "-f", "null", "-"]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    # each metadata=print filter emits its own "frame:N ..." header, so merge by frame index
    frames = {}
    cur = None
    for line in out.splitlines():
        m = re.match(r"frame:(\d+)\s+pts:\d+\s+pts_time:([\d.]+)", line)
        if m:
            idx = int(m.group(1))
            cur = frames.setdefault(idx, {"t": float(m.group(2))})
            continue
        m = re.match(r"lavfi\.signalstats\.(\w+)=([\d.\-]+)", line)
        if m and cur is not None:
            cur[m.group(1)] = float(m.group(2))
    return [frames[k] for k in sorted(frames) if {"YDIF", "YAVG", "SATAVG"} <= frames[k].keys()]


def windows(frames, win):
    buckets = defaultdict(list)
    for f in frames:
        buckets[int(f["t"] // win)].append(f)
    rows = []
    for k in sorted(buckets):
        fs = buckets[k]
        rows.append({
            "start": k * win,
            "ydif": sum(f["YDIF"] for f in fs) / len(fs),
            "yavg": sum(f["YAVG"] for f in fs) / len(fs),
            "sat": sum(f["SATAVG"] for f in fs) / len(fs),
        })
    return rows


def classify(rows, static_ydif, static_sat, dead_ydif):
    for r in rows:
        if r["ydif"] >= static_ydif and r["sat"] <= static_sat:
            r["cls"] = "static"
        elif r["ydif"] <= dead_ydif:
            r["cls"] = "dead"
        else:
            r["cls"] = "action"
    return rows


def candidates(rows, win, clip_len, top):
    n = max(1, int(round(clip_len / win)))
    out = []
    for i in range(0, len(rows) - n + 1):
        seg = rows[i:i + n]
        if any(r["cls"] != "action" for r in seg):
            continue
        out.append({"start": seg[0]["start"], "end": seg[-1]["start"] + win,
                    "motion": sum(r["ydif"] for r in seg) / n})
    out.sort(key=lambda c: -c["motion"])
    picked = []
    for c in out:
        if all(c["end"] <= p["start"] or c["start"] >= p["end"] for p in picked):
            picked.append(c)
        if len(picked) >= top:
            break
    return picked


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("clip")
    ap.add_argument("--fps", type=float, default=5)
    ap.add_argument("--win", type=float, default=1.0)
    ap.add_argument("--clip-len", type=float, default=12)
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--static-ydif", type=float, default=30)
    ap.add_argument("--static-sat", type=float, default=8)
    ap.add_argument("--dead-ydif", type=float, default=8.0)
    ap.add_argument("--json")
    args = ap.parse_args()

    frames = probe_metrics(args.clip, args.fps)
    if not frames:
        sys.exit("no frames parsed; check ffmpeg output")
    rows = classify(windows(frames, args.win), args.static_ydif, args.static_sat, args.dead_ydif)
    cands = candidates(rows, args.win, args.clip_len, args.top)

    print(f"| t(s) | motion | bright | sat | class |")
    print(f"|---|---|---|---|---|")
    for r in rows:
        print(f"| {r['start']:.0f} | {r['ydif']:.1f} | {r['yavg']:.0f} | {r['sat']:.1f} | {r['cls']} |")
    print()
    print(f"Top {len(cands)} action windows of {args.clip_len:.0f}s:")
    for c in cands:
        print(f"  {c['start']:.1f} to {c['end']:.1f}  motion {c['motion']:.1f}")
    # transitions worth a look: action -> dead (crash / landing), anything -> static
    marks = []
    for a, b in zip(rows, rows[1:]):
        if a["cls"] == "action" and b["cls"] == "dead":
            marks.append(("action->dead (crash/landing?)", b["start"]))
        if a["cls"] != "static" and b["cls"] == "static":
            marks.append(("signal lost", b["start"]))
    if marks:
        print("Markers:")
        for label, t in marks:
            print(f"  {t:.0f}s  {label}")
    if args.json:
        with open(args.json, "w") as f:
            json.dump({"windows": rows, "candidates": cands, "markers": marks}, f, indent=1)


if __name__ == "__main__":
    main()
