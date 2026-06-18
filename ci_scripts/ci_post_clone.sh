#!/bin/sh
# Xcode Cloud — runs after cloning the repo, before building.
#
# Available environment variables:
#   CI_WORKSPACE     — path to the cloned repo
#   CI_PRODUCT       — product name
#   CI_BRANCH        — branch being built
#   CI_BUILD_NUMBER  — Xcode Cloud's own monotonic build counter

echo "ci_post_clone: build #${CI_BUILD_NUMBER:-local} on ${CI_BRANCH:-unknown}"

# --- Auto-increment the app build number --------------------------------------
# Every Xcode Cloud archive / TestFlight upload needs a UNIQUE, increasing
# CFBundleVersion or App Store Connect won't take it — this is why new
# submissions were being skipped: the committed CURRENT_PROJECT_VERSION was
# static, so successive builds shared one build number. Derive it automatically
# from the git commit count: monotonic, already in the hundreds (far above any
# hand-set build), and it grows with every commit to main. Falls back to
# 1000 + CI_BUILD_NUMBER if the clone has no usable history. Runs only in CI
# (CI_WORKSPACE set); local Xcode builds keep the committed value.
if [ -n "$CI_WORKSPACE" ]; then
  cd "$CI_WORKSPACE" || exit 0
  # Xcode Cloud may shallow-clone; deepen so the commit count is real.
  git fetch --unshallow --quiet 2>/dev/null || git fetch --deepen=5000 --quiet 2>/dev/null || true
  COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
  FALLBACK=$((1000 + ${CI_BUILD_NUMBER:-0}))
  if [ "${COUNT:-0}" -ge 100 ]; then BUILD="$COUNT"; else BUILD="$FALLBACK"; fi

  XC="AppVersion.xcconfig"
  if [ -f "$XC" ]; then
    sed -i.bak -E "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${BUILD}/" "$XC"
    rm -f "${XC}.bak"
    echo "ci_post_clone: set CURRENT_PROJECT_VERSION = ${BUILD} (commit count ${COUNT})"
  else
    echo "ci_post_clone: WARNING — $XC not found; build number not updated"
  fi
fi
