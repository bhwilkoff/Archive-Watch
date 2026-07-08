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

n=0
max=5
while :; do
  n=$(( n + 1 ))
  if "$@"; then
    [ "$n" -gt 1 ] && echo "succeeded on attempt $n: $*"
    exit 0
  else
    # Capture the command's real exit status HERE, inside the else branch. After
    # `fi`, `$?` would be the compound if's status (0 when the branch isn't taken),
    # not the command's — which would make this exit 0 and mask a stuck upload.
    rc=$?
  fi
  if [ "$n" -ge "$max" ]; then
    echo "::error::command failed after $max attempts (rc=$rc): $*" >&2
    exit "$rc"
  fi
  echo "attempt $n failed (rc=$rc); retrying in $(( n * 5 ))s: $*" >&2
  sleep $(( n * 5 ))
done
