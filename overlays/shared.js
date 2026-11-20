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
})();
