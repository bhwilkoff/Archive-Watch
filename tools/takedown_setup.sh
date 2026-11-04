#!/usr/bin/env bash
# One-time setup of the private case record (docs/TAKEDOWNS.md). The owner runs
# this: it deploys the Worker. The token is generated here and never printed.
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p "$HOME/.config/archivewatch"
if [ ! -f "$HOME/.config/archivewatch/takedown.env" ]; then
  printf 'TAKEDOWN_TOKEN=%s\n' "$(openssl rand -hex 32)" > "$HOME/.config/archivewatch/takedown.env"
fi
TOKEN=$(sed -n 's/^TAKEDOWN_TOKEN=//p' "$HOME/.config/archivewatch/takedown.env")
printf '%s' "$TOKEN" | gh secret set TAKEDOWN_TOKEN
cd worker
printf '%s' "$TOKEN" | wrangler secret put TAKEDOWN_TOKEN
wrangler d1 execute archivewatch-pulse --remote --file=schema-takedowns.sql
wrangler deploy
cd ..
python3 tools/takedown_cases.py list
echo "Case record is live."
