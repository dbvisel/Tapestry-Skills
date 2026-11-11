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
is "often more convenient." This path also needs no separate `client/.env` at
all: `docker-compose.local.yml`'s `client` build args pull everything (except
two hardcoded values, see below) from the same `--env-file ./server/.env` used
for everything else, since Compose maps the non-`VITE_`-prefixed keys
(`GOOGLE_CLIENT_ID`, `BUG_REPORT_FORM_URL`, ...) into `VITE_`-prefixed build
args itself. One of those two hardcoded values, `VITE_AUTH_PROVIDERS: google`,
isn't read from `server/.env` at all — if you need a different provider
locally (e.g. `ia`, which needs no OAuth client ID), change it to
`VITE_AUTH_PROVIDERS: ${AUTH_PROVIDERS}` and set `AUTH_PROVIDERS=ia` in
`server/.env`, matching the pattern `docker-compose-fnf.yml`-style production
deployments already use. Worth doing even for host-direct execution of
`server`/`worker`, since a worker container still needs real Chromium/ffmpeg/
ImageMagick (see `Dockerfile.server`'s `worker` stage) that running directly
on host has to provide itself. The container path also already handles the
Docker-networking problems a naive setup would hit:
`AWS_ENDPOINT_URL: http://host.docker.internal:8333` and a `--host-resolver-rules`
Puppeteer flag are already hardcoded into the `worker` service's own
`environment:` block, so the worker can reach the browser-facing SeaweedFS/
viewer addresses from inside its container without any extra configuration.

## Real server/.env.example gotchas (verified, not upstream-specific guesses)

A plain `cp server/.env.example server/.env` plus `cp client/.env.example
client/.env` does **not** work as shipped — four of `.env.example`'s own
default values crash or misbehave against `docker-compose.local.yml`'s actual
local containers. All four were found by directly starting the real server/
worker and reading the actual crash, not by inspection alone:

1. **`DB_USE_SSL=true`** genuinely enables TLS, and the plain
   `postgres:17-alpine` container `docker-compose.local.yml` brings up has no
   TLS configured — crashes with `Error: The server does not support SSL
   connections`. Set it blank or `false`.
2. **`REDIS_USE_TLS=true`** has the same shape: the plain `redis:7` container
   has no TLS either — crashes with `ioredis`'s `ETIMEDOUT` hanging on the TLS
   handshake. Set it `false`.
3. **`S3_CLEAN_UP_CRON_PATTERN=`** ships blank. `config.ts` declares
   `z.string().default('0 0 * * *')`, but Zod's `.default()` only applies when
   a key is `undefined` — an explicit empty string is still a defined value,
   so the default never kicks in and BullMQ crashes on boot with `Either
   .pattern or .every options must be defined for this repeatable job`. Give
   it a real cron pattern, e.g. `0 0 * * *`.
4. **`TAPESTRY_THUMBNAIL_GENERATION_DELAY=120_000`,
   `TAPESTRY_THUMBNAIL_GENERATION_TIMEOUT=300_000`, and
   `ITEM_THUMBNAIL_GENERATION_DELAY=120_000`** use underscore digit separators
   — valid as a JS source literal (which is how `config.ts` itself writes its
   own fallback defaults, e.g. `OptionalInt(150_000)`), but **not** as a
   `.env` file value. These go through `OptionalInt`
   (`core/src/data-format/schemas/common.ts`), which is `z.coerce.number()`
   under the hood — i.e. `Number("120_000")`, which is `NaN` in plain
   JavaScript, since underscore separators are only meaningful in source-code
   numeric literals, never in string-to-number coercion. (A YAML-based Compose
   `environment:` block is a different story — YAML 1.1's int grammar *does*
   treat underscores as digit separators and strips them before the value
   ever reaches a container, so the same-looking value can work there and
   fail here. If you're reconciling against a deployment that sets these in a
   Compose file directly, don't assume the same literal text works in a flat
   `.env` file.) Write these three as plain digits.

A fifth one isn't about `.env.example`'s defaults, but bites as soon as you
actually load the app in a browser: **`VIEWER_URL` drives more than page
URLs** — `server/src/socket/index.ts` uses it directly as Socket.io's CORS
`origin`, so if it doesn't match the origin the browser is actually loading
the client from, Socket.io's `/subscribe` polling fails with a CORS error
(live updates break, not just one request) even though the page itself loads
fine. `server/.env.example`'s own default (`http://localhost:5173`) is only
correct when running the client via the Vite dev server directly — set it to
`http://localhost:8080` instead if you're using the Docker-container client
path above.

## Stale generated CSS-module types break the build on long-lived checkouts only

`*.module.css.d.ts` files (generated by `vite-css-modules`, see "Configuration notes"
above) are gitignored - never committed, never cleaned up by `git checkout`/`git pull`/
switching branches, since git doesn't track them at all. On a checkout that's had the
Vite dev server (or a Docker client build - see below) run against several different
commits over time, a given component's `.d.ts` can go stale relative to its current
`.module.css`: verified directly as `tsc -b` failures like `Property 'playArea' does not
exist on type '{ root: string; controlBar: string; audioOnly: string; }'` even though
`.play-area`/`.play-button` genuinely exist in the current CSS file - the stale `.d.ts`
on disk just predates them being added. This is why the *exact same commit* can build
clean in a freshly-created checkout/worktree (no stale files ever existed there) and fail
in an older, long-lived one with no code difference at all - confirmed by reproducing
both outcomes from the identical commit. **Fix**: delete every `*.module.css.d.ts` under
`client/`/`core-client`/`viewer` (`find . -name "*.module.css.d.ts" -not -path
"*/node_modules/*" -delete`) and rebuild - they regenerate automatically, there's nothing
to lose. Don't waste time suspecting Docker's build cache first - `docker compose build
--no-cache` reproduces the exact same failure, since it's a stale *source-tree* file
Docker's `COPY` picks up, not a stale Docker *layer*.

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
