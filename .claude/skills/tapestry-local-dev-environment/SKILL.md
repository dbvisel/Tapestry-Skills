---
name: tapestry-local-dev-environment
description: Run asteasolutions/tapestry-project locally the way upstream documents (npm workspaces, per-workspace .env files, SeaweedFS/Redis/Vault via docker-compose.local.yml, Vite dev server)
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry-project", "tapestries", "local dev", "run tapestry locally", "npm run local", "docker-compose.local.yml"]
  - keywords: ["SeaweedFS", "Vault dev", "vite dev server", "server/.env", "client/.env"]
last_verified: 2026-11-11
---

Run Tapestries locally. **`asteasolutions/tapestry-project` (`main`) is the definitive
upstream** — this skill documents that flow, which is the only local-dev flow that
exists on any checkout, fork included: `dbvisel/main` carried a fork-specific
Docker+MinIO installer variation until 2026-11-11, when it was retired and `dbvisel/main`
was synced to be an exact mirror of `asteasolutions/main`.

## When to use this skill

- "Run tapestry-project locally" / "start Tapestry for local development"
- Setting up Postgres/Redis/SeaweedFS/Vault for local dev
- Choosing/configuring an auth provider (`ia` or `google`) locally
- Diagnosing a CSP error — on `main` this is not applicable, since `client/index.html`
  has no CSP `<meta>` tag at all; if you're seeing one, you're on a customized branch
  (e.g. an archive.org production-deployment branch) outside this skill's scope

## Prerequisites

- Node v22+ (a version manager like `nvm` is convenient).
- Docker, for the infrastructure containers (Postgres/Redis/SeaweedFS/Vault) —
  `npm run *:start` scripts wrap `docker compose` for these.
- A checkout of `tapestry-project` (this repo is fork-friendly: work happens
  against a personal fork with a remote named after your GitHub username,
  `origin` pointing at `asteasolutions/tapestry-project`).

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

**Auth provider(s)** — set `VITE_AUTH_PROVIDERS` in `client/.env` to a
comma-separated list drawn from `ia`/`google` (the only two implemented — see
`tapestry-client-features`), e.g. `ia` or `google,ia`. The app renders a login
menu when more than one is configured. `ia` needs no further config; `google`
needs a real OAuth client ID in both `GOOGLE_CLIENT_ID` (`server/.env`) and
`VITE_GOOGLE_CLIENT_ID` (`client/.env`).

## 2. Start infrastructure

Root `package.json` provides npm scripts that wrap `docker compose -f
docker-compose.local.yml --env-file ./server/.env up -d --build <service>`:

```bash
npm run local       # shorthand for db:start + redis:start + vault:start
npm run s3:start     # SeaweedFS as a persistent S3-compatible store (see note below)
```

Individually: `db:start`, `redis:start`, `s3:start`, `vault:start`,
`worker:start` (plus matching `*:logs` for each).

- **Postgres** — standard, matches `server/.env`'s `DB_*` vars.
- **Redis 7** — used for caching and BullMQ job scheduling (see
  `tapestry-server-worker`).
- **SeaweedFS** — upstream's local S3-compatible store, **not MinIO or
  LocalStack**. `npm run s3:start` also creates the bucket and its CORS rules.
  Unlike LocalStack's free tier (upstream's previous local S3 story), data
  **persists** across restarts.
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

Upstream's `client/index.html` (checked `asteasolutions/tapestry-project`
`main`) has **no `Content-Security-Policy` meta tag at all** — nothing to
violate, nothing to patch. If you're hitting CSP errors on `localhost`, you
are not on a plain upstream checkout; see the next section.

## Guardrails

1. **Treat `asteasolutions/tapestry-project` `main` as ground truth.** Verify
   any fork-specific claim (file presence, CSP, installer scripts) against the
   actual branch/checkout in front of you before assuming it generalizes.
2. **Env files are per-workspace upstream** (`server/.env`, `client/.env`) —
   don't assume a single root `.env` unless you've confirmed you're on a fork
   variation that uses one.
3. **SeaweedFS, not MinIO or LocalStack, is upstream's local S3 story** — and
   unlike LocalStack's free tier, it persists across restarts.
4. **`ia`, `google`, `orcid`, `wikimedia`, and `bluesky` are all real auth
   providers on upstream `main`** — see `tapestry-auth-providers`.
5. **Don't rename the checkout directory** if using Docker Compose for
   anything — Compose derives the project/volume names from it, and renaming
   orphans existing data into fresh empty volumes.
