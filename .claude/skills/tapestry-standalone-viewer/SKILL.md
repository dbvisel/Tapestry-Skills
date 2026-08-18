---
name: tapestry-standalone-viewer
description: Package the standalone /viewer app together with ONE specific tapestry .zip into a single self-contained static directory — no server-side templating, no CORS setup, no ?source= param the end user has to know about. A specialization of tapestry-viewer-embedding's recipe (which packages the viewer generically, for any zip a host points it at) for the "one app, one fixed tapestry" case — the same shape as e.g. a WordPress plugin bundle, but as a plain static folder any http(s) host can serve. Includes a bundled script, verified end-to-end in a real headless browser (not just curl/static-file checks) against a real viewer build and a real sample zip
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
over any http(s) origin) and that exact tapestry loads, with no server and no CORS
configuration to get right (a visible `?source=` query param by default; optionally
hidden entirely with `--no-query-string`, at a real trade-off — see below). Use this
skill's bundled `scripts/package-standalone-viewer.sh` rather than assembling this by
hand.

**This is a specialization of `tapestry-viewer-embedding`, not a competing approach** —
read that skill first. It documents the general recipe (build with `--base=./`, never
serve over `file://`, point the viewer at a zip via its own unmodified `?source=<url>`
contract) for a viewer that's pointed at *some* zip supplied by the host at runtime (a
WordPress block pointed at a Media-Library upload, a macOS opener pointed at whatever
file was dropped on it). This skill covers the narrower, simpler case where the zip is
known **at packaging time** and baked into the output — one app, one fixed tapestry,
nothing chosen at runtime.

**Verified end-to-end against a real headless browser, not just curl.** The viewer's
`<BrowserRouter>` (`viewer/src/main.tsx`) registers exactly one route, `<Route
path="/">`, and matches nothing else — a `curl`-and-static-server check can't reveal
that, since it doesn't execute JS or a router; it takes an actual browser run. Both
modes below were verified that way: driving headless Chrome against a served build
confirms no console errors, the real tapestry content rendering, and the URL staying at
the site root throughout (with the query string appended in the default mode, or
completely bare with `--no-query-string` — which also skips re-fetching the zip on
reload, reading from IndexedDB instead).

## When to use this skill

- "Turn this tapestry into a standalone web page/app" / "export this tapestry as a
  static site"
- "Bundle the viewer with this specific .zip so it just opens" (as opposed to: "let my
  CMS/app choose which zip to show at runtime" — that's `tapestry-viewer-embedding`)
- Distributing one tapestry to someone who just needs to upload/host a folder — no URL
  param to configure, no database
- "I don't want the `?source=` param visible in the URL at all" — `--no-query-string`,
  with a real trade-off (see below) worth reading before defaulting to it
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
location", confirmed against a real deploy). So getting the tapestry loaded has to
happen *without ever navigating away from `/`* (i.e. the untouched, unrenamed
`index.html`). Both of the script's two modes below do this; they differ only in
**where the zip reference comes from and whether it shows up in the URL.**

### Default mode: visible `?source=` (the app's documented contract)

Inject one small, plain (non-module) inline script into the built `index.html`'s
`<head>`, immediately before the built module `<script>` tag:

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
`https://your-host/?source=tapestry.zip`, not a separate page. This uses the app's own
**documented** loading contract (the same `?source=` mechanism `tapestry-viewer-embedding`
covers for the general case) — the most future-proof option, at the cost of a visible
query string.

### `--no-query-string`: hides it, at the cost of depending on an undocumented mechanism

If even the visible `?source=tapestry.zip` isn't acceptable, `--no-query-string` hides
it completely — verified working in a real browser (see below) — by using the app's
*other* fallback path instead: with no `source` param, `app.tsx` falls back to reading
a previously-imported file from IndexedDB (`viewer/src/services/db-service.ts`: database
`tapestry` v1, object store `last_tapestry`, autoincrement key, storing a raw
`ArrayBuffer`) — the mechanism that normally lets a returning visitor's last
drag-and-dropped import survive a page reload. This mode pre-seeds that exact store with
the bundled zip's bytes, **before** dynamically injecting the real module script (the
static module `<script>` tag is removed from the HTML entirely and only added back,
pointing at the same built filename, once seeding finishes) — avoiding a race against
the app's own startup read of that store. A `count()` check skips the fetch-and-reseed
work on repeat visits once it's already there, so this isn't a "refetch the zip on every
load" cost.

**The trade-off**: this depends on an *undocumented* internal storage schema
(`db-service.ts`'s exact db/store names and shape) rather than the app's public
`?source=` URL contract, so it's more fragile against a future viewer change — if that
schema is ever renamed or restructured, this mode silently stops working (falls through
to the app's own empty-state import UI, per the `try/catch`) while the default mode
would keep working unaffected. Default to the visible-query-string mode; reach for
`--no-query-string` only when a literally bare URL is a real requirement.

Both modes edit the *build output* (`dist/index.html`) as a packaging step — not
`viewer/`'s TypeScript/React source, which is what `tapestry-viewer-embedding`
guardrail #1 actually means to rule out. Regenerate via the script (or a fresh
`vite build --base=./` plus re-running the injection) if the viewer itself changes;
don't hand-maintain a divergent copy of either patch.

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

## Performance at scale: network download dominates, not unzipping

Real public tapestries range from a few MB to 400+ MB. **Measured directly** (real
headless Chrome, the same package this skill produces, a real 430 MB / 236-item / 821
zip-entry tapestry, served over loopback so network transfer cost is negligible): the
zip finished transferring in ~1.1s, and real canvas content was rendering by ~4.6–5.4s
total — meaning the client-side unzip-and-decompress-everything step
(`ImportService.parse`'s `Promise.all` over every item's source and every thumbnail
rendition, `viewer/src/services/import-service.ts`) cost only a few seconds even for
236 items and hundreds of renditions. JS heap stayed at 22–41 MB throughout — the
decompressed bytes live in browser-managed Blob storage, not the JS heap, so this isn't
a heap-exhaustion risk either.

**The real cost at scale is the download itself, not decompression.** `app.tsx` loads
the zip via `fetch(source).arrayBuffer()`, which cannot return until the *entire*
response body has arrived — there's no client-side streaming or HTTP range-request
support (contrast the *server* importer, `tapestry-import-service.ts`, which does use
range requests via `zip.js`'s `HttpReader`; the browser viewer doesn't). So for a real
deployment of a 400+ MB tapestry on ordinary broadband (~5–10 MB/s), expect **tens of
seconds to a couple of minutes of blank-screen download time** before anything renders
— that's inherent to the current viewer, not something this packaging skill introduces
or can fix.

**Pre-unzipping does not help this, and can make it worse.** The bottleneck is total
bytes that must arrive before rendering starts, not the zip container format — a
pre-extracted folder loaded by an equivalent "fetch everything, then render" approach
faces the identical download-time cost, and loses the zip's compression and single-request
efficiency in the process (see guardrail below). The only thing that would actually help
a very large tapestry load faster is genuine lazy loading — fetching `root.json` first,
then only the assets for items actually on screen — which means a materially different
loader that doesn't go through `ImportService` at all. That's a real gap in `/viewer`
itself worth flagging if it comes up, not something to attempt inside this packaging
skill's scope.

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
4. **Validate any change here against a real browser, not just `curl`/a static-file
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
7. **Default to the visible-`?source=` mode; treat `--no-query-string` as an opt-in
   trade.** It depends on `db-service.ts`'s undocumented internal storage schema rather
   than the app's public URL contract, so it's the more fragile of the two against
   future viewer changes. Reach for it only when a literally bare URL is a genuine
   requirement, not by default.
8. **Don't try to avoid shipping the `.zip` by pre-unzipping it.** The viewer's real
   loader (`ImportService.parse`, `viewer/src/services/import-service.ts`) is built
   entirely around parsing a zip blob and resolving `file:/...` references to entries
   *inside that same zip* — there's no supported "loose files + a manifest" path. Doing
   this would mean hand-reimplementing `parseRootJson` and the `file:/` resolution logic
   outside the app's real, tested code — exactly the kind of unverified custom logic
   guardrail #4 is warning against. It's also not a real performance win — see
   "Performance at scale" above for the measured reasoning: the bottleneck for a large
   tapestry is total bytes downloaded before rendering starts, and pre-unzipping doesn't
   reduce that.

## Bundled scripts

| File | Purpose |
|---|---|
| `scripts/package-standalone-viewer.sh` | Builds (or reuses) the viewer, copies its output plus one tapestry `.zip` into a fresh directory unchanged, and injects a bootstrap script into `index.html` so the app finds the zip before it mounts — same path, no redirect. Default mode sets `?source=tapestry.zip` via `history.replaceState` (visible, documented contract); `--no-query-string` instead pre-seeds the viewer's IndexedDB "last import" store (hidden, undocumented mechanism — see the trade-off above). Optional `--serve` to check it immediately with a local static server. |
