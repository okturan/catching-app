---
name: Catching App
description: A newsroom clock wall that shows one instant five ways, so friends across time zones find their hour.
colors:
  wall: "#f2efe9"
  wall-deep: "#e6e1d6"
  face: "#ffffff"
  ink: "#141414"
  ink-soft: "#4a4744"
  hairline: "rgba(20, 20, 20, 0.14)"
  enamel: "#24405e"
  enamel-deep: "#1a2f47"
  enamel-text: "#ffffff"
  enamel-half: "#8796a6"
  enamel-wash: "#c8cfd7"
  signal: "#d7262a"
  awake: "#ffc65a"
  awake-deep: "#e0a52b"
  awake-wash: "#ffe5b5"
  success: "#1a7f4b"
typography:
  display:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(2.4rem, 6.2vw, 5.6rem)"
    fontWeight: 800
    lineHeight: 0.98
    letterSpacing: "-0.035em"
  headline:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.6rem, 3vw, 2.4rem)"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "1.25rem"
    fontWeight: 800
    lineHeight: 1.2
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "1rem"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "ss01"
  lede:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(1.05rem, 1.4vw, 1.25rem)"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Schibsted Grotesk, Helvetica Neue, Arial, sans-serif"
    fontSize: "0.8rem"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.12em"
  time:
    fontFamily: "Martian Mono, ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "1.05rem"
    fontWeight: 500
    lineHeight: 1.15
    letterSpacing: "0.04em"
    fontVariation: "tabular-nums"
  time-small:
    fontFamily: "Martian Mono, ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.3
    fontVariation: "tabular-nums"
rounded:
  sm: "3px"
  md: "4px"
  lg: "6px"
  pill: "30px"
spacing:
  cell: "4px"
  xs: "0.5rem"
  sm: "0.75rem"
  md: "1rem"
  lg: "1.5rem"
  xl: "2.5rem"
  gutter: "clamp(1rem, 4vw, 2.5rem)"
  face-pad: "clamp(1rem, 2.5vw, 1.75rem)"
  section: "clamp(2.5rem, 6vw, 5rem)"
components:
  plate:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.enamel-text}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0.45em 1em"
  plate-ink:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.enamel-text}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0.45em 1em"
  plate-button:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.enamel-text}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0.7em 1.4em"
  plate-button-hover:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.enamel-text}"
  button-outline:
    backgroundColor: "{colors.face}"
    textColor: "{colors.enamel}"
    rounded: "{rounded.md}"
    padding: "0.65rem 1.25rem"
  face:
    backgroundColor: "{colors.face}"
    textColor: "{colors.ink}"
    rounded: "{rounded.lg}"
    padding: "{spacing.face-pad}"
  input:
    backgroundColor: "{colors.face}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
  nav-link:
    textColor: "{colors.ink}"
    padding: "0.4rem 0"
  quiet-link:
    textColor: "{colors.ink-soft}"
  grid-header:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.enamel-text}"
    rounded: "{rounded.sm}"
    padding: "0.55em 0.9em"
  grid-cell-offered:
    backgroundColor: "{colors.face}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "34px"
  grid-cell-inactive:
    backgroundColor: "{colors.wall}"
    rounded: "{rounded.sm}"
    height: "34px"
  grid-cell-painted:
    backgroundColor: "{colors.enamel}"
    textColor: "{colors.enamel-text}"
    rounded: "{rounded.sm}"
    height: "34px"
  grid-cell-consensus:
    backgroundColor: "{colors.awake-wash}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "34px"
  grid-cell-consensus-painted:
    backgroundColor: "{colors.awake}"
    textColor: "{colors.ink}"
    rounded: "{rounded.sm}"
    height: "34px"
  alert-info:
    backgroundColor: "{colors.face}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
  alert-warning:
    backgroundColor: "{colors.awake-wash}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
---

# Design System: Catching App

## Overview

**Creative North Star: "The Newsroom Clock Wall"**

Every surface is a wall in a newsroom: a warm painted plaster ground, a row of white glass wall clocks with black hands and one red second hand, and enamel-blue plates hung underneath naming the city. The landing page is that wall literally, with five synchronized clocks as the offer and the proof. The app surfaces (planning form, participation page, dashboard, Devise forms) are instruments hung on the same wall: white glass faces holding forms and grids, enamel plates as day headers and primary actions, and every time set in the mono face as if read off a dial.

The world is flat and physical rather than digital. Depth comes from real materials (a plate has an inset highlight and shade because enamel does; a face casts a soft shadow because glass sits proud of plaster; a clock hangs and throws a shadow down the wall), never from glass blur, gradients of any kind, or decorative shadows. Colour is disciplined: one blue for anything that can be pressed or that labels, one red for the second hand and the ruler thumb, one yellow for the hours when everyone is awake. Copy is playful and the layout is calm. The tagline "We have some catching app to do!" is the headline, set at display scale.

Confirmed rejections: the headline-plus-app-screenshot scheduler page, the 2021 carousel videos, every externally hosted image, glass blur, gradient surfaces, and invented testimonials or numbers.

**Key Characteristics:**
- Warm painted wall as ground, white glass faces as the only raised surface.
- Enamel-blue plates with white engraved caps, flat colour with one hairline bevel, for labels and primary actions.
- Two typefaces with strict jobs: Schibsted Grotesk for words, Martian Mono for every time.
- Red is reserved for the second hand, the ruler thumb, and destructive state; yellow marks consensus and awake hours.
- One authored motion: clock hands sweep from noon to now on load, disabled under reduced motion.
- Grids are painted, not ticked: white offered cells, enamel painted cells, yellow consensus.

## Colors

A painted wall, white glass, black ink, deep enamel, one red, one yellow.

### Primary
- **Enamel** (`{colors.enamel}`): the deep blue of an enamel plate. Every label plate, primary action, day header, painted grid cell, focus outline, checked toggle, and link. If it is blue, it is enamel.
- **Enamel Deep** (`{colors.enamel-deep}`): the same enamel in shadow. Link hover and the border of a painted cell.
- **Enamel Half / Enamel Wash** (`{colors.enamel-half}`, `{colors.enamel-wash}`): enamel at 55% and 25% over white glass. Only on the landing page sample grid, to show two friends and one friend. Precomputed so Sass emits no colour-function output.

### Secondary
- **Signal Red** (`{colors.signal}`): the second hand, the clock pin, the range thumb on the time ruler, the grid cell focus outline, and Bootstrap's danger. Never a fill for a panel.
- **Awake Yellow** (`{colors.awake}`): the painted band on the time ruler where every city is awake, the "everyone" cell in the sample grid, a consensus cell the viewer has also painted, and text selection.
- **Awake Deep** (`{colors.awake-deep}`): the border of a consensus cell and Bootstrap's warning.
- **Awake Wash** (`{colors.awake-wash}`): yellow at 45% over glass. Consensus cells not yet painted by the viewer, and warning flashes.

### Tertiary
- **Success Green** (`{colors.success}`): Bootstrap's success only. No component of the world paints with it.

### Neutral
- **Wall** (`{colors.wall}`): the painted plaster. Page background, navbar, theme-color meta, and the inactive grid cell.
- **Wall Deep** (`{colors.wall-deep}`): a shadowed band of the same wall. The stations rail and the footer.
- **Face** (`{colors.face}`): white glass. Every panel, form, offered grid cell, ruler track, clock face, and the text on enamel.
- **Ink** (`{colors.ink}`): near-black. Body text, clock hands and ticks, the navbar wordmark, the visitor's plate, the footer plate, headings.
- **Ink Soft** (`{colors.ink-soft}`): secondary text, ledes, captions, row labels, quiet links.
- **Hairline** (`{colors.hairline}`): the one border. Face edges, section rules, notice-list dividers, the nav and footer rules.

### Named Rules
**The One Blue Rule.** Enamel is the only chromatic colour a component may be made of. Red and yellow are marks, not materials: red is the moving hand and the thumb, yellow is a painted band or a cell. A red or yellow button does not exist in this world.

**The Wash Rule.** Tints are precomputed hex washes over white glass (enamel-wash, enamel-half, awake-wash), never runtime alpha over the wall. Alpha is used only for ink: hairlines, ring strokes, tick marks, and shadows.

## Typography

**Display Font:** Schibsted Grotesk (with Helvetica Neue, Arial, sans-serif)
**Body Font:** Schibsted Grotesk (with Helvetica Neue, Arial, sans-serif)
**Label/Mono Font:** Martian Mono (with ui-monospace, SF Mono, Menlo, monospace)

**Character:** A sturdy newspaper grotesk doing all the talking, set heavy and tight for headlines and plain for body, beside a wide, mechanical mono that reads like the numerals on a dial. Both are self-hosted variable fonts from `app/assets/fonts` (Schibsted Grotesk 400 to 900, Martian Mono 300 to 800), loaded with `font-display: swap`. The body enables the `ss01` stylistic set.

### Hierarchy
- **Display** (800, `clamp(2.4rem, 6.2vw, 5.6rem)`, line-height 0.98, tracking -0.035em): the tagline on the landing page only. Balanced wrapping.
- **Headline** (800, `clamp(1.6rem, 3vw, 2.4rem)`, tracking -0.02em): section headings on the landing page, page heads on app surfaces, the dashboard title (which runs slightly larger, to 2.6rem), the closing question.
- **Title** (800, 1.2 to 1.6rem): station headings, event panel names, card titles, form headings. Always 800; the world has no medium-weight heading.
- **Lede** (400, `clamp(1.05rem, 1.4vw, 1.25rem)`, line-height 1.5, ink-soft, max 62ch): the one sentence of offer under a heading.
- **Body** (400, 1rem, line-height 1.5): paragraphs, form labels at 600, notice-list items at 1.05rem with bold 800 leads.
- **Label** (700, 0.8rem, tracking 0.12em, uppercase): engraved plate text. Smaller plates step to 0.72rem (clock city), 0.75rem (grid day header, tracking 0.1em), 0.7rem (dashboard section plate) and 0.65rem (event state plate). Sample grid column heads use 0.7rem at 0.06em.
- **Time** (Martian Mono, tabular): 1.05rem on clock plates with 0.04em tracking; 0.95rem for a confirmed window; 0.9rem for a card's time; 12px at 500 for grid row labels; 0.75rem inside sample cells. Never uppercase, never letterspaced beyond 0.04em.

### Named Rules
**The Dial Rule.** Every time, offset, or clock reading is set in Martian Mono with tabular numerals. This includes `time` elements, grid row labels, ruler output, and the time on an event card. Words never appear in the mono face except a UTC offset abbreviation.

**The Heavy Heading Rule.** Headings are 800 with negative tracking and balanced wrap. There are no kickers, eyebrows, or overlines above a heading. A plate may sit inline after a heading only to state a fact about it (a "Set in stone" state, a count of events), never before it as a label.

## Layout

The page is a vertical wall. `html` and `body` are wall-coloured; `body` is a flex column so the footer sits at the bottom of short pages.

**Containers.** Landing sections and the nav and footer inner rail run to 1280px; landing content (clock row, ruler, claim, stations) narrows to 1120px; generic `wall-section` blocks to 1200px; the dashboard to 1000px; app work surfaces with a grid (plan, participation) widen to 1400px; single-column forms are `min(440px, 100%)`. Horizontal gutter is always `clamp(1rem, 4vw, 2.5rem)`.

**Rhythm.** Section padding is `clamp(2.5rem, 6vw, 5rem)` vertically. Inside a face, padding is `clamp(1rem, 2.5vw, 1.75rem)` (forms go to 2rem). Component gaps step 0.5rem, 0.75rem, 1rem, 1.5rem, 2.5rem. Grids use CSS grid with `gap`, never margins between siblings.

**Two-column work surfaces.** Plan and participation pages put the form or event card in a fixed left column (`minmax(300px, 400px)` or 420px) and the time grid in the remaining space, collapsing to one column at 900px. The landing claim is `1.4fr / 1fr`, collapsing at 800px; the sample section is `1fr / 1.3fr`, collapsing at 900px.

**Breakpoints observed.** 480px (stations go one column), 520px (event card stacks its time), 767.98px (Bootstrap nav collapse; the header wraps and the plate button shrinks to 0.7rem), 800px (claim and stations reflow), 900px (the clock row becomes a horizontally scrolling, scroll-snapping rail of all five clocks at `minmax(150px, 36vw)` each, bleeding into the gutter with the scrollbar hidden; work surfaces stack). All five clocks always ship; none is hidden on a phone. Touch is detected with `any-pointer: coarse`, not width: the paint-mode switch appears and the grid action bar sticks to the bottom.

**The grid.** Time grids are tables with `border-spacing: 4px`, sticky enamel day headers on top and sticky mono row labels on the left, scrolling inside a face whose max height is the viewport minus the navbar and action bar (96px each, as CSS custom properties). Slot rows are 34px, and on touch 44 / 36 / 28px for 60 / 30 / 15-minute slots. Cells are at least 120px wide (88px on touch).

## Elevation & Depth

Depth is material, not atmospheric. The wall is flat. A white face sits a millimetre proud of it with a hairline border and a soft two-part shadow. An enamel plate is a thin pressed sheet: an inset top highlight, an inset bottom shade, and a short drop. A wall clock hangs from the wall and throws a soft shadow downward. Hover lifts a plate or a face by one or two pixels and lengthens its shadow. Nothing blurs the background and nothing glows except the input focus ring.

### Shadow Vocabulary
- **Plate** (`inset 0 1px 0 rgba(255,255,255,0.28), inset 0 -1px 0 rgba(0,0,0,0.35), 0 2px 4px rgba(20,20,20,0.25)`): every plate and enamel grid header at rest.
- **Plate lifted** (`inset 0 1px 0 rgba(255,255,255,0.28), inset 0 -1px 0 rgba(0,0,0,0.35), 0 6px 12px -4px rgba(20,20,20,0.4)`): plate buttons on hover and focus, with `translateY(-1px)`.
- **Face** (`0 1px 2px rgba(20,20,20,0.06), 0 6px 18px -8px rgba(20,20,20,0.25)`): every white panel at rest.
- **Face lifted** (`0 1px 2px rgba(20,20,20,0.06), 0 12px 24px -12px rgba(20,20,20,0.35)`): clickable event faces on hover, with `translateY(-2px)`.
- **Hung clock** (`filter: drop-shadow(0 6px 8px rgba(20,20,20,0.16))`): the SVG wall clock, so it reads as an object hanging on the wall rather than a drawing on it.
- **Recessed track** (`inset 0 1px 3px rgba(20,20,20,0.12)`): the time ruler track, a groove in the glass.
- **Sticky bar** (`0 -6px 16px -10px rgba(20,20,20,0.35)`): the touch action bar when it sticks to the viewport bottom.
- **Focus ring** (`0 0 0 3px rgba(36,64,94,0.2)` on inputs; `outline: 3px solid enamel, offset 2px` everywhere else; grid cells outline in signal red).

### Named Rules
**The Hung-On Rule.** Depth exists only where a physical object would have it: plates, faces, and clocks. Text, wall bands, and the footer are flat. A shadow never appears on something that is not a plate, a face, or a clock.

**The Lift Rule.** Interactive objects rise on hover (1px for plates, 2px for faces) over 0.18s with the `cubic-bezier(0.16, 1, 0.3, 1)` ease, and settle back on press. Nothing else moves on hover.

## Shapes

Edges are barely rounded, like stamped metal and cut glass. Plates and grid cells use 3px; Bootstrap-derived inputs, alerts, buttons, the ruler track, and the paint-mode switch use 4px; white faces use 6px. The toggle is the one pill (30px track, round knob). Clocks are exact circles drawn in SVG on a 100-unit viewBox with a hairline outer ring, a 6-unit soft grey ring inside it, sixty round-capped ticks (majors 3 units wide), round-capped hands, and a red pin.

Plates carry no hardware and no gradient: no screw heads, rivets, or imitation fixings. A plate is flat enamel with a 1px inset highlight above, a 1px shade below, and a short drop shadow. The world has no gradient anywhere; the ruler's awake band is painted with hard colour stops, which is a painting technique, not a gradient look.

Borders are a single hairline of 14% ink. Inputs use a darker 28% ink stroke; grid cells 22% (45% when offered). Day boundaries inside the grid are a 2px dashed line at 35% ink. Nothing else is dashed.

## Components

### Buttons
- **Character:** an enamel plate you can press.
- **Shape:** stamped corners (3px), no border, uppercase engraved caps, no hardware.
- **Primary (`plate-button`, `btn-meeting`, `plate-button-sm`, form submit):** enamel on white text, 700, 0.12em tracking. Large plate buttons pad `0.7em 1.4em` at 0.95rem; `btn-meeting` pads `0.75em 1.5em` at 0.9rem; nav and inline plates use the base `0.45em 1em` at 0.8rem. Devise and lost-link submits are plate-sized (`0.85em 1.6em` at 0.85rem), never full width, and sit inside the same white face as their fields: the fields block and the actions block join into one face with a shared border and continuous corners.
- **Hover / Focus:** lift 1px, shadow lengthens (see Elevation). Focus-visible also gets the 3px enamel outline. Active returns to rest. Disabled drops to 60% opacity and does not lift.
- **Ink plate (`plate-ink`):** the same plate in near-black, used for the visitor's own clock as deliberate emphasis (the one clock that is yours is the one black plate on the wall) and for the footer brand.
- **Outline (`btn-outline-primary`, `-secondary`, `-danger`):** Bootstrap outlines on a white face background, 700 weight, 4px corners. Used for secondary and destructive guest actions (None of these times work, Leave this event) and organizer utilities.
- **Text (`btn-link`, `quiet-link`):** underlined with 0.2em offset. `quiet-link` is ink-soft with a 35% ink underline, darkening to ink on hover. `btn-link` is 700 in enamel.

### Chips / Plates
- **Style:** the plate is the chip. Enamel background, white caps, 3px corners. Sizes step down by context (0.8rem base, 0.72rem clock city, 0.7rem dashboard count, 0.65rem event state inline in a heading or on a card). On a phone the clock plates tighten to `0.5em 0.7em`.
- **Where:** a plate states a fact or offers an action. Facts: a city and its time, "Set in stone" after a finalized event's name, the number of events beside a dashboard heading, the event name on the activities page, the footer brand and year. Actions: every plate button. A plate is never a section label or a step marker; the four stations on the landing page carry headings alone.
- **State:** ink variant for the visitor's own clock and the footer; `plate-signal` exists in the stylesheet but no view uses it and it is not part of the system.
- **Clock plate:** a vertical plate under each clock reading city (caps), local time (mono, 1.05rem), and UTC offset (0.65rem, 75% opacity).

### Cards / Containers
- **Face** (`face`, `event-face`, `event-panel`, `organizer-panel`, `form-events`, `form-inputs`, `time-grid-panel`, dashboard `empty`): white glass, hairline border, 6px corners, face shadow, `clamp(1rem, 2.5vw, 1.75rem)` padding (the grid panel uses a tight 12px).
- **Event face:** a clickable card laid out as `1fr / auto` with the title at 1.25rem 800, a mono time on the right, and a state row with a small plate. Lifts 2px on hover. Stacks under 520px.
- **Wall bands:** the stations rail and footer sit on wall-deep between hairlines, flat.
- **Notice list:** plain items separated by hairlines, bold 800 lead-ins, max 62ch.

### Inputs / Fields
- **Style:** white glass, 28% ink stroke, 4px corners, 600-weight labels, ink-soft placeholders. Bootstrap form controls carry the world through the variable overrides.
- **Focus:** enamel border and a 3px enamel glow at 20%.
- **Toggle:** 52 by 30px pill, 25% ink track, white knob with a small shadow; checked fills the track enamel. Focus-visible outlines in enamel.
- **Paint mode:** a segmented radio group in a white 4px box with a 30% ink border; the checked segment fills enamel with white text. Shown only on coarse pointers.
- **Range (time ruler):** an invisible native range over a recessed white track with 25 tick marks (every sixth is ink), a 6px by 44px signal-red thumb ringed in white, and a yellow painted band behind. The cursor is a grab hand.

### Navigation
- **Style:** a wall-coloured header with a bottom hairline. The brand is an ink wordmark reading "Catching.app" (800, 1.15rem, -0.02em) that turns enamel on hover. Links are 600 ink with a 2px transparent bottom border that turns ink on hover. The one plate in the header is the small "Plan a meeting" plate button on the right.
- **Mobile:** Bootstrap collapse below 767.98px. The toggler is a 40px square with no box, border, or background, holding an inline SVG of two round-capped ink lines (22 by 14, 2px stroke) that inherit the ink colour; the plate button stays visible beside it at 0.7rem; links stack left-aligned below.
- **Footer:** wall-deep band with an ink plate for the brand and year, and quiet links.
- **Flashes:** notices pinned under the nav as a full-width 4px box with a 20% ink border, 600 text, dismiss button. Info is white glass; warning is awake-wash.

### Wall Clock (signature)
An SVG clock built in JavaScript: white face with a 1.5-unit ink stroke, a 6-unit ring at 12% ink, sixty ticks, hour hand 4.5 wide to radius 24, minute hand 3 wide to radius 34, second hand 1.4 wide in signal red with a tail past the centre, and a red pin with a white stroke. Hands rotate via CSS transform about the centre. On load, hands start at noon and sweep to the current time over 1.4s with the spring ease, then the transition is removed; under `prefers-reduced-motion: reduce` they appear in place. The wall renders five clocks, the visitor's zone first on an ink plate, re-rendered every animation frame so the second hand sweeps continuously; the clock carries a 0 6px 8px drop shadow so it hangs on the wall rather than printing on it.

### Time Ruler (signature)
A 44px recessed track spanning 12 hours either side of now in 15-minute steps. A one-line hint above it ("Drag the red line", with the lead in signal red) says what to do. The visitor drags a red thumb and every clock follows. Behind the thumb, quarter-hours where all five cities are between 08:00 and 23:00 local are painted awake yellow with hard stops. Under the track a mono scale reads −12h, −6h, now, +6h, +12h at 0.7rem in ink-soft, with "now" in bold signal red. A legend row shows a yellow swatch with a plain sentence counting the awake hours "in the 24 around now", and a mono output reading "now" or an offset.

### Availability Grid (signature)
A table of slots. Day headers are enamel plates, sticky at the top. Row labels are 12px mono, right-aligned, sticky at the left on white. Cells are 3px-cornered: white glass when offered (45% ink border), wall-coloured and faint when not offered, enamel with white text when the viewer has painted them (with a 0.3s scale pulse), awake-wash with an awake-deep border where every responder overlaps, and full awake yellow with an ink border where the viewer has painted a consensus slot. Past slots strike through at 40% opacity. Cell focus outlines in signal red. A 4px gap between cells shows the wall through, so the grid reads as tiles on the wall. Once finalized, a plate reading "Set in stone" follows the event name inline in its heading; while planning, the heading stands alone.

## Do's and Don'ts

### Do:
- **Do** set every time, offset, and clock reading in Martian Mono with tabular numerals; words stay in Schibsted Grotesk.
- **Do** make every primary action and every stated fact (a city and time, "Set in stone", a count) an enamel plate with white uppercase caps (700, 0.12em) and 3px corners; use the ink plate for the visitor's clock and the footer.
- **Do** hold content in white faces (hairline border, 6px corners, face shadow) on the wall, and keep the wall itself flat.
- **Do** paint consensus in awake yellow and its wash, and paint the viewer's own selection in enamel.
- **Do** use hairline (14% ink) as the only divider, at 1px, and reserve dashed 2px lines for day boundaries inside a grid.
- **Do** lift interactive plates and faces by 1 or 2px over 0.18s with `cubic-bezier(0.16, 1, 0.3, 1)`, and respect `prefers-reduced-motion` for the clock sweep.
- **Do** keep headings at 800 with negative tracking and balanced wrap, and keep ledes to 62ch in ink-soft.
- **Do** self-host every font and image; the only shipping raster is the og:image.

### Don't:
- **Don't** fill any surface with a gradient or apply backdrop blur. The one permitted gradient is technique, not look: the hard-stop painted awake band on the ruler.
- **Don't** make a red or yellow button, panel, or plate. Red is the second hand, the ruler thumb, a focus outline on a grid cell, and Bootstrap danger. Yellow is a painted band or cell.
- **Don't** add kickers, eyebrows, or overlines above headings, and don't put a plate above a heading as a step or section label; a plate may follow a heading inline only to state a fact about it.
- **Don't** load imagery, fonts, scripts, or video from a third-party host. Cloudinary is gone and stays gone.
- **Don't** invent testimonials, usage numbers, logos, or customer names; the landing page's proof is the live clocks and a labelled, made-up sample grid.
- **Don't** use a heading weight below 800 or a body face other than Schibsted Grotesk; the world has two typefaces and no third.
- **Don't** round corners past 6px on anything but the toggle pill.
- **Don't** hide a clock on small screens; the clock row scrolls and snaps so the same five cities appear at every width.
