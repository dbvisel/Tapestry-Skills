---
name: tapestry-zip-analysis
description: Analyze an existing Tapestry .zip file (a tapestry export/import bundle) to report what it contains — version, item counts and types, groups/rels/presentation structure, and whether it's actually valid/importable — without needing internetarchive/tapestry-project's source or a running server. Depends on tapestry-zip-authoring for the full root.json schema reference
license: MIT
compatibility: claude-code
depends_on: ["tapestry-zip-authoring"]
skill_discovery_hints:
  - keywords: ["analyze tapestry zip", "what's in this tapestry zip", "inspect root.json", "tapestry export contents"]
  - keywords: ["validate tapestry zip", "tapestry zip report", "is this tapestry zip valid"]
  - keywords: ["tapestry-import-service validation", "presentation step order", "file:/ dangling reference"]
last_verified: 2026-08-18
---

How to open an existing Tapestry `.zip` (an export/import bundle — see
`tapestry-zip-authoring` for the full format) and report what's actually in it: version,
item inventory, structural elements (groups/rels/presentation), and whether it would
actually import cleanly. Use this skill's bundled `scripts/analyze-tapestry-zip.py`
rather than re-deriving the parsing logic — it's stdlib-only Python (no dependencies,
no need for the tapestry-project repo or a running server) and was verified against 19
real public tapestry zips spanning schema versions 5 and 7, plus a deliberately broken
zip to confirm it actually catches problems rather than just reporting happy-path stats.

**This skill depends on `tapestry-zip-authoring`** for the full field-by-field
`root.json` schema — read that skill first if you need the complete shape of an item,
group, rel, or presentation step. This skill is about *reading and validating* an
existing zip, not constructing one.

## When to use this skill

- "What's in this tapestry .zip?" / "Analyze this tapestry export"
- "Is this tapestry zip valid?" / "Will this import cleanly?"
- Comparing several tapestry zips (e.g. auditing a batch of exports)
- Paired with `tapestry-zip-authoring` when you've hand-built or generated a zip and
  want to sanity-check it before handing it to a user to import

## The short version: use the bundled script

```bash
python3 scripts/analyze-tapestry-zip.py path/to/tapestry.zip        # human-readable report
python3 scripts/analyze-tapestry-zip.py path/to/tapestry.zip --json # same data, as JSON
```

Exit code is `0` if no problems were found, `1` otherwise — safe to use in a batch
script over many zips. Example output on a real sample:

```
version:      5
  note: version 5 is not the current schema (7), but that's normal — real-world exports
  are frequently older versions, and the app auto-upgrades them on import via a
  migration chain. Not a defect.
title:        'What is/are Tapestries?'
...
items (193):
  text: 94
  webpage: 63
  actionButton: 20
  image: 12
  pdf: 4
  webpage subtypes:
    (generic): 33
    youtube: 20
    iaWayback: 9
    iaVideo: 1
  bundled media (in-zip): 15
  external media (URLs): 64

groups: 3   rels: 81
presentation steps: 0

zip entries: 111   uncompressed size: 33,312,313 bytes

No problems found.
```

## What the script checks, and why each check matters

These mirror what the real app's importer (`tapestry-import-service.ts`) actually does
— not a stricter or looser standard invented for this skill:

1. **`root.json` exists at the zip root, and is valid JSON.** If either fails, nothing
   else can be checked — the real importer throws `ImportError('root-not-found')` or an
   uncaught `SyntaxError` respectively.
2. **`version` is a number this script recognizes (0-7 as of `last_verified`).** An
   older version than 7 is **normal, not a defect** — the real app has an 8-parser
   migration chain (`v0` through `v7`) and auto-upgrades any older export on import.
   Don't report a v5 zip as "outdated" or "broken"; report it as "will be auto-upgraded
   on import." An unrecognized version is the real problem — that's what the app's
   `ImportError('unrecognized-version')` actually guards against.
3. **Every `file:/`-prefixed reference (tapestry thumbnail, item `source`, thumbnail
   rendition `source`) resolves to an actual zip entry**, by exact filename match. A
   dangling reference is exactly what makes the real importer throw
   `ImportError('item-source-not-found')`.
4. **Every media item's bundled `source` entry name has a parenthesized segment.** This
   one doesn't fail JSON-schema-style validation at all — root.json can be perfectly
   well-formed — but the real importer's filename-extraction regex
   (`/.*\((.*)\)/.exec(filename)![1]`) returns `null` on a name without parens, and the
   `![1]` throws an uncaught `TypeError`, aborting the whole import ungracefully. This is
   the single most important non-obvious check this script does — verified by
   reproducing the exact crash. See `tapestry-zip-authoring`'s SKILL.md for the full
   naming convention.
5. **Every item's `groupId` (if set) actually appears in `groups[]`.** Not something the
   real importer's Zod schema enforces (`groupId` is just `z.string().nullish()`), but a
   dangling group reference indicates a corrupted or hand-edited export worth flagging.
6. **Presentation steps form one well-formed chain.** See the next section — this is
   easy to get subtly wrong and worth checking explicitly.

## Reconstructing presentation order

`presentation` is an array of steps, but **not in display order** — each step links to
its *predecessor* via `prevStepId` (a backward-linked list). The step with
`prevStepId: null` is the first slide; to get display order, build a map from
`prevStepId -> step` and walk forward from the root:

```python
by_prev = {s["prevStepId"]: s for s in steps if s.get("prevStepId")}
current = next(s for s in steps if s.get("prevStepId") is None)
order = [current]
while current["id"] in by_prev:
    current = by_prev[current["id"]]
    order.append(current)
```

Verified against real presentations of 15 and 55 steps (`Every Song is a Rabbit Hole`,
`Happy Birthday Bob!`) — both reconstructed correctly into a single ordered chain from
root to tip. A raw step *count* is fine for a quick summary, but if you're describing
*what a presentation does* (e.g. "walks through 12 groups in this order"), reconstruct
the order — don't assume the array's storage order means anything.

## Interpreting fields for a human-readable report

- **Item type counts** are the most useful top-level summary — `webpage` items further
  break down by `webpageType` (`null`/absent = a generic embedded page, not an error;
  `youtube`/`vimeo`/`iaWayback`/`iaAudio`/`iaVideo` = specially-handled embeds).
- **Bundled vs. external media** (does `source` start with `file:/`?) tells you whether
  re-importing this zip elsewhere would still work if the original external URLs rot —
  bundled assets travel with the zip; external ones depend on the source URL still
  being alive. Worth calling out explicitly for an archival-context "will this still
  work in 5 years" question.
- **A thumbnail rendition's `isAutoGenerated: false`** means a user uploaded that
  specific image as a custom thumbnail, rather than the server generating one from the
  source file — useful for distinguishing "the creator chose this image" from "this is
  just a resized version of the source."
- **`groups`/`rels` being empty is completely normal** — many real tapestries (e.g. a
  simple showcase gallery) have zero connectors and zero explicit groups; don't treat
  either as a sign of an incomplete or broken export.
- **`presentation` being empty is also normal** — most real tapestries have no
  presentation at all (only 2 of 19 sampled real public tapestries did).

## Guardrails

1. **A version other than 7 is not a defect** — see point 2 above. Report it neutrally.
2. **The parenthesized-filename check matters more than it looks** — it's the one
   failure mode that produces an ugly crash instead of a clean rejection; always run it,
   don't just eyeball root.json's JSON-schema-shaped validity and call it done.
3. **Don't assume `presentation`'s array order is display order** — reconstruct via
   `prevStepId` before describing "what a presentation does."
4. **Don't flag empty `groups`/`rels`/`presentation` as problems** — they're common and
   fine.
5. For the full field-by-field schema of anything referenced here (an item type's exact
   shape, a group/rel's fields), see `tapestry-zip-authoring` rather than re-deriving it.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/analyze-tapestry-zip.py` | Opens a tapestry `.zip`, parses `root.json`, and prints a structured report (or `--json`) covering version, item inventory, groups/rels/presentation, and validity problems (dangling `file:/` references, missing-parens crash risk, dangling `groupId`s). Stdlib-only Python. Exit code reflects whether problems were found. |
