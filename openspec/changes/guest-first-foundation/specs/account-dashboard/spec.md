## ADDED Requirements

### Requirement: Sign-in lands on the dashboard or the stored location
`after_sign_in_path_for` SHALL return `stored_location_for(resource) || dashboard_path`.

#### Scenario: Plain sign-in
- **WHEN** a user signs in without a stored location
- **THEN** the browser is redirected to `/dashboard`

### Requirement: The dashboard lists participations only
`GET /dashboard` SHALL list `current_user.participants.active` as "Organizing" and "Invited" cards showing the event name, the participation state and a link to `my_participation_path`. The Members tab, its badge, `dashboards/shared/_my_friends` and every listing of other users SHALL be removed; no page SHALL enumerate accounts.

#### Scenario: Dashboard content
- **WHEN** a user organizes one event and is invited to another
- **THEN** the dashboard shows one card under "Organizing" and one under "Invited", each linking to its participation, and contains no other user's name or email

#### Scenario: Left participation is hidden
- **WHEN** a user's claimed guest participation has `left_at` set
- **THEN** it does not appear on the dashboard and `/participations/<id>` returns 404

### Requirement: The session family renders the same pages
`/participations/:id` and its nested actions SHALL render the same templates and perform the same writes as the token family for the participant `current_user.participants.active.find(id)`, with the single difference that the organizer's `link_opened_at` is never set through this family.

#### Scenario: One write through the session family
- **WHEN** a claimed guest saves availability through `PATCH /participations/:id`
- **THEN** the slots are replaced exactly as through the token family and the notice is "Availability saved."

### Requirement: Signed-in organizers get the same organizer flow
A signed-in user who plans an event SHALL get a claimed organizer participant, receive the `organizer_link` mail, and be able to send invitations only after opening that link.

#### Scenario: Signed-in plan is claimed and mailed
- **WHEN** a signed-in user plans an event
- **THEN** the organizer participant has `user_id` = the user, one `organizer_link` mail is enqueued, and the dashboard lists the event under "Organizing"

### Requirement: Activities are authorized through participations
`ActivitiesController` SHALL scope index and show with `Event.for_user(current_user)` (any active participation) and new and create with `Event.organized_by(current_user)`; the "Add activity" control SHALL render only when the current user holds the organizer participation; "Back to event" SHALL link to `my_participation_path`.

#### Scenario: Invited account can view, not add
- **WHEN** a user with a claimed guest participation requests the activities index and then posts a new activity
- **THEN** the index renders 200 without the "Add activity" control and the post responds 404

#### Scenario: Unrelated account is not found
- **WHEN** a user with no participation on the event requests its activities index
- **THEN** the response is 404

### Requirement: Deleting an account never deletes other people's events
Devise account deletion SHALL nullify `participants.user_id` and leave events, participants, slots and ledger rows intact.

#### Scenario: Organizer deletes account mid-plan
- **WHEN** a signed-in organizer with two responded guests deletes their account
- **THEN** the event still exists, the guests' links still work, and the organizer link still works with `user_id` NULL
