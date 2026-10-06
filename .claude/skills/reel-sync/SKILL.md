---
name: reel-sync
description: Align two or more recordings of the same flight (RunCam Thumb HD, goggle DVR, GoPro controller cam) by cross-correlating their audio, and output the per-source start offsets needed by reel-frame's three-source template. Use this whenever a reel involves more than one source file, when the user mentions syncing, lining up, matching, or offset between cameras, or when a three-panel layout is requested. Run it before reel-shotlist on multi-source sessions.
---

# reel-sync

Wraps `scripts/sync.py`. Envelope cross-correlation at 8 kHz over the first 120 s of each file. Works across codecs (PCM DVR vs AAC GoPro) because it correlates the amplitude envelope, not the waveform. Validated: a 1.5 s synthetic offset re-encoded through a different codec recovered as exactly 1.500.

## Run
Pick the hero source as REF (usually the HD file). One call per other source:
```
python .claude/skills/reel-sync/scripts/sync.py inbox/HD.mp4 inbox/DVR.mov
python .claude/skills/reel-sync/scripts/sync.py inbox/HD.mp4 inbox/GOPRO.mp4
```
Output: `{"offset_s": 1.5, "confidence": 1.98}`

## Reading the result
- `offset_s > 0`: OTHER started that many seconds after REF. OTHER's t=0 is REF's t=offset.
- To cut the same moment: REF `--start S`, OTHER `--start S - offset_s`.
- `confidence` above 3 is a clean lock; 1.5 to 3 is usable (the validated 1.5 s recovery scored 1.98). Below 1.5, don't trust it: check that both files actually contain the same flight (DVR files often start before the HD record button was pressed, and the GoPro may be a separate segment). These bands match sync.py's docstring; re-measure on the first real multi-source session and update both together.

## Hand off to reel-frame
```
--in HD --start S   --ctrl GOPRO --ctrl-start (S - off_gopro)   --dvr DVR --dvr-start (S - off_dvr)
```
If a computed start is negative, the reel's opening point is earlier than that source's recording; move S later or drop that panel for the first seconds.

## When audio sync can't work
No audio on one source, a wind-only track, or a clipped DVR motor wall (measured 2026-09-07: every 2026-09-07 pair failed audio sync at confidence 1.0-1.3). Two tested fallbacks, in `scripts/`:
- `visync.py REF OTHER` — video motion-energy correlation. For sources on the SAME airframe (goggle DVR vs onboard HD): both see identical motion. Run REF as the 360px work/ proxy for speed. Verify a 1.5-3 confidence result with `lagfit.py` before rendering (0019 farm: conf 1.61 gave +15.0; lagfit ground truth +14.86). Feed visync full clips only — trimming both inputs to a 30-60 s window collapses confidence to ~1.0 and returns garbage.
- `onset_sync.py REF.wav OTHER.wav` — onset-train correlation for the controller cam. Feed it band-passed 8kHz mono WAVs (`ffmpeg -af "highpass=f=150,lowpass=f=3500" -ac 1 -ar 8000`). Rival peaks run close: ALWAYS confirm the top peak with a disarm-edge or punch anchor (below) before cutting. An unconfirmed top peak shipped a +26.5 offset on 0018/GX010054 that was wrong by 70 SECONDS (true -43.58, caught 2026-09-08); "the panel content looks like the right location" is not confirmation.

## Disarm-edge / punch anchors (controller-cam ground truth, proven 2026-09-08)
The takeoff throttle punch and the landing disarm are step edges audible in BOTH the hero (on-quad mic, razor sharp) and the chest cam (sharp when the quad is within a few meters — takeoffs usually qualify). Measure each edge on a 20 ms band-passed RMS trace and difference the times; two anchors ~90 s apart agreeing within 0.05 s give a flight-wide offset with no drift question.
- Punch: band-pass 800-3500 Hz, look for the 10x RMS jump to sustained plateau. Sharpest anchor; at takeoff the quad is near the pilot.
- Disarm: FFT the hero's last 0.5 s of flight for the idle-tone cluster, band-pass the chest cam to that cluster, find where the SUSTAINED run ends. TRAP: the goggles beep on disarm 30 cm from the chest mic and extend the apparent motor tail ~0.3-0.4 s — the beep burst after the sustained run is not motor. When punch and disarm disagree by ~0.4 s, trust the punch.
- Print the traces and read the structure; single-number edge detectors get fooled by wind lulls and voice. RMS envelope cross-correlation over long windows fails outright in wind (peak ≈ rival ≈ 0.35) — don't bother.
- Distant takeoffs/landings (5-10 m plus wind) leave the edges mushy: expect ±0.3 s at best. If the existing offset sits inside that band, keep it (0019/GX010055 +4.62 re-checked 2026-09-08: anchors span +4.08..+4.74, kept).
- Whoop + chest GoPro, no usable DVR audio (2026-10-04, Air65 analog: the DVR "audio" is a clipped VTX wall, so nothing above applies). Anchor on the LIFTOFF: tile the chest cam at 15-30 fps around the first motor whine onset (band-energy trace 1-7 kHz, 50 ms steps) and find the quad itself leaving the pavement at the pilot's feet; pin the DVR side with the voltage sag / fence drop at throttle-up (the fly timer only gives the arm). At takeoff no other whoop is at the pilot's feet, so this anchor is clean. Pack 1: GP 39.75-39.8 vs DVR 4.1 -> +35.6. Confirm at the landing only if the quad is VISIBLE in the chest cam at that moment (pack 2: tumble at the pilot's feet, whine end + impact clicks GP 84.8, their hand reaches down 0.2 s after the DVR STATS -> +51.8). TRAP that shipped three wrong versions: a whine spool-down / harmonic sweep near the landing time was ANOTHER whoop flying around the group, and the pilot's arm swinging off the radio after the disarm looked like a reach for the quad. That gave +39.1, 3.5 s off; under it the GoPro was silent at the pilot's own takeoff, which should have been checked first. Rule: a whine TAIL is never an anchor on its own in a group session, and a liftoff that is silent in the chest cam means the offset is wrong. `showspectrumpic` (`-lavfi "aformat=channel_layouts=mono,showspectrumpic=s=1600x500:legend=1:stop=4000:scale=log"`) is still the quickest way to see whine onsets/ends. +/-0.1 s.
Last resort: a visual event both cameras see (arm beep in DVR OSD timer vs the arm switch on the controller cam), offset by hand. Either way, note results in `work/SESSION_sync.md` so the next session doesn't redo them.

## lagfit.py (confirming or refining an offset)
`scripts/lagfit.py HERO T0H DUR OTHER T0D DUR2` cross-correlates per-frame motion energy (signalstats YDIF, 100 Hz grid) over a short window around a sharp event — a whip turn, animals flushing, touchdown — and prints the true offset with sub-frame precision plus peak/rival correlations. Run it at 2+ windows far apart; matching values (±0.05 s) confirm one flight-wide offset (0019 farm: 14.84-14.88 at four windows, peaks 0.64-0.92 — no clock drift).

DO NOT judge offsets by matching frame compositions between cameras with different FOVs. The wide DVR lens shows an approaching landmark earlier and holds it longer than the cropped hero, which biased a composition-anchored estimate a full second low on 0019 — the pilot caught the DVR leading the hero in the rendered PiP. Composition stills are only a sanity check that lagfit's peak is the right event, not a measurement. User-quoted timestamps ("3:47") are player time on the hero file, not the DVR OSD timer.
