## MODIFIED Requirements

### Requirement: The grid is an accessible table
Both grids SHALL render as `<table role="grid">` with a `thead` row of `th[scope=col]` day headers and one `tr` per time row; each cell SHALL be `td.slot[data-date]` carrying an `aria-label` such as "Tue 10 Feb, 09:00–09:30" (viewer zone). On the show grid the label SHALL be followed by ", N others available" when a count from `#availability-counts` exists; on the definer grid it SHALL be followed by ", N guests picked this" when a count from `#guest-picked-counts` exists. Non-offered and past cells SHALL carry `aria-disabled="true"` and no `aria-selected`; selectable cells SHALL carry `aria-selected`. Keyboard: roving tabindex (one cell at 0), arrow keys move focus, Space toggles, so the grid is one Tab stop; `.slot:focus-visible` SHALL have a visible outline. The "Hide times not offered" switch SHALL have a visually hidden label and hide with `visibility: hidden` so table semantics survive. The paint-mode control SHALL be a `role="radiogroup"` of two radios.

#### Scenario: One Tab stop
- **WHEN** a keyboard user tabs from the zone picker
- **THEN** focus lands on one grid cell, Space toggles it, and the next Tab leaves the grid

#### Scenario: Show cell labels include counts
- **WHEN** two other participants are available at a cell of the show grid
- **THEN** the cell's `aria-label` ends with ", 2 others available"

#### Scenario: Definer cell labels include guest picks
- **WHEN** `#guest-picked-counts` on `offer/edit` maps a cell's instant to 2
- **THEN** the cell's `aria-label` ends with ", 2 guests picked this"

#### Scenario: Past definer cells are disabled
- **WHEN** a definer cell's instant is before `data-not-before`
- **THEN** the cell carries `aria-disabled="true"` and no `aria-selected`

### Requirement: The definer page keeps its contract
`events/new` SHALL render `#time-grid-define[data-slot-minutes][data-time-zone]`, `input#time_slot_array[name="time_slots[time_slot_array]"]` whose value is rendered back on 422, `select#event_slot_minutes[name="event[slot_minutes]"]`, `select#timezone-picker-new[name="event[time_zone]"][data-selected]`, unnamed `#event-begin` and `#event-end`, `#range-tooltip`, `#selection-summary` and `#paint-mode`. The controls SHALL come from the builder-agnostic partial `events/_grid_controls.html.erb` (plain `select_tag`/`text_field_tag` with the pinned ids and names, no form-builder dependency) and the grid from `events/_definer_grid.html.erb` (`table#time-grid-define`, `#selection-summary`, `#paint-mode`); both partials SHALL be shared with `GET …/offer/edit`, where they render inside `form_with model: @event, url: scoped_path(:offer), method: :patch, id: "offer-form"` (on `events/new` they render inside `simple_form_for`). The definer ID contract test (`#time-grid-define`, `#timezone-picker-new`, `#event_slot_minutes`, `#time_slot_array`, `#event-begin`, `#event-end`, `#range-tooltip`, `#selection-summary`) SHALL run against both pages, so a rename cannot silently break the second page.

On `offer/edit` the page SHALL additionally render `table#time-grid-define[data-not-before]` holding the parser cut-off `TimeSlotParser::PAST_GRACE.ago` as ISO 8601, `#event-begin` with `min` = today in the event zone, `#time_slot_array` hydrated with the organizer's offered instants at or after that cut-off, a hidden `#current-offer` (JSON array of the same instants) and a hidden `#guest-picked-counts` (JSON object of ISO instant → number of counting or voided guests holding that instant). `events/new` SHALL render neither `#current-offer` nor `#guest-picked-counts`.

`populateTimeZoneSelect(select, preferred)` SHALL select `preferred` when present. The selection SHALL be a Set of UTC instants that survives redraws, is hydrated from the hidden value on load, is remapped by wall clock on zone change (`setZone(old).setZone(new, { keepLocalTime: true })`), is rescaled on step change, and is serialized after every stroke and on submit.

`renderDefinerTable` SHALL accept optional `isPast` and `counts`. A cell whose instant is before `data-not-before` SHALL render with class `past` and `aria-disabled="true"`, without `aria-selected` and without `selectable`, so a stroke across it changes nothing. A cell whose instant appears in `#guest-picked-counts` SHALL show a `+N` badge and extend its `aria-label` with ", N guests picked this". After every stroke on `offer/edit`, when instants present in `#current-offer` with a count are absent from the selection, `#selection-summary` SHALL append a warning of the form "Removing 3 times that 2 guests picked" (from the pure helper `removalWarning(currentOffer, selection, counts)`) and `#offer-form` SHALL carry `data-turbo-confirm` "Remove N times that M guests picked?"; when no such instant is missing the attribute SHALL be removed.

On `events/new` the step-change handler SHALL additionally disable every `#event_duration_minutes` option whose value is not a multiple of the new step and reset the select to "Not set" when the selected option became invalid, deciding through the pure helper `allowedDurations(stepMinutes, options)` and using no inline script (CSP). On `offer/edit`, while no guest has `responded_at`, `select#event_slot_minutes` and `select#timezone-picker-new` SHALL be live with the existing remap and rescale behaviour; once any guest has replied both SHALL render `disabled` with `aria-describedby` pointing at the caption "Fixed since the first reply".

#### Scenario: Zone change moves cells by wall clock
- **WHEN** 09:00 Europe/Berlin is painted and the picker changes to Asia/Kolkata
- **THEN** the painted instant is 09:00 Asia/Kolkata and the summary reports the move

#### Scenario: Hydration after a 422
- **WHEN** the form re-renders with a hidden value of two instants and `data-selected="Asia/Kolkata"`
- **THEN** the grid draws in Asia/Kolkata with those two cells painted and the date range covering them

#### Scenario: The definer ID contract holds on both pages
- **WHEN** the ID contract test renders `events/new` and `offer/edit`
- **THEN** `#time-grid-define`, `#timezone-picker-new`, `#event_slot_minutes`, `#time_slot_array`, `#event-begin`, `#event-end`, `#range-tooltip` and `#selection-summary` are present on both, `#time-grid-define` on `offer/edit` carries `data-not-before`, and `events/new` renders neither `#current-offer` nor `#guest-picked-counts`

#### Scenario: The offer page hydrates the current future offer
- **WHEN** the organizer offered 09:00 yesterday (before `PAST_GRACE.ago`) and 10:00 and 11:00 next week, a counting guest holds 10:00, and the organizer opens `offer/edit`
- **THEN** `#time_slot_array` and `#current-offer` contain exactly the two future instants, `#guest-picked-counts` is `{"<10:00 ISO>":1}`, and the grid draws with 10:00 and 11:00 painted

#### Scenario: Past cells cannot be painted
- **WHEN** `offer/edit` renders with `data-not-before` after some cells of the visible date range
- **THEN** those cells carry `past` and `aria-disabled="true"`, and a stroke across them changes neither the selection nor `#time_slot_array`

#### Scenario: Badge on a picked cell
- **WHEN** `#guest-picked-counts` maps 10:00 to 2
- **THEN** the 10:00 cell shows a `+2` badge and its `aria-label` ends with ", 2 guests picked this"

#### Scenario: Unpainting a picked cell arms the confirm
- **WHEN** the organizer unpaints the only offered cell held by 2 guests and then paints it again
- **THEN** after the first stroke `#selection-summary` names 1 removed time and 2 guests and `#offer-form` carries a `data-turbo-confirm` beginning "Remove", and after the second stroke the warning is gone and `#offer-form` has no `data-turbo-confirm`

#### Scenario: Step change disables non-multiple durations
- **WHEN** 90 is selected in `#event_duration_minutes` on `events/new` and the organizer changes `#event_slot_minutes` to 60
- **THEN** the 90 option is disabled and the select shows "Not set"

#### Scenario: Frozen selects after the first reply
- **WHEN** one guest has `responded_at` and the organizer opens `offer/edit`
- **THEN** `#event_slot_minutes` and `#timezone-picker-new` are `disabled` with `aria-describedby` pointing at "Fixed since the first reply", and the grid still draws and paints

### Requirement: The show page keeps its contract
The participation page SHALL render `#time-grid-show[data-slot-minutes][data-role="guest"|"organizer"|"viewer"][data-event-time-zone][data-not-before][data-finalized?][data-cancelled?][data-duration-minutes?]`. `data-role` SHALL be `@participant.role` while `@event.open?` and `"viewer"` otherwise (`viewer_role` is `@event.open? ? @participant.role : "viewer"`); `data-finalized` SHALL be present when `status?` is true; `data-cancelled` SHALL be present when `cancelled_at` is set (a cancelled finalized event carries both); `data-duration-minutes` SHALL equal `events.duration_minutes` when it is set. The page SHALL render hidden `#received-time-slots`, `#my-time-slots`, `#availability-counts` (JSON object of ISO to count), `#consensus-time-slots`, `#final-window` when finalized together with `#final-window-local` that the JavaScript fills in the picker zone, `#hide-disabled-cells`, `#paint-mode`, `#selection-summary[aria-live=polite]`, and on every page that is not cancelled `select#timezone-picker-show[data-selected]`. While the event is open a guest SHALL get an `#availability-form` (PATCH) with hidden `#new-time-slot-array`, `participant[name]` and hidden `participant[time_zone]`, and an organizer with at least one counting guest SHALL get `#finalize-form` with hidden `#final-time-slot-array`. With `data-role="viewer"` (finalized or cancelled) no painting SHALL be attached and neither `#availability-form` nor `#finalize-form` SHALL render. `#is-host` SHALL NOT exist. Every form on the page SHALL copy the picker value into its `participant[time_zone]` on submit.

`time_slot_show.js` SHALL read `data-duration-minutes` and pass it as `durationMinutes` to `summary()`, so the organizer's action bar reads the selected window with its length followed by the planned length, such as "Tue 10 Feb 20:00–21:00 (1 h) · planned 1 h 30 min", and adds "shorter than planned" when the selection is shorter — a warning in the action bar, never a refusal.

Every server-rendered instant on the page SHALL be `<time datetime="<iso8601>" data-zoned-instant class="time">` in the event zone with the zone name, e.g. `20:00 (Europe/Berlin)`; `time_slot_show.js` SHALL rewrite every `[data-zoned-instant]` into the picker zone on load and on zone change, through the same path that fills `#final-window-local` and the pure helper `zonedLabel(iso, zone)`. This applies to derived plan starts and to the "The organizer changed the offered times on <date>", "The set time was withdrawn on <date>" and "Cancelled on <date>" notices. On a cancelled page there is no zone picker, so every `[data-zoned-instant]` SHALL stay in the event zone, named, and the component SHALL initialize without `#timezone-picker-show`.

The `sessionStorage` re-apply after a redirect SHALL keep only stashed keys present in `offeredKeys`, through the pure helper `filterStash(keys, offeredKeys)`, so a stale save cannot loop on cells that no longer exist. When every offered instant is before `data-not-before` on an open event, a guest's `#selection-summary` SHALL read "All the offered times have passed." and the Save control SHALL be hidden.

#### Scenario: Show page contract for an organizer
- **WHEN** an organizer opens their open event with at least one counting guest
- **THEN** `#time-grid-show[data-role="organizer"]`, `#consensus-time-slots` and `#finalize-form` are present and `#availability-form` is absent

#### Scenario: Viewer mode after finalization
- **WHEN** a guest or the organizer opens a finalized, not cancelled event
- **THEN** `#time-grid-show[data-finalized][data-role="viewer"]` is present without `data-cancelled`, `#final-window` is present and `#final-window-local` is filled in the picker zone, no painting is attached, and neither `#availability-form` nor `#finalize-form` renders

#### Scenario: Viewer mode with data-cancelled after cancellation
- **WHEN** a guest opens their link on a cancelled event that had been finalized
- **THEN** the page renders 200 with `#time-grid-show[data-role="viewer"][data-finalized][data-cancelled]`, no `#timezone-picker-show`, no `#availability-form` and no `#finalize-form`, and the "Cancelled on" `[data-zoned-instant]` reads in the event zone with its name

#### Scenario: Planned length reaches the finalize summary
- **WHEN** an event with `duration_minutes` 90 renders for its organizer and the organizer paints a 60-minute consensus window
- **THEN** `#time-grid-show` carries `data-duration-minutes="90"` and `#selection-summary` contains "(1 h)", "planned 1 h 30 min" and "shorter than planned", while the finalize form still submits

#### Scenario: Zoned instants follow the picker
- **WHEN** a finalized Europe/Berlin event renders a derived plan start of 20:00 as `<time datetime="…" data-zoned-instant class="time">20:00 (Europe/Berlin)</time>` and the guest's picker is Asia/Kolkata
- **THEN** after load the element reads "00:30 (Asia/Kolkata)", and changing the picker to Europe/Berlin makes it read "20:00 (Europe/Berlin)" again

#### Scenario: Stash is filtered to the offer
- **WHEN** the stash holds 10:00 and 11:00, the offer no longer contains 11:00, and the page reloads with an alert
- **THEN** only 10:00 is re-painted and `#new-time-slot-array` serializes 10:00 alone

#### Scenario: Every offered time has passed for a guest
- **WHEN** a guest opens an open event whose every offered instant is before `data-not-before`
- **THEN** `#selection-summary` reads "All the offered times have passed." and no Save control is visible

### Requirement: JavaScript tests run as a directory
`package.json` `test` SHALL be `node --test "test/javascript/**/*.test.js"` so every test file runs in `npm run check` on the pinned Node 24; no new npm dependency SHALL be added. `node --test` SHALL cover pure helpers only; DOM behaviour (past cells, badges, the confirm attribute, the duration select, the `[data-zoned-instant]` rewrite, the stash re-apply) SHALL be covered by Selenium system tests, not by node. In addition to `strokeMode`, `applyStroke`, `remapZone`, `rescale` and `summary`, the following pure helpers SHALL be exported and covered by `node --test`: `definerCellState(instant, { notBefore, counts })`, `zonedLabel(iso, zone)`, `allowedDurations(stepMinutes, options)`, `removalWarning(currentOffer, selection, counts)`, `filterStash(keys, offeredKeys)` and `summary()` with `durationMinutes` (in `app/javascript/lib/paint.js`).

#### Scenario: New test file is picked up
- **WHEN** `test/javascript/paint.test.js` exists
- **THEN** `npm test` runs it

#### Scenario: definerCellState is pure
- **WHEN** `definerCellState` runs under `node --test` with an instant before `notBefore` and with an instant whose ISO key maps to 2 in `counts`
- **THEN** the first result reports the cell as past and the second reports a count of 2

#### Scenario: zonedLabel formats in two zones
- **WHEN** `zonedLabel("2030-01-15T19:00:00Z", "Europe/Berlin")` and `zonedLabel("2030-01-15T19:00:00Z", "Asia/Kolkata")` run under `node --test`
- **THEN** they return "20:00 (Europe/Berlin)" and "00:30 (Asia/Kolkata)"

#### Scenario: allowedDurations follows the step
- **WHEN** `allowedDurations(60, [30, 60, 90, 120, 1440])` runs under `node --test`
- **THEN** it reports 60, 120 and 1440 as allowed and 30 and 90 as disallowed

#### Scenario: removalWarning counts removed picks
- **WHEN** `removalWarning(currentOffer, selection, counts)` runs with `currentOffer` of 10:00 and 11:00, `counts` mapping 10:00 to 2, and a selection of 11:00 only, and then with a selection that is a superset of `currentOffer`
- **THEN** the first call reports 1 removed time affecting 2 guests and the second reports zero removals

#### Scenario: filterStash keeps offered keys only
- **WHEN** `filterStash(["<10:00>", "<11:00>"], ["<10:00>"])` runs under `node --test`
- **THEN** it returns `["<10:00>"]`

#### Scenario: summary compares with the planned length
- **WHEN** `summary()` runs as organizer with a 60-minute selection and `durationMinutes: 90`, and again with a 90-minute selection and `durationMinutes: 90`
- **THEN** the first text contains "(1 h)", "planned 1 h 30 min" and "shorter than planned", and the second contains "planned 1 h 30 min" and not "shorter than planned"
