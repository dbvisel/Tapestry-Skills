---
name: tapestry-pr-conventions
description: Code-review conventions actually observed from real asteasolutions/tapestry-project maintainers (zmarinov-astea, and now also Sachanski) across four real PRs (#96, IA search-query import; #109, client-side HEIC import; #123, Clover IIIF viewer rework; #112, Openverse/Wikimedia Commons collection import), nine-plus review rounds, and one direct design question outside GitHub — comment discipline (including a TODO exception), merge-don't-duplicate (for both business logic and shared UI/list components), composition over internal dependency, trust the strongest already-available signal (including real file-content sniffing over metadata/extension guesses, but check its own boundary conditions), colocate small helpers with their siblings instead of a dedicated file, match the full input space of the pipeline you're plugging into, don't fall back where the primary signal is already reliable, fit the actual API surface instead of an assumed one, distinguish a missing value from a meaningless-but-present one, prefer a documented known limitation over a partial workaround for a rare upstream bug, verify a suspected dependency-declaration gap by reading the real package.json, replace ternary sprawl on a discriminant field with one per-branch config function, don't reach for a server-side proxy before checking real CORS support and simpler client-side fixes, give a discriminated union direct members instead of nesting a second dimension inside one, rename a type once its scope outgrows its name — plus a pre-submission self-review checklist to catch these before the reviewer does, the concrete gh/GraphQL commands (including a real empty-review-body gotcha and a re-check-before-assuming-a-thread-is-pending gotcha) for replying to and resolving PR review comments, and a project-standing (not reviewer-observed) ASD-STE100 writing-style rule for comments and replies. Not invented best practices; specific, verified feedback from the actual gatekeepers who review PRs to this repo, clearly separated from this project's own style preferences
license: MIT
compatibility: claude-code
depends_on: ["asd-ste100"]
skill_discovery_hints:
  - keywords: ["PR review", "code review conventions", "pull request feedback", "tapestry-project PR"]
  - keywords: ["resolve review thread", "reply to PR comment", "gh api pulls comments", "GraphQL resolveReviewThread"]
  - keywords: ["comment discipline", "merge duplicate components", "composition over internal dependency"]
  - keywords: ["authoritative signal over derived guess", "mediaType vs file extension", "narrowing an existing pipeline's input space", "speculative dead code", "unused generality"]
  - keywords: ["pre-submission checklist", "self-review before PR", "empty review body", "gh pr view comments empty", "catch review feedback before opening a PR"]
  - keywords: ["Blob vs File", "unnecessary type wrapping", "fallback only where needed", "check library API signature", "manufactured metadata unused filename"]
  - keywords: ["ASD-STE100", "Simplified Technical English", "comment writing style", "PR reply writing style", "reduce verbosity"]
  - keywords: ["fileTypeFromBlob", "magic bytes", "content sniffing over extension", "file-type npm package", "colocate helper existing file", "TODO comment exception", "explicit return type inferred"]
  - keywords: ["known limitation vs workaround", "partial fix for upstream bug", "accept library bug", "third-party viewer bug", "OpenSeadragon known limitation"]
  - keywords: ["verify dependency package.json", "does this package declare X", "check node_modules package.json before workaround", "re-check review thread for further reply", "thread overruled"]
  - keywords: ["maps instead of ternaries", "per-branch config function", "ternary sprawl", "discriminant field dispatch"]
  - keywords: ["reject server-side proxy", "CORS instead of proxy", "autoReload false", "rate limit background reload"]
  - keywords: ["direct union member vs nested platform union", "rename type outgrows scope", "flatten nested discriminated union"]
last_verified: 2026-09-14
---

What real reviewers at `asteasolutions/tapestry-project` actually asked for, across
nine-plus real review rounds on four real PRs (plus one direct follow-up question from
zmarinov-astea, outside GitHub — see point 13): [#96](https://github.com/asteasolutions/tapestry-project/pull/96)
(the IA search-query bulk-import feature — see `tapestry-collection-imports`, which this
skill's findings were first folded into before being generalized out here),
[#109](https://github.com/asteasolutions/tapestry-project/pull/109) (client-side HEIC
import — see `tapestry-content-types`' variation section),
[#123](https://github.com/asteasolutions/tapestry-project/pull/123) (Clover IIIF viewer
rework — see `tapestry-content-types`' IIIF reference), and
[#112](https://github.com/asteasolutions/tapestry-project/pull/112) (Openverse/Wikimedia
Commons collection import — see `tapestry-collection-imports`, points 20-22). **Points
1-13 and 18-22 are all `zmarinov-astea`**, verified across all four PRs — feedback that
recurs in the same shape across unrelated features is a stable preference of that
gatekeeper, not a one-PR quirk. **Points 14-17 are a second reviewer, `Sachanski`**, on a
later round of PR #109 and a round of PR #96 — their feedback so far is consistent in
spirit with `zmarinov-astea`'s (avoid unneeded complexity, don't duplicate, prefer the
strongest real signal), so treat both as this repo's actual review bar rather than one
person's idiosyncrasy, but keep the attribution honest since it's only been one round
each from Sachanski so far — less evidence than points 1-13/18-22 have. Every piece of feedback below was
phrased as a general principle, not a feature-specific nitpick, so treat it as worth
applying proactively on any future PR to this project rather than waiting to be told
again. Whoever is about to open or update a PR here — this skill is meant to be run as a
self-review pass on your own diff (see "Pre-submission checklist" below), not just
consulted after a reviewer has already commented.

## When to use this skill

- Before opening or updating a PR against `asteasolutions/tapestry-project` — run the
  pre-submission checklist below against your diff first
- "Why did the reviewer ask for X" / anticipating what a reviewer here will flag
- Replying to or resolving PR review comments via `gh`
- Any skill in this repo whose checklist ends in "open a PR" should point here

## What this reviewer actually asked for, verified across six rounds on two PRs

1. **Don't add a near-duplicate sibling next to an existing near-identical one — merge
   them and parameterize by whatever actually differs.** Round 1: a new `search-list/`
   component was ~90% identical to the existing `collection-list/`, differing only in
   the raw Solr query string passed in. Reviewer: *"This looks like an almost complete
   copy of IACollectionList. Why don't we just remove IACollectionList and rename this to
   IASearchList instead."* Same principle, same round, at the factory level: two
   IA-URL-recognizing factories existed side by side; reviewer: *"Can we use one IA
   factory which handles all IA logic?"* Both got merged into one component / one factory
   that branches on the URL shape internally, with the old case expressed as a special
   case of the new one's parameter (a "collection" is just `query: collection:<id>`).
2. **Return the plain value, not a single-field wrapper object — and name the function
   after exactly what it returns.** Round 1: `parseIASearchURL(source): { query: string }
   | null` became `parseIASearchURLQuery(source): string | null` on request. Only wrap a
   return value in an object if there's genuinely more than one field, or callers need to
   distinguish "matched but empty" from "no match."
3. **A generic helper must not reach into another helper to transform its own argument —
   apply that transformation at the call site instead.** Round 2: `fetchIASearchCount`
   had grown to call `excludeIACollections(query)` internally before searching. Reviewer:
   *"fetchIASearchCount should not depend on excludeIACollections, rather we should modify
   the argument before it is passed."* The generalizable shape: one function encodes a
   generic capability (searching), another encodes a policy specific to one caller
   (excluding collections, which only this one feature needs) — keep them composable and
   separate; don't let the generic one silently absorb a caller-specific policy.
4. **Comment discipline here is "core logic and complex math only" — stricter than "explain
   the non-obvious why."** Round 2, three comments removed on request, verbatim: *"We put
   comments only on core logic and complex math, we don't need a comment here"* (twice,
   worded almost identically, on two different comments) and *"This comment is not
   necessary"* (once more). One of the three was exactly the kind of comment that's
   normally the right call by general standards — it explained a real, non-obvious hidden
   constraint (why a helper excludes collections at all: a collection is itself a search
   result but never an importable item). **That didn't save it.** Don't assume a
   well-reasoned "why" comment is safe here just because it clears the general bar for
   "worth explaining" — if the surrounding code isn't itself core logic or complex math,
   expect it flagged. Default to no comment on a first submission to this repo unless the
   code is genuinely intricate.
5. **Expect the reviewer to verify against the live external product, not just read the
   diff — and get ahead of it by doing the same yourself.** Round 2: the reviewer found
   that archive.org's own search UI has a `tab=` URL parameter (a media-type filter) purely
   by using the real site, and asked whether it should be honored. Answering that well
   required the same kind of live verification: checking which tab produces which `tab=`
   value against the real site (undocumented — had to drive a real browser to find
   `tab=movies`, `tab=etree`, etc.), and confirming the resulting query actually works
   against the specific API this code calls (a live `advancedsearch.php` request, not an
   assumption). It also surfaced a real gotcha worth generalizing: **a URL parameter that
   looks like a type filter isn't necessarily one for every value** — `tab=radio`/`tab=tv`
   don't correspond to any real facet value, `tab=fulltext` is a search-mode toggle, and
   `tab=collection` is a real value that still had to be rejected because it would
   contradict this feature's own mandatory collection-exclusion. Verify each value against
   the real service rather than assuming a parameter is safe to pass through wholesale.
6. **Trust the strongest signal already available before falling back to a weaker derived
   one.** PR #109, round 1: a new `heicImageFactory` decided "is this HEIC" purely from a
   filename extension, even though the surrounding pipeline (`parseMediaSource`) had
   already resolved a real `mediaType` (from the browser's `File.type`, a mime lookup, or
   the server's content-type proxy for a URL) and was passing it in as an argument the
   factory ignored. Reviewer: *"This is not a reliable way to check if the source is a
   heic image. We should first check the mediaType if it is image/heic or image/heif ...
   if not, proceed only if the file extension is heic or heif."* The generalizable shape:
   when a stronger signal is already sitting in scope (an argument, a prior resolution
   step), check it first — don't re-derive a weaker approximation of the same fact from
   scratch and let the strong one go unused.
7. **Match the full input space of the pipeline you're plugging a new branch into — don't
   silently narrow it to whatever you tested with.** Same comment, second half: *"If the
   source is a link, download the image first, and then use maybe mediaSourceToBlob."*
   `heicImageFactory` only branched on `File` instances and returned `null` for every
   string (URL) source, even though the `ItemFactory` pipeline it was added to already
   treats `File` and URL sources uniformly (both flow through the same `mediaType`
   resolution before reaching any factory). The fix wasn't a special case for links — it
   was recognizing that "download the source first" already had a shared helper
   (`mediaSourceToBlob`) built for exactly this, so honoring the pipeline's existing input
   space was a small addition, not new design work.
8. **Expect literal-minded scrutiny of whether code matches what actually calls it — remove
   generality nothing exercises rather than leaving it "just in case."** PR #109, round 1,
   a one-line comment: *"why are we splitting by ? or # when we are passing a file name?"*
   `isHeicSource` stripped a query string/fragment before checking an extension — logic
   shaped for a URL, on a helper that (at the time) was only ever called with a bare
   `File.name`. The reviewer reads code against its real call sites, not its most general
   imaginable input; speculative handling for a case nothing currently produces reads as a
   bug question, not defensive engineering. Fixed by removing the stripping from
   `isHeicSource` entirely and moving "reduce a URL down to a bare filename" to a proper
   `new URL(source).pathname`-based helper at the one call site that actually has a URL —
   `isHeicSource` itself stayed a genuinely single-purpose, filename-only helper even after
   point 7's fix made the factory accept URL sources too. The lesson isn't "never
   generalize," it's "put the generalization at the point that actually needs it, not
   inside a helper whose own contract doesn't call for it."
9. **Don't build a fallback path for an input branch that already has a fully reliable
   primary signal.** PR #109, round 2, on the round-1 fix to point 6/7 above: *"This is
   again too complicated, if the given mediaType is not heic, check the filename extension
   only if the source is a File."* The round-1 fix had applied the extension-fallback to
   *both* File and URL sources, deriving a filename from the URL's path just to have
   something to check. But a URL source's `mediaType` always comes from the server's
   content-type proxy — it doesn't get meaningfully less reliable the way a browser's
   `File.type` can be empty — so a fallback for that branch was solving a problem that
   doesn't occur. **"Again"** is the reviewer's own word: this is the same shape as point
   8 (unused generality), but about a whole conditional branch's *behavior*, not dead code
   in a helper — reserve fallback/defensive logic for the specific input branch where the
   primary signal can genuinely be missing, not every branch uniformly.
10. **Pass data in the loosest type the actual API accepts — don't wrap/reshape it to fit
    an assumed stricter interface, and don't manufacture metadata nothing downstream
    reads.** Same round, a second comment: *"Why are we creating a new file when the
    heic-to module can accept a simple Blob? Also when then returned file from
    convertHeicFile can have a random filename, it is not important, for example
    converted.jpg."* The code wrapped a downloaded `Blob` in a `new File(...)` purely to
    satisfy a `File`-typed parameter that turned out to be assumed, not required —
    `heic-to`'s `heicTo({ blob, ... })` takes a plain `Blob`, and the "real" filename it
    was being constructed to carry was never read by anything after conversion. Check the
    library's actual signature before reshaping data to match a narrower type than it
    needs, and don't thread a piece of information through a data structure just because
    the type technically wants a name for it — a fixed placeholder (`converted.jpg`) is
    fine when nothing consumes the value.
11. **Before deriving a fact yourself, check whether an argument you already have fully
    subsumes that derivation somewhere upstream in the same call chain — not just
    whether a *stronger signal exists* (point 6), but whether the strong signal already
    *is* the weak one plus more.** PR #109, round 3 (an otherwise-approving review):
    *"Can we use only HEIC_MEDIA_TYPES.includes for our isHeic check? The extension is
    already read at line 362 (mime.getType(source.name) ?? '') in
    client/src/model/data/utils.ts."* Point 6 had already moved mediaType to be checked
    first, but kept a same-shaped extension fallback "just in case" mediaType came back
    empty — missing that for a `File` source, `mediaType`'s own resolution (`getMediaType`)
    *already* falls back to the exact same `mime.getType(source.name)` lookup before ever
    reaching this factory. The fallback looked strictly redundant — checking the extension
    a second time seemed like it could never produce a different answer.
    Trace an argument back through what actually produced it before assuming you need to
    re-derive part of it defensively. **Caveat, found one round later (point 13): "strictly
    redundant" was itself an overclaim** — it only followed from assuming `getMediaType`'s
    fallback triggers whenever the extension check would help, which turned out to be false
    for a specific truthy-but-generic value. Tracing an argument to its source tells you
    what the *common case* produces; it doesn't by itself prove every input reaches that
    source the same way — check the boundary conditions of the upstream logic too, not just
    that it exists.
12. **When a reviewer asks you to verify platform-specific runtime behavior you have no
    access to (a real Windows machine, in this case), do the closest available research
    and disclose it as research, not as an empirical test — don't skip it, and don't
    silently present it with the same confidence as something you actually ran.** Same
    comment, second half: *"See if that works properly on windows."* No Windows machine
    or browser-automation tool was available; targeted web research (documented Chromium
    behavior: `File.type` for `.heic` is empty without the Windows HEIF codec pack, which
    is exactly the falsy case the code already falls through on) stood in for a live test,
    and the reply to the reviewer said so explicitly, including the one edge case research
    couldn't rule out (a third-party-corrupted MIME registry entry). This is the same
    "verify against real behavior" instinct as point 5, extended to platform behavior
    instead of an external website, and to research-as-substitute when literal access
    isn't possible. **Strengthened one question later**: asked (by the user, not this
    reviewer) whether the same question was testable on Linux instead of Windows — and it
    was, for real, without any research-as-substitute caveat needed. Linux's MIME detection
    (`shared-mime-info`, which Chromium's Linux `File.type` lookup consults) is an
    installable, versioned package, so six real Ubuntu/Debian Docker images
    (`docker run --rm <image> bash -c 'apt-get install -y shared-mime-info; grep -i heic
    /usr/share/mime/packages/*'`) gave a genuine, verified version boundary: no
    `.heic`/`.heif` glob at all below `shared-mime-info` 1.15 (Ubuntu 18.04's `1.9-2`),
    present from `1.15-1` (Ubuntu 20.04) onward. **When the literal target platform is
    inaccessible but a real, cheaply-spun-up adjacent system shares the underlying
    mechanism, actually testing that adjacent system beats researching the original one** —
    it produced the concrete finding in point 13 below, which pure Windows documentation
    reading would not have surfaced.
13. **A non-empty return value isn't automatically a reliable positive signal — some
    values are themselves "I don't know" sentinels.** Following up on the Linux testing
    above (not a reviewer comment, but the same real gatekeeper's original design
    question, relayed directly rather than through a PR comment thread): *"should we
    check the .heic extension additionally if the browser gives us image/png, or
    application/octet-stream?"* `getMediaType`'s own fallback
    (`source.type || mime.getType(...)`) only activates when `source.type` is *falsy* —
    but the real Linux testing above showed a system with no MIME mapping for an
    extension reports the **truthy** generic sentinel `application/octet-stream`, not an
    empty string, which silently defeats a falsy-only fallback. The fix isn't "trust
    mediaType less" across the board (a concrete `image/png` is a real positive claim,
    worth trusting over the extension) — it's specifically recognizing the small set of
    known "unknown" sentinel values and treating *those* as equivalent to no signal,
    while still trusting every other concrete value. Don't let "does this value exist"
    stand in for "does this value mean anything."

14. **Colocate a small, one-off helper with its closest sibling in an existing file —
    don't give it a dedicated single-function file.** PR #109, Sachanski's round:
    `convertHeicFile` lived alone in a new `client/src/lib/heic.ts`. Reviewer asked for
    it to move into the existing `client/src/lib/media.ts`, next to `compressImage` —
    another single-purpose image-transform helper already living there. The file was
    deleted, the function moved, all imports updated. The generalizable shape: before
    creating a new file for one function, check whether an existing file already holds
    functions doing the same *kind* of work (here: "transform a media file for import")
    and put the new one there instead — a dedicated file is for something that actually
    needs its own module boundary, not every helper that happens to be new.
15. **The strongest available signal for "what kind of file is this" is the file's own
    bytes, not its name, extension, or browser-reported MIME type — and an
    already-installed dependency may already do this.** PR #109, Sachanski's round,
    superseding the entire mediaType/extension back-and-forth in points 6, 9, 11, and 13
    above: after four rounds across two reviewers debating which of `File.type` or a
    filename extension to trust and when, Sachanski's fix used `fileTypeFromBlob`/
    `fileTypeFromBuffer` from the `file-type` package — already a project dependency,
    already imported elsewhere in this same file (`item-factories.ts`) for `.webloc`
    detection — to read the file's actual magic bytes instead of trusting either weaker
    signal. This is stronger than either signal points 6-13 debated: a browser-reported
    `mediaType` can be empty or a generic sentinel (point 13), and a filename extension
    can be wrong or missing outright (the original concern zmarinov-astea raised in
    point 6 was specifically "an incorrect or missing extension on some Linux systems"
    — magic-byte sniffing satisfies that concern directly, without needing any
    extension fallback at all). **The lesson isn't just "use file-type instead of mime"
    — it's that none of us (across two reviewers and four rounds) checked whether an
    even more authoritative signal than the ones being argued about was already sitting
    in the codebase as a dependency.** Before extending a signal-priority chain (weak
    signal → weaker fallback → weakest fallback), check whether the *strongest possible*
    signal (the actual file content) is available and already has a library for it,
    rather than only ever choosing between the signals already in the discussion.
16. **Don't write an explicit return type annotation when it's inferred and
    unambiguous.** PR #109, Sachanski's round: `convertHeicFile(blob: Blob):
    Promise<File>` had its `Promise<File>` return type annotation removed on request —
    TypeScript already infers it correctly from the function body, and the codebase's
    existing convention (e.g. `compressImage` right next to it) doesn't annotate
    inferred return types either. Match the surrounding file's own convention on this
    rather than adding an annotation "for clarity" by default.
17. **A TODO comment is the one exception to point 4's "no comments" bar — but only
    when a reviewer explicitly asks for exactly that, to flag a deliberately-deferred
    piece of cleanup.** PR #96, Sachanski's round: the reviewer flagged real, sizeable
    duplication between two branches of `ImportDetails` (an IA-shaped branch and the
    new `OpenverseCollection` branch) but, rather than asking for an immediate merge
    (contrast point 1, where zmarinov-astea asked for exactly that on a similar-shaped
    finding), said the extraction could wait and asked for `// TODO: Extract a shared
    layout component. This removes the duplication between the two branches below.`
    to be added instead. This is different from a self-initiated "why" comment (which
    point 4 rules out) — it's an explicit, reviewer-requested marker for work everyone
    has agreed to defer, not an explanation of current logic. Add the TODO with
    (approximately) the reviewer's own wording when this happens; don't extend it into
    a general license to leave TODOs for deferred cleanup on your own initiative.
18. **Reject a partial workaround for a rare upstream-library bug in favor of accepting
    it as a known limitation — especially when the workaround doesn't even fully solve
    the problem.** [PR #123](https://github.com/asteasolutions/tapestry-project/pull/123)
    (Clover IIIF viewer rework, zmarinov-astea): a real, reproducible OpenSeadragon bug
    broke a second simultaneously-open instance of a single-canvas IIIF manifest. The fix
    routed single-canvas manifests through Clover's lower-level `<Image>` component with
    `isTiledImage` forced, sidestepping the buggy code path for that one case, while a
    narrower version of the same bug still affected multi-canvas manifests (unfixable
    without dropping Clover's full `<Viewer>` entirely). Reviewer: *"it adds too much
    overhead for not a rare use case. Also the bug will persist for multi-canvas iiifs
    even with your workaround. So remove the CloverImage logic."* The generalizable
    shape: a workaround that only covers part of a bug's surface, at the cost of a real
    second code path, is a worse trade than documenting the bug as a known limitation and
    keeping one code path — same "avoid unneeded complexity for an edge case" instinct as
    points 8/9, extended from data-shape fallbacks to a third-party UI library's own bug.
19. **Verify a suspected "this dependency doesn't declare what it needs" claim by reading
    that dependency's own `package.json`, not by trusting an earlier, unverified read of
    it.** Same PR, same reviewer: after I added a Vite `resolve.alias` (routing
    `@asteasolutions/epub-reader`'s internal bare `lodash` import to the already-declared
    `lodash-es`) on the assumption that `epub-reader` "declares only `lodash-es`,"
    reviewer: *"Bare lodash is still a dependency. Leave it like that and remove the
    aliases."* Checking `node_modules/@asteasolutions/epub-reader/package.json` directly
    showed the assumption was simply wrong — it declares a real `"lodash": "^4.17.21"`
    dependency of its own, already resolvable through normal npm hoisting with no alias
    needed, including in an isolated single-workspace Docker build. The alias was solving
    a problem that did not exist. Before building a workaround for an apparent dependency
    gap, read the actual `package.json` (or lockfile entry) in `node_modules`, not a
    summary or a prior session's memory of it.
20. **Replace a ternary chain branching on a discriminant field with one function
    returning a per-branch config object, once there's more than one such branch or
    once extensibility comes up.** [PR #112](https://github.com/asteasolutions/tapestry-project/pull/112)
    (Openverse/Wikimedia Commons collection import): a component had five separate
    `platform === 'openverse'` ternaries/conditionals scattered through it (detail
    columns, detail header, item media-type fallback, empty-placeholder text, which
    `fetch*` function to call), and a sibling component had a two-level nested ternary
    for a label/noun pair. Reviewer: *"Create maps instead of having so many ternary
    operators here and on other places. What will happen when we import even more
    collection types?"* Collapsed each into one small `if`/`return` function building a
    single config object per branch (`describeExternalCollection`), and into per-type
    components for the label case. **"Maps" here is shorthand for "one dispatch point
    per concern," not literally a `Record` object** — a literal `Record` cannot
    type-safely map a discriminated union to differently-shaped per-variant data
    without an unsafe cast, so a function with an early return per branch is the
    correct TypeScript idiom, and satisfies the same underlying ask (adding a branch
    means touching one place, not every scattered ternary).
21. **Don't reach for a server-side proxy to protect a rate-limited third-party API
    before checking whether it's actually needed.** Same PR: a first draft routed every
    Openverse/Wikimedia Commons request through a server-side proxy with a Redis cache,
    reasoning that centralizing and caching requests would reduce the chance of
    tripping a rate limit. Reviewer: *"I don't think we need to route anything to the
    server, just to try avoiding the request limits. These imports don't happen that
    often and shouldn't trigger the restrictions. We could just disable the autoreload
    on our lazy list for the collection import."* Verified before agreeing: both
    platforms send real `access-control-allow-origin: *` headers on the actual
    endpoints called (checked with a live `curl -D -`, not assumed), so nothing blocked
    calling them directly from the browser — and the actual rate-limit risk traced back
    to an existing list component's `autoReload` default (`true`, polling the same
    request every 10 seconds for as long as a dialog stayed open), not to picker
    pagination itself. Removed the proxy and its cache entirely; disabled `autoReload`
    on the affected list. The generalizable shape: before adding server-side
    infrastructure to guard against a third-party rate limit, check (a) whether the API
    genuinely requires it (CORS support is a fast, concrete check), and (b) whether the
    real trigger is something narrower and already fixable client-side, like a
    background-polling default — a proxy is the more complex fix and should lose to a
    simpler one whenever either check comes back favorable.
22. **Give a discriminated union direct members per real-world case — don't nest a
    second dimension (like a platform) inside one shared member.** Same PR: a first
    draft added one `ExternalCollection` union member shaped as `{ type:
    'ExternalCollection'; total: number } & ({ platform: 'openverse'; ... } | {
    platform: 'wikimedia-commons'; ... })`, reasoning that fewer top-level members meant
    less integration-point surface for a future platform. Reviewer: *"the external
    collection type should not exist, instead OpenverseCollection and
    wikimediaCommonsCategory should be direct subtypes."* Shipped as two ordinary
    top-level members with no `platform` field at all, matching every other member of
    the same union. The "fewer integration points" argument for nesting didn't hold up
    in practice — call sites needed one branch per platform either way, and the direct
    shape reads the same as every other member instead of being the one exception. Same
    round, a related naming correction: *"Since this type is no longer strictly
    connected to IA, can we rename it to CollectionImport?"* — the type, and every
    identifier carrying its old name (a field, two `Record` maps, a component and its
    directory), had been named for what the mechanism used to be, not what it had grown
    into. **Expect both corrections together whenever a mechanism named after one
    specific case starts serving a second, different case**: check whether its name is
    still accurate, and whether a wrapper/nesting shape it uses to "save" top-level
    members should just be flattened into direct ones instead.

## Pre-submission checklist: catch these before the reviewer does

The point of tracking this reviewer's feedback across multiple PRs is to stop paying for
it one review round-trip at a time. Before opening or updating a PR against this repo,
walk your own diff against each finding above as a self-review pass — most of it is
checkable without waiting for a live comment:

1. **Duplication** — does this add something ~90% identical to existing code, differing
   only in a value? Merge them and parameterize by whatever actually differs (point 1).
2. **Return shape** — does a function return a single-field wrapper object? Return the
   plain value and name the function after exactly what it returns (point 2).
3. **Composition** — does a "generic" helper call another helper to apply a
   caller-specific transformation to its own argument? Move that transformation to the
   call site instead (point 3).
4. **Comments** — does any comment do more than explain genuinely core logic or complex
   math? Delete it — a well-reasoned "why" comment gets flagged here too (point 4).
5. **Live behavior** — does this depend on how an external service or site actually
   behaves? Verify against the real thing before claiming it's handled, not just docs or
   memory (point 5).
6. **Signal strength** — is this re-deriving a fact (a format, a type) from a weak signal
   (a filename extension, a guess) when a stronger one (an already-resolved value passed
   in as an argument, a prior computation) is sitting unused in scope? Use the strong
   signal first, and only fall back to the weak one when the strong one is unavailable
   (point 6).
7. **Pipeline scope** — does this add a branch/case to an existing polymorphic pipeline
   (an `ItemFactory`, a dispatcher, anything that already accepts more than one input
   shape)? Confirm it covers every shape the pipeline itself already supports, not just
   the one you happened to test with (point 7).
8. **Dead/speculative code** — does any logic handle an input shape nothing currently
   passes to it? Remove it; add it back only once a real caller needs it (point 8).
9. **Uniform fallbacks** — if a fallback/defensive path is applied identically across
   every branch of an input, check whether every branch actually needs it — a branch
   with an already-fully-reliable primary signal doesn't need the same fallback as one
   that doesn't (point 9).
10. **Type-fitting** — does this wrap or reshape a value (e.g. a `Blob` into a `File`)
    to satisfy a parameter type before checking whether the actual function called
    needs the narrower type at all? Check the real signature first. Does it also
    manufacture a piece of metadata (a filename, an id) that nothing downstream reads?
    Drop it (point 10).
11. **Trace it upstream** — before writing your own fallback/derivation for a value, check
    what actually produced the argument you already have. If it already incorporates the
    fallback you're about to re-add, yours is dead weight even though it looks defensive
    (point 11).
12. **Can't test it live? Say so — but check for an adjacent system you actually can
    test first.** If a reviewer's ask (or your own diff) depends on platform/environment
    behavior you can't run, look for a real, cheaply-accessible system that shares the
    underlying mechanism (a Docker image of a different OS, an installable package that
    embeds the platform database) before falling back to documentation research; whichever
    you end up doing, state plainly what was actually tested versus researched, including
    what you couldn't rule out (point 12).
13. **"Non-empty" isn't "meaningful."** When trusting an already-resolved value over
    re-deriving it (point 6/11), check whether that value has known "I don't know"
    sentinels (`application/octet-stream`, and similar generic fallbacks elsewhere) that
    are truthy but carry no real information — treat those the same as missing, while
    still trusting every other concrete value (point 13).
14. **New single-purpose helper** — before giving a new function its own file, check
    whether an existing file already holds siblings doing the same kind of work and put
    it there instead (point 14).
15. **Is there a stronger signal available than the ones you're choosing between?**
    Before picking a "least-bad" option among weak/derived signals (an extension, a
    possibly-empty MIME type), check whether the file's actual content is available and
    an already-installed dependency can read it (point 15).
16. **Inferred return types** — does a function have an explicit return type annotation
    TypeScript would infer anyway? Check whether sibling functions in the same file
    annotate theirs; if not, drop it (point 16).
17. **Reviewer-requested TODO** — if a reviewer explicitly asks for a TODO marking
    deferred cleanup (not an immediate fix), add it with close to their own wording;
    don't treat this as license to add other self-initiated TODOs (point 17).
18. **Partial workaround vs. known limitation** — does a fix add a whole extra code path
    to cover only part of a rare upstream bug's surface, while the bug still exists
    elsewhere? Consider documenting it as a known limitation instead of shipping the
    extra path (point 18).
19. **Dependency claims** — before adding a workaround for "this package doesn't declare
    dependency X," open its actual `package.json` in `node_modules` and check. Don't
    trust an earlier read, a summary, or memory of it (point 19).
20. **Ternary sprawl** — does a component have more than one ternary/conditional
    branching on the same discriminant field, scattered across several concerns? Collapse
    them into one function returning a per-branch config object instead (point 20).
21. **Proxy-first instinct** — about to add a server-side proxy or cache to protect
    against a third-party rate limit? Check real CORS support first, and check whether
    the actual trigger is something narrower (a list's own background-reload default)
    that's fixable without server-side infrastructure at all (point 21).
22. **Nested union vs. direct members, and a name that's outgrown its scope** — does a
    discriminated union nest a second dimension (a platform, a variant) inside one
    shared member instead of giving each case its own top-level member? And does the
    type/mechanism's name (or any identifier carrying it) still describe what it now
    does, now that a second case exists? (point 22)

Skipping this pass doesn't mean the code is wrong — it means finding out costs a full
review round-trip (wait for the review, interpret it, fix it, reply, resolve) instead of
minutes of self-review. Every point above earned its place in this list by actually
costing a round-trip once already.

**How this checklist has actually fared so far**: points 9-13 were all found on a
*previous* round's fix, made before those points existed — so none of PR #109's rounds
2-3-plus (including point 13's finding, which came through a direct message from the
same reviewer rather than a fourth formal PR round) test the checklist; they're the
reason points 9-13 exist at all. Round 3's *fix* (`48cc3e4`) was the first change
actually run through this checklist (points 1-10, before 11-13 existed) before pushing —
it came back clean, with one disclosed gap (point 12-shaped, before it had a number: live
platform behavior that couldn't be tested, only researched) — a gap that then led
straight to point 13's finding, meaning the checklist's own "disclose what you couldn't
verify" habit is what surfaced the next real bug, not just a liability to manage. Whether
a future fix draws a comment the checklist *should* have caught (because the relevant
point already existed) or *couldn't* have caught (a genuinely new pattern) is the actual
signal to watch for going forward — the former means "run it more carefully next time,"
the latter means "add a new point," and both are useful, but only the former would mean
the checklist itself has a gap.

**A third data point, from a different PR (#112, Openverse + Wikimedia Commons import)**:
running the checklist against the full diff before opening the PR caught a real point-1
violation self-review, with no reviewer involved at all — `createOpenverseMediaItems`
and `createWikimediaMediaItems` were ~90% identical, differing only in whether
`mediaType` was a fixed value or a per-item field, and got merged into one
`createExternalMediaItems` before the PR was ever opened. This is the checklist doing
exactly the job it was built for: catching a point-1-shaped issue pre-review instead of
paying for it as a round-trip, on a PR where — unlike #109 — the checklist was run
proactively from the start rather than reconstructed after the fact.

**A growing list is itself worth watching**: this checklist is now 22 items, entirely
because it only ever grows when a real round of feedback justifies a new line. That's
correct for keeping it evidence-based, but a 22-item self-review pass risks becoming too
long to actually run carefully every time — the opposite of the speed this was meant to
buy. Point 15 is itself a sharp example of why consolidation matters here: it directly
supersedes the entire 6/9/11/13 chain (a stronger signal — actual file content — was
available the whole time and nobody checked). If it keeps growing, worth revisiting
whether 6/9/11/13/15 can merge into one "trust the strongest signal, and periodically
re-ask whether an even stronger one exists" point, rather than only ever appending.

## The real review-comment workflow

PR review comments on GitHub don't get "fixed" by just pushing a commit — reply to each
inline comment explaining what changed (or why not), and mark the thread resolved once
it's genuinely addressed. See `references/gh-review-commands.md` for the exact commands —
worth using directly rather than re-deriving the GraphQL mutation shape each time; the
REST API can reply to a comment but resolving a thread is GraphQL-only.

**A top-level review can have an empty `body` and still carry all the real feedback —
regardless of its `state`.** PR #109's round-1 review showed up via
`gh pr view --json reviews` as `state=COMMENTED` with `body: ""` — reading only that
field looks like "reviewed, no comments." The actual feedback was two inline (line-level)
comments, only visible via `gh api repos/<owner>/<repo>/pulls/<number>/comments`. Round 3
repeated this with a `state=APPROVED` review — an *approval* that still carried one
substantive inline comment, with the same empty top-level body. Treat any empty-body
review — approving or not — as a prompt to go check inline comments, not as a sign
there's nothing to address.

**A thread you already replied to can get a further reply that overrules your fix —
re-fetch every thread's comments before assuming "awaiting response" still holds.** PR
#123: after replying to two threads with an explanation of my approach (the lodash alias,
the CloverImage workaround), the reviewer had in fact already replied again to both,
rejecting the approach outright (see points 18-19 above) — discovered only by re-listing
`gh api repos/<owner>/<repo>/pulls/<number>/comments` and noticing `in_reply_to_id`
pointing at comments I thought were still open-ended. Don't rely on a mental model of
"which threads are settled" built at the time you last replied — a long-running PR
session should re-check the full comment list (sorted by `in_reply_to_id`) before treating
any thread as merely pending.

## Writing style for comments and review replies

**This is a standing project preference, not observed reviewer feedback** — unlike every
numbered point above, no reviewer on this repo has asked for this; keep the two kinds of
guidance distinct rather than implying the real gatekeeper demanded a writing standard.

Whenever a comment survives the "core logic or complex math only" bar (point 4), and
whenever writing PR review-reply text (the `gh api .../replies` messages this skill's
workflow section covers), write it in ASD-STE100 (Simplified Technical English) style —
see the `asd-ste100` skill for the actual rule set. In short: short sentences, active
voice, one idea per sentence, no hedge-stacking, no nominalization. This doesn't relax
point 4's bar for *whether* to comment at all — it constrains the *form* of whatever
text actually gets written, code comment or review reply alike.

## Guardrails

1. **Points 1-13 and 18-22 are observed behavior from one specific reviewer
   (`zmarinov-astea`), verified across four unrelated PRs/features; points 14-17 are a
   second reviewer (`Sachanski`), so far only one round each on two PRs** — real and
   worth taking seriously, but don't present either as if every asteasolutions reviewer
   will behave identically, and don't overstate Sachanski's points as being as thoroughly
   verified as zmarinov-astea's just because they're in the same numbered list. If a
   future PR's reviewer gives different guidance, that's the more current signal for that
   PR.
2. **Don't add a speculative "why" comment expecting it to survive review here** — see
   point 4 above. This cuts against generic advice (including this skill set's own default
   elsewhere) to explain non-obvious constraints; this repo's bar is specifically narrower.
   The one exception is a TODO a reviewer explicitly asks for (point 17) — that's a
   reviewer-requested marker, not a self-initiated explanatory comment, so it doesn't
   loosen this guardrail for anything you add on your own.
3. **When two pieces of code differ only in a value passed through the same shape**,
   default to merging and parameterizing rather than duplicating, even as a first draft —
   don't treat "clean up the duplication later if asked" as an acceptable intermediate
   state for this repo.
4. **Resolving a thread requires GraphQL** — `gh pr view --comments` and the REST
   `pulls/comments` endpoints can read and reply, but `isResolved` only appears in
   `reviewThreads` via GraphQL, and only `resolveReviewThread` can flip it.
5. **When adding a branch/case to an existing polymorphic pipeline** (an `ItemFactory`, a
   dispatcher, anything that already accepts more than one input shape), check what the
   *pipeline* already supports before assuming your new branch's scope — don't let it
   silently cover fewer cases than the thing it's plugged into.
6. **Don't add defensive/general-purpose handling for an input shape nothing currently
   passes in** — see point 8 above. Write the helper for what actually calls it today;
   widen it when a real caller needs the wider case, not preemptively.
7. See `tapestry-collection-imports` for the concrete PRs (#96, #112), and
   `tapestry-content-types` for PRs (#109, #123), that all of the above was verified
   against, including the actual code before/after each round of feedback.
8. **Comment and reply text follows ASD-STE100 style (see `asd-ste100`) — but this is a
   standing project preference, not something any reviewer here asked for.** Don't cite it
   as reviewer feedback in a PR reply or elsewhere in this skill's "verified" framing.

## Bundled references

| File | Purpose |
|---|---|
| `references/gh-review-commands.md` | The exact `gh api`/GraphQL commands to list a PR's reviews and inline comments, reply to a specific comment, and resolve a review thread. |
