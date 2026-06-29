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

DEV="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR="$DEV"

# GUARD: never archive with a BETA toolchain — App Review rejects beta-built apps (TestFlight allows
# them). The beta lives at /Applications/Xcode-beta.app, so a "beta" in the path is the reliable tell.
case "$DEV" in
  *[Bb]eta*) echo "REFUSING: DEVELOPER_DIR points at a BETA Xcode ($DEV)."
             echo "App Review rejects beta-toolchain builds. Install a released Xcode and set"
             echo "  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer"; exit 1;;
esac
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
xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj -scheme "Archive Watch Mac" \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCH" archive -allowProvisioningUpdates

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
