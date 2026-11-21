// Shared helpers for every overlay. No need to edit — change config.js instead.
(function () {
  const base = window.OVERLAY_CONFIG || {};

  // Per-source overrides: file.html#key=value&key2=value2 (or ?key=value)
  const params = new URLSearchParams(
    (location.hash.slice(1) || "") + "&" + (location.search.slice(1) || "")
  );
  // Brand profile (brands/private/brands.js, optional): #brand=<id> wins, else the
  // brand chosen in the Meeting Control dock, else none (personal config.js).
  const brands = window.OBSKIT_BRANDS || {};
  // A dock choice (stored, even "Personal" = "") wins; until one is made, use
  // OBSKIT_DEFAULT_BRAND from brands/private/brands.js, if set.
  const readStoredBrand = () => {
    let v = null;
    try { v = localStorage.getItem("obsKit.brand"); } catch (e) {}
    return v === null ? (window.OBSKIT_DEFAULT_BRAND || "") : v;
  };
  const storedBrand = readStoredBrand();
  const pinnedBrand = params.get("brand");
  const brandId = pinnedBrand !== null ? pinnedBrand : storedBrand;
  const brand = brands[brandId] || null;

  const cfg = Object.assign({}, base, brand || {});
  for (const [k, v] of params) if (k && k !== "brand") cfg[k] = v;
  cfg.brandId = brand ? brandId : "";
  window.CFG = cfg;

  // When the dock switches brand, reload so every color/font/logo is re-applied.
  if (pinnedBrand === null) {
    setInterval(() => {
      const now = readStoredBrand();
      if ((brands[now] ? now : "") !== cfg.brandId) location.reload();
    }, 1000);
  }

  // Fill an element with the brand logo <img>, or brandName text if there's no logo file.
  // opts.invert: true on light backgrounds (brand logos are white).
  window.brandMark = function (el, opts) {
    opts = opts || {};
    const src = opts.src || cfg.logo;
    const fallback = () => { el.textContent = opts.text !== undefined ? opts.text : (cfg.brandName || ""); el.classList.add("brand-text"); };
    if (!src) { fallback(); return; }
    const img = new Image();
    img.alt = cfg.brandName || "";
    img.className = "brand-logo";
    if (opts.invert) img.style.filter = "invert(1)";
    img.onerror = () => { img.remove(); fallback(); };
    el.textContent = "";
    el.appendChild(img);
    img.src = src;
  };

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
  const fontSpec = cfg.fontSpec || "ital,wght@0,400..700;1,400..700";
  if (cfg.font) families.push(`family=${encodeURIComponent(cfg.font)}:${fontSpec}`);
  if (cfg.monoFont && cfg.monoFont !== cfg.font) families.push(`family=${encodeURIComponent(cfg.monoFont)}`);
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
        localStorage.setItem("obsKit.brandSeen", document.title + "=" + (cfg.brandId || "personal"));
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

  // ── Calendar autopilot ────────────────────────────────────
  // tools/calendar ("ObsKit Calendar.app") writes ../state/calendar.js every minute while
  // OBS runs. Pages can't fetch() local files, so we re-load it as a <script> tag.
  const CAL_SRC = "../state/calendar.js";
  const SOON_WINDOW = 90 * 60e3;           // a "next" meeting counts when it starts within 90 min

  window.calendarNow = function (cal) {
    cal = cal || window.OBSKIT_CALENDAR || null;
    const now = Date.now();
    if (!cal) return { status: "missing", events: [], current: null, next: null, upcoming: null, stale: true };
    const events = (cal.events || []).filter((e) => e.end > now);
    const current = events.filter((e) => e.start <= now).sort((a, b) => b.start - a.start)[0] || null;
    const next = events.filter((e) => e.start > now).sort((a, b) => a.start - b.start)[0] || null;
    const soon = next && next.start - now <= SOON_WINDOW ? next : null;
    return {
      status: cal.status || "missing", generated: cal.generated || 0, events, current, next,
      upcoming: current || soon,                         // the meeting the overlays should talk about
      stale: !cal.generated || now - cal.generated > 5 * 60e3,
    };
  };

  window.watchCalendar = function (fn, everyMs) {
    let last = "";
    const load = () => {
      const s = document.createElement("script");
      s.src = CAL_SRC + "?t=" + Date.now();
      s.onload = s.onerror = () => {
        s.remove();
        const j = JSON.stringify(window.OBSKIT_CALENDAR || null);
        if (j !== last) { last = j; fn(calendarNow()); }
      };
      document.head.appendChild(s);
    };
    document.addEventListener("DOMContentLoaded", load);
    setInterval(load, everyMs || 15000);
  };

  // Combine dock state with the calendar. Dock values win for the meeting they were set
  // for (titleFor / agendaFor = that meeting's id); otherwise the calendar fills in.
  window.meetingView = function (state, cal) {
    state = state || {}; cal = cal || calendarNow();
    const now = Date.now();
    const auto = state.autopilot !== false && cal.status === "ok";
    const ev = auto ? cal.upcoming : null;
    const evId = ev ? ev.id : "";
    const view = { event: ev, autopilot: auto };

    // Title
    if (state.title && (state.titleFor || "") === evId) view.title = state.title;
    else if (ev) view.title = ev.title;
    else view.title = state.title || CFG.meetingTitle || "";

    // Countdown target: a manual timer wins while it's running; else the next meeting's start
    if (state.countdownTo && state.countdownTo > now) view.countdownTo = state.countdownTo;
    else if (auto && cal.next && cal.next.start - now <= SOON_WINDOW) view.countdownTo = cal.next.start;
    else view.countdownTo = null;

    // Agenda bar text
    const items = ev && ev.agenda ? ev.agenda : [];
    if ((state.agendaFor || "") === evId && typeof state.agenda === "string") {
      view.agenda = state.agenda;                         // set in the dock for this meeting
    } else if (ev && cal.current === ev && items.length && items.every((i) => i.minutes > 0)) {
      // Timed agenda ("Intros (5m)"): step through it as the meeting runs
      let t = (now - ev.start) / 60e3, idx = items.length - 1;
      for (let i = 0; i < items.length; i++) { if (t < items[i].minutes) { idx = i; break; } t -= items[i].minutes; }
      view.agenda = (idx + 1) + " · " + items[idx].text;
    } else if (!ev) {
      view.agenda = typeof state.agenda === "string" ? state.agenda : (CFG.agenda || "");
    } else {
      view.agenda = "";                                   // untimed agenda: pick items in the dock
    }
    return view;
  };
})();
