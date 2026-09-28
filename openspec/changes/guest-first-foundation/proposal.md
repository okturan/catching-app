## Why

Catching App can only schedule among registered accounts picked from a directory of every other user, so a meeting with anyone outside the app is impossible and every invitee must sign up first. The product vision is a guest-friendly scheduler where an emailed link is enough to answer and an email address is enough to organize. Nothing is deployed and no data exists, so the identity model can change now at zero migration cost; every month of delay adds data that would have to be migrated later.

## What Changes

- **BREAKING** Every person on an event becomes a `participants` row (role `organizer` or `guest`, email, optional name, nullable `user_id`). `time_slots` re-parent from users to participants; `events.user_id` and the `user_events` table are dropped; the member directory (Members tab, `invited_user_ids` select over all users) is removed.
- Capability links: guests and organizers act through `/p/:token`; tokens are stored only as SHA-256 digests, can be replaced by a mailed pending token without killing the working link, and are revoked when a guest leaves. Account holders reach the same pages through `/participations/:id`.
- Accountless organizer: creating an event needs a name and an email; the organizer link arrives by mail; invitations leave only after that link has been opened (verify-by-click) and within DB-backed caps and a global daily budget.
- Transactional email with a `mail_deliveries` ledger: organizer link, invitation, response confirmation (first reply only), finalized notice; delivery state and retries via a dedicated mail job; sender fallback so CI needs no `MAILER_FROM`.
- Per-event slot granularity `events.slot_minutes` in {15, 30, 60} (default 30) and `events.time_zone`; parser, alignment, contiguity, finalize, DB checks and the grid derive from them.
- Availability grid rebuilt as an accessible table: the show grid draws the organizer's lattice on a circular wall-clock band, the definer keeps selections across zone and step changes, and painting works with mouse, finger (scroll and paint modes) and keyboard. The DST midnight-gap defect in `lib/time_grid.js` is fixed.
- Guest exits: "None of these times work" (decline, reversible) and "Leave this event" (revoked, unclaimed). Consensus counts responders only, and finalization needs at least one guest reply.
- Claim flow (guest link into an account), dashboard over participations, account deletion nullifies participations instead of destroying other people's events.
- Organizer-link recovery form with a constant response.
- Friendly 404 for bad links and 406 for unsupported browsers; token masking in logs and redirects.
- Minimal CI unblock: remove `--ensure-latest` from `bin/brakeman`, mailer sender fallback, JavaScript test glob.
- **BREAKING** Routes removed: `GET/PATCH /events/:id`, `POST /events/:event_id/time_slots`, `TimeSlotsController`, `events/show` and `time_slots/new` views.

## Capabilities

### New Capabilities

- `event-participants`: the Participant model, its roles, states, invariants, ownership of availability, account linkage, and the reversible migrations that replace user ownership.
- `capability-links`: token issuance, storage, resolution, pending replacement, revocation, the two route families, role gates, failure pages, page and log hygiene.
- `event-planning`: creating an event with an offer, granularity, time zone and invitee list, signed in or not, atomically and under caps.
- `guest-availability-response`: how a guest views an event, paints and saves availability, declines, leaves, and what happens after finalization.
- `organizer-event-management`: verify-by-click, sending and resending invitations, inviting more people, removing guests, and the participant table with delivery state.
- `event-finalization`: the consensus denominator, contiguity, finalize, the closed state and the finalized notice.
- `slot-granularity`: per-event slot length and time zone and every derivation from them.
- `availability-grid`: the table markup, the definer and show grids, pointer and touch painting, keyboard access, DST behavior and the serialization contract.
- `transactional-email`: templates, ledger, caps and budget, delivery job, sender configuration and content hygiene.
- `organizer-link-recovery`: the lost-link form and its constant response.
- `participation-claim`: linking a token participation to an account.
- `account-dashboard`: what a signed-in user sees, the removal of the member directory, and activities authorization.

### Modified Capabilities

(none: `openspec/specs/` is empty)

## Impact

- Data: four new migrations on top of `20260710000000` (participants and mail_deliveries; events columns; time_slots re-parenting; drop user ownership); `db/schema.rb` regenerated; fixtures rewritten; `user_event.rb` and its test and fixture deleted.
- Models: `Participant`, `MailDelivery` (+ `Caps`), `Event` (`plan!`, participant-based `replace_time_slots!`, `mark_unavailable!`, alignment, single-statement consensus, locks), `TimeSlot`, `User` (associations only).
- Services: `TimeSlotParser` gains `slot_minutes:` and a past-instant rule; new `InviteeListParser`.
- Web: `EventsController` (public new/create/pending), `ParticipationScopedController` base, `ParticipationsController` and six nested controllers, `OrganizerLinksController`, `DashboardsController`, `ActivitiesController` scopes; routes for the token and session families; `TimeSlotsController` and the events show page removed; layout gains `yield :head` and a canonical `og:url`.
- JavaScript and CSS: `lib/time_grid.js`, new `lib/paint.js`, both grid components, `time_zones.js`, `_time_slot_definer.scss`, `_cards.scss`.
- Mail: `ParticipantMailer` with four templates in HTML and text, `MailDeliveryJob`, previews, development file delivery.
- Config: `ApplicationMailer` sender fallback, Devise `parent_mailer`, `delivery_job`, `filter_redirect`, a `Rails::Rack::Logger` mask for `/p/<token>`, `after_sign_in_path_for`, `allow_browser` floor and block, `bin/brakeman`, `package.json` test glob. CI workflow, Dockerfile and `.env.example` unchanged.
- Tests: models, services, routing, controllers, integration, mailer, migration round-trip, JavaScript, and five system tests including a mobile touch class.
- Documentation: README sections on the security model and verification updated in the final task group.
