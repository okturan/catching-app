## MODIFIED Requirements

### Requirement: Consensus counts responders only, in one statement
`Event#mutually_available_start_times` SHALL return the start times held by every counting participant. A participant counts when `responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND reply_voided_at IS NULL` (the organizer counts from creation). `Participant.counting` SHALL be `where.not(responded_at: nil).where(declined_at: nil, left_at: nil, reply_voided_at: nil)` and `Participant#counting?` SHALL apply the same four conditions. The query SHALL be one SQL statement: numerator filtered to counting participants, `HAVING COUNT(DISTINCT participant_id) = (correlated count of counting participants)` combined with `EXISTS` (at least one counting guest), where both the correlated count and the `EXISTS` guard carry `AND reply_voided_at IS NULL`, so the denominator and the guard share one snapshot and a guest voided by an offer revision can never block finalization. With no counting guest it SHALL return an empty list, and `ensure_replies!` SHALL raise "Wait for at least one reply before confirming" when voiding left no counting guest. A guest who keeps at least one slot after a revision SHALL stay counting. `assert_queries_count(1)` in `test/models/event_test.rb` SHALL keep holding.

#### Scenario: Silent invitee does not block
- **WHEN** the organizer offered 10:00 and 11:00, guest A saved 10:00, and guest B never replied
- **THEN** consensus is `[10:00]`

#### Scenario: Declined guest is excluded
- **WHEN** guest A saved 10:00 and guest B declined
- **THEN** consensus is `[10:00]`

#### Scenario: Organizer alone yields nothing
- **WHEN** no guest counts
- **THEN** consensus is empty and the query count for the call is exactly one

#### Scenario: Voided guest is excluded
- **WHEN** guest A saved 10:00, guest B's only pick was removed by an offer revision so B has `reply_voided_at` set, and the organizer still offers 10:00
- **THEN** consensus is `[10:00]`, B is absent from `Participant.counting` and `B.counting?` is false

#### Scenario: Trimmed guest still counts
- **WHEN** guest B saved 10:00 and 12:00 and an offer revision removed 12:00
- **THEN** B has `reply_voided_at` NULL, stays in `Participant.counting` and is part of the consensus denominator

#### Scenario: Voiding leaves nobody counting
- **WHEN** the only guest who replied is voided by an offer revision and the organizer finalizes
- **THEN** the response is 303 with "Wait for at least one reply before confirming" and `status` stays false

#### Scenario: The predicate is one statement
- **WHEN** `mutually_available_start_times` is called on an event with counting, declined and voided guests
- **THEN** exactly one query runs and both its correlated count and its `EXISTS` guard contain `reply_voided_at IS NULL`

### Requirement: Finalization notifies everyone with a live link
After `finalize!` commits, `Deliveries.finalized!(event:)` SHALL enqueue `ParticipantMailer#finalized` once per participant in `participants.active.linked` (including declined guests who still hold a link; excluding left and never-invited guests), each as its own job with its own `finalized` ledger row, and SHALL pass `window: [start_time, end_time]` in the mailer params; `ParticipantMailer#finalized` and the attached `CalendarFile` SHALL build from those params, never from the event row, so a retry after `reopen!` still renders. Links: for an unclaimed guest `Deliveries.finalized!` SHALL issue a pending token with `issue_pending_token!` (never expiring; it retires the previous pending token while the live token from the invitation keeps working) and pass `token:`, so the body carries `/p/<pending token>`; for a claimed guest it SHALL pass no token and the mailer SHALL link `my_participation_url(participant)`; the organizer's copy SHALL carry no link and SHALL say "Open your organizer link". The subject SHALL be unchanged. The body SHALL add "Where: <mail_safe(place)>" and "How long: <duration>" when set, the plan with derived starts in the recipient zone and the event zone when every preceding item has a duration, the closing sentence exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels.", and SHALL end with the standing sentence "To stop hearing about this event, open your link and choose Leave this event." The mail SHALL attach `catching-app.ics` (`mime_type: "text/calendar; method=PUBLISH"`) built in mail mode: `STATUS:CONFIRMED`, `SEQUENCE` equal to `events.revision`, no `://`, no `URL`, no description, no capability token, at most 8 KB. `place_url` MUST never appear in the body, subject or attachment. `finalize!` SHALL bump `events.revision` inside its `with_lock` transaction; `notified_revision` SHALL be set to `revision` after the batch. `finalized` SHALL stay exempt from every cap and MAY be sent up to three times per event (the initial finalization plus one after each of at most two reopenings).

#### Scenario: One job per linked participant
- **WHEN** an event with an organizer, two invited guests (one declined), one unsent guest and one left guest is finalized
- **THEN** exactly three `finalized` jobs are enqueued and exactly three `finalized` ledger rows are created

#### Scenario: Unclaimed guest gets a fresh pending token
- **WHEN** an unclaimed guest with a live token and an unused pending token from a Resend receives the `finalized` mail
- **THEN** the body carries `/p/<new pending token>`, a GET with it changes no digest, the previous pending link answers 404 and the live invitation link still opens the page

#### Scenario: Claimed guest gets the signed-in link
- **WHEN** a guest whose `user_id` is set receives the `finalized` mail
- **THEN** no token is issued and the body carries `/participations/<id>`

#### Scenario: Organizer copy carries no link
- **WHEN** the organizer receives the `finalized` mail
- **THEN** the body contains neither a `/p/` nor a `/participations/` URL and says "Open your organizer link"

#### Scenario: Facts and closing sentence in the mail
- **WHEN** the finalized event has `place` "Ege's place" and `place_url` "https://zoom.us/j/1" and a guest receives the mail
- **THEN** both parts contain "Where: Ege's place", `place_url` appears nowhere in subject, body or attachment, the closing sentence is exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels." and the body ends with "To stop hearing about this event, open your link and choose Leave this event."

#### Scenario: Attachment is a confirmed calendar file
- **WHEN** the `finalized` attachment is decoded
- **THEN** it is a valid calendar file named `catching-app.ics` with `STATUS:CONFIRMED`, `SEQUENCE` equal to `events.revision`, `DTSTART`/`DTEND` equal to the window passed in params in UTC, no `://` and a size of at most 8 KB

#### Scenario: Window comes from params, not the row
- **WHEN** a queued `finalized` job is performed after `reopen!` has set `status` false and cleared `start_time`/`end_time`
- **THEN** the mail renders the window passed as `window:` in the params and the job does not raise

#### Scenario: Finalize bumps revision and marks guests told
- **WHEN** an event at `revision` N is finalized
- **THEN** `revision` is N + 1 in the same `with_lock` transaction as the window and, after the batch, `notified_revision` equals `revision`

#### Scenario: Finalized may be sent three times
- **WHEN** an event runs finalize, reopen, revise, finalize, reopen, finalize
- **THEN** exactly three `finalized` batches are sent, each with one row per active linked participant, none refused by a cap, and each attachment's `SEQUENCE` is higher than the previous one

### Requirement: The closed event is read-only everywhere
After finalization (`status` true, `cancelled_at` NULL) the organizer and guest pages SHALL show the confirmed window (event zone server-side, picker zone client-side), `#time-grid-show[data-finalized]` SHALL be present with `data-role="viewer"` (`viewer_role` is `"viewer"` whenever `@event.open?` is false), and both pages SHALL show the **Add to calendar** plate button linking to `scoped_path(:calendar)`. Every availability write in either family SHALL be refused with "Availability is closed for this event" (`Event::ClosedError` from `ensure_pending!`, answered 303): guest save, decline, a second finalization and `Event#revise_offer!`; the offer page (`GET` and `PATCH …/offer`) SHALL answer 303 "Reopen the time before changing the offer". The send, resend, link reveal and remove forms SHALL NOT render after finalization. The following SHALL be allowed after finalization: **Edit details** (`GET …/details/edit`, `PATCH …/details`), plan writes (`POST …/activities`, `PATCH`/`DELETE …/activities/:id`, `POST …/activities/:id/move`), **Reopen the time** (`POST …/reopening`), **Cancel this event** (`POST …/cancellation`), the calendar download (`GET …/calendar.ics`), Leave (`DELETE /p/:token`) and Claim (`POST /p/:token/claim`). Once the event is cancelled, `ensure_pending!` SHALL raise "This event was cancelled" before the finalized message, reopen SHALL be refused with it too, and only Leave and Claim remain.

#### Scenario: Organizer page after finalize
- **WHEN** the organizer opens the event after finalizing
- **THEN** the page shows the window, `#time-grid-show[data-finalized][data-role="viewer"]`, the **Add to calendar**, **Edit details**, **Reopen the time** and **Cancel this event** controls, and no finalize, send, resend, reveal or remove form

#### Scenario: Guest page after finalize
- **WHEN** an unclaimed guest opens their link after finalization
- **THEN** the page shows the window twice (event zone and picker zone), `#time-grid-show[data-finalized][data-role="viewer"]`, **Add to calendar**, **Leave this event** and **Keep this event in your account**, and no save or decline form

#### Scenario: Guest save is refused
- **WHEN** a guest submits availability on a finalized event in either family
- **THEN** the response is 303 with "Availability is closed for this event" and no slot row changes

#### Scenario: Offer page is refused until reopen
- **WHEN** the organizer opens or submits `…/offer` on a finalized event
- **THEN** the response is 303 with "Reopen the time before changing the offer" and the offer is unchanged

#### Scenario: Details are editable after finalize
- **WHEN** the organizer submits `PATCH …/details` with a new `place` on a finalized event
- **THEN** the response is 303 with "Details saved.", `place` is stored, `revision` is bumped and the window is untouched

#### Scenario: The plan is editable after finalize
- **WHEN** the organizer posts `POST …/activities` on a finalized event
- **THEN** the item is created, `revision` is bumped and the window is untouched

#### Scenario: Reopen is allowed
- **WHEN** the organizer posts `POST …/reopening` on a finalized event with `reopen_count` below 2
- **THEN** the response is 303 with "The set time was withdrawn. N guests were told.", `status` is false, `start_time` and `end_time` are NULL and the page no longer carries `data-finalized`

#### Scenario: Cancel is allowed
- **WHEN** the organizer posts `POST …/cancellation` on a finalized event
- **THEN** the response is 303 with "Event cancelled. N people were told.", `cancelled_at` is set, `status`, `start_time` and `end_time` are untouched and the page shows "Was set for <window>"

#### Scenario: Leave and Claim still work
- **WHEN** a guest sends `DELETE /p/:token` on a finalized event, and a signed-in unclaimed guest posts `POST /p/:token/claim` on another finalized event
- **THEN** the first guest's `left_at` is set and the second participation's `user_id` is set, neither answering "Availability is closed for this event"

#### Scenario: Cancelled after finalize
- **WHEN** a finalized event is cancelled and the organizer then posts `POST …/reopening` while a guest submits availability
- **THEN** both responses are 303 with "This event was cancelled"
