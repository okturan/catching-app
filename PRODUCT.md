# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Friend groups spread across time zones who want to do something together at the same moment: a call, a movie night, an online game, a catch-up. One person organizes; the rest are guests who may never have used the product and should not have to sign up. Mobile use is normal for guests, who typically open the link from a message or an email on a phone.

## Product Purpose

Catching App finds a time that works for everyone. The organizer offers a range of slots on a grid, guests paint the ones that work for them in their own time zone, and the organizer confirms one continuous window that every responder shares. Success is a confirmed time with the least back-and-forth, for people who do not share a calendar.

## Positioning

- Painting time instead of ticking boxes: availability is drawn on a touch-capable grid, with the whole grid shown in each viewer's own time zone.
- Nobody has to sign up: guests answer through a personal link; the organizer needs only an email address and receives an organizer link. Accounts exist only to remember events.
- Flexibility: per-event slot length (15, 30 or 60 minutes), a 31-day planning range, and guests who can say "none of these work" or leave the event.
- Tone: made for friends, not offices.

## Operating Context

- Organizer plans on the web, usually desktop or laptop; guests respond from the emailed link, often on a phone.
- Email is the delivery channel for every link (organizer link, invitations, confirmation, final time). Invitations leave only after the organizer has opened their own link.
- Time zones are first-class: the organizer's zone anchors the grid; every viewer sees it in a zone of their choosing; mails print times in both.

## Capabilities and Constraints

- Events: name, description, slot length, time zone, offered slots, a place with an optional link, a planned length and a plan of up to 20 items; one organizer; up to 50 guests; finalization needs at least one guest reply and one continuous window shared by all responders. The plan is edited by the organizer and read by every participant through their link.
- Guests: view, paint availability, decline ("none of these times work"), leave; optional display name; optional claim into an account; once the time is set, a calendar file with a reminder from the page and from the mail.
- Organizer: send and resend invitations, invite more, remove a guest, show a link to copy, edit the details and the plan, change the offered times, tell the guests about changes, finalize, reopen the set time (twice at most), cancel; lost-link recovery by email.
- Accounts (Devise): dashboard of participations; no member directory; email is not verified.
- Constraints: Rails 8.1 on PostgreSQL, Propshaft, esbuild, Dart Sass, Turbo; CSP forbids inline scripts; slot length and zone are frozen after the first guest reply; every mail is capped by a delivery ledger (change notices: five per guest and event, ten minutes apart); cancellation is final and nothing is sent after it.
- Undecided: a friends graph, mail reminders before the set time, polls. Registered as follow-up changes under `openspec/changes/` (`friends-graph`, `reminders`, `guest-polls`).

## Brand Commitments

- Name: Catching App.
- Domain: catching.app.
- Tagline: "We have some catching app to do!" and the playful tone it sets.
- Open: the current logo (`app/assets/images/Sadelogo.png`), colors, typography and imagery are not binding.

## Evidence on Hand

- Working product on the `guest-first-foundation` branch with 152 Rails tests, 7 browser tests and 19 JavaScript tests.
- Historical 2021 screenshots in `docs/screenshots/legacy/`.
- No testimonials, usage numbers, press or customer names exist; future copy must not invent them.
- Current imagery is hosted on a third-party Cloudinary account not controlled by the project; the three landing-page videos and eight images there are not committed assets.

## Product Principles

- The guest's path is the product: fewest steps from link to painted grid, on a phone, in their own time zone.
- Never make someone sign up to answer.
- Time is shown in the viewer's zone and named explicitly wherever it appears.
- Friendly by default, precise underneath: playful copy, strict data.
- Nothing leaves without the organizer's proof of address, and every mail says why it arrived and how to stop.
