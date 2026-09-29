---
name: tapestry-auth-providers
description: Add a new external login provider to internetarchive/tapestry-project (ia/google today) — the full client+server+schema+deployment checklist, generalized from a real open PR (ORCID, asteasolutions/tapestry-project#76) and one reference implementation (MediaWiki OAuth) on an unmerged fork branch
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["add auth provider", "new login provider", "OAuth provider tapestry", "AuthProvider", "AuthService"]
  - keywords: ["ORCID login", "MediaWiki login", "Wikimedia OAuth", "authorization code flow"]
  - keywords: ["VITE_AUTH_PROVIDERS", "providers-registry", "tryCompleteLogin", "updateUserIfExists", "session dto", "SessionCreateDto"]
last_verified: 2026-09-28
---

Checklist and patterns for adding a new external login provider to Tapestries, alongside
the two that ship today (`ia`, `google` — see `tapestry-client-features`/
`tapestry-server-worker`). Generalized from two OAuth-authorization-code implementations,
at two different levels of realness — **be precise about which, when citing either**:

- **ORCID** — a real, open PR against actual upstream:
  [asteasolutions/tapestry-project#76](https://github.com/asteasolutions/tapestry-project/pull/76)
  (`dbvisel/tapestry-project` branch `orcid-upstream`). Originally built against an older,
  single-exclusive-provider client architecture; merged forward onto the current
  multi-provider `VITE_AUTH_PROVIDERS`/`providers-registry.tsx` architecture (see
  `tapestry-client-features`) as part of reconciling it with upstream `main` — the shape
  described below is that *current*, merged-forward shape, not the PR's original commits.
- **MediaWiki OAuth** — still only a reference implementation on an unmerged fork branch
  (`dbvisel/tapestry-project` branch `mediawiki-login`, a single commit, never forward-merged
  onto the current architecture). Useful for the server-side token-exchange shape (see
  "Two token-exchange sub-cases" below) and as a second data point that the checklist
  generalizes correctly — but don't tell a user MediaWiki login already works or exists on
  any real branch.

## When to use this skill

- "Add \<X\> as a login option to Tapestries"
- "How do I plug in a new OAuth provider?"

## The two provider shapes

Look at how the identity provider's OAuth flow actually works before writing anything —
it determines which existing provider to model the new one on:

| Shape | Example | Client pattern | Server pattern |
|---|---|---|---|
| In-page popup / SDK-issued credential | `google` | SDK popup, hands a signed credential (`gsiCredential`) straight to the server | Server verifies the credential itself (`google-auth-library`), no code exchange |
| Credential form | `ia` | Username/password form, POSTed to the server | Server calls the provider's own auth API with the credentials |
| **OAuth 2.0 authorization-code redirect** | `orcid`, `mediawiki` (reference only) | Full-page redirect to the provider, provider redirects back with `?code=`, client hands the code to the server | Server exchanges the code for a token (and, if needed, a second call for identity) |

**Most new providers you'll be asked to add are the third shape** (any standard
OAuth2/OIDC provider — ORCID, MediaWiki/Wikimedia, GitHub, ORCID-likes, etc.). The rest of
this skill is the checklist for that shape. If the provider instead issues a client-side
SDK credential (like Google) or is a plain credential form (like IA), look at
`client/src/auth/google/` or `client/src/auth/internet-archive/` directly instead — the
list below doesn't quite fit.

## Two token-exchange sub-cases

Check the provider's OAuth docs for which one applies **before** writing the server
provider — it changes the shape of `exchangeCodeForX`:

- **Token endpoint returns identity directly** (ORCID: `/oauth/token`'s JSON response
  includes `orcid` + optional `name`) → one `fetch` call.
- **Token endpoint returns only an opaque access token** (MediaWiki: `/oauth2/access_token`
  returns just a token) → a *second*, `Authorization: Bearer <token>`-authenticated call to
  a profile/userinfo endpoint (MediaWiki: `oauth2/resource/profile`) to get the identity.

Either way: **key the account on the provider's stable central user id** (ORCID iD, or
MediaWiki's `sub`), never on a mutable username — usernames can change, stable ids don't.

## The checklist

Work through these in order; every one of them was touched by both reference
implementations. Follow existing provider names/casing conventions exactly (e.g. `orcid`
lowercase for `authType`/config keys, `Orcid` PascalCase for class names) — the codebase is
consistent about this and mixing case breaks nothing at compile time but reads as sloppy.

1. **`shared/src/data-transfer/resources/dtos/session.ts`** — add
   `LoginWith<X>Dto { authType: '<x>'; code: string; redirectUri: string }` and add it to
   the `SessionCreateDto` union.
2. **`shared/src/data-transfer/resources/schemas/session.ts`** — add the matching member to
   the `SessionCreateSchema` discriminated union: `z.object({ authType: z.literal('<x>'), code: z.string(), redirectUri: z.string() })`.
3. **`server/src/config.ts`** — add `<X>_CLIENT_ID`/`<X>_CLIENT_SECRET`/`<X>_BASE_URL` (all
   `z.string().default('')`, base URL defaulting to the provider's real endpoint) to the env
   schema, and expose them as `config.server.<x> = { clientId, clientSecret, baseUrl }`.
4. **`server/src/auth/tokens.ts`** — add `<x>Id: z.string().nullish()` to `RegisterJWTSchema`.
5. **`server/prisma/schema.prisma`** — add `<x>Id String? @unique` to `User`, then generate
   a migration (`npm run -w server prisma:migrate` or equivalent — see
   `tapestry-server-worker` for the auto-deploy-on-boot implication of new migrations).
6. **`server/src/auth/providers/<x>.ts`** — new file:
   - A Zod schema for the token response (and, if sub-case 2, a second schema for the
     profile response).
   - `exchangeCodeFor<X>(code, redirectUri)`: POST to the token endpoint with
     `client_id`/`client_secret`/`grant_type=authorization_code`/`code`/`redirect_uri` as
     `application/x-www-form-urlencoded`; on a non-OK response throw
     `InvalidCredentialsError`; wrap unexpected errors (`console.error` + rethrow
     `ServerError`) — **don't let a parse/network error leak as `InvalidCredentialsError`**,
     only an actual auth rejection should look like bad credentials to the caller.
   - Map the result to `RegisterJWTData`: the stable id field, an email (see below), and
     name fields.
   - `export class <X>AuthProvider implements AuthProvider<<X>Credentials>`, `login({code, redirectUri})`
     calls the exchange function then `updateUserIfExists({ <x>Id: id }, data)` (from
     `server/src/auth/index.ts` — looks up by the new column, 404s via
     `UserDoesNotExistError` if no match, else updates and returns the user id).
   - **No email guarantee**: many providers don't return a confirmed email (ORCID's
     `/authenticate` scope never does; MediaWiki only does when the user confirmed one).
     Synthesize a stable, unique placeholder tied to the provider's id (e.g.
     `${id}@<provider>.invalid` — note `.invalid` is the correct TLD for
     "intentionally not a real address" per RFC 2606, cleaner than piggybacking on the
     provider's real domain the way the ORCID reference does with `@orcid.org`) — never
     leave it blank, `email` is `@unique` on `User`.
7. **`server/src/auth/providers/index.ts`** — register in `AUTH_PROVIDERS`:
   `<x>: config.server.<x>.clientId ? new <X>AuthProvider() : unsupported`. This is why the
   server can ship with every provider's code present but only "live" wherever its client
   ID is actually configured — no build-time branching needed server-side.
8. **`server/src/resources/sessions.ts`** — add the dispatch branch:
   `if (request.authType === '<x>') return AUTH_PROVIDERS.<x>.login(request)`.
9. **`client/src/config.ts`** — add `'<x>'` to the `AuthProviderEnum` Zod enum (this
   automatically makes it a legal value inside the comma-separated `VITE_AUTH_PROVIDERS`
   var — no separate single-provider var to touch); add `VITE_<X>_CLIENT_ID`/
   `VITE_<X>_BASE_URL`/`VITE_<X>_REDIRECT_URI` (base URL defaulted to the provider's real
   endpoint, redirect URI defaulted to `''` meaning "use the app's own origin at runtime");
   expose as `config.<x> = { clientId, baseUrl, redirectUri }`.
10. **`client/src/auth/<x>/service.ts`** — new file. **No service class** — the shared
    `AuthService` (`client/src/services/auth.ts`) is a single instance used by every
    provider, not subclassed per-provider. Export two plain functions instead:
    - `start<X>Login()`: build the authorize URL (`${baseUrl}/<authorize-path>` with
      `client_id`/`response_type=code`/`redirect_uri` — plus any provider-specific params
      like ORCID's `scope=/authenticate`), `window.location.assign(...)` to it. Nothing to
      await; the navigation itself ends the current page's JS execution.
    - `async tryComplete<X>Login(signal?): Promise<boolean>`: read `code` from
      `new URL(window.location.href)`'s search params; return `false` immediately if
      absent. If present: strip `code`/`error`/`error_description`/`state` from the URL via
      `window.history.replaceState` (so a page reload doesn't try to reuse a spent code),
      then `try { await auth.login({ authType: '<x>', code, redirectUri: redirectUri() }, signal); return true } catch (error) { if (error instanceof CanceledError) throw error; return false }`
      — rethrow a genuine abort, but swallow an actual failed exchange and return `false` so
      the caller falls back to the normal refresh-token flow instead of leaving the app stuck.
    - `redirectUri()` helper: `config.<x>.redirectUri || \`${window.location.origin}/\``.
11. **`client/src/auth/<x>/login-button.tsx`** — new file, `<X>LoginButton`: no `instanceof`
    guard needed (there's no per-provider service to distinguish `auth` from anymore) —
    just `<Button onClick={start<X>Login}>Sign in with <X></Button>`.
12. **`client/src/auth/providers-registry.tsx`** — add `<X>LoginButton` and
    `tryComplete<X>Login` to `PROVIDER_MAP`:
    `<x>: { id: '<x>', component: <X>LoginButton, tryCompleteLogin: tryComplete<X>Login }`.
    This is the piece that doesn't exist yet for the two real providers upstream (`ia`,
    `google` — neither needs a redirect-resume step) — check whether `AuthProviderItem`
    still needs a `tryCompleteLogin?: (signal?) => Promise<boolean>` field added, and
    `AuthService.refresh()` still needs the loop that calls it before falling through to
    the refresh-token flow:
    ```ts
    async refresh(loadUser: boolean, signal?: GenericAbortSignal) {
      for (const provider of AUTH_PROVIDERS) {
        if (await provider.tryCompleteLogin?.(signal)) return
      }
      await this.doLogin({ authType: 'refreshToken' }, loadUser, signal)
    }
    ```
    See `tapestry-client-features` for the rest of `providers-registry.tsx`'s shape (the
    `PROVIDER_MAP`/`AUTH_PROVIDERS` pattern this plugs into).
13. **Deployment wiring** — every place `VITE_GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_ID` currently
    flows needs a matching `VITE_<X>_*`/`<X>_*` entry: every `Dockerfile.client*` that builds
    the client (`ARG VITE_<X>_CLIENT_ID` etc.), every `docker-compose*.yml` that builds it
    (both the client's build `args:` and the server/worker's `environment:` block), and, if
    you're using the installer described in `tapestry-local-dev-environment`, `.env.sample`
    and `setup.sh` (a new prompt block for the new secret, plus a `set_env` call for it —
    the provider *selection* itself needs no new gating logic, since `AUTH_PROVIDERS` is
    already a free-form comma-separated list; just document that `<x>` is now a legal value
    in the existing prompt's help text). Which exact files exist depends on which
    deployment tooling your checkout has — verify with `git status`/`ls` rather than
    assuming; see `tapestry-local-dev-environment` for why file presence varies by branch.
    **Verified real gotcha**: a bare rename of this var (singular → plural, or any future
    rename) is easy to apply in `client/src/config.ts` and miss in one of these
    deployment-config copies — the client won't error, it'll just silently fall back to the
    schema's own default provider, which looks like a working app with the wrong (or no)
    login option rather than an obvious failure. Grep for the old name across `.env`,
    `.env.sample`, every `docker-compose*.yml`, and every `Dockerfile.client*` after any such
    rename, not just the one file you were editing.
14. **Docs** — add a provider section to the README's "Authentication Providers" list
    (one paragraph: how the flow works, which env vars to set, link to the provider's OAuth
    docs), and consider a dedicated `<X>.md` for registration steps specific to that
    provider's developer console — both reference implementations did this and it's a good
    pattern to keep (IDP app registration is usually the most fiddly, least-transferable
    part, and the part users will actually get stuck on).

## Real gotchas hit by both reference implementations

- **`localhost` vs `127.0.0.1` in the redirect URI.** ORCID's developer console rejects
  `http://localhost:8080/` as a redirect URI but accepts `http://127.0.0.1:8080/`. If a
  provider does this, you must register the `127.0.0.1` form *and* load the app at
  `http://127.0.0.1:...` (not `localhost`) so the URI the client actually sends matches
  what's registered, byte-for-byte, trailing slash included. Check this per-provider — don't
  assume every OAuth provider is `localhost`-friendly.
- **Sandbox vs production are separate credentials.** ORCID's sandbox
  (`sandbox.orcid.org`) and production (`orcid.org`) client IDs are not interchangeable —
  a sandbox ID only works against the sandbox base URL. If the provider has a sandbox,
  make the base URL configurable (as both references do) rather than hardcoding production.
- **Strip OAuth query params after consuming the code.** Without the
  `window.history.replaceState` cleanup, reloading the page after login resends a spent
  `code` to the server, which will reject it — surfacing as a confusing failed-login loop
  on refresh rather than a clean logged-in state.
- **Don't swallow `CanceledError` in `tryComplete<X>Login`.** It signals the caller
  aborted the request (e.g. component unmounted) — rethrow it, and only return `false`
  (falling through to the normal refresh-token flow) on an actual failed exchange.

## Guardrails

1. **Follow the checklist in order** — later steps (client service, login button) assume
   earlier ones (DTO, schema, config) already compile.
2. **Never invent a real-looking email** for a provider that doesn't supply one — use an
   `.invalid`-TLD placeholder keyed to the provider's stable id, and say so in a comment,
   the way both references do.
3. **Key the account on the provider's stable id, not username/email** — usernames and
   even confirmed-email status can change; the id in the new `@unique` column shouldn't.
4. **Verify which files actually exist in your checkout** before following the deployment-wiring
   step blindly — see `tapestry-local-dev-environment` for why `Dockerfile.client-minio` /
   `docker-compose.minio.yml` etc. are fork-specific, not universal.
5. See `tapestry-client-features` (client-side provider-selection pattern) and
   `tapestry-server-worker` (server-side `AUTH_PROVIDERS` map and JWT session mechanism)
   for the surrounding architecture this checklist plugs into.
