## 1. Files

- [x] 1.1 Delete unused Devise views and mailer templates and the `_error_messages` partial
- [x] 1.2 Delete `_avatar.scss`, remove its import, trim dead selectors in `_banner.scss` and `_buttons.scss`
- [x] 1.3 Delete inflections initializer, `hello` locale key, `.browserslistrc`, scaffold template, `storage/.keep`, empty `.keep` files, `.keep` files in populated test directories
- [x] 1.4 Delete `config/credentials.yml.enc`

## 2. Schema

- [x] 2.1 Migration dropping `users.address`, `users.phone_number`, `users.time_zone_name` with typed `down`; regenerate `db/schema.rb`; add it to the round-trip test

## 3. Pages and config

- [x] 3.1 Write a real `public/500.html`, fix `public/404.html` (year, markup in head)
- [x] 3.2 Remove `config.reconfirmable`, the CI test job `APP_HOST`, and stale `.dockerignore` entries

## 4. Verify

- [x] 4.1 `bin/ci` green locally; push; CI green on the PR (run 33954666370)
