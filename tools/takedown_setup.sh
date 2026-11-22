#!/usr/bin/env bash
# One-time setup of the private case record (docs/TAKEDOWNS.md). The owner runs
# this: it creates the table and deploys the Worker. There is no token to set:
# the check authenticates with its GitHub OIDC token (worker/src/github-oidc.js).
set -euo pipefail
cd "$(dirname "$0")/.."
cd worker
wrangler d1 execute archivewatch-pulse --remote --file=schema-takedowns.sql
wrangler deploy
cd ..
python3 tools/takedown_cases.py list
echo "Case record is live."
