// ─────────────────────────────────────────────────────────────
//  EDIT THIS FILE to brand every overlay at once.
//  After saving, right-click a Browser Source in OBS → "Refresh".
//
//  Any value can also be overridden per-source by adding a hash to
//  the file path/URL, e.g.  lower-third.html#name=Guest%20Name&role=CTO
// ─────────────────────────────────────────────────────────────
window.OVERLAY_CONFIG = {
  // Identity
  name: "Michael Lynn",
  role: "Engineer at SpaceXAI · Developer Advocate",
  handle: "@mlynn",
  website: "mlynn.org",

  // Hook card (first 2–3 seconds of a short-form video)
  hook: "Stop doing this in OBS",
  hookKicker: "Quick tip",

  // Outro / call to action
  cta: "Follow for more",
  ctaSub: "New videos every week",

  // Brand colors (from mlynn.org)
  accent: "#E8C547",      // signature gold
  accent2: "#C9A52B",     // deeper gold (gradient end)
  ink: "#131512",         // near-black panels / background
  paper: "#E8E6DC",       // warm off-white text
  muted: "#A9A79D",       // secondary text

  // Typography (Google Font names; fall back to system fonts offline)
  font: "Familjen Grotesk",   // headlines + body
  monoFont: "Fragment Mono",  // small uppercase labels

  // Shape
  radius: 4,              // px corner radius for panels and buttons

  // Timing (seconds). 0 = stay on screen until the source is hidden.
  lowerThirdHoldSeconds: 6,
  lowerThirdAlign: "left", // "center" keeps it inside a 9:16 crop of a 16:9 recording
  hookHoldSeconds: 0,

  // Webcam frame
  camRadius: 8,           // px corner radius (matches masks/cam-bubble-mask.png)
  camBorder: 3,           // px border thickness
};
