## ADDED Requirements

### Requirement: A public form requests a new organizer link
`GET /organizer_links/new` SHALL render an email form without a session. `POST /organizer_links` SHALL carry `rate_limit to: 5, within: 1.hour` per IP as a courtesy layer and SHALL always respond with the same status, redirect target and flash text ("If that address organizes an event, we sent it a new link.") whether the address is unknown, known, or capped.

#### Scenario: Known and unknown addresses are indistinguishable
- **WHEN** the form is posted with an organizer's address and then with an address that organizes nothing
- **THEN** both responses have identical status, location and flash

#### Scenario: Second request within the hour is silent
- **WHEN** the form is posted twice within an hour for the same canonical address
- **THEN** the second response is identical to the first and no second mail is enqueued

### Requirement: Recovery issues pending organizer tokens and touches nothing else
For each pending (not finalized) event whose organizer participant has the canonical address, the system SHALL issue a pending organizer token expiring in 24 hours, leave `token_digest` and `user_id` unchanged, and enqueue one `organizer_link` mail (constant content) through the ledger, at most one per canonical address per hour.

#### Scenario: Recovery does not unclaim
- **WHEN** an anonymous client posts the recovery form for a claimed organizer's address
- **THEN** the organizer's `user_id` is unchanged and `GET /participations/<id>` still returns 200 for that user

#### Scenario: Current link keeps working
- **WHEN** recovery issues a pending token and the organizer then opens the old link
- **THEN** the old link returns 200

### Requirement: The recovered link behaves like the organizer link
Opening the pending organizer link SHALL render the organizer page and, on the first such request, set `link_opened_at`; the first non-GET with the pending token SHALL promote it as defined in `capability-links`. An expired pending organizer token SHALL be refused with the friendly 404 page.

#### Scenario: Pending link proves delivery
- **WHEN** an organizer whose `link_opened_at` is NULL opens the recovered link
- **THEN** `link_opened_at` is set and no mail is sent

### Requirement: The dashboard offers the same path
On the session-family organizer page and on the pending page, "Send the link again" SHALL submit the recovery form for the organizer's address.

#### Scenario: Send the link again from the dashboard page
- **WHEN** a signed-in organizer presses "Send the link again"
- **THEN** the recovery flow runs for their address and the constant flash is shown
