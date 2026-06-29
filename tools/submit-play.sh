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

( cd android && ./gradlew --quiet bundleRelease )
AAB="android/app/build/outputs/bundle/release/app-release.aab"
[ -f "$AAB" ] || { echo "AAB not produced at $AAB"; exit 1; }
echo "signed AAB: $AAB ($(du -h "$AAB" | cut -f1))"

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
