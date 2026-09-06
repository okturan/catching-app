## 1. Pins and schema

- [x] 1.1 Move fixture `planning_invitee_only` into the organizer's offer (or drop it) and add the guest-slots-are-a-subset-of-the-offer assertion to the fixture integrity test
- [x] 1.2 Migration `add_planning_state_to_events_and_participants` (events: place, place_url, duration_minutes, revision, notified_revision, offer_revised_at, offer_revision_added/removed, cancelled_at, reopened_at, reopen_count; participants: reply_voided_at; all checks) with typed `down`
- [x] 1.3 Migration `revamp_activities_into_plan` (position with dense backfill, nullable duration/description, bounded check, `(event_id, position)` index, cascade FK) and its row-insert down test
- [x] 1.4 Migration `extend_mail_delivery_kinds` (event_updated, cancelled, reopened) and `MailDelivery::KINDS`; regenerate `db/schema.rb`; extend the round-trip test lists; `Activity` model rules and `activity_test.rb`; fixture `position`

## 2. Event facts and the details page

- [ ] 2.1 `Event` validations and normalizers for place, place_url, duration_minutes; `update_details!` (one save, revision bump, change set without revision/updated_at); `EventsHelper#place_link`
- [ ] 2.2 `events/new` gains place, link, planned length; `event_params`; `Event.plan!` passes them; `allowedDurations` helper and the step-change wiring in `time_slot_definer.js` with a node test
- [ ] 2.3 `scoped_path(edit:)`, `resource :details`, `Participations::DetailsController` (edit/update, organizer-only, cancelled → 303), the details face (`min(440px, 100%)`, details form closes before the plan section), facts block with `dt` in form-label style, zoned dates via `[data-zoned-instant]`
- [ ] 2.4 Routing, model, controller (both families), view and events tests; `assert_select "form form", count: 0`

## 3. The plan

- [ ] 3.1 `Participations::ActivitiesController` (create/update/destroy) and `ActivityMovesController` (`move[position]`, dense renumbering under the lock, revision bump), organizer-only, refused on cancelled
- [ ] 3.2 Plan editor on the details page with per-row forms and accessible labels; plan rows on every participant's card; derived starts with `data-zoned-instant` once finalized; "The plan runs longer than the set time" note
- [ ] 3.3 Delete `ActivitiesController`, its views, routes, test, the two show-page links and the `.container-cards` rules; fix the participation controller assertion; seeds become a two-item plan
- [ ] 3.4 Tests: model, controller (both families, 404 for guests and other events' items), view, node `zonedLabel`, system (organizer adds and reorders, guest sees the order)

## 4. Cancellation

- [ ] 4.1 `Event#cancel!`, `cancelled?/open?/closed?`, `ensure_pending!` message order, `ensure_not_cancelled!`, immutability validation, `Event.not_cancelled`
- [ ] 4.2 Base controller: `viewer_role`, `refuse_closed_writes` (Leave and Claim exempt), `rescue_from Event::ClosedError`; `Participations::CancellationsController`; cancelled page states (ink "Cancelled" plate, `data-cancelled`, Leave and Claim only, "Plan a new event"); dashboard "cancelled"
- [ ] 4.3 `cancelled` mail template; `Deliveries.cancelled!` (every active linked participant including the organizer, no token, never capped) and the `Deliveries` cancelled guard; recovery scope `Event.not_cancelled`
- [ ] 4.4 Tests: model refusals with exact messages, Deliveries guard, controller both families, Leave and Claim still work, mailer, recovery, dashboard

## 5. Calendar file and the finalized mail

- [ ] 5.1 `CalendarFile` service (CRLF, 75-octet folding, escaping, UID, SEQUENCE, DTSTART/DTEND in UTC, LOCATION, STATUS, DESCRIPTION plan lines, VALARM, page vs mail mode) and its tests including the 8 KB cap
- [ ] 5.2 `resource :calendar` (`calendar.ics`, format false), `Participations::CalendarsController#show` (any participant, 404 unless finalized, `STATUS:CANCELLED` when cancelled), "Add to calendar" plate button
- [ ] 5.3 `finalized` mail: facts, plan, guest link by the claimed/unclaimed rule, organizer copy without link, new closing sentence, attachment built from `window:` params; `Deliveries.finalized!` issues pending tokens and sets `notified_revision`; `finalize!` bumps `revision`
- [ ] 5.4 Finalize summary hint (`data-duration-minutes`, `summary()` extension, node test); update finalizations controller, workflow and mailer tests

## 6. Change notices

- [ ] 6.1 `MailDelivery::Caps.check_update_notice!` (5 per event and address lifetime excluding failed, 10-minute cooldown, shared daily keys) and the two-kind daily relation in `check_invitation!`
- [ ] 6.2 `Deliveries.event_updated!` (recipients by reason, declined excluded on removal-only, opened-link requirement, pending token vs `my_participation_url`, skip on cap, `notified_revision`), `reason:` and `changes:` mailer params, `event_updated` templates with body variants
- [ ] 6.3 `notice[send]` checkbox on the details form, `resource :notice`, `Participations::NoticesController`, "Tell the guests" button; guest not-found copy about newer links; Leave sentence at the end of finalized/event_updated/reopened bodies
- [ ] 6.4 Rewritten invitation promise and confirmation sentences; tests: caps, deliveries, mailer variants, previous pending link 404s after a notice, controller

## 7. Offer revision

- [ ] 7.1 `reply_voided_at` behaviour: `counting` scope and `counting?`, consensus predicate (still one statement), clearing in `ParticipationsController#update`, `mark_unavailable!`, `leave!`
- [ ] 7.2 `Event#revise_offer!` with the three outcomes (instant delta / step-or-zone only / nothing), past frozen, guest row deletion, voiding, `duration_minutes` cleared when it stops fitting, `Revision` return value
- [ ] 7.3 `resource :offer`, `Participations::OffersController` (organizer-only, finalized → "Reopen the time before changing the offer", cancelled → 303), partials `events/_grid_controls` (builder-agnostic) and `events/_definer_grid`, `events/new` refactored onto them with its ID contract unchanged
- [ ] 7.4 Definer JS: `data-not-before` past cells, `#current-offer`, `#guest-picked-counts` badges with extended `aria-label`, `removalWarning` and `turbo_confirm`, disabled step/zone with `aria-describedby`; `filterStash` in `time_slot_show.js`; node tests for the pure helpers
- [ ] 7.5 Guest inline notices (`role="status"`), organizer table states and counts, action-bar warnings including "Every offered time has passed"; `event_updated` offer variants
- [ ] 7.6 Tests: model cases (added/removed/trimmed/voided/no-op/Berlin→Paris/past-frozen/frozen after reply/consensus excludes voided/`ensure_replies!`), fixture integrity, controller both families and the definer ID contract on `offer/edit`, mailer, system (voided guest re-replies)

## 8. Reopen

- [ ] 8.1 `Event#reopen!` (status true only, not cancelled, at most twice, window captured, revision bump), `resource :reopening`, `Participations::ReopeningsController`
- [ ] 8.2 `reopened` mail with `previous_window:` params and `STATUS:CANCELLED` attachment; `Deliveries.reopened!`; page controls ("Reopened once/twice"), guest note while `responded_at < reopened_at`, every-offer-past sentence
- [ ] 8.3 Tests: model transitions and refusals, controller both families, mailer, round trip finalize → reopen → revise → finalize

## 9. Derived times, previews and close-out

- [ ] 9.1 `[data-zoned-instant]` rewrite in `time_slot_show.js` with a `zonedLabel` node test; `finalized` mail plan lines with derived starts; `ParticipantMailerPreview` samples for every kind and the preview-rendering test
- [ ] 9.2 PRODUCT.md capabilities and undecided lines rewritten; change README rewritten without polls; register `guest-polls`, `reminders`, `organizer-digest`, `data-retention` READMEs
- [ ] 9.3 Full check green: `npm test`, `bin/rails test`, `bin/rails test:system`, `bin/rubocop`, `bin/brakeman`; `openspec validate thorough-planning`
