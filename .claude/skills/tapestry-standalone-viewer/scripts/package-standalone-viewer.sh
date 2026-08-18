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

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --zip) ZIP_PATH="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --dist) DIST_DIR="$2"; shift 2 ;;
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
# matched location" (confirmed against a real deploy). The query param the app reads
# (?source=...) has to reach it WITHOUT changing the pathname, so instead of a redirect
# we inject a tiny bootstrap script into the built index.html's <head> — this edits the
# BUILD OUTPUT as a packaging step, not viewer/'s source — that calls
# history.replaceState to add ?source=tapestry.zip to the current URL before the app's
# module script (which React Router reads on mount) ever runs. No navigation, no
# redirect, no extra page — the same index.html, at "/", just already has the query
# param by the time React mounts.
python3 - "$OUTPUT_DIR/index.html" <<'PYEOF'
import re
import sys

path = sys.argv[1]
html = open(path, encoding="utf-8").read()

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

# Insert immediately before the built module <script> tag, so this plain (non-module,
# non-deferred) script runs first during HTML parsing.
new_html, count = re.subn(
    r'(<script type="module")', bootstrap + r"\1", html, count=1
)
if count != 1:
    print(f"error: could not find the module <script> tag in {path}", file=sys.stderr)
    sys.exit(1)

open(path, "w", encoding="utf-8").write(new_html)
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
