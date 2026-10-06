#!/usr/bin/env bash
# frame.sh — render a 1080x1920 Instagram Reel rough cut from one or three sources.
#
# Templates
#   hero60  : one source (DVR or HD) as hero at 60% height (y 269..1421), blur-fill top/bottom
#   full    : one source at full width, no crop (100% FOV; analog whoop DVR), panel
#             centered in the hero band, blur fill everywhere else
#   two     : HD hero 60% + controller cam bottom 26%, no PiP (flights without DVR)
#   three   : HD hero 60% + controller cam bottom 26% + DVR PiP top strip
#   fullctrl: analog `full` panel + controller cam filling the rest below it, gapless (seated chest-cam sets, 2026-10-04)
#   collage : analog `full` panel as the star, plus HD pop-in panels (16:9, --pop-w wide)
#             that appear and disappear at diagonally opposed corners of the analog panel.
#             Repeat --pop "FILE::SRC_START::DUR::AT::CORNER" per pop-in; AT is seconds into
#             this render, CORNER is tr|bl|tl|br (tr sits at y=170 clear of the IG top icon,
#             bl/br sit directly under the analog panel). Pops fade 0.2 s in/out. --pop-post
#             grades the pop streams only (e.g. "eq=gamma=1.3"). --pop-w 680 is the size
#             the pilot settled on (560 read too small); wide top pops slide the star panel down
#             to stay tangent. --star-y N pins the star panel for pop-free segments.
#             The pilot's ask 2026-09-30.
# Controller cam options (two/three): --ctrl-flip undoes a bogus 180 rotation tag
# (chest-mounted GoPro), --ctrl-y N sets the crop's top offset in the 1080-wide
# scaled ctrl frame so the radio/hands land in the panel (default 0).
# --hero-x F pans the hero crop horizontally: 0=left edge, 0.5=center (default),
# 1=right edge of the source. Use when the subject (vehicle, animal) sits off-center
# in the 16:9 source and the centered 9:16 crop would lose it. Accepts an ffmpeg
# expression in t for animated pans (quote it; commas need the whole arg quoted).
#
# Usage
#   frame.sh --in SRC --start S --dur D --out OUT.mp4 [--template hero60|full|two|three|fullctrl|pip|collage]
#            [--grade none|c03|chroma] [--logo PNG | --brand "TEXT"] [--keep-audio]
#            [--ctrl FILE --ctrl-start S] [--dvr FILE --dvr-start S]
#
# Branding: --logo PNG overlays the PNG at 320 px wide. Without a logo the script draws
# --brand TEXT (default "SHOEYS FOR NEWEY") with the first font it finds: fontconfig
# (fc-match), then the Windows and macOS system fonts, then Linux DejaVu.
#
# Geometry (1080x1920): hero y=269 h=1152 (14%..74%), bottom panel y=1421 h=499, top strip h=269.
# Encode: H.264 yuv420p 59.94fps CRF 20, faststart. Silent unless --keep-audio.
# 59.94 (60000/1001) matches the Thumb hero 1:1 and frame-doubles the 29.97 GoPro exactly.
set -euo pipefail

FPS="60000/1001"

TEMPLATE=hero60; GRADE=none; LOGO=""; BRAND="SHOEYS FOR NEWEY"; KEEP_AUDIO=0; POST="null"
IN=""; START=0; DUR=""; OUT=""
CTRL=""; CTRL_START=0; DVR=""; DVR_START=0; CTRL_FLIP=0; CTRL_Y=0; DVR_Y=20; DVR_H=230; HERO_X=0.5
POPS=(); POP_W=560; POP_POST="null"; POP_FADE=0.2; STAR_Y=""; PANEL_Y_OPT=""; CTRL_ZOOM=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in) IN="$2"; shift 2;;
    --start) START="$2"; shift 2;;
    --dur) DUR="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --template) TEMPLATE="$2"; shift 2;;
    --grade) GRADE="$2"; shift 2;;
    --post) POST="$2"; shift 2;;
    --logo) LOGO="$2"; shift 2;;
    --brand) BRAND="$2"; shift 2;;
    --keep-audio) KEEP_AUDIO=1; shift;;
    --ctrl) CTRL="$2"; shift 2;;
    --ctrl-start) CTRL_START="$2"; shift 2;;
    --ctrl-flip) CTRL_FLIP=1; shift;;
    --ctrl-y) CTRL_Y="$2"; shift 2;;
    --dvr) DVR="$2"; shift 2;;
    --dvr-start) DVR_START="$2"; shift 2;;
    --dvr-y) DVR_Y="$2"; shift 2;;
    --dvr-h) DVR_H="$2"; shift 2;;
    --hero-x) HERO_X="$2"; shift 2;;
    --pop) POPS+=("$2"); shift 2;;
    --pop-w) POP_W="$2"; shift 2;;
    --pop-post) POP_POST="$2"; shift 2;;
    --pop-fade) POP_FADE="$2"; shift 2;;
    --star-y) STAR_Y="$2"; shift 2;;
    --panel-y) PANEL_Y_OPT="$2"; shift 2;;
    --ctrl-zoom) CTRL_ZOOM="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[[ -n "$IN" && -n "$DUR" && -n "$OUT" ]] || { echo "need --in --dur --out" >&2; exit 1; }

# Grade presets. Analog only. Never sharpen, never luma-denoise.
case "$GRADE" in
  none) GRADEF="null";;
  c03)  GRADEF="eq=gamma=1.25:saturation=1.4:contrast=1.03,chromanr=thres=60:sizew=5:sizeh=5,hqdn3d=0:0:4:4";;
  chroma) GRADEF="chromanr=thres=60:sizew=5:sizeh=5,hqdn3d=0:0:4:4";;  # analog chroma cleanup only, no tonal change (night reels; tonal work goes in --post)
  *) echo "unknown grade: $GRADE" >&2; exit 1;;
esac

HERO_H=1152; HERO_Y=269; BOT_Y=1421; BOT_H=499
# Hero crop x: fraction (or t-expression) of the pannable width. 0.5 = centered,
# identical to the old fixed crop. Quoted so expression commas survive the graph parser.
HERO_CROP="crop=1080:${HERO_H}:'(iw-1080)*(${HERO_X})':0"

# Input-seeking the GoPro smears the first ~1s after the keyframe jump, so the ctrl
# input gets a 2s decode run-up that the filter trims back off. Sync is unchanged.
CTRL_SEEK=0; CTRL_PRE=0; CTRL_T=""
if [[ -n "$CTRL" && -n "$DUR" ]]; then
  read -r CTRL_SEEK CTRL_PRE CTRL_T <<<"$(awk -v s="$CTRL_START" -v d="$DUR" \
    'BEGIN{p=(s<2)?s:2; printf "%.3f %.3f %.3f", s-p, p, d+p}')"
fi
CTRL_TRIM="trim=start=${CTRL_PRE},setpts=PTS-STARTPTS"
FONT=$(fc-match -f '%{file}' 'DejaVu Sans:bold' 2>/dev/null || true)
if [[ -z "$FONT" ]]; then
  # No fontconfig (Windows, stock macOS): try the system fonts directly.
  for f in "C:/Windows/Fonts/arialbd.ttf" "C:/Windows/Fonts/arial.ttf" \
           "/System/Library/Fonts/Supplemental/Arial Bold.ttf" "/System/Library/Fonts/Helvetica.ttc" \
           "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"; do
    [[ -f "$f" ]] && { FONT="$f"; break; }
  done
fi
[[ -n "$LOGO" || -n "$FONT" ]] || { echo "no --logo and no font found for the --brand text fallback; pass --logo assets/logo.png" >&2; exit 1; }
# drawtext option values: escape the drive-letter colon and any quote in the font path and brand text.
FONT_ESC="${FONT//:/\\:}"
BRAND_ESC="${BRAND//\'/\\\'}"; BRAND_ESC="${BRAND_ESC//:/\\:}"

# Logo overlay chain fragment: PNG if given, else text placeholder.
# --post (finishing color/lighting pass, CLAUDE.md policy) grades the composed picture
# BEFORE the logo overlay so the brand asset stays untouched.
# The final scale=out_range=tv,format=yuv420p normalizes full-range (yuvj) sources
# like the Thumb and GoPro to limited-range yuv420p, or the Stop hook rejects the export.
if [[ -n "$LOGO" ]]; then
  LOGO_IN="-i $LOGO"
  LOGO_F="[base]${POST}[pgr];[logo]scale=320:-1[lg];[pgr][lg]overlay=40:$((HERO_Y+24))[wl0];[wl0]scale=out_range=tv,format=yuv420p[withlogo]"
else
  LOGO_IN=""
  LOGO_F="[base]${POST}[pgr];[pgr]drawtext=fontfile='${FONT_ESC}':expansion=none:text='${BRAND_ESC}':fontsize=34:fontcolor=white@0.85:x=40:y=$((HERO_Y+31)):shadowcolor=black@0.6:shadowx=2:shadowy=2[wl0];[wl0]scale=out_range=tv,format=yuv420p[withlogo]"
fi

AUDIO_OPTS="-an"
[[ $KEEP_AUDIO -eq 1 ]] && AUDIO_OPTS="-c:a aac -b:a 128k"

case "$TEMPLATE" in
  hero60)
    # [0] = hero source
    FILTER="[0:v]fps=${FPS},${GRADEF},split=2[a][b];\
[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[bg];\
[b]scale=-1:${HERO_H},${HERO_CROP}[hero];\
[bg][hero]overlay=0:${HERO_Y}[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[1:v]}"
      # shellcheck disable=SC2086
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" $LOGO_IN \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  pip)
    # Hero + DVR PiP top-right, no controller cam (same-airframe goggle DVR as
    # instrument overlay, 2026-09-10). PiP geometry matches three; use --dvr-y 170.
    [[ -n "$DVR" ]] || { echo "pip needs --dvr" >&2; exit 1; }
    FILTER="[0:v]fps=${FPS},split=2[h0][h1];\
[h0]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[cv];\
[h1]scale=-1:${HERO_H},${HERO_CROP}[hero];\
[1:v]fps=${FPS},${GRADEF},scale=-2:${DVR_H}[dvr];\
[cv][hero]overlay=0:${HERO_Y}[s1];[s1][dvr]overlay=W-w-40:${DVR_Y}[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[2:v]}"
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$DVR_START" -t "$DUR" -i "$DVR" -i "$LOGO" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$DVR_START" -t "$DUR" -i "$DVR" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  full)
    # [0] = source. Full-width panel keeps 100% of the FOV (the pilot's call for analog
    # whoop DVR, 2026-09-09). Centered in the hero band, not the frame, so the
    # panel bottom stays clear of the IG caption zone (bottom ~35%).
    FILTER="[0:v]fps=${FPS},${GRADEF},split=2[a][b];\
[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[bg];\
[b]scale=1080:-2[panel];\
[bg][panel]overlay=0:${HERO_Y}+(${HERO_H}-h)/2[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[1:v]}"
      # shellcheck disable=SC2086
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" $LOGO_IN \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  collage)
    # [0]=analog star (graded), [1..N]=HD pop-ins, [N+1]=logo optional.
    # Star panel = the `full` geometry (100% FOV, centered in the hero band).
    # Each pop is its own input (-ss/-t), scaled to POP_W x POP_W*9/16, alpha-faded at
    # both ends, time-shifted to AT with setpts, and overlaid with eof_action=pass so the
    # star passes through untouched before the pop starts and after it ends.
    # Zero pops is allowed (a pop-free segment that must keep the same star geometry as
    # its neighbours: pass --star-y with the panel y the other segments printed).
    read -r SW SH <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$IN" | tr ',' ' ')"
    PANEL_H=$(( (1080 * SH / SW) / 2 * 2 ))
    PANEL_Y=$(( HERO_Y + (HERO_H - PANEL_H) / 2 ))
    POP_H=$(( POP_W * 9 / 16 / 2 * 2 ))
    # A top pop (tr/tl) lives at y 170 and must not cover the analog OSD row, so the
    # star panel slides down until the pop is tangent to it (pops over 560 wide).
    for spec in ${POPS[@]+"${POPS[@]}"}; do
      case "${spec##*::}" in tr|tl) [[ $PANEL_Y -lt $((170 + POP_H)) ]] && PANEL_Y=$((170 + POP_H));; esac
    done
    [[ -n "$STAR_Y" ]] && PANEL_Y=$STAR_Y
    echo "collage: star panel ${PANEL_H} tall at y=${PANEL_Y}, pops ${POP_W}x${POP_H}" >&2
    FILTER="[0:v]fps=${FPS},${GRADEF},split=2[a][b];\
[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[bg];\
[b]scale=1080:-2[panel];\
[bg][panel]overlay=0:${PANEL_Y}[c0]"
    POP_INPUTS=(); i=0
    for spec in ${POPS[@]+"${POPS[@]}"}; do
      IFS='|' read -r PF PS PD PAT PC <<<"${spec//::/|}"
      case "$PC" in
        tr) PX=$((1080 - POP_W - 40)); PY=170;;
        tl) PX=40; PY=170;;
        bl) PX=40; PY=$((PANEL_Y + PANEL_H));;
        br) PX=$((1080 - POP_W - 40)); PY=$((PANEL_Y + PANEL_H));;
        *) echo "pop corner must be tr|tl|bl|br: $PC" >&2; exit 1;;
      esac
      j=$((i + 1))
      FO=$(awk -v d="$PD" -v f="$POP_FADE" 'BEGIN{printf "%.3f", d - f}')
      FILTER+=";[${j}:v]fps=${FPS},scale=${POP_W}:${POP_H},${POP_POST},format=yuva420p,\
fade=t=in:st=0:d=${POP_FADE}:alpha=1,fade=t=out:st=${FO}:d=${POP_FADE}:alpha=1,\
setpts=PTS-STARTPTS+${PAT}/TB[p${j}];\
[c${i}][p${j}]overlay=${PX}:${PY}:eof_action=pass:enable='between(t,${PAT},${PAT}+${PD})'[c${j}]"
      POP_INPUTS+=(-ss "$PS" -t "$PD" -i "$PF")
      i=$j
    done
    FILTER+=";[c${i}]null[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[$((i + 1)):v]}"
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" ${POP_INPUTS[@]+"${POP_INPUTS[@]}"} -i "$LOGO" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" ${POP_INPUTS[@]+"${POP_INPUTS[@]}"} \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  fullctrl)
    # `full` analog panel (100% FOV) + controller cam panel filling everything below it,
    # NO gap (pilot 2026-10-04: the blur strip between the two panels read as a mistake).
    # For analog whoop DVR heroes when the chest GoPro actually holds the radio (first:
    # 2026-10-04 air65 set, the pilot flew seated with the radio on their lap).
    # [0]=DVR (graded), [1]=controller cam, [2]=logo optional.
    # --panel-y N   pins the analog panel top (default: centered in the hero band, y 485 for 3:2).
    # --ctrl-zoom F scales the ctrl frame to 1080*F wide before the crop (centered), so a taller
    #               panel can keep the radio near its bottom edge instead of showing more torso.
    # --ctrl-y N    crop top offset in the zoomed ctrl frame, as in two/three.
    [[ -n "$CTRL" ]] || { echo "fullctrl needs --ctrl" >&2; exit 1; }
    read -r SW SH <<<"$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$IN" | tr ',' ' ')"
    PANEL_H=$(( (1080 * SH / SW) / 2 * 2 ))
    PANEL_Y=$(( HERO_Y + (HERO_H - PANEL_H) / 2 ))
    [[ -n "$PANEL_Y_OPT" ]] && PANEL_Y=$PANEL_Y_OPT
    CTRL_TOP=$(( PANEL_Y + PANEL_H ))
    CTRL_H=$(( 1920 - CTRL_TOP ))
    CTRL_W=$(awk -v z="$CTRL_ZOOM" 'BEGIN{printf "%d", int(1080*z/2)*2}')
    echo "fullctrl: panel ${PANEL_H} tall at y=${PANEL_Y}; ctrl panel ${CTRL_H} tall from y=${CTRL_TOP}, ctrl scaled ${CTRL_W} wide (zoom ${CTRL_ZOOM}), crop y ${CTRL_Y}" >&2
    CTRLF="${CTRL_TRIM},fps=${FPS},scale=${CTRL_W}:-2"
    [[ $CTRL_FLIP -eq 1 ]] && CTRLF+=",hflip,vflip"
    CTRLF+=",crop=1080:${CTRL_H}:(iw-1080)/2:${CTRL_Y}"
    FILTER="[0:v]fps=${FPS},${GRADEF},split=2[a][b];[a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[bg];[b]scale=1080:-2[panel];[1:v]${CTRLF}[ctrl];[bg][panel]overlay=0:${PANEL_Y}[s1];[s1][ctrl]overlay=0:${CTRL_TOP}[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[2:v]}"
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL" -i "$LOGO"         -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" )         -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL"         -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" )         -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  two)
    [[ -n "$CTRL" ]] || { echo "two needs --ctrl" >&2; exit 1; }
    # [0]=HD hero (no grade), [1]=controller cam, [2]=logo optional
    CTRLF="${CTRL_TRIM},fps=${FPS},scale=1080:-1"
    [[ $CTRL_FLIP -eq 1 ]] && CTRLF+=",hflip,vflip"
    CTRLF+=",crop=1080:${BOT_H}:0:${CTRL_Y}"
    FILTER="[0:v]fps=${FPS},split=2[h0][h1];\
[h0]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[cv];\
[h1]scale=-1:${HERO_H},${HERO_CROP}[hero];\
[1:v]${CTRLF}[ctrl];\
[cv][hero]overlay=0:${HERO_Y}[s1];[s1][ctrl]overlay=0:${BOT_Y}[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[2:v]}"
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL" -i "$LOGO" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  three)
    [[ -n "$CTRL" && -n "$DVR" ]] || { echo "three needs --ctrl and --dvr" >&2; exit 1; }
    # [0]=HD hero (no grade), [1]=controller cam, [2]=DVR (graded), [3]=logo optional
    # Controller cam bottom panel: 1080x499, sticks kept left of center (crop from left 85%).
    # DVR PiP: top strip, --dvr-h tall (default 230), right-aligned 40 px from the edge.
    # CTRLF built as a variable, not an inline $( [[ ]] && echo ) substitution: the
    # no-flip case made the substitution exit 1 and set -e killed the script silently.
    CTRLF="${CTRL_TRIM},fps=${FPS},scale=1080:-1"
    [[ $CTRL_FLIP -eq 1 ]] && CTRLF+=",hflip,vflip"
    CTRLF+=",crop=1080:${BOT_H}:0:${CTRL_Y}"
    FILTER="[0:v]fps=${FPS},split=2[h0][h1];\
[h0]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:6,eq=brightness=-0.15[cv];\
[h1]scale=-1:${HERO_H},${HERO_CROP}[hero];\
[1:v]${CTRLF}[ctrl];\
[2:v]fps=${FPS},${GRADEF},scale=-2:${DVR_H}[dvr];\
[cv][hero]overlay=0:${HERO_Y}[s1];[s1][ctrl]overlay=0:${BOT_Y}[s2];[s2][dvr]overlay=W-w-40:${DVR_Y}[base];${LOGO_F}"
    if [[ -n "$LOGO" ]]; then
      FILTER="${FILTER/\[logo\]/[3:v]}"
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL" \
        -ss "$DVR_START" -t "$DUR" -i "$DVR" -i "$LOGO" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    else
      ffmpeg -v error -y -ss "$START" -t "$DUR" -i "$IN" -ss "$CTRL_SEEK" -t "$CTRL_T" -i "$CTRL" \
        -ss "$DVR_START" -t "$DUR" -i "$DVR" \
        -filter_complex "$FILTER" -map "[withlogo]" $( [[ $KEEP_AUDIO -eq 1 ]] && echo "-map 0:a?" ) \
        -c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -r $FPS $AUDIO_OPTS -movflags +faststart "$OUT"
    fi
    ;;
  *) echo "unknown template: $TEMPLATE" >&2; exit 1;;
esac

ffprobe -v error -select_streams v:0 -show_entries stream=width,height,r_frame_rate:format=duration -of default=nw=1 "$OUT"
echo "wrote $OUT"
