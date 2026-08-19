# Tapestry-Skills maintenance

This file only applies when working *inside this repo* to author/maintain skills. It
has no effect on a `tapestry-project` checkout that only copies `.claude/skills/` in —
see README.md's "Using these skills."

## When adding, removing, or renaming a skill

- Add/update its row in `README.md`'s skill table in the same commit. This has drifted
  before (`tapestry-visibility`, `tapestry-backups` were added without a table row) —
  don't let it happen again.
- If the skill has a real "here's what we got wrong and fixed" story (not just routine
  content), fold a note into README's "Status" section, matching the existing bullets'
  style — that section exists specifically to save a future editor from repeating the
  same mistake.
- Cross-reference related skills both ways: a prose mention in each `SKILL.md` where
  relevant, and `depends_on` in frontmatter when one skill genuinely needs the other's
  content to be understood first (not just "vaguely related").

## Every `SKILL.md`

- Frontmatter: `name`, `description`, `license: MIT`, `compatibility: claude-code`,
  `depends_on` (array, `[]` if none), `skill_discovery_hints` (keyword groups),
  `last_verified` (bump it whenever you substantively verify or edit the content, not
  just on typo fixes).
- Be explicit about what's **real, existing upstream code** vs. a **reference
  implementation on an unmerged fork/branch** — several skills exist specifically to
  generalize a pattern from unmerged exploratory work, and conflating "here's the
  pattern to follow" with "this already works upstream" is the single most common way
  these docs mislead a future reader. State it plainly whichever way it is.
- Standard sections: "When to use this skill," the checklist/how-to content itself,
  "Guardrails" (numbered), and — if the skill bundles anything — a "Bundled scripts"
  and/or "Bundled assets" table at the end (see below for the distinction).

## Bundled scripts, references, and assets

Three distinct directories, don't blur them:

- `scripts/` — executable code (bash/python) the agent runs.
- `references/` — prose supporting docs, loaded on-demand.
- `assets/` — non-executable templates/configs the agent copies or hands to the
  user (a `.env.sample`, a Dockerfile, a compose file, a sample spec). Not a
  script itself, even if a script in the same skill reads it —
  `tapestry-local-dev-environment`'s `setup.sh` lives in `scripts/`, but the
  `.env.sample`/`docker-compose.minio.yml`/`Dockerfile.client-minio` it reads
  live in `assets/`, since none of them are code that runs.

For anything landing in `scripts/`:

- Follow `.claude/guidelines/script-audit-guidelines.md`: zero-argument handling,
  `-h`/`--help`, `set -euo pipefail`, no bash 4+ features, errors to stderr.
- **Run it for real before calling it done — don't just read it and reason about
  whether it should work.** `tapestry-standalone-viewer`'s first version passed a
  `curl`-and-static-file check and still broke in a real browser (a client-side router
  bug curl can't see). When JS runtime behavior matters, that means an actual browser
  (headless Chrome via Playwright is available), not just checking HTTP status codes.
- When a script's behavior depends on the real app (schema validation, an actual
  import/export path, a live API), verify against the real thing when it's reasonably
  available — a local Docker stack for `tapestry-project` exists and can be brought up
  (see `tapestry-local-dev-environment`) — rather than only reasoning from reading the
  source. Several skills in this repo were corrected by exactly this kind of check.

## Repo-level maintenance tooling: `tools/`

`tools/` at the repo root is for scripts that audit *this repo itself* — distinct
from a skill's own `scripts/`, which is content a skill hands to whoever uses it.
Run before committing any change to `.claude/skills/`:

```bash
python3 tools/verify-skills.py
```

Structural, offline, stdlib-only: every skill has complete frontmatter,
`last_verified` is a real date and not stale, every `depends_on` target exists,
every bundled `scripts/`/`references/`/`assets/` file is actually mentioned in its
`SKILL.md`, and every bundled-file path *mentioned* in a `SKILL.md` actually exists.
This is the automation of the "when adding/removing/renaming a skill" and "every
`SKILL.md`" sections above — it catches drift, it doesn't replace judgment about
content quality.

### Where this fits in a bigger picture, and when to grow it

`verify-skills.py` is "Tier 1" of a maturity model worth keeping in mind as this repo
grows (adapted from surveying `fuzheado/Wikipedia-AI-Skills`' considerably larger
`scripts/`+`tests/` setup — most of it is sized for *their* scale — dozens of skills,
hundreds of cited external URLs and live APIs — not this repo's, so don't adopt it
just because it exists there):

- **Tier 1 (this)** — structural self-checks, offline, no new dependencies. Worth
  having from early on; the cost is low and it directly automates hygiene this repo
  has already drifted on by hand at least twice.
- **Tier 2 — external-reality checks.** Wikipedia-AI-Skills validates that cited URLs
  and API endpoints are still live, via a periodically-refreshed, checked-in registry
  file (so the actual CI check stays offline). This repo's equivalent risk isn't URL
  rot, it's `tapestry-project`'s source drifting from what a skill claims — worth
  building once there's enough external-reference churn to justify it, not before.
  A rough trigger: skills routinely going stale between `last_verified` bumps because
  the *app*, not the doc, moved.
- **Tier 3 — reporting/dashboards.** A metrics table (word/line counts, dependency
  graph) once eyeballing `README.md`'s table stops being enough. Cheap to build on
  top of Tier 1's frontmatter parsing whenever it's actually wanted.
- **Tier 4 — functional tests for bundled scripts.** Worth it once there are enough
  *deterministic, dependency-free* scripts to regression-test formally — right now
  that's really just `tapestry-zip-authoring`/`tapestry-zip-analysis`'s two Python
  tools; most other bundled scripts wrap Docker/Postgres and need live infra to test
  meaningfully anyway. A rough trigger: three or more scripts in that
  testable-without-live-infra category.
- **Tier 5 — the audit as a repeatable multi-agent workflow**, not code: a documented
  prompt that fans a full-repo audit out across parallel subagents by domain. Ports
  well regardless of scale, but only pays for itself once there are enough skills that
  reading all of them in one pass gets unwieldy — Wikipedia-AI-Skills needed 6 batches
  for ~47 skills; this repo's skill count still fits in one pass.

Don't build Tier 2+ preemptively — add each when its trigger condition actually shows
up, not on a schedule.

## Tone

Skills in this repo write guardrails and gotchas as concrete, verified claims with
enough detail to explain *why* — not generic best-practice advice. If you can't verify
a claim, say so explicitly rather than presenting it with the same confidence as a
verified one.
