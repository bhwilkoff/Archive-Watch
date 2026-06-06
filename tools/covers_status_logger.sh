#!/usr/bin/env bash
# covers_status_logger.sh — append a cover-pipeline status snapshot to a log file
# every hour, independent of any agent session (#86). Survives session
# sleep/close; tail it anytime. Stops itself once generation is done.
#
# Launch:
#   nohup ./tools/covers_status_logger.sh > /dev/null 2>&1 &
# Watch:
#   tail -f tools/covers_out/status_history.log
set -u
cd "$(dirname "$0")/.."
LOG="tools/covers_out/status_history.log"
INTERVAL="${STATUS_INTERVAL:-3600}"
mkdir -p tools/covers_out

while true; do
  {
    echo "================ $(date '+%Y-%m-%d %H:%M:%S') ================"
    python3 tools/covers_status.py --plain
    echo ""
  } >> "$LOG" 2>&1
  # stop once the generator is no longer running (final snapshot already written)
  pgrep -f batch_covers.py >/dev/null 2>&1 || { echo "[logger] generator stopped — exiting" >> "$LOG"; break; }
  sleep "$INTERVAL"
done
