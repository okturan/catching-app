## ADDED Requirements

### Requirement: Tokens are high-entropy and stored only as digests
The system SHALL generate capability tokens with `SecureRandom.base58(32)` and store only the hex SHA-256 digest in `participants.token_digest` (live) or `participants.pending_token_digest` (pending). The raw token SHALL exist only in memory for the current request, in mail job arguments, and in the mail body. Digest columns MUST be unique and MUST be exactly 64 characters when present (database check). Issuing any token for a participant with `left_at` set MUST raise.

#### Scenario: Issuing a live token stores a digest
- **WHEN** `issue_live_token!` is called on a guest participant
- **THEN** the return value matches `/\A[A-Za-z0-9]{32}\z/`, `token_digest` equals its SHA-256 hex digest, and the raw value is stored nowhere

#### Scenario: Issuing a token for a left participant raises
- **WHEN** `issue_live_token!` or `issue_pending_token!` is called on a participant with `left_at` set
- **THEN** an error is raised and no digest changes

### Requirement: Token resolution is format-checked, digest-based and canonicalizing
`Participant.find_by_token(raw)` SHALL return nil without querying when `raw` does not match the token format after stripping trailing non-base58 characters. It SHALL look up the digest in `token_digest` or in `pending_token_digest` (only when `pending_token_expires_at` is NULL or in the future). When the request path carried trailing characters that were stripped and the token resolves, the controller SHALL redirect with 303 to the canonical path.

#### Scenario: Malformed token runs zero queries
- **WHEN** `find_by_token("short")` is called
- **THEN** it returns nil and no SQL is executed

#### Scenario: Link mangled by a mail client is canonicalized
- **WHEN** a guest opens `/p/<token>.` or `/p/<token>)`
- **THEN** the response is a 303 redirect to `/p/<token>`

#### Scenario: Unknown token is a friendly 404
- **WHEN** a request is made with a well-formed token that matches no digest
- **THEN** the response is status 404 rendering the friendly "This link is not valid" page with a link to the organizer-link recovery form

### Requirement: Pending tokens replace links without breaking the working one
`issue_pending_token!` SHALL store a new digest in `pending_token_digest` and leave `token_digest` and `user_id` unchanged. For guests the pending token SHALL NOT expire; for organizer recovery tokens `pending_token_expires_at` SHALL be 24 hours after issue. A GET request with a pending token SHALL resolve the participant and MUST NOT change any digest or `user_id`. The first non-GET request authenticated by a pending token SHALL promote it in one guarded statement (`WHERE pending_token_digest = digest`): `token_digest` becomes the pending digest, the pending columns are cleared, and `user_id` is cleared unless the request is signed in as that user. Until promotion both the old live token and the pending token SHALL work.

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

### Requirement: Leaving revokes every credential
`Participant#leave!` SHALL run inside `event.with_lock`, delete the participant's slots, set `responded_at`, `declined_at` and `left_at`, and clear `user_id`, `token_digest`, `pending_token_digest` and `pending_token_expires_at`.

#### Scenario: Both tokens stop working after leave
- **WHEN** a guest with a live and a pending token leaves
- **THEN** GET with either token returns 404 and the session family returns 404 for the account that had claimed it

### Requirement: Two route families resolve one identity
The system SHALL expose a token family under `scope "p/:token", constraints: { token: %r{[^/]+} }, format: false` and a session family under `scope "participations/:participation_id", as: :my`. Both SHALL mount the same singular `resource :participation` and the same nested actions (decline, finalization, invitations, participants#destroy, resend) on shared controllers; the claim action exists only in the token family. Family detection and the `authenticate_user!` skip MUST key on `request.path_parameters` (`:token` present), never on `params`. In the session family the participant SHALL be `current_user.participants.active.find(params[:participation_id])`. Route helpers `participation_*_path(token, ...)` and `my_participation_*_path(participant, ...)` SHALL exist and a routing test SHALL pin each helper, its controller and action, and the viewer parameter for both families.

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

### Requirement: Role and state gates answer 404, never 403
Guest-only actions (availability update, decline, leave) SHALL respond 404 to an organizer token. Organizer-only actions (finalization, invitations, resend, remove) SHALL respond 404 to a guest token. Invitations and resend SHALL additionally require `link_opened_at` on the organizer and otherwise respond with a 303 redirect and an explanatory alert. Nested targets (`params[:id]` for remove, `params[:participant_id]` for resend) SHALL be resolved only through `@participant.event.guests.active`, so the organizer row and rows of other events are unreachable.

#### Scenario: Organizer token cannot respond as a guest
- **WHEN** an organizer token sends PATCH availability, POST decline or DELETE leave
- **THEN** each response is 404 and the organizer's offer rows are unchanged

#### Scenario: Guest token cannot manage the event
- **WHEN** a guest token sends POST finalization, POST invitations, POST resend or DELETE a participant
- **THEN** each response is 404

#### Scenario: Remove with a foreign id is not found
- **WHEN** an organizer sends DELETE participants with the id of a guest from another event, or with their own id
- **THEN** the response is 404 and no row is deleted

### Requirement: Failure pages are friendly and uniform
Unknown, expired, revoked, left and malformed tokens SHALL render one identical 404 page ("This link is not valid…") with a link to the organizer-link recovery form. `allow_browser` SHALL use the grid's real floor (`safari: 15.4, chrome: 99, firefox: 93, opera: 85, ie: false`) and an explicit block that renders an `errors/unsupported_browser` view with the application layout and status 406, telling invited guests to reply to the invitation email.

#### Scenario: Left, revoked and unknown tokens are indistinguishable
- **WHEN** GET is made with a left guest's old token, with a revoked token and with a random well-formed token
- **THEN** all three responses are 404 with byte-identical bodies except the CSRF meta tags

#### Scenario: Unsupported browser gets a real page
- **WHEN** a request carries a Safari 14 user agent
- **THEN** the response is 406 and the body contains the unsupported-browser message rendered in the layout

### Requirement: Capability pages carry cache, index and referrer hygiene
Every response in both families SHALL set `Cache-Control: no-store`, include `<meta name="robots" content="noindex">` and `<meta name="turbo-cache-control" content="no-cache">` through a `yield :head` in the layout, and render `og:url` as the site root (or a `content_for(:canonical_url)`), never the request URL.

#### Scenario: Token page hygiene headers and tags
- **WHEN** GET `/p/<token>` succeeds
- **THEN** the response has `Cache-Control: no-store`, the head contains the `noindex` and `turbo-cache-control` meta tags, and `og:url` does not contain the token

### Requirement: Tokens are masked in application logs
The system SHALL configure `config.filter_redirect` to mask `/p/<32 base58 chars>` in "Redirected to" lines, set `log_arguments = false` on the mail delivery job, and install a `Rails::Rack::Logger` subclass (or equivalent) that rewrites `/p/<token>` to `/p/[FILTERED]` in the "Started" request line. The Thruster access log in the production image SHALL be disabled or masked; if the pinned Thruster version offers no switch, the limitation MUST be documented in `design.md` Open Questions and `.env.example` comments.

#### Scenario: Raw token absent from Rails logs
- **WHEN** `GET /p/<token>` is made while capturing `Rails.logger` output, followed by a failed PATCH that redirects back
- **THEN** the captured output does not contain the raw token

### Requirement: Writes are ordinary CSRF-protected forms with a courtesy rate limit
All state changes in both families SHALL be POST, PATCH or DELETE forms protected by Rails CSRF; the token SHALL appear only in the form action path. Token-family write actions SHALL carry `rate_limit to: 30, within: 1.minute` keyed by the path token (fallback: remote IP) as a courtesy layer. Confirmations SHALL use `data-turbo-confirm` on `button_to` forms.

#### Scenario: Missing authenticity token is rejected
- **WHEN** forgery protection is enabled in a test and a PATCH is sent to `/p/<token>` without an authenticity token
- **THEN** the request is rejected and no slot changes

#### Scenario: Excess writes are throttled
- **WHEN** the captured rate-limit store reports 31 writes within a minute for one token
- **THEN** the next write responds 429
