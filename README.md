# Tapestry-Skills

Claude Code / Claude Agent skills for working on
[`internetarchive/tapestry-project`](https://github.com/internetarchive/tapestry-project)
("Tapestries") — a canvas/annotation web app with a `core` / `core-client` / `client` /
`server` / `shared` / `viewer` npm-workspaces monorepo.

Modeled on the structure of [Wikipedia-AI-Skills](https://github.com/fuzheado/Wikipedia-AI-Skills):
each skill is a `SKILL.md` under `.claude/skills/<name>/`, with `references/` for
longer supporting docs and `scripts/` for bundled scripts where useful. This first pass
intentionally skips the reference repo's CI verification workflows and test suite —
[`.claude/guidelines/script-audit-guidelines.md`](.claude/guidelines/script-audit-guidelines.md)
adapts just the substance of its script-audit guidelines to this repo's actual scale (a
handful of scripts, not dozens), without the CI/pre-commit-hook machinery that scale
doesn't yet justify.

## Skills

Grouped below by what they're *for*, not by any physical folder structure —
every skill still lives as a direct child of `.claude/skills/` (flat), which
both `tools/verify-skills.py` and skill discovery itself expect. These
groupings are just how this README presents them; nothing here reflects a
directory layout.

### Admin & maintenance (operating an already-running installation)

| Skill | Covers |
|---|---|
| [`tapestry-visibility`](.claude/skills/tapestry-visibility/SKILL.md) | Managing a tapestry's visibility (private/link/public) on a running installation via the bundled `manage-tapestry-visibility.sh` script, including how "public" surfaces it in every client's "Samples" list |
| [`tapestry-backups`](.claude/skills/tapestry-backups/SKILL.md) | Backing up a Tapestry installation's Postgres database and MinIO object storage via the bundled `backup-tapestry.sh` script (interactive or scheduled), plus how to restore |
| [`tapestry-thumbnail`](.claude/skills/tapestry-thumbnail/SKILL.md) | Remaking a tapestry's own single card thumbnail (`Tapestry.thumbnail` — the dashboard/Samples preview) via the bundled `manage-tapestry-thumbnail.sh` script. Not per-frame thumbnails — see the next entry for that |
| [`tapestry-frame-thumbnails`](.claude/skills/tapestry-frame-thumbnails/SKILL.md) | Inspecting and backfilling missing per-frame thumbnails (the small preview image on each canvas item) via the bundled `manage-tapestry-frame-thumbnails.sh` script — the fix for tapestries imported before a given install picked up the "generate thumbnails on import" server fix |

These four share a convention: each bundled `manage-*.sh`/`backup-tapestry.sh`
script resolves the actual repo/compose-file location via a `REPO_DIR`
environment variable (default: the current directory), so the script file
itself can live anywhere — e.g. a dedicated admin `scripts/` directory,
separate from the `tapestry-project` checkout it operates on.

### Local development (building/running the app itself)

| Skill | Covers |
|---|---|
| [`tapestry-local-dev-environment`](.claude/skills/tapestry-local-dev-environment/SKILL.md) | Running the app locally the way upstream documents it (npm workspaces, per-workspace `.env` files, LocalStack/Redis/Vault via `docker-compose.local.yml`, Vite dev server) — plus a clearly-separated note on a Docker+MinIO installer variation that exists only on some forks, and the CSP issue that only shows up there |
| [`tapestry-client-features`](.claude/skills/tapestry-client-features/SKILL.md) | Adding UI functionality in `client`/`core-client` — canvas item types, the controller/manager pattern, auth providers, live updates, build-time config |
| [`tapestry-server-worker`](.claude/skills/tapestry-server-worker/SKILL.md) | Adding backend functionality — REST resources, Prisma models/migrations, BullMQ jobs, S3/MinIO presigning, Vault-backed secrets, Socket.io fan-out |
| [`tapestry-auth-providers`](.claude/skills/tapestry-auth-providers/SKILL.md) | Adding a new external login provider — full client+server+schema+deployment checklist, generalized from two real (unmerged) reference implementations: ORCID and MediaWiki OAuth |
| [`tapestry-content-types`](.claude/skills/tapestry-content-types/SKILL.md) | Adding a new canvas content/item type while changing as little as possible — full checklist including the easy-to-miss export-version bump, generalized from two real (unmerged) reference implementations: IIIF deep-zoom images and STL 3D models — plus a variation for an *existing* type accepting a format that needs conversion before it's renderable, with client-side vs. server-side tradeoffs verified against two real, competing PRs (HEIC image import) |
| [`tapestry-webpage-types`](.claude/skills/tapestry-webpage-types/SKILL.md) | Adding a new *known webpage type* (recognizing a specific site's URLs) without adding a whole new item type — two strategies, embed-and-iframe or fetch-and-render-as-DOM, generalized from four real (unmerged) reference implementations: SoundCloud, Spotify, Sketchfab, and Wikipedia |
| [`tapestry-external-media-sources`](.claude/skills/tapestry-external-media-sources/SKILL.md) | Letting users paste a URL that *describes* a single file on an external platform (e.g. a Wikimedia Commons `File:` page) and importing the real file as a plain, ordinary item of an existing type — no schema changes at all, the lightest of the "URL connection" patterns. Generalized from two real (unmerged) reference implementations: Wikimedia Commons and Openverse single-file import |
| [`tapestry-collection-imports`](.claude/skills/tapestry-collection-imports/SKILL.md) | Extending Tapestries' existing bulk-import picker (real upstream functionality) with a new collection type — a Wikimedia Commons category, an Openverse tag search, an Internet Archive search query — generalized from reference implementations plus one real, currently-in-review implementation against actual upstream (IA search, [PR #96](https://github.com/asteasolutions/tapestry-project/pull/96)) |
| [`tapestry-viewer-embedding`](.claude/skills/tapestry-viewer-embedding/SKILL.md) | Packaging the real, existing standalone `/viewer` app for a host that isn't a website — build with `--base=./`, serve over a real http(s) origin (never `file://`), point it at `?source=<url>` unmodified — generalized from two real (unmerged) reference integrations: a WordPress block and a macOS drag-and-drop opener |
| [`tapestry-standalone-viewer`](.claude/skills/tapestry-standalone-viewer/SKILL.md) | A specialization of `tapestry-viewer-embedding` for the "one app, one fixed tapestry" case: a bundled script packages the standalone `/viewer` build together with one specific `.zip` into a self-contained static folder — no CORS setup, since the zip ships same-origin with the viewer, and (optionally, with a documented trade-off) no visible `?source=` param either |
| [`tapestry-pr-conventions`](.claude/skills/tapestry-pr-conventions/SKILL.md) | Code-review conventions actually observed from a real maintainer, now verified across five review rounds on two real PRs (#96, #109) — comment discipline, merge-don't-duplicate, composition over internal dependency, trust the strongest already-available signal, match the full input space of the pipeline you're plugging into, don't fall back where the primary signal is already reliable, fit the actual API surface instead of an assumed one — plus a pre-submission self-review checklist and the exact `gh`/GraphQL commands (with a real empty-review-body gotcha) for replying to and resolving PR review comments |

### Standalone `.zip` tooling (no `tapestry-project` checkout needed at all)

| Skill | Covers |
|---|---|
| [`tapestry-zip-authoring`](.claude/skills/tapestry-zip-authoring/SKILL.md) | Constructing a valid tapestry export/import `.zip` from scratch — the full `root.json` schema and file-naming convention, plus a bundled, dependency-free builder script. **Does not require a `tapestry-project` checkout** — verified directly against the real app's schema/import behavior rather than derived from reading its source |
| [`tapestry-zip-analysis`](.claude/skills/tapestry-zip-analysis/SKILL.md) | Analyzing an existing tapestry `.zip` — version, item inventory, groups/rels/presentation structure, and whether it's actually importable — via a bundled, dependency-free analyzer script. **Does not require a `tapestry-project` checkout**; depends on `tapestry-zip-authoring` for the schema reference, not on the app's source |

## Using these skills

Every skill except `tapestry-zip-authoring`/`tapestry-zip-analysis` is about working on
`tapestry-project` itself, so copy `.claude/skills/` into a checkout of that repo (or
symlink it), or point your agent's skill-search path at this repo. Each `SKILL.md`
cross-references its siblings (e.g. the client and server skills each note where the
auth-provider or live-update story continues on the other side).

`tapestry-zip-authoring` and `tapestry-zip-analysis` are the exception: they document
the tapestry export/import `.zip` format itself (verified against the real app, not
just read from it) and ship bundled, dependency-free scripts to build/analyze one —
usable anywhere, with no `tapestry-project` checkout, running server, or repo access of
any kind required.

## Maintaining this repo

`tools/verify-skills.py` (repo-root tooling, distinct from any skill's own
`scripts/`) is a structural self-check — every `SKILL.md` has complete, well-formed
frontmatter, `last_verified` isn't stale, `depends_on` targets exist, bundled files are
documented and documented paths exist. Run it before committing a change to
`.claude/skills/`:

```bash
python3 tools/verify-skills.py
```

See `CLAUDE.md` for the fuller set of conventions this repo follows, and the maturity
model for what (if anything) to add beyond this as the repo grows.

## Status

Built from a hands-on local-dev session plus codebase research — not yet verified
against a from-scratch read by anyone but the agent that wrote it. Treat facts in here
as accurate as of the `last_verified` date in each `SKILL.md`'s frontmatter, and expect
some upstream drift over time (e.g. new Prisma migrations, new item types).

**`internetarchive/tapestry-project` `main` is treated as the definitive upstream
throughout.** A personal fork (e.g. `dbvisel/tapestry-project`) carries several
real but non-default variations across different branches — a Docker+MinIO local-dev
installer (`dbvisel/main`), archive.org-specific production customizations including a
hardcoded CSP (`archive-version`/`archive-version-updated`), and experimental auth
providers on other branches that were never merged anywhere. Corrections folded in
during review, in case future editors hit the same trap:

- The Docker+MinIO installer (`docker-compose.minio.yml`, `Dockerfile.client-minio`,
  `setup.sh`, `.env.sample`) is real and has git history, but only on a specific fork
  branch (`dbvisel/main`) — not on upstream `main`, and not on the archive.org
  customization branches either. Upstream's actual local-dev story is npm scripts +
  LocalStack + per-workspace `server/.env`/`client/.env`, documented in upstream's own
  README.
- The CSP problem is even narrower than "this fork's installer" — it only exists on
  the archive.org customization branches, which is a separate axis of variation from
  the MinIO installer. Most people running any form of local dev, including
  `dbvisel/main`, never see a CSP `<meta>` tag at all.
- Those "experimental auth providers on other branches" are exactly what
  `tapestry-auth-providers` is built from (`orcid-login`, `mediawiki-login` — each a
  single clean commit on top of `dbvisel/main`). They're real, complete reference
  implementations of the pattern, but not implemented on any default branch — the skill
  is explicit that ORCID/MediaWiki login don't exist today, only the pattern for adding
  something like them does.
- Same story for `tapestry-content-types`, built from `iiif-upstream` (a single clean
  commit, but this one directly on top of upstream `internetarchive/main` rather than
  `dbvisel/main`) plus, later, the `model3d` item type found in a separate, giant,
  deliberately-messy commit that bundles in a lot of unrelated work — not present on any
  long-lived branch; only the lines actually touching `model3d` were used. Neither IIIF nor
  `model3d` support exists on any default branch — again, patterns to follow, not features
  to claim exist. The second example was folded in specifically because it revealed real
  gaps the first alone had left the skill overstating (e.g. that a bespoke item factory is
  always necessary — `model3d` shows the far more common case of reusing the existing
  generic file-matching factory instead).
- `tapestry-webpage-types` is built from small commits found in unmerged exploratory work
  (dirty, not up to date), covering SoundCloud, Spotify, and — folded in later — Sketchfab,
  plus a `wikipedia` webpage type found in a different, separately-messy commit. Sketchfab
  confirmed the same embed-and-iframe strategy as SoundCloud/Spotify (it just blocks framing
  via `X-Frame-Options` rather than CSP, and needed a trickier id-extraction technique from
  a hyphenated slug) — worth noting since Sketchfab hosts 3D models but has nothing to do
  with `tapestry-content-types`' `model3d` item type; it embeds Sketchfab's own hosted
  viewer, not Tapestries' native one. Wikipedia, by contrast, is a genuinely different
  strategy: instead of iframing a rewritten embed URL, it fetches the article via the
  Wikipedia REST API and renders sanitized DOM directly in a fully custom component —
  revealing a whole dispatch mechanism (a per-`webpageType` component override, optional and
  client-only) the skill didn't cover until this was folded in. None of the four exists on
  any default branch.
- `tapestry-external-media-sources` and `tapestry-collection-imports` are both built from
  the same giant, deliberately-messy unmerged commit as `model3d` and Wikipedia above —
  Wikimedia Commons and Openverse single-file import for the former (verified against real
  example URLs given in conversation, including a `.stl` 3D model that maps to `model3d` via
  the exact same mechanism with no special-casing, not invented), and Commons
  categories/Openverse tag collections/Internet Archive search for the latter, extending a
  picker mechanism that — unlike everything else on this list — actually *is* real, existing
  upstream functionality; only the three new collection types are unmerged. Single-file
  import is deliberately scoped to one item at a time; the bulk/collection picker mechanism
  it originally left out of scope is exactly what `tapestry-collection-imports` covers.
- `tapestry-viewer-embedding` is different from every skill above: `/viewer` itself is real,
  existing upstream code (deliberately minimal — no auth, no sockets, `core-client`-only,
  see `tapestry-client-features`), and neither reference integration touches its source at
  all. A WordPress block and a macOS drag-and-drop opener were found in the same unmerged
  exploratory work as several skills above, and — independently of each other — converge on
  the exact same packaging recipe (`vite build --base=./`, copy into the host's own resource
  folder, serve over a real http(s) origin since ES modules can't load under `file://`,
  point at the unmodified `?source=<url>` param). Neither integration exists on any default
  branch; the recipe they demonstrate is the durable artifact.
- `tapestry-standalone-viewer` keeps the built viewer's `index.html` untouched at the site
  root — the viewer's `<BrowserRouter>` only registers `<Route path="/">`, so anything that
  renames or redirects away from that path breaks with "No routes matched location." A small
  bootstrap script injected into `index.html` instead sets the loading state (either the app's
  own `?source=` URL param via `history.replaceState`, or — optionally, via
  `--no-query-string` — its IndexedDB "last import" fallback store) before the app mounts,
  verified against a real headless-Chrome run, not just `curl`/static-file checks. The skill's
  "Performance at scale" section is similarly measured, not assumed: a real 430 MB/236-item
  tapestry rendered in ~5s over loopback, showing the actual bottleneck for large tapestries is
  the viewer's lack of streaming/range-request support on download, not the zip format or
  client-side decompression.
- `tapestry-collection-imports`' IA-search example became a real PR
  ([#96](https://github.com/asteasolutions/tapestry-project/pull/96)) that then got real
  review — twice — and the review feedback changed the skill's own recommended architecture,
  not just its wording. Round 1 rejected the checklist's original "copy a sibling component,
  share styles if the fields match" advice on sight (a near-duplicate `search-list/` next to
  `collection-list/`) in favor of merging both into one parameterized component and one
  parameterized factory; round 2 caught a helper reaching into another helper to modify its
  own argument (should compose at the call site instead) and rejected two comments that would
  pass this skill set's own general "explain the non-obvious why" bar — this specific
  upstream's comment discipline turned out to be narrower ("core logic and complex math
  only"). Both rounds' feedback was generalized out into a new skill,
  `tapestry-pr-conventions`, rather than left buried in one skill's history — real, verified
  signal from the actual gatekeeper who reviews PRs here, not invented best practice.
- `tapestry-local-dev-environment`'s `AWS_INTERNAL_ENDPOINT_URL` previously described a
  mechanism that **did not actually exist**: the `.env.sample`/`docker-compose.minio.yml`
  this skill bundles set the variable, but nothing in `server/src/config.ts` or
  `s3-service.ts` ever read it — a documentation-only fix that was never wired up or
  verified against the real app. Discovered the hard way in a real session building a new
  feature (HEIC image import) that, for the first time, actually depended on the worker
  successfully self-fetching from S3 — every prior use of that code path (thumbnail
  generation) fails silently on this exact gap, so nobody had noticed. Corrected to the
  real, verified fix: `docker-compose.minio.yml`'s `worker` service overrides
  `AWS_ENDPOINT_URL`/adds `VIEWER_URL` via Compose-level fallback interpolation
  (`${AWS_INTERNAL_ENDPOINT_URL:-${AWS_ENDPOINT_URL}}`), not application code — confirmed
  with real `curl`/`wget` tests from inside the containers, both before (connection
  refused) and after (200 OK) the fix. Also ruled out, empirically, a tempting
  zero-config alternative (`extra_hosts: ["localhost:host-gateway"]`) that turns out not to
  work on this project's actual Alpine/musl-based images even though it works on a plain
  `alpine:latest` image — see the skill's new "Internal vs. browser-facing addresses"
  section. The broader lesson: a fix added only to bundled documentation/config files,
  never exercised against the real running app, isn't verified just because it looks
  reasonable — the same standard this repo already applies to bundled scripts ("run it for
  real before calling it done") applies to config templates too.
- `tapestry-content-types` gained a variation section from the same HEIC image-import
  session, but built from a genuinely different kind of case than IIIF/`model3d`: it adds
  **no new item type at all** — the existing `image` type accepts a format (HEIC) the
  browser can't render, and needs a background conversion step instead. Real, concrete
  bugs surfaced along the way were generalized directly into guardrails rather than left
  as one-off war stories: an item-size computation that assumed decode always succeeds (it
  doesn't, for a format the browser can't handle at all — not the same as `model3d`'s "no
  natural aspect ratio" case); a broken-image flash traced to *two* distinct "not ready
  yet" windows for any media item (a local optimistic `blob:` URL during upload, then a
  real-but-unconverted URL after), each needing a different signal to detect; and a
  format-detection helper that worked on a bare S3 key but silently broke against a
  presigned URL with a query string appended, because it split on the last `.` in the
  whole string. Considered splitting this into its own skill; decided against it for now
  (asked the user directly) since it's small, its main value is redirecting someone away
  from the full new-item-type checklist at the point they'd otherwise reach for it, and
  there's only one real example so far — matching this repo's own pattern of splitting
  only once something's proven to generalize across more than one real case (see
  `tapestry-pr-conventions` above).
- That same feature then got a **second, independent, real implementation** — a
  client-side conversion variant, opened as a second competing PR
  ([#109](https://github.com/asteasolutions/tapestry-project/pull/109), alongside the
  server-side [#108](https://github.com/asteasolutions/tapestry-project/pull/108)) — and
  the "only one real example so far" reasoning above for not splitting the variation
  section out no longer fully applies (there are now two), but the section stayed put
  since it's still small and still exists to redirect someone away from the big
  checklist, not to house a growing library of conversion patterns. Real findings from
  building the client-side variant, generalized into the skill: (1) a static top-level
  `import` of a heavy library, even inside its own module file, does not lazy-load it if
  that file is itself always loaded — confirmed by literally comparing real Vite build
  output before/after moving to a dynamic `import()` at the actual call site, watching
  the dependency move from the main chunk into its own; (2) `client/tsconfig.app.json`'s
  `moduleResolution: "Node"` can't resolve a package's subpath exports at all, discovered
  via a `TS2307` on an otherwise-real, otherwise-documented import path; (3) evaluating
  three real candidate HEIC-decoding libraries surfaced two independently-verifiable
  failure modes worth generalizing beyond HEIC specifically — `libheif-js` (typed only at
  the useless low-level C-binding layer, not the actually-documented high-level API) and
  `heic2any` (a real, still-open LGPL-attribution violation, not a hypothetical one) —
  before landing on a better-fitting third option (`heic-to`); (4) a real, avoidable
  network round-trip in the first draft of the client-side conversion code itself
  (re-fetching bytes from storage that were already sitting in memory from the original
  drop), caught by the user noticing the feature felt slightly slower and asking about
  it, not by anything automated. That last one is a good example of a "learned during
  code review, not during initial implementation" finding making it into a skill.
- PR #109 then went through one more real rework, prompted by the user noticing the
  item still appeared at a guessed placeholder size before conversion finished ("we
  don't know what aspect ratio the HEIC has, and the defaults are giving the user the
  wrong idea"). The fix wasn't a better placeholder — it was realizing the placeholder
  didn't need to exist at all: conversion moved into a dedicated `ItemFactory` that runs
  *before* `createMediaItem`, so the item is only ever created once its real size is
  known. That deleted the placeholder component, the post-creation
  `resource('items').update(...)` patch call, and all manual `pendingRequests` wiring in
  one pass — the existing `insertDataTransfer` wrapper already puts every drop/paste
  through a `pendingRequests` increment for the whole factory pipeline, so the standard
  hourglass covers the wait for free. `tapestry-content-types`' variation section was
  rewritten to lead with this as the preferred pattern (a bespoke async-resolution
  `ItemFactory`, per the main checklist's step 16, applied to conversion) and to scope
  the original placeholder-and-patch pattern to where it's actually still necessary — a
  server-side job (PR #108), which has no choice but to create the item before the job
  can attach to it. At the time, gating the new factory on `source instanceof File` also
  looked like a nice side effect: only ever seeing a locally-dropped file meant it never
  had a URL to evaluate, incidentally sidestepping the "can a client-side conversion tell
  internal from external sources" problem from the first rework. **That didn't survive
  actual review** — see the next bullet.
- The real reviewer's first pass on PR #109 (round 1, same reviewer as #96 — see
  `tapestry-pr-conventions`) caught two things the self-review above missed: (1) HEIC
  detection was extension-only, ignoring the `mediaType` the surrounding pipeline had
  already resolved and was passing in as an argument; (2) the factory's File-only gating
  wasn't actually a clever design choice, it was an unrequested scope cut — the reviewer
  explicitly asked for link/URL sources to be downloaded (via the existing
  `mediaSourceToBlob`) and converted too, which is exactly the case the previous bullet's
  "nice side effect" was quietly relying on never happening. Fixed by checking `mediaType`
  first and falling back to the filename extension only when `mediaType` is unresolved,
  and by handling string sources through `mediaSourceToBlob` same as `File` ones. A third,
  smaller comment — *"why are we splitting by ? or # when we are passing a file name?"* on
  `isHeicSource`'s query-string stripping — flagged genuinely dead code: that stripping
  was shaped for a URL input the function never actually received at the time. Fixed by
  moving "reduce a URL to a bare filename" to a dedicated `new URL(...).pathname`-based
  helper at the one call site that now actually has a URL, keeping `isHeicSource` itself a
  real single-purpose, filename-only helper. Both findings, plus the two from PR #96,
  generalized into `tapestry-pr-conventions` as new numbered points — worth reading before
  writing any new `ItemFactory`-style branch on an existing pipeline. The broader lesson
  for this README specifically: a "nice side effect" noticed during self-review, before a
  real reviewer has looked at the code, is a hypothesis, not a finding — this bullet
  existed for less than a day before the next real review round showed it was actually a
  gap.
- Asked directly whether there were more general process-level learnings from this same
  PR loop, beyond individual review-comment findings — two came out of it, both folded
  into `tapestry-pr-conventions` as a "Pre-submission checklist" section (not just another
  numbered finding, a new kind of section): (1) the accumulated findings across #96 and
  #109 are specific and numerous enough now to actually run as a self-review pass against
  a diff *before* opening/updating a PR, rather than only serving as an after-the-fact
  explanation once a reviewer has already commented — the goal being to catch what's
  catchable without paying for a full review round-trip; (2) a real `gh` CLI gotcha: PR
  #109's round-1 review showed up via `gh pr view --json reviews` as `state: "COMMENTED"`
  with an empty `body` — the real feedback was two inline comments, only visible via
  `gh api .../pulls/<number>/comments`. An empty-body review reads like "nothing to
  address" if you stop there; it isn't. Not yet verified whether the checklist actually
  reduces round-trips on a real subsequent PR — that's the next thing to check.
- The very next PR #109 round answered part of that, but not the way originally hoped:
  round 2 landed on the round-1 *fix* itself (pushed before the checklist existed), so it
  couldn't test the checklist at all — it just supplied two more real findings
  (`tapestry-pr-conventions` points 9-10: don't apply a fallback path uniformly across
  every input branch when only one branch's primary signal is actually unreliable; check
  a library's real parameter type before wrapping data to fit an assumed stricter one, and
  don't manufacture metadata nothing downstream reads). Both quoted verbatim from the
  reviewer, one of them — *"This is again too complicated"* — using almost the same words
  as round 1's underlying complaint, on a fix that itself over-corrected into new
  unnecessary complexity. The actual test of whether the checklist reduces round-trips
  still hasn't happened yet: it requires a PR pushed *after* running the checklist against
  the diff, which this round wasn't. Whether that happens depends on there being a next
  round to check it against.
