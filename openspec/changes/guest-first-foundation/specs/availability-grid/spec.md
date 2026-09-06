## ADDED Requirements

### Requirement: The grid is an accessible table
Both grids SHALL render as `<table role="grid">` with a `thead` row of `th[scope=col]` day headers and one `tr` per time row; each cell SHALL be `td.slot[data-date]` carrying an `aria-label` such as "Tue 10 Feb, 09:00–09:30" (viewer zone) followed by ", N others available" when a count exists; non-offered and past cells SHALL carry `aria-disabled="true"` and no `aria-selected`; selectable cells SHALL carry `aria-selected`. Keyboard: roving tabindex (one cell at 0), arrow keys move focus, Space toggles, so the grid is one Tab stop; `.slot:focus-visible` SHALL have a visible outline. The "Hide times not offered" switch SHALL have a visually hidden label and hide with `visibility: hidden` so table semantics survive. The paint-mode control SHALL be a `role="radiogroup"` of two radios.

#### Scenario: One Tab stop
- **WHEN** a keyboard user tabs from the last grid control
- **THEN** focus lands on one grid cell, Space toggles it, and the next Tab leaves the grid

#### Scenario: Cell labels include counts
- **WHEN** two other participants are available at a cell
- **THEN** the cell's `aria-label` ends with ", 2 others available"

### Requirement: The wire format is unchanged
Browser to server SHALL be one field `time_slots[time_slot_array]` of comma-joined UTC ISO 8601 strings; server to browser SHALL be hidden inputs whose values are JSON arrays of `iso8601` strings; the JavaScript SHALL normalize both through `slotISO` before comparing.

#### Scenario: Round trip preserves identity
- **WHEN** the server renders `2030-01-15T10:00:00Z` and the grid serializes the same painted cell
- **THEN** the serialized value equals `slotISO` of the parsed instant

### Requirement: The definer page keeps its contract
`events/new` SHALL render `#time-grid-define[data-slot-minutes][data-time-zone]`, `input#time_slot_array[name="time_slots[time_slot_array]"]` whose value is rendered back on 422, `select#event_slot_minutes`, `select#timezone-picker-new[name="event[time_zone]"][data-selected]`, unnamed `#event-begin` and `#event-end`, `#range-tooltip` and `#selection-summary`. `populateTimeZoneSelect(select, preferred)` SHALL select `preferred` when present. The selection SHALL be a Set of UTC instants that survives redraws, is hydrated from the hidden value on load, is remapped by wall clock on zone change (`setZone(old).setZone(new, { keepLocalTime: true })`), and is serialized after every stroke and on submit.

#### Scenario: Zone change moves cells by wall clock
- **WHEN** 09:00 Europe/Berlin is painted and the picker changes to Asia/Kolkata
- **THEN** the painted instant is 09:00 Asia/Kolkata and the summary reports the move

#### Scenario: Hydration after a 422
- **WHEN** the form re-renders with a hidden value of two instants and `data-selected="Asia/Kolkata"`
- **THEN** the grid draws in Asia/Kolkata with those two cells painted and the date range covering them

### Requirement: The show page keeps its contract
The participation page SHALL render `#time-grid-show[data-slot-minutes][data-role="guest"|"organizer"|"viewer"][data-event-time-zone][data-not-before][data-finalized?]`, hidden `#received-time-slots`, `#my-time-slots`, `#availability-counts` (JSON object of ISO to count), `#consensus-time-slots`, `#final-window` when finalized, `select#timezone-picker-show[data-selected]`, `#hide-disabled-cells`, `#paint-mode`, `#selection-summary[aria-live=polite]`, an `#availability-form` (PATCH) with hidden `#new-time-slot-array`, `participant[name]` and hidden `participant[time_zone]`, and for organizers `#finalize-form` with hidden `#final-time-slot-array`. `#is-host` SHALL NOT exist. Every form on the page SHALL copy the picker value into its `participant[time_zone]` on submit.

#### Scenario: Show page contract for an organizer
- **WHEN** an organizer opens their event with at least one counting guest
- **THEN** `#time-grid-show[data-role="organizer"]`, `#consensus-time-slots` and `#finalize-form` are present and `#availability-form` is absent

### Requirement: The show grid draws the organizer's lattice on a circular band
`offeredGrid(offeredInstants, eventZone, viewerZone, slotMinutes)` SHALL build cells from the event-zone lattice (`localDaySlots` for each event-zone day overlapping the offer), key each instant by viewer-local date and `(wallMinutes, occurrence)`, and choose one band for all days by sorting offered wall-clock minutes modulo 1440, finding the largest gap (wrapping), and starting the band just after it; rows SHALL be the union of keys inside the band, days missing a key SHALL get a placeholder cell, and a day-boundary rule SHALL mark the row that crosses midnight.

#### Scenario: Half-hour organizer matches from UTC
- **WHEN** an Asia/Kolkata organizer offers hourly cells and a UTC viewer opens the page
- **THEN** cells at 18:30Z, 19:30Z... are drawn and marked offered by identity

#### Scenario: Cross-midnight offer stays compact
- **WHEN** a Europe/Berlin 09:00–18:00 offer at 30 minutes is viewed from Pacific/Auckland
- **THEN** the grid has 19 rows starting after the largest gap, not 48

#### Scenario: Fall-back day adds one row
- **WHEN** the offer spans a fall-back day in the viewer's zone
- **THEN** exactly one extra `(wallMinutes, 1)` row appears with placeholders on other days

### Requirement: Day generation is DST-correct at every step
`localDayColumns(first, last, slotMinutes)` SHALL apply `startOf("day")` after each day increment so a zone whose midnight does not exist neither duplicates an instant nor drops the last date.

#### Scenario: Santiago spring-forward at midnight
- **WHEN** columns are built for America/Santiago 2026-09-05 through 2026-09-08 at 60 minutes
- **THEN** the counts are [24, 23, 24, 24] with no duplicate instant

#### Scenario: Cairo
- **WHEN** columns are built for Africa/Cairo 2026-04-23 through 2026-04-25
- **THEN** three columns are produced

### Requirement: Painting works with pointer events for mouse, touch and pen
A shared `lib/paint.js` SHALL implement `attachPainting(grid, { selectable, selection, mode, onStroke })` with delegated pointer events on the grid root: `pointerdown` ignores non-primary pointers and records the active pointer; the stroke mode (add or remove) is decided by the pressed cell; a `mouse` pointer always paints; `touch` and `pen` follow the stored mode; in paint mode the grid attempts `setPointerCapture` inside try/catch; `pointermove` hit-tests with `document.elementFromPoint`; the stroke ends exactly once on the first of `pointerup`, `pointercancel` or `lostpointercapture` and calls `onStroke`; in scroll mode only a `pointerdown`/`pointerup` pair on the same cell toggles. Listeners SHALL be registered through an `AbortController` stored on the element so re-initialization on `turbo:load` is idempotent. Pure helpers `strokeMode`, `applyStroke`, `remapZone`, `rescale` and `summary` SHALL be exported and covered by `node --test`.

#### Scenario: Mouse drag paints four cells
- **WHEN** a mouse presses on an offered cell and moves across three more before release
- **THEN** four cells are painted and `onStroke` fires once

#### Scenario: Touch drag in scroll mode scrolls
- **WHEN** a touch drag crosses the grid while in scroll mode
- **THEN** no cell changes and `scrollY` changes

#### Scenario: Re-initialization does not double-bind
- **WHEN** `turbo:load` fires twice on the same page
- **THEN** one stroke still toggles each cell exactly once

### Requirement: Touch layout keeps the page scrollable and zoomable
On coarse pointers the default mode SHALL be scroll, paint SHALL be opt-in through `#paint-mode` and remembered in `localStorage`; `touch-action` SHALL be `pan-x pan-y pinch-zoom` in scroll mode and `none` on the grid body only while painting, with `pan-x pan-y pinch-zoom` kept on the sticky header row and the row-label column. The grid wrapper `.time-grid-scroll` SHALL have a bounded height and `overflow: auto` so sticky day headers and a sticky row-label column work and paint-mode auto-scroll has one target: `max-height: calc(100dvh - <navbar> - <action bar>)` on the show page, and on the definer page — where the controls strip sits inside the same panel and its height varies with width and with the frozen state — the panel itself is bounded to the viewport and lays out as a column, so the wrapper takes the space the strip leaves, above a floor; while a captured pointer is within 48 px of a wrapper edge the wrapper SHALL auto-scroll until the stroke ends. The event card SHALL be `width: min(400px, 100%)` and the document MUST NOT scroll horizontally on a 412 px viewport.

#### Scenario: Paint mode reaches the bottom rows
- **WHEN** a touch stroke in paint mode drags to within 48 px of the wrapper's bottom edge on a 48-row grid
- **THEN** the wrapper scrolls and cells below the initial viewport get painted

#### Scenario: No horizontal body scroll on a phone
- **WHEN** the guest page or the definer page renders in the 412 px mobile system test
- **THEN** `document.documentElement.scrollWidth` is at most `window.innerWidth`

#### Scenario: The grid comes before the button that posts it
- **WHEN** the definer page renders in the 412 px mobile system test
- **THEN** `#time-grid-define` starts above the submit and the sticky action bar does not overlap it

### Requirement: JavaScript tests run as a directory
`package.json` `test` SHALL be `node --test "test/javascript/**/*.test.js"` so every test file runs in `npm run check` on the pinned Node 24; no new npm dependency SHALL be added.

#### Scenario: New test file is picked up
- **WHEN** `test/javascript/paint.test.js` exists
- **THEN** `npm test` runs it
