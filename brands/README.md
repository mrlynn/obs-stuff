# Brand profiles

Overlays use `overlays/config.js` (your personal brand) by default. A **brand profile**
overrides any of those values (colors, fonts, corner radius, logo, role line) so the same
overlays, meeting scenes and backgrounds can switch to an employer or client brand.

Company brands usually can't be published, so profiles live in **`brands/private/`**, which
is gitignored. The public repo works fine without it: the brand switcher just isn't shown.

## Add a profile

1. Create `brands/private/brands.js` (copy `brands/example.js`).
2. Put official logo files in `brands/private/logos/`. Use the company's own artwork,
   e.g. from its brand kit or official templates. Don't redraw logos.
3. Reload the gallery (`overlays/index.html`). The brand buttons appear at the top.

## Switch brands

- **OBS:** click a brand in the **Meeting Control** dock. Every overlay reloads in that brand.
- **Default:** set `window.OBSKIT_DEFAULT_BRAND = "<id>"` in `brands/private/brands.js`. It applies
  until a brand button in the dock is clicked. A click, including **Personal**, always wins.
- **One source only:** add `#brand=<id>` to a page URL, e.g. `meeting-brb.html#brand=acme`.
- **Meet / Zoom backgrounds:** `meeting-backgrounds/render.sh` also renders every private
  brand into `brands/private/backgrounds/`.
