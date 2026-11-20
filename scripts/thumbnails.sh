#!/usr/bin/env bash
# thumbnails.sh — pull the most "representative" frames from a recording so you can
# pick a cover image, plus a contact sheet to compare them at a glance.
#
#   scripts/thumbnails.sh <input | --latest> [count=12] [outdir]
#
# Output: <outdir>/<name>_thumb_01.jpg … and <name>_contact.jpg
set -euo pipefail
command -v ffmpeg >/dev/null || { echo "ffmpeg not found" >&2; exit 1; }

RECORDINGS_DIR="${RECORDINGS_DIR:-$HOME/Movies}"
IN="${1:-}"
if [ "$IN" = "--latest" ]; then
  IN="$(ls -t "$RECORDINGS_DIR"/*.{mov,mp4,mkv} 2>/dev/null | head -1 || true)"
fi
[ -n "$IN" ] && [ -f "$IN" ] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
N="${2:-12}"
OUT="${3:-$(cd "$(dirname "$IN")" && pwd)/exports}"
mkdir -p "$OUT"
base="$(basename "${IN%.*}")"

dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$IN")"
# Split the video into N even windows; pick the sharpest-looking frame in each.
fps="$(awk -v n="$N" -v d="$dur" 'BEGIN{printf "%.6f", n/d}')"

echo "Picking $N frames from $IN (${dur%.*}s)…"
ffmpeg -hide_banner -loglevel error -y -i "$IN" \
  -vf "fps=$fps*10,thumbnail=10,scale=1920:-2" -frames:v "$N" -q:v 2 \
  "$OUT/${base}_thumb_%02d.jpg"

cols=4; rows=$(( (N + cols - 1) / cols ))
ffmpeg -hide_banner -loglevel error -y -pattern_type glob -i "$OUT/${base}_thumb_*.jpg" \
  -vf "scale=480:-2,tile=${cols}x${rows}:padding=8:margin=8:color=0x111111" -frames:v 1 -update 1 -q:v 3 \
  "$OUT/${base}_contact.jpg"

echo "Frames:        $OUT/${base}_thumb_01.jpg …"
echo "Contact sheet: $OUT/${base}_contact.jpg"
