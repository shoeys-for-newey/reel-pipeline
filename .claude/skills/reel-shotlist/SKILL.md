---
name: reel-shotlist
description: Rank the action in an FPV clip and flag crashes, landings, dead screens (STATS page, quad on the ground), and analog signal loss, producing candidate start/end windows for a reel. Use this whenever the user drops in raw footage, asks "what's usable", "find the best part", "where's the crash", or wants a cut list, before any framing or export. Run it on every new DVR or HD file, even if the user already named a start time, and compare.
---

# reel-shotlist

Wraps `scripts/shotlist.py`. Per-second motion energy (luma frame difference), brightness, and saturation from ffmpeg `signalstats`, then classification and ranked windows.

## Run
```
python .claude/skills/reel-shotlist/scripts/shotlist.py inbox/CLIP.mov \
  --fps 4 --clip-len 12 --top 3 --json work/CLIP_shots.json
```
Runtime is dominated by decoding: 60 fps MJPEG DVR takes about 1.5x realtime on a laptop. For files over 3 minutes, first cut a proxy: `ffmpeg -i CLIP -vf scale=360:-2 -r 10 -an work/CLIP_proxy.mp4` and run on that (`-2` not `-1`: a 16:9 source lands on an odd height at 360 wide and libx264 refuses it).

## Shake check (scripts/shakescore.py, added 2026-09-13)
Contact sheets cannot show high-frequency wobble, and twitchmap misses it too (it targets single-frame gyro twitches; slow 2-5 Hz turbulence buffeting passes clean). Before locking any slow/scenic window (climbs, pans, cruises), score it:
```
python .claude/skills/reel-shotlist/scripts/shakescore.py "NAME::D:/path/HERO_stab.mp4::START::DUR" ...
```
RMS of per-frame phase-correlation translation residual after removing a 0.5 s moving average. Pass WINDOWS-STYLE paths (D:/...) — MSYS does not convert paths embedded inside the :: spec. Compare like scenes against like: day-dive calibration (2026-09-13): pilot-flagged shaky climbs 1.57-1.88 px, smooth climbs 0.23-0.33, smooth dive 0.49, apex pano drift 0.82. Facade-filling dives inflate to 4+ px from parallax, not shake — the metric only ranks within a scene type. Whoop climbs near supertall tops are turbulence magnets; the same flight's lower/approach sections often score 5x cleaner.

## Classes
- `action`  ranked by motion. Higher is more stick movement or faster scenery.
- `dead`    motion under 8 (analog) or 3 (HD). STATS screen, quad on the ground, hand-carry idle.
- `static`  high motion with saturation under 8: analog snow, signal loss, end of recording.

## Markers
- `action->dead`  crash or landing candidate. Good reel endings are 1 to 2 s after this.
- `signal lost`   analog static. Nothing after this is usable.

## Calibration (Air65 DVR, 720x480, 60 fps)
Flight 4 to 13 s scored 32 mean motion; hand-carry 24 to 33 s scored 31 (high motion, wrong kind). Motion alone can't tell flight from a hand-carry, so always confirm the top window with a still or the OSD flight timer before cutting.

## Digital HD feeds (O4 goggle DVR, onboard)
- The `static` class and `signal lost` markers misfire constantly on digital sources: desaturated urban scenes (concrete, asphalt, white trucks) sit under sat 8 at high motion. Ignore both for O4/HD files; they mean something only on analog.
- The brightness column is an indoor/outdoor detector on home-launch flights: WHDoop apartment interior read 29-46, street 70-145 (2026-09-12). The jump marks the window exit; the drop at the tail marks the return. Faster and more reliable than frame-scanning for "skip anything indoors".
- On goggle DVR contact sheets, read the OSD ALT field across consecutive stills: a 30+ m drop over 5 s is a dive (45.8→9.7 found both dives on the city story). Cheaper than motion scores for finding dives specifically.

## Output to the user
Give the top windows with start, end, motion score, and the markers, then one sentence recommending a cut: open point, end point, total length. Ask before cutting if the top two windows are within 10% of each other.

Distrust top windows that touch the last ~15 s of a clip: the hand-catch, landing, and walk-up score high motion (2026-09-08: both long 2026-09-08 flights ranked their pickup as the #1 "action" window). Verify tails with a still before believing them — though those same moments make great endings on purpose.

## Tuning
`--static-ydif`, `--static-sat`, `--dead-ydif` are the thresholds. HD sources have lower baseline motion; start with `--dead-ydif 3`. Record any threshold change per quad in `presets/quads.yaml` under `notes`.

## Inverted-moment finder (scripts/invertscan.py, added 2026-10-02)
Motion scores rank a whole 5 min freestyle flight at 24-30 everywhere and cannot tell a loop apex from a fast cruise. `python .claude/skills/reel-shotlist/scripts/invertscan.py work/CLIP_proxy.mp4` (the 360p 10 fps shotlist proxy) prints every run where the bottom of the frame is bluer than the top — the quad is inverted. On the r5l maiden it listed 40 + 25 runs over two flights in ~40 s; the 1.5-3 s runs were the full loops with the skyline upside down, the 0.5 s ones rolls. Tile the hits at 0.25 s before cutting: analog breakup bursts sit right next to many apexes. Note: ffmpeg signalstats on a raw-MJPEG input seek always reports the first decoded frame as SATAVG 0 — judge mono cut-ins on the rendered segment, never on the raw seek.
