---
name: tapestry-wikimedia-reference
description: Pointer/index to external reference material for working with Wikimedia Commons and the MediaWiki Action API from Tapestry code — an external skills repo (fuzheado/Wikipedia-AI-Skills) worth checking before reinventing an API pattern, plus real facts about the Commons API (imageinfo, categorymembers, categoryinfo, mediatype values, CORS, and unauthenticated rate-limiting) verified live against the actual API rather than taken on faith from that repo
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["Wikimedia Commons API", "MediaWiki Action API", "Wikipedia-AI-Skills", "fuzheado"]
  - keywords: ["commons.wikimedia.org api.php", "imageinfo", "categorymembers", "categoryinfo", "gcmcontinue"]
  - keywords: ["Commons CORS", "upload.wikimedia.org CORS", "Wikimedia rate limit", "User-Agent required Wikimedia"]
  - keywords: ["Commons mediatype", "BITMAP DRAWING AUDIO VIDEO OFFICE 3D"]
last_verified: 2026-09-03
---

An index of where to look for Wikimedia/Wikipedia integration knowledge, not a
how-to itself. Use this before reaching for `tapestry-external-media-sources` or
`tapestry-collection-imports` on a Wikimedia-related task, and before re-deriving an
API pattern from scratch.

## When to use this skill

- Starting any task that touches `commons.wikimedia.org`, `wikipedia.org`, or the
  MediaWiki Action API from Tapestry code
- Deciding whether a third-party claim about the Wikimedia API is safe to trust
  as-is, or needs a live spot-check first

## External reference repo: fuzheado/Wikipedia-AI-Skills

[fuzheado/Wikipedia-AI-Skills](https://github.com/fuzheado/Wikipedia-AI-Skills) is a
much larger, more mature skills repo specifically for Wikimedia/Wikipedia work — not
Tapestry-specific, and not vetted by us beyond the spot-checks below. Check it before
assuming a Wikimedia API pattern needs figuring out from scratch; Tapestry will likely
never need most of it (it also covers editing, uploading, Wikidata — well beyond
anything Tapestry does), but the read-only/resolution-focused skills are directly
relevant to import-style features:

| Their skill | What it covers |
|---|---|
| `wikimedia-commons` | Search, upload, metadata retrieval, category browsing via the Action API |
| `commons-file-resolution` | Resolving a Commons file reference to a browser-usable URL; CORS behavior; `Special:FilePath` |
| `wikimedia-commons-categories` | Creating/disambiguating categories from Wikidata (not relevant to read-only import) |
| `wikimedia-commons-thumbnails` | Constructing thumbnail URLs (`iiurlwidth`/`iiurlheight`) at any size |
| `wikimedia-api-access` | Required `User-Agent`, gateway rate-limit classes |
| `wikipedia-error-handling` | Retry strategy, `Retry-After`, pagination/continuation tokens |

**Treat their specific numbers and edge-case claims as leads to verify, not settled
fact** — this repo is optimized for a different scale/use case (bulk editing, bot-style
automation) and some of its claims may be generic best-practice advice rather than
something checked against the live API. The verified facts below are what we've
actually confirmed ourselves; where a third-party claim from that repo hasn't been
independently checked, it's marked as such.

## Verified facts (checked live against `commons.wikimedia.org`, 2026-09-03)

- **`action=query&prop=imageinfo&titles=File:...&iiprop=url|mime|mediatype&format=json&origin=*`**
  resolves a File: page to its direct file URL, MIME type, and MediaWiki's own
  `mediatype` classification. Real confirmed `mediatype` values: `BITMAP` (a `.JPG`),
  `OFFICE` (a `.pdf`, with `mime: application/pdf` — the same OFFICE/PDF ambiguity
  `tapestry-external-media-sources` already documents from the Commons reference
  implementation), `VIDEO` (a `.ogv`, `mime: application/ogg`), `AUDIO` (a `.ogg`,
  also `mime: application/ogg` — confirming the same MIME-is-ambiguous, mediatype-
  disambiguates pattern for audio vs. video that the existing skill only previously
  showed for video).
- **The Action API itself (`commons.wikimedia.org/w/api.php`) sends
  `access-control-allow-origin: *`** — confirmed via response headers. Client-side
  metadata resolution is viable from a CORS standpoint.
- **`upload.wikimedia.org` (the actual file host) is a separate origin from the API
  host, and a third-party claim (not independently verified by us) says it does *not*
  send permissive CORS headers**, meaning a `fetch()` read of file bytes cross-origin
  would fail even though `<img>`/`<video>`/`<audio src=...>` rendering (which doesn't
  require CORS) works fine. Doesn't block a by-reference import design (which never
  fetches the bytes client-side), but would matter for any future real-copy mode
  unless resolved server-side.
- **Category listing has no single all-in-one endpoint the way Openverse's search
  does** — two separate calls: `action=query&generator=categorymembers&gcmtitle=...
  &gcmlimit=&gcmtype=file&prop=imageinfo&iiprop=...` for the actual file list (confirmed
  live, batches of files with full imageinfo in one round trip), and a separate
  `action=query&titles=Category:...&prop=categoryinfo&format=json` for the cheap total
  count (confirmed live: real `categoryinfo.files` count for a real category).
- **Category pagination is opaque-cursor-based (`gcmcontinue`), not page-number-based**
  — confirmed live across two consecutive calls (each response's `continue.gcmcontinue`
  is required to fetch the next batch; there's no way to jump directly to an arbitrary
  page the way Openverse's `page=N` allows). Any UI built against this needs either
  sequential-only fetching or a server-side cache that remembers each page's cursor as
  it's discovered — matters directly for how a category-picker list component can be
  built, unlike Openverse's numeric pagination.
- **Unauthenticated requests are genuinely rate-limited at bursts, confirmed live**: 20
  concurrent unauthenticated requests to the Action API returned a mix of `429` and
  `200` (9 of 20 came back `429`) — not a clean sequential cutoff, more like a
  token-bucket limiter. This is the same shape of problem as Openverse's Cloudflare
  bot-mitigation (see `tapestry-collection-imports`/this session's Openverse work): a
  scrolling category picker firing bursts of client-side requests will get throttled.
  **Route Commons requests through a server-side proxy with caching, the same pattern
  already used for Openverse**, not direct client-side `fetch()` calls, especially for
  any collection/category browsing. The third-party rate-limit table in
  `wikimedia-api-access` (10 req/min unidentified, 200 req/min with a compliant
  `User-Agent`, 2000 req/min authenticated) is plausible and directionally consistent
  with what we saw, but the exact numbers weren't independently confirmed — the actual
  live 429 rate is what matters for the "needs server-side proxying" conclusion, not
  the specific published thresholds.
- **A browser's `fetch()` can never set a custom `User-Agent` header** (it's a
  forbidden header name) — meaning even a well-intentioned custom UA string is not
  achievable from client-side JS, another reason server-side proxying (where a real
  `User-Agent` header naming Tapestry can actually be set) is the more robust design
  for this specific API, independent of the rate-limiting finding above.

## Guardrails

1. **Don't copy fuzheado/Wikipedia-AI-Skills content wholesale into a Tapestry skill.**
   It's reference material for figuring out the right approach, not something to vendor
   the way `asd-ste100` was — most of that repo (editing, uploading, Wikidata) is out of
   scope for anything Tapestry does.
2. **Re-verify a claim from that repo against the live API before depending on it** —
   see the "Verified facts" section above for the ones already checked; spot-check
   anything else the same way (a handful of real `curl` calls) rather than trusting the
   published claim at face value.
3. See `tapestry-external-media-sources` and `tapestry-collection-imports` for how
   these facts translate into an actual Tapestry import feature.
