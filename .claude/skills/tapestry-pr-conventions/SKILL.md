---
name: tapestry-pr-conventions
description: Code-review conventions actually observed from a real asteasolutions/tapestry-project maintainer across two real review rounds on one real PR (#96, IA search-query import) — comment discipline, merge-don't-duplicate, composition over internal dependency — plus the concrete gh/GraphQL commands for replying to and resolving PR review comments. Not invented best practices; specific, verified feedback from the actual gatekeeper who reviews PRs to this repo
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["PR review", "code review conventions", "pull request feedback", "tapestry-project PR"]
  - keywords: ["resolve review thread", "reply to PR comment", "gh api pulls comments", "GraphQL resolveReviewThread"]
  - keywords: ["comment discipline", "merge duplicate components", "composition over internal dependency"]
last_verified: 2026-08-21
---

What a real reviewer at `asteasolutions/tapestry-project` actually asked for, across two
real review rounds on one real, currently-open PR
([#96](https://github.com/asteasolutions/tapestry-project/pull/96), the IA search-query
bulk-import feature — see `tapestry-collection-imports`, which this skill's findings were
first folded into before being generalized out here). **This is a sample of one reviewer
on one PR, not a universal law** — but every piece of feedback below was phrased as a
general principle, not an IA-specific nitpick, so treat it as a real, verified signal
about what this repo's actual gatekeeper cares about, worth applying proactively on any
future PR to this project rather than waiting to be told again.

## When to use this skill

- Before opening or updating a PR against `asteasolutions/tapestry-project`
- "Why did the reviewer ask for X" / anticipating what a reviewer here will flag
- Replying to or resolving PR review comments via `gh`
- Any skill in this repo whose checklist ends in "open a PR" should point here

## What this reviewer actually asked for, verified across two rounds

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

## The real review-comment workflow

PR review comments on GitHub don't get "fixed" by just pushing a commit — reply to each
inline comment explaining what changed (or why not), and mark the thread resolved once
it's genuinely addressed. See `references/gh-review-commands.md` for the exact commands —
worth using directly rather than re-deriving the GraphQL mutation shape each time; the
REST API can reply to a comment but resolving a thread is GraphQL-only.

## Guardrails

1. **This is observed behavior from one specific reviewer on one specific PR** — real and
   worth taking seriously, but don't present it as if every asteasolutions reviewer or
   every PR will behave identically. If a future PR's reviewer gives different guidance,
   that's the more current signal for that PR.
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
5. See `tapestry-collection-imports` for the concrete PR (#96) all of the above was
   verified against, including the actual code before/after each round of feedback.

## Bundled references

| File | Purpose |
|---|---|
| `references/gh-review-commands.md` | The exact `gh api`/GraphQL commands to list a PR's reviews and inline comments, reply to a specific comment, and resolve a review thread. |
