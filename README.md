# reel-pipeline

A [Claude Code](https://claude.com/claude-code) project that turns raw FPV footage into silent
1080x1920 Instagram Reel rough cuts: analog goggle DVR, DJI O4 onboard, RunCam Thumb, and a
chest GoPro as the controller cam. Music, on-screen text, and posting happen in Instagram Edits
afterward. The repo never adds music and never posts.

This is the working repo behind [@shoeys_fpv_newey](https://www.instagram.com/shoeys_fpv_newey).
The rules, presets, and field notes are one account's real decisions, dated. Fork it, swap in your
logo and quads, and the agent does the same work for you.

## What it does

Claude Code reads `CLAUDE.md` for the always-on rules and uses three skills that wrap tested scripts:

| skill | script | job |
|---|---|---|
| `reel-shotlist` | `shotlist.py`, `shakescore.py`, `invertscan.py` | rank the action per second, flag crashes, landings, dead screens (STATS page), analog signal loss, inverted moments; propose start/end windows |
| `reel-sync` | `sync.py`, `visync.py`, `onset_sync.py`, `lagfit.py` | per-source start offsets for multi-camera reels: audio cross-correlation, motion cross-correlation for same-airframe cameras, onset trains for the chest cam, sub-frame refinement |
| `reel-frame` | `frame.sh` | the render: seven templates, blur fill, logo, per-camera grade presets, `--post` finishing pass |

A Stop hook (`.claude/hooks/verify_exports.sh`) probes every new file in `exports/` and refuses to let
the session end until it is 1080x1920, H.264, yuv420p, 59.94 fps, 15 to 45 s, with no audio stream.

A session runs in this order, from `CLAUDE.md`:

1. Identify the quad from the craft name in the DVR OSD.
2. Stabilize O4 onboard footage (Gyroflow, with djgyrofix for gyro bursts) when it is the hero.
3. Sync, if there is more than one source.
4. Shot list. Top windows and markers are shown before anything is cut.
5. Frame, with the template and grade from `presets/quads.yaml`.
6. Export. The hook checks it. Multi-segment reels render to `work/` and copy-concat into `exports/`.

## Requirements

| tool | why | install |
|---|---|---|
| ffmpeg + ffprobe | every script | `winget install Gyan.FFmpeg` / `brew install ffmpeg` |
| Python 3 + numpy | sync and shotlist scripts | `python -m pip install numpy` |
| Claude Code | the agent | https://docs.claude.com/en/docs/claude-code/overview |
| bash | `frame.sh` and the hook | ships with macOS/Linux; on Windows it is Git for Windows, which Claude Code already needs |
| Gyroflow (optional) | stabilizing O4 and Thumb footage before it enters the pipeline | `winget install Gyroflow` / https://gyroflow.xyz |
| djgyrofix (optional) | repairing DJI O4 gyro metadata before Gyroflow | https://github.com/steamvogue/djgyrofix, plus [o4-gyro-surgeon](https://github.com/shoeys-for-newey/o4-gyro-surgeon) for the surgical fixes `CLAUDE.md` refers to |

On Windows `python3` is the Microsoft Store stub and runs nothing; every command in these docs uses
`python`. On macOS substitute `python3`. ffmpeg joins PATH for new terminals only.

## Install

```
git clone https://github.com/shoeys-for-newey/reel-pipeline.git
cd reel-pipeline
chmod +x .claude/hooks/*.sh .claude/skills/*/scripts/*.sh tests/*.sh   # macOS/Linux only
bash tests/smoke.sh
```

Or click **Use this template** on GitHub first and clone your copy. Keep the folder off iCloud Drive
and OneDrive; the intermediates in `work/` run to tens of GB.

`tests/smoke.sh` renders a synthetic 720x480 clip through `frame.sh` with the text brand fallback,
runs the shot list on it, and checks the output against the export spec. It should end with
`SMOKE OK`. The Stop hook and permission rules in `.claude/settings.json` load automatically when
`claude` is started inside the folder.

## Make it yours

1. **Logo.** Drop a PNG with transparency at `assets/logo.png`. It renders 320 px wide at the top-left
   of the hero panel. Without one, `frame.sh` draws `--brand "TEXT"` instead (default is this account's
   name; change the default near the top of the script or pass the flag).
2. **`CLAUDE.md`.** The header names this account. The dated notes ("pilot 2026-09-19") are the original
   pilot's calls and the reasons behind them; keep the ones you agree with, rewrite the rest.
3. **`presets/quads.yaml`.** Ships filled with the author's quads as a worked example. The header comments
   explain every field. Replace the entries with your own; the agent reads the craft name off the DVR
   OSD and matches it to `osd_name`.
4. **Hook bounds.** Duration limits live in `.claude/hooks/verify_exports.sh` if your format differs.

## First session, paste this

Copy one analog DVR clip into `inbox/` first.

```
Read CLAUDE.md and presets/quads.yaml. Then run the reel-shotlist skill on inbox/CLIP.mov,
show me the top windows, and render the best one with reel-frame to exports/test.mp4.
Show me the opening frame before you finish.
```

## Layout

| path | purpose |
|---|---|
| `inbox/` | raw files off the cards. Read-only by convention; the permission rules deny edits here |
| `work/` | proxies, stills, shot lists, sync notes. Disposable |
| `exports/` | finals only. The Stop hook verifies every new `.mp4` here |
| `assets/` | your logo PNG (git-ignored) |
| `presets/quads.yaml` | per-quad sources, template, grade, OSD geometry, field notes |
| `CLAUDE.md` | always-on rules: workflow, output spec, frame geometry, content rules, grading, working style |
| `.claude/settings.json` | Stop hook and permissions: ffmpeg/ffprobe and the skill scripts run without prompts, `inbox/` is write-protected |
| `.claude/hooks/verify_exports.sh` | the export check |
| `.claude/skills/*/` | the three skills; each `SKILL.md` documents its scripts and the hard-won traps |
| `tests/smoke.sh` | install check |
| `docs/field-notes.md` | dev log from the first weeks |

## Output and frame geometry

1080x1920, H.264, yuv420p, 59.94 fps (matches a 59.94 hero 1:1 and frame-doubles a 29.97 GoPro
exactly), 15 to 30 s target, 45 s hard cap, no audio. Instagram's UI covers roughly the bottom 20 to
35 %, the right 10 %, and lightly the top 14 %, so the hero panel sits at y 269 to 1421, the controller
cam below it, and the DVR picture-in-picture top right at y 170 to clear the top-right icon. Empty
regions are blur fill from the hero source, never black bars. Analog is never sharpened or luma-denoised.

## Batch mode

```
claude -p "For every file in inbox/ that has no matching export, run the full workflow from CLAUDE.md and stop after exporting."
```

`-p` is headless. This only works from the CLI, not the desktop app's Code tab.

## Related

- [o4-gyro-surgeon](https://github.com/shoeys-for-newey/o4-gyro-surgeon): surgical repair of DJI O4 gyro bursts for Gyroflow, and twitch measurement of the renders.
- [postflight](https://github.com/shoeys-for-newey/postflight): Betaflight blackbox review agent, same author.
- [Gyroflow](https://gyroflow.xyz) and [djgyrofix](https://github.com/steamvogue/djgyrofix).

## License

MIT. See `LICENSE`.
