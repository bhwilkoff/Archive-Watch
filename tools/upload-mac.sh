#!/usr/bin/env bash
# Submit the macOS app to App Store Connect from the COMMAND LINE — no Xcode GUI / Organizer.
# Archives with a RELEASED Xcode, then exports + uploads in one step via the App Store Connect API.
#
# ── One-time setup ────────────────────────────────────────────────────────────────────────────
# 1) Install a RELEASED Xcode (NOT the beta) — App Review rejects beta-toolchain builds. Point at it:
#       export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
#    (Leave the beta at /Applications/Xcode-beta.app; this script refuses a "*beta*" DEVELOPER_DIR.)
# 2) App Store Connect API key: ASC ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸
#    generate a key (Role: App Manager or Admin). Download AuthKey_<KEYID>.p8 (ONE download only),
#    note the Key ID + Issuer ID, and place the key here:
#       mkdir -p ~/.appstoreconnect/private_keys
#       mv ~/Downloads/AuthKey_<KEYID>.p8 ~/.appstoreconnect/private_keys/
#    Then export the IDs (the .p8 + these belong in NO git repo):
#       export ASC_KEY_ID=XXXXXXXXXX
#       export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# 3) Bump BOTH numbers in AppVersion.xcconfig (Decision 003) — every upload needs a new build number.
#
# ── Run ───────────────────────────────────────────────────────────────────────────────────────
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tools/upload-mac.sh
#
# After it finishes, the build processes in ASC (~5–30 min) — it does NOT auto-submit. Finish in the
# App Store Connect WEB UI (not Xcode): the macOS version ▸ select the build ▸ Submit for Review.
# (To automate that last step too, use fastlane `deliver` or the ASC REST API.)
set -euo pipefail
cd "$(dirname "$0")/.."

# Pick a RELEASED Xcode toolchain (App Review rejects beta builds). Priority: an explicit
# DEVELOPER_DIR; else the xcode-select default if it's a non-beta Xcode; else the newest
# /Applications/Xcode*.app that isn't a beta (so it "just works" wherever `xcodes install 26` put it).
resolve_dev() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then printf '%s\n' "$DEVELOPER_DIR"; return; fi
  local sel; sel="$(xcode-select -p 2>/dev/null)"
  case "$sel" in
    *[Bb]eta*) : ;;
    */Contents/Developer) printf '%s\n' "$sel"; return ;;
  esac
  local app
  for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | grep -iv beta | sort -rV); do
    printf '%s\n' "$app/Contents/Developer"; return
  done
  printf '%s\n' "/Applications/Xcode.app/Contents/Developer"   # fallback; the guard below catches absent/beta
}
DEV="$(resolve_dev)"
export DEVELOPER_DIR="$DEV"

# Load local App Store Connect API credentials if present (gitignored: tools/asc-credentials.env) so
# you don't have to export ASC_KEY_ID / ASC_ISSUER_ID every run. Env vars already set take precedence.
if [ -f "tools/asc-credentials.env" ]; then
  set -a; . "tools/asc-credentials.env"; set +a
fi

# GUARD: never archive with a BETA toolchain — App Review rejects beta-built apps (TestFlight allows
# them). The beta lives at /Applications/Xcode-beta.app, so a "beta" in the path is the reliable tell.
case "$DEV" in
  *[Bb]eta*) echo "REFUSING: DEVELOPER_DIR points at a BETA Xcode ($DEV)."
             echo "App Review rejects beta-toolchain builds. Install a released Xcode and set"
             echo "  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"; exit 1;;
esac
# A released Xcode must actually be installed (the standalone Command Line Tools can't archive apps).
if [ ! -x "$DEV/usr/bin/xcodebuild" ]; then
  echo "No released Xcode found at $DEV."
  echo "Install one first (your Apple ID is needed for the download):  xcodes install 26"
  echo "Then re-run:  tools/upload-mac.sh"; exit 1
fi
XVER="$(/usr/bin/xcodebuild -version | tr '\n' ' ')"
SDKS="$(/usr/bin/xcodebuild -showsdks 2>/dev/null | grep -i 'macos' | head -1 | xargs)"
echo "Toolchain: $XVER | $SDKS | $DEV"

: "${ASC_KEY_ID:?set ASC_KEY_ID (App Store Connect API Key ID)}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID (App Store Connect API Issuer ID)}"
KEY="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$KEY" ] || { echo "Missing API key at $KEY — see setup notes at the top of this script."; exit 1; }

VERSION="$(grep -E '^MARKETING_VERSION'        AppVersion.xcconfig | sed 's/.*= *//')"
BUILD="$(grep   -E '^CURRENT_PROJECT_VERSION'  AppVersion.xcconfig | sed 's/.*= *//')"
echo "Archiving Archive Watch Mac $VERSION ($BUILD)…"

ARCH="build/ArchiveWatchMac.xcarchive"
rm -rf "$ARCH" build/export
# Pass the API key to the ARCHIVE step too — on a fresh Xcode with no signed-in Apple ID,
# -allowProvisioningUpdates needs it to create/download the signing cert + profile (the export
# step needs it as well, below).
xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj -scheme "Archive Watch Mac" \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCH" archive -allowProvisioningUpdates \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$KEY"

echo "Exporting + uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath build/export \
  -exportOptionsPlist ExportOptions-appstore.plist \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  -authenticationKeyPath "$KEY" \
  -allowProvisioningUpdates

echo
echo "✓ Uploaded $VERSION ($BUILD). Now in App Store Connect (web): open the Archive Watch record →"
echo "  macOS version → select build $BUILD → Submit for Review. (Build needs a few min to finish processing.)"
