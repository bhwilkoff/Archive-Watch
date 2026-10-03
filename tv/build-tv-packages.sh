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
# DERIVED from index.html, never hand-kept. This was `APP_JS=(js/api.js)` and
# went stale the moment sync shipped (2026-09-03): index.html gained
# js/drivesync.js and js/cloudkitsync.js, the packages did not, and every TV
# launch since made two requests that 404. Nothing THREW — watch.js calls them
# as `window.AWDriveSync?.init(...)` — which is exactly why it went unnoticed.
# Read what the page actually loads instead of maintaining a second list.
APP_JS=($(grep -oE 'src="js/[A-Za-z0-9._-]+\.js"' "$ROOT/index.html" \
          | sed 's/src="//; s/"//' | sort -u))

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

# DEBUG HOOKS, for testing on a retail set that offers no shell, no screenshot
# and no inspector (docs/tizen-signing.md). Both are off unless asked for, and
# the package is renamed ArchiveWatch-debug.wgt when either is on.
#
#   AW_TV_INSPECT=10.0.0.90:8080   load Chii's target script, so Chrome DevTools
#                                  on this Mac inspects the app ON the TV
#                                  (console, DOM, network, focus). Run:
#                                  chii start -p 8080
#   AW_TV_LIVE=http://10.0.0.90:8099/?tv=1
#                                  boot the app from a server on this Mac
#                                  instead of the package, so a change reaches
#                                  the TV with a reload. NOT the shipped origin:
#                                  final checks are always on a packaged build.
debug_hooks() {
  local dest="$1"
  if [ -n "${AW_TV_INSPECT:-}" ]; then
    sed -i '' "s#<head>#<head><script src=\"http://${AW_TV_INSPECT}/target.js\"></script>#" "$dest/index.html"
    # A WIDGET WITH NO CSP OF ITS OWN ONLY RUNS ITS OWN SCRIPTS: the set ran
    # the debug package and never requested target.js (2026-10-03). So the
    # debug package names the inspector host; the store package declares none.
    sed -i '' "s#</widget>#  <tizen:content-security-policy>default-src * data: blob: 'unsafe-inline' 'unsafe-eval'; script-src 'self' file: 'unsafe-inline' 'unsafe-eval' http://${AW_TV_INSPECT}; connect-src * ws: wss:</tizen:content-security-policy>\n</widget>#" "$dest/config.xml"
    echo "    inspector hook -> http://${AW_TV_INSPECT}/target.js"
  fi
  if [ -n "${AW_TV_LIVE:-}" ]; then
    cat > "$dest/live-launcher.html" <<HTML
<!doctype html><meta charset="utf-8"><title>Archive Watch (live)</title>
<body style="background:#000;color:#fff;font:32px sans-serif;padding:96px">
Loading from ${AW_TV_LIVE}…
<script>location.replace("${AW_TV_LIVE}")</script>
HTML
    sed -i '' 's#<content src="index.html"/>#<content src="live-launcher.html"/>#' "$dest/config.xml"
    local host; host="$(echo "$AW_TV_LIVE" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')"
    sed -i '' "s#<tizen:allow-navigation>#<tizen:allow-navigation>${host} #" "$dest/config.xml"
    echo "    live launcher -> ${AW_TV_LIVE}"
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
  # ONLY the widget's own version attribute. An unanchored `version="..."`
  # also matches the XML DECLARATION (which must stay 1.0) and
  # required_version (the minimum TIZEN PLATFORM, not our app) — it rewrote
  # both, and nobody saw it because no .wgt was ever built until 2026-09-09.
  sed -E "s/^([[:space:]]*)version=\"[0-9][^\"]*\"/\1version=\"$VERSION\"/" \
    "$ROOT/tv/tizen/config.xml" > "$app/config.xml"
  cp "$ROOT/tv/tizen/icon.png" "$app/"
  # SAMSUNG'S PLATFORM API (webapis.appcommon — the screensaver during
  # playback). It exists only on the set, at the $WEBAPIS path the runtime
  # resolves, so it is added to the Tizen package and never to the web.
  sed -i '' 's#<script src="tv.js"></script>#<script src="$WEBAPIS/webapis/webapis.js"></script>\
  <script src="tv.js"></script>#' "$app/index.html"
  grep -q 'webapis/webapis.js' "$app/index.html" || { echo "  !! webapis.js was not added" >&2; exit 1; }
  debug_hooks "$app"
  mkdir -p "$OUT"
  if command -v tizen >/dev/null 2>&1; then
    tizen build-web -- "$app"
    # tizen build-web emits into <app>/.buildResult
    tizen package -t wgt ${TIZEN_PROFILE:+-s "$TIZEN_PROFILE"} -o "$OUT" -- "$app/.buildResult"
    # `tizen package` names the file from config.xml's <name>, which is
    # "Archive Watch" — WITH A SPACE. `tizen install` interpolates that path
    # into a remote shell command unquoted, so the install fails on the TV with
    # NO ERROR AT ALL: no reason, no platform log, nothing. Renaming it is what
    # turned that silence into the real diagnostic (a certificate chain error).
    # Never ship a .wgt whose name contains a space.
    for f in "$OUT"/*\ *.wgt; do
      [ -e "$f" ] || continue
      mv "$f" "$OUT/$(basename "${f// /}")"
    done
    # A DEBUG package is named as one, so it can never be uploaded by mistake;
    # a store package must carry no debug hook at all.
    if [ -n "${AW_TV_INSPECT:-}${AW_TV_LIVE:-}" ]; then
      mv "$OUT/ArchiveWatch.wgt" "$OUT/ArchiveWatch-debug.wgt"
      echo "    DEBUG package -> $OUT/ArchiveWatch-debug.wgt (never upload this)"
    elif grep -rqE "target\.js|live-launcher" "$app/.buildResult" 2>/dev/null; then
      echo "  !! a debug hook is inside the store package" >&2; exit 1
    fi
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
