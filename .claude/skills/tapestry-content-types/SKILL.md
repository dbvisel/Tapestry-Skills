---
name: tapestry-content-types
description: Add a new canvas content/item type to asteasolutions/tapestry-project while changing as little as possible — the full checklist generalized from a real, complete reference implementation (IIIF deep-zoom images) on an unmerged fork branch, including the easy-to-miss export-version bump
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["add item type", "new content type", "canvas item type", "MediaItemSchema", "ItemType"]
  - keywords: ["IIIF", "deep zoom", "OpenSeadragon", "export version", "ExportV8"]
  - keywords: ["item factory", "itemSizes", "TapestryComponentsConfig", "thumbnail generator"]
last_verified: 2026-08-12
---

Checklist and minimal-diff patterns for adding a new canvas content type to Tapestries,
alongside the ones that ship today (`text`, `actionButton`, `audio`, `book`, `image`,
`pdf`, `video`, `webpage` — see `tapestry-client-features`). Generalized from a real,
complete reference implementation — IIIF deep-zoom image support — on an unmerged branch
of a fork (`dbvisel/tapestry-project` branch `iiif-upstream`, a single clean commit
directly on top of upstream `asteasolutions/tapestry-project` `main`). **IIIF support does
not exist on any current branch of `asteasolutions/tapestry-project`** — it's a reference
example for this skill, not an implemented feature. Don't tell a user IIIF items already
work; use this as the template for adding a *new* type.

## When to use this skill

- "Add \<X\> as a new item/content type to Tapestries"
- Reviewing/reviving the `iiif-upstream` branch itself
- Any task that touches `MediaItemSchema`, `ItemType`, or the per-item-type maps this
  skill catalogs below

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
7. **`server/src/transformers/item.ts`** — in `itemDbToDto`: add a `type === '<x>'`
   branch that spreads `commonProps`/`commonMediaItemProps` plus the new field(s). In
   `itemDtoToDb`'s field-selection predicate: add a line so the new DB column is only
   populated `if (field === '<newField>') return item.type === '<x>'` — **this one is not
   type-checked**; forgetting it means the column silently stays null on write. Also add
   the new column to the `DB_TO_DTO_FIELD_MAP` if it needs the dotted-path mapping other
   fields use.
8. **`server/src/tasks/thumbnail-generators/index.ts`** — if the type has a derivable
   thumbnail, add it to `ITEM_TYPES_WITH_INHERENT_THUMBNAIL` (a plain array — **not**
   type-checked against `ItemType`, so double-check the spelling) and add a branch in
   `generatePrimaryThumbnail`. The reference implementation's branch delegates to the
   *existing* `generateImageThumbnail` on a derived flat-image URL rather than writing a
   new image-thumbnailing routine — look for a similar shortcut before writing a new
   generator from scratch.
9. **`server/src/services/tapestry-import-service.ts`** — add the type to the `isMediaItem`
   predicate (another plain `||` chain, not type-checked) and, in the field-copy logic for
   duplicating/importing a tapestry, copy the new field(s) across
   (`<newField>: i.type === '<x>' ? i.<newField> : null`).

### 3. Client rendering (core-client generic + client editor-specific)

10. **`core-client/src/components/tapestry/items/<x>/`** — new component folder: a
    `viewer.tsx` (or similarly named file) holding the actual rendering logic (the
    reference implementation's OpenSeadragon deep-zoom viewer lives entirely here, reading
    the new field via `useTapestryConfig().useStoreData`), and an `index.tsx` wrapping it
    in `<TapestryItem>` with the generic `<ItemToolbar>`. This is the component both the
    real app (`client`) and the standalone `viewer` app can fall back to.
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
    — TypeScript will refuse to compile until you add it.
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

16. **`client/src/stage/item-factories.ts`** — add a new `ItemFactory`: recognize sources
    for this type (URL pattern / metadata probing — the reference checks both an Internet
    Archive item URL and a direct manifest URL), resolve whatever's needed using your new
    `core/` module, build the item via the existing `createMediaItem(type, source, tapestryId)`
    helper, set any type-specific fields on the returned item, and set
    `item.skipSourceResolution = true` if you've already done resolution the server would
    otherwise redo. Insert it into the `ITEM_FACTORIES` array at the right priority — before
    any catch-all factory (`webpageItemFactory` is always last), and before/after
    IA-collection handling depending on whether your type should intercept IA URLs first.
    Return `null` (not throw) for anything that isn't actually your type, so later factories
    still get a chance.
17. **`client/src/lib/media.ts`** — add a `get<X>ItemSize(source)` function computing the
    item's default/initial size (e.g. derive an aspect ratio from fetched metadata, or a
    fixed default).
18. **`client/src/model/data/utils.ts`** — register it in
    `itemSizes: Record<ItemType, Size | ((source) => Promise<Size>)>` — another
    type-checked forcing function (step 11/13's pattern again).

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
22. Update the README's item-type list / add a short doc for anything with non-obvious
    setup (API keys, registration, format quirks) — same reasoning as the docs step in
    `tapestry-auth-providers`.

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
6. See `tapestry-client-features` for the surrounding client architecture (stage/controller
   pattern, workspace boundaries) and `tapestry-server-worker` for the surrounding backend
   architecture (REST resource conventions, Prisma migrations) this checklist plugs into.
