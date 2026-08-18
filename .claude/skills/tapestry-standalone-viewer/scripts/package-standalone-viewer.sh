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

# Rename the built entry point out of the way of our own index.html. Safe because
# --base=./ made every asset reference in it relative to the containing directory,
# not to the filename "index.html" itself — confirmed by inspecting a real build.
mv "$OUTPUT_DIR/index.html" "$OUTPUT_DIR/viewer.html"

cp "$ZIP_PATH" "$OUTPUT_DIR/tapestry.zip"

# A thin redirect shim — NOT a modification of viewer/ source (see
# tapestry-viewer-embedding guardrail #1) — so opening the directory's root just
# works, without anyone needing to know about ?source=.
cat > "$OUTPUT_DIR/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta http-equiv="refresh" content="0; url=viewer.html?source=tapestry.zip" />
  <title>Tapestry</title>
  <script>location.replace('viewer.html?source=tapestry.zip')</script>
</head>
<body>
  <p>Loading tapestry&hellip; if nothing happens,
    <a href="viewer.html?source=tapestry.zip">click here</a>.</p>
</body>
</html>
HTML

echo
echo "Packaged standalone viewer app at: $OUTPUT_DIR"
echo "Serve it over any static http(s) server (NEVER open index.html via file://" \
     "— ES module <script> tags are blocked under that scheme) and open its root."

if [ "$SERVE" = "1" ]; then
  echo
  echo "Serving on http://localhost:$SERVE_PORT/ (Ctrl-C to stop)..."
  ( cd "$OUTPUT_DIR" && python3 -m http.server "$SERVE_PORT" )
fi
