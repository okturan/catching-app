## ADDED Requirements

### Requirement: `event_updated` is a ledger kind
`MailDelivery::KINDS` and the database check `mail_deliveries_kind_allowed` SHALL include `event_updated` (migration `20260906000003_extend_mail_delivery_kinds.rb` drops the check and re-adds it with `('organizer_link','invitation','response_confirmation','finalized','link_shown','event_updated','cancelled','reopened')`; its `down` re-adds the five-kind check and fails when rows of the new kinds exist, so the round-trip test truncates first). Every `event_updated` mail SHALL be exactly one `mail_deliveries` row created before enqueue through `Deliveries.record!(kind: :event_updated, sender_email: MailDelivery.canonical(organizer.email), request_ip:)`, so the row carries `sender_email`, `request_ip`, `recipient_email` and `canonical_recipient_email` and is counted by the caps below. A recipient refused by a cap SHALL be skipped without raising, without a ledger row and without any change to the event.

#### Scenario: One row per recipient, written before the job
- **WHEN** `Deliveries.event_updated!` reaches two guests
- **THEN** two `mail_deliveries` rows with `kind = "event_updated"` and `sender_email` equal to the organizer's canonical address exist, and two `ParticipantMailer#event_updated` jobs are enqueued after them

#### Scenario: A refused recipient leaves nothing behind
- **WHEN** `MailDelivery::Caps.check_update_notice!` raises `MailDelivery::CapExceeded` for one of three recipients
- **THEN** `Deliveries.event_updated!` does not raise, two rows are created, no row exists for the refused address, and the event's columns are unchanged by that recipient

### Requirement: Notices are sent only when the organizer asks
An `event_updated` mail SHALL never be sent implicitly. Exactly three triggers exist, each calling `Deliveries.event_updated!(event:, organizer:, request_ip:, reason:, changes: nil)` after the write commits:
1. The **Edit details** form (`PATCH …/details`) with checkbox `notice[send]` "Email the guests about this change", rendered only when `@participant.link_opened_at` is present and at least one active linked guest exists, unchecked while the event is pending and checked once finalized; when `notice[send]` is "1" and `Event#update_details!` returned a non-empty change set, the controller calls with `reason: :details, changes:` (a plain hash of attribute → `[old, new]`).
2. The **Change the times** form (`PATCH …/offer`) with checkbox `notice[send]` "Email the guests who already replied" (default checked); when ticked and `Event#revise_offer!` produced an instant delta (not the no-op and not the step-or-zone-only outcome), the controller calls with `reason: :offer`.
3. The **Tell the guests** plate button, `POST …/notice` (`participation_notice_path`, `my_participation_notice_path`), handled by `Participations::NoticesController#create` behind `require_opened_organizer!` (a guest token is 404), with the button's reason (`:all`).
Plan writes (`POST …/activities`, `PATCH`/`DELETE …/activities/:id`, `POST …/activities/:id/move`) SHALL send no mail; a details save whose change set is empty SHALL send nothing. Mailer params SHALL carry `reason:` alongside `changes:`.

#### Scenario: A plan edit alone sends nothing
- **WHEN** the organizer adds an item to the plan
- **THEN** no `event_updated` row is created and `events.revision` is greater than `events.notified_revision`

#### Scenario: Details saved with the box unticked
- **WHEN** the organizer changes `place` through `PATCH …/details` without `notice[send]`
- **THEN** the details are saved, the flash is "Details saved." and no `event_updated` row is created

#### Scenario: Details saved with the box ticked
- **WHEN** the organizer changes `place` with `notice[send]=1` and two active linked guests exist
- **THEN** after commit `Deliveries.event_updated!` runs with `reason: :details` and `changes` containing `"place"`, and two rows are created

#### Scenario: Guest token cannot tell the guests
- **WHEN** `POST /p/<guest token>/notice` is requested
- **THEN** the response is the uniform 404 not-found page and no row is created

#### Scenario: Both families reach the button
- **WHEN** a signed-in organizer requests `POST /participations/<id>/notice` on an event whose `revision` exceeds `notified_revision`
- **THEN** the same notice is sent as through `POST /p/<organizer token>/notice`

### Requirement: Notices require an opened organizer link
`Deliveries.event_updated!` SHALL raise `ArgumentError, "Open your organizer link before emailing guests"` unless `organizer.link_opened_at` is present. The details and offer forms SHALL render the `notice[send]` checkbox only when `@participant.link_opened_at` is present; `Participations::NoticesController` SHALL gate `create` with `require_opened_organizer!`; a controller that receives `notice[send]` for an unopened organizer SHALL rescue the `ArgumentError` and answer 303 to `scoped_path` with the same opened-link hint that `require_opened_organizer!` issues, without sending anything.

#### Scenario: Deliveries refuses an unopened organizer
- **WHEN** `Deliveries.event_updated!` is called for an organizer whose `link_opened_at` is nil
- **THEN** it raises `ArgumentError` with "Open your organizer link before emailing guests" and no row is created

#### Scenario: Tell the guests before opening the link
- **WHEN** an organizer whose `link_opened_at` is nil requests `POST …/notice`
- **THEN** the response is 303 to the participation page with the opened-link hint and no row is created

#### Scenario: Checkbox hidden until the link was opened
- **WHEN** an organizer whose `link_opened_at` is nil opens `GET …/details/edit`
- **THEN** no `notice[send]` input is rendered

### Requirement: Recipients are chosen per reason
The recipient set SHALL start from `event.guests.active.linked`. For `reason: :offer` it SHALL be restricted to `where.not(responded_at: nil)` (trimmed, voided, untouched-but-added and declined guests) and SHALL exclude declined guests when the revision's `added` count is 0; unreplied guests SHALL receive nothing about an offer change, and a revision before any reply SHALL send nothing. For `reason: :details` and the **Tell the guests** button every active linked guest, replied or not, SHALL be a recipient. The organizer SHALL never receive an `event_updated` mail; a guest without a live token (`token_digest` NULL) or one who left SHALL never receive one; on a cancelled event `Deliveries.event_updated!` SHALL raise `Event::ClosedError, "This event was cancelled"` (the `Deliveries`-wide guard) and send nothing.

#### Scenario: Offer notices skip guests who never replied
- **WHEN** a revision with removals is saved with the box ticked while one linked guest has `responded_at` and another has none
- **THEN** exactly one `event_updated` row is created, for the replied guest

#### Scenario: Details notices include guests who never replied
- **WHEN** `Deliveries.event_updated!(reason: :details)` runs with one replied and one unreplied linked guest
- **THEN** two rows are created

#### Scenario: Removal-only revision skips declined guests
- **WHEN** a revision removes two instants and adds none, and one active linked guest has `declined_at` set
- **THEN** that guest receives no `event_updated` mail while trimmed and voided guests do

#### Scenario: Additions reach declined guests
- **WHEN** a revision adds one instant and one active linked guest has `declined_at` set
- **THEN** that guest receives an `event_updated` mail

#### Scenario: Revision before the first reply is silent
- **WHEN** the organizer revises the offer with the box ticked while no guest has `responded_at`
- **THEN** no `event_updated` row is created

#### Scenario: Cancelled event
- **WHEN** `Deliveries.event_updated!` is called on an event whose `cancelled_at` is set
- **THEN** it raises `Event::ClosedError` with "This event was cancelled" and creates no row

### Requirement: Notices are capped per event and address and share the invitation's daily keys
`MailDelivery::Caps` SHALL define `UPDATE_NOTICES_PER_EVENT_ADDRESS = 5` and `UPDATE_NOTICE_COOLDOWN = 10.minutes` and `check_update_notice!(event:, organizer:, recipient_email:, request_ip:)`, which SHALL apply, in order: the four daily keys shared with invitations — the global `INVITATION_DAILY_BUDGET`, the organizer allowance (100, or 20 while the organizer has no finalized event), 200 per request IP and 10 per canonical recipient address — counted over `MailDelivery.where(kind: %w[invitation event_updated])` in the last 24 hours; then, on `event_updated` rows for the (event, canonical address) pair excluding rows with `failed_at`, a lifetime maximum of 5 and a 10-minute cooldown since the newest row. `check_invitation!` SHALL count its four daily keys over the same two-kind relation while its per-(event, address) maximum of 5 and its 10-minute cooldown stay `invitation`-only. Refusals SHALL raise `MailDelivery::CapExceeded`; `Deliveries.event_updated!` SHALL rescue it per recipient, skip that recipient and count the skip. `finalized`, `cancelled` and `reopened` mails MUST never be refused by any cap.

#### Scenario: Sixth notice per event and address is refused
- **WHEN** five non-failed `event_updated` rows exist for one event and one canonical address and a sixth is attempted
- **THEN** `check_update_notice!` raises `MailDelivery::CapExceeded`

#### Scenario: Second notice within ten minutes is refused
- **WHEN** an `event_updated` row for the pair was created 9 minutes ago
- **THEN** `check_update_notice!` raises `MailDelivery::CapExceeded`, and passes once the row is older than 10 minutes

#### Scenario: Failed rows do not count
- **WHEN** five `event_updated` rows exist for the pair and one of them has `failed_at` set
- **THEN** `check_update_notice!` passes

#### Scenario: Notices consume the shared recipient key
- **WHEN** a canonical recipient address has 7 `invitation` rows and 3 `event_updated` rows in the last 24 hours
- **THEN** both `check_invitation!` and `check_update_notice!` refuse the next mail to that address

#### Scenario: The invitation's per-event count ignores notices
- **WHEN** an address has 3 `event_updated` rows and 4 `invitation` rows for one event
- **THEN** `check_invitation!` still allows a fifth invitation for that pair

#### Scenario: Other kinds are never capped
- **WHEN** a recipient has exhausted the daily key and the per-event notice count
- **THEN** `finalized`, `cancelled` and `reopened` mails to that recipient are still enqueued

### Requirement: Notice links follow the claim rule and newer links replace older ones
For a claimed guest (`guest.claimed?`) `Deliveries.event_updated!` SHALL issue no token and the mailer SHALL link `my_participation_url(participant)`; for an unclaimed guest it SHALL call `guest.issue_pending_token!`, which issues a fresh pending token and retires the previous pending one while the live token from the invitation keeps working; the raw token SHALL be passed to `enqueue(delivery, raw_token)` and rendered in both parts. A `GET` with the pending token SHALL change no digest. A pending link from an earlier mail SHALL answer the not-found page, whose guest copy reads "This link is not valid. Open the newest email about this event: a newer link replaces older ones, or ask the organizer to resend your invitation."

#### Scenario: Claimed guest gets a signed-in link
- **WHEN** a notice reaches a guest whose participation is claimed
- **THEN** no pending token is issued and both mail parts contain a `/participations/<id>` link and no `/p/` link

#### Scenario: Unclaimed guest gets a pending token that reads without writing
- **WHEN** a notice reaches an unclaimed guest and the guest requests `GET /p/<pending token>`
- **THEN** the participation page renders and `token_digest` and `pending_token_digest` are unchanged afterwards

#### Scenario: The previous pending link stops working
- **WHEN** a guest holds an unused pending token from an earlier mail and a notice is sent
- **THEN** the earlier pending link answers 404 with the newest-email copy while the invitation's live link still opens the page

### Requirement: The notice subject and headers resist phishing
`ParticipantMailer#event_updated` SHALL render `participant_mailer/event_updated.{html,text}.erb` with subject `subject_for("#{mail_safe(organizer.name)} changed #{mail_safe(event.name)}")` — "Catching App: <organizer> changed <event>", fixed prefix first, truncated to 80 characters — and Reply-To the organizer's bare validated address. Place, event name, organizer name and plan names SHALL pass through `mail_safe`; `place_url` and every description SHALL be excluded by construction; the only `://` in either part SHALL belong to the participation link.

#### Scenario: Subject shape and truncation
- **WHEN** an organizer named "Ege" changes an event with a 120-character name
- **THEN** the subject starts with "Catching App: Ege changed " and is at most 80 characters

#### Scenario: Reply-To the organizer
- **WHEN** a notice is rendered
- **THEN** `mail.reply_to` equals `[organizer.email]`

#### Scenario: No organizer URL reaches the notice
- **WHEN** the event has `place_url` "https://zoom.us/j/1", a description containing "https://evil.example" and a plan item described with a URL
- **THEN** in both parts the count of "://" equals the count of participation-link occurrences and neither `zoom.us` nor `evil.example` appears

### Requirement: The notice body describes the current facts and the recipient's offer situation
Both parts SHALL contain, in order: one reason line; when `changes` contains `name`, "The event is now called <new> (was <old>)"; a facts block with the current place (`mail_safe`), planned length and plan (names and lengths, never descriptions); for offer changes the per-recipient situation derived from state at send time — a voided guest (`reply_voided_at` set) reads "None of the times you picked are offered any more. Please pick again.", a counting guest with `responded_at < offer_revised_at` reads "Some of the offered times changed (N added, M removed). Your remaining picks still stand; look again." with `N`/`M` from `offer_revision_added`/`offer_revision_removed`, and a declined guest reads "You said none of the times worked. New times were added."; then the link; then the standing sentence "To stop hearing about this event, open your link and choose Leave this event." `ParticipantMailerPreview` SHALL include one `event_updated` sample per reason.

#### Scenario: Renamed event shows old and new
- **WHEN** a notice is rendered with `changes: { "name" => ["Film night", "Dune night"] }`
- **THEN** both parts contain "The event is now called Dune night (was Film night)"

#### Scenario: Voided guest
- **WHEN** an offer notice is rendered for a guest whose `reply_voided_at` is set
- **THEN** both parts contain "None of the times you picked are offered any more. Please pick again."

#### Scenario: Stale counting guest
- **WHEN** an offer notice is rendered for a counting guest whose `responded_at` precedes `offer_revised_at` after a revision that added 4 and removed 2
- **THEN** both parts contain "Some of the offered times changed (4 added, 2 removed). Your remaining picks still stand; look again."

#### Scenario: Declined guest
- **WHEN** an offer notice is rendered for a guest with `declined_at` set after a revision that added instants
- **THEN** both parts contain "You said none of the times worked. New times were added."

#### Scenario: The standing sentence closes every notice
- **WHEN** any `event_updated` mail is rendered
- **THEN** both parts end with "To stop hearing about this event, open your link and choose Leave this event."

#### Scenario: Previews cover every reason
- **WHEN** the preview test iterates `ActionMailer::Preview.all`
- **THEN** an `event_updated` sample renders for each reason without error

### Requirement: `notified_revision` drives the "Tell the guests" reminder
`events.notified_revision integer NOT NULL DEFAULT 0` with check `events_revisions_ordered: notified_revision >= 0 AND notified_revision <= revision` SHALL record the last `revision` any mail batch reached guests with; `Deliveries.event_updated!` SHALL set it with `event.update_columns(notified_revision: event.revision)` only when `sent > 0` (the `invitation`, `finalized`, `reopened` and `cancelled` batches set it too, so the reminder may under-report for guests invited before a change — accepted). The organizer page SHALL show "Guests have not been told about your latest changes" with a **Tell the guests** plate button when `revision > notified_revision`, at least one active linked guest exists and the event is not cancelled, and SHALL omit both otherwise. `POST …/notice` when `revision == notified_revision` SHALL answer 303 with "Guests already know about every change." and send nothing.

#### Scenario: Set only when something was sent
- **WHEN** every recipient of a notice is refused by a cap
- **THEN** `notified_revision` is unchanged, and after a later notice that reaches one guest it equals `revision`

#### Scenario: Reminder after an untold change
- **WHEN** the organizer edits the plan without sending a notice and one active linked guest exists
- **THEN** the organizer page shows "Guests have not been told about your latest changes" and the **Tell the guests** button

#### Scenario: No button when nothing changed
- **WHEN** `revision` equals `notified_revision`
- **THEN** the organizer page shows neither the sentence nor the button

#### Scenario: Nothing to tell
- **WHEN** `POST …/notice` is requested while `revision` equals `notified_revision`
- **THEN** the response is 303 with "Guests already know about every change." and no row is created

#### Scenario: No reminder on a cancelled event
- **WHEN** the event is cancelled after an untold change
- **THEN** the organizer page shows no **Tell the guests** button

### Requirement: The organizer hears how many guests were reached
`Deliveries.event_updated!` SHALL return `{ sent:, skipped: }`. Every trigger's flash SHALL report "N guests emailed." and, when `M > 0`, "M skipped (recently notified). Try again after 10 minutes."; the details flash prefixes "Details saved." The participant table SHALL keep showing the ledger state per guest as today.

#### Scenario: Two emailed, one skipped
- **WHEN** a notice reaches two guests and a third is refused by the cooldown
- **THEN** the flash contains "2 guests emailed." and "1 skipped (recently notified). Try again after 10 minutes."

#### Scenario: Nobody skipped
- **WHEN** a notice reaches every recipient
- **THEN** the flash contains "N guests emailed." and no "skipped" sentence

### Requirement: The invitation and confirmation promise the new mails honestly
The invitation (`invitation.{html,text}.erb`) SHALL promise exactly: "You will get at most: up to 5 resends, one confirmation when you reply, up to 5 notes if the organizer changes the plan, one message each time the time is set or reopened, and one if it is cancelled." The response confirmation's last sentence (`response_confirmation.{html,text}.erb`) SHALL be exactly: "To change your reply, use the link from your invitation. You will hear from us when the time is set, and if the organizer changes the plan."

#### Scenario: Promise in both invitation parts
- **WHEN** an invitation is rendered
- **THEN** both parts contain "You will get at most: up to 5 resends, one confirmation when you reply, up to 5 notes if the organizer changes the plan, one message each time the time is set or reopened, and one if it is cancelled."

#### Scenario: Confirmation closing sentence
- **WHEN** a response confirmation is rendered
- **THEN** both parts end with "To change your reply, use the link from your invitation. You will hear from us when the time is set, and if the organizer changes the plan."
