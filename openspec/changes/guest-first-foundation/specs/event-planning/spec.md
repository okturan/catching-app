## ADDED Requirements

### Requirement: Anyone can start planning an event
`GET /events/new`, `POST /events` and `GET /events/pending` SHALL be reachable without a session. The navbar and the home page SHALL show "PLAN YOUR MEETING NOW" to signed-out visitors. When the visitor is signed in, the organizer email SHALL be `current_user.email`; a posted `organizer[email]` MUST be ignored and the field MUST NOT be rendered.

#### Scenario: Signed-out visitor reaches the form
- **WHEN** a signed-out visitor requests `GET /events/new`
- **THEN** the response is 200 and contains fields `event[name]`, `event[description]`, `event[slot_minutes]`, `event[time_zone]`, `organizer[name]`, `organizer[email]`, `invitations[emails]` and the hidden `time_slots[time_slot_array]`

#### Scenario: Signed-in organizer email cannot be overridden
- **WHEN** a signed-in user posts `organizer[email]=other@example.com`
- **THEN** the organizer participant's email is the signed-in user's email and the row is claimed by that user

### Requirement: Event fields are validated and bounded
The system SHALL require `event[name]` (squished, at most 120 characters) and `event[description]` (stripped, paragraphs kept, at most 2000 characters), `event[slot_minutes]` in {15, 30, 60} (default 30), `event[time_zone]` accepted by `ActiveSupport::TimeZone[]`, `organizer[name]` (at most 100 characters), and a valid organizer email. `invitations[emails]` SHALL be rejected before parsing when longer than 4096 bytes.

#### Scenario: Unknown time zone is refused
- **WHEN** an event is posted with `event[time_zone]=Mars/Olympus`
- **THEN** the response is 422 and the error names the time zone

#### Scenario: Oversized description is refused
- **WHEN** an event is posted with a 2001-character description
- **THEN** the response is 422 and no event is created

### Requirement: Invitee lists are parsed, normalized and capped
`InviteeListParser` SHALL split `invitations[emails]` on commas and newlines, strip and lowercase each address, drop blanks, deduplicate, drop the organizer's own address, and reject the list when it contains an address that fails the participant email format (naming the address) or when more than 50 addresses remain.

#### Scenario: Mixed separators and case are handled
- **WHEN** the list is `"Bob@Example.com, cy@example.com\nbob@example.com\n\nann@example.com"` and the organizer is `ann@example.com`
- **THEN** the parsed guests are exactly `bob@example.com` and `cy@example.com`

#### Scenario: Invalid address is named
- **WHEN** the list contains `not-an-address`
- **THEN** the response is 422 and the base error names `not-an-address`

#### Scenario: Fifty-one guests are refused
- **WHEN** the list contains 51 distinct valid addresses
- **THEN** the response is 422 with a message stating the limit of 50

### Requirement: Event creation is one atomic operation
`Event.plan!` SHALL create, in one transaction: the event; the organizer participant (`responded_at` now, `link_opened_at` NULL, `user_id` when signed in); the organizer's offered slots through `replace_time_slots!` (validated as aligned, inside 31 days, not before the past cut-off, at least one); one guest participant per invitee with no token; and the `organizer_link` ledger row. Any failure SHALL roll back everything and re-render the form with status 422, echoing the hidden slot value, the selected zone and step via `data-selected`, the organizer fields, the invitee list, and base errors rendered explicitly.

#### Scenario: Successful plan writes everything
- **WHEN** a valid form with two aligned slots and two invitees is posted
- **THEN** exactly one event, three participants, two time slots and one `organizer_link` mail delivery row exist, and no guest has a token digest

#### Scenario: Invalid slots roll back the whole plan
- **WHEN** a form is posted with `time_slots[time_slot_array]=not-a-time`
- **THEN** no event, participant, time slot or mail delivery is created, the response is 422, and the rendered form contains the posted organizer name, invitee list and `data-selected` zone

#### Scenario: Missing slots is a validation error, not a 400
- **WHEN** a form is posted with an empty `time_slots[time_slot_array]`
- **THEN** the response is 422 with the base error "Select at least one time slot"

### Requirement: Creation sends only the organizer link
After a successful plan the system SHALL enqueue exactly one `organizer_link` mail to the organizer and zero invitations, then redirect to `GET /events/pending`. The pending page SHALL read the address from the flash ("We emailed your organizer link to <address>"), degrade to "the address you entered" on refresh, and state that nothing has been sent to guests until the organizer opens that link and presses Send.

#### Scenario: One mail, no invitations
- **WHEN** a valid plan with three invitees is posted
- **THEN** one `organizer_link` job is enqueued and no `invitation` job or ledger row exists

#### Scenario: Pending page explains the next step
- **WHEN** the organizer follows the redirect after creating an event
- **THEN** the page contains the organizer's address and the sentence explaining that guests receive nothing until the link is opened and Send is pressed

### Requirement: Creation is capped without leaking identities
`POST /events` SHALL carry `rate_limit to: 5, within: 10.minutes` per IP as a courtesy layer. The system SHALL refuse creation when, for the canonical organizer email, five events whose organizer opened the link were created in the last 24 hours, or when three unopened events were created for that address from the requesting IP in the last 24 hours, or when ten unopened events were created from the requesting IP in the last 24 hours. Refusals SHALL respond 303 to the form with the generic alert "Could not create the event right now. Try again later." and the response MUST be identical whether or not the address belongs to an account.

#### Scenario: Sixth opened event in a day is refused
- **WHEN** an organizer email already has five events created today whose organizer link was opened
- **THEN** the next creation is refused with the generic alert and nothing is written

#### Scenario: Third party cannot exhaust a victim's allowance
- **WHEN** an attacker creates three events with a victim's address from one IP, then the victim creates an event from another IP
- **THEN** the victim's creation succeeds

#### Scenario: Known and unknown address refusals are identical
- **WHEN** creation is refused for an address that has an account and for one that does not
- **THEN** both responses have the same status, redirect target and flash text

### Requirement: Legacy event routes no longer exist
The routes `GET /events/:id`, `PATCH /events/:id` and `POST /events/:event_id/time_slots` SHALL be removed along with `TimeSlotsController`, `events/show.html.erb` and `time_slots/new.html.erb`.

#### Scenario: Old event page is gone
- **WHEN** a signed-in user requests `GET /events/1`
- **THEN** the router raises a routing error (no route matches) and the request does not reach a controller
