---
name: tapestry-listing
description: Read-only, sortable report of every tapestry on a running installation (title, owner, visibility, last updated, view URL) via the bundled list-tapestries.sh script
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["list tapestries", "all tapestries", "tapestry report", "list-tapestries.sh"]
  - keywords: ["tapestry URL", "username slug URL", "what tapestries exist"]
last_verified: 2026-10-21
---

Print a read-only, sortable report of every tapestry on a running Tapestry
installation: title, owner, visibility, when it was last updated, and its
real view URL. No picking, no mutation — purely a status report, for when
you want to see what's on an installation rather than change anything about
it.

## When to use this skill

- "List all the tapestries on this installation"
- "What tapestries exist, who owns them, when were they last touched"
- Generating a quick audit/report of a Tapestry installation's content
- You want `manage-tapestry-visibility.sh`'s table but without the interactive
  picker/mutation that follows it — see `tapestry-visibility` for that

## Using the script

```bash
cd my-tapestry-repo/scripts
REPO_DIR=.. ./list-tapestries.sh                      # everything, most recently updated first
REPO_DIR=.. ./list-tapestries.sh wikimania            # filter by title / slug / owner email
REPO_DIR=.. ./list-tapestries.sh --sort title         # sort by a different column
REPO_DIR=.. ./list-tapestries.sh wikimania --sort owner  # filter and sort together
./list-tapestries.sh --help                           # show usage
```

It prints a table with five columns:

- **title** — truncated to 40 characters with a trailing `…` so long titles
  don't blow out the table's width (same approach as `manage-tapestry-visibility.sh`)
- **owner** — the owner's email if known, otherwise their raw user id (same
  `COALESCE(u.email, t."ownerId")` as `manage-tapestry-visibility.sh`, so the
  two scripts' output is consistent)
- **visibility** — `Tapestry.visibility` (`private`/`link`/`public`), plain
- **last_updated** — `Tapestry.updatedAt`, formatted `YYYY-MM-DD HH24:MI`
- **url** — the tapestry's real view URL, `/u/<owner's username>/<slug>`
  (`client/src/utils/paths.ts`'s `tapestryPath()`, route registered in
  `client/src/main.tsx` as `/u/:username/:slug/:edit?`). Set `BASE_URL` (e.g.
  `https://tapestries.archive.org`) to get a full absolute URL instead of the
  bare path — left unset, you just get `/u/username/slug`. `NULL` here means
  the tapestry's owner row is missing (a deleted/orphaned user), since a URL
  needs a real username.

Sorted most-recently-updated first by default, since this is a status report
("what's been active lately") rather than a lookup tool — unlike
`manage-tapestry-visibility.sh`, which sorts alphabetically by title because
you're picking one out by name. Override with `--sort title`/`owner`/
`visibility`/`updated` (or the `SORT` env var) — these are the only four
accepted values, translated to a fixed `ORDER BY` expression via a `case`
statement in the script, not interpolated directly into SQL, so there's no
injection surface from this flag the way there could be with free-form
column/direction input.

Same connection mechanism as `manage-tapestry-visibility.sh`: runs
`docker compose exec` against the `db` service, same `REPO_DIR`/`COMPOSE_FILE`/
`ENV_FILE`/`DB_SERVICE`/`DB_USER`/`DB_NAME` overrides, same preflight
connectivity check, same injection-safe filter escaping. If you're unfamiliar
with that harness, `tapestry-visibility`'s SKILL.md walks through it in the
context of an interactive script, which may be easier to follow first.

## Guardrails

1. **This is read-only** — it never writes to the database. No confirmation
   prompt exists because there's nothing to confirm.
2. **`url` is `NULL` for a tapestry whose owner row no longer exists** — don't
   assume every row has a usable URL; check for `NULL` before using the
   output programmatically (e.g. piping into another script).
3. **`BASE_URL` is unset by default, not hardcoded to any one deployment's
   domain** — this script is meant to work against any Tapestry installation,
   not just one specific fork. Set it per-invocation (or export it in your
   shell) rather than hardcoding a domain into a local copy of the script.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/list-tapestries.sh` | Prints the read-only tapestries report described above. |
