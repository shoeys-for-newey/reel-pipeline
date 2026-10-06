#!/usr/bin/env bash
# smoke.sh — install check. Renders a synthetic 720x480 clip through frame.sh with the
# text brand fallback (no logo PNG needed) and runs the shotlist on it, then checks the
# output against the export spec the Stop hook enforces. Needs ffmpeg, ffprobe, python+numpy.
# Run from the repo root:  bash tests/smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PY=python; command -v python >/dev/null 2>&1 || PY=python3
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }

for t in ffmpeg ffprobe; do command -v "$t" >/dev/null 2>&1 || fail "$t not on PATH"; done
"$PY" -c "import numpy" 2>/dev/null || fail "$PY cannot import numpy"

echo "1/3 synthetic 720x480 60 fps source (16 s)"
ffmpeg -v error -y -f lavfi -i "testsrc2=size=720x480:rate=60" -t 16 \
  -c:v libx264 -preset veryfast -pix_fmt yuv420p "$TMP/src.mp4"

echo "2/3 frame.sh hero60, text brand fallback, no logo"
bash .claude/skills/reel-frame/scripts/frame.sh --in "$TMP/src.mp4" --start 0 --dur 16 \
  --brand "SMOKE TEST" --out "$TMP/out.mp4" >/dev/null

eval "$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,codec_name,pix_fmt -of default=nw=1 "$TMP/out.mp4" \
  | sed -E 's/^width=/w=/; s/^height=/h=/; s/^r_frame_rate=/fr=/; s/^codec_name=/codec=/; s/^pix_fmt=/pix=/')"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$TMP/out.mp4")
astreams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$TMP/out.mp4" | wc -l | tr -d ' ')
[[ "$w" == "1080" && "$h" == "1920" ]] || fail "size ${w}x${h}"
[[ "$fr" == "60000/1001" ]] || fail "fps $fr"
[[ "$codec" == "h264" ]] || fail "codec $codec"
[[ "$pix" == "yuv420p" ]] || fail "pix_fmt $pix"
awk -v d="$dur" 'BEGIN{exit !(d>=15 && d<=45)}' || fail "duration ${dur}s"
[[ "$astreams" == "0" ]] || fail "audio streams $astreams"

echo "3/3 shotlist.py on the source"
"$PY" .claude/skills/reel-shotlist/scripts/shotlist.py "$TMP/src.mp4" --fps 4 --clip-len 5 --top 1 >/dev/null

echo "SMOKE OK: 1080x1920 h264 yuv420p ${fr} ${dur}s silent"
