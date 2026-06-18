#!/bin/sh
# Xcode Cloud — runs after cloning the repo, before building.
#
# Version + build number are managed in AppVersion.xcconfig and bumped on EVERY
# commit (both MARKETING_VERSION and CURRENT_PROJECT_VERSION). Xcode Cloud uses
# those committed values directly — there is nothing to set here.
#
# Available environment variables:
#   CI_WORKSPACE · CI_PRODUCT · CI_BRANCH · CI_BUILD_NUMBER

echo "ci_post_clone: build #${CI_BUILD_NUMBER:-local} on ${CI_BRANCH:-unknown}"
