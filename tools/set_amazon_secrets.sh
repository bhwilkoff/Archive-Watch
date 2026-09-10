#!/usr/bin/env bash
# Push the Amazon Appstore client credentials into GitHub Actions secrets.
#
# The values are read straight from ~/.config/amazon/appstore.json and piped to
# `gh secret set` — they are never echoed, never written to a temp file, and
# never reach the transcript. Same pattern as tools/set_reports_key.sh.
#
#   ./tools/set_amazon_secrets.sh
set -euo pipefail
CREDS="$HOME/.config/amazon/appstore.json"
[ -f "$CREDS" ] || { echo "no $CREDS — nothing to push" >&2; exit 1; }
for pair in "AMAZON_CLIENT_ID:client_id" "AMAZON_CLIENT_SECRET:client_secret"; do
  name="${pair%%:*}"; key="${pair##*:}"
  python3 -c "import json,sys;v=json.load(open('$CREDS')).get('$key','');sys.stdout.write(v)" \
    | gh secret set "$name"
  echo "  set $name"
done
echo "done — pulse.yml already passes both through."
