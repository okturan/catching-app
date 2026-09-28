## MODIFIED Requirements

### Requirement: Recovery issues pending organizer tokens and touches nothing else
For each event in `Event.not_cancelled` (the scope `where(cancelled_at: nil)`, so pending or finalized events alike) whose organizer participant has the canonical address, the system SHALL issue a pending organizer token expiring in 24 hours, leave `token_digest` and `user_id` unchanged, and enqueue one `organizer_link` mail (constant content, unchanged from the foundation; it now also reaches finalized organizers) through the ledger. `OrganizerLinksController#create` SHALL use `Event.not_cancelled` in place of `Event.where(status: false)` as the event scope. A cancelled event, whether pending or finalized when cancelled, SHALL receive no token and no `organizer_link` row.

The one-`organizer_link`-per-canonical-address-per-hour rule (`MailDelivery::Caps.organizer_link_allowed?`) SHALL be checked once per request, before any event is considered: a request that passes it SHALL issue one token and enqueue one mail for every not-cancelled event of that address in the same request (N events yield N mails), and a request that fails it SHALL issue nothing.

#### Scenario: Recovery does not unclaim
- **WHEN** an anonymous client posts the recovery form for a claimed organizer's address
- **THEN** the organizer's `user_id` is unchanged and `GET /participations/<id>` still returns 200 for that user

#### Scenario: Current link keeps working
- **WHEN** recovery issues a pending token and the organizer then opens the old link
- **THEN** the old link returns 200

#### Scenario: A finalized event still recovers
- **WHEN** the recovery form is posted with the address of an organizer whose event is finalized (`status` true) and not cancelled
- **THEN** one pending organizer token expiring in 24 hours is issued for that organizer and one `organizer_link` mail with the same constant content as for a pending event is enqueued

#### Scenario: A cancelled event issues nothing
- **WHEN** the recovery form is posted with the address of an organizer whose only event has `cancelled_at` set
- **THEN** no pending organizer token is issued, no `organizer_link` ledger row is created and the response is the constant notice "If that address organizes an event, we sent it a new link."

#### Scenario: Only the not-cancelled events of an address are recovered
- **WHEN** one address organizes a pending event, a finalized event and a cancelled event, and no `organizer_link` row exists for it within the last hour
- **THEN** exactly two pending organizer tokens are issued and two `organizer_link` mails are enqueued, one each for the pending and the finalized event, and the cancelled event's organizer participant keeps `pending_token_digest` NULL

#### Scenario: N events yield N mails in one request
- **WHEN** one address organizes N not-cancelled events and posts the recovery form with no `organizer_link` row for it within the last hour
- **THEN** N `organizer_link` mails are enqueued in that one request and a second post within the hour enqueues none
