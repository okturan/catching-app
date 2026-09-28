## MODIFIED Requirements

### Requirement: A guest sees the event and the offer through their link
`GET /p/:token` for a guest (and `GET /participations/:id` for a claimed guest) SHALL render the event name, description, organizer display name, the reply summary, a time-zone picker preselected to the guest's saved `time_zone` (else the browser zone) captioned with the event zone, an optional "Your name" field, and the show grid with the organizer's offered instants, the guest's saved instants pre-painted and pre-serialized, and per-cell counts of other counting participants. The page MUST NOT reveal other guests' email addresses.

While the event is open (`Event#open?`), the page SHALL additionally show, at the top of the action bar, an inline notice with `role="status"` when one of these conditions holds for the guest:
- a counting guest (`responded_at` set; `declined_at`, `left_at` and `reply_voided_at` NULL) whose `responded_at` is earlier than `events.offer_revised_at`: "The organizer changed the offered times on <date>: N added, M removed. Check your picks and save again." where N is `events.offer_revision_added` and M is `events.offer_revision_removed`, with the surviving picks pre-painted and pre-serialized;
- a voided guest (`reply_voided_at` set): "None of the times you picked are offered any more. Pick again." with Save enabled and nothing pre-painted (`#my-time-slots` is empty);
- a declined guest whose `responded_at` is earlier than `events.offer_revised_at` while `events.offer_revision_added > 0`: "You said none of these worked. New times were added." (a revision that only removed instants shows a declined guest no notice);
- a guest whose `responded_at` is set and earlier than `events.reopened_at`: "The set time was withdrawn on <date>. Check your picks and save." with the painted cells intact.

A guest with `responded_at` NULL SHALL see no notice; their first open shows the current offer. Every `<date>` in these notices SHALL be rendered server-side as `<time datetime="<iso8601>" data-zoned-instant>` in the event zone with the zone name, and `time_slot_show.js` SHALL rewrite every `[data-zoned-instant]` on the page into the picker zone on load and on every zone change. Saving or declining SHALL clear the condition (`responded_at` moves past `offer_revised_at` and `reopened_at`; `reply_voided_at` is cleared), so the redirected page shows no notice.

#### Scenario: Guest page contract
- **WHEN** a guest with two saved slots opens their link
- **THEN** the page contains `table#time-grid-show[role=grid][data-role="guest"][data-slot-minutes]`, `#received-time-slots` with the offer, `#my-time-slots` with the two instants, `#availability-counts`, and no email address of another guest

#### Scenario: Saved zone is preferred
- **WHEN** a guest who saved `Asia/Kolkata` reopens their link from a browser in `Europe/Berlin`
- **THEN** the zone picker is preselected to `Asia/Kolkata`

#### Scenario: Stale counting guest sees what changed
- **WHEN** a guest who saved 10:00 and 12:00 before a revision that added 4 instants and removed 12:00 opens their link
- **THEN** the action bar shows a `[role="status"]` notice "The organizer changed the offered times on <date>: 4 added, 1 removed. Check your picks and save again.", 10:00 is pre-painted and `#my-time-slots` lists only 10:00

#### Scenario: Voided guest is asked to pick again
- **WHEN** a guest whose every pick was removed by a revision (`reply_voided_at` set) opens their link
- **THEN** the action bar shows a `[role="status"]` notice "None of the times you picked are offered any more. Pick again.", `#my-time-slots` is empty, no cell is pre-painted and the Save button is present

#### Scenario: Declined guest sees additions only
- **WHEN** a declined guest opens their link after a revision that added instants, and another declined guest opens theirs after a revision that only removed instants
- **THEN** the first page shows "You said none of these worked. New times were added." and the second page shows no revision notice

#### Scenario: Withdrawn time note after a reopen
- **WHEN** a guest who saved availability before the organizer reopened the set time opens their link
- **THEN** the grid is paintable with their cells pre-painted, `#availability-form` is present and the action bar shows a `[role="status"]` notice "The set time was withdrawn on <date>. Check your picks and save."

#### Scenario: Notice dates are zoned and named
- **WHEN** a revision or reopen notice is rendered for an event in `Europe/Berlin` and the guest's picker is set to `Asia/Kolkata`
- **THEN** the server markup carries `<time datetime="<iso8601>" data-zoned-instant>` reading the event-zone time with "(Europe/Berlin)", and after load the element reads the same instant in `Asia/Kolkata` with that zone name

#### Scenario: Unreplied guest sees no notice
- **WHEN** an invited guest who never replied opens their link after a revision and after a reopen
- **THEN** the page shows the current offer and no inline notice

#### Scenario: Saving clears the notice
- **WHEN** a voided guest paints an offered cell and saves, and a stale guest saves after a reopen
- **THEN** each redirected page shows no revision or withdrawal notice

### Requirement: Saving availability replaces the guest's slots atomically
`PATCH /p/:token` (guest only) SHALL parse `time_slots[time_slot_array]` with the event's `slot_minutes`, verify every instant is on the event grid, is offered by the organizer, and is not before the past cut-off, then inside `event.with_lock` delete the guest's slots and insert the new ones with `insert_all!`, set `responded_at`, `name` and `time_zone`, and clear `declined_at` and `reply_voided_at` in the same `update!` (the check `participants_voided_is_open_reply` makes any other order a `StatementInvalid`), and redirect with notice "Availability saved.". Because neither an offer revision nor a reopen resets `responded_at`, a re-reply by a voided or stale guest is not a first reply and SHALL enqueue no second `response_confirmation`. Validation failures SHALL redirect back with status 303 and the exact alert: "Select at least one time slot", "Select only time slots offered by the organizer", "Select time slots on the event's <n>-minute grid", "Select time slots from today onward", "Availability is closed for this event" (finalized), "This event was cancelled" (cancelled; `ensure_pending!` raises it before the finalized message), or the time-zone error. A save that carries instants an offer revision removed SHALL be refused with "Select only time slots offered by the organizer" by the existing `ensure_slots_were_offered!` check, whether the guest painted them on a stale page or the revision acquired the lock first; a save that acquires the lock before the revision is trimmed or voided by it like any other reply.

#### Scenario: Valid save replaces only the guest's slots
- **WHEN** a guest with slots at 10:00 and 11:00 saves 11:00 and 12:00 (all offered)
- **THEN** the guest's slots are exactly 11:00 and 12:00, the organizer's slots are unchanged, `responded_at` is set and the redirect carries "Availability saved."

#### Scenario: Unoffered instant is refused without changing anything
- **WHEN** a guest saves an instant the organizer did not offer
- **THEN** the response is 303 with alert "Select only time slots offered by the organizer" and the guest's previous slots remain

#### Scenario: Off-grid instant is refused
- **WHEN** the event uses 60-minute slots and a guest saves 10:30
- **THEN** the response is 303 with alert "Select time slots on the event's 60-minute grid"

#### Scenario: Closed event refuses changes
- **WHEN** a guest saves availability on a finalized event
- **THEN** the response is 303 with alert "Availability is closed for this event" and no row changes

#### Scenario: Cancelled event refuses changes
- **WHEN** a guest saves availability on a cancelled event, whether it was pending or finalized when cancelled
- **THEN** the response is 303 with alert "This event was cancelled" and no row changes

#### Scenario: Invalid time zone is refused
- **WHEN** a guest saves with `participant[time_zone]=Mars/Olympus`
- **THEN** the response is 303 with an alert naming the time zone and no slot changes

#### Scenario: Voided guest saves again
- **WHEN** a guest with `reply_voided_at` set saves one offered instant
- **THEN** `reply_voided_at` is NULL, `declined_at` is NULL, `responded_at` is updated, the guest is in `Participant.counting`, the redirect carries "Availability saved." and no `response_confirmation` mail is enqueued

#### Scenario: Stale cells after a revision are refused
- **WHEN** a guest who left the old page open submits a selection containing an instant the organizer has since removed
- **THEN** the response is 303 with alert "Select only time slots offered by the organizer" and the guest's slots are unchanged

### Requirement: Past instants are not selectable and unsaved paint survives a rejection
The server SHALL pass the parser's past cut-off on the grid root (`data-not-before`); the grid SHALL mark earlier offered instants as past (not selectable, `aria-disabled="true"`, muted) and exclude them from the summary. When no offered instant is at or after `TimeSlotParser::PAST_GRACE.ago` — including after a reopen whose offer has since passed — the open guest page SHALL show "All the offered times have passed." in the action bar and hide Save. The component SHALL stash the last serialized selection in `sessionStorage` keyed by token before submit and re-apply it after a redirect back with an alert; the re-apply SHALL keep only stashed keys present in `offeredKeys`, through the exported pure helper `filterStash(keys, offeredKeys)` covered by `node --test`, so a reload after a rejected stale save cannot loop on cells that are no longer offered.

#### Scenario: Expired offer shows the empty state
- **WHEN** every offered instant is before the cut-off
- **THEN** the page shows "All the offered times have passed." and no Save button

#### Scenario: Every offered time passed after a reopen
- **WHEN** the organizer reopens a set time on an event whose every offered instant is now before `TimeSlotParser::PAST_GRACE.ago` and a guest opens their link
- **THEN** the guest page shows "All the offered times have passed." and Save is hidden

#### Scenario: Rejected save keeps the painted cells
- **WHEN** a save is rejected with a 303 alert
- **THEN** after the page reloads the previously painted cells are painted again and the alert is visible in the action bar

#### Scenario: Stash is filtered to the offer
- **WHEN** the stash holds 10:00 and 11:00, the offer no longer contains 11:00, and the page reloads with an alert
- **THEN** only 10:00 is re-painted, the hidden `#new-time-slot-array` lists only 10:00 and a second Save is not refused for 11:00

#### Scenario: filterStash is a pure helper
- **WHEN** `filterStash(["<10:00>", "<11:00>"], ["<10:00>"])` is called under `node --test`
- **THEN** it returns `["<10:00>"]` without touching the DOM or `sessionStorage`

### Requirement: A guest can say none of these times work
`POST /p/:token/decline` (guest only) SHALL, inside `event.with_lock`, run `ensure_pending!`, delete the guest's slots, and set `responded_at` and `declined_at` while clearing `reply_voided_at` in the same `update!` (`Event#mark_unavailable!`; the check `participants_voided_is_open_reply` makes any other order a `StatementInvalid`), keep both tokens and `user_id`, and redirect with a notice. On a finalized event it SHALL answer 303 "Availability is closed for this event"; on a cancelled event 303 "This event was cancelled". A declined guest SHALL be excluded from consensus and MAY change the answer later by saving availability, which clears `declined_at`. A guest who declines after an offer revision or a reopen SHALL no longer see the inline notice on the redirected page.

#### Scenario: Decline clears slots and keeps the link
- **WHEN** a guest with saved slots declines
- **THEN** the guest has zero slots, `declined_at` is set, the same link still returns 200, and the guest is not in `participants.counting`

#### Scenario: Saving after declining reverses it
- **WHEN** a declined guest saves an offered instant
- **THEN** `declined_at` is NULL and the guest counts again

#### Scenario: Voided guest declines
- **WHEN** a guest with `reply_voided_at` set declines
- **THEN** `declined_at` is set and `reply_voided_at` is NULL after one `update!`, no `StatementInvalid` is raised, and the redirected page shows no revision notice

#### Scenario: Cancelled event refuses decline
- **WHEN** a guest of a cancelled event posts to `/p/:token/decline`
- **THEN** the response is 303 with alert "This event was cancelled" and `declined_at` and the guest's slots are unchanged

### Requirement: A guest can leave the event for good
`DELETE /p/:token` (guest only) SHALL call `Participant#leave!` and respond with a 303 redirect to the site root carrying the notice "You left <event name>." `leave!` SHALL NOT call `ensure_pending!` and SHALL clear `reply_voided_at` in the same `update!` that sets `responded_at`, `declined_at`, `left_at` and clears `user_id` and both token digests. `refuse_closed_writes` SHALL be skipped for `ParticipationsController#destroy`, so Leave works while pending, finalized and cancelled, and "Leave this event" SHALL render on pending, finalized and cancelled guest pages. A left guest's links SHALL return 404 in both families, the guest SHALL receive no further mail (`finalized`, `event_updated`, `reopened` and `cancelled` included), and the row SHALL NOT be revived by invite-more, resend or bulk send. A `pageshow` handler SHALL reload a bfcache-restored capability page so a dead grid is never shown.

#### Scenario: Leave redirects and revokes
- **WHEN** a guest confirms "Leave this event"
- **THEN** the response redirects to the root with "You left <event name>.", the slots are gone, `left_at` and `declined_at` are set, `reply_voided_at`, both digests and `user_id` are NULL, and the next GET with the old link is 404

#### Scenario: Voided guest leaves
- **WHEN** a guest with `reply_voided_at` set confirms "Leave this event"
- **THEN** `left_at` is set and `reply_voided_at` is NULL without a `StatementInvalid`

#### Scenario: Leave on a finalized event
- **WHEN** a guest of a finalized, not cancelled event submits `DELETE /p/:token`
- **THEN** the response is 303 to the site root with "You left <event name>.", `left_at` is set and the response is not "Availability is closed for this event"

#### Scenario: Leave on a cancelled event
- **WHEN** a guest of a cancelled event submits `DELETE /p/:token`
- **THEN** the response is 303 to the site root with "You left <event name>.", `left_at` is set and the response is not "This event was cancelled"

#### Scenario: Left guest is not re-invited by resend
- **WHEN** the organizer presses "Send invitations" after a guest left
- **THEN** the left guest receives no mail and no token

### Requirement: Finalized events are read-only for guests
When the event is closed (`Event#open?` false: finalized or cancelled) the guest page SHALL render `#time-grid-show[data-role="viewer"]` (`viewer_role` is `"viewer"` whenever `@event.open?` is false), SHALL render neither `#availability-form` nor the decline form, and SHALL keep only **Leave this event** (`DELETE /p/:token`) and, for an unclaimed guest on a token request, **Keep this event in your account** (`POST /p/:token/claim`); both SHALL keep working, and every GET SHALL keep working for every valid token in both families.

When finalized (`status` true, `cancelled_at` NULL) the page SHALL show the confirmed window rendered server-side in the event zone with the zone name and, through the grid component, in the picker zone, `data-finalized` on the grid, and the plate button **Add to calendar** linking to `scoped_path(:calendar)` (`GET /p/:token/calendar.ics`); save and decline SHALL be refused 303 with "Availability is closed for this event".

When cancelled (`cancelled_at` set) the page SHALL show the heading followed by an inline `plate plate-ink` "Cancelled" and `data-cancelled` on the grid; save and decline SHALL be refused 303 with "This event was cancelled", which `ensure_pending!` raises before the finalized message even when the event was finalized first.

#### Scenario: Finalized guest page
- **WHEN** an unclaimed guest opens their link after finalization
- **THEN** the page shows the window twice (event zone and picker zone), `#time-grid-show[data-finalized][data-role="viewer"]` is present, the **Add to calendar** link points at `/p/<token>/calendar.ics`, **Leave this event** and **Keep this event in your account** are rendered, and no `#availability-form` or decline form is rendered

#### Scenario: Guest writes are refused after finalization
- **WHEN** a guest of a finalized event submits `PATCH /p/:token` and `POST /p/:token/decline`
- **THEN** both responses are 303 with "Availability is closed for this event" and no slot or participant row changes

#### Scenario: Leave and Claim still work on a finalized event
- **WHEN** a guest sends `DELETE /p/:token` on a finalized event, and a signed-in unclaimed guest posts `POST /p/:token/claim` on another finalized event
- **THEN** the first guest's `left_at` is set with the redirect "You left <event name>.", the second participation's `user_id` is set, and neither response is "Availability is closed for this event"

#### Scenario: Cancelled guest page
- **WHEN** a guest opens their link on a cancelled event
- **THEN** the page renders 200 with `#time-grid-show[data-role="viewer"][data-cancelled]`, the ink "Cancelled" plate, the Leave form and, for an unclaimed token request, the Claim control, and no `#availability-form`, decline form or `#finalize-form`

#### Scenario: Guest writes are refused after cancellation
- **WHEN** a guest of an event that was finalized and then cancelled submits `PATCH /p/:token` and `POST /p/:token/decline`
- **THEN** both responses are 303 with "This event was cancelled", not "Availability is closed for this event", and no row changes

#### Scenario: Leave and Claim still work on a cancelled event
- **WHEN** a guest sends `DELETE /p/:token` on a cancelled event, and a signed-in unclaimed guest posts `POST /p/:token/claim` on another cancelled event
- **THEN** the first guest's `left_at` is set and the second participation's `user_id` is set, neither answering "This event was cancelled"
