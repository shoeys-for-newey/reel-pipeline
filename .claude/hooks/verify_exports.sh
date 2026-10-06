#!/usr/bin/env bash
# verify_exports.sh — Stop hook. Checks every .mp4 in exports/ newer than the last clean pass.
# Exit 2 sends the failure list back to Claude and keeps the session going; exit 0 lets it stop.
# The mark file only advances on a clean pass, so a failing export stays on the list until
# it is actually re-rendered. If stop_hook_active is true in the hook input (this stop was
# already blocked once), report but exit 0 so a hopeless export can't loop forever; the
# files re-check on the next stop.
# Spec: 1080x1920, h264, yuv420p, 60 fps (59.94 accepted), 15..45 s (target 15-30; >30 when content earns it, pilot 2026-09-08), no audio stream (Edits adds music).
set -u
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
DIR="$ROOT/exports"
MARK="$ROOT/.claude/hooks/.last_verify"
HOOK_INPUT=$(cat 2>/dev/null || true)
STOP_ACTIVE=0
grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' <<<"$HOOK_INPUT" && STOP_ACTIVE=1
[[ -d "$DIR" ]] || exit 0
touch -d '1970-01-01' "$MARK.tmp" 2>/dev/null || touch -t 197001010000 "$MARK.tmp"
[[ -f "$MARK" ]] && cp -p "$MARK" "$MARK.tmp"   # -p keeps the mtime; without it find -newer compares against "now" and misses everything

fail=0; msgs=""
while IFS= read -r -d '' f; do
  eval "$(ffprobe -v error -select_streams v:0 \
    -show_entries stream=width,height,r_frame_rate,codec_name,pix_fmt -of default=nw=1 "$f" \
    | sed -E 's/^width=/w=/; s/^height=/h=/; s/^r_frame_rate=/fr=/; s/^codec_name=/codec=/; s/^pix_fmt=/pix=/')"
  dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
  astreams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$f" | wc -l | tr -d ' ')
  n=$(basename "$f"); bad=""
  [[ "$w" == "1080" && "$h" == "1920" ]] || bad+=" size=${w}x${h}"
  [[ "$fr" == "60000/1001" || "$fr" == "60/1" ]] || bad+=" fps=$fr"
  [[ "$codec" == "h264" ]] || bad+=" codec=$codec"
  [[ "$pix" == "yuv420p" ]] || bad+=" pix=$pix"
  awk -v d="$dur" 'BEGIN{exit !(d>=15 && d<=45)}' || bad+=" dur=${dur}s"
  [[ "$astreams" == "0" ]] || bad+=" audio_streams=$astreams"
  if [[ -n "$bad" ]]; then fail=1; msgs+="$n:$bad"$'\n'; else msgs+="$n: OK"$'\n'; fi
done < <(find "$DIR" -maxdepth 1 -name '*.mp4' -newer "$MARK.tmp" -print0)
rm -f "$MARK.tmp"

[[ -z "$msgs" ]] && exit 0
if [[ $fail -eq 1 ]]; then
  if [[ $STOP_ACTIVE -eq 1 ]]; then
    printf 'Export check still failing (not blocking again this stop):\n%s' "$msgs"
    exit 0
  fi
  printf 'Export check FAILED. Fix before finishing:\n%s' "$msgs" >&2
  exit 2
fi
touch "$MARK"
printf 'Export check passed:\n%s' "$msgs"
exit 0
