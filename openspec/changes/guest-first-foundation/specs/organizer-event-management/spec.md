## ADDED Requirements

### Requirement: The organizer page shows every participant and the reply state
`GET /p/:token` for an organizer (and `GET /participations/:id` for a claimed organizer) SHALL render a participant table with, per guest: email, name, and one state among "not sent", "queued", "sent on <date>", "delivery unknown, resend" (queued for more than 15 minutes), "could not be delivered", "replied (N slots)", "none of these work", "left"; a Resend and a Remove control per active guest; an "Invite more people" textarea; and a reply summary with separate counts: n = active guests with a live token, k = counting guests, d = declined guests, u = guests not yet invited. While no guest counts, the page SHALL show the waiting state ("No replies yet. Invitations sent to N people.") with the grid in viewer mode; once at least one guest counts the grid SHALL be in organizer mode with consensus cells selectable.

#### Scenario: Counts are defined by scopes
- **WHEN** an event has 5 guests: 2 replied, 1 declined, 1 invited with no reply, 1 never sent
- **THEN** the summary shows 4 invited, 2 replied, 1 cannot make it, 1 not yet invited

#### Scenario: Waiting state before any reply
- **WHEN** invitations were sent and nobody has replied
- **THEN** the page shows "No replies yet" with the number invited and `#time-grid-show[data-role="viewer"]`, and no finalize form

### Requirement: Verify-by-click gates invitations
`link_opened_at` SHALL be set only on the first request that resolves the organizer row through the token family (live or pending organizer token). A request through the session family MUST NOT set it. The GET that sets it MUST NOT send any mail. Invitations, invite-more and resend SHALL require `link_opened_at`; otherwise the organizer page SHALL render, instead of the Send button, "Open the organizer link we emailed to <address> to send invitations" with a "Send the link again" control that uses the organizer-link recovery path, and a POST SHALL be refused with a 303 alert.

#### Scenario: First organizer link open is the delivery proof
- **WHEN** the organizer opens the emailed link for the first time
- **THEN** `link_opened_at` is set, no mail is enqueued, and the Send button is rendered

#### Scenario: Dashboard visit does not verify
- **WHEN** a signed-in organizer opens the event from the dashboard before opening the emailed link
- **THEN** `link_opened_at` stays NULL, the page shows the "Open the organizer link" hint and no Send button, and `POST /participations/:id/invitations` responds 303 with an alert

### Requirement: Sending invitations issues tokens and mail through the ledger
`POST /p/:token/invitations` (organizer with `link_opened_at`) SHALL issue a live token for every `unsent` guest, create one `invitation` ledger row and enqueue one `invitation` mail per guest, subject to the caps in `transactional-email`. Left guests SHALL be skipped. When `invitations[emails]` is present the addresses SHALL be parsed as in `event-planning`, deduplicated against the event's existing addresses (naming duplicates and left addresses in the flash), and added as guests before sending; the event SHALL never exceed 50 guests. The response SHALL be a 303 to the organizer page with a notice stating how many invitations were sent.

#### Scenario: Bulk send reaches only unsent active guests
- **WHEN** an event has two unsent guests, one guest already invited and one left guest, and the organizer presses Send
- **THEN** exactly two live tokens are issued, two `invitation` jobs and two ledger rows are created, and the left guest and the already-invited guest are untouched

#### Scenario: Invite more deduplicates and names conflicts
- **WHEN** the organizer submits `invitations[emails]` containing an existing guest's address, a left guest's address and a new address
- **THEN** only the new address becomes a guest and is mailed, and the flash names the duplicate and the left address

#### Scenario: Cap on guests per event
- **WHEN** an event already has 50 guests and the organizer adds one more address
- **THEN** the response is 303 with an alert stating the limit and no guest is added

### Requirement: Resend issues a replacement without breaking the working link
`POST /p/:token/participants/:participant_id/resend` (organizer with `link_opened_at`) SHALL target an active guest of the organizer's event. If the guest has no live token it SHALL issue a live token; otherwise it SHALL issue a pending token that never expires. It SHALL enqueue an `invitation` mail through the ledger, honoring a 10-minute cooldown and a lifetime cap of 5 sends per (event, address), where ledger rows with `failed_at` set count toward neither. It MUST NOT change `user_id`. The response SHALL confirm the send without displaying the raw token.

#### Scenario: Resend after a failed delivery is immediate
- **WHEN** the last `invitation` row for a guest has `failed_at` set and the organizer presses Resend one minute later
- **THEN** a new mail is enqueued and the response is a notice, not a cooldown alert

#### Scenario: Resend keeps the old link alive
- **WHEN** a guest has a live token and the organizer presses Resend
- **THEN** the guest gains a pending token, the old link still returns 200, and `user_id` is unchanged

#### Scenario: Sixth send to one address is refused
- **WHEN** five successful `invitation` rows exist for one (event, address)
- **THEN** Resend responds 303 with an alert stating the limit and enqueues nothing

### Requirement: Showing a link to copy is an explicit, recorded action
The organizer page SHALL offer "Show link to copy" per active guest as a confirmed POST that names the impersonation risk ("Anyone with this link can answer as this guest"). On confirmation the system SHALL issue a token as Resend does, record a `link_shown` ledger row, and display the URL once in the response as plain text (never an anchor). The URL MUST NOT appear in any later page.

#### Scenario: Link shown once and recorded
- **WHEN** the organizer confirms "Show link to copy" for a guest
- **THEN** the response contains the URL as text, a `link_shown` ledger row exists, and reloading the page does not contain the URL

### Requirement: Removing a guest keeps the ledger
`DELETE /p/:token/participants/:id` (organizer only) SHALL delete the guest row and its slots inside `event.with_lock`; `mail_deliveries.participant_id` SHALL be set NULL by the database and the rows SHALL keep counting toward caps. Re-adding the same address later SHALL be subject to the (event, address) lifetime cap.

#### Scenario: Remove then re-add honors the lifetime cap
- **WHEN** an address has received five invitations on an event, is removed, and is added again
- **THEN** sending to it is refused with the limit alert

#### Scenario: Remove deletes availability
- **WHEN** a responded guest is removed
- **THEN** the participant and its slots are gone and the consensus no longer includes them

### Requirement: Organizer capabilities are exactly these
An organizer SHALL be able to send, invite more, resend, show a link, remove a guest and finalize. The organizer SHALL NOT be able to revise the offer, edit or delete the event, or respond as a guest in this change; no route for those actions SHALL exist.

#### Scenario: No offer revision route
- **WHEN** an organizer token sends PATCH to `/p/:token` with availability
- **THEN** the response is 404 and the offer is unchanged
