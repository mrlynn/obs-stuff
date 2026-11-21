#!/usr/bin/env python3
"""
Build the "Meetings" OBS scene collection: scenes for Google Meet / Zoom, sent through
OBS's Virtual Camera. Separate from "Social Media Kit", so your recording setup is untouched.

    python3 obs/build_meetings.py            # writes obs/Meetings.json
    python3 obs/build_meetings.py --install  # copies it into OBS and adds the Meeting Control dock
                                             # (quit OBS first)

Then: OBS → Scene Collection → Meetings → Start Virtual Camera,
and pick "OBS Virtual Camera" as the camera in Meet / Zoom.
"""
import json
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

import build_collection as bc   # reuse helpers: source(), browser(), item(), scene(), masks, device lookup

OUT = Path(__file__).resolve().parent / "Meetings.json"
OBS_DIR = Path.home() / "Library/Application Support/obs-studio"
DOCK_TITLE = "Meeting Control"


# Default bindings for the startup script's meeting hotkeys (rebind in OBS Settings → Hotkeys).
# They work while Zoom / Meet / Teams has focus (OBS needs Input Monitoring permission).
def _key(k):
    return [{"control": True, "alt": True, "key": k}]


MEETING_HOTKEYS = {
    "obskit.brb": _key("OBS_KEY_B"),          # ⌃⌥B  be right back (5 min)
    "obskit.back": _key("OBS_KEY_C"),         # ⌃⌥C  I'm back → camera
    "obskit.soon": _key("OBS_KEY_S"),         # ⌃⌥S  starting soon (3 min)
    "obskit.next": _key("OBS_KEY_RIGHT"),     # ⌃⌥→  next agenda item
    "obskit.prev": _key("OBS_KEY_LEFT"),      # ⌃⌥←  previous agenda item
    "obskit.clear": _key("OBS_KEY_BACKSPACE"),  # ⌃⌥⌫  clear agenda bar
    "obskit.reload": [{"control": True, "alt": True, "shift": True, "key": "OBS_KEY_R"}],  # ⌃⌥⇧R  refresh overlays
}


def build():
    bc.sources = []                      # fresh source list for this collection
    mask = bc.make_bubble_mask()         # same rounded bubble as the recording kit

    cam = bc.source("Camera", "macos-avcapture", bc.existing_settings("macos-avcapture", "device"), mixers=0)
    bc.sources.append(cam)
    screen = bc.source("Screen", "screen_capture", bc.existing_settings("screen_capture", "display_uuid")
                       or {"type": 0, "show_cursor": True, "show_hidden_windows": False})
    bc.sources.append(screen)

    bg = bc.browser("BG · Animated", "background.html", restart=False)
    tag = bc.browser("Meeting · Name Tag", "meeting-nametag.html", restart=False)
    agenda = bc.browser("Meeting · Agenda Bar", "meeting-agenda.html", restart=False)
    countdown = bc.browser("Meeting · Starting Soon", "meeting-countdown.html")
    brb = bc.browser("Meeting · Be Right Back", "meeting-brb.html")
    guide = bc.browser("Guide · Meeting Safe Zones (hide in calls)", "meeting-safe-zones.html", restart=False)
    x, y, w, h = bc.CAM_RECT
    ring = bc.browser("Overlay · Cam Ring", "cam-frame.html", w, h, restart=False)

    bubble = bc.scene("[nested] Cam Bubble", [
        bc.item(cam, 1, x, y, w, h, fit="outer", crop=True),
    ], filters=[bc.filt("Rounded Mask", "mask_filter_v2", {
        "type": "mask_alpha_filter.effect", "image_path": str(mask),
    })])

    W, H = bc.CANVAS_W, bc.CANVAS_H
    sx, sy, sw, sh = bc.SCREEN_RECT
    # ⌃⌥1…4 switch scenes. ⌃⌥A / ⌃⌥N / ⌃⌥G show agenda / name tag / guide (add ⇧ to hide).
    bc.scene("M1 · Cam", [
        bc.item(cam, 1, 0, 0, W, H, fit="outer", crop=True),
        bc.item(tag, 2),
        bc.item(agenda, 3),
        bc.item(guide, 4, visible=False),
    ], key="OBS_KEY_1", toggles={2: "OBS_KEY_N", 3: "OBS_KEY_A", 4: "OBS_KEY_G"})

    bc.scene("M2 · Present", [
        bc.item(bg, 1, locked=True),
        bc.item(screen, 2, sx, sy, sw, sh, fit="inner"),
        bc.item(bubble, 3),
        bc.item(ring, 4, x, y),
        bc.item(agenda, 5),
        bc.item(guide, 6, visible=False),
    ], key="OBS_KEY_2", toggles={5: "OBS_KEY_A", 6: "OBS_KEY_G"})

    bc.scene("M3 · Starting Soon", [
        bc.item(bg, 1, locked=True),
        bc.item(countdown, 2),
        bc.item(bubble, 3),
        bc.item(ring, 4, x, y),
    ], key="OBS_KEY_3")

    bc.scene("M4 · Be Right Back", [
        bc.item(bg, 1, locked=True),
        bc.item(brb, 2),
    ], key="OBS_KEY_4")

    scenes = [s for s in bc.sources if s["id"] == "scene" and not s["name"].startswith("[nested]")]
    return {
        "name": "Meetings",
        "sources": bc.sources,
        "groups": [],
        "scene_order": [{"name": s["name"]} for s in scenes] + [{"name": bubble["name"]}],
        "current_scene": "M1 · Cam",
        "current_program_scene": "M1 · Cam",
        "current_transition": "Fade",
        "transition_duration": 250,
        "transitions": [],
        "quick_transitions": [],
        "saved_projectors": [],
        "preview_locked": False,
        "scaling_enabled": False,
        # The Virtual Camera has no audio, so this collection has no mic: Meet/Zoom use your mic directly.
        "modules": {"scripts-tool": [{
            "path": str(Path(__file__).resolve().parent / "startup-scene.lua"),
            # Starts the Virtual Camera on launch (needs the camera extension approved in System Settings)
            "settings": {"scene": "M1 · Cam", "start_virtualcam": True,
                         "calendar_autopilot": False, "calendar_switch": True, "lead_minutes": 3,
                         "phone_remote": True, "remote_port": 8777, **MEETING_HOTKEYS},
        }]},
    }


def add_dock():
    """Add the Meeting Control page as an OBS Custom Browser Dock (user.ini → ExtraBrowserDocks)."""
    ini = OBS_DIR / "user.ini"
    if not ini.exists():
        print("! user.ini not found — add the dock by hand: Docks → Custom Browser Docks…")
        return
    text = ini.read_text()
    url = (bc.OVER / "meeting-control.html").as_uri()
    lines, out, found = text.splitlines(), [], False
    for line in lines:
        if line.startswith("ExtraBrowserDocks="):
            found = True
            try:
                docks = json.loads(line.split("=", 1)[1] or "[]")
            except json.JSONDecodeError:
                docks = []
            docks = [d for d in docks if d.get("title") != DOCK_TITLE]
            docks.append({"title": DOCK_TITLE, "url": url, "uuid": str(uuid.uuid4())})
            line = "ExtraBrowserDocks=" + json.dumps(docks, ensure_ascii=False, separators=(",", ":"))
        out.append(line)
    if not found:
        print("! no ExtraBrowserDocks entry in user.ini — add the dock by hand: Docks → Custom Browser Docks…")
        return
    shutil.copy(ini, ini.with_name("user.ini.bak-meetings"))
    ini.write_text("\n".join(out) + "\n")
    print(f"Added dock '{DOCK_TITLE}' → {url}")


if __name__ == "__main__":
    data = build()
    OUT.write_text(json.dumps(data, indent=4, ensure_ascii=False))
    print(f"Wrote {OUT}")
    if "--install" in sys.argv:
        if subprocess.run(["pgrep", "-x", "OBS"], capture_output=True).returncode == 0:
            sys.exit("OBS is running — quit it first, then re-run with --install.")
        dest = bc.OBS_SCENES / OUT.name
        bc.OBS_SCENES.mkdir(parents=True, exist_ok=True)
        shutil.copy(OUT, dest)
        print(f"Installed → {dest}")
        add_dock()
        print("Open OBS → Scene Collection → Meetings")
