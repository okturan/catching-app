## MODIFIED Requirements

### Requirement: The dashboard lists participations only
`GET /dashboard` SHALL list `current_user.participants.active` as "Organizing" and "Invited" cards showing the event name, the participation state and a link to `my_participation_path`. The Members tab, its badge, `dashboards/shared/_my_friends` and every listing of other users SHALL be removed; no page SHALL enumerate accounts.

The card partial `app/views/dashboards/shared/_my_events.html.erb` SHALL show "cancelled" in the card's state row (`.event-face-state`) for every event whose `cancelled_at` is present, in both the "Organizing" and the "Invited" section. Cancellation SHALL NOT remove a card: `Event#cancel!` deletes nothing and leaves `participants` untouched, so a cancelled event stays listed for every active participation and its card still links to `my_participation_path`. Because Claim (`POST /p/:token/claim`) stays allowed on a cancelled event, a participation claimed after cancellation SHALL appear on the dashboard like any other active participation, with "cancelled" in its state row. Cards of pending and finalized events that are not cancelled SHALL NOT contain "cancelled".

#### Scenario: Dashboard content
- **WHEN** a user organizes one event and is invited to another
- **THEN** the dashboard shows one card under "Organizing" and one under "Invited", each linking to its participation, and contains no other user's name or email

#### Scenario: Left participation is hidden
- **WHEN** a user's claimed guest participation has `left_at` set
- **THEN** it does not appear on the dashboard and `/participations/<id>` returns 404

#### Scenario: Cancelled event under Organizing
- **WHEN** a signed-in organizer cancels their event and opens `/dashboard`
- **THEN** the event's card is still listed under "Organizing", its state row (`.event-face-state`) shows "cancelled", and the card links to `my_participation_path` for the organizer participation

#### Scenario: Cancelled event under Invited
- **WHEN** a claimed guest's event is cancelled and the guest opens `/dashboard`
- **THEN** the event's card is still listed under "Invited", its state row shows "cancelled", and the card links to `my_participation_path` for the guest participation

#### Scenario: Claim after cancellation lands on the dashboard
- **WHEN** a signed-in user opens their guest link on a cancelled event, posts to `/p/:token/claim` and then opens `/dashboard`
- **THEN** the participation appears under "Invited" with "cancelled" in its state row

#### Scenario: Open and finalized events are not marked
- **WHEN** a user's dashboard lists one pending event and one finalized event, neither cancelled
- **THEN** neither card's state row contains "cancelled"

## REMOVED Requirements

### Requirement: Activities are authorized through participations
**Reason**: Replaced by the ADDED `event-plan` capability. The account-only activities surface is deleted — `app/controllers/activities_controller.rb`, `app/views/activities/{index,show,new,_form}.html.erb`, the `resources :activities, only: %i[index show new create]` nesting under `resources :events`, `test/controllers/activities_controller_test.rb` and the session-only "View activities" / "Add an activity" links on the participation page — so `/events/:id/activities*` no longer routes; the plan is edited by the organizer through `Participations::ActivitiesController` and `Participations::ActivityMovesController` under both route families and read by every participant on the participation page.
