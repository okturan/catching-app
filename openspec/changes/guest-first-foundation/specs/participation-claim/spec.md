## ADDED Requirements

### Requirement: An unclaimed participation offers a claim
Any token-family page whose participant has `user_id` NULL SHALL show "Keep this event in your account" linking to `GET /p/:token/claim`. The claim routes SHALL exist only in the token family.

#### Scenario: Claim CTA visibility
- **WHEN** a guest with `user_id` NULL opens their link, and a claimed guest opens theirs
- **THEN** the first page contains the claim link and the second does not

### Requirement: Claiming requires a session and returns after sign-in
`GET /p/:token/claim` and `POST /p/:token/claim` SHALL run `authenticate_user!`. Signed out, Devise SHALL store the claim path and redirect to sign-in; after sign-in or sign-up the user SHALL land on the claim page. Signed in, `GET` SHALL render a one-button confirmation.

#### Scenario: Sign-up returns to the claim page
- **WHEN** a signed-out guest follows the claim link and signs up
- **THEN** the browser ends on `GET /p/:token/claim`

### Requirement: Claiming is a guarded compare-and-set
`POST /p/:token/claim` SHALL run inside `event.with_lock` the statement `Participant.where(id:, user_id: nil, left_at: nil).update_all(user_id: current_user.id, updated_at: Time.current)`. One affected row SHALL redirect to the participation with a success notice; zero rows SHALL re-read the row and answer 422 with "This invitation is already linked to another account" when another user holds it, a no-op notice when the same user holds it, or "This link can no longer be claimed" when the row left; `ActiveRecord::RecordNotUnique` from the one-account-per-event index SHALL answer 422 with "You already take part in this event as <other email>". Binding SHALL be by token possession only; email equality MUST never link a participation.

#### Scenario: Two claimants, one owner
- **WHEN** users A and B both post the claim for the same forwarded link
- **THEN** exactly one of them owns the row and the other receives 422 "This invitation is already linked to another account"

#### Scenario: Left row cannot be claimed
- **WHEN** the guest leaves between the claim GET and POST
- **THEN** the POST answers 422 "This link can no longer be claimed" and `user_id` stays NULL

#### Scenario: Same account twice on one event
- **WHEN** user A already holds a participation on the event and claims a second link on it
- **THEN** the response is 422 naming the other email and the second row stays unclaimed

#### Scenario: Matching email does not auto-claim
- **WHEN** a user whose account email equals a guest's email opens that guest's link signed in
- **THEN** the row remains unclaimed until the claim button is pressed

### Requirement: A claimed participation is memory, not access
After a claim the participation SHALL appear on the user's dashboard and be reachable through `/participations/:id`; the token link SHALL keep working; leaving or a pending-token promotion by someone else SHALL clear the claim as defined in `capability-links`.

#### Scenario: Dashboard shows the claimed row
- **WHEN** a guest claims their participation
- **THEN** the dashboard lists the event under "Invited" with a link to `my_participation_path`
