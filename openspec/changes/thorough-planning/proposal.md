## Why

The participation page answers "when" and nothing else. A guest cannot see where the event is, how long it runs, or what the plan is; the organizer cannot change the offered times, fix a typo, call the event off, or take back a set time without planning a new event and re-inviting everyone. The activities table exists but is locked behind login on a route no guest can reach. PRODUCT.md lists editing, cancellation and richer planning fields as undecided; this change decides them, guest-first.

## What Changes

- **Event facts**: place, an http(s) join or map link, and a planned length on the event; shown on every participant's page; edited by the organizer on an organizer-only "Edit details" page reachable through both link families.
- **The plan**: the activities table becomes an ordered, guest-visible agenda edited by the organizer on the details page; once the time is set, each item shows its derived start in the viewer's zone. The account-only activities routes, controller and views are removed.
- **Calendar file**: a hand-rolled RFC 5545 `.ics` (stable `UID`, `SEQUENCE` = `events.revision`, 15-minute `VALARM`) attached to the finalized mail and downloadable from the page; `STATUS:CANCELLED` after cancel or reopen.
- **Offer revision**: the organizer changes the offered times after creation; guest picks at removed instants are deleted in the same transaction; a guest left with nothing is voided (`participants.reply_voided_at`) and drops out of the consensus denominator; step and zone stay frozen after the first reply.
- **Change notices**: one new mail kind `event_updated`, sent only when the organizer asks (checkbox or "Tell the guests"), capped at 5 per event and address with a 10-minute cooldown, sharing the invitation's daily keys.
- **Cancellation**: terminal, non-destructive; one `cancelled` mail to everyone with a link; every write refused afterwards except Leave and Claim.
- **Reopen**: withdraw a set time at most twice; every pick and link survives; one `reopened` mail per guest.
- **BREAKING (routes)**: `/events/:id/activities*` no longer routes; the plan lives under `/p/:token/activities` and `/participations/:id/activities`.
- **BREAKING (mail copy)**: the invitation's promise sentence and the finalized mail's closing sentence change; the finalized mail now carries a guest link and an attachment.

## Capabilities

### New Capabilities

- `event-details`: place, link, planned length; the details page; the facts block.
- `event-plan`: the ordered plan, its editor, derived starts, cascade delete.
- `calendar-file`: the `.ics` writer, the download route, mail attachment rules.
- `offer-revision`: the exact rules for changing the offer after creation, voiding, un-voiding.
- `change-notices`: the `event_updated` kind, its triggers, recipients, caps and body variants.
- `event-cancellation`: cancel and reopen, their refusals, mails and page states.

### Modified Capabilities

- `organizer-event-management`: capabilities list, participant states, action bar warnings.
- `event-finalization`: read-only rules after finalization, consensus predicate, finalized mail contents, `revision` bump.
- `transactional-email`: templates, ledger kinds, caps, the promise sentence, links in mails.
- `capability-links`: nested-action list in both families, role gates, not-found copy.
- `guest-availability-response`: Leave on closed events, stash filtering, inline notices.
- `organizer-link-recovery`: recovery scope `Event.not_cancelled`.
- `event-participants`: `reply_voided_at`, the `counting` scope.
- `availability-grid`: new data attributes and definer hidden inputs.
- `account-dashboard`: "cancelled" state; the activities requirement is removed.

## Impact

Three reversible migrations (`events`, `participants`, `activities`, `mail_deliveries` check), eight new controllers under `Participations::`, one service (`CalendarFile`), three mail templates plus changes to two, the definer and show JavaScript components, the participation and details views, PRODUCT.md, and the test suite (model, controller, routing, mailer, service, node, system). No new gem or npm dependency. No scheduler.
