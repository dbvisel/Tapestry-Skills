---
name: tapestry-standalone-viewer
description: Package the standalone /viewer app together with ONE specific tapestry .zip into a single self-contained static directory — no server-side templating, no CORS setup, no ?source= param the end user has to know about. A specialization of tapestry-viewer-embedding's recipe (which packages the viewer generically, for any zip a host points it at) for the "one app, one fixed tapestry" case — the same shape as e.g. a WordPress plugin bundle, but as a plain static folder any http(s) host can serve. Includes a bundled script, verified end-to-end against a real viewer build and a real sample zip
license: MIT
compatibility: claude-code
depends_on: ["tapestry-viewer-embedding"]
skill_discovery_hints:
  - keywords: ["standalone tapestry viewer", "bundle viewer with zip", "self-contained tapestry app"]
  - keywords: ["package-standalone-viewer.sh", "offline tapestry viewer", "tapestry static site"]
  - keywords: ["fixed source zip", "embed one tapestry", "distribute a tapestry as a webpage"]
last_verified: 2026-08-18
---

Build a single static directory that bundles the standalone `/viewer` app **with one
specific tapestry `.zip` already attached** — open the directory's `index.html` (served
over any http(s) origin) and that exact tapestry loads, with no query param, no server,
and no CORS configuration to get right. Use this skill's bundled
`scripts/package-standalone-viewer.sh` rather than assembling this by hand.

**This is a specialization of `tapestry-viewer-embedding`, not a competing approach** —
read that skill first. It documents the general recipe (build with `--base=./`, never
serve over `file://`, point the viewer at a zip via its own unmodified `?source=<url>`
contract) for a viewer that's pointed at *some* zip supplied by the host at runtime (a
WordPress block pointed at a Media-Library upload, a macOS opener pointed at whatever
file was dropped on it). This skill covers the narrower, simpler case where the zip is
known **at packaging time** and baked into the output — one app, one fixed tapestry,
nothing chosen at runtime.

**Verified end-to-end, not just assembled from the general recipe**: this skill's
script was actually run against a real viewer build (`vite build --base=./` against
`asteasolutions/tapestry-project`'s real `viewer/` workspace) and a real sample tapestry
zip, and the resulting directory was served with a real static HTTP server and checked
with `curl` — the redirect page, the renamed entry point, every asset path, and the
bundled zip all resolved with `200` over a real origin.

## When to use this skill

- "Turn this tapestry into a standalone web page/app" / "export this tapestry as a
  static site"
- "Bundle the viewer with this specific .zip so it just opens" (as opposed to: "let my
  CMS/app choose which zip to show at runtime" — that's `tapestry-viewer-embedding`)
- Distributing one tapestry to someone who just needs to double-click/upload/host a
  folder, without touching a `?source=` URL param or a database
- Same underlying mechanism as packaging a WordPress plugin around the viewer (see
  `tapestry-viewer-embedding`), but the output here is a plain static folder — no CMS,
  no plugin API, just files any http(s) host can serve

## The short version: use the bundled script

```bash
scripts/package-standalone-viewer.sh --zip tapestry.zip --output out-dir --project-dir /path/to/tapestry-project
```

This builds the viewer (`vite build --base=./`, skipping the monorepo-wide `tsc -b`
check — same reasoning as `tapestry-viewer-embedding`), copies its output into
`out-dir`, renames the built `index.html` to `viewer.html`, copies your `.zip` in as
`tapestry.zip`, and writes a **new** `index.html` at the root that's a thin redirect to
`viewer.html?source=tapestry.zip`. Already have a built `viewer/dist`? Pass `--dist
path/to/viewer/dist` instead of `--project-dir` to skip the rebuild. Add `--serve
[port]` to immediately serve the result locally with `python3 -m http.server` (matches
`tapestry-viewer-embedding`'s macOS reference integration's own approach to getting a
real http(s) origin) so you can check it right away.

If the input zip needs to be built or validated first, see `tapestry-zip-authoring` /
`tapestry-zip-analysis` — this skill only handles the packaging step, not producing or
checking the zip's contents.

## How the redirect works, and why it's not a viewer-source change

`tapestry-viewer-embedding` guardrail #1 is "don't modify `viewer/` source for a new
embedding target" — this skill doesn't. The built `viewer.html` (the renamed, untouched
build output of `viewer/index.html`) is never edited. Instead, a **new, separate**
`index.html` is written alongside it:

```html
<meta http-equiv="refresh" content="0; url=viewer.html?source=tapestry.zip" />
<script>location.replace('viewer.html?source=tapestry.zip')</script>
```

Both the `<meta refresh>` and the inline script do the same redirect — the `<meta>` tag
covers the (rare) case of JS being disabled; the script fires immediately without
waiting for the refresh delay everywhere else. This is why the entry point had to move:
if the written-out `index.html` and the viewer's own built `index.html` were the same
file, there'd be nothing to redirect *to*. Renaming the build output to `viewer.html` is
safe because `--base=./` (see `tapestry-viewer-embedding`) made every asset reference
inside it relative to the containing *directory*, not to its own filename — confirmed
directly: a real build's `favicon.png` link and `<script src>`/`<link href>` all came
out as `./favicon.png`, `./assets/...` regardless of what the HTML file itself is named.

## Why no CORS setup is ever needed here

`tapestry-viewer-embedding` spends a whole section on same-origin vs. CORS, because in
the general case the viewer bundle and the zip it's pointed at can live on different
origins (a CMS plugin's bundled viewer vs. a Media-Library-hosted file, say), which
needs either same-origin hosting or permissive CORS headers from the zip's host. **That
whole concern doesn't exist here** — the zip is copied into the exact same output
directory as the viewer bundle, so `fetch('tapestry.zip', ...)` (a same-directory
relative URL) is always same-origin with whatever static host serves the folder, by
construction. This is the main simplification this skill's narrower scope buys over the
general recipe.

## Guardrails

1. **Read `tapestry-viewer-embedding` first** — this skill only covers the packaging
   step; the underlying constraints (never `file://`, `--base=./`, don't touch viewer
   source, offline-capability limits for URL-backed content) all still apply and aren't
   re-explained here.
2. **The new `index.html` is a thin redirect, not a modification of the built viewer** —
   don't hand-edit the *built* `viewer.html`/`assets/` output; regenerate it via the
   script (or a fresh `vite build --base=./`) if the viewer itself needs to change.
3. **Still never serve the result over `file://`** — the built viewer uses ES module
   `<script>` tags, blocked under that scheme regardless of how simple the redirect
   trick looks. Static-http-serve it, always.
4. **One zip per package** — this skill is deliberately for the fixed-single-tapestry
   case. If the actual need is "let the host choose which zip at runtime," that's
   `tapestry-viewer-embedding`'s `?source=` contract directly, not this.
5. **A zip that opens correctly here is not proof it would survive a real server-side
   import** — the viewer's own zip-reading is slightly more lenient (see
   `tapestry-zip-authoring`'s note on this). Validate a hand-built zip with
   `tapestry-zip-analysis` if it also needs to work as a real import, not just display
   in the viewer.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/package-standalone-viewer.sh` | Builds (or reuses) the viewer, copies its output plus one tapestry `.zip` into a fresh directory, renames the entry point, and writes a redirect `index.html` so the whole thing opens with no `?source=` param needed. Optional `--serve` to check it immediately with a local static server. |
