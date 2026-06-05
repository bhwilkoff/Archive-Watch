#!/usr/bin/env bash
# drain_covers.sh — continuously upload newly-generated covers to archive.org
# while batch_covers.py is still running, then do a final pass (#86).
#
# Resumable + safe to run alongside generation: upload_covers.py skips anything
# already in uploaded.jsonl and tolerates a partial last manifest line.
#
# Credentials come from the environment ONLY (never committed):
#   IAS3_ACCESS_KEY, IAS3_SECRET_KEY
#
# Launch (keys stay in the process env, not on disk):
#   IAS3_ACCESS_KEY=... IAS3_SECRET_KEY=... nohup ./tools/drain_covers.sh \
#       > tools/covers_out/drain.log 2>&1 &
set -u
cd "$(dirname "$0")/.."

: "${IAS3_ACCESS_KEY:?set IAS3_ACCESS_KEY}"
: "${IAS3_SECRET_KEY:?set IAS3_SECRET_KEY}"
ITEM="${1:-archivewatch-covers}"
INTERVAL="${DRAIN_INTERVAL:-300}"

while pgrep -f batch_covers.py >/dev/null 2>&1; do
  echo "[drain] $(date '+%H:%M:%S') upload pass (generation still running)"
  python3 tools/upload_covers.py --item "$ITEM" || true
  sleep "$INTERVAL"
done

echo "[drain] $(date '+%H:%M:%S') generation finished — final upload pass"
python3 tools/upload_covers.py --item "$ITEM" || true
echo "[drain] done"
