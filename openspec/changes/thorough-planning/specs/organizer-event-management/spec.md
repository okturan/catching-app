## MODIFIED Requirements

### Requirement: The organizer page shows every participant and the reply state
`GET /p/:token` for an organizer (and `GET /participations/:id` for a claimed organizer) SHALL render a participant table with, per guest: email, name, and one state among "not sent", "queued", "sent on <date>", "delivery unknown, resend" (queued for more than 15 minutes), "could not be delivered", "replied (N slots)", "replied (N slots, before the last change)", "needs a new reply", "none of these work", "left". Delivery states SHALL be derived from the guest's `invitation` ledger rows as before.

The state "needs a new reply" SHALL be shown when the guest's `reply_voided_at` is present (a guest who replied and was left with no offered slot by an offer revision; by the check `participants_voided_is_open_reply` such a guest has `responded_at`, no `declined_at` and no `left_at`). The state "replied (N slots, before the last change)" SHALL be shown for a counting guest whose `responded_at` is earlier than `events.offer_revised_at`, N being the slots the guest still holds; a counting guest who saved after the last revision, or on an event whose offer was never revised, SHALL read "replied (N slots)". Declined, unreplied and left guests SHALL keep their labels through an offer revision.

While the event is not cancelled the page SHALL render a Resend and a Remove control per active guest and an "Invite more people" textarea; on a cancelled event the participant table SHALL be read-only (no Send, Resend, Show link to copy, Remove or Invite more controls).

The reply summary SHALL carry separate counts: n = active guests with a live token, k = counting guests (`responded_at` set, `declined_at` NULL, `left_at` NULL, `reply_voided_at` NULL), d = declined guests, u = guests not yet invited, and additionally `stale` = counting guests with `responded_at < events.offer_revised_at` and `voided` = guests with `reply_voided_at` present. A voided guest SHALL NOT count toward k. While `stale` or `voided` is positive the organizer's action bar SHALL show the warning "1 guest has not answered the current times" (with the number of guests concerned).

While no guest counts, the page SHALL show the waiting state ("No replies yet. Invitations sent to N people.") with the grid in viewer mode and no finalize form; once at least one guest counts and the event is open the grid SHALL be in organizer mode with consensus cells selectable and `#finalize-form` present. When no offered instant is at or after `TimeSlotParser::PAST_GRACE.ago`, the organizer action bar SHALL read "Every offered time has passed. Change the times." with the **Change the times** plate button. On a cancelled event `#time-grid-show` SHALL carry `data-role="viewer"` and `data-cancelled`.

#### Scenario: Counts are defined by scopes
- **WHEN** an event has 5 guests: 2 replied, 1 declined, 1 invited with no reply, 1 never sent
- **THEN** the summary shows 4 invited, 2 replied, 1 cannot make it, 1 not yet invited, and `stale` and `voided` are both 0

#### Scenario: Waiting state before any reply
- **WHEN** invitations were sent and nobody has replied
- **THEN** the page shows "No replies yet" with the number invited and `#time-grid-show[data-role="viewer"]`, and no finalize form

#### Scenario: A voided guest needs a new reply
- **WHEN** an offer revision removes every instant a replied guest had picked, so `reply_voided_at` is set
- **THEN** that guest's row reads "needs a new reply", `voided` is 1, the guest is not counted in k, and the action bar shows "1 guest has not answered the current times"

#### Scenario: A trimmed guest replied before the last change
- **WHEN** a guest who picked three slots loses one of them to an offer revision and has not saved since
- **THEN** the row reads "replied (2 slots, before the last change)", `stale` is 1, the guest still counts in k, and the action bar shows "1 guest has not answered the current times"

#### Scenario: Saving again flips the state back
- **WHEN** the voided guest opens their link, paints at least one offered time and saves with `PATCH /p/:token`
- **THEN** `reply_voided_at` is NULL, the row reads "replied (N slots)", `voided` is 0 and the warning is absent from the action bar

#### Scenario: Declined and unreplied guests are unchanged by a revision
- **WHEN** an offer revision runs on an event with one declined guest and one invited guest who never replied
- **THEN** the declined row still reads "none of these work", the unreplied row still shows its delivery state, and neither is counted as `stale` or `voided`

#### Scenario: Voiding can leave nobody counting
- **WHEN** a revision voids the only guest who had replied
- **THEN** k is 0, `voided` is 1, no finalize form is rendered, the action bar shows "1 guest has not answered the current times", and `POST …/finalization` is refused with "Wait for at least one reply before confirming"

#### Scenario: Every offered time has passed
- **WHEN** every offered instant of an open event is before `TimeSlotParser::PAST_GRACE.ago`
- **THEN** the organizer action bar reads "Every offered time has passed. Change the times." with a plate button linking to `scoped_path(:offer, edit: true)`

#### Scenario: Cancelled event table is read-only
- **WHEN** the organizer opens a cancelled event through either family
- **THEN** the participant table renders every guest with no Send, Resend, Show link to copy, Remove or Invite more controls, `#time-grid-show[data-role="viewer"][data-cancelled]` is present, and the heading carries the ink "Cancelled" plate

### Requirement: Organizer capabilities are exactly these
An organizer SHALL be able to: send invitations, invite more, resend, show a link to copy, remove a guest, finalize (**Set in stone**), edit the event's details (`name`, `description`, `place`, `place_url`, `duration_minutes`) on the **Edit details** page (`GET …/details/edit`, `PATCH …/details`), edit the plan (add, change, move and remove items: `POST …/activities`, `PATCH`/`DELETE …/activities/:id`, `POST …/activities/:id/move`) on the same page, change the offered times (**Change the times**, `GET …/offer/edit`, `PATCH …/offer`) while the event is open, tell the guests about untold changes (**Tell the guests**, `POST …/notice`), cancel the event (**Cancel this event**, `POST …/cancellation`) while pending or finalized, reopen a set time (**Reopen the time**, `POST …/reopening`) at most twice, and download the calendar file (**Add to calendar**, `GET …/calendar.ics`) once finalized. Every one of these SHALL be a CSRF-protected form or link handled by a `ParticipationScopedController` subclass, gated by `require_organizer!` (a guest token SHALL receive the uniform 404), and reachable through both route families via `scoped_path` (`/p/:token/…` and `/participations/:participation_id/…`). Sending, invite-more, resend, show link and Tell the guests SHALL additionally require `link_opened_at`; details, plan, offer, cancel, reopen and calendar SHALL NOT.

The organizer SHALL NOT be able to respond as a guest (`PATCH /p/:token` with availability from an organizer token SHALL be 404), delete the event, clear `cancelled_at`, change `slot_minutes` or `time_zone` once any guest has `responded_at`, revise the offer while finalized (`GET …/offer/edit` and `PATCH …/offer` SHALL answer 303 "Reopen the time before changing the offer"), reopen a pending event (303 "Only a set time can be reopened") or reopen a third time (303 "This event was reopened twice already. Cancel it and plan a new one."). No route SHALL exist for deleting or un-cancelling an event, and `/events/:id/activities*` SHALL no longer route.

Controls SHALL follow the event state. While open (pending, not cancelled) the page SHALL offer Edit details, Change the times, Cancel this event and, once a guest counts, Set in stone, plus a hairline note "Reopened once" or "Reopened twice — the last time" after a reopen. Once finalized and not cancelled it SHALL offer Edit details, Reopen the time, Cancel this event and Add to calendar, and SHALL NOT offer Change the times. Tell the guests SHALL be shown, with the plate "Guests have not been told about your latest changes", only when `revision > notified_revision`, at least one active linked guest exists and the event is not cancelled. On a cancelled event every organizer write SHALL be refused with 303 "This event was cancelled" (the base `refuse_closed_writes`), every GET SHALL keep working, and the page SHALL offer none of these controls but a plate link **Plan a new event** → `new_event_path`.

#### Scenario: Offer revision goes through its own route
- **WHEN** an organizer token sends `PATCH /p/:token` with availability
- **THEN** the response is 404 and the offer is unchanged, while the same organizer's `PATCH /p/:token/offer` with `time_slots[time_slot_array]` revises the offer as `offer-revision` specifies

#### Scenario: Every organizer action routes in both families
- **WHEN** the route set is inspected
- **THEN** `edit_participation_details_path(TOKEN)`, `participation_offer_path`, `participation_notice_path`, `participation_cancellation_path`, `participation_reopening_path`, `participation_calendar_path` (→ `/p/<token>/calendar.ics`) and `participation_activity_move_path(TOKEN, 7)` (→ `/p/<token>/activities/7/move`) resolve, their `my_participation_*` counterparts resolve under `/participations/:participation_id/…`, and `/events/1/activities` does not route

#### Scenario: A guest token is refused on every organizer action
- **WHEN** a guest token requests `GET`/`PATCH …/details`, `GET`/`PATCH …/offer`, `POST …/notice`, `POST …/cancellation`, `POST …/reopening`, or any `POST`/`PATCH`/`DELETE` under `…/activities` (including `…/move`)
- **THEN** every response is the uniform 404 and nothing changes

#### Scenario: Controls while the event is open
- **WHEN** the organizer opens a pending, not cancelled event
- **THEN** the page offers Edit details (→ `scoped_path(:details, edit: true)`), Change the times (→ `scoped_path(:offer, edit: true)`) and Cancel this event, and offers neither Reopen the time nor Add to calendar

#### Scenario: Controls once the time is set
- **WHEN** the organizer opens a finalized, not cancelled event
- **THEN** the page offers Edit details, Reopen the time, Cancel this event and Add to calendar (→ `scoped_path(:calendar)`), Change the times is absent, and `GET …/offer/edit` answers 303 "Reopen the time before changing the offer"

#### Scenario: Tell the guests appears only while something is untold
- **WHEN** `revision > notified_revision`, at least one active linked guest exists and the event is not cancelled
- **THEN** the page shows "Guests have not been told about your latest changes" with the Tell the guests plate button; once `revision == notified_revision` the button is absent and `POST …/notice` answers 303 "Guests already know about every change."

#### Scenario: Tell the guests requires the opened organizer link
- **WHEN** the organizer's `link_opened_at` is NULL and they send `POST …/notice`
- **THEN** the response is 303 with the alert "Open your organizer link before emailing guests" and no mail is enqueued

#### Scenario: Cancelled event refuses every organizer write
- **WHEN** an event is cancelled and the organizer posts invitations, resend, link reveal, remove, finalization, details, offer, notice, an activity write, reopening or a second cancellation
- **THEN** each answers 303 with "This event was cancelled" and changes nothing, `cancelled_at` is unchanged, and the participation page GET and, for a finalized event, `…/calendar.ics` still answer 200

#### Scenario: Cancelled page offers only a fresh start
- **WHEN** the organizer opens a cancelled event
- **THEN** no Send, Resend, Show link to copy, Remove, Set in stone, Edit details, Change the times, Tell the guests, Reopen the time or Cancel this event control is rendered, and a plate link "Plan a new event" points to `new_event_path`

#### Scenario: Reopen is bounded
- **WHEN** the organizer sends `POST …/reopening` on a pending event, and on an event already reopened twice
- **THEN** the responses are 303 "Only a set time can be reopened" and 303 "This event was reopened twice already. Cancel it and plan a new one." respectively, and the event is unchanged in both cases

#### Scenario: Step and zone are frozen after the first reply
- **WHEN** a guest has `responded_at` and the organizer submits `event[slot_minutes]` or `event[time_zone]` with `PATCH …/offer`
- **THEN** the parameters are not permitted, `slot_minutes` and `time_zone` are unchanged, and `GET …/offer/edit` renders both selects `disabled` with the caption "Fixed since the first reply"
