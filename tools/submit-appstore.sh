#!/usr/bin/env bash
# Build + upload an App Store archive for ONE platform from the command line (no Xcode GUI).
#   tools/submit-appstore.sh mac      → "Archive Watch Mac"  / macOS  (.pkg)
#   tools/submit-appstore.sh ios      → "ArchiveWatch"       / iOS+iPadOS (.ipa)
#   tools/submit-appstore.sh tvos     → "ArchiveWatch"       / tvOS   (.ipa)
#   tools/submit-appstore.sh all      → mac, then ios, then tvos
#
# Setup: a RELEASED Xcode (App Review rejects beta builds), the App Store Connect API key in
# tools/asc-credentials.env (gitignored) + ~/.appstoreconnect/private_keys/.
#
# Signing is MANUAL, by design: cloud-managed signing fails for this team's API key
# ("Cloud signing permission error"), but the SAME key can create certs + profiles via the REST
# API. So this script ensures an Apple Distribution cert (+ a Mac Installer cert for macOS) exists,
# creates an App Store provisioning profile per embedded bundle id (tools/asc_profiles.py), writes a
# manual ExportOptions, and exports + uploads. Re-running is safe (profiles are recreated by name).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:?usage: submit-appstore.sh <mac|ios|tvos|all>}"
if [ "$PLATFORM" = "all" ]; then
  for p in mac ios tvos; do "$0" "$p"; done
  exit 0
fi
case "$PLATFORM" in
  mac)  SCHEME="Archive Watch Mac"; DEST="generic/platform=macOS"; PKG=1 ;;
  ios)  SCHEME="ArchiveWatch";      DEST="generic/platform=iOS";   PKG=0 ;;
  tvos) SCHEME="ArchiveWatch";      DEST="generic/platform=tvOS";  PKG=0 ;;
  *) echo "unknown platform '$PLATFORM' (use mac|ios|tvos|all)"; exit 1 ;;
esac

# --- released Xcode (newest non-beta) -----------------------------------------------------------
resolve_dev() {
  if [ -n "${DEVELOPER_DIR:-}" ]; then printf '%s\n' "$DEVELOPER_DIR"; return; fi
  local sel; sel="$(xcode-select -p 2>/dev/null)"
  case "$sel" in *[Bb]eta*) : ;; */Contents/Developer) printf '%s\n' "$sel"; return ;; esac
  local app
  for app in $(ls -d /Applications/Xcode*.app 2>/dev/null | grep -iv beta | sort -rV); do
    printf '%s\n' "$app/Contents/Developer"; return
  done
  printf '%s\n' "/Applications/Xcode.app/Contents/Developer"
}
DEV="$(resolve_dev)"; export DEVELOPER_DIR="$DEV"
case "$DEV" in *[Bb]eta*) echo "REFUSING beta Xcode ($DEV) — App Review rejects beta builds."; exit 1;; esac
[ -x "$DEV/usr/bin/xcodebuild" ] || { echo "No released Xcode at $DEV — run: xcodes install 26"; exit 1; }

# --- credentials --------------------------------------------------------------------------------
[ -f "tools/asc-credentials.env" ] && { set -a; . "tools/asc-credentials.env"; set +a; }
: "${ASC_KEY_ID:?set ASC_KEY_ID}"; : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$KEY" ] || { echo "Missing API key at $KEY"; exit 1; }
TEAM="${ASC_TEAM_ID:-L2G756LY8N}"
AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$KEY")

# --- platform support present? (the device SDK is a separate Xcode component download) -----------
if ! "$DEV/usr/bin/xcodebuild" -showdestinations -project ArchiveWatch/ArchiveWatch.xcodeproj \
      -scheme "$SCHEME" 2>/dev/null | grep -qiE "platform:${PLATFORM/mac/macOS}.*name:Any"; then
  : # best-effort; xcodebuild reports the real "not installed" error if missing
fi
# Metal toolchain (the app has a .metal shader; Xcode ships it as a separate component).
"$DEV/usr/bin/xcrun" --find metal >/dev/null 2>&1 || { echo "Installing Metal toolchain (~700MB)…"; xcodebuild -downloadComponent MetalToolchain; }

VERSION="$(grep -E '^MARKETING_VERSION' AppVersion.xcconfig | sed 's/.*= *//')"
BUILD="$(grep   -E '^CURRENT_PROJECT_VERSION' AppVersion.xcconfig | sed 's/.*= *//')"
echo "[$PLATFORM] $SCHEME $VERSION ($BUILD) | $(/usr/bin/xcodebuild -version | tr '\n' ' ') | $DEV"

ARCH="build/${PLATFORM}.xcarchive"
EXPORT="build/${PLATFORM}-export"
rm -rf "$ARCH" "$EXPORT"

echo "[$PLATFORM] archiving…"
xcodebuild -project ArchiveWatch/ArchiveWatch.xcodeproj -scheme "$SCHEME" \
  -configuration Release -destination "$DEST" -archivePath "$ARCH" archive \
  -allowProvisioningUpdates "${AUTH[@]}"

# --- the embedded bundle ids (main app + extensions) --------------------------------------------
APP="$(ls -d "$ARCH"/Products/Applications/*.app 2>/dev/null | head -1)"
[ -n "$APP" ] || { echo "no .app in $ARCH"; exit 1; }
BIDS=$(find "$APP" -name Info.plist 2>/dev/null | while read -r p; do
  /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$p" 2>/dev/null; done | grep archivewatch | sort -u)
echo "[$PLATFORM] bundle ids: $(echo "$BIDS" | tr '\n' ' ')"

# --- the Apple Distribution cert id (manual signing needs it; create if absent) -----------------
DIST_CERT_ID="$(python3 tools/asc_certs.py distribution)"
[ -n "$DIST_CERT_ID" ] || { echo "could not resolve/create Apple Distribution cert"; exit 1; }
if [ "$PKG" = 1 ]; then python3 tools/asc_certs.py mac_installer >/dev/null; fi

# --- App Store profiles for every bundle id, then a manual ExportOptions -------------------------
PJSON="$(python3 tools/asc_profiles.py "$PLATFORM" "$DIST_CERT_ID" $BIDS)"
PLIST="$EXPORT-ExportOptions.plist"; mkdir -p "$(dirname "$PLIST")"
INSTALLER=""
[ "$PKG" = 1 ] && INSTALLER="  <key>installerSigningCertificate</key><string>3rd Party Mac Developer Installer: Learning is Change, Inc. ($TEAM)</string>"
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
  echo '<plist version="1.0"><dict>'
  echo '  <key>method</key><string>app-store-connect</string>'
  echo '  <key>destination</key><string>upload</string>'
  echo "  <key>teamID</key><string>$TEAM</string>"
  echo '  <key>signingStyle</key><string>manual</string>'
  echo "  <key>signingCertificate</key><string>Apple Distribution: Learning is Change, Inc. ($TEAM)</string>"
  echo "$INSTALLER"
  echo '  <key>manageAppVersionAndBuildNumber</key><false/>'
  echo '  <key>provisioningProfiles</key><dict>'
  echo "$PJSON" | python3 -c "import json,sys
for k,v in json.load(sys.stdin).items(): print(f'    <key>{k}</key><string>{v}</string>')"
  echo '  </dict>'
  echo '</dict></plist>'
} > "$PLIST"

echo "[$PLATFORM] exporting + uploading to App Store Connect…"
xcodebuild -exportArchive -archivePath "$ARCH" -exportPath "$EXPORT" \
  -exportOptionsPlist "$PLIST" -allowProvisioningUpdates "${AUTH[@]}"

echo "✓ [$PLATFORM] uploaded $VERSION ($BUILD). In App Store Connect: select build $BUILD for the"
echo "  $PLATFORM platform on the Archive Watch record → Submit for Review (build processes for a few min)."
