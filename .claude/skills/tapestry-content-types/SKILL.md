---
name: tapestry-content-types
description: Add a new canvas content/item type to internetarchive/tapestry-project while changing as little as possible — the full checklist generalized from two real reference implementations (IIIF deep-zoom images, STL 3D models) on unmerged fork branches, including the easy-to-miss export-version bump and when to reuse the generic file-matching factory instead of writing a bespoke one — plus a variation for when an existing type accepts a format needing conversion before it's renderable, with client-side vs. server-side tradeoffs verified against two real competing PRs (HEIC image import)
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["add item type", "new content type", "canvas item type", "MediaItemSchema", "ItemType"]
  - keywords: ["IIIF", "deep zoom", "OpenSeadragon", "export version", "ExportV8"]
  - keywords: ["item factory", "itemSizes", "TapestryComponentsConfig", "thumbnail generator"]
  - keywords: ["HEIC", "unsupported format", "background conversion", "placeholder while converting", "broken image icon"]
  - keywords: ["client-side vs server-side conversion", "lazy load dependency", "code splitting", "bundle size", "moduleResolution subpath exports"]
  - keywords: ["heic-to", "libheif-js", "heic2any", "WASM decoder license", "worker queue contention"]
  - keywords: ["convert before create", "creating-then-patching", "pendingRequests", "DoingWorkIndicator", "insertDataTransfer"]
last_verified: 2026-09-03
---

Checklist and minimal-diff patterns for adding a new canvas content type to Tapestries,
alongside the ones that ship today (`text`, `actionButton`, `audio`, `book`, `image`,
`pdf`, `video`, `webpage` — see `tapestry-client-features`). Generalized from two real,
complete reference implementations on unmerged fork branches:

- **IIIF deep-zoom image support** — `dbvisel/tapestry-project` branch `iiif-upstream`, a
  single clean commit directly on top of upstream `internetarchive/tapestry-project` `main`.
- **STL 3D model viewing (`model3d`)** — one part of a single giant, admittedly messy
  commit found in unmerged exploratory work, which bundles in a lot of unrelated work. Only
  the files/lines that actually touch `model3d` were used here — the rest of that commit was
  deliberately ignored as noise. Not present on any long-lived branch.

**Neither IIIF nor `model3d` support exists on any current branch of
`internetarchive/tapestry-project`** — both are reference examples for this skill, not
implemented features. Don't tell a user either one already works; use this as the template
for adding a *new* type. The two examples are complementary: IIIF needed real async
resolution logic and a dedicated item factory; `model3d` needed neither, and instead
surfaces a lighter, more common path (reusing the existing simple-file-matching factory)
that IIIF alone would have made this skill overstate as always-necessary.

A third, different kind of reference sits at the end of this skill (see "A variation:
an existing type that needs conversion before it's usable") — HEIC image import on this
same fork, built as **two independent, complete, real reference implementations of the
same feature**, opened as competing PRs against `asteasolutions/tapestry-project` for
comparison: [#108](https://github.com/asteasolutions/tapestry-project/pull/108)
(server-side conversion, a background job) and
[#109](https://github.com/asteasolutions/tapestry-project/pull/109) (client-side
conversion, in the browser). Unlike IIIF/`model3d`, neither adds a new item type at
all — both are what to do when an *existing* type accepts a format the browser can't
render directly, and having both real and verified is what makes the "which approach"
tradeoffs below concrete rather than theoretical.

## When to use this skill

- "Add \<X\> as a new item/content type to Tapestries"
- Any task that touches `MediaItemSchema`, `ItemType`, or the per-item-type maps this
  skill catalogs below

**Before reaching for this skill**, check whether the content is really "a web page or
embeddable widget at a URL" (e.g. a specific site like SoundCloud or Spotify) rather than
something needing a genuinely different rendering surface. If so, `tapestry-webpage-types`
is a much smaller, mostly compile-time-enforced pattern that reuses the existing `webpage`
item type entirely — no new Prisma column, no new DTO, no export-version bump.

## Guiding principle: change as little as possible

The reference implementation is a good model precisely because it's disciplined about
this. Before writing anything:

- **Put format-specific parsing/resolution logic in exactly one place**: a new, pure,
  framework-free module under `core/` (no React, no DB, no server-only imports — see
  `core/src/iiif.ts` for the shape: manifest fetching, version-tolerant JSON navigation, a
  thumbnail-URL builder). Import that module from **both** the client item-factory and the
  server-side resolution code, rather than writing the parsing logic twice. The reference
  implementation calls the exact same `fetchIIIFFirstCanvas` from
  `client/src/stage/item-factories.ts` (client-side resolution when the browser can do it)
  and `server/src/resources/items.ts` (server-side resolution when it can't, e.g. direct
  API creation) — one function, two call sites.
- **Reuse existing generic escape hatches instead of inventing new ones.** The new type's
  server-side source resolution reused the *existing* `item.skipSourceResolution` flag
  (already used by `webpage` items) to mean "the client already resolved this, don't redo
  the work" — it didn't add a second, type-specific flag with the same meaning.
- **Prefer additive schema changes.** A new discriminated-union variant plus one new
  nullable column is enough for most new types; you should rarely need to touch existing
  types' fields.
- **Know which maps update themselves.** `MEDIA_ITEM_TYPES` (`core/src/data-format/schemas/item.ts`)
  is derived — `MediaItemSchema.options.map(...)` — from the discriminated union, so adding
  your schema variant is the only edit needed; don't go hunting for a place to manually
  list the new type there.

## The checklist

Work through in order — later steps assume earlier ones compile. Column/file names below
use `iiif`/`Iiif` as the stand-in; substitute your new type's name, following the existing
lowercase-`type`/PascalCase-class convention exactly.

### 1. Schema (core, shared, database)

1. **`core/src/data-format/schemas/item.ts`** — add `export const <X>ItemSchema = z.object({ type: z.literal('<x>'), ...commonItemProps.base, ...commonItemProps.source, <newField>: z.string()... })`, add it to the `MediaItemSchema` discriminated union, export `type <X>Item = z.infer<typeof <X>ItemSchema>`. This is the one edit that makes `MEDIA_ITEM_TYPES` pick it up automatically (see above).
2. **If the new type needs its own parsing/resolution logic**, add a new `core/src/<x>.ts` module now (pure functions, no framework deps) rather than inlining it later in client or server code. If it just needs an existing IA/web-source helper extended, add a small function there instead (the reference added one four-line function, `getIAIIIFManifestURL`, to the existing `core/src/internet-archive.ts`).
3. **`shared/src/data-transfer/resources/dtos/item.ts`** — add `interface <X>ItemDto extends <X>Item, BaseMediaItemDto {}`, add it to the `MediaItemDto` union.
4. **`shared/src/data-transfer/resources/schemas/item.ts`** — import the new base schema, run it through the existing `constructMediaItemSchemas(...)` helper (gives you Create/CreateInTapestry/Update variants for free — don't hand-write these), add the four resulting schemas to their four respective discriminated unions (`MediaItemSchema`, `MediaItemCreateSchema`, `MediaItemCreateInTapestrySchema`, `MediaItemUpdateSchema`).
5. **`server/prisma/schema.prisma`** — add the literal to the `ItemType` enum; add any new column(s) to `Item` as **nullable** (`String?` etc.) — every existing item type's rows must remain valid with the new column null. Generate the migration (see `tapestry-server-worker` for the auto-deploy-on-boot implication).

### 2. Server (resolution, persistence, thumbnails, import)

6. **`server/src/resources/items.ts`** — if the type needs server-side source resolution
   (anything beyond "store whatever URL/text the client sent"), add a
   `resolve<X>Source(item)` function and call it from the existing `resolveWebSource`
   dispatcher (add `if (item.type === '<x>') return resolve<X>Source(item)` at the top —
   don't rename or restructure that dispatcher). Gate on the existing
   `item.skipSourceResolution` flag, per the principle above.
7. **`server/src/transformers/item.ts`** — in `itemDbToDto`: if your new type's DTO shape
   is identical to an existing branch's (no new field, just `commonProps`/`commonMediaItemProps`
   as-is — true of `model3d`, whose schema adds no new column at all), **extend that
   branch's condition** (`if (type === 'image' || type === 'book' || type === '<x>')`)
   rather than writing a near-duplicate new branch. Only add a genuinely new branch when
   you actually have new field(s) to spread in (as IIIF's `imageService` did). Either way,
   if you did add a new column: in `itemDtoToDb`'s field-selection predicate, add a line so
   it's only populated `if (field === '<newField>') return item.type === '<x>'` — **this one
   is not type-checked**; forgetting it means the column silently stays null on write. Also
   add the new column to the `DB_TO_DTO_FIELD_MAP` if it needs the dotted-path mapping other
   fields use.
8. **`server/src/tasks/thumbnail-generators/index.ts`** — if the type has a derivable
   thumbnail, add it to `ITEM_TYPES_WITH_INHERENT_THUMBNAIL` (a plain array — **not**
   type-checked against `ItemType`, so double-check the spelling) and add a branch in
   `generatePrimaryThumbnail`. IIIF's branch delegates to the *existing*
   `generateImageThumbnail` on a derived flat-image URL rather than writing a new
   image-thumbnailing routine — look for a similar shortcut before writing a new generator
   from scratch. **This whole step is genuinely optional** — `model3d` skips it entirely
   (no inherent-thumbnail branch, no generator, nothing) and that's a legitimate choice when
   there's no cheap way to derive a flat preview image; the item just has no thumbnail.
9. **`server/src/services/tapestry-import-service.ts`** — add the type to the `isMediaItem`
   predicate (another plain `||` chain, not type-checked) and, in the field-copy logic for
   duplicating/importing a tapestry, copy the new field(s) across
   (`<newField>: i.type === '<x>' ? i.<newField> : null`).

### 3. Client rendering (core-client generic + client editor-specific)

10. **`core-client/src/components/tapestry/items/<x>/`** — new component folder: a
    `viewer.tsx` (or similarly named file) holding the actual rendering logic (IIIF's
    OpenSeadragon deep-zoom viewer lives entirely here, reading the new field via
    `useTapestryConfig().useStoreData`), and an `index.tsx` wrapping it in `<TapestryItem>`
    with the generic `<ItemToolbar>`. This is the component both the real app (`client`)
    and the standalone `viewer` app can fall back to.

    **If the viewer owns a continuous render loop** (e.g. a WebGL/three.js scene driven by
    `requestAnimationFrame`, as `model3d`'s viewer is — unlike OpenSeadragon, which handles
    its own internal resize/render), you additionally need to:
    - **Observe the container's own resize yourself** (`useResizeObserver` on the
      containing `ref`, updating the renderer's size and the camera's aspect ratio) — Pixi
      resizing the surrounding stage item does not automatically propagate into an
      imperatively-managed child canvas.
    - **Tear down every GPU resource on cleanup**, not just stop the loop: cancel the
      `requestAnimationFrame` handle, `dispose()` geometry/material/renderer objects, and
      remove the canvas element — a bare `cancelAnimationFrame` without disposing the
      underlying WebGL context leaks GPU memory across every mount/unmount of the item
      (e.g. scrolling it off-canvas and back).
11. **`core-client/src/components/tapestry/index.tsx`** — register the new component in
    `TapestryConfigProvider`'s default components map. `TapestryComponentsConfig`'s type
    (`Record<ItemComponentName<...>, ...>`) makes this a **compile error if you skip it** —
    the type system is doing the checklist enforcement for you here.
12. **`core-client/src/stage/renderer/item-renderer.ts`** — if the new type needs different
    Pixi-level thumbnail/placement behavior than the default (`cover`), extend the relevant
    conditional (the reference added its type as a second case alongside `image` for
    `thumbnailPlacement: 'stretch'`) — otherwise skip this file entirely.
13. **`core-client/src/components/tapestry/search/search-pane/use-search-results.ts`** —
    add an icon for the type to `itemIcons: Record<ItemType, IconName>`. **This one *is*
    type-checked** (`Record<ItemType, ...>` — same forcing-function pattern as step 11)
    — TypeScript will refuse to compile until you add it. Optionally, also add search
    keyword synonyms to `itemTypeSynonyms: Partial<Record<ItemType, string[]>>` in the same
    file (e.g. `model3d: ['3d', 'stl', 'model', 'mesh']`) — this one is a `Partial` map, so
    it's genuinely optional and not compiler-enforced; skip it if there's nothing obvious
    to add.
14. **`client/src/components/tapestry-elements/items/<x>/index.tsx`** — the
    editor-specific wrapper: same shape as core-client's version, but using
    `useTapestryData`/`buildToolbarMenu`/`useItemToolbar` (the richer, editor-aware
    toolbar) instead of the generic `<ItemToolbar>`, while still delegating actual
    rendering to the **same** `viewer.tsx` component from `core-client` — don't duplicate
    the viewer, only the chrome around it differs between the two apps.
15. **`client/src/pages/tapestry/tapestry-loader.tsx`** — register the client-specific
    component in the real app's components map (mirrors step 11, but for `client` rather
    than the `viewer`-shared defaults).

### 4. Client creation (item factory, sizing)

16. **`client/src/stage/item-factories.ts`** — **check first whether you need a bespoke
    factory at all.** If the type is just "a file recognized by MIME type (and/or filename
    extension)" — true of most binary asset types, and of `model3d` — reuse the existing
    generic `createSimpleMediaItemFactory('<x>', matcherFn)` (already used for
    `pdf`/`video`/`audio`) instead of writing a new one-off `ItemFactory`:
    ```ts
    createSimpleMediaItemFactory(
      '<x>',
      (source, mediaType) => mediaType === '<expected-mime-type>' ||
        (source instanceof File && source.name.toLowerCase().endsWith('.<ext>')),
    )
    ```
    **Don't trust MIME type alone for niche formats.** `model3d`'s matcher also falls back
    to a filename-extension check (`.stl`) because STL has no single standard MIME type
    (`model/stl` and the older `application/sla` both appear in the wild) and browsers
    frequently report no MIME type at all for a locally-picked file of an uncommon format.

    Only write a genuinely new `ItemFactory` (as IIIF's does) when creation needs real
    **async resolution logic** first — fetching/parsing a manifest, calling an API to
    validate or normalize the source, etc. In that case: recognize sources for this type
    (URL pattern / metadata probing), resolve whatever's needed using your new `core/`
    module, build the item via the existing `createMediaItem(type, source, tapestryId)`
    helper, set any type-specific fields on the returned item, and set
    `item.skipSourceResolution = true` if you've already done resolution the server would
    otherwise redo.

    Either way, insert the factory into the `ITEM_FACTORIES` array at the right priority —
    before any catch-all factory (`webpageItemFactory` is always last), and before/after
    IA-collection handling depending on whether your type should intercept IA URLs first.
    Return `null` (not throw) for anything that isn't actually your type, so later factories
    still get a chance.
17. **`client/src/lib/media.ts`** — add a `get<X>ItemSize(source)` function computing the
    item's default/initial size, **if** there's a meaningful intrinsic size/aspect ratio to
    derive (e.g. from fetched metadata). If there isn't — `model3d` has no natural 2D aspect
    ratio to speak of — just use a fixed default directly in the next step instead of adding
    a function here at all.
18. **`client/src/model/data/utils.ts`** — register the type in
    `itemSizes: Record<ItemType, Size | ((source) => Promise<Size>)>` — another
    type-checked forcing function (step 11/13's pattern again). The value can be either a
    plain `{ width, height }` object (what `model3d` uses) or the async function from the
    previous step — both are valid, pick whichever fits.

### 5. Export/version compatibility — easy to miss, not type-checked

19. **`core/src/data-format/export/v<N+1>/index.ts`** (new file) — even a purely additive
    new item type (new variant, no changes to existing types) still needs a **new export
    version**. Copy the previous version's schema wholesale except the version literal:
    `{ ...ExportV<N>Schema.shape, version: z.literal(<N+1>) }`. This exists so that an
    *older* client/viewer opening an export containing the new item type can detect "this
    file is a version I don't fully understand" rather than silently mis-rendering or
    crashing on an unrecognized `type`.
20. **`core/src/data-format/export/index.ts`** — bump the previous version's parser to
    target the new version (`class ParserV<N> extends ExportParser<ExportV<N+1>>`, its
    `parseInternal` just returns `{ ...tapestry, version: <N+1> }` when the change really is
    additive), add a new `ParserV<N+1>` whose `parseInternal` is the identity function, and
    add it to the `PARSERS` array. **Nothing type-checks that you remembered to do this** —
    it's easy to ship a new item type that works perfectly in the live app but silently
    breaks export/import/fork of any tapestry containing it, because the exported file still
    claims the old version. Treat this as a mandatory step whenever `core/src/data-format/schemas/item.ts`
    changes, not an optional one.

### 6. Dependencies and docs

21. If the type needs a new client-side rendering library, add it to **`core-client/package.json`**
    (that's where the viewer lives, per the workspace-boundary rule in
    `tapestry-client-features`) — not to `client/package.json` unless the library is
    genuinely editor-only. Add `@types/<library>` to the **root** `package.json` devDependencies
    if the library needs separate type definitions.

    **If the library is heavy (a WASM decoder, etc.) and only needed for one specific format**,
    lazy-load it rather than adding it to the initial bundle — but verify the split actually
    happened rather than assuming a dynamic `import()` call is enough. Verified real mistake:
    wrapping a library in its own module file and giving that file a plain top-level `import`
    does **not** lazy-load it if that file is itself statically imported from always-loaded
    code — the dependency still lands in the main chunk. Confirmed by comparing real Vite
    build output before/after: the main chunk grew by exactly the dependency's size until the
    `import()` call itself was moved to be the dynamic one, at the actual point of use, after
    which the dependency appeared in its own separate chunk and the main chunk returned to
    baseline. Always check the actual build output's chunk sizes, not just that you wrote
    `import()` somewhere in the vicinity.

    **A modern package's subpath exports (e.g. `some-lib/worker`) may not resolve under this
    project's TypeScript config.** `client/tsconfig.app.json` uses `moduleResolution: "Node"`,
    which predates package.json `exports` maps entirely — importing a documented subpath fails
    with `TS2307` even though the file genuinely exists on disk. The real fix
    (`moduleResolution: "bundler"`/`"node16"`/`"nodenext"`) is a project-wide tsconfig change
    with its own ripple effects on the rest of the codebase's type-checking — treat that as a
    separate decision requiring sign-off, not something to change casually just to unlock one
    import; falling back to the package's main (non-subpath) export is the lower-risk choice
    for a single feature.
22. Update the README's item-type list / add a short doc for anything with non-obvious
    setup (API keys, registration, format quirks) — same reasoning as the docs step in
    `tapestry-auth-providers`.

## A variation: an existing type that needs conversion before it's usable

Not every new "format" needs a new item type. HEIC images stay the existing `image`
type — the raw bytes just aren't decodable in any browser except Safari 17+, so the
item has to become renderable through a conversion step (server-side, in a background
job, or client-side, in the browser — see the comparison below) rather than being
usable the moment it's created. This pattern applies whenever a recognized source
**can't be rendered/decoded immediately**, for whatever reason, and composes with the
main checklist above rather than replacing it.

**Prefer resolving/converting before creating the item at all, when the async work can
complete using data already in the browser.** This is just step 16's bespoke-`ItemFactory`
pattern ("needs real async resolution logic first") applied to conversion instead of
parsing: the factory does the conversion, then calls `createMediaItem` only once it has
the final, correct bytes — so the item never exists in an unconverted state and needs no
correction afterward. **Real, verified history**: PR #109's *first* implementation used
the placeholder-and-patch approach documented below (create immediately with a guessed
size, convert in the background, `resource('items').update(...)` to correct it after).
It was reworked to convert-before-create once it became clear the browser already had
the whole `File` in hand, with nothing structural forcing the item to exist before
conversion finished. The rework deleted the placeholder component, the post-creation
patch call, and all manual loading-state wiring — the existing `insertDataTransfer`
wrapper (`client/src/pages/tapestry/view-model/utils.ts`) already puts a
`pendingRequests` increment/decrement around the *entire* `ITEM_FACTORIES` pipeline for
every drop/paste, so the standard hourglass indicator (`DoingWorkIndicator`) covers the
conversion wait automatically, with zero bespoke UI.

**A tempting-looking shortcut that real review rejected**: gating the factory on
`source instanceof File` looked like it would incidentally sidestep the
internal-vs-external-source problem below for free (never seeing a URL at all means
nothing to adjudicate). Real review feedback on this exact PR explicitly asked for the
opposite — link/URL sources should be converted too, downloaded via the existing
`mediaSourceToBlob` (`client/src/lib/media.ts`) first — see
`tapestry-pr-conventions`' "match the full input space of the pipeline you're plugging
into" finding. So the factory now branches on `mediaType` (checked first, since it's
already resolved by the surrounding pipeline for both File and URL sources) with a
filename-extension fallback, and handles both source shapes uniformly. The
internal-vs-external distinction below is not actually sidestepped by this design —
see the corrected guidance there.

**This only works when nothing forces the item to exist first.** A server-side
background job (PR #108's approach) still needs a real DB row to attach the job to, so
it has no choice but to create the item immediately and correct it once the job
finishes — the placeholder-and-patch pattern below is still the right one for that case,
and for any client-side case that genuinely can't finish resolving before creation
(e.g. it depends on a value only available after the item is inserted).

- **Client-side item-size computation (step 17) must not assume decode succeeds.** If
  computing the intrinsic size means loading the file into an `<img>`/`<video>`/etc.,
  and that can fail for a format the browser can't handle, detect that case up front
  (check the file's *name/extension*, not by waiting for a decode failure) and return a
  placeholder size instead — the real dimensions get corrected server-side once
  conversion finishes (below). Don't let a recognized-but-unrenderable format block
  item creation entirely; that regresses to a confusing generic "could not import"
  error with no indication of what actually failed.
- **There are two distinct "not ready yet" windows for any media item, not one** — easy
  to handle only the second and still see a broken-image flash in between:
  1. **Local optimistic preview, before upload finishes.** The item's `source` is
     temporarily a `blob:` URL from `URL.createObjectURL(file)`
     (`client/src/services/item-upload.ts`), tracked in that service's own
     upload-state list. A format check against the *DTO's `source` string* won't see
     this phase at all — check the *original `File.name`* from the matching
     upload-tracking entry instead (match by `objectUrl === dto.source`).
  2. **Post-creation, pre-conversion.** The DTO's real `source` is now the
     internally-hosted (but still unconverted) asset URL. A format-detection helper
     used here has to work against a **presigned URL with a query string appended**,
     not a bare filename — an extension check that just splits on the last `.` will
     grab the entire query string as the "extension" and silently never match. Strip
     everything from the first `?`/`#` onward before checking.

     Reuse one shared placeholder component across both windows — the reference
     implementation reuses the existing `ItemPlaceholder`/`LoadingSpinner` combo the
     PDF viewer already uses for its own "not loaded yet" state (step 10) — rather than
     inventing new UI or only covering one of the two windows.

     **If conversion itself happens client-side**, capture the original `File` object
     while it's available (the upload-tracking entry from window 1) instead of
     re-fetching the just-uploaded bytes back down from storage once window 2 starts —
     a real, verified, entirely avoidable network round-trip otherwise. Keep it in a
     ref that survives the transition from window 1 to window 2 (the component instance
     doesn't remount between them), and fall back to fetching from the URL only when no
     captured file is available (e.g. discovering an already-uploaded, still-unconverted
     item on a fresh page load, where nothing was ever in memory).
- **The conversion step must correct more than just `source`.** If the client had to
  guess a placeholder size, whatever does the conversion — a server-side job or the
  client itself — also needs to compute the *real* size once it has decoded bytes (e.g.
  via `sharp(...).metadata()` server-side, or the client's own `getImageItemSize` on the
  converted file) and update the item's `width`/`height` to match, reusing the exact
  same clamp/aspect-ratio/default-width math the normal size-computation path uses, so
  the corrected size is identical to what a directly-renderable upload would have
  produced. A server-side job should be modeled on an existing "download → transform →
  re-upload → update DB → re-trigger thumbnail generation → notify connected clients"
  job (see `tapestry-server-worker`'s job conventions); a client-side conversion should
  reuse the existing REST update path other one-off "fix up this item after some
  out-of-band work" features already use (e.g. `resource('items').update(...)`, the
  same call the "change thumbnail" feature makes) rather than inventing a new one — both
  paths funnel through the same live-update notification, so collaborators see the
  correction either way, not just the tab that triggered it.
- **Scope the conversion to sources it can actually reach — and know this is harder
  client-side.** Whatever does the converting needs to distinguish an internally-hosted
  source (safe to fetch/replace) from an externally-hosted one — fetching and re-hosting
  an external source would silently turn a by-reference import into a copy, a real
  design question worth surfacing explicitly (see `tapestry-collection-imports`'
  import-by-reference-vs-copy section) rather than deciding it unilaterally inside a
  conversion step. A **server-side** job can check this cheaply (the raw, pre-transform
  DB value is a relative key for internal sources, an absolute URL for external ones).
  A **client-side** conversion generally can't make this distinction as cheaply — by the
  time a URL reaches the browser it's already been transformed into an absolute,
  presigned-or-not URL indistinguishable from an external one.

  **Real, verified outcome, not a hypothetical**: a File-only `convert-before-create`
  factory looked like it would sidestep this problem entirely (never seeing a URL means
  nothing to adjudicate) — but the actual PR #109 reviewer explicitly rejected that
  narrower scope and asked for link/URL sources to be converted too, without raising the
  by-reference-vs-copy concern themselves. The shipped factory now converts a matching
  URL source the same as a matching File, via `mediaSourceToBlob` — meaning **this
  specific codebase's real reviewer prioritized uniform format-handling over preserving
  by-reference imports for this feature**, at least implicitly. Don't assume that
  priority generalizes to a different feature or reviewer: treat the
  by-reference-vs-copy question as still worth raising explicitly the first time it comes
  up on a new feature, rather than assuming silence here means it's a non-issue
  project-wide.

### Choosing client-side vs. server-side conversion

Both are real options with genuinely different tradeoffs, verified against the two
real reference PRs above rather than reasoned about in the abstract:

- **Server-side** (background job): zero client bundle cost; needs a Docker/worker
  image change if the conversion tool isn't already present; can cheaply distinguish
  internal from external sources (see above); but is serialized behind whatever else
  the *same* worker is doing — BullMQ's `Worker` defaults to `concurrency: 1` unless
  explicitly configured, so one worker process handles exactly one job at a time. A
  conversion job queued while the worker is mid-way through something slow (e.g. a
  multi-minute Puppeteer tapestry-screenshot job) simply waits — safely, nothing is
  lost, but the user-visible "converting" placeholder can persist far longer than the
  conversion itself would take in isolation.
- **Client-side** (in the browser): zero server/Docker changes, and immune to worker
  contention entirely; but adds a real, if lazy-loadable, client bundle dependency, and
  generally can't distinguish internal from external sources as cheaply (see above).

**Judging whether a candidate dependency's bundle-size cost is reasonable**: compare its
real, gzipped size against something already shipping unconditionally in the same
bundle, not just its raw npm package size. Verified real comparison: a WASM HEIC decoder
added ~700KB gzip (lazy-loaded, paid only by users who actually drop a HEIC file) versus
`@zip.js/zip.js` — already a real, unconditional (not lazy-loaded) ~71.5KB-gzip
dependency in this same client, for the similarly-occasional tapestry export/import
feature. That's the right comparison to reach for; eyeballing an npm page's "size" badge
in isolation doesn't tell you much.

**Evaluating a candidate client-side decode/conversion library**, beyond "does it work":

- **Check for real TypeScript declarations on the actual API you'll call, not just
  whatever `.d.ts` file happens to ship.** Verified real case: `libheif-js` (the
  "obvious" official npm wrapper for libheif) only types the low-level, unusable
  Emscripten C-function bindings — its documented, actually-usable `HeifDecoder` API is
  completely untyped. A purpose-built wrapper (`heic-to`, in this case) shipped a real
  `.d.ts` for the high-level API actually meant to be called.
- **Check the license of what's actually bundled inside, not just the package's own
  declared license field.** Verified real case: `heic2any` bundles libheif's compiled,
  LGPL-3.0-licensed code but relicenses the wrapper as MIT without the attribution LGPL
  requires — a real, still-open GitHub issue, not a hypothetical concern. `heic-to`
  declares (and appears to correctly honor) LGPL-3.0 for the same underlying engine.
- A library that's purpose-built for exactly your use case and actively tracks its
  underlying engine's releases (`heic-to` tracks new `libheif` releases closely) can
  beat both a generic-but-mislicensed popular option and a correctly-licensed-but-barely-typed
  official binding.

**Don't assume decode performance is comparable between a native binary and a
browser-executed decoder without actually measuring it on the target platform.** Native
`heif-convert` decoding a real 12MP HEIC photo took ~0.5 seconds, measured directly
inside the actual worker container. The equivalent client-side WASM/JS decode time in a
real browser was *not* independently measured in the same session (no browser-automation
tool was available to drive DevTools' own timing) — that gap in verification is called
out here deliberately rather than papered over with an assumed number.

## Guardrails

1. **One shared `core/` module for format logic, called from both client and server** —
   never duplicate parsing/resolution logic across the two.
2. **Reuse `skipSourceResolution`** for "client already did this" rather than adding a new,
   type-specific flag with the same meaning.
3. **New DB columns are nullable.** Every existing item type's existing rows must remain
   valid.
4. **Bump the export version (step 19-20) for any change to `core/src/data-format/schemas/item.ts`.**
   This is the single most likely step to be forgotten, because unlike the
   `Record<ItemType, ...>` maps, nothing in the type system forces it.
5. **Distinguish type-checked maps from plain conditionals** when doing the checklist:
   `TapestryComponentsConfig`, `itemIcons`, `itemSizes` are `Record<ItemType, ...>` and the
   compiler catches a missing entry; `ITEM_TYPES_WITH_INHERENT_THUMBNAIL`, `isMediaItem()`,
   and the `itemDtoToDb` field-selection predicate are plain arrays/conditionals the
   compiler does **not** check — verify these by hand.
6. **Prefer the generic `createSimpleMediaItemFactory` matcher over a bespoke `ItemFactory`**
   whenever the type is recognized by MIME type/extension alone, and fall back to a
   filename-extension check for formats with no reliable MIME type. Reserve a bespoke
   factory for types that genuinely need async resolution before item creation.
7. **A continuous-render viewer (WebGL/three.js/etc.) must observe its own container
   resize and dispose GPU resources on cleanup** — don't assume the surrounding Pixi stage
   handles either for you.
8. See `tapestry-client-features` for the surrounding client architecture (stage/controller
   pattern, workspace boundaries) and `tapestry-server-worker` for the surrounding backend
   architecture (REST resource conventions, Prisma migrations) this checklist plugs into.
   If the actual goal is "let users paste a URL from platform X and import the file it
   describes" using an *existing* item type — not render something new — see
   `tapestry-external-media-sources` instead; it needs none of this checklist.
9. **A recognized-but-not-immediately-renderable format is not a new item type** — see
   "A variation" above. Don't reach for the full checklist (new schema variant, export
   version bump, etc.) when the real need is a conversion step before the item becomes
   usable.
10. **Prefer converting before creating the item over creating-then-patching**, whenever
    the async work can finish using data already in the browser (a real, in-memory
    `File`) — a bespoke `ItemFactory` (step 16) that converts and only then calls
    `createMediaItem` needs no placeholder UI, no post-creation correction call, and gets
    the hourglass indicator for free via the existing `insertDataTransfer` wrapper. Only
    fall back to placeholder-then-patch (two windows: uploading, then
    post-creation-pre-conversion; a correction call once conversion finishes) when
    something genuinely forces the item to exist before the async work can complete —
    e.g. a server-side background job that needs a DB row to attach to. **"For free" only
    holds for the drop/paste path.** A different item-creation path (e.g. a picker
    dialog's own confirm handler) does not run through `insertDataTransfer` and gets no
    automatic indicator — see `tapestry-collection-imports`' "Real gotchas" section for a
    real, verified case (slow PDF item creation from a bulk picker) and the fix.
11. **Verify a lazy-loaded dependency actually landed in its own chunk** — check real
    build output, not just that an `import()` call exists somewhere. A static top-level
    import in a file that's itself always loaded defeats the split silently.
12. **A package's subpath exports (`lib/worker`, `lib/csp`, etc.) may not resolve under
    this project's client `moduleResolution: "Node"`** — don't casually change that
    project-wide setting to unlock one import; fall back to the main export instead.
13. **When evaluating a client-side WASM/native-binding wrapper library**, check for real
    TypeScript types on the specific API you'll call (not just any `.d.ts` file existing)
    and the license of what's actually bundled (not just the package's declared license
    field) — both have real, verified failure cases among popular HEIC-decoding options.
