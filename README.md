# Tapestry-Skills

Claude Code / Claude Agent skills for working on
[`asteasolutions/tapestry-project`](https://github.com/asteasolutions/tapestry-project)
("Tapestries") — a canvas/annotation web app with a `core` / `core-client` / `client` /
`server` / `shared` / `viewer` npm-workspaces monorepo.

Modeled on the structure of [Wikipedia-AI-Skills](https://github.com/fuzheado/Wikipedia-AI-Skills):
each skill is a `SKILL.md` under `.claude/skills/<name>/`, with `references/` for
longer supporting docs where useful. This first pass intentionally skips the
reference repo's CI verification workflows, audit scripts, and test suite — just the
skill content, to start.

## Skills

| Skill | Covers |
|---|---|
| [`tapestry-local-dev-environment`](.claude/skills/tapestry-local-dev-environment/SKILL.md) | Running the app locally the way upstream documents it (npm workspaces, per-workspace `.env` files, LocalStack/Redis/Vault via `docker-compose.local.yml`, Vite dev server) — plus a clearly-separated note on a Docker+MinIO installer variation that exists only on some forks, and the CSP issue that only shows up there |
| [`tapestry-production-deployment`](.claude/skills/tapestry-production-deployment/SKILL.md) | Updating a customized production VM deployment — fork/merge workflow, `docker-compose-fnf.yml` specifics, and the resource-contention outage to avoid repeating |
| [`tapestry-client-features`](.claude/skills/tapestry-client-features/SKILL.md) | Adding UI functionality in `client`/`core-client` — canvas item types, the controller/manager pattern, auth providers, live updates, build-time config |
| [`tapestry-server-worker`](.claude/skills/tapestry-server-worker/SKILL.md) | Adding backend functionality — REST resources, Prisma models/migrations, BullMQ jobs, S3/MinIO presigning, Vault-backed secrets, Socket.io fan-out |
| [`tapestry-auth-providers`](.claude/skills/tapestry-auth-providers/SKILL.md) | Adding a new external login provider — full client+server+schema+deployment checklist, generalized from two real (unmerged) reference implementations: ORCID and MediaWiki OAuth |
| [`tapestry-content-types`](.claude/skills/tapestry-content-types/SKILL.md) | Adding a new canvas content/item type while changing as little as possible — full checklist including the easy-to-miss export-version bump, generalized from two real (unmerged) reference implementations: IIIF deep-zoom images and STL 3D models |
| [`tapestry-webpage-types`](.claude/skills/tapestry-webpage-types/SKILL.md) | Adding a new *known webpage type* (recognizing a specific site's URLs) without adding a whole new item type — two strategies, embed-and-iframe or fetch-and-render-as-DOM, generalized from four real (unmerged) reference implementations: SoundCloud, Spotify, Sketchfab, and Wikipedia |
| [`tapestry-external-media-sources`](.claude/skills/tapestry-external-media-sources/SKILL.md) | Letting users paste a URL that *describes* a single file on an external platform (e.g. a Wikimedia Commons `File:` page) and importing the real file as a plain, ordinary item of an existing type — no schema changes at all, the lightest of the "URL connection" patterns. Generalized from two real (unmerged) reference implementations: Wikimedia Commons and Openverse single-file import |
| [`tapestry-collection-imports`](.claude/skills/tapestry-collection-imports/SKILL.md) | Extending Tapestries' existing bulk-import picker (real upstream functionality) with a new collection type — a Wikimedia Commons category, an Openverse tag search, an Internet Archive search query — generalized from three real (unmerged) reference implementations of that extension |
| [`tapestry-viewer-embedding`](.claude/skills/tapestry-viewer-embedding/SKILL.md) | Packaging the real, existing standalone `/viewer` app for a host that isn't a website — build with `--base=./`, serve over a real http(s) origin (never `file://`), point it at `?source=<url>` unmodified — generalized from two real (unmerged) reference integrations: a WordPress block and a macOS drag-and-drop opener |
| [`tapestry-visibility`](.claude/skills/tapestry-visibility/SKILL.md) | Managing a tapestry's visibility (private/link/public) on a running installation via the bundled `manage-tapestry-visibility.sh` script, including how "public" surfaces it in every client's "Samples" list |
| [`tapestry-backups`](.claude/skills/tapestry-backups/SKILL.md) | Backing up a Tapestry installation's Postgres database and MinIO object storage via the bundled `backup-tapestry.sh` script (interactive or scheduled), plus how to restore |
| [`tapestry-zip-authoring`](.claude/skills/tapestry-zip-authoring/SKILL.md) | Constructing a valid tapestry export/import `.zip` from scratch — the full `root.json` schema and file-naming convention, plus a bundled, dependency-free builder script. **Does not require a `tapestry-project` checkout** — verified directly against the real app's schema/import behavior rather than derived from reading its source |
| [`tapestry-zip-analysis`](.claude/skills/tapestry-zip-analysis/SKILL.md) | Analyzing an existing tapestry `.zip` — version, item inventory, groups/rels/presentation structure, and whether it's actually importable — via a bundled, dependency-free analyzer script. **Does not require a `tapestry-project` checkout**; depends on `tapestry-zip-authoring` for the schema reference, not on the app's source |
| [`tapestry-standalone-viewer`](.claude/skills/tapestry-standalone-viewer/SKILL.md) | A specialization of `tapestry-viewer-embedding` for the "one app, one fixed tapestry" case: a bundled script packages the standalone `/viewer` build together with one specific `.zip` into a self-contained static folder — no CORS setup, since the zip ships same-origin with the viewer, and (optionally, with a documented trade-off) no visible `?source=` param either |

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

## Status

Built from a hands-on local-dev session plus codebase research — not yet verified
against a from-scratch read by anyone but the agent that wrote it. Treat facts in here
as accurate as of the `last_verified` date in each `SKILL.md`'s frontmatter, and expect
some upstream drift over time (e.g. new Prisma migrations, new item types).

**`asteasolutions/tapestry-project` `main` is treated as the definitive upstream
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
  commit, but this one directly on top of upstream `asteasolutions/main` rather than
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
- `tapestry-standalone-viewer`'s first version shipped a real bug that a curl-and-static-file
  check didn't catch: it renamed the built viewer's `index.html` to `viewer.html` and
  redirected there, which passed every `200`-status check but broke in an actual browser —
  the viewer's `<BrowserRouter>` only registers `<Route path="/">`, so navigating to
  `/viewer.html` hit "No routes matched location" and rendered blank. Found only once a real
  user deployed the output to Netlify. Fixed by never renaming/redirecting at all: a small
  bootstrap script injected into the untouched `index.html` sets the loading state (either the
  app's own `?source=` URL param via `history.replaceState`, or — optionally, via
  `--no-query-string` — its IndexedDB "last import" fallback store) before the app mounts, and
  the fix was verified against a real headless-Chrome run instead of just `curl`. The skill's
  "Performance at scale" section is similarly measured, not assumed: a real 430 MB/236-item
  tapestry rendered in ~5s over loopback, showing the actual bottleneck for large tapestries is
  the viewer's lack of streaming/range-request support on download, not the zip format or
  client-side decompression.
