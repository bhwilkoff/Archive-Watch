#!/usr/bin/env bash
# apt-get install on a CI runner, retried: one bad answer from Ubuntu's mirror
# (exit 100) failed nine jobs in two workflows on 2026-11-11.
set -uo pipefail
for attempt in 1 2 3 4; do
  if sudo apt-get update -qq && sudo apt-get install -y -qq "$@"; then exit 0; fi
  [ "$attempt" = 4 ] && break
  echo "::warning::apt-get failed (attempt $attempt); retrying"
  sleep $(( attempt * 20 ))
done
echo "::error::apt-get could not install: $*"
exit 1
