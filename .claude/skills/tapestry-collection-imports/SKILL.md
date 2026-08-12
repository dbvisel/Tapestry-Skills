---
name: tapestry-collection-imports
description: Add a new bulk-import source to Tapestries' existing picker dialog — recognizing a URL for a collection of items (a Wikimedia Commons category, an Openverse tag search, an Internet Archive search query) and letting the user choose which to import, up to a selection cap. The picker mechanism itself is real, existing upstream functionality; this skill covers extending it, generalized from three real reference implementations on an unmerged fork branch
license: MIT
compatibility: claude-code
depends_on: ["tapestry-external-media-sources"]
skill_discovery_hints:
  - keywords: ["import picker", "HandleIAImportDialog", "IAImport", "collection import", "bulk import"]
  - keywords: ["commons category", "openverse collection", "IA search import", "select all"]
  - keywords: ["import-items-list", "LazyList", "MAX_SELECTION"]
last_verified: 2026-08-12
---

Checklist for adding a new **bulk-import source** — a URL that names a *collection* of
items (a category, a tag search, a search query) rather than one file — to Tapestries'
existing import picker. Pasting
`https://commons.wikimedia.org/wiki/Category:Fossil_forgeries` opens a dialog listing every
file in that category with checkboxes, a "select all (max. 50)" control, and a confirm
button that imports only the chosen ones — the collection URL itself is never stored
anywhere; it only drives the picker.

**The picker mechanism is real, existing upstream functionality** — `HandleIAImportDialog`,
`IAImport`, and the whole `import-items-list/` component tree already exist on
`asteasolutions/tapestry-project` `main` with real commit history (code review, bug fixes),
originally built for Internet Archive collections and playlists. **This skill is about
extending that mechanism with a new collection type**, generalized from three real,
complete reference implementations of exactly that extension, found in unmerged
exploratory work on a personal fork — not present on any long-lived branch:

- **Wikimedia Commons categories** — `https://commons.wikimedia.org/wiki/Category:Fossil_forgeries`
- **Openverse tag collections** — `https://openverse.org/image/collection?tag=Aztec`
- **Internet Archive search queries** — `https://archive.org/search?query=subject%3A%22Gondavalekar%22`

**None of these three collection types exists on any current branch of
`asteasolutions/tapestry-project` or any default fork branch** — only `IACollection`
(a literal IA collection/identifier) and `IAPlaylist` exist upstream today. Don't tell a
user Commons/Openverse/IA-search bulk import already works; use this as the template for
adding a *new* collection type.

This skill pairs with `tapestry-external-media-sources`, which covers the single-item case
for the same platforms (one Commons file, one Openverse image). A collection type's picker
ultimately creates items the same way that skill's single-item resolvers do — the new work
here is entirely in recognizing the *collection* URL, listing its members, and plugging into
the picker UI.

## When to use this skill

- "Let users import an entire \<platform\> category/collection/search, not just one item"
- Any task touching `IAImport`, `HandleIAImportDialog`, or `import-items-list/`
- Deciding between this skill and `tapestry-external-media-sources` — use this one when the
  pasted URL names *many* items and the user should choose which; use the other when it
  names exactly one

## The checklist

1. **`core/src/<platform>.ts`** (same module as the single-item resolver, if there is one —
   see `tapestry-external-media-sources`) — add:
   - `parse<X>CollectionURL(url)`: recognize the collection URL shape, extract its
     identifier (a category title, a tag, a query string). Same defensive-parsing
     conventions as the single-item case: `try`/`catch` around `new URL(url)`, return `null`
     for anything unrecognized.
   - **A cheap, count-only fetch**, separate from the full member-listing fetch:
     `fetch<X>CollectionCount(id)`. Commons' `fetchCommonsCategoryFileCount` hits a
     lightweight `categoryinfo` endpoint (no thumbnails, no per-file lookups) specifically so
     the item factory (next step) can show "N files" and decide whether to open the picker
     at all, without paying for the expensive full listing until the user actually opens it.
   - **A full member-listing fetch**, used once the picker is actually open:
     `fetch<X>CollectionMembers(id)`, returning enough per-item data for the list UI (an id,
     a thumbnail if cheaply available, whatever metadata the confirm step needs). **Cache
     this per collection id for the page's lifetime** if fetching it is at all expensive —
     Commons' cache means the picker's own list, its "select all," and this skill's later
     confirm step's resolution all share one fetch rather than tripling the request count for
     what the user experiences as a single action. Evict a failed fetch from the cache so a
     transient error doesn't permanently poison it for the session.
2. **`client/src/pages/tapestry/view-model/index.ts`** — add a member to the `IAImport`
   discriminated union: `{ type: '<X>Collection', <idField>: string, total: number }`. The
   `total` (from step 1's count fetch) is shown immediately in the dialog header before the
   full listing loads.
3. **`client/src/stage/item-factories.ts`** — a new factory, structurally different from a
   normal item factory: it does the **cheap count fetch only**, and returns **no items**,
   just a pending import:
   ```ts
   const <x>CollectionFactory: ItemFactory = async (source, _mediaType, _tapestryId) => {
     if (typeof source !== 'string' || !isHTTPURL(source)) return null
     const parsed = parse<X>CollectionURL(source)
     if (!parsed) return null
     const total = await fetch<X>CollectionCount(parsed.id)
     if (total === undefined) return null
     return { items: [], iaImports: [{ type: '<X>Collection', <idField>: parsed.id, total }] }
   }
   ```
   The returned `iaImports` entry is what actually triggers `HandleIAImportDialog` to open —
   nothing else needs to know how to render it yet.
4. **`client/src/components/handle-ia-import-dialog/index.tsx`** — four small edits:
   - Add an entry to `IA_IMPORT_TITLE_MAP: Record<IAImport['type'], string>` (the dialog's
     title for this type) and to `IA_IMPORT_CLASS_MAP: Record<IAImport['type'], string>`
     (its CSS class, usually the shared `collectionList` style). **Both are compile-time
     forcing functions** — a new `IAImport` member fails to compile here until you add it.
   - Add a branch to `createNewItems(iaImport, items, tapestryId)`: given the user's final
     checkbox selection, resolve each selected id to its actual media info (reusing the
     single-item resolver from `tapestry-external-media-sources`, e.g.
     `fetchCommonsFileInfo`) and create the items via the matching `create<X>MediaItems`
     bulk-creation helper. **This one is a plain `if` chain, not type-checked** — nothing
     stops you from adding the `IAImport` member without a matching branch here; the dialog
     would compile but silently do nothing on confirm.
   - Add a branch to the "select all" handler (`toggleAll`): fetch up to `MAX_SELECTION`
     members (via step 1's listing fetch) and select them all. Also not type-checked.
5. **`client/src/components/handle-ia-import-dialog/import-items-list/index.tsx`** — add a
   branch to this dispatcher rendering your new list component:
   `if (iaImport.type === '<X>Collection') return <<X>List <idField>={iaImport.<idField>} {...props} />`.
   Also a plain `if` chain, not type-checked.
6. **`client/src/components/handle-ia-import-dialog/import-items-list/<x>-list/index.tsx`**
   (new component) — implements the shared list contract:
   - A `request<X>Items(id, skip, limit, signal) => Promise<ListResponseDto<T>>` function
     (exported, also reused directly by step 4's "select all" branch) — wraps step 1's
     member-listing fetch, slicing/paginating it to fit `<LazyList>`'s windowed-fetch
     contract even if the underlying API doesn't paginate the same way (Commons fetches one
     capped-size batch and slices it in memory; a genuinely paginated API would forward
     `skip`/`limit` to real API params instead — check which shape your platform's API
     actually offers).
   - The component itself: wrap `<LazyList windowSize={...} requestItems={...} renderItem={...} />`,
     render each item as a `<Checkbox>` (thumbnail + label if available), disable it once
     `selectedItems.length >= MAX_SELECTION`, and include a `<SelectAll>` control wired to
     the dialog's `onToggleAll` prop. Copy an existing sibling (`commons-category-list/`) as
     the starting point — the shape is intentionally near-identical across all of them.
7. **`client/src/components/handle-ia-import-dialog/import-details/index.tsx`** — add a
   branch showing the collection's name/id, its `total` count, and a "View on \<platform\>"
   link back to the original collection page. Also a plain `if` chain.
8. **`MAX_SELECTION`** (`handle-ia-import-dialog/index.tsx`) is a single shared constant —
   **the real upstream default is 50**, applied uniformly to every collection type
   (including `IACollection`/`IAPlaylist`). Don't introduce a per-type selection cap; if a
   cap needs to change, change the shared constant and accept that it now applies to every
   existing collection type too.

## Real gotchas from the reference implementations

- **Distinguish a cheap "how many" probe from the expensive full listing**, and only pay for
  the latter once the user actually opens the picker (step 1). Confusing these means every
  paste of a collection URL triggers a full, possibly multi-request fetch just to show a
  count.
- **Cache the full listing per collection id** if fetching it takes more than one request —
  the list UI, "select all," and (for some platforms) the confirm-time resolution step can
  all end up wanting the same data for what the user experiences as one action.
- **Two of the four dialog-integration points are compile-time-enforced
  (`IA_IMPORT_TITLE_MAP`/`IA_IMPORT_CLASS_MAP`), two are not** (`createNewItems`'s branch,
  the list dispatcher's branch). Adding an `IAImport` member and only updating the two
  `Record` maps compiles cleanly but silently does nothing when a user tries to actually use
  it — verify all four by hand.

## Design consideration: import-by-reference vs. a real copy

**Every reference implementation here — both this skill's collection types and
`tapestry-external-media-sources`' single-item resolvers — imports "by reference": the
created item's `source` is set to the external platform's own hosted URL** (Commons'
hotlinked file, an IA item's own asset URL, Openverse's third-party-hosted image), not a
copy uploaded into Tapestries' own S3/MinIO storage the way a dragged-and-dropped local file
is (see `tapestry-server-worker`'s S3 section for that presigned-upload flow). This is a
real product/design tradeoff worth surfacing explicitly rather than assuming either way:

- **By reference** (what both reference implementations do): fast, no storage cost, always
  reflects the live external asset — but breaks if the source platform deletes/moves the
  file, is subject to that platform's own hotlinking/rate-limit/CORS policies indefinitely,
  and isn't actually archived by Tapestries.
- **A real copy** ("import as if the user dragged the file in themselves"): durable,
  independent of the source platform's continued availability — but costs storage, and
  requires actually fetching the external asset's bytes (which may need a server-side proxy
  fetch rather than a client-side one, if the source blocks cross-origin binary fetches) and
  pushing them through the same presigned-PUT-URL upload flow a real drag-and-drop upload
  uses, before creating the item against the *new*, internally-hosted URL.

If asked to add a new collection type or single-item resolver, **ask which behavior is
wanted** rather than assuming "by reference" is fine just because that's what the existing
examples do — for an archival project in particular, "the link rotted" is a real, not
hypothetical, failure mode.

## Guardrails

1. **The picker mechanism (`HandleIAImportDialog`, `IAImport`, `import-items-list/`) is real
   upstream code** — don't treat any of it as unverified/reference-only. Only the specific
   `IAImport` member and list component you're adding is new.
2. **Verify all four integration points**, not just the two that are type-checked (see the
   gotchas above).
3. **Don't add a per-type selection cap** — `MAX_SELECTION` is shared.
4. **Surface the by-reference-vs-copy question explicitly** before assuming either is
   correct for a new source.
5. See `tapestry-external-media-sources` for the single-item version of this pattern (and
   the resolver conventions this skill's `core/` additions should follow), and
   `tapestry-server-worker` for the S3 upload flow relevant to the "real copy" alternative
   above.
