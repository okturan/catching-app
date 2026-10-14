# Operating catching.app

## Hosting

- **Host:** `hub`, 178.104.118.172 (Hetzner, nbg1, Ubuntu 24.04), shared with other apps under the plan in
  `~/code/backlog/hetzner-consolidation.md`. Moved there from its own server (178.104.14.208) on 2026-10-15.
- **DNS:** Cloudflare, DNS only. `catching.app` A → hub; `www` CNAME → apex. The app redirects `www` to the apex.
- **Routing:** kamal-proxy on hub owns 80/443 for every app and routes `catching.app` and `www.catching.app` here.
- **Deploys:** `.github/workflows/deploy.yml` after CI passes on `master`, as root over SSH with the key
  marked `catching-app-actions-deploy` in hub's `authorized_keys`. Images build on the GitHub runner, never on hub.

## Containers and limits

| Container | Limits | Data |
|---|---|---|
| `catching-app-web-*` (Puma + Solid Queue + Thruster) | memory 1g, cpus 1 | none |
| `catching-app-db` (postgres:17 accessory) | memory 512m, cpus 0.5 | `/srv/catching-app/postgres` |

The database is reachable only on the Docker `kamal` network as `catching-app-db`; it has no published port.

## Backups

`/usr/local/bin/catching-app-backup` runs nightly at 03:30 from `/etc/cron.d/catching-app-backup` on hub and
writes `pg_dump -Fc` files to `/srv/catching-app/backups`, keeping 14 days. Hetzner backups of hub are the
second layer.

Restore a dump (stops the app for the length of the restore):

```bash
export KAMAL_REGISTRY_PASSWORD=$(gh auth token)
bin/kamal app stop
ssh root@178.104.118.172 'docker exec catching-app-db dropdb -U catching_app --force catching_app_production &&
  docker exec catching-app-db createdb -U catching_app catching_app_production &&
  docker exec -i catching-app-db pg_restore -U catching_app -d catching_app_production --no-owner' < catching_app_YYYY-MM-DD.dump
bin/kamal app boot
```

## Schedulers

Solid Queue runs inside Puma. The only host job is the nightly backup above.
