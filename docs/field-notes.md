# Field notes

Dev log carried over from the original README. Entries dated before 2026-09-08 predate the
59.94 fps output spec (the first tests rendered at 30 fps); everything since ships at 59.94.

- `frame.sh` both templates on the Air65 DVR (720x480 3:2 MJPEG). Output verified 1080x1920 30 fps.
- `sync.py` recovers a known 1.5 s offset across codecs.
- `shotlist.py` on VID00028: top window matches the hand-picked cut; crash and static markers correct.
- `verify_exports.sh` passes a conforming file and fails a 4 s one on duration only.
- 2026-09-07, Windows: `frame.sh` hero60 + the Stop hook end-to-end on a synthetic 720x480 source. Render verified 1080x1920 / 30 fps / 16 s; hook pass, fail (exit 2), `stop_hook_active` bail, and mark-advance paths all exercised. Found and fixed in the process: the hook copied the mark file without `-p`, so `find -newer` compared against "now" and every check after the first pass silently matched nothing.

- 2026-09-08, first real production: the first mashup (CineBot30, 5 segments, `two` template) shipped end-to-end on Windows — Gyroflow stabilization, contact-sheet scouting, motion/onset sync fallbacks, per-segment `--post` finishing grade, copy-concat, hook-verified at 59.94 fps. Along the way the hook caught a real spec violation (full-range yuvj420p) and the GoPro seek-smear and bogus rotation tag were found and fixed in frame.sh.
- 2026-09-08, `three` template first real production: the 0019 farm reel (CineBot30, 5 segments, 32.3 s under the new 45 s hook cap). 50 fps PAL DVR PiP frame-mixes cleanly into 59.94; PiP moved to `--dvr-y 170` to clear Instagram's top-right icon. Sync lesson learned the hard way: matching frame compositions across the DVR/hero FOV gap mis-measured the offset by ~1 s (the pilot caught the PiP leading in the render); `lagfit.py` (motion-trace cross-correlation, now in reel-sync) measured the true offset to sub-frame precision at four separate windows and is the required confirmation for any low-confidence sync.

Since then every template has shipped at 59.94 on real footage; per-quad status lives in `presets/quads.yaml`.
