---
name: tapestry-viewer-embedding
description: Package asteasolutions/tapestry-project's standalone /viewer app for use somewhere other than a normal website — a WordPress block, a native desktop file-opener, or anything else that needs to display a Tapestry .zip without depending on the full client/server app. The viewer itself is real upstream code; the packaging recipe is generalized from two real custom integrations (a WordPress Gutenberg block, a macOS drag-and-drop opener) found in unmerged exploratory work
license: MIT
compatibility: claude-code
depends_on: []
skill_discovery_hints:
  - keywords: ["embed tapestry viewer", "package viewer", "vite build --base", "standalone viewer"]
  - keywords: ["WordPress block", "Gutenberg block", "macOS app", "file:// CORS module"]
  - keywords: ["source query param", "same-origin fetch", "tapestry zip"]
last_verified: 2026-08-12
---

Recipe for taking `/viewer` — the standalone, read-only Tapestry viewer that already ships
in this repo as a normal npm workspace — and packaging it for a host environment that isn't
a plain website: a CMS plugin, a native desktop app, anything that needs to display an
exported Tapestry `.zip` without pulling in the full `client`/`server` app (auth, live
sockets, editing). **`/viewer` itself is real, existing upstream code** (see
`tapestry-client-features` for why it's deliberately minimal — it only depends on
`tapestry-core`/`tapestry-core-client`, nothing else). The packaging recipe below is
generalized from two real, complete reference integrations found in unmerged exploratory
work — not present on any long-lived branch:

- **A WordPress Gutenberg block** that embeds the viewer in an `<iframe>` inside a post,
  pointed at a ZIP uploaded to the WordPress Media Library.
- **A macOS drag-and-drop opener** — an `.app` you drop an exported `.zip` onto, which opens
  it in your default browser.

**Neither integration exists on any current branch of `asteasolutions/tapestry-project` or
any default fork branch** — they're reference examples for this skill's packaging pattern,
not features to claim already exist. Don't tell a user there's a real WordPress plugin or
macOS app available; use this as the template for building a *new* host integration.

## Why the viewer is embeddable at all

`/viewer`'s entire integration surface is deliberately tiny, and — critically — **neither
reference integration modifies `viewer/` source at all**. They only change how it's built
and hosted. Its whole loading contract (`viewer/src/app.tsx`):

- If the page URL has a `?source=<url>` query param, it `fetch()`es that URL, treats the
  response as a Tapestry export `.zip`, and renders it read-only.
- Otherwise, it checks IndexedDB for a previously-imported file (so a reload doesn't lose
  it), and if there isn't one, shows a plain drag-and-drop/file-picker UI that imports a
  local `.zip` and remembers it the same way.

**Embedding the viewer somewhere new is almost entirely about (1) building it correctly for
wherever it'll be served from, and (2) pointing it at a URL via `?source=`** — not about
writing any new viewer code. Reach for `tapestry-content-types`/`tapestry-webpage-types`
instead if the actual goal is changing what the viewer can *render*; this skill is purely
about hosting the existing thing somewhere else.

## The core recipe (both reference integrations do exactly this)

1. **Build with a relative asset base**: `cd viewer && npx vite build --base=./` — not
   plain `npm run build`. Vite's default build assumes the bundle is served from a domain
   root, so `index.html` references assets as `/assets/...`; `--base=./` makes it
   `./assets/...` instead, which is required the moment the bundle is served from any
   subdirectory (a plugin folder, an app bundle's `Resources/`) rather than a site's root.
   **Both reference integrations independently deliberately skip the `tsc -b` type-check**
   that `viewer`'s own `npm run build` script runs first, calling `vite build` directly
   instead — packaging a known-good viewer shouldn't fail because of an unrelated,
   in-progress type error elsewhere in the monorepo.
2. **Copy `viewer/dist/` wholesale** into wherever your host platform wants static assets —
   a plugin subfolder, an app bundle's resources directory. It's a normal static site
   (HTML/JS/CSS/assets); nothing about it is platform-specific yet.
3. **Serve it over a real `http(s)` origin — never open the built `index.html` directly via
   a `file://` URL.** This is the single constraint that shapes everything else about
   packaging for a non-website host: Vite's build emits `<script type="module">` tags, and
   browsers block ES module loading under the `file://` scheme as a cross-origin
   restriction. If your host environment doesn't already give you an http(s) origin for
   free (a real website does; a native desktop shell doesn't), you have to stand up a
   server yourself — even a trivial one. The macOS reference integration's entire reason
   for existing is this one constraint: it copies the bundled viewer plus the dropped file
   into a local directory, starts a throwaway local static server there
   (`python3 -m http.server`), and opens `http://localhost:<port>/index.html?source=...` —
   specifically so the browser sees a real http origin instead of `file://`.
4. **Point it at the tapestry via the viewer's own, unmodified `?source=<url>` param.** The
   WordPress integration's front end renders nothing but an
   `<iframe src="…/viewer/index.html?source=<urlencoded zip URL>">`. The macOS integration
   copies the dropped file into its local server's directory and opens
   `…/index.html?source=dropped.zip`. Both reference integrations reuse this exact
   mechanism verbatim — resist the temptation to add a second, bespoke way to hand the
   viewer a file.
5. **Package the whole resulting artifact with one script**, matching the shape both
   reference integrations converge on independently: rebuild the viewer (step 1) → copy its
   output into the host's own resource folder (step 2) → zip up the *entire host artifact*
   (an installable plugin archive, an app bundle) for distribution. Don't hand-assemble this
   by hand each time; script it once.

## Same-origin vs. CORS

**Keep the viewer bundle and the `.zip` it points at on the same origin when you control
both** — the WordPress integration does this automatically, since the plugin's bundled
viewer and the Media-Library-hosted ZIP are both served from the WordPress site's own
domain, making the viewer's internal `fetch(source)` call same-origin. No CORS
configuration needed at all in that case. **If the ZIP has to live on a different origin
than the viewer bundle**, that remote host must send permissive CORS headers — it's the
viewer's own client-side code making that cross-origin request, not something the embedding
host can configure on the viewer's behalf.

## Two ways to embed, compared

| Approach | Example | Isolation | Cost |
|---|---|---|---|
| **iframe embed** | The WordPress integration (explicitly "v1" per its own docs) | Full CSS/JS isolation from the host page — nothing in the viewer can clash with host styles/scripts | A tapestry canvas has no intrinsic size, so the host must pick an explicit height; a nested page load per embed |
| **Native mount** | Not implemented by either reference integration, but explicitly anticipated as a future option | Seamless visual integration into the host page | The host's own JS bundle has to actually depend on and mount `tapestry-core-client` directly, not just host a static build — much heavier integration |

Default to the iframe approach — it's what both real complexity-appropriate reference
integrations actually ship, needs zero changes to viewer source either way, and keeps the
host's own build completely decoupled from the viewer's. Only reach for a native mount if
the host environment is itself a React app that can afford to depend on
`tapestry-core-client` directly and truly needs seamless in-page integration.

## Platform-specific gotchas, generalized

- **Register your host platform's own `.zip` file-type allowlist — don't assume it's
  accepted by default.** WordPress blocks `.zip` media uploads by default and needs an
  `upload_mimes` filter to allow them; a macOS app needs a `CFBundleDocumentTypes` entry
  declaring `public.zip-archive` in its `Info.plist` before Finder will let a user drop a
  `.zip` onto it. Whatever your host platform is, check for its equivalent gate rather than
  assuming `.zip` "just works."
- **A native drag-and-drop wrapper may need a real compiled shim, not just a script.** On
  macOS specifically, a bare shell-script bundle executable launches fine but can never
  receive the `application(_:open:)` Apple Event Finder sends for a file dropped on the app
  or its Dock icon — that delivery mechanism is fundamentally different from argv, which
  only applies to a genuine command-line invocation. The real fix needs a tiny compiled
  AppKit shim whose only job is to receive that event and hand the file path to a plain
  shell script that does the actual work (build the local server, open the browser, etc.).
  If you're wrapping the viewer in an equivalently minimal native shell on a different OS,
  check whether that platform's file-open/drag-drop delivery has an analogous requirement
  before assuming a bare script executable is enough.
- **Lazy-load the viewer bundle if it's not always shown.** It bundles Pixi.js plus
  `tapestry-core-client` and runs to a few MB — the WordPress integration only loads it on
  pages that actually contain the block, and marks the iframe `loading="lazy"`. Don't ship
  it unconditionally if the host only sometimes needs it.

## Set correct offline-capability expectations

Regardless of the host platform, **only assets genuinely byte-embedded in the export render
without network access** — media the user actually uploaded into Tapestries is stored as
real bytes in the `.zip` and displays fully offline. Anything backed by a live external
source keeps only that URL in the export, not downloaded content: a `webpage` item (see
`tapestry-webpage-types` — an embedded page, YouTube/Vimeo, SoundCloud/Spotify, a Wikipedia
article) or an `iiif` deep-zoom item (see `tapestry-content-types` — tiles stream from the
external IIIF server on demand) both need real internet access to render **no matter how
"offline" the packaging otherwise is**. This is inherent to the content model, not
something any host-platform wrapper can work around — say so explicitly if a new
integration is being pitched as "works offline."

## Guardrails

1. **Don't modify `viewer/` source for a new embedding target.** The `?source=<url>`
   contract (and the no-source drag-and-drop-import fallback) is the entire integration
   surface; if a new host integration seems to need viewer code changes, reconsider whether
   it actually does.
2. **Always build with `--base=./`** (or an equivalent relative/subpath base matching your
   actual deployment path) unless the bundle will genuinely be served from a domain root.
3. **Never open the built bundle via `file://`.** Provide a real http(s) origin, standing
   one up yourself if the host platform doesn't already give you one for free.
4. **Keep the viewer bundle and the ZIP same-origin when you control both**, to skip CORS
   entirely; require permissive CORS from the ZIP's host only when you don't.
5. **Set offline-capability expectations correctly** — byte-embedded assets only; anything
   URL-backed always needs network, regardless of packaging.
6. See `tapestry-client-features` for why `/viewer` is architecturally minimal enough to be
   embeddable like this in the first place (no auth, no sockets, `core-client`-only), and
   `tapestry-content-types`/`tapestry-webpage-types` if the actual goal is changing what the
   viewer renders rather than where it's hosted.
