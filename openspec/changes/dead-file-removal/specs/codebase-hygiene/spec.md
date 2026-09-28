## ADDED Requirements

### Requirement: Only enabled Devise modules have views
The repository SHALL contain Devise views and mailer templates only for modules `User` enables (`database_authenticatable`, `registerable`, `recoverable`, `rememberable`, `validatable`). Views for confirmations, unlocks, email-changed and password-changed notifications, and the unused `devise/shared/_error_messages` partial SHALL NOT exist.

#### Scenario: Unused Devise views are gone
- **WHEN** the tree is listed
- **THEN** `app/views/devise/confirmations`, `app/views/devise/unlocks`, `app/views/devise/mailer/confirmation_instructions.html.erb`, `unlock_instructions.html.erb`, `email_changed.html.erb`, `password_change.html.erb` and `app/views/devise/shared/_error_messages.html.erb` are absent, and password reset mail still renders

### Requirement: Stylesheets contain only selectors the markup uses
`_avatar.scss` SHALL NOT exist and SHALL NOT be imported; `.banner h1`, `.banner h2`, `.banner h3`, `.banner p`, `.banner-logo`, `.skewed`, `.btn-success`, `.btn-confirm` and `.btn-activity` rules SHALL be removed; `npm run build:css` SHALL succeed.

#### Scenario: CSS builds without the dead partials
- **WHEN** `npm run build:css` runs
- **THEN** it exits 0 and the output contains no `.avatar` or `.btn-confirm` rule

### Requirement: Scaffold leftovers and placeholders are gone
`config/initializers/inflections.rb`, `.browserslistrc`, `lib/templates/erb/scaffold/_form.html.erb`, `storage/.keep`, `app/controllers/concerns/.keep`, `app/models/concerns/.keep`, `lib/assets/.keep`, `lib/tasks/.keep`, `test/fixtures/files/.keep`, `test/helpers/.keep`, `test/mailers/.keep` and `.keep` files inside populated `test/` directories SHALL NOT exist. `config/locales/en.yml` SHALL contain no `hello` key. The application SHALL still boot and eager load.

#### Scenario: Eager loading after removal
- **WHEN** `bin/rails zeitwerk:check` runs
- **THEN** it reports that all is good

### Requirement: Dead user columns are dropped reversibly
A migration SHALL remove `users.address`, `users.phone_number` and `users.time_zone_name` and SHALL restore them (as text, string, string) on `down`. The migration round-trip test SHALL include it.

#### Scenario: Round trip with the users migration
- **WHEN** the migration round-trip test runs all migrations down and up
- **THEN** the schema dump equals `db/schema.rb` and `users` has no `address`, `phone_number` or `time_zone_name` column

### Requirement: No credentials file without a key
`config/credentials.yml.enc` SHALL NOT exist; production SHALL sign with `SECRET_KEY_BASE`, which the Dockerfile precompile and the CI smoke test already use.

#### Scenario: Boot without credentials
- **WHEN** the production image boots with `SECRET_KEY_BASE` set and no `RAILS_MASTER_KEY`
- **THEN** `/up` responds 200

### Requirement: Static error pages say what happened
`public/500.html` SHALL describe a server error, `public/404.html` a missing page, both with valid HTML (no elements inside `<head>`), the current product name and no year. `public/422.html` stays as generated.

#### Scenario: The 500 page is not a 404
- **WHEN** `public/500.html` is read
- **THEN** it contains "500" and does not contain "404" or "2012"

### Requirement: Config carries no dead settings
`config/initializers/devise.rb` SHALL NOT set `reconfirmable`; the CI `test` job SHALL NOT set `APP_HOST`; `.dockerignore` SHALL NOT list paths that do not exist.

#### Scenario: CI still passes without APP_HOST in the test job
- **WHEN** the workflow runs after the change
- **THEN** all five jobs pass
