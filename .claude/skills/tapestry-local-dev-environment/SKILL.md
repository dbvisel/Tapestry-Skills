---
name: tapestry-local-dev-environment
description: Run internetarchive/tapestry-project locally the way upstream documents (npm workspaces, per-workspace .env files, LocalStack/Redis/Vault via docker-compose.local.yml, Vite dev server) — plus notes on a Docker+MinIO installer variation that exists only on some forks
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry-project", "tapestries", "local dev", "run tapestry locally", "npm run local", "docker-compose.local.yml"]
  - keywords: ["LocalStack", "Vault dev", "vite dev server", "server/.env", "client/.env"]
  - keywords: ["MinIO installer", "setup.sh", "CSP", "Content-Security-Policy", "connect-src"]
last_verified: 2026-08-19
---

Run Tapestries locally. **`internetarchive/tapestry-project` (`main`) is the definitive
upstream** — this skill documents that flow first. A personal fork (e.g.
`dbvisel/tapestry-project`) may carry its own branches with real but *non-default*
variations (a Docker+MinIO installer, archive.org-specific customizations); those are
covered separately at the end and should not be assumed to apply to a plain upstream
checkout.

## When to use this skill

- "Run tapestry-project locally" / "start Tapestry for local development"
- Setting up Postgres/Redis/LocalStack/Vault for local dev
- Choosing/configuring an auth provider (`ia` or `google`) locally
- Diagnosing a CSP error — see the last section; on upstream `main` this is not
  applicable, since upstream's `client/index.html` has no CSP `<meta>` tag at all

## Prerequisites

- Node v22+ (a version manager like `nvm` is convenient).
- Docker, for the infrastructure containers (Postgres/Redis/LocalStack/Vault) —
  `npm run *:start` scripts wrap `docker compose` for these.
- A checkout of `tapestry-project` (this repo is fork-friendly: work happens
  against a personal fork with a remote named after your GitHub username,
  `origin` pointing at `internetarchive/tapestry-project`).

## 1. Install and configure

```bash
npm install   # at repo root — installs every workspace (core, core-client, shared, server, client, viewer)
cp server/.env.example server/.env
cp client/.env.example client/.env
```

Env config is **per-workspace**, not a single root `.env` — `server/.env` for
backend/runtime config, `client/.env` for frontend/build-time config (Vite
inlines `VITE_*` vars at build time). Fill in `server/.env`'s `SECRET_KEY`
(any random string) and, if using Google auth, `GOOGLE_CLIENT_ID` in both
files. Everything else in the `.example` files works for local dev as shipped.

**Auth provider** — set `VITE_AUTH_PROVIDER` in `client/.env` to `ia` or
`google` (the only two implemented — see `tapestry-client-features`). `ia`
needs no further config; `google` needs a real OAuth client ID in both
`GOOGLE_CLIENT_ID` (`server/.env`) and `VITE_GOOGLE_CLIENT_ID` (`client/.env`).

## 2. Start infrastructure

Root `package.json` provides npm scripts that wrap `docker compose -f
docker-compose.local.yml --env-file ./server/.env up -d --build <service>`:

```bash
npm run local              # shorthand for db:start + redis:start + vault:start
npm run localstack:start   # S3-compatible storage emulator (see note below)
```

Individually: `db:start`, `redis:start`, `localstack:start`, `vault:start`,
`worker:start` (plus matching `*:logs` for each).

- **Postgres** — standard, matches `server/.env`'s `DB_*` vars.
- **Redis 7** — used for caching and BullMQ job scheduling (see
  `tapestry-server-worker`).
- **LocalStack** — upstream's recommended local S3 emulator, **not MinIO**.
  `AWS_ENDPOINT_URL=http://s3.localhost.localstack.cloud:4566` (already set in
  `server/.env.example`). **The free tier doesn't persist data — restarting
  the container wipes all Tapestry assets.** MinIO is mentioned in upstream's
  README only as "another alternative... or any other S3-compatible service,"
  not as something upstream actually wires up anywhere.
- **Vault** — optional. Uses `deployment/vault/start-dev.sh` (a real, upstream
  dev-mode script: `vault server -dev` with a hardcoded root token, then seeds
  an AppRole policy scoped to `secret/data/users/*` from `VAULT_ROLE_ID`/
  `VAULT_SECRET_ID`). If you skip it, everything works except AI Chat
  (user-provided LLM API keys, stored in Vault — see `tapestry-server-worker`).
  Don't confuse this with `deployment/vault/README.md`, which documents a
  separate AWS-KMS/SSM-backed production Vault flow for a specific hosted
  deployment — irrelevant to local dev either way.

## 3. Run the app

Migrations + API server:

```bash
cd server
npm run prisma:generate
npm run prisma:migrate
npm start
```

Worker (separate terminal, same codebase/different entrypoint — see
`tapestry-server-worker`):

```bash
cd server
npm run start:worker:dev
```

Needs `chromium`, `ffmpeg`, and `imagemagick` installed on the host (see the
`worker` stage of `Dockerfile.server` for the exact package list) — thumbnail
generation uses Puppeteer.

Client (separate terminal — **Vite dev server, not a Docker/nginx build**):

```bash
cd client
npm start
```

Defaults to `http://localhost:5173` (matches `server/.env.example`'s
`VIEWER_URL=http://localhost:5173`) — not `:8080`. If you see `:8080`
referenced anywhere, that's the Docker-build port used by `docker-compose.local.yml`'s
`client` service (or a fork's variation), not the Vite dev server.

`server`/`worker`/`client` can alternatively be run as Docker containers via
the same `docker-compose.local.yml` (`Dockerfile.server`, `Dockerfile.client`)
instead of directly on the host — upstream's README calls this out as more of
a deployment-shaped option; for day-to-day local dev, running them directly
is "often more convenient."

## No CSP issue on upstream

Upstream's `client/index.html` (checked `internetarchive/tapestry-project`
`main`) has **no `Content-Security-Policy` meta tag at all** — nothing to
violate, nothing to patch. If you're hitting CSP errors on `localhost`, you
are not on a plain upstream checkout; see the next section.

## If you're on a fork with the Docker+MinIO installer variation

Some forks (e.g. a `dbvisel/main` branch, ~20 commits ahead of upstream `main`)
add an alternative, fully-Dockerized local-dev path: `setup.sh`, a single
root `.env.sample`/`.env` (instead of per-workspace `server/.env`/`client/.env`),
`docker-compose.minio.yml`, and `Dockerfile.client-minio` — using MinIO instead
of LocalStack, and building the client into an nginx image instead of running
Vite dev server. If you have these files, they are **not part of
`internetarchive/tapestry-project`** — they're a specific fork's addition. This
skill bundles copies if you need them: `scripts/setup.sh` is interactive
(`./setup.sh` or `./setup.sh --no-start`), regenerates missing secrets, and
idempotently re-runs against an existing `.env`; the config templates it reads
(`.env.sample`, `docker-compose.minio.yml`, `Dockerfile.client-minio`) live
under `assets/` since they aren't executable scripts themselves.

**Separately**, some forks layer archive.org-specific production
customizations on top of that (e.g. `archive-version`/`archive-version-updated`
branches) — including a hardcoded CSP `<meta>` tag in `client/index.html`
pointing at production archive.org domains. **The CSP problem below only
happens if you're on one of those specific branches** (or have otherwise
picked up that customized `client/index.html`) — check for the tag first:

```bash
grep -n "Content-Security-Policy" client/index.html   # empty output = no issue
```

If it's present and you're running it against `localhost` (via the MinIO
Docker installer above), you'll see errors like:

```
Connecting to 'http://localhost:3000/api/sessions?...' violates the following
Content Security Policy directive: "connect-src 'self' https://archive.org ...".
```

Fix by editing the CSP `<meta>` tag (around line 6-7 of `client/index.html`)
to add local origins, then rebuild just the client:

| Directive | What broke | Add |
|---|---|---|
| `connect-src` | REST calls to the API | `http://localhost:3000` |
| `connect-src` | Socket.io (live tapestry updates / RTC signaling — `client/src/pages/tapestry/view-model/socket-manager.ts`) | `ws://localhost:3000` |
| `connect-src` | Uploading files: direct PUT to MinIO via presigned URL, and PDF.js fetching `blob:` URLs when rendering an uploaded PDF | `blob:` and `http://localhost:9000` |
| `img-src` | Viewing an uploaded image (direct GET from MinIO via presigned URL) | `http://localhost:9000` |
| `media-src` | Viewing/playing an uploaded video or audio asset | `http://localhost:9000` |

The `blob:` gap in `connect-src` looks like a genuine bug in that CSP
regardless of environment — it never allowed `connect-src blob:` even for
production, so PDF viewing was presumably already broken there too. The
`localhost:3000`/`localhost:9000` origins, by contrast, are local-dev-only —
revert them (or template the CSP from env vars) before that checkout is ever
used to build a production image.

```bash
docker compose -f docker-compose.minio.yml --profile minio up -d --build client
```

Hard-refresh the browser afterward — the old bundle may be cached.

## Guardrails

1. **Treat `internetarchive/tapestry-project` `main` as ground truth.** Verify
   any fork-specific claim (file presence, CSP, installer scripts) against the
   actual branch/checkout in front of you before assuming it generalizes.
2. **Env files are per-workspace upstream** (`server/.env`, `client/.env`) —
   don't assume a single root `.env` unless you've confirmed you're on a fork
   variation that uses one.
3. **LocalStack, not MinIO, is upstream's local S3 story** — and it doesn't
   persist across restarts on the free tier. Don't assume asset data survives
   a `localstack:start` restart.
4. **Only `ia` and `google` are real auth providers**, on any branch checked
   so far.
5. **Don't rename the checkout directory** if using Docker Compose for
   anything — Compose derives the project/volume names from it, and renaming
   orphans existing data into fresh empty volumes.

## Bundled scripts and assets (fork-variation installer, not upstream)

| File | Purpose |
|---|---|
| `scripts/setup.sh` | Interactive installer for the Docker+MinIO variation: generates `.env` from `.env.sample`, builds, starts, and health-checks the stack |
| `assets/.env.sample` | The secret-free template `setup.sh` reads (every credential blank) |
| `assets/docker-compose.minio.yml` | The MinIO-backed local Compose stack (client/server/worker/db/redis/vault/minio/mc) |
| `assets/Dockerfile.client-minio` | Client image build used by the above compose file |
