## ADDED Requirements

### Requirement: The calendar file is a hand-rolled RFC 5545 document
`app/services/calendar_file.rb` SHALL be pure Ruby with no new gem or npm dependency and SHALL expose `CalendarFile.new(event, mode:, window: nil)` with `mode: :page | :mail`. Its output SHALL use CRLF line endings on every line; a content line longer than 75 octets SHALL be folded at 75 octets into a CRLF followed by a single space, never splitting a UTF-8 multi-byte sequence, so that unfolding (removing every CRLF-plus-space) restores the original line; text values SHALL escape backslash as `\\`, semicolon as `\;`, comma as `\,` and a newline as `\n`. The writer SHALL be covered by `test/services/calendar_file_test.rb`.

#### Scenario: CRLF everywhere
- **WHEN** a file is rendered in either mode
- **THEN** every line ends with `\r\n` and no bare `\n` occurs anywhere in the body

#### Scenario: A long description folds and round-trips
- **WHEN** a 300-character description is rendered into `DESCRIPTION`
- **THEN** no physical line exceeds 75 octets, every continuation line begins with a single space, and unfolding the body yields the original property line

#### Scenario: Reserved characters are escaped
- **WHEN** an event is named `Pizza, then; the \ movie` and its page-mode description contains a newline
- **THEN** `SUMMARY` reads `Pizza\, then\; the \\ movie` and the newline appears in `DESCRIPTION` as the two characters `\n`

#### Scenario: An emoji name is not split mid-sequence
- **WHEN** an event name containing emoji pushes the `SUMMARY` line past 75 octets
- **THEN** the fold falls on a character boundary and the unfolded, decoded value contains every emoji intact

### Requirement: The file carries a fixed property set and a 15-minute alarm
Every file SHALL contain `BEGIN:VCALENDAR`, `VERSION:2.0`, `PRODID:-//Catching App//EN`, `METHOD:PUBLISH` and exactly one `VEVENT` with: `UID`, `DTSTAMP` (the render time in UTC), `SEQUENCE`, `DTSTART` and `DTEND` (the window in UTC `Z` form, with no `VTIMEZONE` component and no zone name anywhere in the file), `SUMMARY:<name>`, `LOCATION:<place>` only when `place` is set, `STATUS`, `DESCRIPTION` (the plan as numbered lines such as `1. Pizza (30 min)` followed by `Planned with Catching App`), and one `VALARM` with `ACTION:DISPLAY`, `DESCRIPTION:<name>` and `TRIGGER:-PT15M`. The file SHALL NOT contain an `ORGANIZER` property in either mode. `DTSTART`/`DTEND` SHALL equal the window passed by the caller, or `events.start_time`/`events.end_time` when none is passed, so the file never states a zone name and calendar apps render it in the viewer's zone.

#### Scenario: Required properties are present
- **WHEN** a finalized event with a place and a two-item plan is rendered
- **THEN** the body contains `BEGIN:VCALENDAR`, `VERSION:2.0`, `PRODID:-//Catching App//EN`, `METHOD:PUBLISH`, one `BEGIN:VEVENT`, `UID`, `DTSTAMP`, `SEQUENCE`, `DTSTART`, `DTEND`, `SUMMARY`, `LOCATION`, `STATUS`, `DESCRIPTION` containing `1. Pizza (30 min)` and `Planned with Catching App`, and one `BEGIN:VALARM` block with `ACTION:DISPLAY`, `DESCRIPTION` equal to the event name and `TRIGGER:-PT15M`

#### Scenario: The window is written in UTC with no zone
- **WHEN** a Europe/Berlin event is finalized for 2030-01-15 10:00–11:00 UTC
- **THEN** the body contains `DTSTART:20300115T100000Z` and `DTEND:20300115T110000Z` and contains neither `VTIMEZONE`, `TZID` nor `Europe/Berlin`

#### Scenario: No place means no LOCATION
- **WHEN** an event whose `place` is NULL is rendered
- **THEN** the body contains no `LOCATION` property

#### Scenario: No ORGANIZER in either mode
- **WHEN** a file is rendered in page mode and in mail mode
- **THEN** neither body contains an `ORGANIZER` property nor the organizer's email address

### Requirement: The UID is stable and SEQUENCE is the event revision
The `VEVENT` `UID` SHALL be `<sha256("#{id}:#{created_at.to_i}")[0,32]>@<host>` where `host` is `Rails.application.config.action_mailer.default_url_options[:host]`; it SHALL be identical across every render for the life of the event and SHALL NOT be sequential across events. `SEQUENCE` SHALL equal `events.revision`, which is bumped inside the same locked transaction by every write that changes what a guest or a calendar entry would see (details, plan items, offer revision, finalize, reopen, cancel), so a later file always supersedes an earlier one.

#### Scenario: UID survives edits and cancellation
- **WHEN** the same event is rendered before a details edit, after it, and after `cancel!`
- **THEN** all three bodies carry the same `UID`, whose local part is the first 32 hex characters of `sha256("#{id}:#{created_at.to_i}")` and whose domain is the mailer host

#### Scenario: SEQUENCE follows revision
- **WHEN** an event with `revision` 3 is rendered, then `update_details!` changes its name and it is rendered again
- **THEN** the first body contains `SEQUENCE:3` and the second `SEQUENCE:4`

#### Scenario: Later files outrank earlier ones
- **WHEN** an event is finalized, reopened and finalized again
- **THEN** the `SEQUENCE` of the three files produced (confirmed, cancelled, confirmed) strictly increases

### Requirement: STATUS reflects cancellation and withdrawal
The `VEVENT` SHALL carry `STATUS:CONFIRMED` for a finalized, not cancelled event, and `STATUS:CANCELLED` when `events.cancelled_at` is set or when the caller passes a withdrawn window (the `reopened` mail). A cancelled or withdrawn file SHALL keep the same `UID` and carry the bumped `SEQUENCE` so a re-import clears the entry from the calendar.

#### Scenario: Confirmed while set
- **WHEN** a finalized event that is not cancelled is rendered
- **THEN** the body contains `STATUS:CONFIRMED`

#### Scenario: Cancelled event
- **WHEN** a finalized event is cancelled and rendered
- **THEN** the body contains `STATUS:CANCELLED`, the `UID` is unchanged and `SEQUENCE` equals the post-cancel `revision`

#### Scenario: Withdrawn window after reopen
- **WHEN** `reopen!` returns the withdrawn window and the file is built from it for the `reopened` mail
- **THEN** the body contains `STATUS:CANCELLED`, `DTSTART`/`DTEND` of the withdrawn window and `SEQUENCE` equal to the post-reopen `revision`

#### Scenario: Re-finalize publishes a confirmed file at the next SEQUENCE
- **WHEN** a reopened event is finalized again
- **THEN** the new file carries `STATUS:CONFIRMED` with a `SEQUENCE` greater than the withdrawn file's

### Requirement: Page mode and mail mode expose different data
Page mode SHALL add `URL:<place_url>` when `place_url` is set and SHALL place the event description as the first `DESCRIPTION` paragraph before the plan lines. Mail mode SHALL pass `name`, `place` and every plan name through `MailTextHelper#mail_safe`, SHALL omit `URL` and the event description, SHALL contain no `://` and no `/p/` URL, and SHALL be at most 8 KB (8192 bytes). Neither mode SHALL contain a capability token. Plan descriptions SHALL NOT appear in mail mode.

#### Scenario: Mail mode carries no link
- **WHEN** an event named `Pizza night http://evil.example` with `place_url` `https://zoom.us/j/1` and a description containing `https://evil.example` is rendered in mail mode
- **THEN** the body contains no `://`, no `URL` property and no `DESCRIPTION` paragraph from the event description, and `SUMMARY` reads `Pizza night evil.example`

#### Scenario: Page mode carries the join link and the description
- **WHEN** the same event is rendered in page mode
- **THEN** the body contains `URL:https://zoom.us/j/1` and `DESCRIPTION` begins with the event description followed by the plan lines and `Planned with Catching App`

#### Scenario: No URL without a place link
- **WHEN** an event whose `place_url` is NULL is rendered in page mode
- **THEN** the body contains no `URL` property

#### Scenario: Mail-mode file is capped at 8 KB
- **WHEN** an event with a maximal name, a 200-character place and 20 plan items with 80-character names is rendered in mail mode
- **THEN** `body.bytesize` is at most 8192

#### Scenario: No capability token in either mode
- **WHEN** a file is rendered in page mode and in mail mode for a guest with a live token
- **THEN** neither body contains that token nor any `/p/` path

### Requirement: The download route exists in both families
The `participation_actions` concern in `config/routes.rb` SHALL contain `resource :calendar, only: :show, path: "calendar.ics", format: false`, so `GET /p/:token/calendar.ics` and `GET /participations/:participation_id/calendar.ics` both reach `Participations::CalendarsController#show`; `participation_calendar_path(TOKEN)` SHALL resolve to `/p/<token>/calendar.ics` and `test/routing/participation_routes_test.rb` SHALL pin both families. The action SHALL be available to any participant of the event, SHALL render page mode, and SHALL answer with `send_data body, type: "text/calendar; charset=utf-8", disposition: "attachment", filename: "#{@event.name.parameterize.presence || 'event'}.ics"`; `Cache-Control: no-store` SHALL come from the base controller's `after_action`.

#### Scenario: Token family download
- **WHEN** a guest of a finalized event set for 2030-01-15 10:00 UTC requests `GET /p/<token>/calendar.ics`
- **THEN** the response is 200 with `Content-Type` `text/calendar; charset=utf-8`, `Content-Disposition` `attachment` with a parameterized `.ics` filename, `Cache-Control: no-store`, and a body containing `DTSTART:20300115T100000Z`

#### Scenario: Session family download
- **WHEN** a signed-in claimed guest requests `GET /participations/<id>/calendar.ics` for the same event
- **THEN** the response carries the same headers and body as the token family

#### Scenario: Filename is the parameterized name with a fallback
- **WHEN** the event is named `Pizza & Movie Night`
- **THEN** the filename is `pizza-movie-night.ics`; and when the name parameterizes to an empty string the filename is `event.ics`

#### Scenario: Organizer downloads too
- **WHEN** the organizer requests `GET /p/<organizer token>/calendar.ics` on a finalized event
- **THEN** the response is 200 with the same file a guest receives

### Requirement: The download is refused as a uniform 404 outside a finalized event
`Participations::CalendarsController#show` SHALL raise `ActiveRecord::RecordNotFound` unless `@event.status?`, producing the uniform friendly 404 that is byte-identical to the bad-link page; a token or participation that does not belong to the caller's event SHALL likewise 404. The file therefore exists only for a finalized event, only to a participant of that event, and contains only data that participant can already see on the page. After `reopen!` the route SHALL answer 404 until the next finalize; a cancelled pending event SHALL answer 404; a cancelled finalized event SHALL answer 200 with `STATUS:CANCELLED`, the same `UID` and the bumped `SEQUENCE`.

#### Scenario: Pending event
- **WHEN** a participant requests the calendar file of an event whose `status` is false
- **THEN** the response is 404 and its body is byte-identical to the bad-link page

#### Scenario: Another event's token
- **WHEN** a request carries a token of a different event
- **THEN** the response is 404 and no data of the finalized event appears

#### Scenario: After reopen
- **WHEN** a finalized event is reopened and a participant requests the calendar file
- **THEN** the response is 404 until the event is finalized again

#### Scenario: Cancelled finalized event
- **WHEN** a finalized event is cancelled and a participant requests the calendar file
- **THEN** the response is 200 and the body contains `STATUS:CANCELLED` with the event's unchanged `UID` and `SEQUENCE` equal to the post-cancel `revision`

#### Scenario: Cancelled pending event
- **WHEN** a pending event is cancelled and a participant requests the calendar file
- **THEN** the response is 404

### Requirement: The finalized page offers Add to calendar
On a finalized event the participation page in both families SHALL show the heading with the "Set in stone" plate, the window in the event zone (server-rendered) and the picker zone (client-rendered), the facts block (where, link, how long, plan with derived starts), and a plate button **Add to calendar** linking to `scoped_path(:calendar)`. The organizer SHALL see the same button after finalization; finalizing SHALL need no new action.

#### Scenario: Guest sees the button in the token family
- **WHEN** a guest opens `/p/<token>` on a finalized event
- **THEN** the page contains a plate button "Add to calendar" whose `href` is `/p/<token>/calendar.ics`

#### Scenario: Claimed guest sees the button in the session family
- **WHEN** a signed-in claimed guest opens `/participations/<id>` on a finalized event
- **THEN** the "Add to calendar" button's `href` is `/participations/<id>/calendar.ics`

#### Scenario: Organizer sees the same button
- **WHEN** the organizer opens the event after finalizing
- **THEN** the page contains the "Add to calendar" plate button linking to the organizer's `scoped_path(:calendar)`

### Requirement: The finalized mail states the facts, the plan and a link
`ParticipantMailer#finalized` (templates `finalized.{html,text}.erb`) SHALL keep its subject and SHALL add to the body "Where: <mail_safe(place)>" when `place` is set, "How long: <duration>" when `duration_minutes` is set, and the plan (names through `mail_safe`, never descriptions) with derived starts in both the recipient zone and the event zone when every preceding item has a duration. `place_url` SHALL NOT appear in the body, subject or attachment. A guest's body SHALL carry a link: for an unclaimed guest `Deliveries.finalized!` SHALL issue a fresh never-expiring pending token through `issue_pending_token!`, retiring the previous pending token while the invitation's live token keeps working, and pass `token:` so the link is `/p/<pending token>` (a GET with it changes no digest); for a claimed guest it SHALL pass no token and the mailer SHALL link `my_participation_url(participant)`; the organizer's copy SHALL carry no link and no token and SHALL read "Open your organizer link". The former closing sentence SHALL be replaced by exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels.", and the body SHALL end with the standing sentence "To stop hearing about this event, open your link and choose Leave this event."

#### Scenario: Facts in the body, join link absent
- **WHEN** a finalized event has `place` "Ege's place", `place_url` `https://maps.example/x` and `duration_minutes` 90
- **THEN** both parts contain "Where: Ege's place" and "How long: 1 h 30 min" and contain neither `maps.example` nor any `://` other than the participation link

#### Scenario: Plan with derived starts in both zones
- **WHEN** the plan is "Pizza" (30 min) then "The movie" and the recipient's zone differs from the event zone
- **THEN** the body lists both items with the start of each item in the recipient zone and the event zone

#### Scenario: Unclaimed guest gets a pending link
- **WHEN** `finalized` is sent to an unclaimed guest
- **THEN** both parts contain `/p/<pending token>`, the token is a never-expiring pending token, the guest's previous pending link answers 404 afterwards and the invitation's live link still works

#### Scenario: Claimed guest gets the account link
- **WHEN** `finalized` is sent to a claimed guest
- **THEN** both parts contain `/participations/<id>` and no `/p/` token

#### Scenario: Organizer copy carries no link
- **WHEN** `finalized` is sent to the organizer
- **THEN** the body contains no `/p/` and no `/participations/` link and reads "Open your organizer link"

#### Scenario: Closing sentences
- **WHEN** any `finalized` mail renders
- **THEN** the body contains exactly "You will hear from us again only if the organizer changes the plan, reopens the time or cancels." and not "This is the last message about this event."

#### Scenario: Ledger rows unchanged
- **WHEN** an event with an organizer, two invited guests and one unsent guest is finalized in `test/controllers/participations/finalizations_controller_test.rb`
- **THEN** exactly three `finalized` ledger rows exist

### Requirement: Mail attachments are built from window params, not the row
`Deliveries.finalized!` SHALL iterate `participants.active.linked` and pass `window: [start_time, end_time]` in the mailer params; `ParticipantMailer#finalized` and its attached `CalendarFile` SHALL build from those params and never from the event row, so a job retried after `reopen!` still renders. The attachment SHALL be named `catching-app.ics` with `mime_type: "text/calendar; method=PUBLISH"`, rendered in mail mode with `STATUS:CONFIRMED` and `SEQUENCE` equal to `revision`. The `reopened` mail SHALL attach a `STATUS:CANCELLED` file built from its `previous_window:` params; the `cancelled` mail SHALL attach a `STATUS:CANCELLED` file built from the previous window params only when a window existed, and a cancel after reopen is a pending cancel with no window and no attachment. `finalized` SHALL stay exempt from every cap and MAY be sent up to three times per event (the initial finalize plus two reopenings); `events.notified_revision` SHALL be set to `revision` after the batch.

#### Scenario: Attachment decodes to a valid file
- **WHEN** a `finalized` mail is rendered
- **THEN** it has one attachment `catching-app.ics` with MIME type `text/calendar; method=PUBLISH` whose decoded body begins with `BEGIN:VCALENDAR`, contains `DTSTART` of the passed window, `STATUS:CONFIRMED`, `SEQUENCE:<revision>` and no `://`

#### Scenario: Retry after reopen still renders
- **WHEN** a `finalized` job enqueued with `window:` params runs after `reopen!` has cleared `start_time` and `end_time`
- **THEN** the mail and its attachment render the window from the params without error

#### Scenario: Workflow carries the attachment
- **WHEN** `test/integration/event_scheduling_workflow_test.rb` finalizes an event
- **THEN** each `finalized` mail carries the `catching-app.ics` attachment

#### Scenario: Three finalized batches at most
- **WHEN** an event runs finalize, reopen, finalize, reopen, finalize with a recipient already at every invitation cap
- **THEN** three `finalized` batches are enqueued, none refused by a cap, and `notified_revision` equals `revision` after each

#### Scenario: Cancel after reopen has no attachment
- **WHEN** a reopened (pending) event is cancelled
- **THEN** the `cancelled` mail carries no attachment

### Requirement: The finalize summary compares the window with the planned length
`#time-grid-show` SHALL carry `data-duration-minutes` from `events.duration_minutes`, and `summary()` in `app/javascript/lib/paint.js` SHALL accept `durationMinutes` and render the selected window with its length followed by the planned length, such as "Tue 10 Feb 20:00–21:00 (1 h) · planned 1 h 30 min", adding "shorter than planned" when the selection is shorter. This is a warning in the action bar, never a refusal: `finalize!` SHALL NOT read `duration_minutes`. The helper SHALL be pure and covered by `node --test`.

#### Scenario: Planned length is shown
- **WHEN** `summary()` runs with a 60-minute selection and `durationMinutes: 90`
- **THEN** the text contains "(1 h)" and "planned 1 h 30 min"

#### Scenario: Shorter selection warns
- **WHEN** `summary()` runs with a 60-minute selection and `durationMinutes: 90`
- **THEN** the text contains "shorter than planned"

#### Scenario: Equal or longer selection does not warn
- **WHEN** `summary()` runs with a 90-minute selection and `durationMinutes: 90`
- **THEN** the text contains "planned 1 h 30 min" and not "shorter than planned"

#### Scenario: A shorter window still finalizes
- **WHEN** the organizer finalizes a 60-minute consensus window on an event planned for 90 minutes
- **THEN** the response is 303 with "Meeting time confirmed." and `status` is true
