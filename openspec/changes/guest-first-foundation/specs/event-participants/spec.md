## ADDED Requirements

### Requirement: Every person on an event is a Participant
The system SHALL represent every person on an event as a row in `participants` with `event_id`, `role` (`organizer` or `guest`), a normalized `email`, an optional `name`, and a nullable `user_id`. Each event SHALL have exactly one organizer participant, and each email address SHALL appear at most once per event. These invariants MUST be enforced by database constraints (partial unique index on `(event_id) WHERE role = 'organizer'`, unique index on `(event_id, email)`, check on `role`).

#### Scenario: Event creation produces an organizer row
- **WHEN** an event is planned by `ann@example.com` with invitees `bob@example.com` and `cy@example.com`
- **THEN** the event has one participant with role `organizer` and email `ann@example.com` and two participants with role `guest`

#### Scenario: A second organizer is refused by the database
- **WHEN** a second participant with role `organizer` is inserted for the same event
- **THEN** the insert fails with a uniqueness violation and no row is written

#### Scenario: Duplicate email on one event is refused
- **WHEN** a guest participant is inserted with an email that already exists on that event
- **THEN** the insert fails with a uniqueness violation

### Requirement: Participant emails are normalized and strictly formatted
The system SHALL normalize participant emails by stripping surrounding whitespace and lowercasing before validation and storage. The system SHALL accept only addresses matching `URI::MailTo::EMAIL_REGEXP` (ASCII, a single address, no `,`, `<`, `>`, or `"`), at most 254 characters. A database check MUST reject stored emails that contain uppercase ASCII letters, leading or trailing whitespace, or no `@` after the first character.

#### Scenario: Whitespace and case are normalized
- **WHEN** a participant is created with email `"  Bob@Example.COM "`
- **THEN** the stored email is `bob@example.com`

#### Scenario: Address lists and angle brackets are rejected
- **WHEN** a participant is created with email `a@b.example,c@d.example` or `Bob <bob@example.com>`
- **THEN** validation fails with an email format error and nothing is stored

#### Scenario: Database rejects an unnormalized email
- **WHEN** `update_columns(email: "Bob@example.com")` is executed on a participant
- **THEN** the statement fails with a check-constraint violation

### Requirement: Participant names are optional for guests, required for organizers, and bounded
The system SHALL squish participant names (collapse internal whitespace, strip ends) and limit them to 100 characters. An organizer participant MUST have a name. A guest with no name SHALL be displayed as "Guest" to other guests and as their email to the organizer. Names SHALL never contain carriage returns or line feeds after normalization.

#### Scenario: Organizer without a name is invalid
- **WHEN** an organizer participant is saved with a blank name
- **THEN** validation fails on `name`

#### Scenario: Guest without a name is displayed neutrally
- **WHEN** a guest with no name has responded and another guest views the event
- **THEN** the other guest sees "Guest" and never the email address

#### Scenario: A name with a line break is normalized
- **WHEN** a participant is saved with name `"Ann\r\nBcc: x@y.example"`
- **THEN** the stored name contains no `\r` or `\n`

### Requirement: Availability belongs to a participant
The system SHALL store availability in `time_slots` with `participant_id` and `event_id`, both NOT NULL. A unique index on `(participant_id, start_time)` SHALL prevent duplicate instants per participant. A composite foreign key `(participant_id, event_id) -> participants(id, event_id)` with `ON DELETE CASCADE` SHALL guarantee a slot belongs to a participant of the same event. `time_slots.user_id` and `time_slots.end_time` SHALL NOT exist.

#### Scenario: Slot for a participant of another event is refused
- **WHEN** a time slot is inserted with `participant_id` from event A and `event_id` of event B
- **THEN** the insert fails with a foreign-key violation

#### Scenario: Deleting a participant deletes their slots
- **WHEN** a participant row is deleted
- **THEN** all `time_slots` rows with that `participant_id` are deleted by the database

#### Scenario: Duplicate instant for one participant is refused
- **WHEN** two slots with the same `start_time` are inserted for one participant with `insert_all!`
- **THEN** the statement raises a uniqueness error and the transaction is rolled back

### Requirement: Participation state is recorded in timestamps with database-enforced consistency
The system SHALL track `responded_at` (organizer: creation time; guest: every save or decline), `declined_at` (set by decline or leave, cleared by a later save), `left_at` (set by leave, never cleared), and `link_opened_at` (organizer only; first request through the organizer token). Database checks MUST enforce: `declined_at IS NULL OR responded_at IS NOT NULL`; and `left_at IS NULL OR (token_digest IS NULL AND pending_token_digest IS NULL AND declined_at IS NOT NULL AND user_id IS NULL AND role = 'guest')`.

#### Scenario: Declined without responded is refused
- **WHEN** `update_columns(declined_at: Time.current, responded_at: nil)` is executed
- **THEN** the statement fails with a check-constraint violation

#### Scenario: A left row must be revoked, unclaimed and a guest
- **WHEN** `update_columns(left_at: Time.current)` is executed on a guest that still has a `token_digest`
- **THEN** the statement fails with a check-constraint violation

#### Scenario: Organizer cannot be marked left
- **WHEN** an organizer row is updated with `left_at` set and all other left-state columns satisfied
- **THEN** the statement fails with a check-constraint violation

### Requirement: Participant scopes define who counts
The system SHALL provide scopes: `active` (`left_at IS NULL`), `counting` (`responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL`), `linked` (`token_digest IS NOT NULL`), and `unsent` (guests, active, with no live token). Consensus, invitations and the dashboard MUST use these scopes rather than ad hoc conditions.

#### Scenario: Counting excludes pending, declined and left guests
- **WHEN** an event has an organizer, a guest who saved slots, a guest who declined, a guest who never replied and a guest who left
- **THEN** `participants.counting` returns exactly the organizer and the guest who saved slots

#### Scenario: Unsent lists guests that were never given a live link
- **WHEN** an event has a guest with no token digest, a guest with a live token and a guest who left
- **THEN** `participants.unsent` returns only the first guest

### Requirement: Account linkage is optional and one account per event
The system SHALL allow `participants.user_id` to be NULL. A partial unique index on `(user_id, event_id) WHERE user_id IS NOT NULL` SHALL ensure one account holds at most one participation per event. The foreign key `participants.user_id -> users(id)` SHALL be `ON DELETE SET NULL`.

#### Scenario: Deleting an account keeps the event and the availability
- **WHEN** a user who organized an event with two responded guests deletes their account
- **THEN** the event, all participants and all time slots still exist and the organizer participant has `user_id` NULL

#### Scenario: One account cannot hold two participations on an event
- **WHEN** a second participant on the same event is updated to the same `user_id`
- **THEN** the update fails with a uniqueness violation

### Requirement: Event deletion cascades to participation data
The database SHALL cascade `events` deletion to `participants`, `time_slots` and `mail_deliveries` through `ON DELETE CASCADE` foreign keys.

#### Scenario: Deleting an event removes its participation data
- **WHEN** an event row with participants, slots and ledger rows is deleted with SQL
- **THEN** no participants, time slots or mail deliveries reference it afterwards

### Requirement: User ownership structures are removed
The system SHALL NOT have an `events.user_id` column, a `user_events` table, a `UserEvent` model, or `User#events`, `User#time_slots`, `User#user_events`, `User#invited_events` associations. `User` SHALL have `has_many :participants, dependent: :nullify` and `has_many :events, through: :participants`.

#### Scenario: Legacy table is absent after migration
- **WHEN** the migrations for this change have run
- **THEN** `connection.table_exists?("user_events")` is false and `Event.column_names` excludes `user_id`

#### Scenario: A user's events are reached through participations
- **WHEN** a user has a claimed organizer participation and a claimed guest participation
- **THEN** `user.events` returns both events

### Requirement: Migrations are reversible and match the committed schema
Each migration in this change SHALL define explicit `up` and `down` methods (or use `reversible` blocks) so that `db:rollback STEP=4` succeeds on an empty database. Check constraints on empty tables SHALL be added validated in one step. `db/schema.rb` SHALL remain the load source and MUST equal the dump produced after running the migrations. A test SHALL run the four migrations down and up inside a transaction, assert the resulting shape with connection introspection only, and compare the schema dump (via `ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)`) with `db/schema.rb`, normalizing only the trailing newline.

#### Scenario: Round trip leaves the schema identical
- **WHEN** the migration round-trip test truncates all tables with cascade, runs the four migrations down in reverse, then up
- **THEN** the schema dump equals `db/schema.rb` and `connection.foreign_keys(:time_slots)` includes the composite participant foreign key

#### Scenario: Rolling back restores the legacy shape
- **WHEN** the four migrations are run down in reverse on an empty database
- **THEN** `user_events` exists, `events.user_id` exists and is nullable, `time_slots.user_id` and `time_slots.end_time` exist, and `participants` and `mail_deliveries` do not exist

### Requirement: Fixtures model the participant world
Test fixtures SHALL define participants for the planning, other and finalized events (organizer, responded guest, pending guest, left guest) with digests computed from literal 32-character raw tokens, `events.slot_minutes: 60` and `events.time_zone: UTC` so hour-aligned assertions keep their meaning. A fixture-integrity test SHALL assert that no slot's `event_id` differs from its participant's `event_id` and that every participant's `event_id` and `user_id` reference existing rows.

#### Scenario: Fixture integrity holds
- **WHEN** the fixture-integrity test runs against the loaded fixtures
- **THEN** it finds zero drifted slots and zero dangling references
