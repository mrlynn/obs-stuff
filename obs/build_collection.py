#!/usr/bin/env python3
"""
Build an OBS scene collection ("Social Media Kit") wired to the overlays in ../overlays.

    python3 obs/build_collection.py            # writes obs/Social-Media-Kit.json
    python3 obs/build_collection.py --install  # also copies it into OBS (quit OBS first)

Then in OBS: Scene Collection → Import → pick obs/Social-Media-Kit.json
(not needed with --install; just choose it from the Scene Collection menu).

Canvas: 1920×1080. Re-run after moving this folder — paths are absolute.
"""
import json
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OVER = ROOT / "overlays"
OUT = Path(__file__).resolve().parent / "Social-Media-Kit.json"
OBS_SCENES = Path.home() / "Library/Application Support/obs-studio/basic/scenes"
CANVAS_W, CANVAS_H = 1920, 1080
MAIN_CANVAS = "6c69626f-6273-4c00-9d88-c5136d61696e"  # OBS's fixed main-canvas UUID

# Layout for the "Screen + Cam" scene. Keep in sync with README (stack export uses these).
SCREEN_RECT = (48, 40, 1824, 1000)   # x, y, w, h  (screen is fit inside this box)
CAM_RECT = (1480, 640, 400, 400)     # rounded webcam bubble, bottom-right
CAM_RADIUS = 8   # keep in sync with camRadius in overlays/config.js

sources = []


def uid():
    return str(uuid.uuid4())


def source(name, sid, settings=None, filters=None, mixers=0, hotkeys=None):
    s = {
        "name": name,
        "uuid": uid(),
        "id": sid,
        "versioned_id": sid,
        "settings": settings or {},
        "mixers": mixers,
        "sync": 0,
        "flags": 0,
        "volume": 1.0,
        "balance": 0.5,
        "enabled": True,
        "muted": False,
        "hotkeys": hotkeys or {},
        "monitoring_type": 0,
        "private_settings": {},
    }
    if filters:
        s["filters"] = filters
    return s


def filt(name, fid, settings):
    f = source(name, fid, settings)
    f.pop("mixers", None)
    return f


def browser(name, file, w=CANVAS_W, h=CANVAS_H, restart=True):
    s = source(name, "browser_source", {
        "is_local_file": True,
        "local_file": str(OVER / file),
        "width": w,
        "height": h,
        "css": "",                       # don't let OBS's default CSS override page backgrounds
        "restart_when_active": restart,  # replays the intro animation on every scene switch
        "shutdown": False,
        "reroute_audio": False,
    })
    sources.append(s)
    return s


def item(src, iid, x=0, y=0, w=None, h=None, fit="none", crop=False, visible=True, locked=False):
    """fit: none | inner (letterbox inside box) | outer (fill box)."""
    bounds_type = {"none": 0, "inner": 2, "outer": 3}[fit]
    return {
        "name": src["name"],
        "source_uuid": src["uuid"],
        "visible": visible,
        "locked": locked,
        "rot": 0.0,
        "align": 5,               # top-left
        "bounds_type": bounds_type,
        "bounds_align": 0,        # center inside bounds
        "bounds_crop": crop,
        "crop_left": 0, "crop_top": 0, "crop_right": 0, "crop_bottom": 0,
        "id": iid,
        "group_item_backup": False,
        "pos": {"x": float(x), "y": float(y)},
        "scale": {"x": 1.0, "y": 1.0},
        "bounds": {"x": float(w or 0), "y": float(h or 0)},
        "scale_filter": "disable",
        "blend_method": "default",
        "blend_type": "normal",
        "show_transition": {"duration": 300},
        "hide_transition": {"duration": 300},
        "private_settings": {},
    }


def scene(name, items, key=None, toggles=None, filters=None):
    """key: OBS key name for Ctrl+Option+<key> scene hotkey. toggles: {item_id: key} show/hide hotkeys."""
    hotkeys = {"OBSBasic.SelectScene": []}
    if key:
        hotkeys["OBSBasic.SelectScene"] = [{"control": True, "alt": True, "key": key}]
    for it in items:
        k = (toggles or {}).get(it["id"])
        hotkeys[f"libobs.show_scene_item.{it['id']}"] = [{"control": True, "alt": True, "key": k}] if k else []
        hotkeys[f"libobs.hide_scene_item.{it['id']}"] = [{"control": True, "alt": True, "shift": True, "key": k}] if k else []
    s = source(name, "scene", {
        "id_counter": max([i["id"] for i in items] + [0]),
        "custom_size": False,
        "items": items,
    }, filters=filters, hotkeys=hotkeys)
    s["canvas_uuid"] = MAIN_CANVAS
    sources.append(s)
    return s


def existing_settings(source_id, required_key):
    """Reuse a device already chosen — the installed kit first, then any other collection."""
    installed = OBS_SCENES / OUT.name
    others = [f for f in sorted(OBS_SCENES.glob("*.json")) if f.name != OUT.name]
    for f in ([installed] if installed.exists() else []) + others:
        try:
            for s in json.loads(f.read_text()).get("sources", []):
                if s.get("id") == source_id and s.get("settings", {}).get(required_key):
                    return s["settings"]
        except Exception:
            pass
    return {}


def make_bubble_mask():
    """Canvas-sized alpha mask: opaque rounded square where the cam bubble sits."""
    path = OVER / "masks" / "cam-bubble-mask.png"
    x, y, w, h = CAM_RECT
    r = CAM_RADIUS
    cx, cy = x + w / 2, y + h / 2
    inside = (f"lte(hypot(max(0\\,abs(X-{cx})-({w/2}-{r}))\\,max(0\\,abs(Y-{cy})-({h/2}-{r})))\\,{r})")
    subprocess.run([
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "lavfi", "-i", f"color=black@0:s={CANVAS_W}x{CANVAS_H},format=rgba",
        "-frames:v", "1", "-update", "1",
        "-vf", f"geq=r=if({inside}\\,255\\,0):g=if({inside}\\,255\\,0):b=if({inside}\\,255\\,0):a=if({inside}\\,255\\,0)",
        str(path),
    ], check=True)
    return path


def build():
    path_mask = make_bubble_mask()

    # ── Inputs ───────────────────────────────────────────────
    cam = source("Camera", "macos-avcapture", existing_settings("macos-avcapture", "device"), mixers=255)
    sources.append(cam)

    screen = source("Screen", "screen_capture", existing_settings("screen_capture", "display_uuid")
                    or {"type": 0, "show_cursor": True, "show_hidden_windows": False})
    sources.append(screen)

    bg = browser("BG · Animated", "background.html", restart=False)
    lt = browser("Overlay · Lower Third", "lower-third.html")
    hook = browser("Overlay · Hook Title", "hook-title.html")
    cta = browser("Overlay · CTA Outro", "cta-outro.html")
    guides = browser("Guide · Safe Zones (hide when recording)", "safe-zones.html", restart=False)
    x, y, w, h = CAM_RECT
    ring = browser("Overlay · Cam Ring", "cam-frame.html", w, h, restart=False)

    # ── Nested "Cam Bubble" scene (rounded via canvas-sized mask) ──
    bubble = scene("[nested] Cam Bubble", [
        item(cam, 1, x, y, w, h, fit="outer", crop=True),
    ], filters=[filt("Rounded Mask", "mask_filter_v2", {
        "type": "mask_alpha_filter.effect",
        "image_path": str(path_mask),
    })])

    # ── Scenes (Ctrl+Option+1…4 to switch) ──────────────────
    scene("1 · Hook", [
        item(cam, 1, 0, 0, CANVAS_W, CANVAS_H, fit="outer", crop=True),
        item(hook, 2),
        item(guides, 3, visible=False),
    ], key="OBS_KEY_1")

    scene("2 · Talking Head", [
        item(cam, 1, 0, 0, CANVAS_W, CANVAS_H, fit="outer", crop=True),
        item(lt, 2),
        item(guides, 3, visible=False),
    ], key="OBS_KEY_2", toggles={2: "OBS_KEY_L", 3: "OBS_KEY_G"})

    sx, sy, sw, sh = SCREEN_RECT
    scene("3 · Screen + Cam", [
        item(bg, 1, locked=True),
        item(screen, 2, sx, sy, sw, sh, fit="inner"),
        item(bubble, 3),
        item(ring, 4, x, y),
        item(lt, 5, visible=False),
        item(guides, 6, visible=False),
    ], key="OBS_KEY_3", toggles={5: "OBS_KEY_L", 6: "OBS_KEY_G"})

    scene("4 · Outro CTA", [
        item(bg, 1, locked=True),
        item(cta, 2),
    ], key="OBS_KEY_4")

    # ── Mic with a voice chain: noise suppression → compressor → limiter ──
    mic = source("Mic", "coreaudio_input_capture", {"device_id": "default"}, mixers=255, filters=[
        filt("Noise Suppression", "noise_suppress_filter_v2", {"method": "rnnoise"}),
        filt("Compressor", "compressor_filter", {
            "ratio": 4.0, "threshold": -20.0, "attack_time": 6, "release_time": 60, "output_gain": 4.0,
        }),
        filt("Limiter", "limiter_filter", {"threshold": -1.5, "release_time": 60}),
    ])

    scenes = [s for s in sources if s["id"] == "scene" and not s["name"].startswith("[nested]")]
    return {
        "name": "Social Media Kit",
        "AuxAudioDevice1": mic,
        "sources": sources,
        "groups": [],
        "scene_order": [{"name": s["name"]} for s in scenes] + [{"name": bubble["name"]}],
        "current_scene": scenes[1]["name"],
        "current_program_scene": scenes[1]["name"],
        "current_transition": "Fade",
        "transition_duration": 250,
        "transitions": [],
        "quick_transitions": [],
        "saved_projectors": [],
        "preview_locked": False,
        "scaling_enabled": False,
        # Lua script that switches to "2 · Talking Head" on startup (see obs/startup-scene.lua)
        "modules": {"scripts-tool": [{"path": str(Path(__file__).resolve().parent / "startup-scene.lua"),
                                      "settings": {"scene": "2 · Talking Head", "start_virtualcam": False}}]},
    }


if __name__ == "__main__":
    data = build()
    OUT.write_text(json.dumps(data, indent=4))
    print(f"Wrote {OUT}")
    if "--install" in sys.argv:
        running = subprocess.run(["pgrep", "-x", "OBS"], capture_output=True).returncode == 0
        if running:
            sys.exit("OBS is running — quit it first, then re-run with --install.")
        OBS_SCENES.mkdir(parents=True, exist_ok=True)
        dest = OBS_SCENES / OUT.name
        shutil.copy(OUT, dest)
        print(f"Installed → {dest}\nOpen OBS → Scene Collection → Social Media Kit")
