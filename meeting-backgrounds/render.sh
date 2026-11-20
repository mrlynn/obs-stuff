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

render() { # $1=variant $2=theme $3=out $4=brand ; fresh profile per run, retried because headless Chrome can crash on exit
  local try
  for try in 1 2 3; do
    rm -f "$3"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
      --user-data-dir="$TMP/profile-$4-$1-$2-$try" --window-size=1920,1080 --virtual-time-budget=3000 \
      --screenshot="$3" "file://$PWD/background.html#variant=$1&theme=$2&brand=$4" >/dev/null 2>&1 || true
    [ -s "$3" ] && return 0
    sleep 1
  done
  echo "✗ failed to render $3" >&2; return 1
}

# Personal brand (overlays/config.js) → this folder
for theme in dark light; do
  for variant in plain name booking; do
    out="$theme-$variant.png"
    render "$variant" "$theme" "$PWD/$out" "" && echo "✓ $out"
  done
done

# Private work brands (brands/private/brands.js, gitignored) → brands/private/backgrounds/
BRANDS_JS="../brands/private/brands.js"
if [ -f "$BRANDS_JS" ]; then
  OUTDIR="$(cd ../brands/private && pwd)/backgrounds"; mkdir -p "$OUTDIR"
  # Top-level profile ids, skipping aliases marked hiddenInPicker
  ids=$(grep -oE '^    "[a-z0-9-]+": \{' "$BRANDS_JS" | grep -oE '[a-z0-9-]+' || true)
  for id in $ids; do
    for theme in dark light; do
      for variant in plain name; do
        out="$id-$theme-$variant.png"
        render "$variant" "$theme" "$OUTDIR/$out" "$id" && echo "✓ brands/private/backgrounds/$out"
      done
    done
  done
fi
