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
  role: "Engineer at SpaceXAI · Developer Advocate · Advisor",
  handle: "@mlynn",
  website: "mlynn.org",
  tagline: "I help people build with data & AI.",   // shown on the "name" meeting backgrounds

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

  // ── Meetings (Google Meet / Zoom via OBS Virtual Camera) ──
  // These are defaults; change them live from the "Meeting Control" dock in OBS.
  meetingTitle: "Weekly sync",
  agenda: "",                 // e.g. "1 · Roadmap review"; empty hides the agenda bar
  countdownMinutes: 3,        // "Starting soon" length when no time is set in the dock
  brbMinutes: 5,              // "Be right back" length when no time is set in the dock
  brbNote: "Grabbing a coffee",
  showLocalTime: true,        // name tag shows your local time (helps other time zones)
  timeZone: "",               // IANA name like "America/New_York"; empty = this Mac's zone
  bookingUrl: "mlynn.org",    // shown on the meeting backgrounds
};
