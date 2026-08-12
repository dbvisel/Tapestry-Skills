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
| [`tapestry-webpage-types`](.claude/skills/tapestry-webpage-types/SKILL.md) | Adding a new *known webpage type* (recognizing a specific site's URLs) without adding a whole new item type — two strategies, embed-and-iframe or fetch-and-render-as-DOM, generalized from three real (unmerged) reference implementations: SoundCloud, Spotify, and Wikipedia |

## Using these skills

Copy `.claude/skills/` into a `tapestry-project` checkout (or symlink it), or point
your agent's skill-search path at this repo. Each `SKILL.md` cross-references its
siblings (e.g. the client and server skills each note where the auth-provider or
live-update story continues on the other side).

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
  `dbvisel/main`) plus, later, the `model3d` item type on branch `wikimania-mess` — one
  giant, deliberately-flagged-messy commit ("Everything added for Wikimania") that bundles
  in a lot of unrelated work; only the lines actually touching `model3d` were used. Neither
  IIIF nor `model3d` support exists on any default branch — again, patterns to follow, not
  features to claim exist. The second example was folded in specifically because it
  revealed real gaps the first alone had left the skill overstating (e.g. that a bespoke
  item factory is always necessary — `model3d` shows the far more common case of reusing
  the existing generic file-matching factory instead).
- `tapestry-webpage-types` is built from two small commits on `iiif-image-support` (dirty,
  not up to date per its own author) plus, later, a `wikipedia` webpage type — which does
  turn out to be real, just on `wikimania-mess` rather than `iiif-image-support` where it
  was first (and correctly) found not to exist. Wikipedia's implementation is a genuinely
  different strategy from SoundCloud/Spotify: instead of iframing a rewritten embed URL, it
  fetches the article via the Wikipedia REST API and renders sanitized DOM directly in a
  fully custom component — revealing a whole dispatch mechanism (a per-`webpageType`
  component override, optional and client-only) the skill didn't cover until this was
  folded in. None of the three exists on any default branch.
