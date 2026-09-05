## 1. Foundation

- [x] 1.1 Self-host Schibsted Grotesk and Martian Mono (`app/assets/fonts`, `config/_fonts.scss`), retune colors and Bootstrap variables
- [x] 1.2 Shared materials: `.plate`, `.face`, `.quiet-link`, wall clock SVG styles

## 2. Landing page

- [x] 2.1 `pages/home.html.erb` with clock wall, shared-moment ruler, headline, stations, sample grid, notice list, close
- [x] 2.2 `components/clock_wall.js`: five clocks, visitor zone first, ruler, awake band, sweep-on-load, idempotent on `turbo:load`

## 3. App pages

- [x] 3.1 Navbar, footer, flashes, layout `<main>`
- [x] 3.2 Planning form, participation page (event panel, guest panel, visible switch label), grid materials, dashboard faces, Devise forms
- [x] 3.3 Remove Cloudinary URLs, videos, carousel and tab scripts, logo and avatar rasters; tighten CSP; update meta description

## 4. Verification

- [x] 4.1 Update tests for the new labels; Rails, system, JS tests and RuboCop green
- [x] 4.2 Screenshot round at 1440 and 412, one fix batch, one confirm round
- [x] 4.3 Finish review and DESIGN.md
