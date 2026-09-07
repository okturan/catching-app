## ADDED Requirements

### Requirement: Consensus counts responders only, in one statement
`Event#mutually_available_start_times` SHALL return the start times held by every counting participant (`responded_at` set, not declined, not left; the organizer counts from creation). It SHALL be one SQL statement: numerator filtered to counting participants, `HAVING COUNT(DISTINCT participant_id) = (correlated count of counting participants)` combined with `EXISTS` (at least one counting guest), so the denominator and the guard share one snapshot. With no counting guest it SHALL return an empty list.

#### Scenario: Silent invitee does not block
- **WHEN** the organizer offered 10:00 and 11:00, guest A saved 10:00, and guest B never replied
- **THEN** consensus is `[10:00]`

#### Scenario: Declined guest is excluded
- **WHEN** guest A saved 10:00 and guest B declined
- **THEN** consensus is `[10:00]`

#### Scenario: Organizer alone yields nothing
- **WHEN** no guest counts
- **THEN** consensus is empty and the query count for the call is exactly one

### Requirement: Finalize is organizer-only, locked and validated in order
`POST /p/:token/finalization` SHALL parse `time_slots[time_slot_array]` with the event's `slot_minutes` and call `Event#finalize!(starts_at:)`, which inside `with_lock` SHALL check: pending (`Event::ClosedError`, "Availability is closed for this event"); at least one counting guest ("Wait for at least one reply before confirming"); every selected instant in consensus ("Select only time slots available to every participant"); contiguity with gap exactly `slot_length` ("Select one continuous meeting window"); then set `start_time` = min, `end_time` = max + `slot_length`, `status` = true. A database check SHALL require the finalized window to be a whole number of slots. Success SHALL redirect with "Meeting time confirmed."; each failure SHALL redirect with status 303 and the exact message.

#### Scenario: Successful finalize at 30 minutes
- **WHEN** the organizer selects 10:00 and 10:30 on a 30-minute event where both are consensus
- **THEN** `start_time` is 10:00, `end_time` is 11:00, `status` is true and the notice is "Meeting time confirmed."

#### Scenario: Finalize before any reply is refused
- **WHEN** the organizer finalizes an event whose guests have not replied
- **THEN** the response is 303 with "Wait for at least one reply before confirming" and `status` stays false

#### Scenario: Discontinuous window is refused
- **WHEN** the organizer selects 10:00 and 12:00 on a 60-minute event
- **THEN** the response is 303 with "Select one continuous meeting window"

#### Scenario: Second finalize is refused
- **WHEN** an already finalized event receives another finalization
- **THEN** the response is 303 with "Availability is closed for this event" and the window is unchanged

### Requirement: Every writer of the denominator takes the event lock
`replace_time_slots!`, `mark_unavailable!`, `Participant#leave!`, guest removal, claim and `finalize!` SHALL run inside `event.with_lock`, so a finalize cannot interleave with a decline, leave, removal or claim. The two existing stale-request tests SHALL keep asserting exactly one `FOR UPDATE` statement. A contention test in a class with `use_transactional_tests = false` SHALL show a second connection's `with_lock` blocks until the first transaction commits.

#### Scenario: Concurrent decline is observed by finalize
- **WHEN** a decline commits on a second connection while a finalize holds the lock and the finalize then re-reads consensus
- **THEN** the finalize sees the declined guest excluded and either succeeds on the remaining consensus or fails with the consensus message, never with a stale window

### Requirement: Finalization notifies everyone with a live link
After `finalize!` commits the system SHALL enqueue `ParticipantMailer#finalized` once per participant with a live token (including declined guests who still hold a link; excluding left and never-invited guests), each as its own job.

#### Scenario: One job per linked participant
- **WHEN** an event with an organizer, two invited guests (one declined), one unsent guest and one left guest is finalized
- **THEN** exactly three `finalized` jobs are enqueued

### Requirement: The closed event is read-only everywhere
After finalization the organizer and guest pages SHALL show the confirmed window (event zone server-side, picker zone client-side), `#time-grid-show[data-finalized]` SHALL be present, and every write in either family SHALL be refused with "Availability is closed for this event".

#### Scenario: Organizer page after finalize
- **WHEN** the organizer opens the event after finalizing
- **THEN** the page shows the window and no finalize, send, resend or remove form
