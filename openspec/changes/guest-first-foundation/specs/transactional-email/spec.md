## ADDED Requirements

### Requirement: Mail infrastructure has one sender and one delivery job
`ApplicationMailer` SHALL default `from` to `ENV.fetch("MAILER_FROM", "no-reply@catching.app")`; Devise SHALL use `config.parent_mailer = "ApplicationMailer"`; production SHALL still require `MAILER_FROM` at boot. `config.action_mailer.delivery_job` SHALL be `MailDeliveryJob < ActionMailer::MailDeliveryJob` with `log_arguments = false`, `retry_on Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout` (polynomially longer, 3 attempts, marking the ledger row failed after the last), and `discard_on Net::SMTPFatalError, Net::SMTPAuthenticationError, Net::SMTPSyntaxError` with the same marking; the job file SHALL `require "net/smtp"`. Development SHALL use `delivery_method = :file` and a `ParticipantMailer` preview SHALL exist.

#### Scenario: CI without MAILER_FROM still sends
- **WHEN** `MAILER_FROM` is absent from the environment in a mailer test
- **THEN** every `ParticipantMailer` mail has From `no-reply@catching.app`

#### Scenario: Transient SMTP failure retries then fails the ledger row
- **WHEN** the delivery method raises `Net::SMTPServerBusy` on every attempt
- **THEN** a retry is enqueued after the first attempt and after the third the ledger row has `failed_at` and an `error` set

### Requirement: Four templates with defined triggers and recipients
`ParticipantMailer` SHALL provide, each in HTML and text: `organizer_link` (to the organizer; after `Event.plan!` commits and from the recovery form; subject "Catching App: your organizer link"; constant content with no organizer-supplied text), `invitation` (to a guest; on send and resend; subject "Catching App: <organizer name> invited you to <event>"), `response_confirmation` (to a guest; first reply only, including decline; subject "Catching App: your reply to <event> is saved"; contiguous instants coalesced into per-day ranges in the guest's zone and the event zone, capped with "and N more days"), and `finalized` (one job per participant with a live token; subject "Catching App: <event> is set for <date in recipient zone>"). Every mail SHALL state why the recipient got it and how to stop, and SHALL fall back to the event zone when the participant has no valid zone. Only `organizer_link` and `invitation` carry a link (they are the mails that issue a token); `response_confirmation` and `finalized` point the recipient to the link from their invitation.

#### Scenario: Organizer link carries no organizer text
- **WHEN** an event named "Buy crypto now http://evil.example" is planned
- **THEN** the `organizer_link` body and subject contain neither the event name nor any URL other than the participation link

#### Scenario: Confirmation coalesces ranges
- **WHEN** a guest saves 09:00, 09:30, 10:00 and 14:00 on one day at 30 minutes
- **THEN** the confirmation lists "09:00–10:30" and "14:00–14:30" for that day in both zones

### Requirement: Invitation content resists phishing
The invitation SHALL exclude the event description, link to the participation page instead, name the organizer as "Invitation from <name> (<email>)" with the fixed prefix first, never place organizer-supplied text as the first token of the subject, contain no `://` originating from organizer input, prefix subjects with "Catching App:" and truncate them to 80 characters, set Reply-To to the organizer's bare validated address, and promise exactly: "You will get at most: up to 5 resends, one confirmation when you reply, and one message when the time is set."

#### Scenario: Description never reaches the mail
- **WHEN** an event description contains `https://evil.example`
- **THEN** the invitation body in both parts contains no `://` except the participation link

#### Scenario: Header injection is neutralized
- **WHEN** an event is named with `"\r\nBcc: victim@example.com"` inside
- **THEN** the subject contains no line breaks and no Bcc header is set

### Requirement: Every mail is a ledger row
`mail_deliveries` SHALL have `event_id` (cascade), `participant_id` (nullable, set NULL on delete), `kind` (`organizer_link`, `invitation`, `response_confirmation`, `finalized`, `link_shown`; database check), `recipient_email`, `canonical_recipient_email`, `sender_email` (organizer email for invitations, canonical), `request_ip`, `delivered_at`, `failed_at`, `error`, `created_at`, with indexes on `(canonical_recipient_email, created_at)`, `(sender_email, created_at)`, `(event_id, canonical_recipient_email)`, `(request_ip, created_at)` and `(participant_id, created_at)`. The row SHALL be created before enqueue; `after_deliver` SHALL set `delivered_at`; job handlers SHALL set `failed_at`. Rows SHALL survive participant removal.

#### Scenario: Delivery marks the row
- **WHEN** an invitation job performs successfully
- **THEN** its ledger row has `delivered_at` set and `failed_at` NULL

#### Scenario: Ledger survives removal
- **WHEN** a guest with three ledger rows is removed
- **THEN** the three rows exist with `participant_id` NULL

### Requirement: Send caps use canonical keys and do not scale with free identities
The system SHALL canonicalize addresses for caps by stripping a `+tag` from the local part and, for `gmail.com` and `googlemail.com`, removing dots. Caps, all counted from the ledger over the last 24 hours unless stated: a global invitation budget (`INVITATION_DAILY_BUDGET`, default 500) beyond which invitations are refused and a warning is logged; 100 invitation recipients per canonical organizer email, reduced to 20 while that organizer has no finalized event; 200 invitation sends per request IP; 10 invitation mails per canonical recipient address (system kinds exempt); per (event, canonical address) 5 invitation sends ever and a 10-minute cooldown, excluding rows with `failed_at`; one `organizer_link` per canonical address per hour. `response_confirmation` and `finalized` mails MUST never be refused by a cap. Refusals SHALL be 303 alerts with a generic message and MUST NOT raise.

#### Scenario: Plus-addressing shares one allowance
- **WHEN** `spam+1@example.com` has used 100 invitation recipients today and `spam+2@example.com` sends more
- **THEN** the send is refused

#### Scenario: Global budget stops the cannon
- **WHEN** 500 invitation rows exist in the last 24 hours
- **THEN** the next invitation send is refused and a warning is logged

#### Scenario: Starter allowance
- **WHEN** an organizer email with no finalized event has 20 invitation recipients today
- **THEN** the next send is refused, and after that organizer finalizes an event the limit becomes 100

#### Scenario: Finalized notice is never capped
- **WHEN** a recipient has reached 10 invitation mails today and an event they are on is finalized
- **THEN** the `finalized` mail is enqueued

### Requirement: Mail behavior is tested per template
`test/mailers/participant_mailer_test.rb` SHALL assert per template: recipient, subject, From fallback with `MAILER_FROM` removed in setup and restored in teardown, Reply-To, the link with the raw token in both parts of the two token-carrying templates, zone rendering, and the `organizer_link` freedom from organizer text; a test SHALL render every `ActionMailer::Preview`; controller and integration tests SHALL use `assert_enqueued_emails` and `perform_enqueued_jobs` to pull links from deliveries.

#### Scenario: Preview rendering
- **WHEN** the preview test iterates `ActionMailer::Preview.all`
- **THEN** every preview method renders without error
