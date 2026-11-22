#!/bin/bash
# Run a command with the Android upload-key signing from the login Keychain, never from a file left on disk
# or from plaintext in ~/.gradle/gradle.properties (docs/SECRETS-PLAN.md). The keystore is written to a private
# temporary directory and the four gradle properties android/app/build.gradle.kts reads (UPLOAD_KEYSTORE_PATH,
# UPLOAD_KEYSTORE_PASSWORD, UPLOAD_KEY_ALIAS, UPLOAD_KEY_PASSWORD) are exported as ORG_GRADLE_PROJECT_* for that
# one command; the directory is removed when it ends.
#   tools/with_signing.sh sh -c 'cd android && ./gradlew bundleGoogleRelease'
# Items: UPLOAD_KEYSTORE (tools/secrets.sh keychain-import-file), UPLOAD_STORE_PASSWORD, UPLOAD_KEY_PASSWORD and
# UPLOAD_KEY_ALIAS (tools/secrets.sh keychain-import-gradle). In CI the workflow writes its own gradle properties and
# nothing is read here.
set -euo pipefail
[ $# -gt 0 ] || { echo "usage: tools/with_signing.sh COMMAND [ARGS...]" >&2; exit 2; }
if [ -n "${ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PATH:-}" ] || [ -n "${CI:-}" ]; then exec "$@"; fi
item() { security find-generic-password -a archivewatch -s "archivewatch:$1" -w 2>/dev/null; }
kc() { local n i out=""; n="$(item "$1")" || return 1; [[ "$n" =~ ^[0-9]+$ ]] || return 1
       for ((i = 0; i < n; i++)); do out+="$(item "$1.$i")" || return 1; done; printf '%s' "$out"; }
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
chmod 700 "$dir"
kc UPLOAD_KEYSTORE | base64 -d > "$dir/upload.jks" || true
[ -s "$dir/upload.jks" ] || { echo "with_signing.sh: UPLOAD_KEYSTORE is not in the Keychain (tools/secrets.sh keychain-import-file UPLOAD_KEYSTORE FILE)" >&2; exit 1; }
chmod 600 "$dir/upload.jks"
export ORG_GRADLE_PROJECT_UPLOAD_KEYSTORE_PATH="$dir/upload.jks"
for pair in UPLOAD_STORE_PASSWORD:UPLOAD_KEYSTORE_PASSWORD UPLOAD_KEY_PASSWORD:UPLOAD_KEY_PASSWORD UPLOAD_KEY_ALIAS:UPLOAD_KEY_ALIAS; do
  v="$(kc "${pair%%:*}" | base64 -d)" && [ -n "$v" ] || { echo "with_signing.sh: ${pair%%:*} is not in the Keychain (tools/secrets.sh keychain-import-gradle)" >&2; exit 1; }
  export "ORG_GRADLE_PROJECT_${pair##*:}=$v"
done
"$@"
