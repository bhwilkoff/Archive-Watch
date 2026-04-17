#!/bin/sh
# Xcode Cloud — runs after cloning the repo, before building.
# Use this for any pre-build setup (install tools, generate files, etc.)
#
# Available environment variables:
#   CI_WORKSPACE     — path to the cloned repo
#   CI_PRODUCT       — product name
#   CI_BRANCH        — branch being built
#   CI_BUILD_NUMBER  — auto-incrementing build number
#
# Example: auto-increment build number from Xcode Cloud
# cd "$CI_WORKSPACE"
# /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $CI_BUILD_NUMBER" AppName/Info.plist

echo "ci_post_clone: build #${CI_BUILD_NUMBER:-local} on ${CI_BRANCH:-unknown}"
