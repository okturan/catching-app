## ADDED Requirements

### Requirement: Events carry a place, a place link and a planned length
Migration `20260906000001_add_planning_state_to_events_and_participants.rb` (explicit `up`/`down`, on top of `20260905000001`, listed in `MIGRATIONS` of the migration round-trip test) SHALL add to `events` the nullable columns `place string`, `place_url string` and `duration_minutes integer`, plus the check constraints `events_place_url_scheme` (`place_url IS NULL OR place_url ~ '^[Hh][Tt][Tt][Pp][Ss]?://'`, a locale-free ASCII class as in `participants_email_normalized`) and `events_duration_minutes_quarter_hour` (`duration_minutes IS NULL OR (duration_minutes > 0 AND duration_minutes <= 1440 AND duration_minutes % 15 = 0)`), both added validated in one step. The model SHALL declare `normalizes :place, with: -> { _1.squish.presence }` and `validates :place, length: { maximum: 200 }`. `slot_minutes` and `time_zone` MUST NOT be changed by any details write.

#### Scenario: Migration round-trips
- **WHEN** the migration is applied and rolled back in the round-trip test
- **THEN** `events` gains and then loses `place`, `place_url`, `duration_minutes` and the two checks, and `db/schema.rb` is unchanged after `db:migrate` in the build image

#### Scenario: Place is squished and blank becomes NULL
- **WHEN** an event is saved with `place: "  Ege's   place, Kadıköy "` and another with `place: "   "`
- **THEN** the first stores `"Ege's place, Kadıköy"` and the second stores NULL

#### Scenario: Oversized place is refused
- **WHEN** an event is saved with a 201-character `place`
- **THEN** validation fails on `place` and nothing is written

### Requirement: The place link is an absolute http(s) URL at both layers
`events.place_url` SHALL be NULL or an absolute `http`/`https` URL with a host and no userinfo, at the model and at the database. The model SHALL declare `normalizes :place_url` that strips the value and downcases the scheme portion only (a blank value becomes NULL), and SHALL validate that `URI.parse` succeeds, the scheme is `http` or `https`, `host` is present, `userinfo` is nil and the length is at most 2000, otherwise adding the error "must be a web address starting with http:// or https://". The database check `events_place_url_scheme` SHALL be the second guard.

#### Scenario: Scheme is downcased, the rest kept
- **WHEN** `place_url` is assigned `"HTTPS://X"`
- **THEN** it normalizes to `"https://X"` and the event is valid

#### Scenario: Non-web schemes are refused by the model
- **WHEN** `place_url` is assigned `"javascript:alert(1)"` or `"ftp://files.example"`
- **THEN** validation fails with "must be a web address starting with http:// or https://" and nothing is written

#### Scenario: Userinfo is refused
- **WHEN** `place_url` is assigned `"https://user@evil.example"`
- **THEN** validation fails with "must be a web address starting with http:// or https://"

#### Scenario: The database refuses what the model missed
- **WHEN** `event.update_columns(place_url: "javascript:x")` bypasses validation
- **THEN** PostgreSQL raises `ActiveRecord::StatementInvalid` from `events_place_url_scheme` and the row is unchanged

### Requirement: The planned length is a whole number of slots and only a hint
`events.duration_minutes` SHALL be NULL or an integer that is `> 0`, `<= 1440` (error "must be at most 24 hours") and a whole multiple of the event's `slot_minutes` (error "must be a whole number of #{slot_minutes}-minute slots"). The database check `events_duration_minutes_quarter_hour` SHALL enforce the multiple of 15 so that a pre-reply step change is caught by the model, never by the constraint. `duration_minutes` SHALL be a hint for painting and finalizing and MUST NOT be read by `finalize!`.

#### Scenario: Forty-five minutes depends on the slot length
- **WHEN** `duration_minutes: 45` is saved on a 30-minute event and on a 15-minute event
- **THEN** the 30-minute event fails with "must be a whole number of 30-minute slots" and the 15-minute event saves

#### Scenario: More than a day is refused
- **WHEN** `duration_minutes: 1441` is saved
- **THEN** validation fails with "must be at most 24 hours"

#### Scenario: A shorter window still finalizes
- **WHEN** an event with `duration_minutes: 90` is finalized on a contiguous 60-minute consensus run
- **THEN** `finalize!` succeeds and `duration_minutes` stays 90

### Requirement: The new-event form offers place, link and planned length
`app/views/events/new.html.erb` SHALL render, after `event[description]`: `event[place]` (text, `maxlength="200"`, placeholder "Ege's place, Kadıköy — or 'Zoom'"), `event[place_url]` (`type="url"`, placeholder "Link to join or a map link") and `event[duration_minutes]` as `select#event_duration_minutes` whose options are "Not set", then every multiple of the event's `slot_minutes` up to 240, then 300, 360, 480, 720 and 1440, labelled in the "1 h 30 min" form. All three SHALL be optional. `EventsController#event_params` SHALL permit `place`, `place_url` and `duration_minutes`; `Event.plan!` SHALL pass them through; the 422 re-render (`Event.new(event_params)`) SHALL echo the posted values.

#### Scenario: Creation persists the three fields
- **WHEN** `POST /events` is sent with a valid plan plus `event[place]=Ege's place`, `event[place_url]=https://zoom.us/j/1`, `event[duration_minutes]=90`
- **THEN** the created event has `place` "Ege's place", `place_url` "https://zoom.us/j/1" and `duration_minutes` 90

#### Scenario: A 422 echoes the three fields
- **WHEN** `POST /events` fails validation with the three fields present
- **THEN** the re-rendered form contains the posted place, place link and a selected `#event_duration_minutes` option

#### Scenario: Options follow the slot length
- **WHEN** `GET /events/new` renders with the default 30-minute step
- **THEN** `#event_duration_minutes` offers "Not set", every multiple of 15 up to 240, then 300, 360, 480, 720 and 1440, with every option that is not a multiple of 30 rendered `disabled`

### Requirement: Duration options follow a step change without inline script
`app/javascript/components/time_slot_definer.js` SHALL, in its step-change handler, disable every `#event_duration_minutes` option whose value is not a multiple of the new step and reset the select to "Not set" when the selected option became invalid; no inline script is used (CSP). The decision SHALL live in a pure helper `allowedDurations(stepMinutes, options)` exported for `node --test`; the DOM behaviour is covered in Selenium.

#### Scenario: Pure helper decides which options survive
- **WHEN** `allowedDurations(60, [30, 60, 90, 120, 1440])` runs under `node --test`
- **THEN** it returns the options that are multiples of 60 as allowed and the others as disallowed

#### Scenario: Step change resets an invalid selection
- **WHEN** 90 is selected in `#event_duration_minutes` and the organizer changes `#event_slot_minutes` to 60
- **THEN** the 90 option is disabled and the select shows "Not set"

### Requirement: Details are edited on an organizer-only page in both route families
The `participation_actions` concern SHALL gain `resource :details, only: %i[edit update]` under `scope module: :participations`, so `GET /p/:token/details/edit`, `PATCH /p/:token/details`, `GET /participations/:participation_id/details/edit` and `PATCH /participations/:participation_id/details` all route to `Participations::DetailsController` (`edit`, `update`). `edit_participation_details_path(TOKEN)` SHALL equal `/p/<token>/details/edit`; `edit_my_participation_details_path` SHALL exist. `ParticipationScopedController#scoped_path(name = nil, *args, edit: false)` SHALL prefix the helper with `edit_` when `edit: true`. Both actions SHALL run `require_organizer!` (404 for a guest token, rendering the uniform not-found page). The organizer page SHALL show a `plate-button-sm` **Edit details** linking to `scoped_path(:details, edit: true)` in both families while the event is pending or finalized and not cancelled.

#### Scenario: Both families route the details page
- **WHEN** the routing test resolves `GET /p/<token>/details/edit`, `PATCH /p/<token>/details`, `GET /participations/3/details/edit` and `PATCH /participations/3/details`
- **THEN** each maps to `participations/details` with `edit` or `update`, and `edit_participation_details_path(TOKEN)` returns `/p/<token>/details/edit`

#### Scenario: A guest token gets a uniform 404
- **WHEN** a guest token requests `GET …/details/edit` or sends `PATCH …/details`
- **THEN** the response is 404 with the "This link is not valid" page and the event is unchanged

#### Scenario: The organizer page links to Edit details
- **WHEN** an organizer opens a pending event and, separately, a finalized event through either family
- **THEN** each page contains an `a.plate-button-sm` "Edit details" whose `href` is the details edit path of that family

#### Scenario: No Edit details on a cancelled event
- **WHEN** an organizer opens a cancelled event
- **THEN** the page contains no link to the details edit path

### Requirement: The edit page is one white face with facts, fields and no nested forms
`GET …/details/edit` SHALL render one white face `width: min(440px, 100%)` (the Devise/lost-link pattern: fields and actions share one face) containing a `form_with` PATCH to `scoped_path(:details)` with `event[name]`, `event[description]`, `event[place]`, `event[place_url]` and `event[duration_minutes]`; `slot_minutes` and `time_zone` SHALL be printed as facts in the form "30-minute slots · Europe/Berlin" and MUST NOT be rendered as fields. `Participations::DetailsController#details_params` SHALL permit exactly `name description place place_url duration_minutes`. The details `<form>` SHALL close before the plan section (`event-plan`); the face is a layout container holding the details form and then the plan editor with its own per-row forms, so `assert_select "form form", count: 0` holds. When `@participant.link_opened_at` is present and at least one active linked guest exists, the details form SHALL include a checkbox `notice[send]` labelled "Email the guests about this change", unchecked while pending and checked once finalized; otherwise the checkbox is absent. The page has no zone picker, so every instant it renders SHALL be in the event zone with the zone name.

#### Scenario: Fields are rendered, step and zone are facts
- **WHEN** an organizer opens `GET …/details/edit` on a 30-minute Europe/Berlin event
- **THEN** the page contains inputs named `event[name]`, `event[description]`, `event[place]`, `event[place_url]` and `event[duration_minutes]`, the text "30-minute slots · Europe/Berlin", and no element named `event[slot_minutes]` or `event[time_zone]`

#### Scenario: No nested forms
- **WHEN** the details edit page renders for an event with two plan items
- **THEN** `assert_select "form form", count: 0` passes and the plan editor's forms are siblings of the details form inside the same face

#### Scenario: Posted step and zone are ignored
- **WHEN** an organizer sends `PATCH …/details` with `event[slot_minutes]=15` and `event[time_zone]=Asia/Kolkata` alongside a new name
- **THEN** the name is saved and `slot_minutes` and `time_zone` are unchanged

#### Scenario: Notice checkbox appears only with an opened link and a linked guest
- **WHEN** the organizer has `link_opened_at` set and one active guest holds a live token
- **THEN** the details form contains `notice[send]`, unchecked on a pending event and checked on a finalized one

#### Scenario: Notice checkbox absent before the link is opened
- **WHEN** the organizer's `link_opened_at` is NULL
- **THEN** the details form contains no `notice[send]` input

### Requirement: `update_details!` is one locked save that bumps the revision once
`Event#update_details!(attributes)` SHALL run inside `with_lock`: `ensure_not_cancelled!` (raising `ClosedError, "This event was cancelled"`), `assign_attributes`, and, when `changed?` intersects `name description place place_url duration_minutes`, `self.revision += 1`, followed by exactly one `save!`. It SHALL return the change set (attribute → `[old, new]`) excluding `revision` and `updated_at`. A save that changes nothing SHALL bump nothing and return an empty set. Details writes MUST NOT touch `time_slots`, `participants`, `slot_minutes`, `time_zone`, `status`, `start_time` or `end_time`; they SHALL be allowed on a finalized event and refused on a cancelled one.

#### Scenario: One bump per changed save
- **WHEN** `update_details!(place: "Ege's place", duration_minutes: 90)` runs on an event at `revision` 3
- **THEN** `revision` is 4, the return value has keys `place` and `duration_minutes` only, and one `save!` occurred

#### Scenario: A no-op bumps nothing
- **WHEN** `update_details!(name: event.name)` runs with the current name
- **THEN** `revision` is unchanged, the return value is empty and `updated_at` is unchanged

#### Scenario: Cancelled events refuse details
- **WHEN** `update_details!(name: "New name")` runs on an event with `cancelled_at` set
- **THEN** `Event::ClosedError` is raised with "This event was cancelled" and nothing is written

#### Scenario: Finalized events accept details
- **WHEN** `update_details!(place: "Zoom")` runs on a finalized event
- **THEN** it saves, `revision` increases by one and `status`, `start_time` and `end_time` are unchanged

#### Scenario: Slots and participants are untouched
- **WHEN** `update_details!` renames an event with offered slots and replied guests
- **THEN** every `time_slots` and `participants` row is byte-identical afterwards

### Requirement: Saving details redirects with a summary and tells the guests only when asked
`PATCH …/details` SHALL call `Event#update_details!(details_params)` and redirect 303 to `scoped_path` with the notice "Details saved.". When `notice[send]` is "1" and the change set is non-empty, the controller SHALL call `Deliveries.event_updated!(event:, organizer: @participant, request_ip:, reason: :details, changes:)` after commit (see `change-notices`) and append " N guests emailed." and, when skipped > 0, " M skipped (recently notified). Try again after 10 minutes."; when the organizer's `link_opened_at` is NULL the `ArgumentError` "Open your organizer link before emailing guests" SHALL be rescued into the same 303 hint. A validation failure SHALL re-render the edit face with status 422, `@event.errors` on the fields and base errors rendered explicitly as in `events/new.html.erb`. On a cancelled event both `GET …/details/edit` and `PATCH …/details` SHALL answer 303 to `scoped_path` with the alert "This event was cancelled".

#### Scenario: Save and redirect
- **WHEN** an organizer sends `PATCH …/details` with a new `event[place]` through either family
- **THEN** the response is 303 to that family's participation page with "Details saved." and the place is persisted

#### Scenario: Invalid link re-renders with 422
- **WHEN** an organizer sends `PATCH …/details` with `event[place_url]=ftp://files.example`
- **THEN** the response is 422, the edit face shows "must be a web address starting with http:// or https://" and `place_url` is unchanged

#### Scenario: Ticking the box emails the guests
- **WHEN** an organizer with an opened link changes the place with `notice[send]=1` on an event with two active linked guests
- **THEN** one `event_updated` mail with `reason: :details` and `changes` containing `place` is enqueued per guest and the flash reads "Details saved. 2 guests emailed."

#### Scenario: A no-op with the box ticked sends nothing
- **WHEN** an organizer submits unchanged details with `notice[send]=1`
- **THEN** no `event_updated` row is created, `revision` is unchanged and the flash is "Details saved."

#### Scenario: Cancelled event refuses edit and update
- **WHEN** an organizer requests `GET …/details/edit` or sends `PATCH …/details` on a cancelled event
- **THEN** the response is 303 to the participation page with the alert "This event was cancelled" and nothing is written

### Requirement: The guest card answers where and how long in a facts block
The `.event-panel` on the participation page SHALL render `<dl class="event-facts">` under the heading (under the confirmed window once finalized) with `dt` in the form-label style (body face, weight 600, never plate caps) and `dd` in body type; no plate labels a row (the Heavy Heading Rule). Rows SHALL render only when set: **Where** → `place` as text and, when `place_url` is set, an anchor produced by `EventsHelper#place_link(event)` (`tag.a` on the model-validated, DB-checked value) whose visible text is the URL host (e.g. `zoom.us`), with `rel="noopener noreferrer nofollow"`, `target="_blank"`, class `quiet-link` and a visually hidden "(opens in a new tab)"; **How long** → `duration_minutes` in the zone-free form "1 h 30 min" (hours as "N h", remaining minutes as "N min", a zero part omitted: "2 h", "45 min"); **Plan** → the ordered plan of `event-plan`. The block SHALL be absent when none of place, link, length or plan is set. The existing "Time to be confirmed by <organizer>" line SHALL stay while pending. The block needs no JavaScript and adds no tap, and the 400 px card MUST NOT make a 412 px viewport scroll horizontally. If `bin/brakeman` warns on the anchor, a justified `config/brakeman.ignore` entry SHALL name the two guards.

#### Scenario: Nothing set, no block
- **WHEN** a guest opens an event with no place, link, length or plan
- **THEN** the page contains no `dl.event-facts`

#### Scenario: Where row with a link
- **WHEN** an event has `place` "Ege's place" and `place_url` "https://zoom.us/j/1"
- **THEN** the Where `dd` contains the text "Ege's place" and an `a.quiet-link[target=_blank][rel="noopener noreferrer nofollow"]` whose visible text is "zoom.us", followed by a visually hidden "(opens in a new tab)", and the full URL appears only in that anchor's `href`

#### Scenario: How long is zone-free
- **WHEN** an event has `duration_minutes` 90 and a guest views it from Asia/Kolkata
- **THEN** the How long `dd` reads "1 h 30 min" with no zone name

#### Scenario: Labels are not plates
- **WHEN** the facts block renders
- **THEN** no `dt` inside `dl.event-facts` carries the `plate` class and the block contains no `.plate`

#### Scenario: Facts fit the phone card
- **WHEN** the mobile system test renders a guest page whose event has a long place, a link and a plan on a 412 px viewport
- **THEN** `document.documentElement.scrollWidth` is at most `window.innerWidth`

### Requirement: Every date on a capability page is zoned and named
Every server-rendered instant on a capability page (participation page, details page and their notices) SHALL be a `<time datetime="<iso8601>" data-zoned-instant class="time">` element rendered in the event zone with the zone name, e.g. `20:00 (Europe/Berlin)`. On pages with a zone picker, `app/javascript/components/time_slot_show.js` SHALL rewrite every `[data-zoned-instant]` into the picker zone on load and on zone change, through the same path that fills `#final-window-local`. Pages without a picker (the details edit page) SHALL stay in the event zone, named.

#### Scenario: A facts-block instant follows the picker
- **WHEN** a finalized event in Europe/Berlin renders a derived plan start of 20:00 in the facts block and the guest's picker is Asia/Kolkata
- **THEN** the server markup is `<time datetime="…" data-zoned-instant class="time">20:00 (Europe/Berlin)</time>` and after load the element reads "00:30 (Asia/Kolkata)"

#### Scenario: The details page stays in the event zone
- **WHEN** the organizer opens the details edit page of a finalized Europe/Berlin event whose plan renders a derived timeline
- **THEN** every `[data-zoned-instant]` on the page shows the event-zone time with "(Europe/Berlin)" and the page contains no zone picker

### Requirement: The place link and the name never leak beyond capability pages
`place_url` SHALL be rendered only as the anchor on capability pages and as `URL` in the page-mode calendar file (`calendar-file`); it MUST NOT appear in any mail body, subject or attachment. `place` and `name` SHALL reach mail only through `MailTextHelper#mail_safe`, and `name` only after `normalizes :name` (squish), so a renamed event cannot inject headers. A participation that does not belong to the requester SHALL answer the uniform 404 page, which contains no event data.

#### Scenario: Finalized mail carries the place, not the link
- **WHEN** the `finalized` mail renders for an event with `place` "Ege's place" and `place_url` "https://zoom.us/j/1"
- **THEN** both parts contain "Where: Ege's place", neither contains "zoom.us/j/1", and the only `://` is the participation link

#### Scenario: Another account's participation leaks nothing
- **WHEN** a signed-in user requests `GET /participations/:id` for a participation that is not theirs on an event with `place_url` set
- **THEN** the response is the 404 "This link is not valid" page and the body does not contain the `place_url`

#### Scenario: A renamed event cannot inject headers
- **WHEN** details rename the event to "Dinner\r\nBcc: victim@example.com" and a mail is later rendered
- **THEN** the stored name is squished to one line and the subject contains no header break
