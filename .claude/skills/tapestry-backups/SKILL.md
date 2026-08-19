---
name: tapestry-backups
description: Back up a Tapestry installation's Postgres database and, if present, its MinIO object storage — via a bundled script safe to run interactively or on a schedule (cron/systemd timer) — plus how to restore
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["backup tapestry", "pg_dump tapestry", "backup-tapestry.sh", "minio backup"]
  - keywords: ["restore tapestry database", "cron backup docker", "systemd timer backup rootless docker"]
last_verified: 2026-08-19
---

Back up a Tapestry installation's Postgres database, and its MinIO object storage
volume if the install has one, using the bundled `scripts/backup-tapestry.sh`. Written
to be safe both run by hand and run unattended on a schedule.

## When to use this skill

- "Back up the Tapestry database" / "set up regular backups"
- Before any risky operation (upgrade, migration, config change) on a live install
- Setting up a cron job or systemd timer for recurring backups
- Restoring from a backup after data loss or a bad migration

## What it backs up, and how

- **Postgres**: `pg_dump -F c` (custom format) run inside the Postgres service
  (`db` by default — see below) via `docker compose exec -T`, streamed directly
  to a host file. `-T` disables pseudo-TTY allocation — required, since a TTY
  would corrupt the binary dump stream. This also avoids the
  dump-inside-container-then-`docker compose cp`-out dance; streaming straight
  to a host file is simpler and just as reliable.
- **MinIO** (only if that service — `minio` by default — is actually running):
  the script inspects the running container to find whatever volume is actually
  mounted at `/data`,
  rather than assuming a volume name. Compose derives volume names from the
  project name (the checkout directory name by default), which differs between
  installs. A throwaway `alpine` container then mounts that volume read-only and
  tars it.
- If no `minio` service is running (not part of this install, or the install
  uses a real AWS S3 backend instead — see `tapestry-local-dev-environment`),
  the MinIO step is skipped cleanly. That's not an error condition.
- **Retention**: keeps the newest `--keep` (default 14) backups of each kind and
  deletes older ones, so unattended runs don't grow disk usage without bound.
- Every step verifies its output is non-empty before declaring success, and the
  script exits non-zero if anything actually failed — important for a scheduler
  to be able to detect and alert on a broken backup.

## Usage

```bash
./backup-tapestry.sh                                              # run from the project dir, defaults for everything
./backup-tapestry.sh --project-dir ~/tapestries/tapestry-project  # run from elsewhere
./backup-tapestry.sh --keep 30 --backup-dir /mnt/backups/tapestry # more history, different location
COMPOSE_FILE=docker-compose-fnf.yml ./backup-tapestry.sh          # non-default compose filename
```

Defaults are generic (`docker-compose.yml`, `db`, `minio`, `.env` for
`DB_NAME`/`DB_USER`) — **don't assume they match any given install**, since the
compose filename in particular varies a lot (`docker-compose.local.yml`,
`docker-compose-fnf.yml`, `docker-compose.minio.yml`, ...). Override via
environment variables (`COMPOSE_FILE`, `ENV_FILE`, `DB_SERVICE`, `MINIO_SERVICE`,
`BACKUP_DIR`, `KEEP`) or the matching flags — same pattern as
`tapestry-visibility`'s `manage-tapestry-visibility.sh`. `--help` prints the full
option list.

Backups default to `~/tapestry-backups` — deliberately *outside* the project
checkout, so they don't show up as untracked clutter in `git status` and don't
get wiped by a `git clean` or checkout switch.

## Scheduling with cron (rootless Docker gotcha)

If Docker on this box is rootless (check `docker context show`, or see whether
`DOCKER_HOST` points at `/run/user/<uid>/docker.sock`), a plain cron job runs
outside your login session and **won't have that environment set**, and the
`systemd --user` instance running `dockerd` may not even be alive unless
lingering is enabled for that user:

```bash
loginctl show-user "$(whoami)" --property=Linger   # must show Linger=yes
loginctl enable-linger "$(whoami)"                  # if not — needs root
```

Then set the environment explicitly in the crontab (`crontab -e`), not just the
command:

```cron
XDG_RUNTIME_DIR=/run/user/1000
DOCKER_HOST=unix:///run/user/1000/docker.sock
0 3 * * * /path/to/backup-tapestry.sh --project-dir /home/you/tapestries/tapestry-project >> /home/you/tapestry-backups/backup.log 2>&1
```

(Replace `1000` with the real uid — `id -u`.) A `systemd --user` timer is a more
robust alternative to cron for the same reason `docker.service` itself runs that
way — it inherits the right environment naturally — but still needs lingering
enabled to run when nobody's logged in.

## Restoring (not scripted — deliberately)

Restoring is destructive, so it isn't automated here; do it by hand, and stop
`server`/`worker` first so nothing writes to the database or object store mid-restore.

**Postgres** (drops and recreates existing objects — make sure this is really
the dump you want; substitute your install's actual compose file, service name,
DB user/name):

```bash
docker compose -f <compose-file> exec -T <db-service> \
  pg_restore -U <db-user> -d <db-name> --clean --if-exists < pg_tapestries_TIMESTAMP.dump
```

**MinIO** (replaces the volume's entire contents with the backup):

```bash
docker run --rm -v <minio-data-volume>:/data -v "$(pwd)":/backup alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/minio_TIMESTAMP.tar.gz -C /data"
```

Find `<minio-data-volume>` the same way the backup script does —
`docker inspect <minio-container-id>` and look for the mount at `/data` — since
its name depends on the project/checkout directory name.

## Guardrails

1. **A local backup on the same VM is not disaster recovery** — copy backups
   off the box regularly (this script doesn't do that part; wire up your own
   `rsync`/`scp`/object-storage sync to wherever is appropriate for this install).
2. **Restoring is destructive and intentionally not scripted** — do it by hand,
   with `server`/`worker` stopped first.
3. **Rootless Docker + cron needs explicit environment and lingering enabled**
   (see above) — a cron job that silently never runs because `dockerd` wasn't
   reachable is worse than no cron job, since it looks fine until you need it.
4. **A missing MinIO container isn't a failure** — treat it as "this install
   uses a different S3 backend," not "something's broken," per
   `tapestry-local-dev-environment`'s AWS-vs-MinIO distinction.
5. **Don't hardcode volume names** — discover them from the running container;
   Compose derives them from the checkout directory name, which varies between
   installs.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/backup-tapestry.sh` | Backs up Postgres (`pg_dump`, custom format) and, if running, MinIO's data volume (`tar`), with retention pruning. Safe interactively or via cron/systemd timer; exits non-zero on failure. |
