# Catching App

Catching App helps a group find a mutually available time for an event. An organizer offers time slots, invites other users, and finalizes a continuous window after every participant has submitted availability.

## Ownership and collaboration

The original 2021 application was a three-person Le Wagon project built with [Sedef Çakmak](https://github.com/sedcakmak) and [Ege Çakmak](https://github.com/Egecak). GitHub attributes substantial implementation work to Okan, including 11 merged pull requests and 47 of the newest 100 commits at the 2026-07-18 audit. [Okan's merged pull-request history](https://github.com/okturan/catching-app/pulls?q=is%3Apr+is%3Amerged+author%3Aokturan) is the durable attribution source; the project is not presented as solo work, and no project-wide license is asserted without all three authors' agreement.

## Historical UI

These original team screenshots preserve the 2021 product flow while the implementation is modernized.

| Landing page | Event scheduling |
|---|---|
| ![Catching App landing page](docs/screenshots/legacy/Homepage.png) | ![Catching App scheduling flow](docs/screenshots/legacy/Carousel2.png) |

The complete historical set is in [`docs/screenshots/legacy`](docs/screenshots/legacy).

## Stack

- Ruby 4.0.5 (the Gemfile accepts `~> 4.0.5`) and Rails 8.1.3.1
- PostgreSQL 18
- Node.js 24.18.0 LTS and npm 11.16.0
- Propshaft, esbuild, Dart Sass, Turbo, Bootstrap 5, and Luxon
- Devise for optional accounts; capability links for everyone else
- Minitest, RuboCop Rails Omakase, Brakeman, and bundler-audit

Runtime versions are pinned in `.ruby-version`, `.node-version`, `Gemfile.lock`, and `package-lock.json`. Dependency updates are applied by hand; `bin/bundler-audit` and `npm audit` run in CI.

## Local setup

Install the pinned Ruby and Node.js versions, PostgreSQL, and Chrome or Chromium for system tests. Then run:

```bash
cp .env.example .env
bin/setup --skip-server
bin/dev
```

The app is available at <http://localhost:3000>. On a newly created development database, setup loads three demo users. Their shared password defaults to `development-password` and can be changed with `SEED_PASSWORD` before running setup.

To rebuild the database and development seed data:

```bash
bin/setup --reset --skip-server
```

## Verification

Run the complete local gate:

```bash
bin/ci
```

The gate installs deterministic dependencies, lints Ruby, audits Ruby and JavaScript dependencies, runs Brakeman, checks eager loading, builds assets, and runs the Rails test suite. Individual commands are also available:

```bash
bin/rails test
bin/rails test:system
bin/rails zeitwerk:check
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit check --update
npm run check
npm audit --audit-level=high
```

GitHub Actions runs the same categories of checks with PostgreSQL 18 and also builds the production image. Dependabot tracks Bundler, npm, and Actions updates.

## Production container

Build the non-root production image:

```bash
docker build -t catching-app .
```

The runtime expects these environment variables:

- `APP_HOST`: public hostname, without a scheme
- `DATABASE_URL`: PostgreSQL connection URL
- `SECRET_KEY_BASE` or `RAILS_MASTER_KEY`: Rails signing secret
- `MAILER_FROM`: sender address
- `SMTP_ADDRESS`: SMTP server address
- `SMTP_PORT`, `SMTP_USERNAME`, and `SMTP_PASSWORD`: optional SMTP connection settings
- `INVITATION_DAILY_BUDGET`: optional ceiling on invitation mails per day (default 500)
- `LOG_REQUESTS`: set to `false` (the Dockerfile does) so Thruster does not log capability links

The container prepares the database before starting, listens through Thruster on port 80, and exposes `GET /up` as its health endpoint. It assumes TLS is terminated by the reverse proxy and forces HTTPS for application traffic.

## How scheduling works

An organizer plans an event with an email address, a name, a slot length (15, 30 or 60 minutes), a time zone and a painted set of offered times. The organizer receives a link by email; opening it proves the address, and only then can invitations be sent. Each guest receives their own link, paints availability on the organizer's grid (mouse, finger or keyboard), can say that none of the times work, or can leave the event. The organizer finalizes one continuous window that every responder shares. Accounts are optional: they remember participations on a dashboard, and a guest can keep an event in an account from their link.

## Security model

- Every person on an event is a participant row; links carry a 32-character random token that is stored only as a SHA-256 digest. Re-sent and recovered links are pending tokens that go live on their first use, so a working link is never revoked by a resend, a scanner, or a stranger who knows the organizer's address.
- Nothing is sent to guests before the organizer has opened the emailed link. Invitations are capped per organizer, per recipient, per event and address, per IP, and by a global daily budget (`INVITATION_DAILY_BUDGET`, default 500), all counted in a delivery ledger. Confirmations and finalized notices are never refused.
- There is no member directory. Guests see other guests by display name or as "Guest"; the organizer sees the addresses they invited.
- Scheduling writes run under the event's row lock; database constraints enforce one organizer per event, one address per event, one account per event, quarter-hour instants and whole-slot windows.
- Capability pages are `no-store` and `noindex`, tokens are masked in request and redirect logs, and Thruster request logging is off in the production image.
- Authentication endpoints and token-route writes are rate limited per container as a courtesy layer; production forces TLS and host authorization.

See the official [Ruby releases](https://www.ruby-lang.org/en/downloads/releases/) and [Rails maintenance policy](https://guides.rubyonrails.org/maintenance_policy.html) for the support status behind the pinned baseline.
