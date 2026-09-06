## MODIFIED Requirements

### Requirement: Two route families resolve one identity
The system SHALL expose a token family under `scope "p/:token", constraints: { token: %r{[^/]+} }, format: false` and a session family under `scope "participations/:participation_id", as: :my`. Both SHALL mount the same singular `resource :participation` (`show`, `update`, `destroy`) and the same shared `participation_actions` concern on shared controllers under `scope module: :participations`; the claim action exists only in the token family. The concern SHALL contain exactly these nested actions:

```ruby
concern :participation_actions do
  scope module: :participations do
    resource  :decline,      only: :create
    resource  :finalization, only: :create
    resources :invitations,  only: :create
    resources :participants, only: :destroy do
      resource :resend,      only: :create
      resource :link_reveal, only: :create
    end
    resource  :details,      only: %i[edit update]
    resource  :offer,        only: %i[edit update]
    resource  :notice,       only: :create
    resource  :cancellation, only: :create
    resource  :reopening,    only: :create
    resource  :calendar,     only: :show, path: "calendar.ics", format: false
    resources :activities,   only: %i[create update destroy] do
      resource :move, only: :create
    end
  end
end
```

so that `/p/:token/details/edit`, `/p/:token/details`, `/p/:token/offer/edit`, `/p/:token/offer`, `/p/:token/notice`, `/p/:token/cancellation`, `/p/:token/reopening`, `/p/:token/calendar.ics`, `/p/:token/activities`, `/p/:token/activities/:id` and `/p/:token/activities/:activity_id/move` each have a `/participations/:participation_id/…` twin. The new actions SHALL be served by `Participations::DetailsController` (`edit`, `update`), `Participations::OffersController` (`edit`, `update`), `Participations::NoticesController` (`create`), `Participations::CancellationsController` (`create`), `Participations::ReopeningsController` (`create`), `Participations::CalendarsController` (`show`), `Participations::ActivitiesController` (`create`, `update`, `destroy`) and `Participations::ActivityMovesController` (`create`), every one a `ParticipationScopedController` subclass. The account-only nesting `resources :activities, only: %i[index show new create]` under `resources :events` and `app/controllers/activities_controller.rb` SHALL be removed, so `/events/:id/activities*` no longer routes.

Family detection and the `authenticate_user!` skip MUST key on `request.path_parameters` (`:token` present), never on `params`. In the session family the participant SHALL be `current_user.participants.active.find(params[:participation_id])`. Route helpers `participation_*_path(token, ...)` and `my_participation_*_path(participant, ...)` SHALL exist for every nested action, and `ParticipationScopedController#scoped_path(name = nil, *args, edit: false)` SHALL build `participation_<name>_path` or `my_participation_<name>_path` for the current family, prefixed with `edit_` when `edit: true` (so `scoped_path(:details, edit: true)` yields `edit_participation_details_path(token)` or `edit_my_participation_details_path(participant)`). `test/routing/participation_routes_test.rb` SHALL pin each helper, its controller and action, and the viewer parameter for both families, including `edit_participation_details_path(TOKEN)` → `/p/<token>/details/edit`, `participation_offer_path(TOKEN)` → `/p/<token>/offer`, `participation_notice_path(TOKEN)` → `/p/<token>/notice`, `participation_cancellation_path(TOKEN)` → `/p/<token>/cancellation`, `participation_reopening_path(TOKEN)` → `/p/<token>/reopening`, `participation_calendar_path(TOKEN)` → `/p/<token>/calendar.ics`, `participation_activity_move_path(TOKEN, 7)` → `/p/<token>/activities/7/move`, their `my_participation_*` twins, and SHALL assert that `/events/1/activities` no longer routes.

#### Scenario: Query token does not bypass sign-in on the session family
- **WHEN** a signed-out client requests `GET /participations/1?token=<valid token>`
- **THEN** the response redirects to the sign-in page

#### Scenario: Token family ignores a participation_id query
- **WHEN** a client requests `GET /p/<token>?participation_id=1`
- **THEN** the page for the token's participant is rendered

#### Scenario: Session family requires sign-in for writes
- **WHEN** a signed-out client sends PATCH or DELETE to `/participations/1`
- **THEN** the response redirects to the sign-in page and nothing changes

#### Scenario: Another account's participation is not found
- **WHEN** user A requests `/participations/<id of B's participation>`
- **THEN** the response is 404

#### Scenario: Every organizer action routes in both families
- **WHEN** the routing test resolves `GET …/details/edit`, `PATCH …/details`, `GET …/offer/edit`, `PATCH …/offer`, `POST …/notice`, `POST …/cancellation`, `POST …/reopening`, `POST …/activities`, `PATCH …/activities/7`, `DELETE …/activities/7` and `POST …/activities/7/move` under both `/p/<token>` and `/participations/3`
- **THEN** each maps to `participations/details`, `participations/offers`, `participations/notices`, `participations/cancellations`, `participations/reopenings`, `participations/activities` or `participations/activity_moves` with the expected action, carrying `token` in the first family and `participation_id` in the second, and `my_participation_claim_path` still raises `NoMethodError`

#### Scenario: The calendar route is a fixed `.ics` path in both families
- **WHEN** the routing test resolves `GET /p/<token>/calendar.ics` and `GET /participations/3/calendar.ics`
- **THEN** both map to `participations/calendars#show` with no `format` parameter, and `participation_calendar_path(TOKEN)` returns `/p/<token>/calendar.ics`

#### Scenario: The move route nests under an activity
- **WHEN** `participation_activity_move_path(TOKEN, 7)` is built and `POST /p/<token>/activities/7/move` is recognized
- **THEN** the helper returns `/p/<token>/activities/7/move` and the request maps to `participations/activity_moves#create` with `activity_id: "7"`

#### Scenario: scoped_path builds the edit helper for the current family
- **WHEN** a controller calls `scoped_path(:details, edit: true)` during a token request and during a session request
- **THEN** the token request yields `/p/<canonical token>/details/edit` and the session request yields `/participations/<id>/details/edit`

#### Scenario: The account-only activities routes are gone
- **WHEN** `Rails.application.routes.recognize_path` is called for `GET /events/1/activities`, `GET /events/1/activities/new` and `POST /events/1/activities`
- **THEN** each raises `ActionController::RoutingError` and no `ActivitiesController` outside `Participations::` is defined

### Requirement: Role and state gates answer 404, never 403
Guest-only actions (availability update `PATCH …`, decline `POST …/decline`, leave `DELETE …`) SHALL respond 404 to an organizer token through `require_guest!`. Organizer-only actions SHALL respond 404 to a guest token through `require_organizer!`: finalization, invitations, resend, link reveal, remove, details (`edit` and `update`), offer (`edit` and `update`), notice, cancellation, reopening, activities (`create`, `update`, `destroy`) and activity move. Every such 404 SHALL render the uniform not-found page. The calendar file (`GET …/calendar.ics`) SHALL be available to any participant of the event — guest or organizer, in either family — and SHALL raise `ActiveRecord::RecordNotFound` (the same uniform 404) unless `@event.status?`.

Invitations, resend, link reveal and notice SHALL additionally require `link_opened_at` on the organizer (`require_opened_organizer!`) and otherwise respond with a 303 redirect to `scoped_path` and an explanatory alert. Details, plan items, offer, cancellation, reopening and calendar SHALL NOT require `link_opened_at`.

Nested guest targets (`params[:id]` for remove, `params[:participant_id]` for resend and link reveal) SHALL be resolved only through `@participant.event.guests.active`, so the organizer row and rows of other events are unreachable; nested plan targets (`params[:id]` for activity `update` and `destroy`, `params[:activity_id]` for move) SHALL be resolved only through `@event.activities`, so items of other events are unreachable. Every unreachable target SHALL answer the uniform 404.

State gates SHALL be 303 redirects with a message, never 404 and never 403. `ParticipationScopedController#viewer_role` SHALL be `@event.open? ? @participant.role : "viewer"`. The base controller SHALL run `before_action :refuse_closed_writes, unless: -> { request.get? }`, which, when `@event.cancelled?`, redirects 303 to `scoped_path` with the alert "This event was cancelled"; it SHALL be skipped only for `ParticipationsController#destroy` (Leave) and `Participations::ClaimsController` (Claim). The base controller SHALL `rescue_from Event::ClosedError`, answering 303 to `scoped_path` with the exception message as the alert, so no subclass needs its own rescue. Every GET in both families SHALL keep working on a finalized or cancelled event for every valid token.

#### Scenario: Organizer token cannot respond as a guest
- **WHEN** an organizer token sends PATCH availability, POST decline or DELETE leave
- **THEN** each response is 404 and the organizer's offer rows are unchanged

#### Scenario: Guest token cannot manage the event
- **WHEN** a guest token sends POST finalization, POST invitations, POST resend, POST link_reveal, DELETE a participant, GET `…/details/edit`, PATCH `…/details`, GET `…/offer/edit`, PATCH `…/offer`, POST `…/notice`, POST `…/cancellation`, POST `…/reopening`, POST `…/activities`, PATCH or DELETE `…/activities/:id`, or POST `…/activities/:id/move`, in either family
- **THEN** each response is 404 rendering the uniform not-found page and no row changes

#### Scenario: Remove with a foreign id is not found
- **WHEN** an organizer sends DELETE participants with the id of a guest from another event, or with their own id
- **THEN** the response is 404 and no row is deleted

#### Scenario: Plan item of another event is not found
- **WHEN** the organizer of event A sends PATCH, DELETE or POST move for the id of a plan item belonging to event B
- **THEN** the response is 404 and the item is unchanged

#### Scenario: The calendar file is open to any participant of a finalized event
- **WHEN** a guest token, the organizer token and a signed-in claimed guest each request `…/calendar.ics` on a finalized event
- **THEN** each response is 200 with the same file; and when the same requests are made on a pending event each response is 404 with a body byte-identical to the bad-link page

#### Scenario: Tell the guests needs an opened organizer link
- **WHEN** an organizer whose `link_opened_at` is NULL sends `POST …/notice`
- **THEN** the response is 303 to the organizer page with an explanatory alert and no mail is enqueued

#### Scenario: Details, offer, cancel, reopen and calendar do not need an opened link
- **WHEN** an organizer whose `link_opened_at` is NULL requests `GET …/details/edit`, `GET …/offer/edit`, `GET …/calendar.ics` on a finalized event, or sends `POST …/cancellation`
- **THEN** none of the responses is a 303 caused by the missing `link_opened_at`

#### Scenario: Cancelled event answers writes with 303, not 404
- **WHEN** the organizer of a cancelled event posts to invitations, resend, link_reveal, participants#destroy, finalization, details, offer, notice, activities, activity move, reopening or cancellation in either family
- **THEN** each response is 303 to `scoped_path` with the alert "This event was cancelled", no row changes, and a following GET of the participation page returns 200

#### Scenario: Leave and Claim bypass the closed-writes gate
- **WHEN** a guest of a cancelled event sends `DELETE /p/<token>` and, separately, a signed-in user posts `POST /p/<token>/claim`
- **THEN** neither request is answered with "This event was cancelled"; the leave sets `left_at` and the claim sets `user_id`

#### Scenario: ClosedError is rescued once at the base
- **WHEN** an organizer sends `POST …/finalization` on an already finalized event through a controller that defines no `rescue_from` of its own
- **THEN** the response is 303 to the participation page with the alert "Availability is closed for this event"

#### Scenario: Viewer role follows the open state
- **WHEN** the organizer opens an open event, a finalized event and a cancelled event
- **THEN** `#time-grid-show` carries `data-role="organizer"` on the open event and `data-role="viewer"` on the other two

### Requirement: Failure pages are friendly and uniform
Unknown, expired, revoked, retired (replaced by a newer pending token), left and malformed tokens, every role-gate refusal, every unreachable nested target and the calendar file of a non-finalized event SHALL render one identical 404 page (`participations/not_found`, reached through the base `rescue_from ActiveRecord::RecordNotFound`). The page SHALL keep the heading "This link is not valid." and a link to the organizer-link recovery form (`new_organizer_link_path`), and its guest copy SHALL read exactly "This link is not valid. Open the newest email about this event: a newer link replaces older ones, or ask the organizer to resend your invitation." — no other guest sentence; the page SHALL not say whether the token ever existed. `allow_browser` SHALL use the grid's real floor (`safari: 15.4, chrome: 99, firefox: 93, opera: 85, ie: false`) and an explicit block that renders an `errors/unsupported_browser` view with the application layout and status 406, telling invited guests to reply to the invitation email.

#### Scenario: Left, revoked, retired and unknown tokens are indistinguishable
- **WHEN** GET is made with a left guest's old token, with a revoked token, with a pending token retired by a later mail, and with a random well-formed token
- **THEN** all four responses are 404 with byte-identical bodies except the CSRF meta tags

#### Scenario: The guest copy points at the newest email
- **WHEN** a guest opens a pending link from an earlier mail after a newer token-carrying mail was sent
- **THEN** the response is 404 and the body contains "Open the newest email about this event: a newer link replaces older ones, or ask the organizer to resend your invitation." together with the link to the organizer-link recovery form

#### Scenario: Role-gate and calendar refusals are the same page
- **WHEN** a guest token requests `GET …/details/edit` and a participant requests `…/calendar.ics` on a pending event
- **THEN** both responses are 404 with bodies byte-identical to the unknown-token page except the CSRF meta tags

#### Scenario: Unsupported browser gets a real page
- **WHEN** a request carries a Safari 14 user agent
- **THEN** the response is 406 and the body contains the unsupported-browser message rendered in the layout

### Requirement: Pending tokens replace links without breaking the working one
`issue_pending_token!` SHALL store a new digest in `pending_token_digest` and leave `token_digest` and `user_id` unchanged. For guests the pending token SHALL NOT expire; for organizer recovery tokens `pending_token_expires_at` SHALL be 24 hours after issue. A GET request with a pending token SHALL resolve the participant and MUST NOT change any digest or `user_id`. The first non-GET request authenticated by a pending token SHALL promote it in one guarded statement (`WHERE pending_token_digest = digest`): `token_digest` becomes the pending digest, the pending columns are cleared, and `user_id` is cleared unless the request is signed in as that user. Until promotion both the old live token and the pending token SHALL work.

Newer links SHALL replace older ones. Every mail that carries a link to an unclaimed guest — the invitation Resend, `finalized`, `event_updated` and `reopened` — SHALL issue a fresh pending token with `issue_pending_token!` and pass the raw token to the mailer, so the previous pending token (if any) is retired and answers the not-found page while the live token from the invitation keeps working. A claimed guest (`user_id` set) SHALL receive no token; the mailer SHALL link `my_participation_url(participant)` instead. The organizer's copies SHALL carry no token, and the `cancelled` mail SHALL issue no token and carry no link. A test SHALL pin that a pending link from an earlier mail answers 404 after a notice.

#### Scenario: Scanner opening a pending link changes nothing
- **WHEN** a pending token is issued and a GET is made with it, then a GET is made with the previous live token
- **THEN** both GETs return 200 and `token_digest`, `pending_token_digest` and `user_id` are unchanged

#### Scenario: First write with a pending token promotes it
- **WHEN** a PATCH is made with a pending guest token
- **THEN** `token_digest` equals the pending digest, `pending_token_digest` and `pending_token_expires_at` are NULL, and a subsequent GET with the old live token returns 404

#### Scenario: Promotion by the claiming account keeps the claim
- **WHEN** the participant is claimed by user U and a PATCH with the pending token is made while signed in as U
- **THEN** `user_id` remains U

#### Scenario: Promotion by anyone else clears the claim
- **WHEN** the participant is claimed by user U and a PATCH with the pending token is made signed out
- **THEN** `user_id` is NULL afterwards

#### Scenario: Expired organizer recovery token is refused
- **WHEN** a request is made with an organizer pending token whose `pending_token_expires_at` is in the past
- **THEN** the response is the friendly 404 page

#### Scenario: A newer mail retires the previous pending link
- **WHEN** an unclaimed guest holds an unused pending token from a Resend and then receives an `event_updated`, `finalized` or `reopened` mail
- **THEN** the new body carries `/p/<new pending token>`, a GET with the new token returns 200 and changes no digest, a GET with the earlier pending token returns the 404 page with the newest-email copy, and a GET with the live invitation token still returns 200

#### Scenario: Claimed guests and the organizer get no pending token
- **WHEN** `finalized`, `event_updated` or `reopened` reaches a claimed guest, and `finalized` or `cancelled` reaches the organizer
- **THEN** no digest of either participant changes, the claimed guest's body links `/participations/<id>` and contains no `/p/` URL, and the organizer's body contains neither a `/p/` nor a `/participations/` URL

#### Scenario: The cancelled mail issues nothing
- **WHEN** `Deliveries.cancelled!` runs for an event with unclaimed linked guests
- **THEN** every guest's `token_digest` and `pending_token_digest` are unchanged and no body carries a link
