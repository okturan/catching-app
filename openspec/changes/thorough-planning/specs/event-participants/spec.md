## MODIFIED Requirements

### Requirement: Participation state is recorded in timestamps with database-enforced consistency
The system SHALL track `responded_at` (organizer: creation time; guest: every save or decline), `declined_at` (set by decline or leave, cleared by a later save), `left_at` (set by leave, never cleared), `link_opened_at` (organizer only; first request through the organizer token) and `reply_voided_at` (guest only; set by `Event#revise_offer!` inside its `with_lock` transaction on every guest that has `responded_at`, no `declined_at`, no `left_at` and holds no slot once the revision has deleted guest rows at removed instants; cleared by that guest's next save, decline or leave). Voiding MUST NOT reset `responded_at`, so a voided guest's later save is not a first reply and enqueues no second `response_confirmation`. The three clearing writers SHALL each clear `reply_voided_at` in the same `update!` statement as their other columns: `ParticipationsController#update` sets `reply_voided_at: nil` together with `responded_at` and `declined_at: nil`; `Event#mark_unavailable!` sets `reply_voided_at: nil` alongside `declined_at` in its own `update!`; `Participant#leave!` sets `reply_voided_at: nil` in its `update!`. Database checks MUST enforce: `participants_declined_implies_responded` (`declined_at IS NULL OR responded_at IS NOT NULL`); `participants_left_is_revoked` (`left_at IS NULL OR (token_digest IS NULL AND pending_token_digest IS NULL AND declined_at IS NOT NULL AND user_id IS NULL AND role = 'guest')`); and `participants_voided_is_open_reply` (`reply_voided_at IS NULL OR (responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND role = 'guest')`), added validated in one step by `20260906000001_add_planning_state_to_events_and_participants.rb` together with the column `participants.reply_voided_at datetime NULL`. Because the checks fire per statement, setting `declined_at` or `left_at` on a voided row in one statement and clearing `reply_voided_at` in a later one MUST fail with `ActiveRecord::StatementInvalid`.

#### Scenario: Declined without responded is refused
- **WHEN** `update_columns(declined_at: Time.current, responded_at: nil)` is executed
- **THEN** the statement fails with a check-constraint violation

#### Scenario: A left row must be revoked, unclaimed and a guest
- **WHEN** `update_columns(left_at: Time.current)` is executed on a guest that still has a `token_digest`
- **THEN** the statement fails with a check-constraint violation

#### Scenario: Organizer cannot be marked left
- **WHEN** an organizer row is updated with `left_at` set and all other left-state columns satisfied
- **THEN** the statement fails with a check-constraint violation

#### Scenario: Only an open guest reply can be voided
- **WHEN** `update_columns(reply_voided_at: Time.current)` is executed on a declined guest, on a guest with `responded_at` NULL, on a guest who left, or on the organizer
- **THEN** each statement fails with `ActiveRecord::StatementInvalid` from `participants_voided_is_open_reply` and the row is unchanged

#### Scenario: A voided guest who replied and now holds nothing is marked, not reset
- **WHEN** an offer revision removes every instant a replied guest had picked
- **THEN** that guest has `reply_voided_at` set, zero `time_slots` rows, and `responded_at`, `declined_at`, `left_at`, `name`, `time_zone`, `user_id` and both token digests unchanged

#### Scenario: Decline clears the void in one statement
- **WHEN** `event.mark_unavailable!(participant:)` runs for a guest with `reply_voided_at` set
- **THEN** `declined_at` is set and `reply_voided_at` is NULL after a single `update!`, and no `ActiveRecord::StatementInvalid` is raised

#### Scenario: Leave clears the void in one statement
- **WHEN** `leave!` runs for a guest with `reply_voided_at` set
- **THEN** `left_at` and `declined_at` are set, `reply_voided_at` is NULL, both credentials and the claim are gone, and the row satisfies `participants_left_is_revoked` and `participants_voided_is_open_reply`

#### Scenario: Save clears the void without a second confirmation
- **WHEN** a guest with `reply_voided_at` set sends `PATCH /p/:token` with one currently offered instant
- **THEN** `reply_voided_at` is NULL, `responded_at` is updated and `declined_at` is NULL in the same `update!`, and no second `response_confirmation` is enqueued

#### Scenario: Clearing the void in a later statement is refused
- **WHEN** `update_columns(declined_at: Time.current)` is executed on a guest with `reply_voided_at` set, without clearing `reply_voided_at` in the same statement
- **THEN** the statement fails with `ActiveRecord::StatementInvalid` from `participants_voided_is_open_reply`

### Requirement: Participant scopes define who counts
The system SHALL provide scopes: `active` (`left_at IS NULL`), `counting` (`responded_at IS NOT NULL AND declined_at IS NULL AND left_at IS NULL AND reply_voided_at IS NULL`, declared as `where.not(responded_at: nil).where(declined_at: nil, left_at: nil, reply_voided_at: nil)`), `linked` (`token_digest IS NOT NULL`), and `unsent` (guests, active, with no live token). `Participant#counting?` SHALL apply the same four conditions as `counting`. Consensus (`Event#mutually_available_start_times`, whose correlated denominator count and `EXISTS` guard both carry `AND reply_voided_at IS NULL` while the query stays one SQL statement), `ensure_replies!`, invitations and the dashboard MUST use these scopes and this predicate rather than ad hoc conditions, so a guest voided by an offer revision drops out of the consensus denominator and can never block `finalize!`. A guest who keeps at least one slot after a revision SHALL stay in `counting`.

#### Scenario: Counting excludes pending, declined, left and voided guests
- **WHEN** an event has an organizer, a guest who saved slots, a guest who declined, a guest who never replied, a guest who left and a guest with `reply_voided_at` set
- **THEN** `participants.counting` returns exactly the organizer and the guest who saved slots

#### Scenario: The predicate method mirrors the scope
- **WHEN** `counting?` is called on a guest with `reply_voided_at` set and on a guest whose picks were only trimmed by a revision
- **THEN** it returns false for the voided guest and true for the trimmed guest, matching membership in `participants.counting`

#### Scenario: A trimmed guest still counts
- **WHEN** a guest saved 10:00 and 12:00 and an offer revision removed 12:00
- **THEN** the guest has `reply_voided_at` NULL, is in `participants.counting` and is part of the consensus denominator

#### Scenario: Voiding leaves nobody counting
- **WHEN** the only guest who replied is voided by an offer revision and `ensure_replies!` runs
- **THEN** it raises "Wait for at least one reply before confirming" because `participants.counting.guest` is empty

#### Scenario: Consensus excludes a voided guest in one statement
- **WHEN** `mutually_available_start_times` is called on an event where guest A saved 10:00 and guest B has `reply_voided_at` set
- **THEN** it returns `[10:00]`, exactly one query runs, and both the correlated count and the `EXISTS` guard contain `reply_voided_at IS NULL`

#### Scenario: Unsent lists guests that were never given a live link
- **WHEN** an event has a guest with no token digest, a guest with a live token and a guest who left
- **THEN** `participants.unsent` returns only the first guest

### Requirement: Migrations are reversible and match the committed schema
Each migration in `guest-first-foundation` and in this change SHALL define explicit `up` and `down` methods (or use `reversible` blocks), so that this change's three migrations can be rolled back (`db:rollback STEP=3`) and re-applied on an empty database. This change's migrations, all on top of `20260905000001`, SHALL be `20260906000001_add_planning_state_to_events_and_participants.rb` (which adds `participants.reply_voided_at datetime NULL` and the check `participants_voided_is_open_reply`, alongside the `events` columns and checks specified in `event-details`, `offer-revision`, `change-notices` and `event-cancellation`), `20260906000002_revamp_activities_into_plan.rb` and `20260906000003_extend_mail_delivery_kinds.rb`. Check constraints on effectively empty tables SHALL be added validated in one step. `db/schema.rb` SHALL remain the load source, SHALL be regenerated in the build image, and MUST equal the dump produced after running the migrations. The round-trip test `test/migrations/guest_first_foundation_migrations_test.rb` SHALL require the three new migration files and list their classes in `MIGRATIONS` after `DropDeadUserColumns`, SHALL keep `MODELS` covering every model whose table these migrations touch (`Participant`, `MailDelivery`, `TimeSlot`, `Event`, `User`, `Activity`), SHALL truncate every table with cascade before running down (so `20260906000003`'s `down` can re-add the five-kind `mail_deliveries_kind_allowed` check), SHALL run every listed migration down in reverse and then up inside a transaction, SHALL assert the resulting shape with connection introspection only, and SHALL compare the schema dump (via `ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)`) with `db/schema.rb`, normalizing only the trailing newline. The activities `down` backfill SHALL be covered by a separate row-insert test, not by the truncating round-trip test.

#### Scenario: Round trip leaves the schema identical
- **WHEN** the migration round-trip test truncates all tables with cascade, runs every listed migration down in reverse, then up
- **THEN** the schema dump equals `db/schema.rb`, `connection.foreign_keys(:time_slots)` includes the composite participant foreign key, `connection.column_exists?(:participants, :reply_voided_at)` is true and `connection.check_constraints(:participants)` includes `participants_voided_is_open_reply`

#### Scenario: Rolling back restores the legacy shape
- **WHEN** every listed migration is run down in reverse on an empty database
- **THEN** `user_events` exists, `events.user_id` exists and is nullable, `time_slots.user_id` and `time_slots.end_time` exist, and `participants` and `mail_deliveries` do not exist

#### Scenario: Rolling back this change removes the voided-reply mark
- **WHEN** `20260906000001_add_planning_state_to_events_and_participants.rb` is run down on an empty database
- **THEN** `connection.column_exists?(:participants, :reply_voided_at)` is false, `connection.check_constraints(:participants)` has no `participants_voided_is_open_reply`, and running it up restores both

#### Scenario: The kind check round-trips on a truncated ledger
- **WHEN** the round-trip test has truncated `mail_deliveries` and runs `20260906000003_extend_mail_delivery_kinds.rb` down then up
- **THEN** `down` re-adds the five-kind `mail_deliveries_kind_allowed` check without error and `up` re-adds the eight-kind check
