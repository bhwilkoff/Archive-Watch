#!/usr/bin/env bash
# Retry a load-bearing command against transient failures (network blips,
# GitHub API 5xx) with linear backoff.
#
# Unlike gh_dispatch.sh (a fire-and-forget dispatch that self-heals, so it exits
# 0 even on ultimate failure), this is for operations whose output MUST persist —
# `gh release upload` of a freshly built index/DB. So it retries the transient
# case but still exits non-zero after exhausting retries, so a genuinely-stuck
# publish surfaces as a failed run instead of silently dropping the artifact.
#
# Usage: bash tools/gh_retry.sh <cmd> [args...]
set -uo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: gh_retry.sh <cmd> [args...]" >&2
  exit 2
fi

# A DETERMINISTIC failure must not be retried. `gh release upload` answers
# HTTP 422 "size must be less than 2147483648" when an asset exceeds GitHub's
# 2 GiB limit, and that answer will not change on attempt five — the subtitle
# index burned its whole budget on it nightly while publishing nothing. Retry
# is for blips; a validation error is a fact.
PERMANENT='HTTP 422|Validation Failed|size must be less than|already_exists'

n=0
max=5
while :; do
  n=$(( n + 1 ))
  out=$("$@" 2>&1); rc_run=$?
  printf '%s\n' "$out"
  if [ "$rc_run" -ne 0 ] && printf '%s' "$out" | grep -qE "$PERMANENT"; then
    echo "permanent failure (not retrying): $*" >&2
    exit "$rc_run"
  fi
  if [ "$rc_run" -eq 0 ]; then
    [ "$n" -gt 1 ] && echo "succeeded on attempt $n: $*"
    exit 0
  else
    # The command's real status now comes from rc_run, captured at the call
    # itself. Reading `$?` here would read the `if` test, not the command —
    # which is why it was captured inside this branch before the restructure.
    rc=$rc_run
  fi
  if [ "$n" -ge "$max" ]; then
    echo "::error::command failed after $max attempts (rc=$rc): $*" >&2
    exit "$rc"
  fi
  echo "attempt $n failed (rc=$rc); retrying in $(( n * 5 ))s: $*" >&2
  sleep $(( n * 5 ))
done
