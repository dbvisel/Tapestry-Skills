---
name: tapestry-auth-providers
description: Add a new external login provider to asteasolutions/tapestry-project (ia/google/orcid/wikimedia/bluesky all ship today) — the full client+server+schema+deployment checklist, verified against the real ORCID and Wikimedia OAuth providers on asteasolutions/main
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["add auth provider", "new login provider", "OAuth provider tapestry", "AuthProvider", "AuthService"]
  - keywords: ["ORCID login", "MediaWiki login", "Wikimedia OAuth", "Bluesky login", "authorization code flow"]
  - keywords: ["VITE_AUTH_PROVIDERS", "providers-registry", "tryCompleteLogin", "findUserIdOrStartRegistration", "session dto", "SessionCreateDto"]
last_verified: 2026-10-28
---

Checklist and patterns for adding a new external login provider to Tapestries. Five ship
today: `google` (SDK credential), `ia` (credential form), `orcid` and `wikimedia` (OAuth
2.0 authorization-code redirect, sharing real code — see below), and `bluesky` (AT
Protocol OAuth, a distinct shape — see its own section near the end, not the checklist).

## When to use this skill

- "Add \<X\> as a login option to Tapestries"
- "How do I plug in a new OAuth provider?"

## The provider shapes

Look at how the identity provider's login flow actually works before writing anything —
it determines which existing provider to model the new one on:

| Shape | Example | Client pattern | Server pattern |
|---|---|---|---|
| In-page popup / SDK-issued credential | `google` | SDK popup, hands a signed credential (`gsiCredential`) straight to the server | Server verifies the credential itself (`google-auth-library`), no code exchange |
| Credential form | `ia` | Username/password form, POSTed to the server | Server calls the provider's own auth API with the credentials |
| **OAuth 2.0 authorization-code redirect** | `orcid`, `wikimedia` | Full-page redirect to the provider, provider redirects back with `?code=`, client hands the code to the server | Server exchanges the code for a token (and, if needed, a second call for identity) |
| AT Protocol OAuth (DPoP, public client) | `bluesky` | Its own flow, not the shared redirect helpers below | Receives an already-exchanged `serviceToken`, not a code |

**Most new providers you'll be asked to add are the third shape** (any standard
OAuth2/OIDC provider — GitHub, ORCID-likes, etc.) — `orcid` and `wikimedia` both use it
and share real code for it, described below. If the provider instead issues a
client-side SDK credential (like Google), is a plain credential form (like IA), or is
AT Protocol (like Bluesky), look at that provider's own files directly instead — the
checklist below is specifically for the shared OAuth2 shape.

## Two token-exchange sub-cases

Check the provider's OAuth docs for which one applies:

- **Token endpoint returns identity directly** (ORCID: `/oauth/token`'s JSON response
  includes `orcid` + optional `name`, see `server/src/auth/providers/orcid.ts`) → one
  `fetch` call.
- **Token endpoint returns only an opaque access token** (Wikimedia:
  `/w/rest.php/oauth2/access_token` returns just a token, see
  `server/src/auth/providers/wikimedia.ts`) → a *second*, `Authorization: Bearer
  <token>`-authenticated call to a profile endpoint
  (`/w/rest.php/oauth2/resource/profile`) to get the identity.

Either way: **key the account on the provider's stable central user id** (ORCID iD, or
Wikimedia's `sub`), never on a mutable username — usernames can change, stable ids don't.

## Shared helpers — use these, don't reimplement per provider

- **Server: `server/src/auth/providers/oauth.ts`** — `BaseTokenResponseSchema` (the
  common token-response fields) and `exchangeCodeForToken({ tokenUrl, clientId,
  clientSecret, code, redirectUri, headers? }, schema)`: POSTs
  `application/x-www-form-urlencoded` with `grant_type=authorization_code`, throws
  `InvalidCredentialsError` on a non-OK response, wraps unexpected errors as
  `ServerError` (so a parse/network error never looks like a rejected login). Both
  `orcid.ts` and `wikimedia.ts` build on this directly — extend `BaseTokenResponseSchema`
  for provider-specific fields rather than writing a new exchange function.
- **Client: `client/src/auth/oauth-clients.ts`** — `createOAuthClient({ authType,
  authorizeUrl, clientId, scope?, redirectUri })` returns `{ start, tryCompleteLogin }`.
  It generates a CSRF nonce (stored in `sessionStorage`, checked against the `state`
  param on return), strips OAuth query params from the URL once consumed, and
  deduplicates concurrent `tryCompleteLogin()` calls via a cached pending promise. Both
  `client/src/auth/orcid/service.ts` and `.../wikimedia/service.ts` are a few lines each,
  just calling this factory with their own `authorizeUrl`/`clientId`/`scope` — a new
  OAuth2-redirect provider should do the same, not hand-roll `start`/`tryCompleteLogin`.
- **Redirect URI is shared, not per-provider.** One `VITE_OAUTH_REDIRECT_URI` /
  `config.redirectUri` covers every OAuth2-redirect provider (defaults to the app's own
  origin at runtime when blank) — there's no `VITE_<X>_REDIRECT_URI`.
- **Server: `findUserIdOrStartRegistration(where, registrationData, response,
  suggestions)`** (`server/src/auth/index.ts`) — looks up a user by `where`; if found,
  returns the id. If not found, it sets a short-lived (5 min) `registrationToken` cookie
  carrying `registrationData` and throws `UserDoesNotExistError` with username/first/last
  name suggestions, which the client's existing registration flow (`authType:
  'registerUser'`) completes. New providers call this, not a direct update-or-404.

## The checklist

1. **`shared/src/data-transfer/resources/dtos/session.ts`** — add
   `LoginWith<X>Dto { authType: '<x>'; code: string; redirectUri: string }` and add it to
   the `SessionCreateDto` union.
2. **`shared/src/data-transfer/resources/schemas/session.ts`** — add the matching member
   to the `SessionCreateSchema` discriminated union: `z.object({ authType:
   z.literal('<x>'), code: z.string(), redirectUri: z.string() })`.
3. **`server/src/config.ts`** — add `<X>_CLIENT_ID`/`<X>_CLIENT_SECRET`/`<X>_BASE_URL`
   (all `z.string().default('')`, base URL defaulting to the provider's real endpoint) to
   the env schema, and expose them as `config.server.<x> = { clientId, clientSecret,
   baseUrl }`.
4. **`server/src/auth/tokens.ts`** — add `<x>Id: z.string().nullish()` to
   `RegisterJWTSchema`.
5. **`server/prisma/schema.prisma`** — add `<x>Id String? @unique` to `User`, then
   generate a migration (see `tapestry-server-worker`).
6. **`server/src/auth/providers/<x>.ts`** — new file:
   - A Zod schema extending `BaseTokenResponseSchema` for the token response (and, if
     sub-case 2, a separate schema for the profile response).
   - Build identity via `exchangeCodeForToken(...)` (and a profile `fetch` if needed).
   - `export class <X>AuthProvider implements AuthProvider<<X>Credentials>`, `login({
     code, redirectUri }, response)` calls the exchange, then `findUserIdOrStartRegistration({
     <x>Id: id }, { <x>Id: id, avatar: null, ... }, response, suggestions)`.
   - **Email is optional — `User.email` is `@unique` but nullable.** Many providers
     don't return a confirmed email (ORCID's `/authenticate` scope never does). The real
     precedent (`wikimedia.ts`) is to **leave it unset** rather than synthesize one: a
     made-up placeholder still risks colliding with `@unique` if the same person later
     links another provider using their real email. Only set a real, provider-confirmed
     email if you have one.
7. **`server/src/auth/providers/index.ts`** — register in `AUTH_PROVIDERS`:
   `<x>: config.server.<x>.clientId ? new <X>AuthProvider() : unsupported`. This is why
   the server can ship with every provider's code present but only "live" wherever its
   client ID is actually configured — no build-time branching needed server-side.
8. **`server/src/resources/sessions.ts`** — add the dispatch branch:
   `if (request.authType === '<x>') return AUTH_PROVIDERS.<x>.login(request, response)`.
9. **`client/src/config.ts`** — add `'<x>'` to the `AuthProviderEnum` Zod enum (this
   automatically makes it a legal value inside the comma-separated `VITE_AUTH_PROVIDERS`
   var); add `VITE_<X>_CLIENT_ID`/`VITE_<X>_BASE_URL` (reuse the existing
   `VITE_OAUTH_REDIRECT_URI` — don't add a per-provider one); expose as `config.<x> = {
   clientId, baseUrl }`.
10. **`client/src/auth/<x>/service.ts`** — new file, a few lines:
    `export const <x>Client = createOAuthClient({ authType: '<x>', authorizeUrl:
    \`${config.<x>.baseUrl}/<authorize-path>\`, clientId: config.<x>.clientId, scope:
    '<if needed>', redirectUri: config.redirectUri })`. Add `'<x>'` to
    `OAuthAuthType` in `oauth-clients.ts`.
11. **`client/src/auth/<x>/login-button.tsx`** — new file, `<X>LoginButton`:
    `<Button onClick={<x>Client.start}>Sign in with <X></Button>`.
12. **`client/src/auth/providers-registry.tsx`** — add to `PROVIDER_MAP`:
    `<x>: { id: '<x>', component: <X>LoginButton, tryCompleteLogin: <x>Client.tryCompleteLogin }`.
    `AuthProviderItem`'s real shape is `{ id, component, prepare?, tryCompleteLogin?: ()
    => Promise<boolean> }` (no `signal` param) — `AuthService.refresh()` already loops
    over `AUTH_PROVIDERS` calling `tryCompleteLogin?.()` before falling through to the
    refresh-token flow, so a new provider needs no changes there. See
    `tapestry-client-features` for the rest of this file's shape.
13. **Deployment wiring** — every place `VITE_GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_ID`
    currently flows needs a matching `VITE_<X>_*`/`<X>_*` entry: every `Dockerfile.client*`
    that builds the client, every `docker-compose*.yml` (both the client's build `args:`
    and the server/worker's `environment:` block), and, on a checkout using the installer
    described in `tapestry-local-dev-environment`, `.env.sample` and `setup.sh`. Which
    exact files exist depends on your checkout — verify with `git status`/`ls` rather
    than assuming. **Verified real gotcha**: a bare rename of this var is easy to apply
    in `client/src/config.ts` and miss in one of these deployment-config copies — the
    client won't error, it'll just silently fall back to the schema's default provider.
    Grep for the old name across `.env`, `.env.sample`, every `docker-compose*.yml`, and
    every `Dockerfile.client*` after any such rename.
14. **Docs** — add a provider section to the README's "Authentication Providers" list
    (how the flow works, which env vars to set, link to the provider's OAuth docs).

## Bluesky — a different shape, not this checklist

`bluesky` doesn't use any of the shared helpers above. Its DTO is
`LoginWithBlueskyDto { authType: 'bluesky'; serviceToken: string }` — the client already
holds a completed AT Protocol session token by the time it calls the server, rather than
handing over a `code` for the server to exchange. The identity column is
`User.blueskyDid`. `VITE_ATPROTO_CLIENT_ID` is a public AT Protocol client id; the
client-metadata JSON file it requires is generated by `vite.config.ts`, which scans
`VITE_AUTH_PROVIDERS` for a `'bluesky'` substring to decide whether to emit it. Real
files: `server/src/auth/providers/bluesky.ts`, `client/src/auth/bluesky/`
(`client-metadata.ts`, `oauth-client.ts`, `login-button.tsx`, `login-dialog/`). Read
those directly if asked to add another AT-Protocol-style provider — this skill doesn't
generalize that shape.

## Real gotchas

- **`localhost` vs `127.0.0.1` in the redirect URI.** ORCID's developer console rejects
  `http://localhost:8080/` as a redirect URI but accepts `http://127.0.0.1:8080/`. If a
  provider does this, register the `127.0.0.1` form *and* load the app at
  `http://127.0.0.1:...` (not `localhost`) so the URI the client sends matches what's
  registered, byte-for-byte, trailing slash included. Check this per-provider.
- **Sandbox vs production are separate credentials.** ORCID's sandbox
  (`sandbox.orcid.org`) and production (`orcid.org`) client IDs are not interchangeable.
  Make the base URL configurable rather than hardcoding production.
- **CSRF via `state`.** `createOAuthClient` already generates a nonce, stores it in
  `sessionStorage`, and verifies it against the returned `state` before completing login
  — don't bypass this by calling `auth.login(...)` directly with a raw `code`.
- **Strip OAuth query params after consuming the code.** `createOAuthClient` already
  does this via `window.history.replaceState`; without it, reloading the page resends a
  spent `code`, which the server rejects — a confusing failed-login loop on refresh.

## Guardrails

1. **Follow the checklist in order** — later steps assume earlier ones (DTO, schema,
   config) already compile.
2. **Don't synthesize a placeholder email** for a provider that doesn't supply one —
   leave it unset. `User.email` is `@unique`; a made-up value can still collide once the
   same person links a second provider with their real email.
3. **Key the account on the provider's stable id, not username/email** — usernames and
   even confirmed-email status can change; the id in the new `@unique` column shouldn't.
4. **Use the shared `oauth.ts` / `oauth-clients.ts` helpers** for a new OAuth2-redirect
   provider — don't write a new per-provider token-exchange or start/tryCompleteLogin
   pair from scratch.
5. **Verify which deployment files actually exist in your checkout** before following
   the deployment-wiring step blindly — see `tapestry-local-dev-environment` for why
   `Dockerfile.client-minio` / `docker-compose.minio.yml` etc. are fork-specific, not
   universal.
6. See `tapestry-client-features` (client-side provider-selection pattern) and
   `tapestry-server-worker` (server-side `AUTH_PROVIDERS` map and JWT session mechanism)
   for the surrounding architecture this checklist plugs into.
