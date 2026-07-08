#!/usr/bin/env bash
# Retry a `gh workflow run` dispatch against transient GitHub API errors.
#
# Why: the dispatch API intermittently returns HTTP 500/502/503. Under a job's
# `bash -e`, a bare `gh workflow run X.yml` on such a blip fails the ENTIRE run
# even though all real work already committed/published (this nuked a
# fully-successful discover-content run on 2026-07-08, GitHub run 28921808254).
#
# A failed dispatch is NON-FATAL: every catalog-writer pipeline is idempotent
# and publish-db.yml also runs on its own daily schedule, so the next scheduled
# run re-dispatches. So we retry with backoff, and if it still can't dispatch we
# warn loudly and exit 0 rather than failing an otherwise-clean run.
#
# Usage: bash tools/gh_dispatch.sh <workflow.yml> [extra gh workflow run args...]
set -uo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: gh_dispatch.sh <workflow.yml> [args...]" >&2
  exit 2
fi

wf="$1"
for attempt in 1 2 3 4 5; do
  if gh workflow run "$@"; then
    echo "dispatched $wf (attempt $attempt)"
    exit 0
  fi
  echo "dispatch of $wf failed (attempt $attempt); retrying…" >&2
  sleep $(( attempt * 5 ))
done

echo "::warning::could not dispatch $wf after 5 attempts (transient GitHub API error); it self-heals on the next scheduled run"
exit 0
