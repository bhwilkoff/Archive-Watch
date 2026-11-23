#!/usr/bin/env python3
"""attempt_ledger.py — remember every failed attempt, so no scheduled job retries it blindly.

Owner, 2026-11-23: "fix the re-scan of the exact same failures. We should never
build something that does that."

What prompted it: stock-index scanned ~2,360 films four times a day and the same
~2,354 came back "no shots" every run; color-classify took the top 1,200 targets
three times a day and the same ~1,195 came back "unreadable". Neither tool wrote
the failure down, so the next run's selection — popularity-first, "not done
yet" — picked exactly the same head again. A failure that is not recorded is a
failure that is scheduled to repeat.

The rule every per-item scheduled tool follows:

  * Record EVERY attempt's outcome: the item, what happened (indexed, no_shots,
    unreadable, error ...), why, how many times, when, and under which tool
    version.
  * A failed item waits before it is tried again, and the wait grows:
    BACKOFF_DAYS after the 1st, 2nd, 3rd failure. After MAX_ATTEMPTS failures
    it is CAPPED: reported in the run summary, never retried.
  * Bumping the tool's version constant reopens every recorded failure ONCE,
    because a fixed bug deserves a retry of what it broke. The count restarts
    under the new version, so a still-failing item backs off again.

Records are plain dicts so each tool can keep them where its data already lives
(a SQLite table in a published index, a field on a catalog item):

    {"outcome": "no_shots", "reason": "...", "attempts": 2,
     "at": "2026-11-23T21:00:00Z", "v": 2}
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

BACKOFF_DAYS = (1, 7, 30)
MAX_ATTEMPTS = len(BACKOFF_DAYS) + 1     # the 4th failure is the last
SUCCESS = frozenset({"indexed", "classified", "ok"})

ELIGIBLE, BACKOFF, CAPPED = "eligible", "backoff", "capped"


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _iso(t: datetime) -> str:
    return t.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse(s) -> datetime | None:
    try:
        return datetime.strptime(str(s), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (TypeError, ValueError):
        return None


def status(rec: dict | None, now: datetime, version) -> str:
    """ELIGIBLE, BACKOFF (failed recently; wait), or CAPPED (failed too often; report)."""
    if not rec or rec.get("outcome") in SUCCESS:
        return ELIGIBLE
    if rec.get("v") != version:          # the tool changed since: one fresh try
        return ELIGIBLE
    n = int(rec.get("attempts") or 0)
    if n <= 0:
        return ELIGIBLE
    if n >= MAX_ATTEMPTS:
        return CAPPED
    at = _parse(rec.get("at"))
    if at is None:
        return ELIGIBLE
    wait = timedelta(days=BACKOFF_DAYS[min(n, len(BACKOFF_DAYS)) - 1])
    return BACKOFF if now - at < wait else ELIGIBLE


def record(prev: dict | None, outcome: str, reason: str, now: datetime, version) -> dict:
    """The new record after one attempt. Failures count up within a version;
    a success, or a new version, starts the count again."""
    prior = 0
    if (prev and prev.get("v") == version and prev.get("outcome") not in SUCCESS
            and outcome not in SUCCESS):
        prior = int(prev.get("attempts") or 0)
    return {"outcome": outcome, "reason": (reason or "")[:200],
            "attempts": prior + 1, "at": _iso(now), "v": version}


def partition(pairs, now: datetime, version):
    """Split (key, record) pairs into (eligible keys, backoff keys, capped keys), order kept."""
    out = {ELIGIBLE: [], BACKOFF: [], CAPPED: []}
    for key, rec in pairs:
        out[status(rec, now, version)].append(key)
    return out[ELIGIBLE], out[BACKOFF], out[CAPPED]


def summary(tag: str, eligible: int, backoff: int, capped_ids: list, done_already: int = 0) -> str:
    """One line for the run log, with backoff and capped counted SEPARATELY from new work."""
    line = (f"[{tag}] selection: {eligible} eligible, {backoff} skipped (backoff), "
            f"{len(capped_ids)} capped (failed {MAX_ATTEMPTS}x; reported, not retried)")
    if done_already:
        line += f", {done_already} already done"
    if capped_ids:
        shown = ", ".join(str(c) for c in capped_ids[:10])
        line += f"\n[{tag}] capped: {shown}" + (" ..." if len(capped_ids) > 10 else "")
    return line
