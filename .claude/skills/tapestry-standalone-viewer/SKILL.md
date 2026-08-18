---
name: tapestry-standalone-viewer
description: Package the standalone /viewer app together with ONE specific tapestry .zip into a single self-contained static directory — no server-side templating, no CORS setup, no ?source= param the end user has to know about. A specialization of tapestry-viewer-embedding's recipe (which packages the viewer generically, for any zip a host points it at) for the "one app, one fixed tapestry" case — the same shape as e.g. a WordPress plugin bundle, but as a plain static folder any http(s) host can serve. Includes a bundled script; verified against a real deploy failure (a naive redirect-to-a-renamed-file approach breaks the viewer's client-side router) and fixed with an approach confirmed in a real headless browser, not just curl
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

**Verified end-to-end against a real headless browser, not just curl.** An earlier
version of this skill renamed the built entry point to `viewer.html` and redirected
there — that passed a `curl`-and-static-server check (every path returned `200`) but
**failed in an actual browser** when a real user deployed it to Netlify: the viewer's
`<BrowserRouter>` (`viewer/src/main.tsx`) registers exactly one route,
`<Route path="/">`, and matches nothing else — navigating to `/viewer.html` hit "No
routes matched location" and rendered blank. `curl` can't catch this class of bug at
all (it doesn't execute JS or a router); only a real browser run reveals it. The current
approach (below) was verified by actually driving headless Chrome against a served
build: no console errors, the real tapestry content rendered, and the final URL stayed
at the site root with the query string appended (`.../?source=tapestry.zip`), not a
separate path.

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
`out-dir` **unchanged** (same `index.html`, same filename, at the root), copies your
`.zip` in as `tapestry.zip`, and injects a small bootstrap script into that
`index.html`'s `<head>` — see below for exactly what it does and why. Already have a
built `viewer/dist`? Pass `--dist path/to/viewer/dist` instead of `--project-dir` to
skip the rebuild. Add `--serve [port]` to immediately serve the result locally with
`python3 -m http.server` (matches `tapestry-viewer-embedding`'s macOS reference
integration's own approach to getting a real http(s) origin) so you can check it right
away.

If the input zip needs to be built or validated first, see `tapestry-zip-authoring` /
`tapestry-zip-analysis` — this skill only handles the packaging step, not producing or
checking the zip's contents.

## Why there's no redirect, and no renamed entry point

The viewer's app reads which zip to load from a `?source=` query param
(`useSearchParams()` in `viewer/src/app.tsx`) — but its `<BrowserRouter>` only ever
registers `<Route path="/">` (`viewer/src/main.tsx`), matching that exact pathname and
nothing else. **Any approach that serves the tapestry from a different path — a
renamed file, a redirect to one — breaks the router outright** ("No routes matched
location", confirmed against a real deploy). So the query param has to land on the
*same* path (`/`, i.e. the untouched, unrenamed `index.html`) without ever navigating
elsewhere.

The fix: inject one small, plain (non-module) inline script into the built
`index.html`'s `<head>`, immediately before the built module `<script>` tag:

```html
<script>(function(){
  if(!/(?:^|[?&])source=/.test(location.search)){
    var sep = location.search ? '&' : '?';
    history.replaceState(null, '', location.pathname + location.search + sep + 'source=tapestry.zip');
  }
})();</script>
```

`history.replaceState` rewrites the current URL's query string **without navigating** —
no page load, no history entry, no visible redirect. Because this plain script isn't
`type="module"` (module scripts are deferred until HTML parsing finishes), it runs
*before* the module script that boots React and mounts `<BrowserRouter>`. By the time
`useSearchParams()` first reads `location.search`, the `source` param is already there
— the router never sees any path but `/`, and the URL bar ends up at
`https://your-host/?source=tapestry.zip`, not a separate page.

This edits the *build output* (`dist/index.html`) as a packaging step — not
`viewer/`'s TypeScript/React source, which is what `tapestry-viewer-embedding`
guardrail #1 actually means to rule out. Regenerate via the script (or a fresh
`vite build --base=./` plus re-running the injection) if the viewer itself changes;
don't hand-maintain a divergent copy of this one-line patch.

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
2. **Never rename the entry point or redirect to a different path** — the viewer's
   router matches `/` only; any other path fails with "No routes matched location".
   Keep `index.html`'s filename and location exactly as built.
3. **Still never serve the result over `file://`** — the built viewer uses ES module
   `<script>` tags, blocked under that scheme regardless of how the query param gets
   attached. Static-http-serve it, always.
4. **Validate a fix like this against a real browser, not just `curl`/a static-file
   check** — a client-side routing bug produces `200`s for every file and still fails
   completely once real JS executes. `curl` genuinely cannot catch that class of bug.
5. **One zip per package** — this skill is deliberately for the fixed-single-tapestry
   case. If the actual need is "let the host choose which zip at runtime," that's
   `tapestry-viewer-embedding`'s `?source=` contract directly, not this.
6. **A zip that opens correctly here is not proof it would survive a real server-side
   import** — the viewer's own zip-reading is slightly more lenient (see
   `tapestry-zip-authoring`'s note on this). Validate a hand-built zip with
   `tapestry-zip-analysis` if it also needs to work as a real import, not just display
   in the viewer.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/package-standalone-viewer.sh` | Builds (or reuses) the viewer, copies its output plus one tapestry `.zip` into a fresh directory unchanged, and injects a `history.replaceState` bootstrap script into `index.html` so `?source=tapestry.zip` is present before the app mounts — same path, no redirect. Optional `--serve` to check it immediately with a local static server. |
