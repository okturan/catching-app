## ADDED Requirements

### Requirement: Events carry a slot length and a planning time zone
`events.slot_minutes` SHALL be an integer, NOT NULL, default 30, with a database check `IN (15, 30, 60)` and a model inclusion validation. `events.time_zone` SHALL be a string, NOT NULL, default `UTC`, validated with `ActiveSupport::TimeZone[value].present?`. Both SHALL be immutable once any guest has `responded_at` set.

#### Scenario: Invalid slot length is refused at both layers
- **WHEN** an event is saved with `slot_minutes: 45`
- **THEN** validation fails, and `update_columns(slot_minutes: 45)` fails with a check-constraint violation

#### Scenario: Granularity is frozen after the first reply
- **WHEN** a guest has responded and the event's `slot_minutes` is changed from 30 to 60
- **THEN** validation fails on `slot_minutes`

### Requirement: The parser scales its caps with the slot length
`TimeSlotParser.call(value, slot_minutes:)` SHALL accept at most `31 * 25 * (60 / slot_minutes)` instants (775, 1550, 3100), keep the 31-day span rule, reject any instant earlier than 24 hours before now with "Select time slots from today onward", and keep the existing messages "Select at least one time slot", "Time slots must use ISO 8601 timestamps" and "Time slots must fit within a 31-day window".

#### Scenario: Cap at 15 minutes
- **WHEN** 3101 instants are submitted with `slot_minutes: 15`
- **THEN** the parser raises "Select no more than 3100 time slots"

#### Scenario: Past instant is refused
- **WHEN** an instant two days in the past is submitted
- **THEN** the parser raises "Select time slots from today onward"

### Requirement: Instants must sit on the event grid anchored at local midnight
`Event#ensure_aligned!` SHALL require, for every instant `t`, that `(t - t.in_time_zone(time_zone).beginning_of_day) % slot_length` is zero, with message "Select time slots on the event's <slot_minutes>-minute grid". A nonexistent local midnight (spring-forward gap at 00:00) SHALL resolve forward as Rails does, matching the JavaScript generator. A database check SHALL require `time_slots.start_time = date_bin('15 minutes', start_time, '2000-01-01')` as the granularity-independent floor.

#### Scenario: Half-hour offsets align at 60 minutes
- **WHEN** an `Asia/Kolkata` event with 60-minute slots receives instants at 18:30Z and 19:30Z
- **THEN** alignment passes

#### Scenario: Off-grid instant is refused
- **WHEN** a 60-minute event receives 10:15 local
- **THEN** alignment fails with "Select time slots on the event's 60-minute grid"

#### Scenario: Midnight-gap day aligns like the grid
- **WHEN** an `America/Santiago` event receives instants generated from the day whose midnight does not exist
- **THEN** alignment passes for every instant the grid would draw

#### Scenario: Database rejects a non-quarter-hour instant
- **WHEN** `insert_all!` writes a slot at 10:07:30
- **THEN** the statement fails with a check-constraint violation

### Requirement: Contiguity and the finalized window derive from the slot length
`ensure_contiguous!` SHALL require consecutive selected instants to differ by exactly `slot_length`; `finalize!` SHALL set `end_time = max + slot_length`; the database check `events_finalized_window_whole_slots` SHALL require `(end_time - start_time)` to be a multiple of `slot_minutes` minutes when `status` is true.

#### Scenario: Contiguity at 15 minutes
- **WHEN** a 15-minute event finalizes 10:00, 10:15, 10:30
- **THEN** `end_time` is 10:45

#### Scenario: Hourly gap on a 15-minute event is discontinuous
- **WHEN** a 15-minute event finalizes 10:00 and 11:00
- **THEN** finalize raises "Select one continuous meeting window"

### Requirement: The grid steps by the event slot length
Both grid roots SHALL carry `data-slot-minutes` and `data-time-zone`; `localDaySlots(day, slotMinutes)` SHALL generate rows from local midnight to the next local midnight in exact-duration steps; labels SHALL be `HH:mm` with an offset suffix on repeated wall clocks; row height SHALL follow `[data-slot-minutes]` on coarse pointers (44/36/28 px for 60/30/15).

#### Scenario: Tirane day counts at each step
- **WHEN** `localDaySlots` runs for Europe/Tirane on a spring-forward, normal and fall-back day
- **THEN** it yields 92/96/100 instants at 15, 46/48/50 at 30 and 23/24/25 at 60, all unique

### Requirement: The definer rescales a selection when the step changes
When the organizer changes `event[slot_minutes]` the definer SHALL expand each painted slot into its sub-cells on refinement and, on coarsening, keep a cell if any of its sub-cells was painted; instants outside the date range SHALL be dropped and the summary SHALL report moves and drops.

#### Scenario: Refine 60 to 30
- **WHEN** 10:00 is painted at 60 minutes and the step changes to 30
- **THEN** 10:00 and 10:30 are painted

#### Scenario: Coarsen 30 to 60
- **WHEN** only 10:30 is painted at 30 minutes and the step changes to 60
- **THEN** 10:00 is painted

### Requirement: Fixtures pin the hourly baseline
Event fixtures SHALL declare `slot_minutes: 60` and `time_zone: UTC` so every existing hour-aligned assertion keeps its meaning, and the form default SHALL remain 30.

#### Scenario: Form default is 30
- **WHEN** `GET /events/new` renders
- **THEN** the `event[slot_minutes]` control has 30 selected
