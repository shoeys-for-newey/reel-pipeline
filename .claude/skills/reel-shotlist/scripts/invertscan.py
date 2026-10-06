# invertscan.py PROXY.mp4 — list inverted-flight runs in an FPV clip from colour alone.
# Per frame, mean (B-G) of the top 30% band vs the bottom 30% band (centre columns only).
# Bottom bluer than top = sky at the bottom = quad inverted (loop/roll apex). Runs >= 0.3 s,
# gaps under 0.5 s merged. Written for a 360x288 10 fps proxy (edit W,H,FPS for others).
# Added 2026-10-02 (r5l maiden): found every loop/roll apex on two 5-6 min
# analog flights in ~40 s; cross-check hits with 0.25 s contact sheets before cutting.
import subprocess, sys, numpy as np
# Inverted when the bottom band reads bluer than the top band.
src = sys.argv[1]; W, H, FPS = 360, 288, 10.0
p = subprocess.Popen(["ffmpeg","-v","error","-i",src,"-f","rawvideo","-pix_fmt","rgb24","-"], stdout=subprocess.PIPE)
n = 0; rows = []
band = int(H*0.3)
while True:
    buf = p.stdout.read(W*H*3)
    if len(buf) < W*H*3: break
    f = np.frombuffer(buf, np.uint8).reshape(H,W,3).astype(np.int16)
    sky = f[:,:,2] - f[:,:,1]
    top = sky[:band, 40:W-40].mean(); bot = sky[H-band:, 40:W-40].mean()
    rows.append((n/FPS, top, bot)); n += 1
rows = np.array(rows)
inv = rows[:,2] - rows[:,1]   # >0 means bottom bluer than top (inverted)
# find runs of inverted frames (inv > 8), merge gaps < 0.5 s
flag = inv > 8
runs = []; start=None
for i,fl in enumerate(flag):
    if fl and start is None: start=i
    if not fl and start is not None:
        runs.append((start,i-1)); start=None
if start is not None: runs.append((start,len(flag)-1))
merged=[]
for s,e in runs:
    if merged and s - merged[-1][1] <= 5: merged[-1]=(merged[-1][0],e)
    else: merged.append((s,e))
print(f"# {src}: {n} frames, inverted runs (start s, end s, dur s, peak inv)")
for s,e in merged:
    if e-s >= 2:
        print(f"{rows[s,0]:7.1f} {rows[e,0]:7.1f} {(e-s+1)/FPS:5.1f} {inv[s:e+1].max():6.1f}")
np.save(src.replace('.mp4','_inv.npy'), np.column_stack([rows, inv]))
