---
name: tapestry-external-media-sources
description: Let users import a single media file from an external platform's "page about a file" URL (e.g. a Wikimedia Commons File: page, an Openverse image page) by resolving it to the direct file URL and creating a plain, ordinary media item — no new item type, no new webpage type, no schema changes at all. Generalized from two real reference implementations on an unmerged, messy fork branch
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["import from URL", "wikimedia commons import", "openverse import", "resolve URL to media"]
  - keywords: ["File: page", "direct file URL", "hotlinkable URL", "media source resolver"]
  - keywords: ["item-factories.ts", "createMediaItem", "parseCommonsFileURL"]
last_verified: 2026-08-12
---

Checklist for letting users paste a URL from an external platform that describes a single
media file — not the file itself — and having Tapestries resolve it and import the actual
file as a plain, ordinary item of an existing type (`image`, `video`, `audio`, `pdf`, ...).
Example: pasting `https://commons.wikimedia.org/wiki/File:AmmoniteFossil.JPG` (a wiki page
*about* an image) creates a normal `image` item pointing at the image's real, direct URL —
not a `webpage` item, and not a new item type.

Generalized from two real, complete reference implementations found in unmerged
exploratory work on a personal fork — not present on any long-lived branch, so treat the
patterns below as the durable artifact, not any particular branch they came from:

- **Wikimedia Commons file import** — `core/src/wikimedia-commons.ts` +
  `commonsFileItemFactory` in `client/src/stage/item-factories.ts`. Handles any Commons
  media type this way, not just images — e.g.
  `https://commons.wikimedia.org/wiki/File:3D_Model_Belly_Amphora.stl` resolves straight to
  a `model3d` item (see step 2's mapping table) exactly as `AmmoniteFossil.JPG` resolves to
  an `image` one.
- **Openverse image import** — `core/src/openverse.ts` + `openverseImageItemFactory`, an
  intentionally near-identical, simpler second example (images only, no ambiguous
  media-type narrowing needed) — e.g.
  `https://openverse.org/image/6c17d9b6-7721-4d42-95e6-1d570cadae74?p=1` (the `?p=1` is just
  the search-results page the user came from and is correctly ignored — the parser matches
  against the path alone).

**Neither exists on any current branch of `asteasolutions/tapestry-project` or any default
fork branch** — these are reference examples for this skill, not implemented features.

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
   alternates.** Modern browsers can no longer decode Ogg Theora, an older but still common
   Commons video codec — Commons' resolver checks for a transcoded WebM derivative and
   returns the highest-resolution one instead of the original whenever one exists. If the
   platform's API surfaces alternate renditions (transcodes, other resolutions), prefer the
   most broadly compatible one over blindly taking "the first URL in the response."
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

**If the platform's API isn't browser-CORS-enabled**, resolution has to happen server-side
instead of in the item factory: add the equivalent logic to a new function in
`server/src/services/` (or extend `resolveWebSource`'s dispatcher — see
`tapestry-content-types`'s step 6) rather than in `core/`, since `core/` code runs in the
browser here. Both reference implementations happen not to need this (Wikimedia's and
Openverse's public APIs are both directly callable from client code), so treat it as an
exception to check for, not the default path.

## Design consideration: import-by-reference vs. a real copy

**Both reference implementations import "by reference": the created item's `source` is set
to the external platform's own hosted URL** (Commons' hotlinked file, Openverse's
third-party-hosted image), not a copy uploaded into Tapestries' own S3/MinIO storage the way
a dragged-and-dropped local file is (see `tapestry-server-worker`'s S3 section for that
presigned-upload flow). This is a real product/design tradeoff, not a settled default to
copy without thinking about it:

- **By reference** (what both reference implementations do): fast, no storage cost, always
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
