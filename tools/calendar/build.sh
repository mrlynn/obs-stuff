#!/usr/bin/env bash
# Build "ObsKit Calendar.app": a tiny background app (no Dock icon) that reads today's meetings
# from macOS Calendar and writes state/calendar.json + state/calendar.js for the overlays.
# It's an app rather than a script so macOS can ask once for Calendar access and remember it.
#
#   tools/calendar/build.sh          # builds tools/calendar/build/ObsKit Calendar.app
#   tools/calendar/build.sh --run    # builds, then runs it once (first run asks for Calendar access)
set -euo pipefail
cd "$(dirname "$0")"
APP="build/ObsKit Calendar.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.obskit.calendar</string>
  <key>CFBundleName</key><string>ObsKit Calendar</string>
  <key>CFBundleExecutable</key><string>obskit-calendar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>ObsKit Calendar shows your next meeting's title, start time and agenda on your OBS meeting overlays. Links, passcodes and attendee details are never shown.</string>
</dict></plist>
PLIST

swiftc -O -o "$APP/Contents/MacOS/obskit-calendar" ObsKitCalendar.swift -framework EventKit
codesign --force --sign - "$APP" >/dev/null
echo "Built $(pwd)/$APP"

if [ "${1:-}" = "--run" ]; then
  STATE="$(cd ../.. && pwd)/state"
  open -n -W -g -j "$APP" --args --out "$STATE"
  echo "Wrote $STATE/calendar.json:"; python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print('status:',d['status'],'· events:',len(d['events']))" "$STATE/calendar.json"
fi
