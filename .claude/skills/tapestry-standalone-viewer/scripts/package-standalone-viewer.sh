#!/usr/bin/env bash
# Package the standalone /viewer app together with one tapestry .zip into a
# single, self-contained static directory — no server, no ?source= param the
# end user has to know about, no CORS setup (the zip ships same-origin with
# the viewer bundle). See tapestry-standalone-viewer's SKILL.md.
#
# Usage:
#   package-standalone-viewer.sh --zip tapestry.zip --output out-dir [options]
#
# Options:
#   --zip PATH          Tapestry export .zip to bundle (required)
#   --output DIR         Output directory to create (required; wiped if it exists)
#   --project-dir DIR    Path to a tapestry-project checkout (default: .)
#   --dist DIR            Reuse an already-built viewer/dist instead of rebuilding
#                          (skips the vite build step entirely)
#   --no-query-string     Hide the ?source=tapestry.zip param from the URL bar
#                          entirely (default: it's visible). Trades the app's
#                          documented ?source= contract for pre-seeding its
#                          undocumented "remember the last import" IndexedDB
#                          store instead — more fragile against future viewer
#                          changes; see SKILL.md before using this by default.
#   --serve [PORT]       After packaging, serve the result with `python3 -m
#                          http.server` (default port 8000) so you can open it
#                          immediately — Ctrl-C to stop
#   -h, --help            Show this help

set -euo pipefail

PROJECT_DIR="."
OUTPUT_DIR=""
ZIP_PATH=""
DIST_DIR=""
SERVE=0
SERVE_PORT=8000
MODE="query"

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP_PATH="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --dist) DIST_DIR="$2"; shift 2 ;;
    --no-query-string) MODE="hidden"; shift 1 ;;
    --serve)
      SERVE=1
      if [ $# -gt 1 ] && [[ "$2" =~ ^[0-9]+$ ]]; then SERVE_PORT="$2"; shift 2; else shift 1; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$ZIP_PATH" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "error: --zip and --output are required" >&2
  usage
  exit 1
fi
if [ ! -f "$ZIP_PATH" ]; then
  echo "error: zip not found: $ZIP_PATH" >&2
  exit 1
fi

if [ -z "$DIST_DIR" ]; then
  VIEWER_DIR="$PROJECT_DIR/viewer"
  if [ ! -d "$VIEWER_DIR" ]; then
    echo "error: no viewer/ directory at $VIEWER_DIR — pass --project-dir, or build" \
         "it yourself and pass --dist" >&2
    exit 1
  fi
  echo "Building viewer with a relative asset base (vite build --base=./)..."
  # Deliberately `vite build` directly, not `npm run build` (which also runs `tsc -b`) —
  # see tapestry-viewer-embedding: packaging a known-good viewer shouldn't fail because
  # of an unrelated, in-progress type error elsewhere in the monorepo.
  ( cd "$VIEWER_DIR" && npx vite build --base=./ )
  DIST_DIR="$VIEWER_DIR/dist"
fi

if [ ! -f "$DIST_DIR/index.html" ]; then
  echo "error: $DIST_DIR doesn't look like a built viewer (no index.html)" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"
cp -R "$DIST_DIR/." "$OUTPUT_DIR/"

cp "$ZIP_PATH" "$OUTPUT_DIR/tapestry.zip"

# The built viewer app uses <BrowserRouter><Routes><Route path="/" .../></Routes></...>
# (viewer/src/main.tsx) — it ONLY matches the exact pathname "/". So the entry point
# must stay named index.html, served at the site's root — renaming it (e.g. to
# viewer.html) or redirecting to a different path breaks React Router with "No routes
# matched location" (confirmed against a real deploy). Both modes below get the tapestry
# loaded without ever changing the pathname; they edit the BUILD OUTPUT as a packaging
# step (not viewer/'s source).
python3 - "$OUTPUT_DIR/index.html" "$MODE" <<'PYEOF'
import re
import sys

path, mode = sys.argv[1], sys.argv[2]
html = open(path, encoding="utf-8").read()

if mode == "query":
    # Calls history.replaceState to add ?source=tapestry.zip to the current URL before
    # the app's module script (which react-router reads on mount) ever runs. No
    # navigation, no redirect, no extra page — the same index.html, at "/", just already
    # has the query param by the time React mounts. Uses the app's own DOCUMENTED
    # ?source= contract — the robust default.
    bootstrap = (
        "<script>"
        "(function(){"
        "if(!/(?:^|[?&])source=/.test(location.search)){"
        "var sep=location.search?'&':'?';"
        "history.replaceState(null,'',location.pathname+location.search+sep+'source=tapestry.zip');"
        "}"
        "})();"
        "</script>\n"
    )
    new_html, count = re.subn(r'(<script type="module")', bootstrap + r"\1", html, count=1)
    if count != 1:
        print(f"error: could not find the module <script> tag in {path}", file=sys.stderr)
        sys.exit(1)
    html = new_html

else:  # mode == "hidden"
    # No query string ever appears. Instead, pre-seed the SAME IndexedDB store the app
    # itself falls back to reading when no ?source= is present (viewer/src/services/
    # db-service.ts: db "tapestry" v1, object store "last_tapestry", autoIncrement,
    # storing a raw ArrayBuffer) — an UNDOCUMENTED internal mechanism, not the app's
    # public contract, so this is more fragile against future viewer changes than the
    # "query" mode above. The real module <script> tag is removed from the static HTML
    # and only injected dynamically once seeding finishes, to avoid a race against the
    # app's own startup read of that same store. A count() check skips re-fetching the
    # zip on repeat visits once it's already seeded.
    match = re.search(r'<script type="module"[^>]*\ssrc="([^"]+)"[^>]*></script>', html)
    if not match:
        print(f"error: could not find the module <script> tag in {path}", file=sys.stderr)
        sys.exit(1)
    module_src = match.group(1)

    bootstrap = f"""<script>
(async function() {{
  try {{
    var req = indexedDB.open('tapestry', 1);
    req.onupgradeneeded = function() {{ req.result.createObjectStore('last_tapestry', {{autoIncrement: true}}); }};
    var db = await new Promise(function(res, rej) {{ req.onsuccess = function() {{ res(req.result) }}; req.onerror = function() {{ rej(req.error) }}; }});
    var countReq = db.transaction('last_tapestry', 'readonly').objectStore('last_tapestry').count();
    var existing = await new Promise(function(res, rej) {{ countReq.onsuccess = function() {{ res(countReq.result) }}; countReq.onerror = function() {{ rej(countReq.error) }}; }});
    if (!existing) {{
      var buf = await (await fetch('tapestry.zip')).arrayBuffer();
      var tx = db.transaction('last_tapestry', 'readwrite');
      tx.objectStore('last_tapestry').clear();
      tx.objectStore('last_tapestry').put(buf);
      await new Promise(function(res, rej) {{ tx.oncomplete = res; tx.onerror = function() {{ rej(tx.error) }}; }});
    }}
    db.close();
  }} catch (e) {{ console.warn('tapestry preload failed, falling back to the import UI', e); }}
  var s = document.createElement('script');
  s.type = 'module';
  s.crossOrigin = 'anonymous';
  s.src = '{module_src}';
  document.head.appendChild(s);
}})();
</script>
"""
    html = html[: match.start()] + bootstrap + html[match.end() :]

open(path, "w", encoding="utf-8").write(html)
PYEOF

echo
echo "Packaged standalone viewer app at: $OUTPUT_DIR"
echo "Serve it over any static http(s) server (NEVER open index.html via file://" \
     "— ES module <script> tags are blocked under that scheme) and open its root."

if [ "$SERVE" = "1" ]; then
  echo
  echo "Serving on http://localhost:$SERVE_PORT/ (Ctrl-C to stop)..."
  ( cd "$OUTPUT_DIR" && python3 -m http.server "$SERVE_PORT" )
fi
