---
name: tapestry-pr-conventions
description: Code-review conventions actually observed from a real asteasolutions/tapestry-project maintainer across two real PRs (#96, IA search-query import; #109, client-side HEIC import) and four review rounds — comment discipline, merge-don't-duplicate, composition over internal dependency, trust the strongest already-available signal, match the full input space of the pipeline you're plugging into — plus the concrete gh/GraphQL commands for replying to and resolving PR review comments. Not invented best practices; specific, verified feedback from the actual gatekeeper who reviews PRs to this repo
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["PR review", "code review conventions", "pull request feedback", "tapestry-project PR"]
  - keywords: ["resolve review thread", "reply to PR comment", "gh api pulls comments", "GraphQL resolveReviewThread"]
  - keywords: ["comment discipline", "merge duplicate components", "composition over internal dependency"]
  - keywords: ["authoritative signal over derived guess", "mediaType vs file extension", "narrowing an existing pipeline's input space", "speculative dead code", "unused generality"]
last_verified: 2026-09-02
---

What a real reviewer at `asteasolutions/tapestry-project` actually asked for, across four
real review rounds on two real PRs: [#96](https://github.com/asteasolutions/tapestry-project/pull/96)
(the IA search-query bulk-import feature — see `tapestry-collection-imports`, which this
skill's findings were first folded into before being generalized out here) and
[#109](https://github.com/asteasolutions/tapestry-project/pull/109) (client-side HEIC
import — see `tapestry-content-types`' variation section). **Same reviewer on both PRs**,
which is itself real signal: feedback that recurs in the same shape across two unrelated
features is a stable preference of this specific gatekeeper, not a one-PR quirk. Every
piece of feedback below was phrased as a general principle, not a feature-specific nitpick,
so treat it as worth applying proactively on any future PR to this project rather than
waiting to be told again.

## When to use this skill

- Before opening or updating a PR against `asteasolutions/tapestry-project`
- "Why did the reviewer ask for X" / anticipating what a reviewer here will flag
- Replying to or resolving PR review comments via `gh`
- Any skill in this repo whose checklist ends in "open a PR" should point here

## What this reviewer actually asked for, verified across four rounds on two PRs

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

## The real review-comment workflow

PR review comments on GitHub don't get "fixed" by just pushing a commit — reply to each
inline comment explaining what changed (or why not), and mark the thread resolved once
it's genuinely addressed. See `references/gh-review-commands.md` for the exact commands —
worth using directly rather than re-deriving the GraphQL mutation shape each time; the
REST API can reply to a comment but resolving a thread is GraphQL-only.

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
