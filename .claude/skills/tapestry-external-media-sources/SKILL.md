---
name: tapestry-external-media-sources
description: Let users import a single media file from an external platform's "page about a file" URL (e.g. a Wikimedia Commons File: page, an Openverse image page) by resolving it to the direct file URL and creating a plain, ordinary media item — no new item type, no new webpage type, no schema changes at all. Openverse and Wikimedia Commons are now real, verified, non-fork implementations (asteasolutions/tapestry-project#112, covering image/audio for Openverse and image/video/audio/pdf for Commons) — including a real codec-compatibility gotcha (prefer Commons' WebM/MP3 transcodes over Ogg originals) and a rate-limiting-forces-server-side-proxying finding that goes beyond plain CORS
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["import from URL", "wikimedia commons import", "openverse import", "resolve URL to media"]
  - keywords: ["File: page", "direct file URL", "hotlinkable URL", "media source resolver"]
  - keywords: ["item-factories.ts", "createMediaItem", "parseCommonsFileURL"]
  - keywords: ["Ogg Theora WebM transcode", "Ogg Vorbis Safari", "Commons derivatives", "browser codec compatibility"]
  - keywords: ["CORS present but rate limited", "burst rate limit", "429 concurrent requests", "server-side proxy required"]
last_verified: 2026-09-03
---

Checklist for letting users paste a URL from an external platform that describes a single
media file — not the file itself — and having Tapestries resolve it and import the actual
file as a plain, ordinary item of an existing type (`image`, `video`, `audio`, `pdf`, ...).
Example: pasting `https://commons.wikimedia.org/wiki/File:AmmoniteFossil.JPG` (a wiki page
*about* an image) creates a normal `image` item pointing at the image's real, direct URL —
not a `webpage` item, and not a new item type.

Generalized from real implementations — one still a reference example from unmerged
exploratory work on a personal fork, one now a real, non-fork implementation verified
against the actual live external APIs and opened as a PR against actual upstream:

- **Openverse image/audio import** — `core/src/openverse.ts` +
  `externalMediaFactory` in `client/src/stage/item-factories.ts` — real, verified, part of
  [asteasolutions/tapestry-project#112](https://github.com/asteasolutions/tapestry-project/pull/112)
  (open, unreviewed as of this writing). Handles both `/image/<uuid>` and `/audio/<uuid>`
  page URLs (`OpenverseMediaType = 'image' | 'audio'`) — e.g.
  `https://openverse.org/image/6c17d9b6-7721-4d42-95e6-1d570cadae74?p=1` (the `?p=1` is just
  the search-results page the user came from and is correctly ignored — the parser matches
  against the path alone). Openverse's own API always returns the single best/original file
  per item — there are no alternate-resolution derivatives to choose between, unlike
  Commons below.
- **Wikimedia Commons file import** — `core/src/wikimedia-commons.ts`, same
  `externalMediaFactory`, same PR. **Real, live-verified `mediatype`-to-item-type mapping**
  (via `action=query&prop=videoinfo&viprop=mediatype|mime`, confirmed against real Commons
  files of each kind): `BITMAP`/`DRAWING` → `image`, `VIDEO` → `video`, `AUDIO` → `audio`,
  `OFFICE` with `mime: application/pdf` → `pdf` (any other `OFFICE` file — DjVu, Word, plain
  category pages — is unsupported and returns `null`, same as the Commons 3D-model mapping
  below). A 3D-model mapping like
  `https://commons.wikimedia.org/wiki/File:3D_Model_Belly_Amphora.stl` → `model3d` is not
  part of #112 (only image/video/audio/pdf were asked for) but would follow the exact same
  pattern if added later — see step 2's mapping table.

`#112` is real, working code, verified end-to-end against the actual live Openverse and
Commons APIs (not just read from their docs) — but it is **not yet merged or reviewed**.
Don't tell a user Openverse/Commons single-file import is upstream and shipping.

**Scope note**: both reference implementations also support a *bulk* variant (importing
every file in a Commons category, or an Openverse tag search, via a picker dialog). That
reuses a separate, pre-existing generic mechanism (`IAImport` + `HandleIAImportDialog`) and
is deliberately **out of scope for this skill** — this covers only the single-URL-to-
single-item case. See `tapestry-collection-imports` for the picker/bulk-import mechanism.

## When to use this skill

- "Let users paste a \<platform\> URL and import the file directly"
- Any task recognizing a URL that describes/hosts a single media file on an external site
- Deciding between this skill, `tapestry-webpage-types`, and `tapestry-content-types` — see
  the comparison below

## Three ways to add a URL-based "connection," compared

| Pattern | Skill | Schema/DB changes | What gets created |
|---|---|---|---|
| Whole new content type | `tapestry-content-types` | New `ItemType`, new column(s), export-version bump | An item of the new type |
| New known webpage type | `tapestry-webpage-types` | New `WebpageType` enum value only | A `webpage` item (iframed or custom-rendered), `source` = the (possibly rewritten) page/embed URL |
| **External media-source resolver (this skill)** | `tapestry-external-media-sources` | **None at all** | An item of an **existing** type (`image`/`video`/.../`pdf`), `source` = the resolved **direct file URL** — indistinguishable at rest from an item created by pasting that direct URL yourself |

**Reach for this skill when**: the pasted URL is a page *about* a file on some platform —
not itself a webpage worth preserving as an item, and not a format Tapestries can't already
render. The platform's page is just a lookup key; once resolved, it's discarded.

**Reach for `tapestry-webpage-types` instead when**: the page itself (or an embed built
from it) is what should be rendered — there's no "underlying file" to unwrap.

**Reach for `tapestry-content-types` instead when**: the resolved content needs a rendering
surface Tapestries doesn't already have for any existing item type.

## The checklist

1. **`core/src/<platform>.ts`** (new file, pure, framework-free — no React, no DB): two
   or three functions:
   - `parse<Platform>URL(url)`: recognize the specific "page about a file" URL shape(s) and
     extract whatever identifier the platform's API needs (a filename, an id). Handle more
     than one shape if the platform has more than one way to link to the same file — the
     Commons parser recognizes both a direct file page (`/wiki/File:Foo.jpg`) and a
     MediaViewer lightbox hash (`#/media/File:Foo.jpg`) opened from an unrelated page, since
     both name the same underlying file. Return `null` (never throw) for anything not
     matching, wrapping the `new URL(url)` parse in a `try`/`catch` — a malformed URL should
     fail closed, not crash the factory that calls this.
   - `fetch<Platform>FileInfo(id, signal?)`: resolve the identifier to `{ url, mime,
     mediatype }`-shaped info (or your own equivalent) via the platform's public API. Accept
     an `AbortSignal` and pass it through to `fetch`. Return `null` on any failure (missing
     file, network error, non-OK response) — never throw out of this function.
   - **Confirm the endpoint is actually CORS-enabled for anonymous browser requests before
     assuming client-side resolution will work.** MediaWiki's `action=query` API needs an
     explicit `origin=*` query parameter to opt into CORS; other platforms' REST-style APIs
     may be CORS-enabled by default (Openverse's is) or may need a different opt-in
     mechanism, or may not support browser calls at all (in which case resolution needs to
     happen server-side instead — see the note at the end of this checklist).
   - **CORS being present on a per-request basis does not mean client-side calls are
     actually safe — check burst/rate-limit behavior too, separately.** Both Openverse
     and Wikimedia Commons send permissive CORS headers on ordinary single requests, yet
     both are unsafe to call directly from the browser: live-fired 20-25 concurrent
     requests got a majority of `429`s from both (Openverse via Cloudflare
     bot-mitigation — the challenge response carries no CORS header at all, which is what
     actually surfaces as a confusing "CORS blocked" browser error; Commons via its own
     gateway rate limiter — 9 of 20 came back `429`, a token-bucket-style limit, not a
     clean cutoff). A scrolling collection picker (see `tapestry-collection-imports`)
     produces exactly this request pattern. **Verify actual concurrent-request behavior
     with a real burst test (a handful of parallel `curl`s), not just a single request's
     response headers, before deciding client-side resolution is viable** — route
     through the server-side proxy with caching if it isn't (see the note at the end of
     this checklist either way, since collection browsing needs it regardless of what a
     single-item lookup can get away with).
   - **Use small typed accessor helpers** (`asRecord`/`asString`/`asNumber`, navigating
     `unknown` JSON defensively) rather than casting the API response — same convention as
     `core/src/iiif.ts` (see `tapestry-content-types`). External platforms' JSON is not
     something you control the shape of; don't trust it with a type assertion.
2. **Prefer the platform's own content-type classification over raw MIME sniffing, when it
   has one.** Commons' `mediatype` field (`BITMAP`/`DRAWING`/`AUDIO`/`VIDEO`/`OFFICE`/...) is
   more useful than the raw MIME type for deciding how to import a file — an Ogg container
   reports the generic MIME type `application/ogg` whether it holds a video or an audio
   stream, but `mediatype` still correctly distinguishes them. Map the platform's
   vocabulary to Tapestry's `MediaItemType` with a small local table:
   ```ts
   const PLATFORM_MEDIA_ITEM_TYPES: Partial<Record<PlatformMediaType, MediaItemType>> = {
     BITMAP: 'image', DRAWING: 'image', VIDEO: 'video', '3D': 'model3d',
   }
   ```
   That `'3D': 'model3d'` row is real, not illustrative: Commons' own `mediatype` vocabulary
   already distinguishes 3D models (e.g.
   `https://commons.wikimedia.org/wiki/File:3D_Model_Belly_Amphora.stl`) from images/video,
   so this resolver pattern composes for free with whatever existing item types happen to be
   available — it maps to `model3d` exactly the same way it maps to `image`, with no special
   casing needed. Good check when adding a mapping of your own: **the target item type only
   needs to already exist** (via `tapestry-content-types`, in `model3d`'s case) — this
   resolver adds no rendering logic of its own, it just points an ordinary item at a
   resolved URL.

   **Handle ambiguous cases by narrowing further on MIME, not by guessing.** Commons'
   `OFFICE` mediatype covers PDFs as well as formats Tapestries has no viewer for (DjVu,
   Word, ...) — `commonsItemType` checks `file.mime === 'application/pdf'` and returns
   `null` (unsupported) for every other `OFFICE` file rather than importing something that
   won't render. Returning `null` here means the factory (next step) declines and the URL
   falls through to whatever the next factory does with it — usually a generic webpage/link
   import — rather than blocking.
3. **Prefer a better-suited derivative over "the original," if the platform offers
   alternates — verified real for both video and audio, not just a video-only concern.**
   Modern browsers cannot decode Ogg Theora video. Safari cannot decode Ogg Vorbis audio
   at all. Commons' `videoinfo` API (a superset of `imageinfo` that also reports
   `derivatives` when requested via `viprop=derivatives`) confirmed live: a real Commons
   video file offers WebM derivatives up to 1080p; a real Commons audio file offers an
   MP3 derivative alongside the Ogg original. `core/src/wikimedia-commons.ts`'s
   `bestPlaybackURL` picks the highest-resolution `video/webm` derivative for video, an
   `audio/mpeg` derivative for audio, and falls back to the original only when no
   matching derivative exists (an already-WebM source, or a file Commons never
   transcoded). **This was found by manually testing an actual pasted video URL in a
   real browser, not by reading API docs** — the failure mode (`getVideoItemSize` never
   resolving, since the browser's `<video>` element never fires `loadedmetadata` for an
   undecodable source) surfaces as a generic, unrelated-looking downstream error
   (`item-batch-mutations` rejecting a `null` position/size), not an obvious "can't play
   this video" message — verify real playback in a real browser for any video/audio
   platform integration, not just that the resolved URL loads at the network level.

   **A generic per-extension "we don't have a thumbnail" icon is not a real thumbnail —
   detect and treat it as null.** Commons' own `thumburl` for audio files it can't
   generate a waveform/cover for comes back as a static, generic
   `/w/resources/assets/file-type-icons/fileicon-<ext>.png`, not a real per-item image.
   Hotlinking it would show every audio item in a collection picker with the exact same
   generic icon fetched from Commons, duplicating work the app's own icon fallback
   already does better and more consistently. `thumbnailFor()` checks the `thumburl`'s
   path against this known prefix and returns `null` instead, so the UI's own
   null-thumbnail fallback (see `tapestry-collection-imports`) takes over uniformly.
   Check for this same pattern on any platform whose thumbnail API might substitute a
   generic placeholder rather than omitting the field entirely when it has nothing real
   to offer.
4. **`client/src/stage/item-factories.ts`** — new dedicated `ItemFactory`:
   ```ts
   const <platform>FileItemFactory: ItemFactory = async (source, _mediaType, tapestryId) => {
     if (typeof source !== 'string' || !isHTTPURL(source)) return null
     const parsed = parse<Platform>URL(source)
     if (!parsed) return null
     const fileInfo = await fetch<Platform>FileInfo(parsed.id)
     const itemType = fileInfo && platformItemType(fileInfo)
     if (!itemType) return null
     return { items: [await createMediaItem(itemType, fileInfo.url, tapestryId)], iaImports: [] }
   }
   ```
   The created item's `source` is `fileInfo.url` — the **resolved direct file URL**, not the
   platform page the user pasted. Once resolution succeeds, the original page URL is
   discarded entirely; the item is a completely ordinary item of an existing type. Insert
   the factory into `ITEM_FACTORIES` **before `htmlFileItemFactory`** — same reasoning as
   `tapestry-webpage-types`: the platform's file/media page serves real HTML, so an earlier
   content-type-sniffing factory would otherwise intercept it into a broken generic webpage
   before this one ever runs.
5. **That's the whole checklist for the single-item case.** No schema change, no DTO change,
   no Prisma migration, no server-side resource branch — the created item is indistinguishable
   from one the user made by pasting the direct file URL themselves, so every existing
   server/transformer/thumbnail/export code path for that item type already handles it with
   zero modification. This is the lightest of the three "URL connection" patterns for
   exactly that reason.

**Route through a server-side proxy by default, not only when CORS is missing.** The
original framing here was that server-side resolution is an exception for the rare
CORS-disabled platform. Real testing corrected that: both Openverse and Wikimedia Commons
are CORS-enabled *and* both still need server-side proxying, because both rate-limit
request bursts regardless of CORS (see the CORS bullet above) — a picker's scrolling
behavior alone is enough to trigger it. `core/src/<platform>.ts`'s `fetch*` functions are
still framework-free/pure (so they're callable from either side), but the actual runtime
call path for both platforms is: client → the generic `proxy` REST resource
(`server/src/resources/proxy.ts`, a `platform`-tagged discriminated union of operations
shared across platforms — see `tapestry-collection-imports`' "Generalizing across
multiple platforms in one PR" for the exact shape) → the `core/` fetch function, called
server-side. **Treat direct client-side calls to an external platform's API as something
to justify with a real burst test, not the default** — CORS headers alone don't prove
it's safe.

## Design consideration: import-by-reference vs. a real copy

**Every implementation here imports "by reference": the created item's `source` is set
to the external platform's own hosted URL** (Commons' hotlinked file, Openverse's
third-party-hosted image), not a copy uploaded into Tapestries' own S3/MinIO storage the way
a dragged-and-dropped local file is (see `tapestry-server-worker`'s S3 section for that
presigned-upload flow). This is a real product/design tradeoff, not a settled default to
copy without thinking about it:

- **By reference** (what both real implementations do): fast, no storage cost, always
  reflects the live external asset — but breaks if the source platform deletes/moves the
  file, is subject to that platform's own hotlinking/rate-limit/CORS policies indefinitely,
  and isn't actually archived by Tapestries.
- **A real copy** ("import as if the user dragged the file in themselves"): durable,
  independent of the source platform's continued availability — but costs storage, and
  requires actually fetching the external asset's bytes (possibly needing a server-side
  proxy fetch instead of a client-side one, if the source blocks cross-origin binary
  fetches) and pushing them through the same presigned-PUT-URL upload flow a real
  drag-and-drop upload uses, before creating the item against the *new*, internally-hosted
  URL rather than the external one.

**Ask which behavior is wanted** before assuming "by reference" is fine just because that's
what the existing examples do — for an archival project in particular, "the link rotted" is
a real, not hypothetical, failure mode.

**By-reference means the resolved URL is often not the URL the user recognizes — record
the original in `notes`.** Confirmed real for both platforms: an Openverse page resolves
to a third-party host (e.g. `rawpixel.com`), a Commons `File:` page resolves to
`upload.wikimedia.org` — a user later inspecting the item sees an unfamiliar host with no
way to trace it back. Fix, applied to both platforms: set the created item's `notes` to
`` `Source: ${url}` ``, where `url` is the actual page the user pasted. See
`tapestry-collection-imports` for the bulk-picker-path variant of this same fix (no
per-item pasted URL exists there, so it reconstructs a canonical link instead).

## Guardrails

1. **Don't drift into adding a new `ItemType` or `WebpageType` for this.** If you find
   yourself touching `MediaItemSchema`, `KNOWN_WEBPAGE_TYPES`, or `server/prisma/schema.prisma`,
   you've left this pattern's scope — reconsider against `tapestry-content-types` /
   `tapestry-webpage-types`.
2. **Store the resolved direct file URL, never the original lookup page URL**, as `source`.
3. **Every resolver function returns `null` on failure — never throws, never partially
   creates an item.** A failed resolution should let the URL fall through to the next
   factory, not abort the paste/drop entirely.
4. **Prefer the platform's own media/content-type field over MIME sniffing** when one
   exists, and narrow ambiguous types by MIME rather than guessing.
5. **This skill is single-item only.** Recognizing a *collection*/category/search-results
   URL and offering a picker is a different, reusable mechanism (`IAImport` +
   `HandleIAImportDialog`) — see `tapestry-collection-imports`.
6. **Surface the by-reference-vs-copy question explicitly** rather than assuming either is
   correct for a new source (see above).
7. See `tapestry-content-types` for the `core/` module conventions (defensive JSON
   accessors) this pattern also follows, and `tapestry-webpage-types` for the closely
   related "recognize a URL, do something special" family this sits alongside.
8. **Record the originally-pasted URL in `notes`** when the resolved `source` points
   somewhere the user won't recognize (see the design-consideration section above).
9. **CORS headers on a single request don't prove client-side calls are safe** — check
   burst/concurrent-request behavior with a real test before skipping the server-side
   proxy. Route through it by default for any platform with real user traffic.
10. **For video/audio platforms, check for and prefer a browser-compatible derivative**
    (a transcode) over the platform's "original" file, and verify actual playback in a
    real browser — a network-level "the URL loads" check is not the same as "the browser
    can decode this," and the failure surfaces as an unrelated-looking downstream error,
    not an obvious codec message.
