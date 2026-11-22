#!/bin/bash
# Run a command with the App Store Connect API key from the login Keychain, never from a file left on disk
# (docs/SECRETS-PLAN.md). The Key ID and Issuer ID are exported, and the .p8 is written to a private temporary
# directory (ASC_KEY_PATH) that is removed when the command ends.
#   tools/with_asc.sh python3 tools/asc_certs.py ...
#   tools/with_asc.sh tools/submit-appstore.sh ...
# In CI the three values are already in the environment from GitHub Actions secrets, and nothing is read here.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: tools/with_asc.sh COMMAND [ARGS...]" >&2; exit 2; }
if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || { [ -z "${ASC_KEY_PATH:-}" ] && [ ! -f "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8" ]; }; then
  item() { security find-generic-password -a archivewatch -s "archivewatch:$1" -w; }
  kc() { local n i out=""; n="$(item "$1")"; for ((i = 0; i < n; i++)); do out+="$(item "$1.$i")"; done; printf '%s' "$out"; }
  dir="$(mktemp -d)"
  trap 'rm -rf "$dir"' EXIT
  chmod 700 "$dir"
  export ASC_KEY_ID="$(kc ASC_KEY_ID | base64 -d)" ASC_ISSUER_ID="$(kc ASC_ISSUER_ID | base64 -d)"
  kc ASC_KEY_P8 | base64 -d > "$dir/AuthKey_$ASC_KEY_ID.p8"
  chmod 600 "$dir/AuthKey_$ASC_KEY_ID.p8"
  export ASC_KEY_PATH="$dir/AuthKey_$ASC_KEY_ID.p8"
  "$@"
else
  exec "$@"
fi
