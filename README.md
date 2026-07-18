# Catching App

Catching App helps a group find a mutually available time for an event. An organizer offers time slots, invites other users, and finalizes a continuous window after every participant has submitted availability.

## Stack

- Ruby 4.0.5 and Rails 8.1.3
- PostgreSQL 18
- Node.js 24.18.0 LTS and npm 11.16.0
- Propshaft, esbuild, Dart Sass, Turbo, Bootstrap 5, and Luxon
- Devise authentication
- Minitest, RuboCop Rails Omakase, Brakeman, and bundler-audit

Runtime versions are pinned in `.ruby-version`, `.node-version`, `Gemfile.lock`, and `package-lock.json`.

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

The container prepares the database before starting, listens through Thruster on port 80, and exposes `GET /up` as its health endpoint. It assumes TLS is terminated by the reverse proxy and forces HTTPS for application traffic.

## Security model

Event access is limited to the organizer and invited users. Only invitees can submit availability, only against organizer-offered slots, and only the organizer can finalize a continuous slot range shared by every participant. Scheduling writes are transactional, database constraints back the key uniqueness and range invariants, authentication endpoints are rate limited, and production enables TLS, origin checking, CSP, filtered sensitive parameters, and host authorization.

Signed-in users can discover other members by display name so they can invite them to an event. Email addresses and other account details are not exposed in the member directory.

See the official [Ruby releases](https://www.ruby-lang.org/en/downloads/releases/) and [Rails maintenance policy](https://guides.rubyonrails.org/maintenance_policy.html) for the support status behind the pinned baseline.
