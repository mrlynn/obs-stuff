#!/usr/bin/env bash
# social-export.sh — turn an OBS recording into platform-ready social videos.
#
#   scripts/social-export.sh <input | --latest> [options]
#
# Formats  (-f, comma-separated, default: vertical)
#   vertical   1080×1920  TikTok · Reels · Shorts
#   feed       1080×1350  Instagram / LinkedIn feed (4:5)
#   square     1080×1080  X · LinkedIn · Facebook
#   landscape  1920×1080  YouTube · X · LinkedIn
#   all        every format above
#
# Reframe mode (-m, default: crop)
#   crop   fill the frame, cut the sides. Use -x to aim (0=left … 1=right).
#   blur   whole frame shown, blurred copy fills the empty space. Good for screen recordings.
#   fit    whole frame shown with black bars.
#   stack  vertical only: webcam on top, screen below. Needs --cam (and optionally --screen).
#
# Options
#   -s, --start  TIME     trim start (e.g. 00:00:03.5 or 3.5)
#   -e, --end    TIME     trim end
#   -x, --focus  0..1     horizontal aim for crop (default 0.5)
#   -y, --focus-y 0..1    vertical aim for crop (default 0.5)
#   --cam    X:Y:W:H      webcam rectangle in the source (pixels) for stack mode
#   --screen X:Y:W:H      screen rectangle in the source for stack mode (default: whole frame)
#   -o, --out DIR         output folder (default: <input folder>/exports)
#   --hw                  use Apple VideoToolbox (much faster, slightly larger files)
#   --no-loudnorm         keep original audio levels (default normalizes to -14 LUFS)
#   --fps N               force output frame rate (default: keep source)
#   --dry-run             print the ffmpeg command instead of running it
#
# Examples
#   scripts/social-export.sh --latest
#   scripts/social-export.sh talk.mov -f vertical,square -x 0.7 -s 4 -e 58
#   scripts/social-export.sh demo.mov -f vertical -m stack --cam 1376:616:480:400
#   scripts/social-export.sh demo.mov -f all -m blur --hw
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
command -v ffmpeg >/dev/null || die "ffmpeg not found (brew install ffmpeg)"

INPUT="" FORMATS="vertical" MODE="crop" START="" END="" FX="0.5" FY="0.5"
CAM="" SCREEN="" OUT="" HW=0 LOUD=1 FPS="" DRY=0
RECORDINGS_DIR="${RECORDINGS_DIR:-$HOME/Movies}"

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--format)   FORMATS="$2"; shift 2;;
    -m|--mode)     MODE="$2"; shift 2;;
    -s|--start)    START="$2"; shift 2;;
    -e|--end)      END="$2"; shift 2;;
    -x|--focus)    FX="$2"; shift 2;;
    -y|--focus-y)  FY="$2"; shift 2;;
    --cam)         CAM="$2"; shift 2;;
    --screen)      SCREEN="$2"; shift 2;;
    -o|--out)      OUT="$2"; shift 2;;
    --hw)          HW=1; shift;;
    --no-loudnorm) LOUD=0; shift;;
    --fps)         FPS="$2"; shift 2;;
    --dry-run)     DRY=1; shift;;
    --latest)
      INPUT="$(ls -t "$RECORDINGS_DIR"/*.{mov,mp4,mkv} 2>/dev/null | head -1 || true)"
      [ -n "$INPUT" ] || die "no recordings found in $RECORDINGS_DIR"
      echo "Using latest recording: $INPUT"; shift;;
    -h|--help)     sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    -*)            die "unknown option $1";;
    *)             INPUT="$1"; shift;;
  esac
done

[ -n "$INPUT" ] || die "no input file. Try --help"
[ -f "$INPUT" ] || die "file not found: $INPUT"
[ "$FORMATS" = "all" ] && FORMATS="vertical,feed,square,landscape"
[ -n "$OUT" ] || OUT="$(cd "$(dirname "$INPUT")" && pwd)/exports"
mkdir -p "$OUT"

base="$(basename "${INPUT%.*}")"
has_audio="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$INPUT" | head -1)"

size_for() {
  case "$1" in
    vertical)  echo "1080 1920";;
    feed)      echo "1080 1350";;
    square)    echo "1080 1080";;
    landscape) echo "1920 1080";;
    *) die "unknown format '$1' (vertical|feed|square|landscape|all)";;
  esac
}

rect_crop() { # X:Y:W:H → ffmpeg crop=W:H:X:Y
  local IFS=:; set -- $1
  [ $# -eq 4 ] || die "rectangle must be X:Y:W:H"
  echo "crop=$3:$4:$1:$2"
}

build_filter() { # $1=W $2=H → video filtergraph ending in [v]
  local W=$1 H=$2 pre="" fpsf=""
  [ -n "$FPS" ] && fpsf=",fps=$FPS"
  case "$MODE" in
    crop)
      echo "[0:v]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H:(iw-$W)*$FX:(ih-$H)*$FY,setsar=1$fpsf,format=yuv420p[v]";;
    blur)
      echo "[0:v]split[a][b];[a]scale=$W:$H:force_original_aspect_ratio=increase,crop=$W:$H,boxblur=40:3,eq=brightness=-0.06:saturation=1.2[bg];[b]scale=$W:$H:force_original_aspect_ratio=decrease[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,setsar=1$fpsf,format=yuv420p[v]";;
    fit)
      echo "[0:v]scale=$W:$H:force_original_aspect_ratio=decrease,pad=$W:$H:(ow-iw)/2:(oh-ih)/2:black,setsar=1$fpsf,format=yuv420p[v]";;
    stack)
      [ -n "$CAM" ] || die "stack mode needs --cam X:Y:W:H (webcam location in the source)"
      [ "$W" -lt "$H" ] || die "stack mode only applies to vertical/feed formats"
      local camH=$(( H * 2 / 5 )) scrH=$(( H - H * 2 / 5 ))
      local camc scrc="null"
      camc="$(rect_crop "$CAM")"
      [ -n "$SCREEN" ] && scrc="$(rect_crop "$SCREEN")"
      echo "[0:v]split=3[c][s][s2];\
[c]$camc,scale=$W:$camH:force_original_aspect_ratio=increase,crop=$W:$camH[top];\
[s]$scrc,scale=$W:$scrH:force_original_aspect_ratio=increase,crop=$W:$scrH,boxblur=30:3,eq=brightness=-0.1[sbg];\
[s2]$scrc,scale=$W:$scrH:force_original_aspect_ratio=decrease[sfg];\
[sbg][sfg]overlay=(W-w)/2:(H-h)/2[bot];\
[top][bot]vstack,setsar=1$fpsf,format=yuv420p[v]";;
    *) die "unknown mode '$MODE' (crop|blur|fit|stack)";;
  esac
}

IFS=',' read -r -a fmt_list <<< "$FORMATS"
for fmt in "${fmt_list[@]}"; do
  read -r W H <<< "$(size_for "$fmt")"
  out="$OUT/${base}_${fmt}.mp4"

  args=(-hide_banner -y)
  [ -n "$START" ] && args+=(-ss "$START")
  [ -n "$END" ]   && args+=(-to "$END")
  args+=(-i "$INPUT" -filter_complex "$(build_filter "$W" "$H")" -map "[v]")

  if [ "$HW" -eq 1 ]; then
    args+=(-c:v h264_videotoolbox -b:v 14M -maxrate 20M -profile:v high)
  else
    args+=(-c:v libx264 -preset slow -crf 19 -profile:v high -level 4.2)
  fi
  args+=(-g 60 -color_primaries bt709 -color_trc bt709 -colorspace bt709)

  if [ -n "$has_audio" ]; then
    args+=(-map 0:a:0)
    [ "$LOUD" -eq 1 ] && args+=(-af "loudnorm=I=-14:TP=-1.0:LRA=11,aresample=48000")
    args+=(-c:a aac -b:a 192k -ar 48000)
  fi
  args+=(-movflags +faststart "$out")

  echo "▶ $fmt ${W}×${H} ($MODE) → $out"
  if [ "$DRY" -eq 1 ]; then
    printf 'ffmpeg'; printf ' %q' "${args[@]}"; echo
  else
    ffmpeg -loglevel warning -stats "${args[@]}"
  fi
done
echo "Done. Files in: $OUT"
