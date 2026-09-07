## ADDED Requirements

### Requirement: A guest sees the event and the offer through their link
`GET /p/:token` for a guest SHALL render the event name, description, organizer display name, the reply summary, a time-zone picker preselected to the guest's saved `time_zone` (else the browser zone) captioned with the event zone, an optional "Your name" field, and the show grid with the organizer's offered instants, the guest's saved instants pre-painted and pre-serialized, and per-cell counts of other counting participants. The page MUST NOT reveal other guests' email addresses.

#### Scenario: Guest page contract
- **WHEN** a guest with two saved slots opens their link
- **THEN** the page contains `table#time-grid-show[role=grid][data-role="guest"][data-slot-minutes]`, `#received-time-slots` with the offer, `#my-time-slots` with the two instants, `#availability-counts`, and no email address of another guest

#### Scenario: Saved zone is preferred
- **WHEN** a guest who saved `Asia/Kolkata` reopens their link from a browser in `Europe/Berlin`
- **THEN** the zone picker is preselected to `Asia/Kolkata`

### Requirement: Saving availability replaces the guest's slots atomically
`PATCH /p/:token` (guest only) SHALL parse `time_slots[time_slot_array]` with the event's `slot_minutes`, verify every instant is on the event grid, is offered by the organizer, and is not before the past cut-off, then inside `event.with_lock` delete the guest's slots and insert the new ones with `insert_all!`, set `responded_at`, `name` and `time_zone`, clear `declined_at`, and redirect with notice "Availability saved.". Validation failures SHALL redirect back with status 303 and the exact alert: "Select at least one time slot", "Select only time slots offered by the organizer", "Select time slots on the event's <n>-minute grid", "Select time slots from today onward", "Availability is closed for this event", or the time-zone error.

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

#### Scenario: Invalid time zone is refused
- **WHEN** a guest saves with `participant[time_zone]=Mars/Olympus`
- **THEN** the response is 303 with an alert naming the time zone and no slot changes

### Requirement: Past instants are not selectable and unsaved paint survives a rejection
The server SHALL pass the parser's past cut-off on the grid root (`data-not-before`); the grid SHALL mark earlier offered instants as past (not selectable, `aria-disabled="true"`, muted) and exclude them from the summary. When no selectable instant remains the page SHALL show "All the offered times have passed" and hide Save. The component SHALL stash the last serialized selection in `sessionStorage` keyed by token before submit and re-apply it after a redirect back with an alert.

#### Scenario: Expired offer shows the empty state
- **WHEN** every offered instant is before the cut-off
- **THEN** the page shows "All the offered times have passed" and no Save button

#### Scenario: Rejected save keeps the painted cells
- **WHEN** a save is rejected with a 303 alert
- **THEN** after the page reloads the previously painted cells are painted again and the alert is visible in the action bar

### Requirement: First reply triggers one confirmation
The system SHALL enqueue `ParticipantMailer#response_confirmation` exactly once per guest, on the first save or decline (when `responded_at` was NULL before the write). Later saves SHALL show only the notice.

#### Scenario: Confirmation only once
- **WHEN** a guest saves availability twice
- **THEN** exactly one `response_confirmation` mail is enqueued

### Requirement: A guest can say none of these times work
`POST /p/:token/decline` (guest only) SHALL, inside `event.with_lock`, delete the guest's slots, set `responded_at` and `declined_at`, keep both tokens and `user_id`, and redirect with a notice. A declined guest SHALL be excluded from consensus and MAY change the answer later by saving availability, which clears `declined_at`.

#### Scenario: Decline clears slots and keeps the link
- **WHEN** a guest with saved slots declines
- **THEN** the guest has zero slots, `declined_at` is set, the same link still returns 200, and the guest is not in `participants.counting`

#### Scenario: Saving after declining reverses it
- **WHEN** a declined guest saves an offered instant
- **THEN** `declined_at` is NULL and the guest counts again

### Requirement: A guest can leave the event for good
`DELETE /p/:token` (guest only) SHALL call `Participant#leave!` and respond with a 303 redirect to the site root carrying the notice "You left <event name>." A left guest's links SHALL return 404 in both families, the guest SHALL receive no further mail, and the row SHALL NOT be revived by invite-more, resend or bulk send. A `pageshow` handler SHALL reload a bfcache-restored capability page so a dead grid is never shown.

#### Scenario: Leave redirects and revokes
- **WHEN** a guest confirms "Leave this event"
- **THEN** the response redirects to the root with "You left <event name>.", the slots are gone, `left_at` and `declined_at` are set, both digests and `user_id` are NULL, and the next GET with the old link is 404

#### Scenario: Left guest is not re-invited by resend
- **WHEN** the organizer presses "Send invitations" after a guest left
- **THEN** the left guest receives no mail and no token

### Requirement: Finalized events are read-only for guests
When the event is finalized the guest page SHALL show the confirmed window rendered server-side in the event zone with the zone name and, through the grid component, in the picker zone, SHALL hide the save, decline and leave forms, and SHALL refuse writes with "Availability is closed for this event".

#### Scenario: Finalized guest page
- **WHEN** a guest opens their link after finalization
- **THEN** the page shows the window twice (event zone and picker zone), `#time-grid-show[data-finalized]` is present, and no availability, decline or leave form is rendered

### Requirement: The selection survives zone changes and redraws
On the show page the component SHALL keep the selection as a set of UTC instants that survives a zone change and any redraw; the hidden `#new-time-slot-array` SHALL be re-serialized after each stroke and on submit; changing the zone MUST NOT clear painted cells.

#### Scenario: Zone change keeps the paint
- **WHEN** a guest paints three cells and switches the picker to another zone
- **THEN** the same three instants are painted in the new layout and the hidden input still lists them
