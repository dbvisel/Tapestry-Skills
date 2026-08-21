---
name: tapestry-collection-imports
description: Add a new bulk-import source to Tapestries' existing picker dialog — recognizing a URL for a collection of items (a Wikimedia Commons category, an Openverse tag search, an Internet Archive search query) and letting the user choose which to import, up to a selection cap. The picker mechanism itself is real, existing upstream functionality; this skill covers extending it, generalized from reference implementations plus one real (non-fork) implementation against actual upstream — IA search, via an open PR
license: MIT
compatibility: claude-code
depends_on: ["tapestry-external-media-sources"]
skill_discovery_hints:
  - keywords: ["import picker", "HandleIAImportDialog", "IAImport", "collection import", "bulk import"]
  - keywords: ["commons category", "openverse collection", "IA search import", "select all"]
  - keywords: ["import-items-list", "LazyList", "MAX_SELECTION"]
last_verified: 2026-08-21
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
`internetarchive/tapestry-project` `main` with real commit history (code review, bug fixes),
originally built for Internet Archive collections and playlists. **This skill is about
extending that mechanism with a new collection type**, generalized from three example
extensions of exactly this kind:

- **Wikimedia Commons categories** — `https://commons.wikimedia.org/wiki/Category:Fossil_forgeries`
  — still only a reference implementation, found in unmerged exploratory work on a personal
  fork, not present on any long-lived branch.
- **Openverse tag collections** — `https://openverse.org/image/collection?tag=Aztec` — same
  status as Commons: fork-only reference, not upstream.
- **Internet Archive search queries** — `https://archive.org/search?query=subject%3A%22Gondavalekar%22`
  — **this one is no longer just a reference implementation.** As of 2026-08-18 it was built
  as a real `IASearchCollection` addition against actual upstream and opened as a PR
  ([asteasolutions/tapestry-project#96](https://github.com/asteasolutions/tapestry-project/pull/96)).
  As of 2026-08-21 **it's been through two real review rounds (2026-08-20, 2026-08-21),
  both fully addressed and resolved, still open/unmerged** — see "Real PR review feedback"
  below for exactly what each reviewer round asked for; treat those as corrections to how
  this skill described the implementation, not just history. It's the source of most of
  the gotchas below, since it was the first case where the *new* collection type had no
  single representative IA item (a category/playlist resolves to one IA item's metadata
  first; a raw search query never does).

**So as of 2026-08-18, only `IACollection` (a literal IA collection/identifier),
`IAPlaylist`, and (pending merge) `IASearchCollection` exist upstream** — Commons categories
and Openverse tag collections don't yet. Don't tell a user Commons/Openverse bulk import
already works; use this skill as the template for adding those.

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
     for anything unrecognized. If the source URL can carry *other* query params that
     narrow the collection (IA search's real `parseIASearchURLQuery` also reads `tab=` —
     the media-type filter tab a user had open on archive.org — and folds a matching
     `mediatype:` clause into the returned query string), check each such param actually
     does what it looks like before wiring it in — see "Real PR review feedback" below;
     not every value that looks like a type filter is one.
   - **A cheap, count-only fetch**, separate from the full member-listing fetch:
     `fetch<X>CollectionCount(id)`. Commons' `fetchCommonsCategoryFileCount` hits a
     lightweight `categoryinfo` endpoint (no thumbnails, no per-file lookups) specifically so
     the item factory (next step) can show "N files" and decide whether to open the picker
     at all, without paying for the expensive full listing until the user actually opens it.
     **If the platform's search backend already reports a total on every query** (IA's
     Solr-backed `advancedsearch.php` sets `response.numFound` regardless of `rows`), the
     "cheap" probe doesn't need its own endpoint — `fetchIASearchCount` is just the normal
     search call with `pageSize: 1`.
   - **A full member-listing fetch**, used once the picker is actually open:
     `fetch<X>CollectionMembers(id)`, returning enough per-item data for the list UI (an id,
     a thumbnail if cheaply available, whatever metadata the confirm step needs). **Cache
     this per collection id for the page's lifetime** if fetching it is at all expensive —
     Commons' cache means the picker's own list, its "select all," and this skill's later
     confirm step's resolution all share one fetch rather than tripling the request count for
     what the user experiences as a single action. Evict a failed fetch from the cache so a
     transient error doesn't permanently poison it for the session.
     **This doesn't have to live in `core/` at all** — it only needs to if `core/` doesn't
     already expose a generic query primitive for the platform. IA's real
     `IASearchCollection` implementation added no `fetchIASearchMembers` to
     `core/src/internet-archive.ts`; the paginated, windowed fetch (`requestSearchItems`)
     lives directly in step 6's list component, built on the existing `iaAdvancedSearch`
     primitive, and step 4's "select all" branch imports and reuses that same function. Only
     add a core member-listing export if the platform has no such reusable primitive yet
     (true for a first-time Commons/Openverse integration).
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
     the dialog's `onToggleAll` prop.
     **Prefer parameterizing an existing sibling over copying it, when the underlying query
     is genuinely "the same list, different filter."** An earlier draft of this skill
     recommended copying a sibling as scaffolding and only sharing its `styles.module.css` if
     the fields matched — that's exactly what `IASearchCollection`'s first draft did
     (`search-list/` as a near-total copy of `collection-list/`, differing only in what string
     got passed as `q`), and a real reviewer rejected it on sight: "This looks like an almost
     complete copy of IACollectionList. Why don't we just remove IACollectionList and rename
     this to IASearchList instead. Then for collection we should just pass the query
     `collection:${collectionId}`\[,\] and the appropriate placeholder." The generalizable
     lesson: **if a new collection type's list differs from an existing one only in the raw
     query string handed to the same underlying search API, don't create a sibling
     component at all — parameterize the existing one by that raw query string**, expressing
     the old type as a special case of the new, more general shape (a "collection" is just
     `collection:<id>` plus the always-required `AND NOT mediatype:collection` exclusion
     below), and delete the now-redundant component. Reserve an actual separate sibling
     component for cases that truly need a different data shape or a different underlying API
     (Commons' `commons-category-list/` legitimately differs this way — it's not just a
     different query string against the same search endpoint).
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
- **A collection type with no single representative item breaks more than the four
  checklist integration points — it can break existing shared code's field assumptions.**
  `createNewItems` in `handle-ia-import-dialog/index.tsx` destructured
  `{ id, metadata: { mediatype } }` straight out of its `IAImport` parameter, and
  `import-details/index.tsx`'s props did the same — both safe when every existing member
  (`IACollection`, `IAPlaylist`) resolved one IA item's metadata before the picker ever
  opened. A raw search query has no such item, so `IASearchCollection` carries no `id`/
  `metadata` — **and `tsc` catches this immediately**: destructuring a field off a
  discriminated union errors at every existing call site that isn't already `id`/`metadata`
  on *all* members, the moment the new member is added to the union (verified: reverting to
  the old blind destructure with `IASearchCollection` present gives
  `TS2339: Property 'id' does not exist on type 'IAImport'`). So this is a *third*
  compile-time forcing function beyond the two `Record` maps step 4 names — but only for
  collection types that omit fields the existing members all share. A new member that keeps
  the same shape as its siblings (a different `id`-bearing collection, say) would compile
  cleanly through these same call sites with no warning, so don't rely on this catching
  every case — it only fires when the new member's shape is a strict subset of what existing
  code destructures.

## Real PR review feedback (2026-08-20 and 2026-08-21)

[asteasolutions/tapestry-project#96](https://github.com/asteasolutions/tapestry-project/pull/96)
(the `IASearchCollection` PR this skill is partly built from) has now been through two real
review rounds, not yet merged as of this writing. Every comment generalizes beyond IA search
specifically — folded in here as corrections, not just a status update. First round
(2026-08-20):

- **Don't accept a near-duplicate sibling component, even as an intermediate step** — see
  the rewritten step 6 above. The reviewer's fix was to delete the duplicate and
  parameterize the survivor by a raw query string, with the old type expressed as a special
  case of the new one (`collection:${collectionId}` plus the exclusion below). If you catch
  yourself about to `cp` a sibling list component and change only the query-builder
  function, stop and parameterize instead — a reviewer will very likely ask for exactly this,
  so doing it upfront saves a review round-trip.
- **Always exclude collections from collection/search results**: `AND NOT
  mediatype:collection` on every IA query this skill's pattern builds, not just the literal
  `IACollection` case. It's easy to add this once (in the original `IACollection` query) and
  forget it when a sibling/generalized query is introduced later — the reviewer caught it
  missing from *both* the new list's query and the cheap count-probe query (`total` would
  otherwise count collection-type results that can never actually appear in the list,
  understating what's importable versus what the header claims). If you consolidate per the
  point above, this exclusion only needs to live in one place instead of two.
- **Merge same-platform factories that both just recognize a URL shape into one factory**,
  rather than registering several separate top-level entries in `ITEM_FACTORIES` for the
  same platform. The reviewer asked for exactly this ("Can we use one IA factory which
  handles all IA logic?") after `IASearchCollection` added a second, entirely separate
  factory (`iaSearchCollectionFactory`) alongside the existing `iaCollectionFactory` — check
  each new URL shape inside one combined factory function instead (try the more specific
  parse first, fall through to the next), and register only that one function.
- **Prefer returning the plain value over a single-field wrapper object** from a
  parse-URL-and-extract helper, and name the function after exactly what it returns. The
  reviewer's concrete suggestion: `parseIASearchURL(source): { query: string } | null` should
  just be `parseIASearchURLQuery(source): string | null` — there was only ever one field, so
  the wrapper object added a destructuring step at every call site for no benefit. This
  applies to any new `parse<X>...URL` helper this skill's checklist has you write: only wrap
  the return value in an object if there's genuinely more than one field to carry, or if
  callers need to distinguish "matched, but a field was empty" from "didn't match" (a bare
  `string | null` return conflates an empty-but-present value with no-match, which a `{
  query: string } | null` shape currently in the codebase this skill was built from avoids -
  weigh that against the reviewer's simplification if it matters for your platform).
- **The "cheap count probe is unavoidably a full search request" tradeoff got explicit
  reviewer sign-off**, not just this skill's own assumption: "this request might be a bit
  slow, but there is no other way to tell if the search result returns any items." That's
  independent confirmation of the "Distinguish a cheap 'how many' probe from the expensive
  full listing" gotcha above for IA specifically (Solr-backed `advancedsearch.php` always
  reports `numFound`, so `pageSize: 1` genuinely is the cheapest possible probe there) — no
  action needed, just don't second-guess this particular tradeoff if asked to optimize it
  further for IA.

Second round (2026-08-21), after round 1's fixes landed:

- **A helper must not reach into another helper to transform its own argument — do that at
  the call site.** `fetchIASearchCount` had grown to call `excludeIACollections(query)`
  internally before searching. The reviewer's exact words: "`fetchIASearchCount` should not
  depend on `excludeIACollections`, rather we should modify the argument before it is
  passed." Fixed by having `fetchIASearchCount` take the query as-is, and its one call site
  apply `excludeIACollections` explicitly before calling it. The generalizable lesson: when
  one function's *purpose* is generic (searching, in this case) and another encodes a
  *policy* specific to one caller's needs (excluding collections, which only this feature
  cares about), keep them composable and separate — don't let the generic function silently
  bake in a caller-specific policy. Apply the same scrutiny to any helper this skill's
  checklist has you write that calls another of its own siblings internally.
- **Comment discipline at this upstream is stricter than "explain the non-obvious why" —
  it's "core logic and complex math only," full stop.** Three comments were removed on
  request in this round alone, and one of them was exactly the kind of "hidden constraint"
  comment that's normally the right call (explaining *why* `excludeIACollections` exists at
  all — because a collection is itself a search result but never an importable item). The
  reviewer's words, twice: "We put comments only on core logic and complex math, we don't
  need a comment here" / "This comment is also not necessary." Don't assume a well-reasoned
  "why" comment is safe here just because it clears the general "non-obvious constraint" bar
  — if the surrounding code isn't itself core logic or complex math, expect it removed, and
  consider leaving out speculative explanatory comments on first submission to this upstream
  rather than having them flagged.
- **Reviewers verify against the live external product, not just the diff — and you can
  get ahead of it by doing the same before you're asked.** A reviewer noticed archive.org's
  own search UI has a `tab` URL parameter (filters results to one media type — Books, Video,
  Audio, etc.) purely by using the real site, and asked whether this skill's URL parser
  should honor it. Answering this required the same kind of live verification this skill set
  already values elsewhere: which tab produces which `tab=` value (checked against the real
  site with a headless browser, since the values aren't documented — `tab=movies`,
  `tab=etree`, `tab=texts`, etc.), and whether the resulting `mediatype:` constraint actually
  works against the specific API this code calls (confirmed against a live
  `advancedsearch.php` request, not assumed from the tab value alone). The gotcha this
  surfaced: not every tab corresponds to a real `mediatype:` value — `tab=radio`/`tab=tv`
  aren't part of the media-type facet at all, `tab=fulltext` ("Text Contents") is a
  search-mode toggle rather than a type filter, and `tab=collection` *is* a real value but
  must still be rejected, since honoring it would AND against this skill's own mandatory
  `NOT mediatype:collection` exclusion and silently return zero results every time. Don't
  assume a facet value that's visible in a URL is safe to pass through unconditionally —
  verify each one actually does what its label implies before wiring it in.

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
4. **Parameterize an existing sibling list component rather than copying it**, when the only
   real difference is the query string handed to the same underlying search API — see "Real
   PR review feedback" above. Always exclude collection-type results (`AND NOT
   mediatype:collection` for IA) everywhere that query gets built, including the cheap count
   probe.
5. **Surface the by-reference-vs-copy question explicitly** before assuming either is
   correct for a new source.
6. **Don't let a generic helper silently bake in a caller-specific policy** — if only one
   caller needs a transformation (excluding collections, say), apply it at that call site,
   not inside the generic helper it calls. See "Real PR review feedback" (2026-08-21) above.
7. **Expect comments to be removed even when they explain a genuinely non-obvious "why"** —
   this upstream's bar is "core logic or complex math," not "non-obvious constraint." Lean
   toward no comment on a first submission here unless the surrounding code is itself
   complex.
8. **Verify a new URL parameter actually means what it looks like before honoring it** — not
   every value visible in a real URL corresponds to the API constraint its label implies
   (see the `tab=` gotcha above). Check against the real service, not just the URL shape.
9. See `tapestry-external-media-sources` for the single-item version of this pattern (and
   the resolver conventions this skill's `core/` additions should follow), and
   `tapestry-server-worker` for the S3 upload flow relevant to the "real copy" alternative
   above. See `tapestry-pr-conventions` for the review norms observed on this PR that
   generalize well beyond collection imports specifically.
