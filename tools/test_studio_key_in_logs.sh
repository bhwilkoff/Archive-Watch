#!/bin/bash
# §8.53 — no log line prints a destination URL, because the last path
# component of every platform destination IS the stream key (§5).
#
# THE FAULT: StudioSession logged "[AWSTUDIOSTART] starting engine
# destination=<full URL>" — the complete YouTube stream key — on every
# platform show, found 2026-09-23 reading a real run's log. §8.10's sentinel
# test exercises only the publisher's own paths, so it could never see a
# session line. This is the source-level half: any diag/awdiag/print that
# formats a destination/server/ingest URL's absoluteString fails, unless it
# goes through redactingKey.
#
#   bash tools/test_studio_key_in_logs.sh
#   AW_SOURCE_ROOT=<dir> bash tools/test_studio_key_in_logs.sh   # negative control
set -u
cd "$(dirname "$0")/.."
ROOT=${AW_SOURCE_ROOT:-ArchiveWatch/ArchiveWatch}
hits=$(grep -rnE '(awdiag|diag|print)\(.*(dest|destination|server|ingest|rtmp)[A-Za-z]*(\?|!)?\.absoluteString' \
        "$ROOT/Studio" "$ROOT/macOS" "$ROOT/iOS" "$ROOT/Views" 2>/dev/null | grep -v redactingKey)
# Two-line calls: the format on one line, the argument on the next.
multi=$(grep -rnE -A1 '(awdiag|diag)\(".*destination=' "$ROOT/Studio" "$ROOT/macOS" "$ROOT/iOS" "$ROOT/Views" 2>/dev/null \
        | grep -E 'absoluteString' | grep -v redactingKey)
if [ -n "$hits$multi" ]; then
  echo "FAIL: a log line prints a destination URL (the key is its last path component):"
  printf '%s\n%s\n' "$hits" "$multi" | sed '/^$/d'
  exit 1
fi
echo "PASS: no log line prints a destination URL"
