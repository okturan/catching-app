## ADDED Requirements

### Requirement: The activities table becomes an ordered plan
Migration `20260906000002_revamp_activities_into_plan.rb` (explicit `up`/`down`, on top of `20260905000001`) SHALL: add `activities.position integer NOT NULL DEFAULT 0` and backfill it with `row_number() OVER (PARTITION BY event_id ORDER BY id) - 1`; make `duration` and `description` nullable; drop the check `activities_duration_positive` and add `activities_duration_bounded: duration IS NULL OR (duration > 0 AND duration <= 1440)`; add `activities_position_non_negative: position >= 0`; remove `index_activities_on_event_id` and add an index on `(event_id, position)`; remove the `events` foreign key and re-add it with `on_delete: :cascade`. `down` SHALL run `UPDATE activities SET duration = 1 WHERE duration IS NULL` and `UPDATE activities SET description = 'No description provided' WHERE description IS NULL`, then restore NOT NULL on both columns, the `activities_duration_positive` check, `index_activities_on_event_id` and the plain foreign key, and drop `position`. The migration SHALL be added to `MIGRATIONS` (and `Activity` kept in `MODELS`) in `test/migrations/guest_first_foundation_migrations_test.rb`, `db/schema.rb` SHALL be regenerated, and the `down` backfill SHALL be covered by a row-insert test rather than by the truncating round-trip test.

#### Scenario: Existing rows receive dense positions
- **WHEN** an event has three activity rows with ids 5, 7 and 9 and the migration runs `up`
- **THEN** their positions are 0, 1 and 2 in id order

#### Scenario: The bounded check accepts NULL and refuses out-of-range durations
- **WHEN** `update_columns(duration: nil)` is run on an item, then `update_columns(duration: 0)` and `update_columns(duration: 1441)`
- **THEN** the first succeeds and the other two raise `ActiveRecord::StatementInvalid`

#### Scenario: Deleting an event removes its items at the database level
- **WHEN** an `events` row that has two `activities` rows is deleted with a raw SQL `DELETE`
- **THEN** both `activities` rows are gone

#### Scenario: Rolling back backfills before restoring NOT NULL
- **WHEN** a row with `duration NULL` and `description NULL` exists and the migration runs `down` one step
- **THEN** the row has `duration = 1` and `description = 'No description provided'`, both columns are NOT NULL, the `activities_duration_positive` check and `index_activities_on_event_id` exist, and the `position` column does not

### Requirement: Plan items are validated and bounded
`Activity` SHALL `belongs_to :event`; SHALL normalize `name` with `squish` and require it with at most 80 characters; SHALL normalize `description` with `strip.presence` (blank becomes NULL) and allow at most 500 characters; SHALL validate `duration` with `numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1440 }, allow_nil: true`; SHALL validate `position` with `numericality: { greater_than_or_equal_to: 0 }`; and SHALL refuse the 21st item of an event on create with the error "The plan can have at most 20 items". `test/models/activity_test.rb` SHALL be rewritten to cover the nullable fields, the bounds, the cap and the ordering.

#### Scenario: A name alone is enough
- **WHEN** an item is built with `name: "Pizza"` and no duration or description
- **THEN** it is valid

#### Scenario: Blank description becomes NULL and the name is squished
- **WHEN** an item is saved with `name: "  Pizza   first "` and `description: "   "`
- **THEN** `name` is "Pizza first" and `description` is NULL

#### Scenario: Duration bounds
- **WHEN** items are built with `duration` 0, 1441 and 1440
- **THEN** the first two are invalid on `duration` and the third is valid

#### Scenario: Overlong fields are refused
- **WHEN** an item is built with an 81-character name, or with a 501-character description
- **THEN** it is invalid

#### Scenario: Twenty-first item is refused
- **WHEN** an event already has 20 items and another is created
- **THEN** the save fails with the error "The plan can have at most 20 items" and 20 items remain

### Requirement: The plan is ordered by position, then id
`Event has_many :activities` SHALL be `-> { order(:position, :id) }, dependent: :destroy`. Positions SHALL be non-negative and are not constrained unique at the database; ties SHALL order by `id`. A newly created item SHALL receive `position = (max || -1) + 1`, the highest existing position plus one, or 0 for the first item. Every rendering of the plan (details page, event card, mails, calendar file) SHALL follow `(position, id)` order.

#### Scenario: New item goes to the end
- **WHEN** an event has items at positions 0 and 1 and the organizer adds a third
- **THEN** the new item has position 2

#### Scenario: First item starts at zero
- **WHEN** an item is created on an event with an empty plan
- **THEN** its position is 0

#### Scenario: Ties break by id
- **WHEN** two items share position 3 with ids 12 and 9
- **THEN** `event.activities` yields id 9 before id 12

### Requirement: The plan is edited only by the organizer, through both link families
Routes SHALL be added inside the shared `participation_actions` concern under `scope module: :participations`: `resources :activities, only: %i[create update destroy] do resource :move, only: :create end`, so `POST /p/:token/activities`, `PATCH /p/:token/activities/:id`, `DELETE /p/:token/activities/:id` and `POST /p/:token/activities/:id/move` exist alongside their `/participations/:participation_id/activities…` twins. `test/routing/participation_routes_test.rb` SHALL pin `participation_activity_move_path(TOKEN, 7)` → `/p/<token>/activities/7/move`. `Participations::ActivitiesController` (`create`, `update`, `destroy`) and `Participations::ActivityMovesController` (`create`) SHALL inherit from `ParticipationScopedController`, run `require_organizer!` (a guest answers the uniform 404), resolve the target with `@event.activities.find(params[:id])` (an item of another event answers 404), permit `activity[name]`, `activity[duration]` and `activity[description]`, be allowed while the event is pending or finalized, and be refused on a cancelled event by the base `refuse_closed_writes` (303 to `scoped_path` with the alert "This event was cancelled").

#### Scenario: Organizer adds an item through the token family
- **WHEN** the organizer posts `activity[name]=Pizza` and `activity[duration]=30` to `POST /p/<organizer token>/activities`
- **THEN** an item named "Pizza" with duration 30 exists at the end of the event's plan

#### Scenario: Organizer edits through the session family
- **WHEN** a signed-in organizer sends `PATCH /participations/<id>/activities/<item id>` with `activity[duration]=45`
- **THEN** the item's duration is 45

#### Scenario: Guest token is not found
- **WHEN** a guest token posts to `POST /p/<guest token>/activities`, or sends PATCH, DELETE or move for an existing item
- **THEN** every response is the uniform 404 and the plan is unchanged

#### Scenario: Another event's item is unreachable
- **WHEN** the organizer of event A sends `DELETE /p/<token>/activities/<id of an item of event B>`
- **THEN** the response is 404 and the item still exists

#### Scenario: Finalized event still accepts plan edits
- **WHEN** the organizer of a finalized, not cancelled event posts a new item
- **THEN** the item is created

#### Scenario: Cancelled event refuses plan writes
- **WHEN** the organizer of a cancelled event posts, patches, deletes or moves an item
- **THEN** each response is 303 to the participation page with the alert "This event was cancelled" and the plan is unchanged

### Requirement: Every plan write is locked, bumps the revision and sends no mail
Create, update, destroy and move SHALL run inside `@event.with_lock` and SHALL increment `events.revision` by one in the same transaction. Plan writes SHALL enqueue no mail and create no `mail_deliveries` row; the organizer tells guests afterwards through **Tell the guests** or the details form's `notice[send]` checkbox.

#### Scenario: Revision bumps once per write
- **WHEN** an event at `revision` 3 receives a create, then an update, then a move, then a destroy
- **THEN** `revision` is 7

#### Scenario: No mail on plan writes
- **WHEN** an organizer with two linked guests creates and then removes an item
- **THEN** no mail job is enqueued and `mail_deliveries` has no new row

### Requirement: Moving an item is one POST with a target position
`POST …/activities/:id/move` SHALL take `move[position]`, a target index clamped to `0..size-1`, so any rearrangement is one write. Inside the lock the controller SHALL first renumber the plan densely (0, 1, 2, …) from `(position, id)` order and then place the item at the target index. The **Up** and **Down** buttons SHALL post the item's current index minus one and plus one respectively. A target equal to the item's current index (Up on the first item, Down on the last) SHALL leave the order unchanged.

#### Scenario: Move to the top
- **WHEN** items A, B and C sit at positions 0, 1 and 2 and C is moved with `move[position]=0`
- **THEN** the order is C, A, B with positions 0, 1, 2

#### Scenario: Out-of-range target is clamped
- **WHEN** a plan of three items receives `move[position]=99` for its first item
- **THEN** that item is last at position 2 and no error is raised

#### Scenario: Ties are renumbered before the move
- **WHEN** items with ids 4, 6 and 8 all sit at position 0 and id 4 is moved with `move[position]=1`
- **THEN** the order is id 6, id 4, id 8 with positions exactly 0, 1, 2

#### Scenario: Up on the first item changes nothing
- **WHEN** the first item's **Up** button posts `move[position]=-1`
- **THEN** the target clamps to 0 and the order is unchanged

### Requirement: The organizer edits the plan on the Edit details page
`GET …/details/edit` SHALL render a section "The plan" below the details fields and outside the details `<form>` (the form closes before the plan section; `assert_select "form form", count: 0`). It SHALL list every item in `(position, id)` order with its `name`, its `duration` when set ("45 min") and its one-line `description` when set. Each row SHALL be its own `PATCH …/activities/:id` form with `activity[name]`, an `activity[duration]` select and `activity[description]`, and SHALL carry three `button_to` controls: **Up** (`POST …/activities/:id/move`, `aria-label="Move <name> up"`), **Down** (`aria-label="Move <name> down"`) and **Remove** (`DELETE …/activities/:id`, `aria-label="Remove <name>"`, `turbo_confirm` "Remove <name> from the plan?"). An "Add to the plan" row SHALL post `POST …/activities` with `activity[name]`, `activity[duration]` and `activity[description]`. Once the event is finalized the page SHALL also show the derived timeline and, when the sum of item durations exceeds the confirmed window, the sentence "The plan runs 2 h 30 min; the set time is 2 h." with the actual lengths.

#### Scenario: Editor controls are labelled and forms never nest
- **WHEN** the organizer opens the edit page of an event whose plan has "Pizza" and "Dune"
- **THEN** the page has buttons with `aria-label` "Move Pizza up", "Move Pizza down" and "Remove Pizza", a Remove form whose confirm text is "Remove Pizza from the plan?", one PATCH form per item, an "Add to the plan" form posting to the activities route, and no `form` nested inside another `form`

#### Scenario: Plan longer than the window
- **WHEN** a finalized event's window is 2 h and its items total 2 h 30 min
- **THEN** the details page contains "The plan runs 2 h 30 min; the set time is 2 h."

#### Scenario: Plan within the window
- **WHEN** a finalized event's window is 2 h and its items total 1 h 30 min
- **THEN** the details page contains no "The plan runs" sentence

#### Scenario: Organizer builds a plan and a guest reads it in order
- **WHEN** the organizer adds "Pizza first" then "The movie", moves "The movie" up, and a guest opens their link
- **THEN** the guest's event card lists "The movie" before "Pizza first"

### Requirement: Every participant reads the plan on the event card
When the event has at least one item, the event card's facts block (`<dl class="event-facts">`) SHALL contain a **Plan** row (`dt` "Plan") whose `dd` is an ordered list in `(position, id)` order; each entry SHALL read "<name> · <duration>" when a duration is set ("Pizza · 30 min", "Dune · 2 h 35 min") and the name alone otherwise, with the description as a muted second line when set. The row SHALL render for every participant of the event, guest or organizer, through `/p/:token` and `/participations/:id`, server-side with nothing to tap and no JavaScript. It SHALL NOT render when the plan is empty, and items SHALL be visible to nobody outside the event (the base controller's uniform 404).

#### Scenario: Token guest sees the plan in order
- **WHEN** a guest opens `/p/<token>` on an event whose items are "Pizza" (30 min, position 0) and "Dune" (155 min, position 1)
- **THEN** the facts block has a "Plan" row whose list reads "Pizza · 30 min" then "Dune · 2 h 35 min"

#### Scenario: Description as a second line
- **WHEN** an item has the description "Margherita and a veggie one"
- **THEN** the description renders as a muted line under that item's name

#### Scenario: Empty plan renders no row
- **WHEN** an event has no items
- **THEN** the facts block has no "Plan" row

### Requirement: Derived starts appear once the time is set
Derived starts SHALL be computed at request time and never stored. When `status?` is true, the event is not cancelled and every item preceding an item has a `duration`, that item SHALL carry its start `start_time + Σ durations of the preceding items`, rendered server-side in the event zone as `<time datetime="<iso8601>" data-zoned-instant class="time">20:00 (Europe/Berlin)</time>`. An item without a `duration` SHALL break the chain: the items after it show no time. `time_slot_show.js` SHALL rewrite every `[data-zoned-instant]` into the picker zone on load and on zone change, the same path that fills `#final-window-local`, through a pure exported helper `zonedLabel(iso, zone)` covered by `node --test`.

#### Scenario: Complete chain on a finalized event
- **WHEN** a Europe/Berlin event is set for 20:00–23:00 with items "Pizza" (30 min) then "Dune" (155 min)
- **THEN** each item carries a `time.time[data-zoned-instant]` whose `datetime` is the ISO 8601 instant of 20:00 Europe/Berlin for "Pizza" and 20:30 Europe/Berlin for "Dune", with text "20:00 (Europe/Berlin)" and "20:30 (Europe/Berlin)"

#### Scenario: Viewer zone rewrite
- **WHEN** a guest whose picker zone is Asia/Kolkata opens that page on a January date
- **THEN** "Pizza" reads "00:30 (Asia/Kolkata)"

#### Scenario: Missing duration breaks the chain
- **WHEN** a finalized event's items are "Arrive" (no duration), "Pizza" (30 min) and "Dune" (155 min)
- **THEN** "Arrive" carries the event's start time and neither "Pizza" nor "Dune" carries a `time` element

#### Scenario: No times while pending or cancelled
- **WHEN** the same plan is viewed on a pending event, or on a finalized event that was cancelled
- **THEN** no item carries a `time[data-zoned-instant]`

#### Scenario: Pure helper formats in two zones
- **WHEN** `zonedLabel("2030-01-15T19:00:00Z", "Europe/Berlin")` and `zonedLabel("2030-01-15T19:00:00Z", "Asia/Kolkata")` run under `node --test`
- **THEN** they return "20:00 (Europe/Berlin)" and "00:30 (Asia/Kolkata)"

### Requirement: Plan text reaches mail only through mail_safe
No plan `description` SHALL appear in any mail body, subject or attachment. Where a mail lists the plan — `event_updated` (names and durations), `finalized` (names, durations and, when the chain is complete, derived starts in the recipient zone and the event zone) and the mail-mode calendar file's `DESCRIPTION` — every item name SHALL pass through `MailTextHelper#mail_safe`, so no URL from organizer input reaches a guest's inbox. The page-mode calendar file SHALL carry the plan as `DESCRIPTION` lines "1. Pizza (30 min)".

#### Scenario: A URL in an item name is stripped in mail
- **WHEN** an item is named "Watch https://evil.example/movie" and an `event_updated` mail is rendered
- **THEN** both parts list the item without `://`

#### Scenario: Descriptions stay on the page
- **WHEN** an item has a description and the `finalized` and `event_updated` mails are rendered
- **THEN** neither part of either mail contains the description text

### Requirement: The account-only activities surface is removed
The nesting `resources :activities, only: %i[index show new create]` under `resources :events` SHALL be removed, so `/events/:event_id/activities`, `/events/:event_id/activities/new` and `/events/:event_id/activities/:id` no longer route. `app/controllers/activities_controller.rb`, `app/views/activities/{index,show,new,_form}.html.erb`, `test/controllers/activities_controller_test.rb` and the `.container-cards` and `.card__container .card` rules in `app/assets/stylesheets/components/_cards.scss` SHALL be deleted; the session-only "View activities" and "Add an activity" links SHALL be removed from `app/views/participations/show.html.erb`; and the `assert_select "a[href=?]", event_activities_path(@event)` assertion SHALL be removed from `test/controllers/participations_controller_test.rb`. `test/routing/participation_routes_test.rb` SHALL assert that `/events/1/activities` does not route.

#### Scenario: Old routes are gone
- **WHEN** a signed-in user requests `GET /events/1/activities`
- **THEN** the router raises a routing error (no route matches) and no controller is reached

#### Scenario: Session page has no activities links
- **WHEN** a signed-in organizer opens `/participations/<id>`
- **THEN** the page has no "View activities" or "Add an activity" link and no `/events/<id>/activities` href

### Requirement: Seeds and fixtures describe a plan
`db/seeds.rb` SHALL replace the Movies/Gaming/Karaoke activities with a two-item plan on the seeded event: "Pizza first" with `duration: 30` at position 0 and "The movie" with `duration: 120` at position 1. Fixture `planning_activity` in `test/fixtures/activities.yml` SHALL gain `position: 0`.

#### Scenario: Development seeds
- **WHEN** `bin/rails db:seed` runs in development on an empty database
- **THEN** the "Movie night" event has exactly two activities: "Pizza first" (30 min, position 0) and "The movie" (120 min, position 1)

#### Scenario: Fixture has a position
- **WHEN** fixtures load
- **THEN** `activities(:planning_activity).position` is 0
