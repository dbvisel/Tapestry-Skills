---
name: tapestry-webpage-types
description: Add a new known webpage type to asteasolutions/tapestry-project — recognizing a URL (e.g. soundcloud.com) and giving it special embed OR fully custom DOM-rendering treatment, without adding a whole new item type. Generalized from three real reference implementations (SoundCloud, Spotify, Wikipedia) on two unmerged, dirty fork branches
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["KNOWN_WEBPAGE_TYPES", "WebpageType", "WEB_SOURCE_PARSERS", "web source parser"]
  - keywords: ["soundcloud embed", "spotify embed", "wikipedia article", "recognize URL", "special webpage handling"]
  - keywords: ["findWebSourceParser", "webpageItemFactory", "ALLOWED_ORIGINS", "DOMPurify", "dangerouslySetInnerHTML"]
last_verified: 2026-08-12
---

Checklist for adding a new **known webpage type** — recognizing a specific site's URLs
(e.g. `soundcloud.com`) and giving them special rendering treatment — as opposed to adding
a whole new canvas **item type** (see `tapestry-content-types` for that heavier pattern).
Generalized from three real, complete reference implementations on two unmerged, dirty
fork branches:

- **SoundCloud and Spotify embeds** — two small commits on `iiif-image-support`, mixed in
  among unrelated work. Both rewrite the pasted URL to the site's embed/widget endpoint and
  still render via the generic iframe.
- **Wikipedia articles** — part of one giant commit ("Everything added for Wikimania") on
  branch `wikimania-mess`. A meaningfully more involved variant: instead of iframing
  anything, it fetches the article's content via the Wikipedia REST API and renders it as
  sanitized DOM directly inside a fully custom item component.

**None of SoundCloud, Spotify, or Wikipedia support exists on any current branch of
`asteasolutions/tapestry-project` or any default fork branch** — these are reference
examples for this skill, not implemented features.

One correction from an earlier pass: a `wikipedia` webpage type was initially checked for
on `iiif-image-support` and found not to exist there (only a stray mention in an AI-chat
test fixture) — it turned out to be real, just on a different branch (`wikimania-mess`)
than first assumed. Both facts stand: it doesn't exist on `iiif-image-support`, and it does
exist, as a complete reference implementation, on `wikimania-mess`.

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
isn't "render a webpage item, one way or another."

## Two ways to render a new webpage type

Within this skill there are two genuinely different rendering strategies, and picking the
right one matters:

| Strategy | Example | What `construct()` returns | Rendering |
|---|---|---|---|
| **Rewrite to an embed URL, still iframe it** | SoundCloud, Spotify | The site's dedicated embed/widget endpoint | The existing generic `webpage` iframe viewer, unmodified |
| **Fetch content, render as DOM directly** | Wikipedia | The canonical page URL, unchanged (there's no embed URL to build) | A fully custom item component — no iframe at all |

Use the first when the site *has* an embeddable widget/player endpoint. Use the second when
it doesn't, but has an API that returns content you can render more usefully than framing
the whole page (which typically drags in site chrome/navigation that doesn't fit a canvas
item). The rest of this checklist covers the first strategy in steps 1-8 (identical to
before) and the second in steps 9-13.

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
     dedicated embed/widget endpoint, not the page the user pasted. **For the
     fetch-and-render strategy** (no embed URL exists), `construct` can legitimately just
     return the canonical page URL unchanged — Wikipedia's does exactly this; the parser's
     job there is purely URL *recognition* and *canonicalization*, not rewriting to
     something iframeable.
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

### Fetch-and-render strategy — steps 9-13, only when there's no embed URL to iframe

9. **`core/src/<x>.ts`** (new file, separate from the web-source parser) — the actual
   content-fetching logic: pure, framework-free functions that hit whatever API the site
   provides and return plain data/HTML. Wikipedia's version has three: fetch the article
   body HTML, fetch its display title, fetch its categories — each independently
   fault-tolerant (e.g. categories fail silently to an empty array, since they're
   supplementary, not core content). Keep this separate from `core/src/web-sources/<x>.ts`
   — the parser's job is URL recognition/canonicalization; this module's job is fetching
   the actual content once you already have a recognized source.
10. **`client/src/components/tapestry-elements/items/<x>-page/index.tsx`** (new file,
    **client-only — no `core-client` counterpart is required**) — the custom item
    component. Fetch via your new `core/` module (wrap in the existing `useAsync` hook from
    `tapestry-core-client/src/components/lib/hooks/use-async`, matching the idiomatic
    component shape from `tapestry-content-types`), then render the result — typically with
    `dangerouslySetInnerHTML` for fetched HTML content.
    - **Sanitize before `dangerouslySetInnerHTML`, always.** Use DOMPurify (or equivalent)
      on every piece of fetched content you render this way, including secondary fields
      like a display title — a public API endpoint is not a trust boundary against the
      *content* it serves; treat it exactly like user-supplied HTML.
    - **Rewrite relative and protocol-relative URLs to absolute** in the fetched content
      before rendering — content fetched via `fetch()` has no natural base URL the way a
      normally-loaded page does, so `./Other_Page`-style links and `//example.com/...`-style
      asset URLs will resolve wrong (or not at all) once injected into your component's DOM.
    - **Force external links to open in a new tab** (`target="_blank"`,
      `rel="noopener noreferrer"`) rather than navigate the canvas away — a link click
      inside a canvas item should never leave the tapestry.
11. **`client/src/pages/tapestry/tapestry-loader.tsx`** — register the custom component as
    a per-`webpageType` override on the `webpage` item's entry:
    `WebpageItem: { default: WebpageItem, iaWayback: WaybackPageItem, <x>: <X>Item }`.
    **This override is optional and not compile-time-enforced** — unlike a whole new
    `ItemType` (where `TapestryComponentsConfig` forces every consumer to supply a
    component), skipping this line just means the webpage item renders via the plain iframe
    `default` everywhere the override isn't registered. That's a feature, not a gap: the
    standalone `viewer` app (which only reads `core-client`'s defaults, per
    `tapestry-client-features`) automatically degrades to a plain iframe of the same stored
    URL, with zero extra work, since there's no equivalent override table in `core-client`
    to also update.
12. **Re-derive structured data from the stored URL at render time**, via the *same*
    parser's `parse()` method, rather than adding new DB columns for it. Wikipedia's item
    component calls `WEB_SOURCE_PARSERS.wikipedia.parse(dto.source)` to get `{ lang, title }`
    back out of the canonical URL on every render — the webpage item's schema still only
    has `source`, untouched. This is the fetch-and-render strategy's version of the
    "additive schema changes" principle from `tapestry-content-types`.
13. **Reuse the toolbar mechanism, and add type-specific controls to it if useful** —
    `useItemToolbar`/`buildToolbarMenu` (see `tapestry-content-types`'s component-shape
    notes) still applies; Wikipedia's component prepends a "reload this article" and "view
    on Wikipedia" button to the standard controls rather than replacing the toolbar
    mechanism with something bespoke.

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
6. **Never render fetched content with `dangerouslySetInnerHTML` unsanitized.** This
   applies to every field pulled from an external API, not just the main body — a "trusted"
   endpoint is not a trust boundary against the content it happens to serve.
7. **A per-`webpageType` component override is optional and client-only.** Skipping it is a
   valid choice (the plain iframe default still renders the item everywhere, including the
   standalone `viewer` app), not a checklist item you're required to complete.
8. See `tapestry-content-types` for the heavier pattern this one deliberately avoids, and
   `tapestry-server-worker` for the `resolveWebSource`/REST resource machinery this
   plugs into for free. If the pasted URL just *describes* a file that should become an
   ordinary `image`/`video`/... item — rather than something that should render as a
   `webpage` item itself — see `tapestry-external-media-sources` instead.
