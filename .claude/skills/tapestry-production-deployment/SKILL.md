---
name: tapestry-production-deployment
description: Update a customized production VM deployment of asteasolutions/tapestry-project (fork-and-merge workflow, docker-compose-fnf.yml specifics, Vault approle, backups) without repeating the 2026-08-12 outage caused by building images against live traffic
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry-project deployment", "docker-compose-fnf.yml", "archive-version-updated", "VM update", "tapestries.archive.org"]
  - keywords: ["fork upstream merge", "prisma migrate deploy", "manage-tapestry-visibility.sh"]
  - keywords: ["docker build live traffic", "resource contention", "vault approle seed"]
last_verified: 2026-08-12
---

Process for updating a **customized, forked** production deployment of `tapestry-project`
(e.g. a VM running under a personal fork with local-only customizations layered on top of
upstream `main`) — merging in upstream changes, rebuilding, and rolling out, without the
resource-contention failure mode that has already caused one real outage.

## When to use this skill

- "Update the production VM to the latest upstream tapestry-project"
- Merging upstream `main` into a customized deployment branch
- Rebuilding/redeploying `docker-compose-fnf.yml` on a live server
- Managing a live tapestry's visibility from the command line
- Diagnosing why a VM went unreachable during/after a deploy

## Why this deployment is structured as a fork, not a vanilla checkout

- No push access to `asteasolutions/tapestry-project` — all work happens against a
  personal fork (remote name matches the fork owner, e.g. `dbvisel`).
- VM-specific customizations (MinIO-based deployment config, IA-specific auth/UX
  tweaks, CSP/cache-control headers) live as **commits on a branch**
  (`archive-version`, and successors like `archive-version-updated`), not on `main` —
  so upstream improvements can keep merging in over time instead of diverging forever.
- Some customization files don't exist upstream at all — `docker-compose-fnf.yml`,
  `Dockerfile.client-fnf`, `manage-tapestry-visibility.sh` — so they never conflict
  during a merge; they carry forward automatically.
- `.env` is gitignored and lives only on the VM — never touched by any of this.

The full step-by-step is in `references/updating-process.md` (verbatim copy of the
in-repo `deployment/UPDATING.md`). What follows here is the load-bearing facts and the
lesson from the one time this went wrong.

## One-time facts worth knowing

- **Compose project name is derived from the checkout directory name**
  (`docker-compose-fnf.yml` sets no explicit `name:`), which determines the actual
  volume names: `<dirname>_pgdata`, `<dirname>_vault-data`, `<dirname>_minio-data`.
  **Never rename the checkout directory** or add a `-p`/`name:` override without
  deliberately migrating those volumes — otherwise `docker compose up` silently
  creates fresh, empty volumes instead of reusing the real data.
- **`server`'s `start:api` runs `prisma migrate deploy` automatically on container
  boot** (see `tapestry-server-worker`) — pulling in upstream schema migrations and
  restarting `server` *is* the deploy step, no separate migration command needed. This
  also means: **check every incoming migration for destructive changes** (dropped
  columns/tables, a non-nullable column added without a default) *before* merging and
  restarting — those need a manual, data-safe migration plan instead of a blind
  `up -d`.
- `docker-compose-fnf.yml` differs from the local-dev `docker-compose.minio.yml` in
  ways that matter operationally: it has no `minio`/`mc` Compose *profile* gating (both
  services always run), MinIO's ports are shifted (`3202` API instead of `9000`,
  `9001` console — check `AWS_ENDPOINT_URL`/`AWS_INTERNAL_ENDPOINT_URL` in the VM's
  `.env` match), the `server` port is remapped (`3201:3000`), and it has commented-out
  Traefik labels/networks for a reverse-proxy setup that isn't currently active. Don't
  assume the two compose files are interchangeable beyond structure.
- Vault runs the same self-initializing entrypoint pattern as local dev (see
  `tapestry-local-dev-environment`) — persistent file storage, auto-unseal on boot,
  idempotent AppRole seeding from `VAULT_ROLE_ID`/`VAULT_SECRET_ID`. **`down` (no `-v`)
  preserves it; `down -v` wipes the volume and forces re-initialization**, which would
  orphan every existing per-user secret stored under `secret/data/users/*`.

## The update process (see `references/updating-process.md` for full commands)

1. **Back up first** — `pg_dump` the database and tar the MinIO data volume, copy both
   off the VM if possible. Untracked/gitignored, safe to leave in the checkout otherwise.
2. **Merge upstream in a separate clone, not on the VM.** The VM has no push access to
   upstream and often no direct reachability from your dev machine either. On the VM:
   commit and push whatever's uncommitted to your fork. Elsewhere: fetch both remotes,
   branch from the VM's customization branch, merge `origin/main`, resolve conflicts by
   checking what *each side* actually changed relative to the merge base (not just
   picking one side blindly), then `npm ci && npm run -w server prisma:generate && npm run lint`
   before pushing the merged branch back to your fork.
3. **Pull the merged branch onto the VM**, sanity-check `.env` is still present (git
   never touches it).
4. **Rebuild and restart** — `docker compose -f docker-compose-fnf.yml build` then
   `up -d`. Same project/volume names, so `pgdata`/`vault-data`/`minio-data` are reused;
   only containers get recreated.
5. **Verify** — `ps`, tail `server`/`worker` logs, then check the live site: login
   works, an existing tapestry with items loads/renders, thumbnail/webpage-screenshot
   generation still works (exercises MinIO + Puppeteer + Vault together).
6. **Rollback** is just checking out the previous branch and rebuilding — data is never
   at risk either way, since volumes aren't touched by branch switches. Only restore a
   DB backup if a migration actually corrupted data (additive migrations, the common
   case, won't).

## Lesson from the 2026-08-12 outage — don't build against live traffic

Running `docker compose -f docker-compose-fnf.yml build` on the VM **while the
production containers were still live and serving traffic** caused the VM to become
completely unreachable (SSH timeouts, site down) partway through the build. Suspected
cause: resource contention — the build compiles native deps for Puppeteer/Chromium,
ImageMagick, and ghostscript across `worker`/`server`/`client` images simultaneously,
competing with the live containers for CPU/memory/disk.

**Before rebuilding on a production VM with live traffic**:
- Take backups first regardless (step 1 above) — they're cheap insurance and were the
  reason the actual outage was a non-event data-wise.
- Check `free -h`, `df -h`, and `docker system df` beforehand to know your headroom.
- Prefer building during a low-traffic window, or building on a separate machine and
  shipping images, if the VM's resources are tight — a heavy multi-service build
  competing with live containers is the specific failure mode that caused the outage,
  not building in general.
- If a build-triggered outage happens anyway: check `dmesg -T | grep -i "killed process\|out of memory"`
  to confirm OOM as the cause before assuming something else broke.

## Operational tool: `manage-tapestry-visibility.sh`

VM-only script (not upstream), run from the repo directory on the server. Lists
tapestries (optionally filtered by title/slug/owner email) and interactively changes
one's `visibility` (`private`/`link`/`public` — `public` makes it appear in the
"Samples" list every client sees on startup). Runs against the `db` service via
`docker compose exec`, defaults to `docker-compose-fnf.yml`/`.env`/`db`/`tapestries`/
`tapestries`, all overridable via env vars. Requires explicitly typing `yes` to confirm
before applying — safe to run without fear of an accidental one-key change.

```bash
./manage-tapestry-visibility.sh            # list everything, then pick one
./manage-tapestry-visibility.sh <search>   # filter by title / slug / owner email
```

## Guardrails

1. **Never rebuild against live traffic without checking resource headroom first** —
   see the outage lesson above.
2. **Never rename the checkout directory or override the Compose project name** without
   a deliberate volume migration.
3. **Treat every incoming Prisma migration as a live-data hazard** before restarting
   `server` — check for destructive changes first (see `tapestry-server-worker`).
4. **`.env` is VM-local and gitignored** — never expect it to arrive via git, never
   commit it, and confirm it's still present after any branch switch.
5. **Merge upstream in a separate clone with push access**, never directly on the VM.
6. See `tapestry-local-dev-environment` for the MinIO/Vault self-init mechanics shared
   between local dev and this deployment, and `tapestry-server-worker` for what
   actually runs inside `server`/`worker`.
