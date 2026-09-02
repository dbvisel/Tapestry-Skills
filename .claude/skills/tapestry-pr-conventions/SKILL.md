---
name: tapestry-pr-conventions
description: Code-review conventions actually observed from a real asteasolutions/tapestry-project maintainer across two real PRs (#96, IA search-query import; #109, client-side HEIC import) and five review rounds — comment discipline, merge-don't-duplicate, composition over internal dependency, trust the strongest already-available signal, match the full input space of the pipeline you're plugging into, don't fallback where the primary signal is already reliable, fit the actual API surface instead of an assumed one — plus a pre-submission self-review checklist to catch these before the reviewer does, and the concrete gh/GraphQL commands (including a real empty-review-body gotcha) for replying to and resolving PR review comments. Not invented best practices; specific, verified feedback from the actual gatekeeper who reviews PRs to this repo
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["PR review", "code review conventions", "pull request feedback", "tapestry-project PR"]
  - keywords: ["resolve review thread", "reply to PR comment", "gh api pulls comments", "GraphQL resolveReviewThread"]
  - keywords: ["comment discipline", "merge duplicate components", "composition over internal dependency"]
  - keywords: ["authoritative signal over derived guess", "mediaType vs file extension", "narrowing an existing pipeline's input space", "speculative dead code", "unused generality"]
  - keywords: ["pre-submission checklist", "self-review before PR", "empty review body", "gh pr view comments empty", "catch review feedback before opening a PR"]
  - keywords: ["Blob vs File", "unnecessary type wrapping", "fallback only where needed", "check library API signature", "manufactured metadata unused filename"]
last_verified: 2026-09-02
---

What a real reviewer at `asteasolutions/tapestry-project` actually asked for, across five
real review rounds on two real PRs: [#96](https://github.com/asteasolutions/tapestry-project/pull/96)
(the IA search-query bulk-import feature — see `tapestry-collection-imports`, which this
skill's findings were first folded into before being generalized out here) and
[#109](https://github.com/asteasolutions/tapestry-project/pull/109) (client-side HEIC
import — see `tapestry-content-types`' variation section). **Same reviewer on both PRs**,
which is itself real signal: feedback that recurs in the same shape across two unrelated
features is a stable preference of this specific gatekeeper, not a one-PR quirk. Every
piece of feedback below was phrased as a general principle, not a feature-specific nitpick,
so treat it as worth applying proactively on any future PR to this project rather than
waiting to be told again. Whoever is about to open or update a PR here — this skill is
meant to be run as a self-review pass on your own diff (see "Pre-submission checklist"
below), not just consulted after a reviewer has already commented.

## When to use this skill

- Before opening or updating a PR against `asteasolutions/tapestry-project` — run the
  pre-submission checklist below against your diff first
- "Why did the reviewer ask for X" / anticipating what a reviewer here will flag
- Replying to or resolving PR review comments via `gh`
- Any skill in this repo whose checklist ends in "open a PR" should point here

## What this reviewer actually asked for, verified across five rounds on two PRs

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

Skipping this pass doesn't mean the code is wrong — it means finding out costs a full
review round-trip (wait for the review, interpret it, fix it, reply, resolve) instead of
minutes of self-review. Every point above earned its place in this list by actually
costing a round-trip once already.

**First real test of this checklist, and what it showed**: points 9 and 10 above were
themselves found in a round-2 review of the round-1 *fix* for points 6/7 — a fix made
before this checklist existed. So this round wasn't run through the checklist before
being pushed, and can't be claimed as either a confirmation or a failure of it yet; it's
the reason points 9-10 exist at all. The real test is the next PR round pushed *after*
a checklist pass — worth explicitly noting in that PR's own history whether the checklist
caught something before review, or the reviewer still found something the checklist
missed (in which case, add it here too).

## The real review-comment workflow

PR review comments on GitHub don't get "fixed" by just pushing a commit — reply to each
inline comment explaining what changed (or why not), and mark the thread resolved once
it's genuinely addressed. See `references/gh-review-commands.md` for the exact commands —
worth using directly rather than re-deriving the GraphQL mutation shape each time; the
REST API can reply to a comment but resolving a thread is GraphQL-only.

**A top-level review can have an empty `body` and still carry all the real feedback.**
PR #109's round-1 review showed up via `gh pr view --json reviews` as
`state=COMMENTED` with `body: ""` — reading only that field looks like "reviewed, no
comments." The actual feedback was two inline (line-level) comments, only visible via
`gh api repos/<owner>/<repo>/pulls/<number>/comments`. Treat a commented-but-empty-body
review as a prompt to go check inline comments, not as a sign there's nothing to
address.

## Guardrails

1. **This is observed behavior from one specific reviewer, now verified across two
   unrelated PRs/features** — real and worth taking seriously, but still don't present it
   as if every asteasolutions reviewer will behave identically; it's this reviewer's
   pattern, not necessarily every gatekeeper's. If a future PR's reviewer gives different
   guidance, that's the more current signal for that PR.
2. **Don't add a speculative "why" comment expecting it to survive review here** — see
   point 4 above. This cuts against generic advice (including this skill set's own default
   elsewhere) to explain non-obvious constraints; this repo's bar is specifically narrower.
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
7. See `tapestry-collection-imports` for the concrete PR (#96), and `tapestry-content-types`
   for PR (#109), that all of the above was verified against, including the actual code
   before/after each round of feedback.

## Bundled references

| File | Purpose |
|---|---|
| `references/gh-review-commands.md` | The exact `gh api`/GraphQL commands to list a PR's reviews and inline comments, reply to a specific comment, and resolve a review thread. |
