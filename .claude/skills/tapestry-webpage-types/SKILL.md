---
name: tapestry-webpage-types
description: Add a new known webpage type to asteasolutions/tapestry-project — recognizing a URL (e.g. soundcloud.com) and giving it special embed handling, without adding a whole new item type. Generalized from two real reference implementations (SoundCloud, Spotify) on an unmerged, dirty fork branch
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["KNOWN_WEBPAGE_TYPES", "WebpageType", "WEB_SOURCE_PARSERS", "web source parser"]
  - keywords: ["soundcloud embed", "spotify embed", "recognize URL", "special webpage handling"]
  - keywords: ["findWebSourceParser", "webpageItemFactory", "ALLOWED_ORIGINS"]
last_verified: 2026-08-12
---

Checklist for adding a new **known webpage type** — recognizing a specific site's URLs
(e.g. `soundcloud.com`) and giving them special embed/rendering treatment — as opposed to
adding a whole new canvas **item type** (see `tapestry-content-types` for that heavier
pattern). Generalized from two real, complete reference implementations — SoundCloud and
Spotify embed support — on an unmerged, admittedly dirty fork branch
(`dbvisel/tapestry-project` branch `iiif-image-support`, two small commits mixed in among
unrelated work). **Neither SoundCloud nor Spotify embed support exists on any current
branch of `asteasolutions/tapestry-project` or any default fork branch** — these are
reference examples for this skill, not implemented features.

One thing to flag explicitly: this branch was expected to also add a `wikipedia` webpage
type, but it doesn't — a full-text search of the branch turns up nothing beyond an
unrelated mention in an AI-chat test fixture. Only `soundcloud` and `spotify` are real,
complete examples here. Don't assume a `wikipedia` webpage type exists anywhere, or invent
one from the name alone.

## When to use this skill

- "Recognize \<site\> URLs and embed them specially" / "add \<site\> as a webpage type"
- Any task touching `KNOWN_WEBPAGE_TYPES`, `WEB_SOURCE_PARSERS`, or `core/src/web-sources/`
- Deciding whether new content needs a new `WebpageType` (this skill) or a new `ItemType`
  (`tapestry-content-types`) — see the comparison below

## WebpageType vs. a whole new ItemType

Tapestries already has exactly one `webpage` item type whose schema carries a generic
`source` (URL) and an optional `webpageType` enum discriminator
(`youtube`/`vimeo`/`iaWayback`/`iaAudio`/`iaVideo`/...). Adding a new **value** to that
enum — plus a parser that knows how to recognize and rewrite URLs for the new site — reuses
the entire existing `webpage` schema, DTO, database columns, and generic REST resolution
path. This is dramatically less work than `tapestry-content-types`' checklist (no new
Prisma column beyond an enum value, no new DTO, no server-side resource branch, no export-
version bump — the reference SoundCloud commit touched **7 files**, versus the IIIF item
type's 26).

**Reach for this skill when**: the content is fundamentally "a web page or embeddable
widget at a URL" and the only thing that needs to differ is which URL gets iframed and
maybe how its thumbnail is generated.

**Reach for `tapestry-content-types` instead when**: the content needs a genuinely
different rendering surface — a Pixi canvas element, a deep-zoom viewer, anything that
isn't "point an iframe at a (possibly rewritten) URL."

## The checklist

1. **`core/src/data-format/schemas/item.ts`** — add the literal to the
   `KNOWN_WEBPAGE_TYPES` array (e.g. `'soundcloud'`). That's the only schema change; the
   `webpage` item's existing `webpageType: z.enum(KNOWN_WEBPAGE_TYPES).nullish()` field
   picks it up automatically. No new discriminated-union variant, no new DTO.
2. **`server/prisma/schema.prisma`** — add the same literal to the `WebpageType` Postgres
   enum. Generate the migration — it's a single line,
   `ALTER TYPE "WebpageType" ADD VALUE '<x>';` (see both reference migrations for the exact
   shape). No new column.
3. **`core/src/web-sources/<x>.ts`** — new file, `class <X>SourceParser implements WebSourceParser<'<x>'>`:
   - `readonly webpageType = '<x>'`.
   - `matches(url)`: `try { const { host } = new URL(url); return Promise.resolve(host === '<x>.com' || host.endsWith('.<x>.com')) } catch { return Promise.resolve(false) }` — defensive URL parsing, host-based sniffing.
   - `parse(source)`: returns `{ source: <rewritten-or-passthrough-url> }`.
   - `construct(params)`: returns the actual URL to store/iframe — usually the site's
     dedicated embed/widget endpoint, not the page the user pasted.
   - **Make `parse`/`construct` idempotent**: both reference parsers detect whether they've
     already been given their own embed URL (vs. the original public URL) and normalize
     either input to the same output. This matters because the webpage viewer **re-runs
     `construct` at render time** from whatever `source` ended up stored — if `construct`
     assumed it always received a raw public URL, re-rendering a stored embed URL would
     double-rewrite it and break.
4. **`core/src/web-sources/index.ts`** — import the new parser class and add
   `<x>: new <X>SourceParser()` to `WEB_SOURCE_PARSERS`. **This step cannot be silently
   skipped**: `WEB_SOURCE_PARSERS` is declared `satisfies ParsersMap`, and `ParsersMap` is a
   mapped type over `ParserName = WebpageType | 'unknown'` — the object literal fails to
   compile until every `WebpageType` (including your new one) has an entry. This is the
   webpage-type equivalent of the `Record<ItemType, ...>` forcing functions documented in
   `tapestry-content-types`.
5. **Nothing else is needed server-side.** `server/src/resources/items.ts`'s
   `resolveWebSource`/`findWebSourceParser` dispatch (see `tapestry-server-worker`) is
   already generic over every entry in `KNOWN_WEBPAGE_TYPES` — a raw URL posted directly to
   the API is automatically matched against every registered parser, in `KNOWN_WEBPAGE_TYPES`
   order, once steps 1 and 4 are done. This is the concrete payoff of "changing as little as
   possible": no new resource branch, no transformer change, no DTO field.
6. **`client/src/stage/item-factories.ts`** — only needed if the site **can't just be
   iframed as a generic webpage** and needs its URL rewritten to a dedicated embed endpoint
   *before* item creation (both SoundCloud and Spotify block framing of their regular pages
   and only work via a separate widget/embed URL). If so:
   - Use the existing `createWebSourceEmbedFactory(parser)` helper (introduced by the
     Spotify commit specifically to avoid duplicating the SoundCloud factory's body — the
     second reference implementation refactored the first's one-off factory into this
     shared helper rather than copy-pasting it; do the same if you're adding a third) to
     build a factory from `WEB_SOURCE_PARSERS.<x>`.
   - Insert it into the `ITEM_FACTORIES` array **before `htmlFileItemFactory`**. Why: a site
     that serves an exact `text/html` content type gets intercepted by `htmlFileItemFactory`
     into a broken generic webpage item before the parser-aware fallback
     (`webpageItemFactory`) is ever reached — a type needing URL rewriting has to jump the
     queue with its own early, narrowly-matching factory.
   - The factory sets `item.webpageType = parser.webpageType` and
     `item.skipSourceResolution = true` (the client already resolved/rewrote the URL; see
     `tapestry-content-types` for the same flag's other use).
   - **If the site doesn't need URL rewriting** (embeddable at its original URL, or you only
     need type-specific thumbnail/behavior downstream), you likely don't need a dedicated
     factory at all — check whether `webpageItemFactory`'s existing `findWebSourceParser`
     fallback already produces a usable item before adding one.
7. **`core-client/src/components/tapestry/items/webpage/viewer.tsx`** — if the embed loads
   its player from a distinct origin, add that origin to `ALLOWED_ORIGINS` (the iframe
   sandbox's same-origin allowlist — needed for the embed's own JS to access its storage/
   cookies via `allow-same-origin`). **Be deliberate about widening the shared `allow="..."`
   iframe permissions attribute** — it's one attribute shared by every webpage type's
   iframe, not per-type. The Spotify reference commit broadened it from `"autoplay"` to
   `"autoplay; encrypted-media; clipboard-write; picture-in-picture"` for *all* webpage
   embeds, not just Spotify's, since there's nowhere to scope it more narrowly. Document why
   each added permission is needed, the way that commit's comment does.
8. **Optional — `server/src/tasks/thumbnail-generators/{index.ts,webpage.ts}`** — the
   generic Puppeteer-screenshot thumbnail (`generateWebpageThumbnail`, the default fallback
   in `generatePrimaryThumbnail`) works for most new webpage types with zero changes — both
   SoundCloud and Spotify ship with no thumbnail-generator changes at all. Only add a
   dedicated branch (mirroring `youtube`'s `generateYoutubeThumbnail`, which fetches a
   direct thumbnail URL instead of taking a full-page screenshot) if the generic screenshot
   genuinely produces a bad result and a faster/better thumbnail source exists. This is a
   plain `if (webpageType === '<x>')` check — not type-checked, and skipping it is often the
   right call, not an oversight.

## Guardrails

1. **Default to this pattern over a whole new `ItemType`** whenever the content is "a web
   page/widget at a URL" — see the comparison above before reaching for
   `tapestry-content-types`.
2. **`WEB_SOURCE_PARSERS` registration cannot be forgotten** (compile error via
   `satisfies ParsersMap`) — but the **Prisma enum value and migration are not
   type-checked from the TypeScript side** and are easy to miss if you only work in `core/`.
3. **Keep `parse`/`construct` idempotent.** The stored `source` is whatever `construct`
   returned once; re-running `construct` on it at render time must be a no-op, not a
   double-rewrite.
4. **Only add a dedicated item factory if the generic fallback genuinely can't handle the
   site** (framing-blocked, or a `text/html` content type that an earlier factory would
   intercept). Don't add one reflexively.
5. **Treat `ALLOWED_ORIGINS`/the iframe `allow` attribute as a shared resource** — every
   addition affects every existing webpage type's embed, not just the new one.
6. See `tapestry-content-types` for the heavier pattern this one deliberately avoids, and
   `tapestry-server-worker` for the `resolveWebSource`/REST resource machinery this
   plugs into for free.
