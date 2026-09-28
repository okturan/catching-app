## Why

The 2021 look leaned on a carousel of three videos and eight images hosted on a third-party Cloudinary account the project does not control, on Google-hosted fonts, and on a glass-blur grid that hid the product's one real asset: the painted time grid. PRODUCT.md records the name, domain and tagline as binding and everything else as open. The product now has a guest-first model; its face should say so in one look.

## What Changes

- Replace the visual world with the "Newsroom Clock Wall": a painted wall, white glass clock faces, black hands, one red second hand, enamel city plates with white engraved caps, self-hosted Schibsted Grotesk for words and Martian Mono for every time. No gradients, no blur, no external imagery.
- New landing page: five live clocks (visitor's zone first) over enamel plates, a draggable shared-moment ruler whose yellow band marks the hours when all five cities are awake, the tagline as the display headline, one sentence, one "Plan a meeting" plate, a quiet lost-link link, then four stations, an authored sample grid, a plain list of what is true, and a close.
- Restyle every app page in the same world: navbar and footer as plates on a rail, the planning form and participation page on white faces, enamel day headers and mono row labels on the grid, enamel painted cells and yellow consensus, dashboard as event faces without tabs or promo filler, Devise forms on one face.
- Remove every Cloudinary URL, the three videos, the carousel and tab scripts, the logo and avatar rasters, and tighten the CSP to `self` for fonts, images and media.
- Copy: sentence-case navigation ("Log in", "Sign up", "Sign out", "My events", "Plan a meeting"), the organizer form submits with "Send me my organizer link" (or "Plan it" when signed in).

## Capabilities

### New Capabilities

- `visual-world`: the materials, type, colors, motion and copy rules every surface follows, and the landing page's first viewport.

### Modified Capabilities

(none; grid, participation and mail contracts are unchanged)

## Impact

Views, stylesheets, `application.js` and one new component (`clock_wall.js`), `app/assets/fonts/*`, CSP, `config/meta.yml`, four tests that named old labels. DESIGN.md is created; PRODUCT.md is unchanged.
