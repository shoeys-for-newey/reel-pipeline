---
name: reel-frame
description: Render a 1080x1920 Instagram Reel rough cut from FPV footage (goggle DVR, RunCam Thumb HD, GoPro controller cam) using the account's fixed frame geometry, blur fill, logo, and per-camera grade presets. Use this whenever the user wants to frame, crop, reframe, grade, color-correct, export, or "make a reel" from any clip, even if they don't say "frame" or "template". Also use it for crop checks and grade before/after stills.
---

# reel-frame

Wraps `scripts/frame.sh`, which is the tested source of truth for the filter graphs. Do not write a new ffmpeg graph when the script can do it; extend the script instead.

## Inputs you need before rendering
1. Quad preset from `presets/quads.yaml` (template, grade, sources). Read the DVR OSD craft name if unsure which quad.
2. Start and duration, from the `reel-shotlist` output or the user. Total 15 to 30 s.
3. For `three`: per-source start times from `reel-sync`.
4. `assets/logo.png` in place, or `--brand "TEXT"` for the text fallback (the script finds fontconfig, Windows, or macOS system fonts on its own; it refuses to run only when none exist).

## Commands
Single source (DVR or HD), 60% hero with blur fill:
```
.claude/skills/reel-frame/scripts/frame.sh --in inbox/CLIP.mov --start 4 --dur 15 \
  --grade c03 --logo assets/logo.png --out exports/NAME.mp4
```
Two sources (HD hero + controller cam bottom, no PiP — for flights without DVR):
```
.claude/skills/reel-frame/scripts/frame.sh --in inbox/HD.mp4 --start S --dur 8 --template two \
  --ctrl GOPRO.MP4 --ctrl-start S_ctrl --ctrl-flip --ctrl-y 240 --logo assets/logo.png --out work/seg.mp4
```
Analog full panel + controller cam (`fullctrl`, added 2026-10-04 for the Air65 seated set where the pilot flew seated and the chest GoPro held the radio; the DVR is the hero, graded, 100% FOV at the `full` geometry, and the GoPro sticks panel fills EVERYTHING below it, no blur strip between them — the pilot's first note on v1 was the gap). `--ctrl-zoom F` scales the GoPro before the crop so the taller panel keeps the radio at its bottom edge instead of showing torso (1.32 on the seated set: 715 px panel, radio at ~72%); `--panel-y N` pins the analog panel if it ever needs to move:
```
.claude/skills/reel-frame/scripts/frame.sh --in DVR.mov --start S --dur D --template fullctrl --grade c03   --ctrl GOPRO.MP4 --ctrl-start S_ctrl --ctrl-flip --ctrl-y 0 --ctrl-zoom 1.32 --logo assets/logo.png --out work/seg.mp4
```
A 3:2 panel lands at y 485..1205 (sticks panel 1205..1920), so measure the hero band as `crop=1080:720:0:485`. Logo at y 293 stays clear of the OSD row. The script prints the geometry it chose.

Three sources (HD hero, controller cam bottom, DVR PiP top right):
```
.claude/skills/reel-frame/scripts/frame.sh --in inbox/HD.mp4 --start S --dur 20 --template three \
  --ctrl inbox/GOPRO.mp4 --ctrl-start S_ctrl --dvr inbox/DVR.mov --dvr-start S_dvr \
  --grade c03 --logo assets/logo.png --out exports/NAME.mp4
```
Collage (analog star + HD pop-in panels at diagonally opposed corners, the pilot's format 2026-09-30, air65_night_pinnacle):
```
.claude/skills/reel-frame/scripts/frame.sh --in inbox/DVR.mov --start 34.6 --dur 12.9 --template collage   --grade chroma --post "eq=saturation=1.2,curves=..." --pop-post "eq=gamma=1.3:saturation=1.1"   --pop "inbox/O4_stab.mp4::18.95::3.0::0.4::tr" --pop "inbox/O4_stab.mp4::23.95::3.6::2.4::bl"   --logo assets/logo.png --out work/seg.mp4
```
Each `--pop` is `FILE::SRC_START::DUR::AT::CORNER`: AT is seconds into the render, CORNER tr|bl|tl|br. Pops are 16:9 at `--pop-w`: `tr` sits at y 170 (clear of the IG top-right icon), `bl` sits directly under the panel at x 40. With a top pop wider than 560 the star panel slides down so the pop stays tangent instead of covering the analog OSD row (680 wide = 382 tall, star at y 552; the script prints the geometry). The pilot's call 2026-09-30: 560 was hard to see on the phone, 680 is the size to use. A pop-free segment in the same reel takes `--template collage --pop-w 680 --star-y 552` (no --pop) so the star sits where its neighbours put it. Pops fade 0.2 s in/out (`--pop-fade`), the star passes through untouched outside each window, and pops may overlap in time. Different moments in the pops are fine (pilot). Measured night O4 pops need `--pop-post "eq=gamma=1.3:saturation=1.1"` to read at 40-58 luma in a 560 px panel; at gamma 1.1 they sat at 30-38 and read as black.

`--grade` applies to the DVR input only in `three`; HD stays ungraded. `--keep-audio` keeps source audio (default is silent; Edits adds music).

Controller cam options (`two` and `three`): `--ctrl-flip` undoes a bogus 180 rotation tag (chest-mounted GoPro — the CineBot30 set carries one); `--ctrl-y N` sets the panel crop's top offset in the 1080-wide scaled ctrl frame so the radio/hands land in the panel (240 fits the chest-mounted GoPro in 4:3). The script gives the ctrl input a 2 s decode run-up and trims it off again: input-seeking a GoPro smears the first second otherwise. Every render is normalized to limited-range yuv420p at the end of the chain; full-range sources (Thumb, GoPro) would otherwise fail the hook as yuvj420p.

Hero crop pan: `--hero-x F` slides the 1080-wide hero crop across the scaled source (0 = left edge, 0.5 = center, default; 1 = right edge). A 16:9 source keeps only the center 53% of its width, so a subject on the frame edge (vehicle, animal) can vanish from a centered crop even when it reads clearly in a full-frame contact sheet — ALWAYS tile-check the rendered hero band (`crop=1080:1152:0:269`) before locking a segment whose subject sits off-center. Accepts a t-expression for animated pans (quote it). Validated 2026-09-11 on the beach jeep passes: 0.7 held a right-side jeep through its approach, 0.18 a left-side one.

Multi-segment reels (one reel from several flights): render each segment with identical settings to `work/seg_*.mp4`, list them in a concat file, then `ffmpeg -f concat -safe 0 -i list.txt -c copy exports/NAME.mp4`. Same encoder settings = lossless copy-concat; the Stop hook judges only the final file. Keep total 15 to 30 s.

## Geometry the script enforces
Hero 1080x1152 at y=269. Bottom panel 1080x499 at y=1421, cropped from the top-left of the controller cam so the sticks sit left of the icon column. DVR PiP `--dvr-h` px tall (default 230), right-aligned 40 px from the right edge; `--dvr-y` sets its top offset (default 20 fills the top strip, but that collides with Instagram's top-right icon — use `--dvr-y 170` for reels; it overlaps hero top-right, fine when that's sky). The pilot's call 2026-09-12 (night dive): 230 felt small in the first series — use `--dvr-h 300` for 16:9 goggle DVRs (533 px wide; battery/ALT/timer OSD becomes legible). Logo at (40, 293), 320 px wide. NOTE on `--ctrl-flip`: the ctrl panel convention is PILOT-POV on the hands (pilot, 2026-09-12), not gravity-corrected. Decide per GoPro set by extracting a still: flip until it reads as your own hands looking down. Both the CineBot30 set (bogus -180 tag) and the WHDoop night set (valid -180 tag) end up needing --ctrl-flip, for different reasons.

## Grade presets
| preset | filters | measured on |
|---|---|---|
| none | passthrough | HD sources |
| c03 | gamma 1.25, saturation 1.4, contrast 1.03, chroma NR 5x5, chroma-only hqdn3d | Air65 DVR: mean luma 24% to 34%, sat 14-28 to 17-35 |

Adding a preset: measure first. `ffmpeg -i CLIP -vf signalstats,metadata=print -f null -` and read YAVG, YMIN, YMAX, SATAVG. If YMIN is already 0 and YMAX 255, use gamma not levels. Never sharpen or luma-denoise analog.

## Finishing pass (--post)
Every final export gets one (CLAUDE.md policy). `--post` takes an ffmpeg filter chain applied to the composed picture before the logo overlay (logo stays untouched):
```
--post "eq=brightness=0.03:saturation=1.08,curves=master='0/0 0.28/0.26 0.72/0.74 1/1'"
```
Workflow: measure each segment window's YAVG/SATAVG, set the reel's target at the median, give each segment a small eq trim toward it (brightness in eq units is luma/255: +10 luma = +0.04), and share one gentle S-curve across every segment so the cuts read as one shoot. eq trims first in the chain, curve after.

WARNING measured 2026-09-17 (shoeycat night reel): this machine's ffmpeg quantizes eq brightness to ~2.5-luma steps and the smallest bucket goes the WRONG WAY: 0.004-0.010 all land at -1 luma, 0.012-0.020 at +2, 0.024 at +4, 0.031-0.039 at +7. Never pass eq brightness under 0.012; verify any trim by measuring, not from the luma/255 arithmetic (fine at 0.04+, garbage below 0.012). Negative buckets run STRONGER than the positive mirror (measured 2026-09-19 reel, day footage YAVG 110-140): -0.016 = -6, -0.024 = -9, -0.031 = -11, -0.045 = -13.6, -0.055 = -15.7, -0.07 = -20.5 luma.

Measure the HERO BAND of the rendered frame (`crop=1080:1152:0:269`), not the raw source: the hero crop can sit 10+ luma off the full source frame (measured on the 2026-09-08 catch segment), so trims designed on source numbers under-correct. Verify convergence on the final export the same way; target spread under ~8 luma across segments. Re-verify after ANY recut — trimming 1 s off a segment moved its window average 4 luma (0019 fence rip) and needed a stronger trim.

## Always show a still
After every render, extract the opening frame and one mid-clip frame to `work/` and look at them:
```
ffmpeg -y -ss 0 -i exports/NAME.mp4 -frames:v 1 work/NAME_open.png
```
Check: OSD text not cut mid-word (else the quad's `osd_cols` in the preset is wrong), sticks visible in bottom panel, logo not overlapping OSD.

## three-template field notes (validated 2026-09-08, 0019 farm reel)
- 50 fps PAL DVR into the 59.94 output frame-mixes cleanly at PiP size; no visible stutter.
- A DVR track that ends before the cut does (goggle DVR stopped early) freeze-frames the PiP via overlay's eof-repeat instead of erroring — fine for under ~0.5 s, recut if longer.
- HEVC DVR input-seeks accurately; only the GoPro needs the decode run-up.
- Ungraded (`--grade none`) CineBot30 DVR PiP reads fine at 230 px; the c03-style lift is unnecessary there.

## Common failures
- `three` render hangs: an input was given without `-t`; the script passes `--dur` to every input, so check that all three paths exist.
- Soft hero from analog: expected at 2.4x upscale. Do not sharpen.
- Duration outside 15 to 45 s: the Stop hook will reject the export (15-30 is still the target; go longer only when the content earns it). Recut, don't pad.
