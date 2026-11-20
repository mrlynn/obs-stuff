// Shared helpers for every overlay. No need to edit — change config.js instead.
(function () {
  const base = window.OVERLAY_CONFIG || {};

  // Per-source overrides: file.html#key=value&key2=value2 (or ?key=value)
  const params = new URLSearchParams(
    (location.hash.slice(1) || "") + "&" + (location.search.slice(1) || "")
  );
  const cfg = Object.assign({}, base);
  for (const [k, v] of params) if (k) cfg[k] = v;
  window.CFG = cfg;

  // Theme → CSS variables
  const root = document.documentElement.style;
  root.setProperty("--accent", cfg.accent);
  root.setProperty("--accent2", cfg.accent2);
  root.setProperty("--ink", cfg.ink);
  root.setProperty("--paper", cfg.paper);
  root.setProperty("--muted", cfg.muted || cfg.paper);
  root.setProperty("--radius", (cfg.radius ?? 4) + "px");
  root.setProperty("--mono", `"${cfg.monoFont || "Fragment Mono"}", "SF Mono", Menlo, monospace`);
  root.setProperty("--font", `"${cfg.font}", -apple-system, "SF Pro Display", "Helvetica Neue", Arial, sans-serif`);
  root.setProperty("--cam-radius", (cfg.camRadius ?? 28) + "px");
  root.setProperty("--cam-border", (cfg.camBorder ?? 6) + "px");

  // Load the font (silently ignored when offline)
  const families = [];
  if (cfg.font) families.push(`family=${encodeURIComponent(cfg.font)}:ital,wght@0,400..700;1,400..700`);
  if (cfg.monoFont) families.push(`family=${encodeURIComponent(cfg.monoFont)}`);
  if (families.length) {
    const l = document.createElement("link");
    l.rel = "stylesheet";
    l.href = `https://fonts.googleapis.com/css2?${families.join("&")}&display=swap`;
    document.head.appendChild(l);
  }

  // Fill [data-cfg="key"] elements with config text
  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll("[data-cfg]").forEach((el) => {
      const v = cfg[el.dataset.cfg];
      if (v === undefined || v === "") el.hidden = true;
      else el.textContent = v;
    });
  });

  // Play/replay an animation each time OBS shows the source.
  // Pass a function that receives `true` (show) or `false` (hide).
  window.onObsShow = function (fn) {
    let shown = false;
    const set = (v) => { if (v !== shown) { shown = v; fn(v); } };
    window.addEventListener("obsSourceVisibleChanged", (e) => set(!!e.detail.visible));
    window.addEventListener("obsSourceActiveChanged", (e) => set(!!e.detail.active));
    // Also play on load (outside OBS, or when "Refresh when scene becomes active" is on)
    document.addEventListener("DOMContentLoaded", () => setTimeout(() => set(true), 150));
    // Click anywhere to replay (handy in the gallery preview / OBS "Interact")
    document.addEventListener("click", () => { set(false); setTimeout(() => set(true), 450); });
  };

  window.holdThenHide = function (seconds, hide) {
    const s = Number(seconds) || 0;
    if (s > 0) return setTimeout(hide, s * 1000);
    return null;
  };

  // ── Live meeting state ────────────────────────────────────
  // meeting-control.html (an OBS dock) writes this; meeting overlays read it.
  // Shape: { title, agenda, countdownTo (epoch ms), brbUntil (epoch ms), brbNote, updated }
  // Falls back to config.js defaults when nothing has been set yet.
  const KEY = "obsKit.meeting";
  const chan = ("BroadcastChannel" in window) ? new BroadcastChannel("obsKit") : null;

  window.readMeeting = function () {
    let s = {};
    try { s = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) {}
    return s;
  };
  window.writeMeeting = function (patch) {
    const next = Object.assign(readMeeting(), patch, { updated: Date.now() });
    try { localStorage.setItem(KEY, JSON.stringify(next)); } catch (e) {}
    if (chan) chan.postMessage(next);
    return next;
  };
  // Calls fn(state) now and whenever the state changes. Three paths, because OBS's
  // browser sources and docks are separate processes: BroadcastChannel, the storage
  // event, and a 500 ms poll of shared localStorage as a backstop.
  window.watchMeeting = function (fn) {
    let last = "";
    const emit = (s) => { const j = JSON.stringify(s); if (j !== last) { last = j; fn(s); } };
    document.addEventListener("DOMContentLoaded", () => emit(readMeeting()));
    if (chan) chan.onmessage = (e) => emit(e.data || {});
    window.addEventListener("storage", (e) => { if (e.key === KEY) emit(readMeeting()); });
    setInterval(() => emit(readMeeting()), 500);
    // Heartbeats so the dock can show which overlays it can reach, and overlays can
    // log (to the OBS log) once they can see the dock.
    let dockLogged = false;
    setInterval(() => {
      try {
        localStorage.setItem("obsKit.seen." + document.title, String(Date.now()));
        const d = Number(localStorage.getItem("obsKit.dock") || 0);
        if (!dockLogged && Date.now() - d < 5000) { dockLogged = true; console.log("[obsKit] " + document.title + " linked to Meeting Control dock"); }
      } catch (e) {}
    }, 2000);
  };

  // "4:05" style formatting for countdowns
  window.fmtClock = function (ms) {
    const t = Math.max(0, Math.ceil(ms / 1000));
    const m = Math.floor(t / 60), s = t % 60;
    return m + ":" + String(s).padStart(2, "0");
  };
})();
