#!/usr/bin/env bash
# Render the six Meet / Zoom background images (dark & light × plain / name / booking)
# from background.html, using headless Google Chrome. Run after editing overlays/config.js.
#
#   meeting-backgrounds/render.sh
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || { echo "Google Chrome not found (set CHROME=/path/to/chrome)" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

render() { # $1=variant $2=theme $3=out ; fresh profile per run, retried because headless Chrome can crash on exit
  local try
  for try in 1 2 3; do
    rm -f "$3"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --user-data-dir="$TMP/profile-$1-$2-$try" --window-size=1920,1080 --virtual-time-budget=3000 \
      --screenshot="$PWD/$3" "file://$PWD/background.html#variant=$1&theme=$2" >/dev/null 2>&1 || true
    [ -s "$3" ] && return 0
    sleep 1
  done
  echo "✗ failed to render $3" >&2; return 1
}

for theme in dark light; do
  for variant in plain name booking; do
    out="$theme-$variant.png"
    render "$variant" "$theme" "$out" && echo "✓ $out"
  done
done
