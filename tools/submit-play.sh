#!/usr/bin/env bash
# Build a signed Android App Bundle and publish it to Google Play from the command line — no Android
# Studio, no manual upload (the Play analog of tools/submit-appstore.sh). Bumps versionCode, builds
# the release AAB with the existing upload key (~/.gradle/gradle.properties), then uploads + releases
# via tools/play-publish.py (Google Play Developer API v3).
#
#   tools/submit-play.sh [--track production|internal|alpha|beta] [--notes "..."] [--rollout 0.1] [--draft] [--no-bump]
#
# One-time setup (the only thing not already in place):
#   A Google Play Developer API service-account JSON key, with release permission for the app granted
#   in Play Console (Users and permissions). Put it at ~/.config/play/archivewatch-play.json (or set
#   PLAY_SERVICE_ACCOUNT_JSON). It belongs in NO git repo.
set -euo pipefail
cd "$(dirname "$0")/.."

TRACK="production"; NOTES=""; ROLLOUT=""; DRAFT=""; BUMP=1
while [ $# -gt 0 ]; do
  case "$1" in
    --track) TRACK="$2"; shift 2;;
    --notes) NOTES="$2"; shift 2;;
    --rollout) ROLLOUT="$2"; shift 2;;
    --draft) DRAFT="--draft"; shift;;
    --no-bump) BUMP=0; shift;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

GRADLE="android/app/build.gradle.kts"
KEY="${PLAY_SERVICE_ACCOUNT_JSON:-$HOME/.config/play/archivewatch-play.json}"
[ -f "$KEY" ] || { echo "Missing service-account JSON at $KEY (see setup notes at top)"; exit 1; }

# Bump versionCode (+1) — Play rejects any previously-uploaded versionCode, even unreleased ones.
if [ "$BUMP" = 1 ]; then
  CUR="$(grep -E '^\s*versionCode\s*=' "$GRADLE" | head -1 | sed -E 's/[^0-9]//g')"
  NEW=$((CUR + 1))
  /usr/bin/sed -i '' -E "s/(versionCode[[:space:]]*=[[:space:]]*)[0-9]+/\1$NEW/" "$GRADLE"
  echo "versionCode $CUR → $NEW"
fi
VN="$(grep -E '^\s*versionName\s*=' "$GRADLE" | head -1 | sed -E 's/.*"(.*)".*/\1/')"
VC="$(grep -E '^\s*versionCode\s*=' "$GRADLE" | head -1 | sed -E 's/[^0-9]//g')"
echo "Building Android $VN (versionCode $VC) …"

# GOOGLE flavor — Play is this flavor's store. The amazon flavor is the
# GMS-free Fire TV build and must never be uploaded here (Decision 047 §6.6).
( cd android && ./gradlew --quiet bundleGoogleRelease )
AAB="android/app/build/outputs/bundle/googleRelease/app-google-release.aab"
[ -f "$AAB" ] || { echo "AAB not produced at $AAB"; exit 1; }
echo "signed AAB: $AAB ($(du -h "$AAB" | cut -f1))"

# ---- RELEASE SMOKE TEST (skip with AW_SKIP_SMOKE=1) --------------------------
# Google Play rejected vc43 for "crashes after opening": R8 removed the no-arg
# constructor of androidx.work.impl.WorkDatabase_Impl, which Room instantiates
# reflectively, so the app died in InitializationProvider on every launch. Only
# the RELEASE build minifies, so every debug install looked perfect and nothing
# in the build or the test suite could see it. The only thing that catches this
# class of defect is running the shipping artifact on a real device — so the
# ship script now does, before it uploads anything.
if [ "${AW_SKIP_SMOKE:-0}" != "1" ]; then
  ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"
  # Try every attached device, not just the first: the first may hold a
  # Play-signed or other-flavour copy of the same package, and installing over
  # it fails (INSTALL_FAILED_UPDATE_INCOMPATIBLE). Picking one device blindly
  # turned a passing smoke test into a failed SHIP.
  SMOKE_SERIAL=""
  for CAND in $("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}'); do
    SMOKE_SERIAL="$CAND"; break
  done
  if [ -z "$SMOKE_SERIAL" ]; then
    echo "SMOKE TEST SKIPPED — no adb device attached."
    echo "  A release build has shipped broken before precisely because nobody ran it."
    echo "  Connect a device, or re-run with AW_SKIP_SMOKE=1 to accept that risk."
    exit 1
  fi
  echo "Smoke-testing the RELEASE build on $SMOKE_SERIAL …"
  ( cd android && ./gradlew --quiet assembleGoogleRelease )
  APK="android/app/build/outputs/apk/google/release/app-google-release.apk"
  [ -f "$APK" ] || { echo "release APK not produced at $APK"; exit 1; }
  INSTALLED=""
  for CAND in $("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}'); do
    if "$ADB" -s "$CAND" install -r "$APK" >/dev/null 2>&1; then
      SMOKE_SERIAL="$CAND"; INSTALLED=1; break
    fi
    echo "  (could not install on $CAND — trying the next device)"
  done
  if [ -z "$INSTALLED" ]; then
    echo "SMOKE TEST FAILED — the release APK would not install on any attached device."
    echo "  A Play-signed or other-flavour copy of com.archivewatch.app is usually the cause:"
    echo "  uninstall it on the test device and retry."
    exit 1
  fi
  echo "  installed on $SMOKE_SERIAL"
  "$ADB" -s "$SMOKE_SERIAL" logcat -c >/dev/null 2>&1
  "$ADB" -s "$SMOKE_SERIAL" shell monkey -p com.archivewatch.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1     || "$ADB" -s "$SMOKE_SERIAL" shell monkey -p com.archivewatch.app -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1
  sleep 14
  CRASHES="$("$ADB" -s "$SMOKE_SERIAL" logcat -d 2>/dev/null | grep -c 'FATAL EXCEPTION' || true)"
  if [ "$CRASHES" != "0" ]; then
    echo "SMOKE TEST FAILED — the release build crashed on launch. NOT uploading."
    "$ADB" -s "$SMOKE_SERIAL" logcat -d 2>/dev/null | grep -A 12 'FATAL EXCEPTION' | head -20
    exit 1
  fi
  RESUMED="$("$ADB" -s "$SMOKE_SERIAL" shell dumpsys activity activities 2>/dev/null | grep -c 'com.archivewatch.app/app.archivewatch.android.MainActivity' || true)"
  [ "$RESUMED" = "0" ] && { echo "SMOKE TEST FAILED — no crash, but the app is not on screen."; exit 1; }
  echo "smoke test PASSED — release build launched, 0 fatal exceptions."
fi
# -----------------------------------------------------------------------------

# Ensure a local venv with the Google API libs (gitignored; keeps system Python clean).
VENV="tools/.play-venv"
if [ ! -x "$VENV/bin/python" ]; then
  echo "Creating $VENV with google-api-python-client + google-auth …"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip google-api-python-client google-auth
fi

ARGS=(--track "$TRACK")
[ -n "$NOTES" ] && ARGS+=(--notes "$NOTES")
[ -n "$ROLLOUT" ] && ARGS+=(--rollout "$ROLLOUT")
[ -n "$DRAFT" ] && ARGS+=("$DRAFT")
PLAY_SERVICE_ACCOUNT_JSON="$KEY" "$VENV/bin/python" tools/play-publish.py "$AAB" "${ARGS[@]}"

echo "✓ Android $VN (versionCode $VC) published to the '$TRACK' track."
