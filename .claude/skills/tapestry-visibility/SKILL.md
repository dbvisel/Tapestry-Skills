---
name: tapestry-visibility
description: Manage a tapestry's visibility (private/link/public) on a running Tapestry installation via the bundled manage-tapestry-visibility.sh script, including how "public" makes a tapestry appear in every client's "Samples" list
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["tapestry visibility", "make tapestry public", "Samples list", "manage-tapestry-visibility.sh"]
  - keywords: ["private link public tapestry", "TapestryVisibility enum"]
last_verified: 2026-08-19
---

Change a tapestry's visibility on a live installation from the command line, via
`scripts/manage-tapestry-visibility.sh`.

## When to use this skill

- "Make this tapestry public" / "publish a sample tapestry"
- "What does public/link/private actually mean for a tapestry?"
- Auditing or bulk-reviewing which tapestries are currently public
- Reverting a tapestry made public by mistake

## What visibility means

`Tapestry.visibility` (`server/prisma/schema.prisma`, enum `TapestryVisibility`) is
one of three values, defaulting to `private`:

- **`private`** — only the owner and explicitly invited users.
- **`link`** — anyone with the tapestry's link.
- **`public`** — listed in the **"Samples"** list every client sees on startup
  (`client/src/pages/dashboard/header/index.tsx`; server-side filtering in
  `server/src/resources/tapestries.ts`). This is the one with real reach: any
  visitor to the installation can find and open it without a link.

## Using the script

Run from the repo directory on the server, with the stack up:

```bash
./manage-tapestry-visibility.sh            # list everything, then pick one
./manage-tapestry-visibility.sh <search>   # filter by title / slug / owner email
./manage-tapestry-visibility.sh --help     # show usage
```

It lists matching tapestries in a numbered table (title, owner, slug, current
visibility, id), lets you pick one, shows its current state, prompts for the new
visibility, and **requires typing `yes`** to confirm before writing anything —
safe to run without fear of an accidental one-key change or a fat-fingered
selection.

Under the hood it's a single `UPDATE "Tapestry" SET visibility = ... WHERE id = ...`
run via `docker compose exec <db> psql`, no different from what you'd type by
hand — the script exists for the safety rails (confirmation prompt, injection-safe
filtering, a read-only preflight check that the database is even reachable
before showing you anything) more than for saving keystrokes.

Overridable via environment variables (defaults shown, matching
`tapestry-production-deployment`'s `docker-compose-fnf.yml` setup):

```bash
COMPOSE_FILE=docker-compose-fnf.yml
ENV_FILE=.env
DB_SERVICE=db   DB_USER=tapestries   DB_NAME=tapestries
```

Point these at a different compose file/service/database name for other installs
(e.g. upstream's plain `docker-compose.local.yml` with `db`/`tapestries`/`tapestries`
still as defaults, or a differently-named database).

## Doing it without the script

If you just need a one-off read (not a change), the same `psql` access works
directly and doesn't need the script's confirmation flow:

```bash
docker compose -f docker-compose-fnf.yml exec -T db \
  psql -U tapestries -d tapestries -c \
  "SELECT title, slug, visibility FROM \"Tapestry\" WHERE visibility = 'public';"
```

For an actual visibility *change*, prefer the script — hand-writing the `UPDATE`
skips its confirmation step and its filter-escaping, and it's easy to select the
wrong row by id when several tapestries share a similar title.

## Guardrails

1. **This script is VM/fork-only, not upstream** — like `docker-compose-fnf.yml`
   itself, it's not part of `internetarchive/tapestry-project`; it assumes the
   Postgres access pattern that deployment uses (see `tapestry-production-deployment`).
2. **`public` has real reach** — it's not "shareable," it's "discoverable by
   anyone on the installation." Confirm that's actually intended before setting it,
   especially when a search-by-title match is ambiguous (the picker shows
   owner + slug + id specifically so you're not guessing from title alone).
3. **Always run from the repo directory on the server**, with the stack up —
   the script's preflight check fails fast with a clear message if the database
   isn't reachable, rather than doing something confusing.
4. **Restoring a tapestry's visibility isn't automatic** — the script doesn't track
   history, so note the "current visibility" it prints before changing anything if
   you might need to revert.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/manage-tapestry-visibility.sh` | Interactively list tapestries (optionally filtered) and change one's visibility, with a confirmation prompt before writing. |
