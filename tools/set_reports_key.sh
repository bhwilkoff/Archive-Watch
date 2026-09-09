#!/usr/bin/env bash
# set_reports_key.sh — finish wiring the App Store downloads reader.
#
# Downloads come from ASC's salesReports endpoint, which needs a key with the
# "Sales and Reports" role. App Store Connect says on its own key page that a
# key "can't be modified to access more services once created", so the release
# key (App Manager) can never gain it — and widening the key that ships builds
# so a dashboard can read a download count would be the wrong trade. Hence a
# SECOND, narrower key that can do nothing but read reports.
#
#   1. App Store Connect -> Users and Access -> Integrations -> App Store
#      Connect API -> Team Keys -> +
#      Name: "Reports - Pulse"      Access: Sales and Reports   (that ONE role)
#   2. Download the .p8 when it offers. Apple offers it ONCE.
#   3. Run this with the path to it:
#
#        tools/set_reports_key.sh ~/Downloads/AuthKey_XXXXXXXXXX.p8
#
# It sets ASC_REPORTS_KEY_ID and ASC_REPORTS_KEY_P8 as repo secrets, verifies
# the key can actually pull a report, and never prints the key.
set -euo pipefail

P8="${1:-}"
[ -f "$P8" ] || { echo "usage: $0 /path/to/AuthKey_XXXXXXXXXX.p8"; exit 1; }

KID="$(basename "$P8" | sed -E 's/^AuthKey_(.+)\.p8$/\1/')"
[ "$KID" != "$(basename "$P8")" ] || { echo "that filename does not look like AuthKey_<KEYID>.p8"; exit 1; }

base64 < "$P8" | tr -d '\n' | gh secret set ASC_REPORTS_KEY_P8
printf '%s' "$KID" | gh secret set ASC_REPORTS_KEY_ID
echo "set ASC_REPORTS_KEY_ID ($KID) and ASC_REPORTS_KEY_P8"

echo "verifying it can read a report…"
set -a; . tools/asc-credentials.env 2>/dev/null || true; set +a
ASC_REPORTS_KEY_ID="$KID" \
ASC_REPORTS_KEY_P8="$(base64 < "$P8" | tr -d '\n')" \
ASC_VENDOR_NUMBER="${ASC_VENDOR_NUMBER:-85339427}" \
  "${PY:-$HOME/.venvs/aw/bin/python}" tools/pulse_collect.py --only apple_downloads

echo
echo "If that line reads 'ok', the Downloads panel fills on the next Pulse run:"
echo "  gh workflow run pulse.yml"
