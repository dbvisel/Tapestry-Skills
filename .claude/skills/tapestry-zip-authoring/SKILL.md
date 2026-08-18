---
name: tapestry-zip-authoring
description: Construct a valid Tapestry .zip file (a tapestry export/import bundle — root.json plus bundled media files) from scratch, e.g. to programmatically generate a new tapestry from other data. Includes the full current (v7) schema, the zip's file-naming convention, and a bundled builder script — verified directly against the real app's Zod schema and a real import-time crash, so this doesn't require opening asteasolutions/tapestry-project's source
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry zip", "root.json", "build a tapestry", "tapestry export format", "tapestry import format"]
  - keywords: ["ExportV7Schema", "file:/ prefix", "tapestry-exporter", "tapestry-import-service"]
  - keywords: ["construct tapestry zip", "generate a tapestry programmatically", "hand-build root.json"]
last_verified: 2026-08-18
---

How to build a `.zip` file that `asteasolutions/tapestry-project` will accept as a
tapestry import — either by hand or, more reliably, via this skill's bundled
`scripts/build-tapestry-zip.py`. Useful for generating a new tapestry from some other
data source (a spreadsheet, a folder of images, a scrape) without going through the
app's UI.

**Everything in this file was verified directly against the real app**, not just read
from its source: the schema below was cross-checked field-by-field against
`core/src/data-format/export/v7/index.ts` and its dependencies; a spec built with the
bundled script was run through the actual `parseRootJson`/`CurrentExportSchema` (via
`npx tsx`, no server needed) and confirmed to parse successfully; and the "parenthesized
filename" gotcha below was confirmed by reproducing the exact `TypeError` the real
importer throws. You should not need to open `tapestry-project`'s source to use this
skill — if something here seems to disagree with a real checkout, the checkout has
moved on and this skill needs re-verifying (see `last_verified`).

## When to use this skill

- "Build/generate a tapestry from \<some other data\>"
- "Create a .zip I can import into Tapestries" / "make a tapestry programmatically"
- Any task that needs to produce `root.json` or a tapestry export bundle by hand
- Paired with `tapestry-zip-analysis` (that skill depends on this one for the schema
  reference) when you need to inspect an *existing* zip instead of building a new one

## The short version: use the bundled script

```bash
python3 scripts/build-tapestry-zip.py spec.json output.zip
```

`spec.json` is written almost exactly like `root.json` (see the schema below), except
any field that should point at a **local file to bundle** — the top-level `thumbnail`,
a media item's `source`, or a thumbnail rendition's `source` — is written as
`{"bundle": "<path, relative to the spec file>"}` instead of a literal string. The
script reads that file, places it in the zip under the correct naming convention (see
"File naming and the `file:/` prefix" below), and rewrites the field to the matching
`file:/...` value. `version`/`id`/`createdAt`/`updatedAt` may be omitted — the script
fills them in (version is always forced to `7`, the current schema).

Example spec (produces the same shape as the "minimal" example under `text` below,
plus one bundled image):

```json
{
  "title": "Test tapestry",
  "thumbnail": {"bundle": "cover.jpg"},
  "items": [
    {
      "type": "text",
      "id": "00000000-0000-0000-0000-000000000001",
      "position": {"x": 0, "y": 0},
      "size": {"width": 400, "height": 200},
      "dropShadow": false,
      "text": "<p>hello</p>",
      "backgroundColor": "#ffffff"
    },
    {
      "type": "image",
      "id": "00000000-0000-0000-0000-000000000002",
      "position": {"x": 0, "y": 300},
      "size": {"width": 100, "height": 100},
      "dropShadow": true,
      "source": {"bundle": "photo.png"}
    }
  ]
}
```

The script does structural validation (required fields per item type, valid
discriminants, unknown `groupId` references) but **is not a substitute for the real
app's Zod validation on import** — it exists to make the fiddly, error-prone mechanical
parts (exact zip-entry naming, `file:/` prefixing, id/version defaults) impossible to
get wrong by hand. If you need to hand-edit beyond what the script's spec format
supports, everything it automates is spelled out below so you can do it manually.

## The zip's layout

```
root.json                                  <- the tapestry itself (see schema below)
thumbnail (<original-name>).<ext>          <- OPTIONAL tapestry-level thumbnail, at zip ROOT (no items/ prefix)
items/<item-id> (<original-name>).<ext>    <- a media item's own file
items/<item-id>-<auto|custom>-<primary|derived>-thumbnail-<format>-<w>x<h> (<original-name>).<ext>
                                            <- a thumbnail rendition
```

- **`root.json` sits at the zip root**, sibling to everything else — this exact
  filename, case-sensitive, no path prefix. The importer does an exact string match
  against zip entry names to find it.
- **The tapestry-level thumbnail has no `items/` prefix** — that's what visually
  distinguishes it from every item-related file in a listing.
- Every bundled binary file's name has two parts: an **identifier** before the
  parenthesized segment (semantically meaningful — see below) and the **original
  filename** (sans extension) inside the parens, purely for human readability. The
  extension, if any, is whatever the original file had.
- Any standard zip tool works for building — Python's `zipfile` (what the bundled
  script uses), the `zip` CLI, etc. Nothing exotic about compression method; the real
  importer reads it with `@zip.js/zip.js`, a standard-zip-format library.

## `root.json`'s full schema (current version: 7)

Every value below is what the exporter would write for a fully-populated tapestry;
`?` marks a field that's optional/nullable and safe to omit from a hand-built spec. The
authoritative source is a Zod schema (`ExportV7Schema` in `core/src/data-format/export/v7/index.ts`,
built by layering `v0` → `v7`'s migration chain) — this is that schema's *fully resolved*
shape, flattened, so you don't need to trace the layering yourself.

### Top level

```ts
{
  version: 7,                    // MUST be the literal number 7 — write this, don't guess an older version
  id: string,                    // any string is accepted; a UUID is conventional
  title: string,
  description?: string | null,
  createdAt: string,             // ISO 8601 — coerced to a Date on parse
  updatedAt: string,
  background: string,            // hex color, e.g. "#ffffff" or "#000000" — '#'-prefixed, RGB or RGBA (alpha as a 4th byte, e.g. "#ff40191a")
  theme: "light" | "dark",
  parentId?: string | null,
  startView?: { position: {x: number, y: number}, size: {width: number, height: number} } | null,
                                  // the camera rect shown when the tapestry first opens
  thumbnail?: string | null,     // an external URL, OR `file:/<zip-entry-path>` (see naming convention)
  items?: Item[] | null,         // see the 8 item types below
  groups?: Group[] | null,
  rels?: Rel[] | null,
  presentation?: PresentationStep[] | null,
}
```

`version` is checked with a Zod *literal* — `7` exactly (a JSON number, not `"7"`). Any
other value gets tried against the older parsers (`v0`-`v6`) instead; if you want the
current schema accepted directly, write `7`.

### `Group`

```ts
{ id: string, color?: string | null, hasBorder: boolean, hasBackground: boolean }
```
Real-world `color` values seen: `null`, or a hex color, sometimes with an alpha byte
(`"#ff40191a"`). If any item references a `groupId`, that id must appear in `groups[]`.

### `Rel` (a connector between two items)

```ts
{
  id: string,
  from: { itemId: string, anchor: {x: number, y: number}, arrowhead: "none" | "arrow" },
  to:   { itemId: string, anchor: {x: number, y: number}, arrowhead: "none" | "arrow" },
  color: string,                          // hex color
  weight: "light" | "medium" | "heavy",
}
```
`anchor` is a fractional point on the item's bounding box (`{x: 0, y: 0.5}` = the
left-middle edge), not a pixel offset.

### `PresentationStep`

```ts
{ id: string, prevStepId?: string | null, type: "item",  itemId: string }
{ id: string, prevStepId?: string | null, type: "group", groupId: string }
```
**This is a backward-linked list, not an array in display order.** Each step points to
its *predecessor* via `prevStepId`; the first step in the sequence is the one with
`prevStepId: null`. To reconstruct display order: build a map from `prevStepId -> step`,
start at the step with `prevStepId: null`, then repeatedly look up "the step whose
`prevStepId` equals the current step's `id`" until you run out. (Verified against real
15- and 55-step presentations — see `tapestry-zip-analysis`'s bundled script, which
implements exactly this walk.)

### Items — common fields

All 8 item types share these (in addition to their type-specific fields below):

```ts
{
  id: string,
  position: {x: number, y: number},
  size: {width: number, height: number},
  title?: string | null,
  dropShadow: boolean,           // REQUIRED, not nullable — always include it
  groupId?: string | null,
  notes?: string | null,
  thumbnail?: { renditions: ThumbnailRendition[] } | null,   // optional — omit entirely if the item has no thumbnail
  layer?: number,                // stacking order; z.int().default(0) — safe to omit, defaults to 0
}
```

`ThumbnailRendition`:
```ts
{
  source: string,                // external URL, or `file:/<zip-entry-path>`
  format: string,                // e.g. "jpeg", "png", "webp" — matches the file's real encoding
  size: {width: number, height: number},
  isPrimary: boolean,            // exactly one rendition should be primary; others are "derived" (resized) from it
  isAutoGenerated: boolean,      // false = a user-uploaded thumbnail ("custom"); true = server-generated
}
```
A minimal item can omit `thumbnail` entirely (confirmed against a real "no thumbnail"
sample — the app happily displays items with no thumbnail at all, generating one lazily
after import). Don't invent a thumbnail you don't have real image bytes for.

### The 8 item types (discriminated by `type`)

**`text`**
```json
{
  "type": "text", "id": "...", "position": {"x":0,"y":0}, "size": {"width":400,"height":200},
  "title": null, "dropShadow": false, "groupId": null, "notes": null,
  "text": "<p><span style=\"color: rgb(0,0,0); font-size: 36px;\">Some HTML</span></p>",
  "backgroundColor": "#ffffff00"
}
```
`text` is rendered as HTML — real exports contain full inline-styled `<p>`/`<span>`
markup, not markdown or plain text. `backgroundColor` accepts an alpha byte for
"transparent" (`#ffffff00` = fully transparent white, seen throughout real samples).

**`actionButton`** (a clickable button; not a media item — no `source`)
```json
{
  "type": "actionButton", "id": "...", "position": {...}, "size": {...},
  "title": null, "dropShadow": false, "groupId": null, "notes": null,
  "actionType": "internalLink" | "externalLink" | null,
  "action": "<url, or an internal-link query string with a `focus` param>" ,
  "text": "<p>Button label as HTML</p>",
  "backgroundColor": "#ffffff00"
}
```
`actionType: null` with a plain URL in `action` is common in real exports (older
buttons predate the internal/external distinction). `internalLink` means `action` is a
query string identifying another view within the *same* tapestry (heuristically:
whether it has a `focus` param) rather than an external URL.

**`image` / `pdf` / `video` / `audio` / `book` / `webpage`** (media items — all require `source`):

```ts
// image
{ type: "image", id, position, size, title?, dropShadow, groupId?, notes?, thumbnail?,
  source: string,                          // file:/... or an external URL
  actionType?: "internalLink" | "externalLink" | null, action?: string | null }  // image can ALSO be a link

// pdf
{ type: "pdf", id, position, size, title?, dropShadow, groupId?, notes?, thumbnail?,
  source: string, defaultPage?: number | null }

// video / audio
{ type: "video" | "audio", id, position, size, title?, dropShadow, groupId?, notes?, thumbnail?,
  source: string, startTime?: number | null, stopTime?: number | null }

// book (epub)
{ type: "book", id, position, size, title?, dropShadow, groupId?, notes?, thumbnail?,
  source: string }

// webpage
{ type: "webpage", id, position, size, title?, dropShadow, groupId?, notes?, thumbnail?,
  source: string,
  webpageType?: "youtube" | "vimeo" | "iaWayback" | "iaAudio" | "iaVideo" | null,  // null = a generic embedded page
  timestamp?: string | null, startTime?: number | null, stopTime?: number | null }
```

Real, complete examples (from actual public tapestries):

```json
{
  "type": "image", "id": "ec499ad2-...", "position": {"x":-360,"y":-320}, "size": {"width":680,"height":580},
  "title": "", "dropShadow": true, "groupId": null, "notes": null,
  "thumbnail": { "renditions": [
    { "source": "file:/items/ec499ad2-...-auto-primary-thumbnail-webp-680x573 (ec499ad2-...-auto-primary-thumbnail-webp-680x573).webp",
      "format": "webp", "size": {"width":680,"height":573}, "isPrimary": true, "isAutoGenerated": true },
    { "source": "file:/items/ec499ad2-...-auto-derived-thumbnail-webp-256x216 (ec499ad2-...-auto-derived-thumbnail-webp-256x216).webp",
      "format": "webp", "size": {"width":256,"height":216}, "isPrimary": false, "isAutoGenerated": true }
  ]},
  "source": "file:/items/ec499ad2-... (0c09a83d-e307-4c87-8bee-5f077dde240d).png"
}
```

```json
{
  "type": "webpage", "id": "...", "position": {"x":320,"y":-1100}, "size": {"width":480,"height":600},
  "title": "", "dropShadow": true, "groupId": "014d7951-...", "notes": null,
  "thumbnail": { "renditions": [
    { "source": "file:/items/....-custom-primary-thumbnail-png-480x600 (7b9bf3e9-...).png",
      "format": "png", "size": {"width":480,"height":600}, "isPrimary": true, "isAutoGenerated": false }
  ]},
  "source": "https://en.wikipedia.org/wiki/Bad_Bunny",
  "webpageType": null
}
```
(A `webpage` item's `source` is very commonly an external URL, unlike `image`/`pdf`/
`video`/`audio`, which are usually bundled — but either can go either way; what governs
it is purely whether the string is `file:/`-prefixed, nothing else.)

`book` items are rare — none appeared across 19 sampled real public tapestries — but
the schema is otherwise identical to `pdf` minus `defaultPage`.

## File naming and the `file:/` prefix

Any string field (`thumbnail`, a media item's `source`, a thumbnail rendition's
`source`) is either a normal external URL, **or**, if it starts with the literal prefix
`file:/`, a pointer into the zip itself. On import, the prefix is stripped and the
**remainder must exactly equal some zip entry's filename** — case-sensitive, including
the `items/` prefix or lack of it, the literal space, and the parentheses. There is no
UUID parsing or fuzzy matching; it's a plain string equality check against the zip's
entry list.

Naming convention (this is what the bundled script generates automatically):

| What | Zip entry name | root.json value |
|---|---|---|
| Tapestry thumbnail | `thumbnail (<name>).<ext>` | `file:/thumbnail (<name>).<ext>` |
| Media item source | `items/<item-id> (<name>).<ext>` | `file:/items/<item-id> (<name>).<ext>` |
| Thumbnail rendition | `items/<item-id>-<auto\|custom>-<primary\|derived>-thumbnail-<format>-<w>x<h> (<name>).<ext>` | matching `file:/...` |

`<name>` (inside the parentheses) is just the original filename without its extension —
purely cosmetic for a human browsing the zip. **The only part of a media item's `source`
entry name that the real importer actually parses back out is that parenthesized
segment**, via the regex `/.*\((.*)\)/.exec(filename)![1]` — it re-extracts "the original
filename" to reuse when re-uploading. This has one sharp edge, verified directly:

> **A media item's `source` zip entry MUST contain a parenthesized segment, or import
> crashes.** `/.*\((.*)\)/.exec("items/abc.png")` returns `null`, and the importer's
> `![1]` non-null assertion then throws `TypeError: Cannot read properties of null
> (reading '1')` — an ugly uncaught crash, not a clean validation error, and it aborts
> the whole import. This does **not** apply to thumbnail renditions or the tapestry-level
> thumbnail (their destination keys are generated fresh, not parsed back out of the
> filename) — only to a media item's own `source`. Always include the parenthesized
> segment on every entry regardless, for consistency; the bundled script always does.

## Guardrails

1. **Target `version: 7` directly** — don't hand-write an older version's shape hoping
   the migration chain will fix it up; that chain exists for *real historical exports*,
   not as a shortcut for new ones, and each older version's schema has its own
   differences (e.g. `thumbnail` was a single flat field before v7, not
   `{renditions: [...]}`).
2. **Every media item's `source` zip entry needs a parenthesized segment** — see above.
   This is the one gotcha that isn't caught by schema validation and produces an ugly
   crash instead of a clean rejection.
3. **`file:/` values must exactly match a real zip entry's filename** — exact string
   equality, case-sensitive, no normalization. If you bundle a file, use the exact same
   path (minus the `file:/` prefix) as the zip entry you actually wrote.
4. **`dropShadow` is required on every item** (not nullable) — don't omit it.
5. **Don't invent a `thumbnail` you don't have real bytes for** — it's fully optional at
   every level (item and tapestry); omit it rather than fabricate one.
6. **Presentation steps are a backward-linked list** — get the `prevStepId` direction
   right (see the schema section above) or the presentation will show steps out of order
   or not at all.
7. Prefer the bundled script over hand-writing — it makes the naming-convention and
   `file:/`-prefixing gotchas structurally impossible to get wrong.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/build-tapestry-zip.py` | Builds a valid tapestry `.zip` from a JSON spec (root.json's shape, with `{"bundle": "path"}` markers for local files to embed). Stdlib-only Python, no dependencies. Verified: its output was run through the real app's `parseRootJson`/`CurrentExportSchema` and parsed successfully. |
