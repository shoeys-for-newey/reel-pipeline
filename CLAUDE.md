# Reel pipeline — Shoeys for Newey (@shoeys_fpv_newey)

Purpose: turn raw FPV footage into silent 1080x1920 rough cuts for Instagram Reels.
Music, on-screen text, and publishing happen in Instagram Edits afterward. This repo
never adds music and never posts.

## Layout
- `inbox/`    raw files as they come off the cards. Read-only by convention: never modify, rename, or delete anything here.
- `work/`     intermediates (proxies, stills, shot lists, sync results). Disposable.
- `exports/`  finals only. The Stop hook verifies every new .mp4 here.
- `presets/quads.yaml`  per-quad sources, OSD geometry, grade preset. Read it before framing anything.
- `assets/`   logo PNG and any fonts.

## Workflow, in this order
1. Identify the quad. DVR files carry the craft name in the OSD top-left (e.g. `AIR65 C`). Grab one frame and read it. If unreadable, ask; never guess which quad a file came from.
2. Stabilize O4/O4 Pro onboard hero footage — standard practice on ANY O4 onboard file with gyro data (pilot 2026-09-19). `djgyrofix scan` first; surgical-hybrid fixes only when the scan flags ring (per-quad playbooks in quads.yaml), skip fixing when clean. MIXED-WINDOW RULE, all O4/O4 Pro units (pilot 2026-09-19, measured on the whdoop 2026-09-19 set): a flagged event that overlaps a deliberate rotation (loop/flip windup, apex) gets NO correction — smoothing it leaks the stick input into stabilization. Cross-check every flagged window against the trick moments, then fix with `-ranges "<pure events only>"`; trick windows ride raw gyro. Verify with tight-window shakescore before/after when in doubt. Then Gyroflow render, `_stab` into `inbox/` as the hero. No shake judgments (shakescore, "too shaky" cuts) on unstabilized O4 footage. Stab keeps the source timeline, so sync offsets measured on the raw file carry over — verify duration matches.
3. Sync (only when there is more than one source): `reel-sync` skill.
4. Shot list: `reel-shotlist` skill. Present the top windows and markers before cutting.
5. Frame: `reel-frame` skill, with the template and grade from `presets/quads.yaml`.
6. Export to `exports/` and let the hook check it. Fix failures before declaring done. Multi-segment reels: render segments to `work/`, copy-concat to `exports/` (see reel-frame skill); a segment swap is a ~1 min re-render, so iterate freely on the pilot's watch-throughs.

## Output spec (enforced by hook)
1080x1920, H.264, yuv420p, 60 fps (59.94 — matches the Thumb; the 29.97 GoPro panel frame-doubles exactly), 15 to 30 s target (hook accepts up to 45 when the content earns it — pilot 2026-09-08), no audio stream.

IG Stories ship through this same pipeline and spec, hook and all (first: whdoop_city_story 2026-09-12). Same frame geometry; stories are just posted from the phone's story composer instead of Edits.

## Frame geometry (1080x1920)
- Instagram UI covers roughly the bottom 20 to 35% (caption, handle, audio), the right 10% (icon column), and lightly the top 14%.
- Hero panel: y 269 to 1421 (14% to 74% of height). Action lives here.
- Bottom panel y 1421 to 1920: controller cam when available, sticks framed left of center.
- Top strip: DVR PiP on the right, logo on the left corner of the hero. PiP at y=20 collides with the IG top-right icon (Reels camera / feed kebab, ~y 70-140): render reels with `--dvr-y 170` (dips ~130 px into hero top-right — keep that region sky).
- No black bars. Empty regions are blur fill from the hero source.
- Crop retention when scaling a source to the 1152 px hero: 3:2 source keeps 62.5% of width, 4:3 keeps 70%, 5:4 keeps 75%, 16:9 keeps 53%. Full-bleed is not used; too much FOV lost.

## Content rules
- Open on the best two seconds. The three-second mark decides retention. Approach shots: 1.5 s max before the payoff (a gap, a structure crossing) — slow starts kill viewership (pilot 2026-09-19). Low altitude + speed beats altitude + scenery for openers (2026-09-08: the creek skim replaced a banked climb the pilot called unengaging).
- End on the crash, catch, or landing. The clip should loop.
- Cut before the pack sags. If the shot list says the flight is 9 s, the reel is 9 s plus the landing, not padded.
- Nothing political, in footage or text, ever. Not even replies.
- Racing/F1 voice is the long-term brand voice; don't force it into every reel.

## Grading
- Every final export gets a color/lighting pass before it ships (policy 2026-09-08; frame.sh `--post`). Measure first (signalstats: YAVG, YMIN, YMAX, SATAVG), then design against the numbers — never grade by eye alone.
- Multi-segment reels: per-segment eq trims toward the reel's median luma target, plus one shared gentle S-curve across all segments. Keep HD moves subtle (10% territory) and don't equalize scene-driven saturation differences away — sand and pasture differ naturally.
- Analog DVR input grade: presets in `reel-frame`. C03 values were measured on an Air65 clip: mean luma 24% to 34%, saturation x1.4.
- Never sharpen analog. Never luma-denoise. No LUTs on 8-bit MJPEG.

## Working style
- Terse. Numbers over adjectives. No em dashes.
- When a command modifies files, show the backup or copy step first.
- Before asserting why a shot failed (crash cause, signal loss), ask.
- Show stills (`work/*.png`) at decision points: opening frame, crop check, any grade change.
- One change per render pass. Don't re-grade and re-crop in the same iteration.
- Scout footage with tiled contact sheets (one still every 10-15 s, ffmpeg tile=3x2), not by decoding whole clips. Trust scene content over motion scores.
- Hunting a moment the pilot remembers (an animal, a pass, a crash): ask for a rough timestamp before frame-scanning. One answer beats 40 extracted frames. Their timestamps are player time on the hero file (mm:ss), not the DVR OSD flight timer; verify against scene content before cutting.

## Tools available
ffmpeg/ffprobe on PATH, `python` with numpy (`python3` is the broken Store stub on Windows; use `python`). djgyrofix on PATH fixes DJI O4 gyro metadata for Gyroflow work; framing never needs it. Gyroflow (winget install, `Gyroflow` on PATH in new shells) stabilizes RunCam Thumb and O4 onboard footage before it enters the pipeline: Thumb needs the .gcsv gyro log copied off the card next to the MP4; O4 gyro is embedded, no -g. The stabilized render goes to `inbox/` as the hd source and keeps its audio, so reel-sync still works. Tested invocation (~10 min per 4K60 clip on the RTX 3050): `Gyroflow.exe FILE.MP4 [-g FILE.gcsv] -t "_stab" -r nvidia -f --stdout-progress`. Scripts live under `.claude/skills/*/scripts/` and are the source of truth; read them before writing new ffmpeg graphs. Ad-hoc drawtext (timestamped contact sheets) needs an explicit font on this machine — no fontconfig: `drawtext=fontfile='C\:/Windows/Fonts/arial.ttf':text='%{pts\:hms\:OFFSET}'`.
