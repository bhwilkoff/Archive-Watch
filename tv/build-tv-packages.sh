#!/usr/bin/env bash
# Assemble the LG webOS (.ipk) and Samsung Tizen (.wgt) packages from the ONE
# shared web app at the repo root (docs/TV-DESIGN.md §7.1, Decision 047).
#
# There is no separate TV codebase: this copies the same index.html / watch.js /
# watch.css / tv.js / tv.css the browser serves, drops in the per-platform
# manifest + icons, and hands off to the vendor CLI. If you ever find yourself
# editing a file inside tv/webos/app or tv/tizen/app, stop — the change belongs
# upstream in the shared app.
#
# Prerequisites (owner, one-time — see docs/TV-PLATFORM-BACKLOG.md §OWNER):
#   webOS : the webOS TV CLI (ares-package) — webostv.developer.lge.com
#   Tizen : Tizen Studio CLI (tizen build-web / tizen package) + a signing
#           certificate. KEEP THAT CERTIFICATE — Samsung requires every update
#           to be signed with the same one.
#
# Usage:  ./tv/build-tv-packages.sh [webos|tizen|all]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/tv/dist"
TARGET="${1:-all}"

# The shared app payload. Keep this list in sync with sw.js SHELL_URLS — both
# describe "what the app is made of".
APP_FILES=(index.html watch.css watch.js tv.css tv.js cast-sender.js manifest.json 404.html)
APP_DIRS=(assets)
# From js/ the viewer needs ONLY api.js. app.js and whats-new.js belong to the
# curator dashboard at /curate/ — dead weight in a TV package, and webOS's
# packager aborts trying to minify them.
APP_JS=(js/api.js)

# One source of truth for the version, the same file the Apple targets read
# (Decision 003). Both vendor manifests are STAMPED at package time rather than
# hand-edited, because they drifted immediately: the .ipk shipped 1.3.284 while
# the app was 1.3.309, and a store will happily accept a wrongly-versioned
# package and then refuse the next upload as "not newer".
VERSION="$(sed -n 's/^MARKETING_VERSION = //p' "$ROOT/AppVersion.xcconfig" | tr -d ' \r')"
if [ -z "$VERSION" ]; then
  echo "!! could not read MARKETING_VERSION from AppVersion.xcconfig" >&2
  exit 1
fi
echo "Version: $VERSION"

stage() {
  local dest="$1"
  rm -rf "$dest"
  mkdir -p "$dest"
  for f in "${APP_FILES[@]}"; do
    [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$dest/" || echo "  (skip missing $f)"
  done
  for d in "${APP_DIRS[@]}"; do
    [ -d "$ROOT/$d" ] && cp -R "$ROOT/$d" "$dest/" || true
  done
  for f in "${APP_JS[@]}"; do
    mkdir -p "$dest/$(dirname "$f")"
    [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$dest/$f" || echo "  (skip missing $f)"
  done
  # macOS turds ship inside the package otherwise. Removed here rather than via
  # ares-package -e, whose pattern did not match a nested assets/.DS_Store.
  find "$dest" -name '.DS_Store' -delete
  # The service worker is deliberately NOT packaged: a packaged TV app already
  # stores its resources locally, and a stale SW inside the package would shadow
  # the packaged files. Network data still comes from archivewatch.org, which
  # watch.js reaches because PAGES_ROOT falls back to the canonical origin under
  # file:// — do not "simplify" that back to a relative URL.
  rm -f "$dest/sw.js"
  # watch.js skips registration itself when the protocol is not http(s), so
  # there is nothing to strip here. Assert it, rather than trusting it: a
  # regression would mean a rejected register() on every TV launch.
  if ! grep -qF 'in navigator && /^https?:$/.test(location.protocol)' "$dest/watch.js"; then
    echo "  !! watch.js no longer guards serviceWorker registration by protocol" >&2
    exit 1
  fi
}

build_webos() {
  echo "==> webOS"
  local app="$ROOT/tv/webos/app"
  stage "$app"
  sed "s/\"version\"[[:space:]]*:[[:space:]]*\"[^\"]*\"/\"version\": \"$VERSION\"/" \
    "$ROOT/tv/webos/appinfo.json" > "$app/appinfo.json"
  cp "$ROOT/tv/webos/icon.png" "$ROOT/tv/webos/largeIcon.png" \
     "$ROOT/tv/webos/splash.png" "$app/"
  mkdir -p "$OUT"
  if command -v ares-package >/dev/null 2>&1; then
    # -n / --no-minify (undocumented in --help, present since 3.x). The CLI
    # bundles uglify-js, which cannot parse modern syntax (optional chaining,
    # nullish coalescing) and aborts the whole package. This app is deliberately
    # no-build-step vanilla (Decision 001), so minification is neither expected
    # nor wanted — and letting an old minifier rewrite working code is a risk,
    # not an optimisation.
    ares-package -n -e ".DS_Store" "$app" -o "$OUT"
    echo "    .ipk -> $OUT"
  else
    echo "    ares-package not installed — staged only at $app"
    echo "    Install the webOS TV CLI, then: ares-package $app -o $OUT"
  fi
}

build_tizen() {
  echo "==> Tizen"
  local app="$ROOT/tv/tizen/app"
  stage "$app"
  sed "s/version=\"[0-9][^\"]*\"/version=\"$VERSION\"/" \
    "$ROOT/tv/tizen/config.xml" > "$app/config.xml"
  cp "$ROOT/tv/tizen/icon.png" "$app/"
  mkdir -p "$OUT"
  if command -v tizen >/dev/null 2>&1; then
    tizen build-web -- "$app"
    # tizen build-web emits into <app>/.buildResult
    tizen package -t wgt -o "$OUT" -- "$app/.buildResult"
    echo "    .wgt -> $OUT"
  else
    echo "    tizen CLI not installed — staged only at $app"
    echo "    Install Tizen Studio CLI, create a signing certificate, then:"
    echo "      tizen build-web -- $app"
    echo "      tizen package -t wgt -o $OUT -- $app/.buildResult"
  fi
}

case "$TARGET" in
  webos) build_webos ;;
  tizen) build_tizen ;;
  all)   build_webos; build_tizen ;;
  *)     echo "usage: $0 [webos|tizen|all]" >&2; exit 2 ;;
esac

echo "Done."
