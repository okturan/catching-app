## Why

The 2026-09-02 audit listed files, columns and config that nothing reads: Devise views for modules the app does not enable, a stylesheet with no matching markup, comment-only initializers, a scaffold template from the 2021 template, placeholder `.keep` files in populated directories, three dead `users` columns, an encrypted credentials file with no key, and a 500 page that shows a 404. They cost review attention on every change and mislead newcomers about what the app does.

## What Changes

- Delete unused Devise views and mailer templates (confirmations, unlocks, email_changed, password_change, `_error_messages`).
- Delete `_avatar.scss` and its import; trim selectors in `_banner.scss` and `_buttons.scss` that match no markup.
- Delete `config/initializers/inflections.rb` (comments only), the `hello` key in `config/locales/en.yml`, `.browserslistrc`, `lib/templates/erb/scaffold/_form.html.erb`, `storage/.keep`, empty `concerns/.keep` and `lib/*/.keep`, and `.keep` files in populated test directories.
- **BREAKING (schema)** Drop `users.address`, `users.phone_number` and `users.time_zone_name` in a reversible migration.
- Delete `config/credentials.yml.enc`: no key is tracked or documented; production signs with `SECRET_KEY_BASE`.
- Replace `public/500.html` (a copy of the 404 page) with a real 500 page; fix the year on `public/404.html`; move the misplaced markup out of `<head>`.
- Remove `config.reconfirmable` from the Devise initializer (no `:confirmable`), the unused `APP_HOST` from the CI test job, and stale `.dockerignore` entries.

## Capabilities

### New Capabilities

- `codebase-hygiene`: what the repository must not contain, and how the static error pages behave.

### Modified Capabilities

(none)

## Impact

Views, stylesheets, initializers, locales, `db/schema.rb` (one migration), `public/*.html`, `.github/workflows/ci.yml`, `.dockerignore`. No route or behavior change beyond the error pages. The migration round-trip test covers the new migration.
