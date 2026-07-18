# Catching App

> **Status:** completed collaborative Rails bootcamp project from 2021. It is preserved as team and learning evidence; its historical dependency graph has known security advisories and must not be exposed or deployed without a dedicated modernization.

Catching App coordinates a meeting across friends: a host creates an event, invites users, proposes time slots, guests submit their availability, and the host finalizes the agreed window from an authenticated dashboard.

## What it demonstrates

- Devise authentication and user profiles.
- Host-owned events and many-to-many guest invitations.
- Per-user availability through event-scoped time slots.
- Host-only final scheduling and invitee-only availability submission.
- PostgreSQL associations, server-rendered Rails views, and Bootstrap-era frontend assets.
- Dashboard aggregation of hosted and invited events.

## Ownership and collaboration

This was a three-person Le Wagon project with [Sedef Çakmak](https://github.com/sedcakmak) and [Ege Çakmak](https://github.com/Egecak). GitHub attributes substantial implementation work to Okan, including 11 merged pull requests and 47 of the newest 100 commits at the 2026-07-18 audit. [Okan's merged pull-request history](https://github.com/okturan/catching-app/pulls?q=is%3Apr+is%3Amerged+author%3Aokturan) is the durable attribution source; the repository is not presented as solo work.

## Historical local setup

The lockfile targets Ruby 2.7.3 and Rails 6.0.4 with PostgreSQL. This is a preserved historical toolchain, not a current support claim. If inspected, use an isolated local environment only and do not connect it to production credentials, real user data, or a public network.

```bash
git clone https://github.com/okturan/catching-app.git
cd catching-app
bundle install
yarn install
bin/rails db:setup
bin/rails server
```

The seeded accounts and passwords are fictional local sample data, not production credentials.

## Security boundary

The current source limits event viewing to hosts and invitees, final scheduling to the host, and availability submission to invited guests. Account and event deletion also clean dependent invitations and time slots. Run the dependency-free source contract without installing the legacy Rails stack:

```bash
ruby script/verify_archive_contract.rb
```

This static contract does not make the historical dependencies safe. The repository should stay unpinned and undeployed until the owner chooses either GitHub archival or a supported Ruby/Rails modernization with real model, request, and system tests plus zero critical/high dependency alerts.

## Origin

Created during the [Le Wagon coding bootcamp](https://www.lewagon.com).
