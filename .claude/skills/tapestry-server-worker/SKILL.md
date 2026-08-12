---
name: tapestry-server-worker
description: Add or modify backend functionality in asteasolutions/tapestry-project's server/worker — REST resources, Prisma models/migrations, BullMQ jobs, S3/MinIO presigning, Vault-backed per-user secrets, auth providers, and Socket.io live updates
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry-project server", "tapestry-project worker", "server/src", "REST resource", "base-resource.ts"]
  - keywords: ["Prisma", "BullMQ", "thumbnail generation", "S3 presigned URL", "MinIO", "Vault", "user secret"]
  - keywords: ["socket.io server", "tapestry-updated", "LISTEN NOTIFY", "auth provider server"]
last_verified: 2026-08-12
---

Backend conventions for `tapestry-project`'s `server`/`worker` — where things live, how
a REST resource is wired end-to-end, how the job queue and asset storage work, and
where secrets actually live (Postgres only ever stores a masked display value).

## When to use this skill

- Adding or changing a REST endpoint/resource on the server
- Adding a Prisma model/migration, or reasoning about what's safe to migrate
- Adding a background job (thumbnailing, cleanup, import) or changing an existing one
- Working with S3/MinIO asset URLs, or Vault-backed per-user secrets
- Adding an auth provider, or touching session/JWT verification
- Anything involving live tapestry updates over Socket.io

## Monorepo shape

Root `package.json` workspaces: `core`, `core-client`, `client`, `server`, `shared`, `viewer`.
For backend work, the two that matter:

- **`core`** (`tapestry-core`) — pure TS: data-format Zod schemas, generic utils, no
  DB/server knowledge.
- **`shared`** (`tapestry-shared`) — the API *contract*: REST endpoint descriptors
  (method/path/Zod schema) in `shared/src/data-transfer/resources/{types.ts,base.ts,dtos/*,schemas/*}`,
  Socket.io event typing in `shared/src/data-transfer/socket/types.ts`, WebRTC signaling
  types in `rtc-signaling/types.ts`. Server and client both import this verbatim — when
  you add a field to a DTO or a new resource, this is where it starts.

`Dockerfile.server` builds **both** `server` and `worker` from the same codebase in one
file: stage `server` (`npm ci` at repo root, copies `core/`, `shared/`, `server/`, runs
`prisma:generate`, `CMD ["start:api"]`) and stage `worker` (`COPY --from=server /app /app`
— identical `node_modules`/build — plus Chromium/ffmpeg/imagemagick/ghostscript for
Puppeteer thumbnailing, `CMD ["start:worker"]`). So `server` and `worker` are the same
code, different entrypoint script and different native deps baked in. Server imports
`core`/`shared` by workspace package name (`tapestry-core/src/...`, `tapestry-shared/src/...`),
not relative paths that reach outside `server/`.

## `server/src/` layout

| Dir/file | Purpose |
|---|---|
| `index.ts` | Express bootstrap: mounts resource routers under `/api`, creates the HTTP server, inits Socket.io, Sentry, Bull-Board, schedules the S3 cleanup cron |
| `config.ts` | Single source of truth for env vars — a frozen, Zod-validated object. Add new env vars here, not `process.env.X` scattered around |
| `db.ts` | Prisma client singleton |
| `resources/*.ts` | One file per REST resource (`tapestries`, `items`, `rels`, `comments`, `groups`, `sessions`, `user-secrets`, `asset-urls`, `proxy`, batch-mutation variants) + `base-resource.ts` (the binding/auth engine) + `utils.ts` (list-filter/include parsing) |
| `services/*.ts` | `s3-service.ts`, `vault.ts`, `user-secret-service.ts`, `redis.ts`, `bull-board.ts`, `tapestry-import-service.ts` |
| `tasks/*.ts` | BullMQ queue def (`index.ts`), worker entrypoint (`worker.ts`), job handlers |
| `auth/` | `index.ts` (`authenticate()`), `tokens.ts` (JWT sign/verify), `providers/` (per-provider login strategies) |
| `socket/` | `index.ts` (Socket.io server + Postgres LISTEN/NOTIFY fan-out), `notifications.ts`, `types.ts` |
| `transformers/*.ts` | DB row ↔ DTO serialization per model, `index.ts` exposes `serialize()` |
| `errors/index.ts` | Typed error classes + Express error middleware |

## Adding/changing a REST resource

Every endpoint is bound through `resources/base-resource.ts`'s `bindEndpoint`, which
calls `authenticate(req)` (see Auth below) before the handler runs. To add an endpoint:
follow the pattern in an existing `resources/*.ts` file (e.g. `tapestries.ts`) —
1. Define/extend the DTO + Zod schema in `shared/src/data-transfer/resources/dtos/*` and
   `.../schemas/*`.
2. Add the handler in the matching `server/src/resources/*.ts`, using `db.ts` (Prisma)
   for reads/writes and a `transformers/*.ts` function to serialize the response.
3. If the mutation should propagate live, call `socketServer.notifyTapestryUpdate(id, socketIdFromRequest(req))`
   (see Socket.io section) — that's how `tapestries.ts`'s `update` handler does it.
4. If it should trigger a background job (e.g. regenerating thumbnails after an edit),
   call the relevant `scheduleXxx()` helper from `tasks/` (e.g.
   `scheduleTapestryThumbnailGeneration(id)`), not the job handler directly.

## Prisma / database

Schema: `server/prisma/schema.prisma` (Postgres, `citext` extension). Key models:
`User`, `Tapestry` (self-referencing `parent`/`children` for forking; `visibility`
enum private/link/public), `TapestryAccess` (per-user edit grants), `TapestryInvitation`,
`TapestryInteraction`, `TapestryBookmark`, `Item` (typed via `ItemType`/`WebpageType`/`ActionType`,
optional `ImageAsset` thumbnail, optional `Group`), `ImageAsset`/`ImageAssetRendition`
(multi-rendition thumbnails), `PresentationStep` (linked list via `prevStep`/`nextSteps`),
`Rel` (edge between two `Item`s), `Comment` (polymorphic via `contextType`, threaded),
`TapestryCreateJob` (import/fork job + `JobStatus`), `AiChat`/`AiChatMessage`/`AiChatMessageAttachment`,
`Group`, `UserSecret` (see Vault section — only stores a `maskedValue`).

Migrations live under `server/prisma/migrations/` (standard Prisma timestamped dirs).
**`start:api` (`npm run prisma:migrate && tsx src/index.ts`) runs `prisma migrate deploy`
automatically on every server boot** — pulling in a migration and restarting `server`
is the entire deploy step, no manual `migrate deploy` needed. The `worker` process does
**not** run migrations itself; it relies on `server` (or a manual deploy) having applied
them first. Because of the auto-deploy-on-boot behavior, **check any new migration for
destructive changes** (dropped columns/tables, non-nullable column added without a
default) before restarting `server` in an environment with real data — see
`tapestry-production-deployment` for the full pre-update checklist.

## Job queue (BullMQ)

Queue defined in `server/src/tasks/index.ts` — a single queue named `'tasks'`, with a
`JobTypeMap` enumerating payload types: `generate-tapestry-thumbnails` (`{tapestryId}`),
`s3-cleanup` (`void`, scheduled via `queue.upsertJobScheduler` on `S3_CLEAN_UP_CRON_PATTERN`),
`create-tapestry` (`{tapestryCreateJobId}`), `convert-to-pdf` (`{itemId}`).

`server/src/tasks/worker.ts` is the single `bullmq.Worker` process; `processTask()`
switches on `job.name` to dispatch to a handler file in `tasks/` (`generate-tapestry-thumbnails.ts`,
`s3-cleanup.ts`, `create-tapestry.ts`, `convert-to-pdf.ts`), plus shared Puppeteer helpers
in `tasks/utils.ts` (`inNewBrowserPage`, `initWebpage`, `scheduleTapestryThumbnailGeneration`)
and cookie-consent automation in `autoconsent.ts`. `PUPPETEER_ARGS` env var is comma-split
into `puppeteer.launch({ args })`.

**To add a new job type**: add its payload shape to `JobTypeMap` in `tasks/index.ts`, add
a handler file, add the dispatch case in `worker.ts`'s `processTask()`, and add a
`scheduleXxx()` helper that resource handlers can call instead of touching the queue
directly. Bull-Board (basic-auth via `JOBS_ADMIN_NAME`/`JOBS_ADMIN_PASSWORD`, mounted in
`index.ts`) gives a UI over the queue — useful for debugging stuck/failed jobs locally.

## S3 asset handling (LocalStack / MinIO / real S3)

`server/src/services/s3-service.ts` wraps `@aws-sdk/client-s3` + `@aws-sdk/s3-request-presigner`.
The `S3Client` reads `endpoint`/`region`/`credentials`/`forcePathStyle` purely from
`config.aws` (`AWS_ENDPOINT_URL`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`,
`AWS_S3_FORCE_PATH_STYLE` — needed for any path-style-only backend). Bucket name from
`AWS_S3_BUCKET_NAME`. This is generic enough that it works unmodified against real AWS
S3, upstream's suggested local emulator (LocalStack, via `AWS_ENDPOINT_URL=http://s3.localhost.localstack.cloud:4566`
— see `tapestry-local-dev-environment`), or MinIO on a fork that uses it instead.

Two presigned-URL flows (this is why the client talks to the S3-compatible endpoint
**directly**, not through the server, once it has a URL — see
`tapestry-local-dev-environment` for CSP implications on forks that hardcode one):

- `getCreateObjectUrl(key, mimeType, expiresIn)` → presigned `PutObjectCommand`, exposed
  via the `assetURLs` resource (`resources/asset-urls.ts`); access-checked with
  `canEditTapestry` (unrestricted for `type === 'import'`). Expiry hardcoded to 1 hour.
- `getReadObjectUrl(key, expiresIn)` → presigned `GetObjectCommand`, memoized in
  `RedisCache` keyed by object key, with a `Range: bytes=0-0` validation probe before
  reuse.

Key helpers: `generateItemKey`, `tapestryKey(id, key, isAsset)` → `tapestries/{id}/assets/{key}`,
`importKey(key)` → `imports/{key}`, `extractInternallyHostedS3Key(url)` (reverse-maps a
full URL back to a key). Plain `putObject`/`deleteObject`/`copyObject`/`listBucket` exist
for server/worker-side writes (e.g. a thumbnail job uploading a generated rendition
directly, no presigning needed since it's server-side).

## Vault-backed secrets

`server/src/services/vault.ts` (`HashiCorpVault`, wraps `@litehex/node-vault`) does
AppRole login against `VAULT_ADDR` with `VAULT_ROLE_ID`/`VAULT_SECRET_ID`, caches the
token, and re-authenticates when the lease is close to expiring.

`server/src/services/user-secret-service.ts` (`UserSecretService`, constructed per
`userId`) builds paths as `secret/data/users/{userId}/{key}` — matching the
`secret/data/users/*` Vault policy seeded by the compose entrypoint (see
`tapestry-local-dev-environment`/`tapestry-production-deployment`). KV-v2 writes need
the double `data` wrapper (`{ data: { value } }`); reads unwrap `result.data.data.data.value`
(yes, three `data`s — v2 API wrapper + your own wrapper).

The `UserSecret` Prisma model (`UserSecretType.googleApiKey` — users' own Google AI API
keys for the AI-chat feature) only stores a `maskedValue` in Postgres for display; **the
real value lives exclusively in Vault**. If you add a new kind of user-supplied secret,
follow this split — never write the plaintext secret to Postgres.

## Auth (server side)

Not a single `AUTH_PROVIDER`-branching middleware — the server supports **all** provider
types simultaneously; the client's login request carries an `authType` field, and
`server/src/auth/providers/index.ts` maps it to a strategy: `AUTH_PROVIDERS: Record<SessionCreateDto['authType'], AuthProvider>`
covering `refreshToken`, `gsi` (Google), `iaCookies`, `iaCredentials`, `registerUser`.
A provider not configured for this deployment (e.g. no `GOOGLE_CLIENT_ID`) is wired to
`UnsupportedAuthProvider`, which throws. Per-provider files: `google.ts` (verifies a
Google ID token via `google-auth-library`, audience = `GOOGLE_CLIENT_ID`),
`internet-archive.ts`, `refresh-token.ts`, `register-user.ts`.

Dispatch: `resources/sessions.ts` calls `AUTH_PROVIDERS[authType].login(...)`, which
calls `updateUserIfExists()` (`auth/index.ts`) in a Prisma transaction. **Post-login,
every provider converges on the same JWT session mechanism**: `authenticate(req)` reads
`Authorization: Bearer <jwt>` and calls `verifySessionJWT` (`auth/tokens.ts`, `jsonwebtoken`,
secret = `SECRET_KEY`, issuer = `EXTERNAL_SERVER_URL`, audience `'tapestries-api'`). The
same `verifySessionJWT` call verifies the Socket.io handshake token (see below) — one JWT
mechanism backs both REST and sockets regardless of login provider.

## Socket.io server side (live tapestry updates)

`server/src/socket/index.ts`, `SocketServer.init(httpServer)`: `path: SOCKET_PATH` (`'/subscribe'`,
from `shared/src/data-transfer/socket/types.ts` — the exact module the client imports),
`cors: { origin: config.server.viewerUrl }`. Auth middleware verifies `socket.handshake.auth.token`
via `verifySessionJWT`, same as REST.

Client→server events: `'subscribe'` (`'tapestry-updated'` — checks `canEditTapestry` before
registering, then immediately acks with a full snapshot via `getTapestryAsOf`; or
`'rtc-signaling-message'`), `'rtc-signaling-message'` (relay), `'disconnect'`.

Server→client events: `'tapestry-updated'` (`{tapestry, items, rels, groups, presentationSteps}`
as create/update/destroy batches — see `TapestryUpdatedSchema`), `'rtc-signaling-message'`.

**Fan-out is Postgres LISTEN/NOTIFY** (`pg-listen`, `DBSubscriber`, channel `'default'`) —
deliberately not Redis pub/sub or a BullMQ event, so that multiple horizontally-scaled
server instances all react to the same DB notification. A resource handler calls
`socketServer.notifyTapestryUpdate(id, socketIdFromRequest(req))` → Postgres `NOTIFY` →
every server process's listener re-emits to its own locally-connected, subscribed sockets,
using the `SocketID` HTTP header to avoid echoing the update back to the socket that
caused it. If you add a new kind of live-propagated mutation, follow this pattern rather
than inventing a second fan-out mechanism.

## Guardrails

1. **Never write a real secret to Postgres.** Follow the `UserSecret`/Vault split above.
2. **Treat every new Prisma migration as a boot-time hazard in production** — it runs
   automatically on the next `server` restart. Check for destructive changes before
   restarting against real data.
3. **Don't invent a second real-time fan-out path.** Use Postgres LISTEN/NOTIFY via
   `socketServer.notifyTapestryUpdate` for anything that needs to reach other connected
   clients live.
4. **Only `refreshToken`, `gsi` (Google), `iaCookies`, `iaCredentials`, and
   `registerUser` are real auth strategies** — adding another is new work, not
   a config toggle.
5. See `tapestry-client-features` for the matching client-side conventions (item types,
   auth provider registration, socket-manager) and `tapestry-local-dev-environment` /
   `tapestry-production-deployment` for how these services are actually run.
