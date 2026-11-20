// Template for brands/private/brands.js (that folder is gitignored).
// Copy this file to brands/private/brands.js and replace the example values with the
// official ones from your company's brand kit. Logos go in brands/private/logos/.
(function () {
  const base = document.currentScript ? new URL(".", document.currentScript.src).href : "";
  const logo = (f) => base + "logos/" + f;

  window.OBSKIT_BRANDS = {
    "acme": {
      label: "Acme",                 // button text in the dock / gallery
      brandName: "Acme",             // plain-text fallback when the logo file is missing
      role: "Engineer · Acme",       // overrides the role line
      handle: "",                    // "" hides your personal handle
      website: "",
      accent: "#FF5A1F", accent2: "#FFB000",
      ink: "#0E0E10", paper: "#FFFFFF", muted: "#9A9AA3",
      font: "Inter", monoFont: "Inter",
      fontSpec: "wght@400;500;600;700",   // Google Fonts axes for `font`
      radius: 8, camRadius: 16,
      logo: logo("acme-logo.png"),   // white/light logo; inverted automatically on light backgrounds
      signoff: "",                   // optional parent-company mark for corners
      palette: [],                   // optional extra brand colors for backgrounds
    },
  };
})();
