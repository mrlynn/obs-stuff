#!/usr/bin/env python3
"""
ObsKit phone remote: a tiny local server (standard library only) that lets your phone drive the
meeting overlays and switch OBS scenes during a call.

    python3 tools/remote/server.py [--port 8777]

The OBS startup script starts it for the Meetings collection (Tools → Scripts → "Phone remote").

Routes
  /r/<token>/              phone remote page            (secret link; open it via the dock's QR code)
  /r/<token>/state         GET merged state · POST a JSON patch (title, agenda, brbUntil, …)
  /r/<token>/scene         POST {"scene": "M4 · Be Right Back"} → OBS switches (via state/remote-cmd.json)
  /local/state.js          overlays poll this (localhost only, no token)
  /local/state             dock/overlays POST their changes here (localhost only)
  /local/info              phone link for the dock's QR code (localhost only)
  /local/action            POST {"action": "brb"|"back"|"soon"|"next"|"prev"|"clear", "minutes": 5} (OBS hotkeys)

Everything lives in state/ (gitignored): remote-token, meeting-remote.json, remote-cmd.json,
and obs.json (current scene + scene list, written by the OBS script).
"""
import argparse
import json
import os
import secrets
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "state"
PAGE = Path(__file__).resolve().parent / "remote.html"
LOCK = threading.Lock()

# Fields the phone/dock may set. Anything else in a patch is ignored.
ALLOWED = {"title", "titleFor", "agenda", "agendaFor", "items", "countdownTo", "brbUntil", "brbNote", "autopilot", "brand"}


def atomic_write(path, text):
    tmp = path.with_name("." + path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def read_json(path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default


def token():
    STATE.mkdir(exist_ok=True)
    f = STATE / "remote-token"
    if not f.exists():
        atomic_write(f, secrets.token_urlsafe(9))
        os.chmod(f, 0o600)
    return f.read_text().strip()


def lan_ip():
    # Prefer the Wi-Fi/Ethernet address (en0/en1) over a VPN tunnel
    for iface in ("en0", "en1"):
        try:
            ip = os.popen(f"ipconfig getifaddr {iface} 2>/dev/null").read().strip()
            if ip:
                return ip
        except Exception:
            pass
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except Exception:
        return "127.0.0.1"
    finally:
        s.close()


def get_state():
    return read_json(STATE / "meeting-remote.json", {})


def write_mirror(s):
    # OBS browser sources can't reach localhost (Chromium Private Network Access), but they can
    # load local files next to them — so overlays inside OBS read this file instead.
    atomic_write(STATE / "meeting-remote.js", "window.OBSKIT_REMOTE = " + json.dumps(s, ensure_ascii=False) + ";\n")


def patch_state(patch, origin):
    clean = {k: v for k, v in (patch or {}).items() if k in ALLOWED}
    if not clean:
        return get_state()
    with LOCK:
        s = get_state()
        s.update(clean)
        s["updated"] = int(time.time() * 1000)
        s["by"] = origin
        atomic_write(STATE / "meeting-remote.json", json.dumps(s, ensure_ascii=False))
        write_mirror(s)
    return s


def obs_info():
    return read_json(STATE / "obs.json", {"scenes": [], "scene": "", "at": 0})


def send_scene(name):
    info = obs_info()
    if info.get("scenes") and name not in info["scenes"]:
        return False                                      # only scenes OBS reported
    with LOCK:
        cmd = read_json(STATE / "remote-cmd.json", {"seq": 0})
        cmd = {"seq": int(cmd.get("seq", 0)) + 1, "scene": name, "at": int(time.time() * 1000)}
        atomic_write(STATE / "remote-cmd.json", json.dumps(cmd, ensure_ascii=False))
    return True


def find_scene(pattern, fallback_first=False):
    import re
    scenes = [s for s in obs_info().get("scenes", []) if not s.startswith("[")]
    for s in scenes:
        if re.search(pattern, s, re.I):
            return s
    return scenes[0] if (fallback_first and scenes) else ""


def run_action(action, minutes=None):
    """Meeting actions for OBS hotkeys (and anything else on this Mac)."""
    now = int(time.time() * 1000)
    s = get_state()
    items = [f"{i + 1} · {t}" for i, t in enumerate(s.get("items") or [])]
    if action == "brb":
        patch_state({"brbUntil": now + int(minutes or 5) * 60_000}, "hotkey")
        scene = find_scene(r"be right back|\bbrb\b")
    elif action == "back":
        patch_state({"brbUntil": 0}, "hotkey")
        scene = find_scene(r"\bcam\b", fallback_first=True)
    elif action == "soon":
        patch_state({"countdownTo": now + int(minutes or 3) * 60_000}, "hotkey")
        scene = find_scene(r"starting soon")
    elif action in ("next", "prev"):
        if not items:
            return {"ok": False, "error": "no agenda items"}
        i = items.index(s["agenda"]) if s.get("agenda") in items else (-1 if action == "next" else 0)
        i = (i + (1 if action == "next" else -1)) % len(items)
        patch_state({"agenda": items[i], "agendaFor": s.get("agendaFor", "")}, "hotkey")
        scene = ""
    elif action == "clear":
        patch_state({"agenda": "", "agendaFor": s.get("agendaFor", "")}, "hotkey")
        scene = ""
    else:
        return {"ok": False, "error": "unknown action"}
    if scene:
        send_scene(scene)
    return {"ok": True, "scene": scene}


class Handler(BaseHTTPRequestHandler):
    server_version = "ObsKitRemote/1"

    def log_message(self, fmt, *args):                   # quiet: no request logging
        pass

    def is_local(self):
        return self.client_address[0] in ("127.0.0.1", "::1")

    def reply(self, code, body=b"", ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        elif isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")   # overlays are file:// pages
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body_json(self):
        n = min(int(self.headers.get("Content-Length") or 0), 64_000)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return None

    def route(self):
        path = urlparse(self.path).path
        tok = token()
        if path.startswith("/r/"):
            parts = path.split("/")                        # ['', 'r', token, rest...]
            if len(parts) < 3 or not secrets.compare_digest(parts[2], tok):
                return "deny", ""
            return "phone", "/" + "/".join(parts[3:])
        if path.startswith("/local/"):
            return ("local" if self.is_local() else "deny"), path[len("/local"):]
        return "deny", ""

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.end_headers()

    def do_GET(self):
        kind, sub = self.route()
        if kind == "deny":
            return self.reply(404, {"error": "not found"})
        if kind == "phone" and sub in ("/", ""):
            return self.reply(200, PAGE.read_bytes(), "text/html")
        if kind == "phone" and sub == "/state":
            return self.reply(200, {"state": get_state(), "obs": obs_info(), "now": int(time.time() * 1000)})
        if kind == "local" and sub == "/state.js":
            js = "window.OBSKIT_REMOTE = " + json.dumps(get_state(), ensure_ascii=False) + ";"
            return self.reply(200, js, "application/javascript")
        if kind == "local" and sub == "/info":
            port = self.server.server_address[1]
            return self.reply(200, {"url": f"http://{lan_ip()}:{port}/r/{token()}/", "obs": obs_info()})
        return self.reply(404, {"error": "not found"})

    def do_POST(self):
        kind, sub = self.route()
        if kind == "deny":
            return self.reply(404, {"error": "not found"})
        data = self.body_json()
        if data is None:
            return self.reply(400, {"error": "bad json"})
        if sub == "/state":
            return self.reply(200, {"state": patch_state(data, "phone" if kind == "phone" else "dock")})
        if kind == "phone" and sub == "/scene":
            ok = send_scene(str(data.get("scene", "")))
            return self.reply(200 if ok else 400, {"ok": ok})
        if kind == "local" and sub == "/action":          # OBS hotkeys (localhost only)
            res = run_action(str(data.get("action", "")), data.get("minutes"))
            return self.reply(200 if res.get("ok") else 400, res)
        return self.reply(404, {"error": "not found"})


def main():
    ap = argparse.ArgumentParser(description="ObsKit phone remote server")
    ap.add_argument("--port", type=int, default=8777)
    a = ap.parse_args()
    STATE.mkdir(exist_ok=True)
    token()
    write_mirror(get_state())
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Handler)
    atomic_write(STATE / f"remote-server-{a.port}.pid", str(os.getpid()))   # one per port
    print(f"ObsKit remote on port {a.port}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
