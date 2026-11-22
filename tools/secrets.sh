#!/bin/bash
# The only way an agent or the owner touches a secret value for Archive Watch
# (docs/SECRETS-PLAN.md; owner 2026-11-22: "I do not want to set or keep track of keys and
# passwords for this repo."). Fixed recipes and fixed names only, so an exact permission rule can
# allow it. A value is never echoed, never put on a command line, and never written to a file: it
# moves from where it is kept (a downloaded file, the login Keychain) through a pipe into the one
# place that uses it (the Keychain, a GitHub Actions secret).
#
#   tools/secrets.sh list                          names only, from GitHub Actions, the Worker and the Keychain
#   tools/secrets.sh keychain-import-file NAME FILE [--delete]
#                                                  a credential file into the login Keychain (archivewatch:NAME), checked
#                                                  byte for byte; --delete removes the file after (the owner approves it)
#                                                  NAME: PLAY_SERVICE_ACCOUNT_JSON AMAZON_APPSTORE_JSON UPLOAD_KEYSTORE
#                                                  ROKU_SIGNING_ENV ROKU_SIGNING_KEY ROKU_GENKEY_RAW PULSE_INGEST_ENV
#                                                  SUBTITLE_KEYS_ENV TIZEN_AUTHOR_P12 TIZEN_DISTRIBUTOR_P12
#   tools/secrets.sh keychain-import-asc [P8] [ISSUER_ID] [--delete]
#                                                  the ASC API key into the Keychain (ASC_KEY_P8, ASC_KEY_ID from the file
#                                                  name, ASC_ISSUER_ID from the argument or tools/asc-credentials.env)
#   tools/secrets.sh renew-signing                 mint new CI distribution AND Mac installer certificates (they share
#                                                  APPLE_P12_PASSWORD) and set the four GitHub secrets
#   tools/secrets.sh drop-takedown-token           delete the retired TAKEDOWN_TOKEN from GitHub and the Worker (Decision 186)
#
# Anything else is refused before any command runs. Keychain items are chunked (a `security -i`
# line holds about 2.6 KB): NAME holds the chunk count, NAME.0 ... hold base64 pieces.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="bhwilkoff/Archive-Watch"
KC_ACCOUNT="archivewatch"
KC_PREFIX="archivewatch:"
CHUNK=2000
FILE_NAMES=(PLAY_SERVICE_ACCOUNT_JSON AMAZON_APPSTORE_JSON UPLOAD_KEYSTORE ROKU_SIGNING_ENV ROKU_SIGNING_KEY ROKU_GENKEY_RAW PULSE_INGEST_ENV SUBTITLE_KEYS_ENV TIZEN_AUTHOR_P12 TIZEN_DISTRIBUTOR_P12)

die() { echo "secrets.sh: $*" >&2; exit 2; }
in_list() { local x=$1; shift; local n; for n in "$@"; do [ "$n" = "$x" ] && return 0; done; return 1; }
# worker/ has no package.json, so pin a wrangler new enough to read the keyring login (4.152+);
# an unpinned npx fell back to a cached 4.80 that asks for CLOUDFLARE_API_TOKEN (2026-11-22).
wrangler() { (cd "$ROOT/worker" && npx --yes wrangler@4.152.0 "$@"); }

kc_item_get() { security find-generic-password -a "$KC_ACCOUNT" -s "$KC_PREFIX$1" -w; }

# Prints the base64 of a stored value to stdout: call it only inside a pipe or $(...), never bare.
kc_get() {
  local n i out=""
  n="$(kc_item_get "$1")"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  for ((i = 0; i < n; i++)); do out+="$(kc_item_get "$1.$i")"; done
  printf '%s' "$out"
}

kc_item_put() {
  [[ "$2" =~ ^[A-Za-z0-9+/=_.-]+$ ]] || die "refusing to store $1: not a single token"
  printf 'add-generic-password -U -a %s -s %s -w %s\n' "$KC_ACCOUNT" "$KC_PREFIX$1" "$2" | security -i >/dev/null
}

# Stores the base64 on stdin as chunks through `security -i`, which reads the command on stdin, so the value
# is never on a command line (ps).
kc_put() {
  local v n=0 i old
  IFS= read -r v || true
  [ -n "$v" ] || die "refusing to store $1: empty"
  old="$(kc_item_get "$1" 2>/dev/null || true)"
  while [ -n "$v" ]; do
    kc_item_put "$1.$n" "${v:0:$CHUNK}"
    v="${v:$CHUNK}"
    n=$((n + 1))
  done
  kc_item_put "$1" "$n"
  if [[ "$old" =~ ^[0-9]+$ ]]; then
    for ((i = n; i < old; i++)); do security delete-generic-password -a "$KC_ACCOUNT" -s "$KC_PREFIX$1.$i" >/dev/null 2>&1 || true; done
  fi
}

b64() { base64 < "$1" | tr -d '\n'; }

recipe="${1:-}"
[ $# -gt 0 ] && shift

case "$recipe" in
  list)
    [ $# -eq 0 ] || die "list takes no arguments"
    echo "GitHub Actions ($REPO):"
    gh secret list --repo "$REPO" --json name --jq '.[].name' | sed 's/^/  /'
    echo "Cloudflare Worker (archivewatch-pulse):"
    wrangler secret list --format json | python3 -c 'import json,sys; [print("  " + s["name"]) for s in json.load(sys.stdin)]'
    echo "login Keychain ($KC_PREFIX*):"
    security dump-keychain 2>/dev/null | sed -n "s/.*\"svce\"<blob>=\"$KC_PREFIX\([A-Za-z0-9_]*\)\".*/  \1/p" | sort -u
    ;;

  keychain-import-file)
    delete=0 args=()
    for a in "$@"; do if [ "$a" = "--delete" ]; then delete=1; else args+=("$a"); fi; done
    [ ${#args[@]} -eq 2 ] || die "keychain-import-file takes a name and a file"
    in_list "${args[0]}" "${FILE_NAMES[@]}" || die "keychain-import-file takes only: ${FILE_NAMES[*]}"
    f="${args[1]}"
    [ -f "$f" ] && [ ! -L "$f" ] || die "not a regular file: $f"
    b64 "$f" | kc_put "${args[0]}"
    cmp -s <(kc_get "${args[0]}") <(b64 "$f") || die "the Keychain copy does not match the file; the file is kept"
    echo "${args[0]} is in the Keychain, and matches the file byte for byte"
    if [ "$delete" = 1 ]; then rm -f -- "$f"; echo "the file is deleted"; else echo "the file is kept (--delete removes it)"; fi
    ;;

  keychain-import-asc)
    delete=0 p8="" issuer=""
    for a in "$@"; do
      case "$a" in
        --delete) delete=1 ;;
        *.p8) p8="$a" ;;
        *) [[ "$a" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die "not an issuer id or a .p8: an argument"
           issuer="$a" ;;
      esac
    done
    if [ -z "$p8" ]; then
      shopt -s nullglob
      found=("$HOME"/.appstoreconnect/private_keys/AuthKey_*.p8)
      [ ${#found[@]} -eq 1 ] || die "found ${#found[@]} AuthKey_*.p8 files; name the one to import"
      p8="${found[0]}"
    fi
    if [ -z "$issuer" ] && [ -f "$ROOT/tools/asc-credentials.env" ]; then
      issuer="$(sed -n 's/^\(export \)\{0,1\}ASC_ISSUER_ID=//p' "$ROOT/tools/asc-credentials.env" | head -1 | tr -d "\"' ")"
      [[ "$issuer" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || issuer=""
    fi
    [ -f "$p8" ] && [ ! -L "$p8" ] || die "not a regular file: $p8"
    kid="$(basename "$p8")"
    [[ "$kid" =~ ^AuthKey_([A-Z0-9]{10})\.p8$ ]] || die "the file is not named AuthKey_<KEYID>.p8"
    kid="${BASH_REMATCH[1]}"
    b64 "$p8" | kc_put ASC_KEY_P8
    printf '%s' "$kid" | base64 | tr -d '\n' | kc_put ASC_KEY_ID
    [ -n "$issuer" ] && { printf '%s' "$issuer" | base64 | tr -d '\n' | kc_put ASC_ISSUER_ID; }
    cmp -s <(kc_get ASC_KEY_P8) <(b64 "$p8") || die "the Keychain copy does not match the file; the file is kept"
    echo "ASC_KEY_P8 and ASC_KEY_ID are in the Keychain${issuer:+, and ASC_ISSUER_ID}"
    if [ "$delete" = 1 ]; then rm -f -- "$p8"; echo "the .p8 file is deleted"; else echo "the .p8 file is kept (--delete removes it)"; fi
    ;;

  renew-signing)
    [ $# -eq 0 ] || die "renew-signing takes no arguments: both certificates share one password"
    dir="$(mktemp -d)"
    trap 'rm -rf "$dir"' EXIT
    pw="$(openssl rand -hex 24)"
    for kind in distribution mac_installer; do
      (cd "$dir" && ASC_KEY_P8="$(kc_get ASC_KEY_P8)" ASC_KEY_ID="$(kc_get ASC_KEY_ID | base64 -d)" ASC_ISSUER_ID="$(kc_get ASC_ISSUER_ID | base64 -d)" \
        P12_PASSWORD="$pw" python3 "$ROOT/tools/ci_make_signing_p12.py" "$kind" "$dir/$kind.p12" - > "$dir/$kind.out")
    done
    read -r dist_id _ < "$dir/distribution.out"
    b64 "$dir/distribution.p12" | gh secret set APPLE_DIST_P12 --repo "$REPO"
    b64 "$dir/mac_installer.p12" | gh secret set APPLE_INSTALLER_P12 --repo "$REPO"
    printf '%s' "$pw" | gh secret set APPLE_P12_PASSWORD --repo "$REPO"
    printf '%s' "$dist_id" | gh secret set APPLE_DIST_CERT_ID --repo "$REPO"
    echo "APPLE_DIST_P12, APPLE_INSTALLER_P12, APPLE_P12_PASSWORD and APPLE_DIST_CERT_ID are set; prune old certificates with tools/asc_prune_certs.py"
    ;;

  drop-takedown-token)
    [ $# -eq 0 ] || die "drop-takedown-token takes no arguments"
    ok=0
    if gh secret delete TAKEDOWN_TOKEN --repo "$REPO" 2>/dev/null; then echo "TAKEDOWN_TOKEN deleted from GitHub Actions"
    elif ! gh secret list --repo "$REPO" | grep -q '^TAKEDOWN_TOKEN'; then echo "TAKEDOWN_TOKEN was already gone from GitHub Actions"
    else echo "FAILED: TAKEDOWN_TOKEN is still in GitHub Actions" >&2; ok=1; fi
    if printf 'y\n' | wrangler secret delete TAKEDOWN_TOKEN >/dev/null 2>&1; then echo "TAKEDOWN_TOKEN deleted from the Worker"
    elif ! wrangler secret list --format json 2>/dev/null | grep -q '"TAKEDOWN_TOKEN"'; then echo "TAKEDOWN_TOKEN was already gone from the Worker"
    else echo "FAILED: TAKEDOWN_TOKEN is still on the Worker (is wrangler logged in?)" >&2; ok=1; fi
    exit $ok
    ;;

  *)
    die "unknown recipe; one of: list, keychain-import-file, keychain-import-asc, renew-signing, drop-takedown-token"
    ;;
esac
