## Context

Everything here was identified by the repository audit and confirmed unused by grep, by the Devise module list in `app/models/user.rb`, and by the CI configuration. Nothing is deployed, so the column drop has no data to preserve.

## Goals / Non-Goals

**Goals:** remove what nothing reads; make the error pages truthful; keep every migration reversible; keep CI green.

**Non-Goals:** the Cloudinary-hosted images and videos (visual-redesign), remote branch cleanup, dependency updates (ci-regime).

## Decisions

- Delete `credentials.yml.enc` rather than rotate: no key exists in the repo or its documentation, the Dockerfile and CI already sign with `SECRET_KEY_BASE`, and Rails 8 needs no credentials file. Alternative: keep and document `RAILS_MASTER_KEY`, rejected because nobody can produce the key.
- Trim dead selectors instead of deleting `_banner.scss` and `_buttons.scss`: both files also hold live rules.
- Write the 500 page by hand in the style of the 404 page so the two match.
- One migration for the three `users` columns, explicit `up`/`down` with the original types.

## Risks / Trade-offs

- [A removed Devise view is requested] -> Devise falls back to its gem views for modules that are enabled; disabled modules have no routes.
- [Column drop on a database with data] -> `down` restores the columns without data; acceptable because no production data exists.

## Migration Plan

One PR on the product branch. Steps: delete files, edit stylesheets and config, add the migration, regenerate `db/schema.rb`, update the round-trip test's migration list, run `bin/ci`.

## Open Questions

- Whether to delete the 27 merged remote branches on origin (safe, but outside the working tree).
