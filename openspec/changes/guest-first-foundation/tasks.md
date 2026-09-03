## 1. Gate green and checkout bootable

- [x] 1.1 Delete the `ARGV.unshift("--ensure-latest")` line from `bin/brakeman`; keep `--exit-on-warn --exit-on-error` in CI and `config/ci.rb` unchanged
- [x] 1.2 Change `Gemfile` to `ruby "~> 4.0.5"` so a patch-level Homebrew Ruby boots the app; keep `.ruby-version` at `4.0.5` so CI and the Dockerfile stay exact and `Gemfile.lock` keeps `RUBY VERSION ruby 4.0.5` (frozen installs tolerate the patch difference; verified locally on 4.0.6); leave `.node-version` exact (CI asserts it)
- [x] 1.3 Change `package.json` `test` to `node --test test/javascript/`
- [x] 1.4 Give `ApplicationMailer` the sender fallback `ENV.fetch("MAILER_FROM", "no-reply@catching.app")` and set Devise `config.parent_mailer = "ApplicationMailer"`
- [ ] 1.5 Open a PR with only the above, confirm all five CI jobs pass including the container smoke test, and note whether bundler-audit surfaces anything now that it runs again

## 2. Grid library and painting (front end only, Ruby suite untouched)

- [x] 2.1 In `app/javascript/lib/time_grid.js` add `localDaySlots(day, slotMinutes)`, make `localDayColumns` accept `slotMinutes` and apply `startOf("day")` after each day increment, alias `localSlotLabels`, keep `hours` as an alias for one phase; node tests for Tirane at 15/30/60, Santiago `[24, 23, 24, 24]`, Cairo three columns, Lord Howe labels (specs/slot-granularity, specs/availability-grid)
- [x] 2.2 Add `offeredGrid(offeredInstants, eventZone, viewerZone, slotMinutes)` with the organizer lattice, viewer-local day columns, circular band, `(wallMinutes, occurrence)` row keys, placeholders and the day-boundary marker; node tests for Kolkata from UTC, Berlin 09–18 from Auckland (19 rows) and Tokyo, Mon/Tue alignment, fall-back extra row
- [x] 2.3 Add `app/javascript/lib/paint.js` (`attachPainting`, pointer-type stroke decision, capture in try/catch, `elementFromPoint` hit-testing, single stroke end, `AbortController` idempotence, edge auto-scroll loop) and pure helpers `strokeMode`, `applyStroke`, `remapZone`, `rescale`, `summary`; node tests in `test/javascript/paint.test.js`
- [x] 2.4 Rewrite `time_slot_definer.js` on the shared module: table markup, selection Set hydrated from the hidden value, wall-clock remap on zone change, rescale on step change, range drops, summary, serialize on stroke and submit, `populateTimeZoneSelect(select, preferred)` honoring `data-selected`
- [x] 2.5 Rewrite `time_slot_show.js` on the shared module: `offeredGrid`, `data-role`, `data-not-before` past cells and empty state, `#availability-counts` labels, selection survives zone change, `sessionStorage` stash and re-apply, `pageshow` reload, finalized window in the picker zone, forms copy the picker into `participant[time_zone]`
- [x] 2.6 Accessibility: `role="grid"`, `th[scope=col]`, `aria-label` with counts, `aria-disabled` on non-offered and past cells, roving tabindex with arrow keys and Space, `:focus-visible` outline, `visibility: hidden` for the hide switch, `#paint-mode` as a radiogroup
- [x] 2.7 SCSS: table styling, `touch-action` rules with `pinch-zoom`, `.painting` state, bounded-height `.time-grid-scroll` with sticky headers and row-label column, coarse-pointer row heights and sticky action bar, `.slot.past`, valid `.received` colors, `.card { width: min(400px, 100%) }`
- [x] 2.8 Render `value` on the hidden `#time_slot_array` in `events/new.html.erb` and add `data-slot-minutes`/`data-time-zone` to both grid roots (defaults 60 and browser zone in this phase); `events/show.html.erb` moved to the show contract (`data-role`, `#my-time-slots`, `#availability-counts`, action bar, `#is-host` removed) with two extra instance variables in `EventsController#show`
- [x] 2.9 System tests: update `authenticated_ui_test.rb` selector to `.slot`; add `organizer_paints_with_mouse_test.rb` (pointer actions paint two adjacent cells, zone change moves them); add `MobileSystemTestCase` (412x915, touch emulation, distinct driver name) and `guest_paints_on_touch_test.rb` asserting scroll-mode scroll, tap toggle, paint-mode four cells, edge auto-scroll, no horizontal body scroll, skipping with a message when the driver lacks touch `PointerInput`; keyboard test with one Tab stop
- [ ] 2.10 Run `npm run check` and the system tests in CI; PR with the Ruby suite unchanged

## 3. Data model: participants, ledger, granularity, re-parented slots

- [x] 3.1 Migration `20260902000001_create_participants.rb`: `participants` and `mail_deliveries` tables with every column, index, check constraint (validated in one step) and foreign key from design.md, explicit `up`/`down`
- [x] 3.2 Migration `20260902000002_add_scheduling_grid_to_events.rb`: `slot_minutes` (default 30, check), `time_zone` (default UTC), drop `meeting_medium` with type for `down`, `events_slot_minutes_allowed` and `events_finalized_window_whole_slots` checks
- [x] 3.3 Migration `20260902000003_reparent_time_slots_to_participants.rb`: backfill organizer and guest participants, `participant_id`, drop `user_id` and `end_time`, unique `(participant_id, start_time)`, `(event_id, start_time)`, composite FK, `date_bin` quarter-hour check, structural `down`
- [x] 3.4 Migration `20260902000004_drop_user_ownership.rb`: drop `user_events` with full column block, `remove_reference :events, :user`, `down` recreating a nullable `events.user_id`
- [x] 3.5 Regenerate `db/schema.rb` in the build-stage image against postgres:18 (`docker build --target build`, `db:drop db:create db:migrate`), then `db:rollback STEP=4 && db:migrate`, commit
- [x] 3.6 Models: `Participant` (enum, normalizes, validations, scopes, `issue_live_token!`, `issue_pending_token!(expires_in:)`, `find_by_token` with stripping and pending lookup, `promote_pending!`, `revoke_tokens!`, `leave!`, `display_name`), `MailDelivery` (+ `Caps` with canonical keys, budget, IP, starter allowance, exemptions), `TimeSlot`, `User` associations (`participants` nullify, `events` through)
- [x] 3.7 `Event`: `plan!`, `slot_length`, `for_user`/`organized_by`, `replace_time_slots!(participant:, starts_at:)` with the `ArgumentError` guard, explicit `event_id`, `ensure_aligned!`, `insert_all!` under `with_lock`; `mark_unavailable!`; single-statement `mutually_available_start_times` with correlated denominator and `EXISTS` guard; `finalize!` with `ensure_replies!`, `slot_length` contiguity and `end_time`; immutability of `slot_minutes`/`time_zone` after a reply; normalizes on `name` and `description`; length validations
- [x] 3.8 `TimeSlotParser.call(value, slot_minutes:)` with scaled caps and the past-instant rule; new `InviteeListParser`
- [x] 3.9 Fixtures: `participants.yml` with ERB digests, `mail_deliveries.yml`, events with `slot_minutes: 60`/`time_zone: UTC`, time_slots by participant; delete `user_events.yml`, `user_event.rb`, `user_event_test.rb`
- [x] 3.10 Tests: `participant_test.rb`, `mail_delivery_test.rb`, `time_slot_test.rb`, `fixture_integrity_test.rb`, `event_test.rb` rewritten (alignment at Kolkata/Lord Howe/Santiago, contiguity at 15/30/60, consensus one statement, `ensure_replies!`, stale-request `FOR UPDATE` assertions verbatim), `event_contention_test.rb` with `use_transactional_tests = false`, `time_slot_parser_test.rb` additions, `invitee_list_parser_test.rb`, `user_test.rb` nullify
- [x] 3.11 `guest_first_foundation_migrations_test.rb`: truncate cascade, down/up with connection introspection only, `SchemaDumper.dump(connection_pool, io)` versus `db/schema.rb`; pg_temp test for the 0003 backfill SQL

## 4. Token pages and routes (still behind login for organizers in this phase)

- [x] 4.1 Routes: `scope "p/:token", constraints: { token: %r{[^/]+} }, format: false` and `scope "participations/:participation_id", as: :my`, the `participation_actions` concern (decline, finalization, invitations, participants#destroy with nested resend and link_reveal), claim in the token family only; remove `events#show/#update` and `time_slots`; add `events#pending` and `organizer_links`
- [x] 4.2 `ParticipationScopedController`: family detection and `authenticate_user!` skip keyed on `request.path_parameters`, `set_participant` per family, canonical 303 for stripped tokens, `rescue_from RecordNotFound` to the friendly 404, `Cache-Control: no-store`, `content_for :head` tags, `scoped_path`, role gates `require_guest!`/`require_organizer!`/`require_opened_organizer!`, nested target scoping, courtesy `rate_limit` on writes
- [x] 4.3 `ParticipationsController` (`show`, `update`, `destroy` → 303 root), `Participations::DeclinesController`, `FinalizationsController`, `InvitationsController`, `ParticipantsController#destroy`, `ResendsController`, `LinkRevealsController`, `ClaimsController`; shared `parsed_time_slots` concern with `slot_minutes:`; `link_opened_at` set only through the token family
- [x] 4.4 Views: `participations/show` (event card, participant table with delivery states and counts, waiting state, forms for guest/organizer/viewer roles, claim CTA, session-family organizer hint), `participations/not_found`, `errors/unsupported_browser`, layout `yield :head` and canonical `og:url`, `events/pending`; delete `events/show.html.erb` and `time_slots/new.html.erb`
- [x] 4.5 `allow_browser` floor `safari: 15.4, chrome: 99, firefox: 93, opera: 85, ie: false` with the explicit 406 block
- [x] 4.6 `EventsController#new/#create` on `Event.plan!` with the new fields (organizer = `current_user` in this phase, tokens issued at creation, no mail); anonymous CTA in navbar and home (link only)
- [x] 4.7 Dashboard over `current_user.participants.active`; remove the Members tab, badge and `_my_friends`; `after_sign_in_path_for`; `ActivitiesController` scopes, owner gate and back link
- [x] 4.8 Rewrite `db/seeds.rb` through `Event.plan!` printing participation URLs, keeping the development guard
- [x] 4.9 Tests: routing test for both families (helpers, viewer params, mangled links, signed-out redirects, query-token cases); controller tests for show contract and hygiene, every 404 gate, guest update/decline/leave, finalize cases, invitations/resend/remove/link-reveal, session family, activities, dashboard; claim tests; integration test updated

## 5. Verify-by-click, transactional mail, recovery, log masking

- [x] 5.1 Make `events#new/#create/#pending` public with `rate_limit`, `organizer[name]/[email]` and the signed-in override, creation caps with the generic identical refusal, pending page copy
- [x] 5.2 `ParticipantMailer` with `organizer_link`, `invitation`, `response_confirmation`, `finalized` in HTML and text under the mailer layout; content hygiene (no description, fixed prefix, subject prefix and truncation, bare Reply-To, coalesced ranges, promise sentence); previews; development `:file` delivery
- [x] 5.3 `MailDeliveryJob` with `log_arguments = false`, `require "net/smtp"`, `retry_on`/`discard_on` marking the ledger; `config.action_mailer.delivery_job`; `after_deliver` sets `delivered_at`; enqueue after commit with the ledger row created first and `request_ip` recorded
- [x] 5.4 Wire `Caps` into `plan!`, invitations, resend, link reveal and recovery; `INVITATION_DAILY_BUDGET` with the warning; failed rows exempt from cooldown and lifetime cap
- [x] 5.5 `OrganizerLinksController` (`new`, `create`) with the constant response even when capped, pending organizer tokens with 24-hour expiry, `user_id` untouched; "Send the link again" on the session-family organizer page and the pending page
- [x] 5.6 `config.filter_redirect`, the `Rails::Rack::Logger` subclass masking `/p/<token>` in the Started line, and the Thruster access-log switch for 0.1.23 (`LOG_REQUESTS=false` in the Dockerfile runtime environment, documented in `.env.example`)
- [x] 5.7 Tests: `participant_mailer_test.rb` per template with `MAILER_FROM` removed in setup, failing-delivery retry test, preview rendering test; controller tests for verify-by-click through both families, sends and caps (canonical, budget, IP, starter, victim exhaustion), resend after failure, pending-token GET/PATCH semantics, recovery identical responses and untouched `user_id`, log capture without raw token; integration test rewritten as the accountless story from anonymous create through finalize and a guest sign-up claim

## 6. Accounts and claim

- [ ] 6.1 `ClaimsController#show/#create` with the guarded compare-and-set including `left_at`, all four outcomes and messages, Devise stored location round trip
- [ ] 6.2 Dashboard cards with role and status, claimed organizer flow (organizer_link mail, invitations gated), account-deletion nullify test, forgery-protection-on integration test
- [ ] 6.3 System tests: `organizer_plans_event_test.rb` (signed out, pending page, organizer link, send), `organizer_finalizes_test.rb`, `claim_round_trip_test.rb`, old-Safari 406 controller test

## 7. Close out

- [ ] 7.1 Run `bin/ci` in the build-stage image and confirm all five GitHub jobs green, including Brakeman with `--exit-on-warn`
- [ ] 7.2 Update README.md: security model (participants, capability links, no directory, caps), verification section, environment variables (`INVITATION_DAILY_BUDGET`), and the local-Ruby note; update SECURITY.md wording about the member directory
- [ ] 7.3 Register the follow-up changes named in design.md Non-Goals as OpenSpec changes (`friends-graph`, `thorough-planning`, `visual-redesign`, `dead-file-removal`, `ci-regime`)
