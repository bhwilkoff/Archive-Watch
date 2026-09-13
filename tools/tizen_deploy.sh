#!/usr/bin/env bash
# Build the Samsung .wgt and put it on the real television, in one step.
#
# WHAT A RETAIL TIZEN SET LETS YOU DO, measured on a QN65S90CDFXZA (2023 S90C,
# Tizen 9.0) and worth knowing before planning a verification run:
#
#   sdb connect     ✅   sdb capability  ✅   tizen install  ✅   tizen run  ✅
#   sdb shell       ❌   dlog            ❌   sdb pull       ❌   screenshot ❌
#
# So a build can be DEPLOYED and LAUNCHED from here, and cannot be OBSERVED.
# There is no web inspector either: it needs `sdb shell 0 debug <appid>`, and
# `tizen run` launches with "debug 0" — the CLI has no debug subcommand. That
# rules out the DOM-measurement route that works so well in headless Chrome.
#
# The consequence for how this app is verified: `?tv=1` in a 1920x1080 headless
# Chrome is the instrument (tools/tv_audit_sizes.mjs, tools/tv_follow_focus.mjs,
# and the packaged-origin run in docs/TIZEN-GLASS-FINDINGS.md). The television
# is where a PERSON looks. Deploy here, then ask.
#
# Usage:  bash tools/tizen_deploy.sh [host]        (default 10.0.0.203)
set -euo pipefail

HOST="${1:-10.0.0.203}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/tizen-studio/tools/ide/bin:$HOME/tizen-studio/tools:$PATH"

command -v tizen >/dev/null || { echo "tizen CLI not found (~/tizen-studio)"; exit 1; }

echo "==> build"
bash "$ROOT/tv/build-tv-packages.sh" tizen | grep -E "Version:|Done" || true
WGT="$(ls -t "$ROOT"/tv/dist/*.wgt | head -1)"
[ -n "$WGT" ] || { echo "no .wgt was produced"; exit 1; }

echo "==> connect $HOST"
sdb connect "$HOST" >/dev/null 2>&1 || true
SERIAL="$(sdb devices | awk -v h="$HOST" '$1 ~ h {print $1; exit}')"
[ -n "$SERIAL" ] || {
  echo "TV not reachable at $HOST."
  echo "  Developer Mode times out on these sets: Apps → 12345 → Developer mode ON,"
  echo "  put THIS machine's IP in, and restart the television."
  exit 1
}
echo "    $SERIAL"

echo "==> install $(basename "$WGT")"
tizen install -s "$SERIAL" -n "$(basename "$WGT")" -- "$(dirname "$WGT")" | tail -3

echo "==> run"
tizen run -s "$SERIAL" -p ArchvWatch.ArchiveWatch | tail -2

echo
echo "Deployed. This is as far as tooling reaches — the set exposes no shell,"
echo "no dlog and no screenshot, so what it LOOKS like is a person's job now."
