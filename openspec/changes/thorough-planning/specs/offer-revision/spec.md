## ADDED Requirements

### Requirement: Only the organizer reaches the offer page, through both families, while the event is open
The `participation_actions` routing concern SHALL gain `resource :offer, only: %i[edit update]` under `module: :participations`, so `GET /p/:token/offer/edit`, `PATCH /p/:token/offer`, `GET /participations/:participation_id/offer/edit` and `PATCH /participations/:participation_id/offer` all exist and are served by `Participations::OffersController` (`edit`, `update`); `scoped_path(:offer, edit: true)` SHALL build the `edit_`-prefixed helper of the current family. Both actions SHALL be gated by `require_organizer!` (a guest token receives the uniform 404). On the organizer page a plate button **Change the times** linking to `scoped_path(:offer, edit: true)` SHALL render only while `@event.open?`. When the event is finalized both actions SHALL answer 303 with the controller message "Reopen the time before changing the offer" (the model keeps raising `Event::ClosedError` "Availability is closed for this event"); when the event is cancelled both SHALL answer 303 with "This event was cancelled". Neither action SHALL require `link_opened_at`.

#### Scenario: Guest token is refused on both actions
- **WHEN** a guest token sends `GET /p/:token/offer/edit` and `PATCH /p/:token/offer`
- **THEN** both responses are 404 and the offer is unchanged

#### Scenario: Finalized event redirects to reopen first
- **WHEN** the organizer of a finalized event opens the offer page or submits `PATCH …/offer` in either family
- **THEN** the response is 303 to the organizer page with the alert "Reopen the time before changing the offer" and no slot changes

#### Scenario: Cancelled event refuses the page
- **WHEN** the organizer of a cancelled event opens the offer page or submits `PATCH …/offer`
- **THEN** the response is 303 with the alert "This event was cancelled"

#### Scenario: Session family reaches the same page
- **WHEN** a claimed organizer opens `GET /participations/:participation_id/offer/edit`
- **THEN** the page renders `form#offer-form` posting to `my_participation_offer_path`

#### Scenario: The button follows the open state
- **WHEN** the organizer page renders for a pending, a finalized and a cancelled event
- **THEN** "Change the times" is present on the pending page and absent on the other two

### Requirement: The offer page hydrates the definer with the current future offer
`GET …/offer/edit` SHALL render a two-column work surface (`.event-new-grid`). The left face SHALL hold `form_with model: @event, url: scoped_path(:offer), method: :patch, id: "offer-form"` containing: the partial `events/_grid_controls.html.erb` (`select#event_slot_minutes[name="event[slot_minutes]"]`, `select#timezone-picker-new[name="event[time_zone]"][data-selected]`, `#event-begin` with `min` = today in the event zone, `#event-end`, `#range-tooltip`); the hidden `input#time_slot_array[name="time_slots[time_slot_array]"]` hydrated with the organizer's offered instants at or after the parser cut-off `TimeSlotParser::PAST_GRACE.ago`; a hidden `#current-offer` holding the same instants as JSON; a hidden `#guest-picked-counts` holding a JSON object of ISO instant → number of counting or voided guests holding that instant; a caption "N past times stay as they are" when any offered instant was dropped from the hydration; a checkbox `notice[send]` labelled "Email the guests who already replied", checked by default, rendered only when `@participant.link_opened_at` is present; and the submit "Save the new times". The right column SHALL be the partial `events/_definer_grid.html.erb` rendering `table#time-grid-define[data-slot-minutes][data-time-zone][data-not-before]`, `#selection-summary` and `#paint-mode`. `events/_grid_controls` SHALL be builder-agnostic (plain `select_tag`/`text_field_tag` with the pinned ids and names) so `events/new` (inside `simple_form_for`) and `offer/edit` (inside `form_with`) share it, and the definer ID contract test (`#time-grid-define`, `#timezone-picker-new`, `#event_slot_minutes`, `#time_slot_array`, `#event-begin`, `#event-end`, `#range-tooltip`, `#selection-summary`) SHALL run against both pages.

#### Scenario: Only future instants are hydrated
- **WHEN** the organizer offered 09:00 yesterday (before `PAST_GRACE.ago`) and 10:00 and 11:00 next week and opens the offer page
- **THEN** `#time_slot_array` and `#current-offer` contain exactly the two future instants and the page shows "1 past times stay as they are"

#### Scenario: Guest counts include voided guests
- **WHEN** a counting guest holds 10:00, a voided guest held nothing and a declined guest once held 11:00
- **THEN** `#guest-picked-counts` is `{"<10:00 ISO>":1}` and contains no key for 11:00

#### Scenario: The definer ID contract holds on both pages
- **WHEN** the ID contract test renders `events/new` and `offer/edit`
- **THEN** every pinned id is present on both, `#time-grid-define` on the offer page carries `data-not-before`, and `events/new` renders neither `#current-offer` nor `#guest-picked-counts`

#### Scenario: No checkbox before the organizer link was opened
- **WHEN** an organizer whose `link_opened_at` is NULL opens the offer page
- **THEN** no `notice[send]` control is rendered

### Requirement: Step and zone are live before the first reply and frozen after it
While no guest of the event has `responded_at`, `select#event_slot_minutes` and `select#timezone-picker-new` SHALL be enabled and the existing remap/rescale behaviour of the definer SHALL apply; `Participations::OffersController#offer_params` SHALL permit `event[slot_minutes]` and `event[time_zone]` only when `@event.participants.guest.where.not(responded_at: nil).none?`. Once any guest has replied, both selects SHALL render `disabled` with the caption "Fixed since the first reply" referenced by `aria-describedby`, the controller SHALL not permit the two parameters, and the model validation `grid_is_frozen_after_replies` SHALL refuse a changed step or zone with "cannot change after a guest has replied". When a pre-reply step change makes `duration_minutes` stop dividing the new step, `revise_offer!` SHALL clear `duration_minutes` in the same transaction and the flash SHALL append "Planned length cleared: it no longer fits N-minute slots."

#### Scenario: Step and zone change before the first reply
- **WHEN** no guest has replied and the organizer submits `event[slot_minutes]=60`, `event[time_zone]=Asia/Kolkata` and an hour-aligned offer
- **THEN** the event's `slot_minutes` is 60, its `time_zone` is `Asia/Kolkata` and the offer is rewritten

#### Scenario: Frozen after a reply
- **WHEN** one guest has `responded_at` and the organizer opens the offer page
- **THEN** both selects are `disabled` with `aria-describedby` pointing at "Fixed since the first reply", and a PATCH carrying `event[slot_minutes]=60` on a 30-minute event leaves `slot_minutes` at 30

#### Scenario: Model refuses a frozen change
- **WHEN** `revise_offer!(starts_at:, slot_minutes: 60)` is called on an event where a guest has replied
- **THEN** it raises a validation error containing "cannot change after a guest has replied" and nothing is written

#### Scenario: Planned length cleared by a step change
- **WHEN** a pre-reply event has `slot_minutes` 30 and `duration_minutes` 90 and the organizer changes the step to 60
- **THEN** `duration_minutes` is NULL after the revision and the flash ends with "Planned length cleared: it no longer fits 60-minute slots."

### Requirement: The definer marks past cells, badges guest picks and asks before removing them
`renderDefinerTable` SHALL accept optional `isPast` and `counts`. Cells before `data-not-before` SHALL render with class `past`, `aria-disabled="true"` and be unselectable. Cells whose instant appears in `#guest-picked-counts` SHALL show a `+N` badge and extend their `aria-label` with ", N guests picked this". After every stroke, when instants present in `#current-offer` with a count are absent from the selection, `#selection-summary` SHALL append a removal warning of the form "Removing 3 times with 2 guest picks" and `form.dataset.turboConfirm` on `#offer-form` SHALL be set to "Remove N times with M guest picks?"; when no such instant is missing the attribute SHALL be removed. `definerCellState(instant, { notBefore, counts })` and `removalWarning(currentOffer, selection, counts)` SHALL be exported pure helpers covered by `node --test`; badge, past-cell and confirm behaviour in the DOM SHALL be covered by Selenium, not by node.

#### Scenario: Past cells cannot be painted
- **WHEN** the offer page renders with `data-not-before` after some cells of the visible range
- **THEN** those cells carry `past` and `aria-disabled="true"` and a stroke across them changes nothing

#### Scenario: Badge on a picked cell
- **WHEN** `#guest-picked-counts` maps 10:00 to 2
- **THEN** the 10:00 cell shows a `+2` badge and its `aria-label` ends with ", 2 guests picked this"

#### Scenario: Unpainting a picked cell arms the confirm
- **WHEN** the organizer unpaints the only offered cell held by 2 guests
- **THEN** `#selection-summary` names 1 removed time and 2 guests and `#offer-form` carries a `data-turbo-confirm` beginning "Remove"

#### Scenario: Repainting disarms the confirm
- **WHEN** the organizer paints that cell again
- **THEN** the removal warning disappears from `#selection-summary` and `#offer-form` has no `data-turbo-confirm`

#### Scenario: Pure helpers under node
- **WHEN** `npm test` runs
- **THEN** `definerCellState` reports a cell before `notBefore` as past and a counted cell with its count, and `removalWarning` reports zero removals for a selection that is a superset of `currentOffer`

### Requirement: `revise_offer!` has three outcomes
`Event#revise_offer!(starts_at:, slot_minutes: nil, time_zone: nil)` SHALL raise `ArgumentError` before taking the lock when `starts_at` is blank. Inside `with_lock` it SHALL run `ensure_pending!` (raising `ClosedError` "This event was cancelled" first, else "Availability is closed for this event"), assign `slot_minutes`/`time_zone` when given and `validate!`, then `ensure_aligned!(starts_at)` against the resulting zone and step. With `cutoff = TimeSlotParser::PAST_GRACE.ago` computed once, `current` = the organizer's rows with `start_time >= cutoff`, `added = starts_at − current`, `removed = current − starts_at`. The three outcomes are: (a) `added` or `removed` non-empty → delete the organizer's rows at `removed` (`time_slots.where(participant_id: organizer.id, start_time: removed).delete_all`), `TimeSlot.insert_all!` one row per `added` instant, delete and void guest rows as specified below, and set `offer_revised_at = now`, `offer_revision_added = added.size`, `offer_revision_removed = removed.size`, `revision += 1` in the same transaction; (b) step or zone changed but the instant set is identical → `save!` the event and bump `revision` only, leaving `offer_revised_at` and the two counts untouched and sending no mail; (c) nothing changed → no write at all (no rows, no timestamps, no `revision`, no mail). The method SHALL return `Revision = Data.define(:added, :removed, :trimmed_ids, :voided_ids)`. The columns `events.offer_revised_at datetime NULL`, `events.offer_revision_added integer NOT NULL DEFAULT 0` and `events.offer_revision_removed integer NOT NULL DEFAULT 0` SHALL be guarded by the check `events_offer_revision_counts: (offer_revised_at IS NULL AND offer_revision_added = 0 AND offer_revision_removed = 0) OR (offer_revised_at IS NOT NULL AND offer_revision_added + offer_revision_removed > 0)`, which the three outcomes never violate. `revise_offer!` SHALL be the only writer of organizer slots after `Event.plan!`.

#### Scenario: Instant delta stamps the event
- **WHEN** the organizer offered 10:00 and 11:00 and submits 11:00, 12:00, 13:00, 14:00 and 15:00
- **THEN** the organizer's rows are exactly those five, `offer_revised_at` is set, `offer_revision_added` is 4, `offer_revision_removed` is 1, `revision` increased by one, and the returned `Revision` has `added.size` 4 and `removed.size` 1

#### Scenario: Berlin to Paris bumps the revision only
- **WHEN** a pre-reply event in `Europe/Berlin` is revised with `time_zone: "Europe/Paris"` and the identical instant set
- **THEN** `time_zone` is `Europe/Paris`, `revision` increased by one, `offer_revised_at` stays NULL, both counts stay 0, no mail is enqueued and the flash reads "Slot length and zone updated."

#### Scenario: Identical submission writes nothing
- **WHEN** the organizer resubmits the current offer with the current step and zone
- **THEN** no `time_slots` row changes, `offer_revised_at`, both counts and `revision` are unchanged, no mail is enqueued and the flash reads "Nothing changed."

#### Scenario: Blank input fails before the lock
- **WHEN** `revise_offer!(starts_at: [])` is called
- **THEN** it raises `ArgumentError` and no `FOR UPDATE` statement is issued

#### Scenario: Closed events are refused by the model
- **WHEN** `revise_offer!` is called on a cancelled event and on a finalized event
- **THEN** it raises `Event::ClosedError` with "This event was cancelled" and "Availability is closed for this event" respectively

#### Scenario: The counts check is a real constraint
- **WHEN** `update_columns(offer_revised_at: Time.current)` is executed on an event whose two counts are 0
- **THEN** the statement fails with a check-constraint violation

### Requirement: Past instants are frozen
Rows (the organizer's or any guest's) with `start_time < TimeSlotParser::PAST_GRACE.ago` SHALL never be inserted, deleted or compared by a revision: they are not part of `current`, so omitting them from the submission does not count as a removal, and the parser refuses submitting them. A pre-first-reply step change MAY leave a past organizer row off the new grid; this is accepted. When no offered instant is at or after `PAST_GRACE.ago`, the organizer action bar SHALL read "Every offered time has passed. Change the times." with the plate button, and the guest page SHALL show "All the offered times have passed." with Save hidden.

#### Scenario: A past organizer row survives an omission
- **WHEN** the organizer's offer includes 09:00 two days ago and the organizer submits only future instants
- **THEN** the 09:00 row still exists, `offer_revision_removed` does not count it and no guest row at 09:00 is deleted

#### Scenario: Past guest picks are untouched
- **WHEN** a guest holds a pick at an instant before the cut-off and the organizer revises the future offer
- **THEN** the guest's past row remains and the guest is neither trimmed nor voided on account of it

#### Scenario: Every offer is past
- **WHEN** every offered instant is before `PAST_GRACE.ago` and the organizer opens the event
- **THEN** the action bar reads "Every offered time has passed. Change the times." with the plate button, and a guest opening their link sees "All the offered times have passed." and no Save button

### Requirement: Guest picks at removed instants are deleted and a guest left with nothing is voided
In the same locked transaction as the organizer's row changes, `revise_offer!` SHALL run `time_slots.where(event_id: id, start_time: removed).where.not(participant_id: organizer.id).delete_all`, capturing the per-guest counts of deleted rows beforehand, so guest slots stay a subset of the offer; rows at kept instants SHALL be untouched. It SHALL then void every guest that replied and now holds no slot: `participants.guest.where(left_at: nil, declined_at: nil).where.not(responded_at: nil).where.not(id: time_slots.select(:participant_id))` restricted to rows whose `reply_voided_at` is NULL, with `update_all(reply_voided_at: now, updated_at: now)`. A guest who keeps at least one slot is trimmed and stays counting; declined, unreplied and left guests SHALL be unchanged. `participants.reply_voided_at datetime NULL` SHALL be guarded by the check `participants_voided_is_open_reply: reply_voided_at IS NULL OR (responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND role = 'guest')`. A revision SHALL never change `responded_at`, `declined_at`, `left_at`, `name`, `time_zone`, `user_id`, either token digest, ledger rows, or slots at kept or past instants. A guest save that acquires the lock before the revision SHALL be trimmed or voided by it; one that acquires it afterwards SHALL see the new offer and be refused with "Select only time slots offered by the organizer" if it carries removed instants. A fixture-integrity test SHALL assert over the whole fixture database that every guest slot is in its organizer's offer, and the fixture `planning_invitee_only` (12:00, outside the 10:00/11:00 offer) SHALL be moved into the offer or removed so the assertion holds.

#### Scenario: Trimmed guest keeps counting
- **WHEN** a guest holds 10:00 and 11:00 and the organizer removes 11:00
- **THEN** the guest's 11:00 row is deleted, the 10:00 row remains, `reply_voided_at` is NULL, the guest is in `participants.counting` and the returned `Revision.trimmed_ids` includes the guest

#### Scenario: Guest left with nothing is voided
- **WHEN** a guest holds only 11:00 and the organizer removes 11:00
- **THEN** the guest has zero slots, `reply_voided_at` is set, `responded_at` is unchanged, the guest is not in `participants.counting` and `Revision.voided_ids` includes the guest

#### Scenario: Other states are untouched
- **WHEN** the event also has a declined guest, a guest who never replied and a left guest and the organizer removes instants
- **THEN** none of the three gains a `reply_voided_at` and their `declined_at`, `responded_at` and `left_at` are unchanged

#### Scenario: Nothing else on the guest changes
- **WHEN** a guest with a name, a saved zone, a claimed `user_id`, a live and a pending token and two ledger rows is trimmed
- **THEN** every one of those values and rows is identical after the revision

#### Scenario: Voiding a declined guest is refused by the database
- **WHEN** `update_columns(reply_voided_at: Time.current)` is executed on a declined guest, on a guest with `responded_at` NULL, or on the organizer
- **THEN** each statement fails with a check-constraint violation

#### Scenario: Guest slots are a subset of the offer across the fixtures
- **WHEN** the fixture-integrity test runs
- **THEN** it finds zero guest slots whose `start_time` is not among the organizer's slots of the same event

#### Scenario: Late save against the new offer
- **WHEN** a guest submits 11:00 after a revision that removed 11:00 committed
- **THEN** the response is 303 with "Select only time slots offered by the organizer" and no guest row is written

### Requirement: Voided guests do not count and are un-voided by their next reply
`Participant.counting` SHALL be `where.not(responded_at: nil).where(declined_at: nil, left_at: nil, reply_voided_at: nil)` and `counting?` SHALL apply the same predicate. `Event#mutually_available_start_times` SHALL add `AND reply_voided_at IS NULL` to both the correlated denominator count and the `EXISTS` guard, staying one SQL statement, so a voided guest is outside the denominator and `ensure_replies!` fails with "Wait for at least one reply before confirming" when voiding left no counting guest. Un-voiding SHALL happen only through the guest's own next reply: `ParticipationsController#update` SHALL set `reply_voided_at: nil` in the same `update!` as `responded_at` and `declined_at: nil`; `Event#mark_unavailable!` SHALL set `reply_voided_at: nil` in its own `update!` alongside `declined_at`; `Participant#leave!` SHALL clear it in its `update!`. Because the check `participants_voided_is_open_reply` fires per statement, any other order is a `StatementInvalid`.

#### Scenario: Consensus excludes a voided guest
- **WHEN** guest A holds 10:00, guest B was voided, and the organizer offers 10:00 and 11:00
- **THEN** `mutually_available_start_times` is `[10:00]` and the call issues exactly one query

#### Scenario: Voiding the only responder blocks finalize
- **WHEN** the only counting guest is voided by a revision and the organizer finalizes
- **THEN** the response is 303 with "Wait for at least one reply before confirming" and `status` stays false

#### Scenario: Saving un-voids
- **WHEN** a voided guest saves an offered instant through `PATCH /p/:token`
- **THEN** `reply_voided_at` is NULL, `responded_at` is updated, the guest counts again and no second `response_confirmation` is enqueued

#### Scenario: Declining un-voids without a check violation
- **WHEN** a voided guest posts `POST /p/:token/decline`
- **THEN** `declined_at` is set and `reply_voided_at` is NULL in one statement and no `StatementInvalid` is raised

#### Scenario: Leaving un-voids
- **WHEN** a voided guest sends `DELETE /p/:token`
- **THEN** `left_at` and `declined_at` are set, `reply_voided_at` is NULL and the row satisfies both participant checks

### Requirement: The update action reports the outcome and keeps unsaved paint on failure
`PATCH …/offer` SHALL parse `time_slots[time_slot_array]` with `parsed_time_slots(slot_minutes: requested)` (the requested step when permitted, else the event's), pass the result with the permitted `event[slot_minutes]`/`event[time_zone]` to `revise_offer!`, and on success redirect 303 to the organizer page with the notice "Times updated: N added, M removed." for outcome (a), "Slot length and zone updated." for outcome (b) or "Nothing changed." for outcome (c); for outcome (a) the notice SHALL append " N guests emailed." and, when M > 0, " M skipped (recently notified). Try again after 10 minutes." when a notice ran and " 1 guest needs a new reply." (with the actual count) when guests were voided. Parser failures (the existing messages "Select at least one time slot", "Time slots must use ISO 8601 timestamps", "Time slots must fit within a 31-day window", "Select no more than N time slots", "Select time slots from today onward"), alignment failures, the frozen step or zone message and the slot cap SHALL re-render the edit page with status 422 and the submitted value echoed in `#time_slot_array` so paint is not lost; state failures (finalized, cancelled) SHALL redirect with status 303 and the exact message.

#### Scenario: Removal that voids a guest
- **WHEN** the organizer removes the only instant a replied guest held, adds two instants and leaves the notice box ticked
- **THEN** the response is 303 with a notice beginning "Times updated: 2 added, 1 removed." that mentions "1 guest needs a new reply" and the guests emailed

#### Scenario: Parser failure keeps the paint
- **WHEN** the organizer submits an instant before the cut-off
- **THEN** the response is 422, the page shows "Select time slots from today onward" and `#time_slot_array` echoes the submitted value

#### Scenario: Off-grid instant keeps the paint
- **WHEN** the organizer submits 10:30 on a 60-minute event
- **THEN** the response is 422 with the alignment message and `#time_slot_array` echoes the submitted value

### Requirement: Offer notices reach only guests who replied
When `notice[send]` is "1" and the revision was outcome (a), the controller SHALL call `Deliveries.event_updated!(event:, organizer:, request_ip:, reason: :offer)` after commit. Recipients SHALL be the event's active linked guests with `responded_at` set (trimmed, voided, untouched-but-added and declined), except that declined guests SHALL be excluded when `added` is empty; unreplied guests SHALL receive nothing. Each recipient SHALL pass `MailDelivery::Caps.check_update_notice!`; a refusal SHALL be skipped silently and counted, and `revise_offer!` SHALL never raise on a cap. Links SHALL follow the claimed rule: a pending token for an unclaimed guest, `my_participation_url` for a claimed one. Outcome (b), outcome (c), an unticked box and a revision made before any guest replied SHALL send nothing.

#### Scenario: Unreplied guests get nothing
- **WHEN** an event has a replied guest and an invited guest who never replied and the organizer revises with the box ticked
- **THEN** exactly one `event_updated` row and job exist, addressed to the replied guest

#### Scenario: Declined guest and a removal-only revision
- **WHEN** a declined guest holds a live token and the organizer only removes instants
- **THEN** the declined guest receives no `event_updated` mail

#### Scenario: Declined guest and an addition
- **WHEN** a declined guest holds a live token and the organizer adds an instant
- **THEN** the declined guest receives one `event_updated` mail

#### Scenario: Revision before any reply is silent
- **WHEN** no guest has `responded_at` and the organizer revises with the box ticked
- **THEN** no `event_updated` row or job is created

#### Scenario: Cap refusal is counted, not raised
- **WHEN** one recipient already has five non-failed `event_updated` rows for the event
- **THEN** the revision commits, that recipient is skipped, the others are mailed and the notice ends with "1 skipped (recently notified). Try again after 10 minutes."

#### Scenario: Unticked box sends nothing
- **WHEN** the organizer revises with `notice[send]` absent
- **THEN** the offer changes and no `event_updated` row is created

### Requirement: The guest page tells a replied guest what changed
On `GET /p/:token` (and the session family) after a revision the page SHALL show the current offer with the guest's surviving picks pre-painted and pre-serialized. At the top of the action bar an inline notice with `role="status"` SHALL read, for a counting guest with `responded_at < event.offer_revised_at`: "The organizer changed the offered times on <date in picker zone>: N added, M removed. Check your picks and save again."; for a voided guest (`reply_voided_at` set): "None of the times you picked are offered any more. Pick again." with Save enabled and nothing pre-painted (`#my-time-slots` empty); for a declined guest with `responded_at < offer_revised_at` and `offer_revision_added > 0`: "You said none of these worked. New times were added." Saving or declining SHALL clear the condition. The `sessionStorage` re-apply in `time_slot_show.js` SHALL keep only stashed keys present in `offeredKeys`, through the exported pure helper `filterStash(keys, offeredKeys)` covered by `node --test`, so a stale save cannot loop on cells that no longer exist.

#### Scenario: Stale counting guest
- **WHEN** a guest who saved before the revision and still holds a pick opens their link
- **THEN** the action bar shows "The organizer changed the offered times on <date>: N added, M removed. Check your picks and save again." with the date in the picker zone and the surviving pick painted

#### Scenario: Voided guest
- **WHEN** a voided guest opens their link
- **THEN** the page shows "None of the times you picked are offered any more. Pick again.", `#my-time-slots` is empty and the Save button is present

#### Scenario: Declined guest sees additions only
- **WHEN** a declined guest opens their link after a revision that added instants, and again after one that only removed instants
- **THEN** the first page shows "You said none of these worked. New times were added." and the second shows no revision notice

#### Scenario: Saving clears the notice
- **WHEN** a voided guest paints an offered cell and saves
- **THEN** the redirected page shows no revision notice and the organizer table shows the guest as replied

#### Scenario: Stash is filtered to the offer
- **WHEN** the stash holds 10:00 and 11:00, the offer no longer contains 11:00, and the page reloads with an alert
- **THEN** only 10:00 is re-painted and `filterStash(["<10:00>", "<11:00>"], ["<10:00>"])` returns `["<10:00>"]`

### Requirement: The organizer page shows who has not answered the current times
`ParticipationsHelper#guest_state` SHALL return `:needs_reply`, rendered "needs a new reply", for a guest with `reply_voided_at` set, and SHALL render "replied (N slots, before the last change)" for a counting guest whose `responded_at < event.offer_revised_at`. `@counts` SHALL gain `stale` and `voided`; while either is positive the organizer's finalize action bar SHALL warn "1 guest has not answered the current times" (with the actual count).

#### Scenario: Voided guest in the table
- **WHEN** the organizer opens the event after a revision voided one guest
- **THEN** that guest's row reads "needs a new reply" and the action bar reads "1 guest has not answered the current times"

#### Scenario: Stale reply in the table
- **WHEN** a counting guest saved before the last revision and still holds two picks
- **THEN** the row reads "replied (2 slots, before the last change)" and `@counts[:stale]` is 1

#### Scenario: State flips after a new reply
- **WHEN** the voided guest paints and saves through their link and the organizer reloads
- **THEN** the row reads "replied (N slots)", `@counts[:voided]` is 0 and the warning is gone
