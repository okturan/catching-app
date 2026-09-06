## ADDED Requirements

### Requirement: Cancellation is a terminal, non-destructive event state
`events` SHALL gain `cancelled_at datetime NULL`. `Event#cancelled?` SHALL be `cancelled_at.present?`, `Event#open?` SHALL be `!status? && !cancelled?` and `Event#closed?` SHALL be `status? || cancelled?`. `Event#cancel!` SHALL run inside `with_lock`, raise `Event::ClosedError` "This event was cancelled" when the event is already cancelled, and otherwise `update!(cancelled_at: now, revision: revision + 1)`. Cancellation SHALL delete no row in `events`, `participants`, `time_slots`, `activities` or `mail_deliveries`, SHALL leave every token and claim valid, and SHALL leave `status`, `start_time` and `end_time` untouched. A model validation SHALL make `cancelled_at` immutable once set with the error "cannot be changed once cancelled". There SHALL be no un-cancel, no reopen after cancel and no delete.

#### Scenario: Cancel stamps the event and bumps the revision
- **WHEN** `cancel!` is called on a pending event with `revision` 3
- **THEN** `cancelled_at` is set, `revision` is 4, `cancelled?` is true, `open?` is false, `closed?` is true and `status` is still false

#### Scenario: Cancelling a finalized event keeps its window
- **WHEN** `cancel!` is called on a finalized event
- **THEN** `status` stays true and `start_time` and `end_time` are unchanged while `cancelled_at` is set

#### Scenario: Second cancel raises
- **WHEN** `cancel!` is called on an event whose `cancelled_at` is already set
- **THEN** it raises `Event::ClosedError` with the message "This event was cancelled" and nothing changes

#### Scenario: The timestamp cannot be changed or cleared
- **WHEN** a cancelled event is assigned a different `cancelled_at` or `nil` and validated
- **THEN** validation fails with "cannot be changed once cancelled" on `cancelled_at`

#### Scenario: Nothing is deleted
- **WHEN** an event with two guests, four time slots, one plan item and five ledger rows is cancelled
- **THEN** every one of those rows still exists and every guest token still resolves

### Requirement: Cancel is organizer-only through both families
`POST /p/:token/cancellation` and `POST /participations/:participation_id/cancellation` SHALL route to `Participations::CancellationsController#create`, gated by `require_organizer!` (404 for a guest token) with no `link_opened_at` requirement, and SHALL be accepted while pending or after finalization. The organizer page SHALL render, below the guests section, a `button_to "Cancel this event"` (`btn btn-outline-danger`) with `turbo_confirm` "Cancel <event> for everyone? Everyone with a link gets one last email. This cannot be undone." The action SHALL call `Event#cancel!`, then `Deliveries.cancelled!(event:)` after commit, and redirect 303 to `scoped_path` with the notice "Event cancelled. N people were told." where N is the number of `cancelled` rows created. A second cancel SHALL answer 303 with the alert "This event was cancelled".

#### Scenario: Guest token is not found
- **WHEN** a guest posts to `/p/<guest token>/cancellation`
- **THEN** the response is 404 and the event is not cancelled

#### Scenario: Organizer cancels through the token family
- **WHEN** the organizer of a pending event with two linked guests posts to `/p/<organizer token>/cancellation`
- **THEN** the response is 303 to the organizer page with "Event cancelled. 3 people were told." and `cancelled_at` is set

#### Scenario: Organizer cancels through the session family
- **WHEN** a signed-in organizer posts to `/participations/<id>/cancellation` on a finalized event
- **THEN** the response is 303 with the same notice and the event is cancelled with its window intact

#### Scenario: Second cancel is refused
- **WHEN** the organizer posts to the cancellation route of an already cancelled event
- **THEN** the response is 303 with the alert "This event was cancelled" and no new ledger row is created

### Requirement: Every write after cancellation is refused with one message
`Event#ensure_pending!` SHALL raise `Event::ClosedError` "This event was cancelled" when `cancelled?` before the existing "Availability is closed for this event" when `status?`; `Event#ensure_not_cancelled!` SHALL raise the first message only. `replace_time_slots!`, `mark_unavailable!`, `finalize!`, `revise_offer!`, `update_details!` and `reopen!` SHALL therefore refuse a cancelled event with that message before any other check. `ParticipationScopedController` SHALL add `before_action :refuse_closed_writes, unless: -> { request.get? }` which, when `@event.cancelled?`, redirects 303 to `scoped_path` with the alert "This event was cancelled", and SHALL add `rescue_from Event::ClosedError` answering 303 with the exception message. Invitations, resend, link reveal, remove, finalize, details, offer, notice, plan items, reopen and cancel SHALL all be refused this way in both families.

#### Scenario: The cancelled message wins over the finalized message
- **WHEN** `finalize!` is called on a cancelled event that was finalized before being cancelled
- **THEN** it raises `Event::ClosedError` "This event was cancelled", not "Availability is closed for this event"

#### Scenario: Every model writer refuses first
- **WHEN** `replace_time_slots!`, `mark_unavailable!`, `finalize!`, `revise_offer!`, `update_details!` or `reopen!` is called on a cancelled event
- **THEN** each raises `Event::ClosedError` with "This event was cancelled" and writes nothing

#### Scenario: Every organizer write answers 303
- **WHEN** the organizer of a cancelled event posts to invitations, resend, link_reveal, participants#destroy, finalization, details, offer, notice, activities, activity move, reopening or cancellation in either family
- **THEN** each response is 303 to the organizer page with the alert "This event was cancelled" and no row changes

#### Scenario: Guest save and decline answer 303
- **WHEN** a guest of a cancelled event submits `PATCH /p/:token` or `POST /p/:token/decline`
- **THEN** the response is 303 with "This event was cancelled" and the guest's slots and `declined_at` are unchanged

### Requirement: Leave and Claim are the only writes a cancelled event accepts
`refuse_closed_writes` SHALL be skipped for `ParticipationsController#destroy` (Leave) and for `Participations::ClaimsController` (Claim); `Participant#leave!` SHALL NOT call `ensure_pending!`. "Leave this event" SHALL render on pending, finalized and cancelled guest pages, and the cancelled guest page SHALL keep both **Leave this event** and **Keep this event in your account**.

#### Scenario: Leave works on a cancelled event
- **WHEN** a guest of a cancelled event submits `DELETE /p/:token`
- **THEN** the response is 303 to the site root with "You left <event name>." and the guest's `left_at` is set

#### Scenario: Claim works on a cancelled event
- **WHEN** a signed-in user opens their guest link on a cancelled event and posts to `/p/:token/claim`
- **THEN** the participation is claimed and appears on the dashboard

#### Scenario: Leave renders on a finalized guest page
- **WHEN** a guest opens their link on a finalized, not cancelled event
- **THEN** the page renders the "Leave this event" form and no save or decline form

### Requirement: No mail of any kind leaves a cancelled event except the cancelled notice
Every `Deliveries` method except `cancelled!` SHALL raise `Event::ClosedError` "This event was cancelled" when `event.cancelled_at` is set, so no later action can enqueue mail for a cancelled event. The organizer page SHALL NOT show the **Tell the guests** control once the event is cancelled.

#### Scenario: The guard covers every other kind
- **WHEN** `Deliveries.invitation!`, `organizer_link!`, `response_confirmation!`, `finalized!`, `reveal_link!`, `event_updated!` or `reopened!` is called with a cancelled event
- **THEN** each raises `Event::ClosedError` "This event was cancelled" and creates no ledger row

#### Scenario: Cancelled itself passes the guard
- **WHEN** `Deliveries.cancelled!` runs after `cancel!` commits
- **THEN** it creates its rows and jobs without raising

### Requirement: Everyone with a link hears about the cancellation once
`MailDelivery::KINDS` and the `mail_deliveries_kind_allowed` check SHALL gain `cancelled`. `Deliveries.cancelled!(event:)` SHALL run after `cancel!` commits and create exactly one `cancelled` ledger row and one job per `participants.active.linked` (declined guests included, the organizer included as a receipt, left and unsent excluded), issuing no token and never refused by a cap; it SHALL set `notified_revision` to `revision` after the batch. `ParticipantMailer#cancelled` (`cancelled.{html,text}.erb`) SHALL use `subject_for("#{mail_safe(event.name)} is cancelled")`, Reply-To the organizer, and the body "<organizer> cancelled <event>. [It was set for <window in your zone> (<event zone>).] Nothing else will be sent about this event. If you added it to your calendar, the attached file removes it." with no link. When a window existed at cancellation the mail-mode `CalendarFile` with `STATUS:CANCELLED` SHALL be attached, built from window values passed in the mailer params, never read from the row at render time; a cancel with no window (pending, or after a reopen) SHALL carry no attachment.

#### Scenario: One row per active linked participant
- **WHEN** an event with an organizer, two linked guests (one declined), one unsent guest and one left guest is cancelled
- **THEN** exactly three `cancelled` rows and three jobs are created, one of them for the organizer

#### Scenario: Attachment when a window existed
- **WHEN** a finalized event is cancelled
- **THEN** each `cancelled` mail names the window in the recipient's zone and the event zone and carries a `text/calendar` attachment containing `STATUS:CANCELLED` and `SEQUENCE:` equal to the bumped `revision`

#### Scenario: No attachment for a pending cancel
- **WHEN** a pending event, or an event reopened and not finalized again, is cancelled
- **THEN** the `cancelled` mail has no attachment and no "It was set for" sentence

#### Scenario: No link and no cap
- **WHEN** a recipient has reached 10 invitation mails today and an event they are linked to is cancelled
- **THEN** the `cancelled` mail is still enqueued and neither part of its body contains `/p/` or `://`

### Requirement: The cancelled page is read-only and stays readable
`viewer_role` SHALL become `@event.open? ? @participant.role : "viewer"`. The participation page GET and the calendar route SHALL keep working for every valid token in both families; `details/edit` and `offer/edit` answer 303 with "This event was cancelled". The page SHALL render `#time-grid-show[data-role="viewer"][data-cancelled]`, the heading followed by an inline `plate plate-ink` "Cancelled", and no availability, decline, finalize, send, resend, reveal, remove, details, offer, notice, reopen or cancel form or link. The organizer page SHALL additionally show "Cancelled on <date>" as `<time datetime="<iso8601>" data-zoned-instant>` in the event zone with the zone name, "Was set for <window>" when the event had one, the participant table read-only and a plate link **Plan a new event** to `new_event_path`. `GET …/calendar.ics` on a cancelled finalized event SHALL return the file with `STATUS:CANCELLED`, the same `UID` and the bumped `SEQUENCE`; on a cancelled pending event it SHALL return 404. Dashboard cards in `app/views/dashboards/shared/_my_events.html.erb` SHALL show "cancelled" in the state row for a cancelled event.

#### Scenario: Organizer page after cancel
- **WHEN** the organizer opens a cancelled finalized event
- **THEN** the page has `#time-grid-show[data-role="viewer"][data-cancelled]`, the "Cancelled" plate, "Cancelled on" with the event zone name, "Was set for" with the window, the "Plan a new event" link and no form at all

#### Scenario: Guest page after cancel
- **WHEN** a guest opens their link on a cancelled event
- **THEN** the page renders 200 with `data-role="viewer"`, `data-cancelled`, the "Cancelled" plate, the Leave form and the Claim control, and no `#availability-form`, decline form or `#finalize-form`

#### Scenario: Calendar file after cancel
- **WHEN** a participant requests `calendar.ics` on a cancelled finalized event and on a cancelled pending event
- **THEN** the first response is `text/calendar` containing `STATUS:CANCELLED` and the event's stable `UID` with `SEQUENCE` equal to `revision`, and the second is 404

#### Scenario: Dashboard shows cancelled
- **WHEN** a signed-in participant of a cancelled event opens `/dashboard`
- **THEN** that event's card shows "cancelled" in its state row

### Requirement: Organizer-link recovery skips cancelled events
`Event.not_cancelled` SHALL be `where(cancelled_at: nil)`. `OrganizerLinksController#create` SHALL issue pending organizer tokens only for `Event.not_cancelled` (pending or finalized), replacing `Event.where(status: false)`. `MailDelivery::Caps.organizer_has_finalized?` SHALL keep counting cancelled finalized events.

#### Scenario: Nothing for a cancelled event
- **WHEN** the recovery form is submitted with the address of an organizer whose only event is cancelled
- **THEN** no token is issued, no `organizer_link` row is created and the response is the constant notice

#### Scenario: A finalized event still recovers
- **WHEN** the recovery form is submitted with the address of an organizer whose event is finalized and not cancelled
- **THEN** one pending organizer token is issued and one `organizer_link` mail is enqueued

#### Scenario: Cancelled finalized event keeps the allowance
- **WHEN** an organizer's only finalized event has been cancelled
- **THEN** `organizer_has_finalized?` is still true for that address

### Requirement: Reopen withdraws a set time at most twice
`events` SHALL gain `reopened_at datetime NULL` and `reopen_count integer NOT NULL DEFAULT 0` with the check `events_reopen_count_bounded: reopen_count BETWEEN 0 AND 2`. `Event#reopen!` SHALL run inside `with_lock` (the same lock as `finalize!`, so the two serialize), call `ensure_not_cancelled!`, raise `ArgumentError` "Only a set time can be reopened" unless `status?`, raise `ArgumentError` "This event was reopened twice already. Cancel it and plan a new one." when `reopen_count >= 2`, capture `[start_time, end_time]`, `update!(status: false, start_time: nil, end_time: nil, reopened_at: now, reopen_count: reopen_count + 1, revision: revision + 1)` and return the captured window. Every slot, reply, `responded_at`, `declined_at`, `reply_voided_at`, token and claim SHALL be untouched. `finalize!` SHALL bump `revision` so the re-published file outranks the withdrawn one.

#### Scenario: Reopen clears the window
- **WHEN** `reopen!` is called on a finalized event with `revision` 5 and `reopen_count` 0
- **THEN** it returns the previous window, `status` is false, `start_time` and `end_time` are NULL, `reopened_at` is set, `reopen_count` is 1 and `revision` is 6

#### Scenario: Pending event is refused
- **WHEN** `reopen!` is called on a pending event
- **THEN** it raises `ArgumentError` "Only a set time can be reopened"

#### Scenario: Cancelled event is refused
- **WHEN** `reopen!` is called on a cancelled finalized event
- **THEN** it raises `Event::ClosedError` "This event was cancelled"

#### Scenario: Third reopen is refused
- **WHEN** `reopen!` is called on a finalized event with `reopen_count` 2
- **THEN** it raises `ArgumentError` "This event was reopened twice already. Cancel it and plan a new one." and the window stays

#### Scenario: Replies survive
- **WHEN** an event with a voided guest, a declined guest and a counting guest holding two slots is reopened
- **THEN** every `time_slots` row, `responded_at`, `declined_at`, `reply_voided_at`, token digest and `user_id` is unchanged and consensus recomputes from those rows

#### Scenario: Finalize after reopen bumps the revision
- **WHEN** an event reopened at `revision` 6 is finalized again
- **THEN** `status` is true, the new window is set and `revision` is 7

### Requirement: Reopen is organizer-only through both families
`POST /p/:token/reopening` and `POST /participations/:participation_id/reopening` SHALL route to `Participations::ReopeningsController#create`, gated by `require_organizer!` (404 for a guest token). A finalized, not cancelled organizer page SHALL render `button_to "Reopen the time"` (`btn btn-outline-secondary`) with `turbo_confirm` "Withdraw <window>? Everyone with a link is told once and can paint again." The action SHALL call `Event#reopen!`, then `Deliveries.reopened!(event:, previous_window:)` after commit, and redirect 303 with "The set time was withdrawn. N guests were told."; a pending event SHALL answer 303 "Only a set time can be reopened" and a third attempt 303 "This event was reopened twice already. Cancel it and plan a new one." Afterwards the organizer page SHALL be the normal planning page (consensus grid, **Change the times**, **Set in stone**) with a hairline note "Reopened once" or "Reopened twice — the last time". When no offered instant is at or after `TimeSlotParser::PAST_GRACE.ago`, the reopen flash SHALL append "Every offered time has passed. Change the times.", the organizer action bar SHALL read the same sentence with the **Change the times** plate button, and the guest page SHALL show "All the offered times have passed." with Save hidden.

#### Scenario: Guest token is not found
- **WHEN** a guest posts to `/p/<guest token>/reopening` on a finalized event
- **THEN** the response is 404 and the window is unchanged

#### Scenario: Organizer reopens in either family
- **WHEN** the organizer of a finalized event with two linked guests posts to the reopening route through `/p/:token` or `/participations/:participation_id`
- **THEN** the response is 303 with "The set time was withdrawn. 2 guests were told." and the event is pending

#### Scenario: Grid returns to organizer mode
- **WHEN** the organizer opens the page after a first reopen
- **THEN** `#time-grid-show[data-role="organizer"]` has no `data-finalized`, `#consensus-time-slots` and `#finalize-form` are present, the **Change the times** link is present and the page reads "Reopened once"

#### Scenario: Pending and third attempts are refused
- **WHEN** the organizer posts to the reopening route on a pending event, and on an event with `reopen_count` 2
- **THEN** the responses are 303 with "Only a set time can be reopened" and "This event was reopened twice already. Cancel it and plan a new one." respectively

#### Scenario: Every offered time has passed
- **WHEN** the organizer reopens an event whose every offered instant is before `PAST_GRACE.ago`
- **THEN** the flash ends with "Every offered time has passed. Change the times.", the organizer action bar shows that sentence with the plate button, and a guest page shows "All the offered times have passed." with no Save control

### Requirement: Every linked guest hears about the reopening once
`MailDelivery::KINDS` and the kind check SHALL gain `reopened`. `Deliveries.reopened!(event:, previous_window:)` SHALL run after commit and create one `reopened` ledger row and one job per active linked guest (no organizer copy), never refused by a cap, passing `previous_window:` (two `Time` values, serialized by the job) in the mailer params; for an unclaimed guest it SHALL issue a fresh pending token that retires the previous pending one, and for a claimed guest it SHALL pass no token so the mailer links `my_participation_url`. It SHALL set `notified_revision` to `revision` after the batch. `ParticipantMailer#reopened` (`reopened.{html,text}.erb`) SHALL use `subject_for("#{mail_safe(event.name)} is no longer set for #{date}")` with the date in the recipient zone and the event-zone fallback, Reply-To the organizer, and a body naming the withdrawn window in both zones, "Your painted times still count. Open your link to change them. You will get one message when a new time is set.", the link, and the standing sentence "To stop hearing about this event, open your link and choose Leave this event." The mail-mode `CalendarFile` for the withdrawn window with `STATUS:CANCELLED` and `SEQUENCE` equal to the new `revision` SHALL be attached, built from the params, never from the live row.

#### Scenario: Guests only, one job each
- **WHEN** an event with an organizer, two linked guests and one unsent guest is reopened
- **THEN** exactly two `reopened` rows and jobs are created and the organizer receives none

#### Scenario: Window in both zones with the cancelled file
- **WHEN** the `reopened` mail renders for an Asia/Kolkata guest of a Europe/Berlin event withdrawn from 2030-01-15 10:00 Berlin
- **THEN** both parts name the window in Asia/Kolkata and in Europe/Berlin, the subject is "Catching App: <event> is no longer set for <date in Asia/Kolkata>", and the attachment contains `STATUS:CANCELLED`, `DTSTART:20300115T090000Z` and `SEQUENCE:` equal to `revision`

#### Scenario: Link rule for unclaimed and claimed guests
- **WHEN** the `reopened` mails render for one unclaimed and one claimed guest
- **THEN** the unclaimed guest's body carries `/p/<new pending token>` and the previous pending link answers 404 after the batch, while the claimed guest's body carries `/participations/<id>` and no token was issued

#### Scenario: Never capped
- **WHEN** a guest has reached every daily cap and their event is reopened
- **THEN** the `reopened` mail is enqueued

### Requirement: After a reopen the event is an ordinary pending event
After `reopen!` the guest page SHALL return to the paintable grid with paint intact and show the inline note "The set time was withdrawn on <date>. Check your picks and save." while `responded_at < reopened_at`, the date rendered as `<time datetime="<iso8601>" data-zoned-instant>` in the event zone with the zone name and rewritten into the picker zone by `time_slot_show.js`. The organizer MAY revise the offer, wait for replies and `finalize!` again; `finalize!` SHALL re-send `finalized` (never capped, up to three times per event) with a `STATUS:CONFIRMED` file at the next `SEQUENCE`. `GET …/calendar.ics` SHALL answer 404 while the event is pending. `GET` and `PATCH …/offer` on a finalized event SHALL answer 303 "Reopen the time before changing the offer" (controller text; the model keeps `Event::ClosedError`).

#### Scenario: Guest sees the withdrawal note
- **WHEN** a guest who replied before the reopen opens their link
- **THEN** their painted cells are pre-painted, `#availability-form` is present and the action bar shows "The set time was withdrawn on <date>. Check your picks and save." with a `[data-zoned-instant]` date

#### Scenario: Saving clears the note
- **WHEN** that guest saves availability after the reopen
- **THEN** `responded_at` is later than `reopened_at` and the note is no longer rendered

#### Scenario: Calendar route is gone while pending
- **WHEN** a participant requests `calendar.ics` after a reopen and before the next finalize
- **THEN** the response is 404

#### Scenario: The offer page points at reopen
- **WHEN** the organizer opens or submits `…/offer` on a finalized event
- **THEN** the response is 303 with "Reopen the time before changing the offer"

#### Scenario: Round trip with at most three finalized batches
- **WHEN** an event is finalized, reopened, its offer revised, finalized, reopened and finalized again
- **THEN** exactly three `finalized` batches were sent, the last file carries `STATUS:CONFIRMED` with the highest `SEQUENCE`, `reopen_count` is 2 and a further reopen is refused
