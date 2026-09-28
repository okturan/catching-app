## MODIFIED Requirements

### Requirement: Four templates with defined triggers and recipients
`ParticipantMailer` SHALL provide seven templates, each in HTML and text, with exactly these triggers and recipients:

- `organizer_link` — to the organizer; after `Event.plan!` commits and from the recovery form (whose scope is now `Event.not_cancelled`, so the unchanged body also reaches organizers of finalized events); subject "Catching App: your organizer link"; constant content with no organizer-supplied text.
- `invitation` — to a guest; on send and resend; subject "Catching App: <organizer name> invited you to <event>".
- `response_confirmation` — to a guest; first reply only, including decline (a re-reply after an offer revision or a reopen sends no second confirmation, because `responded_at` is never reset); subject "Catching App: your reply to <event> is saved"; contiguous instants coalesced into per-day ranges in the guest's zone and the event zone, capped with "and N more days"; its last sentence SHALL be exactly "To change your reply, use the link from your invitation. You will hear from us when the time is set, and if the organizer changes the plan."
- `finalized` — after `finalize!` commits, `Deliveries.finalized!(event:)` enqueues one job per participant in `participants.active.linked` and passes `window: [start_time, end_time]` in the mailer params; `ParticipantMailer#finalized` and its attachment SHALL build from those params, never from the event row, so a job performed after `reopen!` still renders. Subject unchanged: "Catching App: <event> is set for <date in recipient zone>". The body SHALL add "Where: <mail_safe(place)>" and "How long: <duration>" when set, the plan with derived starts in the recipient zone and the event zone when every preceding item has a duration, and the closing sentence exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels."; it SHALL attach `catching-app.ics` (`mime_type: "text/calendar; method=PUBLISH"`, mail mode, `STATUS:CONFIRMED`, `SEQUENCE` equal to `events.revision`). `finalized` MAY be sent up to three times per event (the initial finalization plus one after each of at most two reopenings).
- `event_updated` — to guests only and never implicitly: `Deliveries.event_updated!(event:, organizer:, request_ip:, reason:, changes:)` runs only when the organizer asks (the `notice[send]` checkbox on the details form, the checkbox on the offer form, or the **Tell the guests** button) and SHALL raise `ArgumentError, "Open your organizer link before emailing guests"` unless `organizer.link_opened_at` is present. Recipients are `event.guests.active.linked`, restricted to `where.not(responded_at: nil)` for `reason: :offer` (declined guests excluded when the revision added nothing). Subject `subject_for("#{mail_safe(organizer.name)} changed #{mail_safe(event.name)}")` — "Catching App: <organizer> changed <event>"; Reply-To the organizer's bare validated address; mailer params carry `reason:` (`:details`, `:offer`, `:all`) and `changes:` (a plain hash of attribute → `[old, new]`, or nil).
- `cancelled` — after `cancel!` commits, `Deliveries.cancelled!(event:)` enqueues one job per participant in `participants.active.linked` (declined guests included, the organizer included as a receipt, left and unsent excluded). Subject `subject_for("#{mail_safe(event.name)} is cancelled")`; Reply-To the organizer; body "<organizer> cancelled <event>. [It was set for <window in your zone> (<event zone>).] Nothing else will be sent about this event. If you added it to your calendar, the attached file removes it."; when a window existed at cancellation the mail-mode `CalendarFile` with `STATUS:CANCELLED` SHALL be attached, built from window values passed in the mailer params; a cancel with no window (pending, or after a reopen) SHALL carry no attachment and no "It was set for" sentence.
- `reopened` — after `reopen!` commits, `Deliveries.reopened!(event:, previous_window:)` enqueues one job per active linked guest (no organizer copy); mailer params carry `previous_window:` (two `Time` values, serialized by the job). Subject `subject_for("#{mail_safe(event.name)} is no longer set for #{date}")` with the date in the recipient zone; Reply-To the organizer; the body SHALL name the withdrawn window in the recipient zone and the event zone and read "Your painted times still count. Open your link to change them. You will get one message when a new time is set."; the mail-mode `CalendarFile` for the withdrawn window with `STATUS:CANCELLED` and `SEQUENCE` equal to the new `revision` SHALL be attached.

Every `Deliveries` method except `cancelled!` SHALL raise `Event::ClosedError, "This event was cancelled"` when `event.cancelled_at` is set, so no mail of any other kind is ever enqueued for a cancelled event. `events.notified_revision` SHALL be set to `revision` after every batch that reaches guests (`invitation`, `finalized`, `reopened`, `cancelled`, and `event_updated` when at least one recipient was sent).

Every mail SHALL state why the recipient got it and how to stop, and SHALL fall back to the event zone when the participant has no valid zone (the `reopened` subject date follows the same fallback as `finalized`). The `finalized`, `event_updated` and `reopened` bodies SHALL end with the standing sentence "To stop hearing about this event, open your link and choose Leave this event."

**Links.** Every mail that asks the recipient to act SHALL carry a link; an organizer's copy never does. `organizer_link` and `invitation` carry the token they issue, as before. `finalized` (guest copies), `event_updated` and `reopened` SHALL link by the claim rule: for an unclaimed guest `Deliveries` calls `guest.issue_pending_token!` — a fresh, never-expiring pending token that retires the previous pending one while the live token from the invitation keeps working — and passes the raw token, so both parts carry `/p/<pending token>` and a `GET` with it changes no digest; for a claimed guest (`guest.claimed?`) no token is issued and the mailer links `my_participation_url(participant)`; the organizer's `finalized` copy carries no link and says "Open your organizer link". `response_confirmation` SHALL point the recipient to the link from their invitation, and `cancelled` SHALL carry no link at all. No token-carrying mail SHALL be addressed to a guest without a live token.

**Organizer text.** The event name, the organizer name, `place` and every plan item name SHALL pass through `MailTextHelper#mail_safe` wherever they appear in a subject, a body or a mail-mode attachment; the event description and plan item descriptions SHALL never reach any mail; `place_url` SHALL never appear in any mail body, subject or attachment; in either part of any mail the only `://` SHALL belong to the participation link.

#### Scenario: Organizer link carries no organizer text
- **WHEN** an event named "Buy crypto now http://evil.example" is planned
- **THEN** the `organizer_link` body and subject contain neither the event name nor any URL other than the participation link

#### Scenario: Confirmation coalesces ranges
- **WHEN** a guest saves 09:00, 09:30, 10:00 and 14:00 on one day at 30 minutes
- **THEN** the confirmation lists "09:00–10:30" and "14:00–14:30" for that day in both zones

#### Scenario: Confirmation closing sentence
- **WHEN** a response confirmation is rendered
- **THEN** both parts end with "To change your reply, use the link from your invitation. You will hear from us when the time is set, and if the organizer changes the plan." and contain no `/p/` link

#### Scenario: Finalized links follow the claim rule
- **WHEN** an event is finalized with one unclaimed guest holding an unused pending token from a Resend and one claimed guest
- **THEN** the unclaimed guest's `finalized` body carries `/p/<new pending token>` in both parts, a `GET` with that token changes no digest, the earlier pending link answers 404 while the invitation's live link still opens the page, and the claimed guest's body carries `/participations/<id>` with no token issued

#### Scenario: Organizer copy of the finalized mail carries no link
- **WHEN** the organizer receives the `finalized` mail
- **THEN** neither part contains a `/p/` or `/participations/` URL and the body says "Open your organizer link"

#### Scenario: Finalized carries the facts, the closing sentence and the file
- **WHEN** an event with `place` "Ege's place", `place_url` "https://zoom.us/j/1" and `duration_minutes` 90 is finalized and a guest receives the mail
- **THEN** both parts contain "Where: Ege's place" and "How long: 1 h 30 min", `zoom.us` appears in neither subject, body nor attachment, the closing sentence is exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels.", and the attachment `catching-app.ics` decodes to a calendar file with `STATUS:CONFIRMED` and `SEQUENCE:` equal to `events.revision`

#### Scenario: Finalized renders from params after a reopen
- **WHEN** a queued `finalized` job is performed after `reopen!` has set `status` false and cleared `start_time` and `end_time`
- **THEN** the mail and its attachment render the window passed as `window:` in the params and the job does not raise

#### Scenario: Notice subject, Reply-To and link
- **WHEN** an organizer named "Ege" with `link_opened_at` set sends a notice about "Film night" to an unclaimed guest
- **THEN** the subject is "Catching App: Ege changed Film night", `mail.reply_to` equals `[organizer.email]`, and both parts carry `/p/<pending token>`

#### Scenario: Notices never reach the organizer or a cancelled event
- **WHEN** `Deliveries.event_updated!` runs for an event with an organizer and two linked guests, and is later called on an event whose `cancelled_at` is set
- **THEN** the first call creates rows only for the two guests, and the second raises `Event::ClosedError` "This event was cancelled" and creates no row

#### Scenario: Notice refused without an opened organizer link
- **WHEN** `Deliveries.event_updated!` is called for an organizer whose `link_opened_at` is nil
- **THEN** it raises `ArgumentError` "Open your organizer link before emailing guests" and no row is created

#### Scenario: Cancelled reaches everyone with a link once, without a link
- **WHEN** an event with an organizer, two linked guests (one declined), one unsent guest and one left guest is cancelled
- **THEN** exactly three `cancelled` jobs are enqueued — one of them to the organizer — the subject is "Catching App: <event> is cancelled", `mail.reply_to` equals `[organizer.email]`, and neither part of any of them contains `/p/`, `/participations/` or `://`

#### Scenario: Cancelled attaches the file only when a window existed
- **WHEN** a finalized event is cancelled, and separately a pending event is cancelled
- **THEN** the first mail names the window in the recipient zone and the event zone and carries a `text/calendar` attachment containing `STATUS:CANCELLED` and `SEQUENCE:` equal to the bumped `revision`, while the second has no attachment and no "It was set for" sentence

#### Scenario: Reopened names the window in both zones with the cancelled file
- **WHEN** the `reopened` mail renders for an Asia/Kolkata guest of a Europe/Berlin event withdrawn from 2030-01-15 10:00 Berlin
- **THEN** the subject is "Catching App: <event> is no longer set for <date in Asia/Kolkata>", both parts name the window in Asia/Kolkata and in Europe/Berlin and contain "Your painted times still count. Open your link to change them. You will get one message when a new time is set.", and the attachment contains `STATUS:CANCELLED`, `DTSTART:20300115T090000Z` and `SEQUENCE:` equal to `revision`

#### Scenario: Reopened goes to guests only and links by the claim rule
- **WHEN** an event with an organizer, one unclaimed guest, one claimed guest and one unsent guest is reopened
- **THEN** exactly two `reopened` jobs are enqueued, the organizer receives none, the unclaimed guest's body carries `/p/<new pending token>` and the claimed guest's body carries `/participations/<id>`

#### Scenario: The standing sentence closes every actionable mail
- **WHEN** a `finalized` guest copy, an `event_updated` mail and a `reopened` mail are rendered
- **THEN** both parts of each end with "To stop hearing about this event, open your link and choose Leave this event."

#### Scenario: No organizer URL reaches any mail
- **WHEN** an event has `place_url` "https://zoom.us/j/1", a description containing "https://evil.example" and a plan item whose description contains a URL, and every template is rendered for it
- **THEN** in both parts of every mail the count of "://" equals the count of participation-link occurrences, and neither `zoom.us` nor `evil.example` appears in any subject, body or attachment

#### Scenario: Zone fallback for the reopened subject
- **WHEN** the `reopened` mail renders for a guest whose `time_zone` is blank on a Europe/Berlin event
- **THEN** the subject date and the window are rendered in Europe/Berlin

### Requirement: Invitation content resists phishing
The invitation SHALL exclude the event description, link to the participation page instead, name the organizer as "Invitation from <name> (<email>)" with the fixed prefix first, never place organizer-supplied text as the first token of the subject, contain no `://` originating from organizer input, prefix subjects with "Catching App:" and truncate them to 80 characters, set Reply-To to the organizer's bare validated address, and promise exactly: "You will get at most: up to 5 resends, one confirmation when you reply, up to 5 notes if the organizer changes the plan, one message each time the time is set or reopened, and one if it is cancelled."

#### Scenario: Description never reaches the mail
- **WHEN** an event description contains `https://evil.example`
- **THEN** the invitation body in both parts contains no `://` except the participation link

#### Scenario: Header injection is neutralized
- **WHEN** an event is named with `"\r\nBcc: victim@example.com"` inside
- **THEN** the subject contains no line breaks and no Bcc header is set

#### Scenario: Promise in both invitation parts
- **WHEN** an invitation is rendered
- **THEN** both parts contain "You will get at most: up to 5 resends, one confirmation when you reply, up to 5 notes if the organizer changes the plan, one message each time the time is set or reopened, and one if it is cancelled." and neither contains "one message when the time is set."

### Requirement: Every mail is a ledger row
`mail_deliveries` SHALL have `event_id` (cascade), `participant_id` (nullable, set NULL on delete), `kind` (`organizer_link`, `invitation`, `response_confirmation`, `finalized`, `link_shown`, `event_updated`, `cancelled`, `reopened`; database check `mail_deliveries_kind_allowed`), `recipient_email`, `canonical_recipient_email`, `sender_email` (the organizer's canonical email for `invitation` and `event_updated` rows), `request_ip`, `delivered_at`, `failed_at`, `error`, `created_at`, with indexes on `(canonical_recipient_email, created_at)`, `(sender_email, created_at)`, `(event_id, canonical_recipient_email)`, `(request_ip, created_at)` and `(participant_id, created_at)`. Migration `20260906000003_extend_mail_delivery_kinds.rb` SHALL drop `mail_deliveries_kind_allowed` and re-add it with `('organizer_link','invitation','response_confirmation','finalized','link_shown','event_updated','cancelled','reopened')`; its `down` SHALL re-add the five-kind check and SHALL fail when rows of the new kinds exist (documented; the round-trip test truncates first); `MailDelivery::KINDS` and the enum SHALL be extended in the same task, and the round-trip test's `MIGRATIONS` list SHALL include the migration. The row SHALL be created before enqueue for every kind; `after_deliver` SHALL set `delivered_at`; job handlers SHALL set `failed_at`. Rows SHALL survive participant removal, and cancellation SHALL delete none of them.

#### Scenario: Delivery marks the row
- **WHEN** an invitation job performs successfully
- **THEN** its ledger row has `delivered_at` set and `failed_at` NULL

#### Scenario: Ledger survives removal
- **WHEN** a guest with three ledger rows is removed
- **THEN** the three rows exist with `participant_id` NULL

#### Scenario: New kinds pass the check
- **WHEN** rows with `kind` `event_updated`, `cancelled` and `reopened` are inserted
- **THEN** each insert succeeds and `MailDelivery::KINDS` contains all eight kinds

#### Scenario: Notice rows carry the organizer as sender
- **WHEN** `Deliveries.event_updated!` reaches a guest
- **THEN** the `event_updated` row exists before the job is enqueued and has `sender_email` equal to `MailDelivery.canonical(organizer.email)` and `request_ip` set

#### Scenario: Rolling the kinds migration back
- **WHEN** `mail_deliveries` holds no rows of the three new kinds and `20260906000003` is rolled back
- **THEN** the five-kind `mail_deliveries_kind_allowed` check is in place again and an `event_updated` insert is refused

### Requirement: Send caps use canonical keys and do not scale with free identities
The system SHALL canonicalize addresses for caps by stripping a `+tag` from the local part and, for `gmail.com` and `googlemail.com`, removing dots. Four daily keys SHALL be shared by invitations and change notices and counted over `MailDelivery.where(kind: %w[invitation event_updated])` in the last 24 hours: a global budget (`INVITATION_DAILY_BUDGET`, default 500) beyond which the mail is refused and a warning is logged; 100 recipients per canonical organizer email, reduced to 20 while that organizer has no finalized event (`organizer_has_finalized?`, which keeps counting cancelled finalized events); 200 sends per request IP; 10 mails per canonical recipient address (system kinds exempt). `check_invitation!(event:, organizer:, recipient_email:, request_ip:)` SHALL count those four keys over the two-kind relation while its per (event, canonical address) rules stay `invitation`-only: 5 invitation sends ever and a 10-minute cooldown, excluding rows with `failed_at`. `check_update_notice!(event:, organizer:, recipient_email:, request_ip:)` SHALL apply the same four daily keys, then, on `event_updated` rows for the (event, canonical address) pair excluding rows with `failed_at`, a lifetime maximum of `UPDATE_NOTICES_PER_EVENT_ADDRESS = 5` and a cooldown of `UPDATE_NOTICE_COOLDOWN = 10.minutes` since the newest row. One `organizer_link` per canonical address per hour SHALL remain. `response_confirmation`, `finalized`, `cancelled` and `reopened` mails MUST never be refused by any cap. Invitation refusals SHALL be 303 alerts with a generic message and MUST NOT raise to the user; a refused notice SHALL raise `MailDelivery::CapExceeded` inside `Deliveries.event_updated!`, which SHALL rescue it per recipient, skip that recipient without a ledger row and count the skip so the flash reads "M skipped (recently notified). Try again after 10 minutes."

#### Scenario: Plus-addressing shares one allowance
- **WHEN** `spam+1@example.com` has used 100 invitation recipients today and `spam+2@example.com` sends more
- **THEN** the send is refused

#### Scenario: Global budget stops the cannon
- **WHEN** 500 `invitation` and `event_updated` rows together exist in the last 24 hours
- **THEN** the next invitation send and the next notice are refused and a warning is logged

#### Scenario: Starter allowance
- **WHEN** an organizer email with no finalized event has 20 invitation recipients today
- **THEN** the next send is refused, and after that organizer finalizes an event the limit becomes 100

#### Scenario: Cancelled finalized event keeps the allowance
- **WHEN** an organizer's only finalized event has been cancelled
- **THEN** `organizer_has_finalized?` is still true and the allowance stays 100

#### Scenario: Sixth notice per event and address is refused
- **WHEN** five non-failed `event_updated` rows exist for one event and one canonical address and a sixth is attempted
- **THEN** `check_update_notice!` raises `MailDelivery::CapExceeded`

#### Scenario: Second notice within ten minutes is refused
- **WHEN** an `event_updated` row for the pair was created 9 minutes ago
- **THEN** `check_update_notice!` raises `MailDelivery::CapExceeded`, and passes once the row is older than 10 minutes

#### Scenario: Failed notice rows do not count
- **WHEN** five `event_updated` rows exist for the pair and one of them has `failed_at` set
- **THEN** `check_update_notice!` passes

#### Scenario: Notices consume the shared recipient key
- **WHEN** a canonical recipient address has 7 `invitation` rows and 3 `event_updated` rows in the last 24 hours
- **THEN** both `check_invitation!` and `check_update_notice!` refuse the next mail to that address

#### Scenario: The invitation's per-event count ignores notices
- **WHEN** an address has 3 `event_updated` rows and 4 `invitation` rows for one event
- **THEN** `check_invitation!` still allows a fifth invitation for that pair

#### Scenario: A refused notice is skipped, not raised
- **WHEN** a notice reaches two guests and a third is refused by the cooldown
- **THEN** `Deliveries.event_updated!` returns `{ sent: 2, skipped: 1 }` without raising, no row exists for the third address and the flash contains "1 skipped (recently notified). Try again after 10 minutes."

#### Scenario: System kinds are never capped
- **WHEN** a recipient has reached 10 invitation mails today and five notices for an event they are on, and that event is finalized, reopened and then cancelled
- **THEN** the `finalized`, `reopened` and `cancelled` mails are each enqueued

### Requirement: Mail behavior is tested per template
`test/mailers/participant_mailer_test.rb` SHALL assert per template: recipient, subject, From fallback with `MAILER_FROM` removed in setup and restored in teardown, Reply-To, zone rendering, and the `organizer_link` freedom from organizer text. For every link-carrying template it SHALL assert the link in both parts: the raw token for `organizer_link` and `invitation`, `/p/<pending token>` for the unclaimed-guest copies of `finalized`, `event_updated` and `reopened`, and `/participations/<id>` with no `/p/` link for the claimed-guest copies; it SHALL assert that the organizer's `finalized` copy, every `cancelled` mail and every `response_confirmation` carry no link. It SHALL assert the invitation promise sentence and the confirmation's last sentence in both parts, the `finalized` closing sentence, the standing sentence on `finalized`, `event_updated` and `reopened`, one `event_updated` test per body variant (renamed event, voided guest, stale counting guest, declined guest), the `reopened` window in both zones, and that in every template the only `://` belongs to the participation link and `place_url` is absent. Attachments SHALL be decoded and asserted: `finalized` carries a `STATUS:CONFIRMED` file, `cancelled` a `STATUS:CANCELLED` file only when a window existed, `reopened` a `STATUS:CANCELLED` file with `SEQUENCE` equal to `revision`, each under 8 KB and free of `://`. `ParticipantMailerPreview` SHALL include a sample for every kind (place and plan set, a voided guest, `cancelled`, `reopened`) and one `event_updated` sample per reason; a test SHALL render every `ActionMailer::Preview`. Controller and integration tests SHALL use `assert_enqueued_emails` and `perform_enqueued_jobs` to pull links from deliveries.

#### Scenario: Preview rendering
- **WHEN** the preview test iterates `ActionMailer::Preview.all`
- **THEN** every preview method, including the `cancelled`, `reopened` and per-reason `event_updated` samples, renders without error

#### Scenario: Every link-carrying template is pinned in both parts
- **WHEN** the mailer tests run
- **THEN** a test fails if any of `organizer_link`, `invitation`, `finalized` (guest copy), `event_updated` or `reopened` drops the link from either part, or if the organizer's `finalized` copy or a `cancelled` mail gains one

#### Scenario: Attachments decode to valid files
- **WHEN** the `finalized`, `cancelled` (with a window) and `reopened` attachments are decoded in tests
- **THEN** each is a `text/calendar` document with the expected `STATUS`, `SEQUENCE:` equal to `events.revision`, no `://`, and a size of at most 8 KB
