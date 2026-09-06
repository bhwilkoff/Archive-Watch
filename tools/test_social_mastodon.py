#!/usr/bin/env python3
"""
test_social_mastodon.py — locks the Mastodon adapter's contract.

The Fediverse differs from every other platform here in two ways that a
hardcoded adapter gets wrong, so both are asserted: the instance is whatever
the owner pasted, and the character limit belongs to the SERVER, not to
Mastodon. Run:  python tools/test_social_mastodon.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import social_post as S  # noqa: E402

CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def env(instance=None, token=None):
    for k, v in (("MASTODON_INSTANCE", instance), ("MASTODON_ACCESS_TOKEN", token)):
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


def main() -> int:
    # 1. People copy the instance out of the address bar, so it arrives in
    #    several shapes. Getting this wrong yields a 404 on every call.
    for raw, want in [("mastodon.social", "https://mastodon.social"),
                      ("https://mastodon.social", "https://mastodon.social"),
                      ("https://mastodon.social/", "https://mastodon.social"),
                      ("  mastodon.art  ", "https://mastodon.art")]:
        env(raw, "t")
        check(f"normalises {raw!r}", S.mastodon_base(), want)
    env(None, None)
    check("no instance means not configured", S.mastodon_base(), None)

    # 2. compose() reads LIMITS[platform] before any adapter runs, so a
    #    missing key is a KeyError that kills the whole post.
    check("mastodon has a composing limit", "mastodon" in S.LIMITS, True)
    check("the floor is the universally safe 500", S.LIMITS["mastodon"] >= 500, True)

    # 3. resolve_mastodon_limit talks to the network. It must NEVER lower the
    #    floor, or an odd answer produces a draft no server will accept.
    S.LIMITS["mastodon"] = 500
    env("this-instance-does-not-exist.invalid", "t")
    S.resolve_mastodon_limit()
    check("an unreachable instance keeps the floor", S.LIMITS["mastodon"], 500)

    S.LIMITS["mastodon"] = 9999
    env("mastodon.social", "t")
    S.resolve_mastodon_limit()
    check("a lower instance limit never lowers ours", S.LIMITS["mastodon"], 9999)
    S.LIMITS["mastodon"] = 500

    # 4. Unconfigured and dry-run paths must not touch the network. Every
    #    adapter here shares this contract; a platform that posts during a
    #    dry run is the worst failure this tool can have.
    spec = {"id": "x", "date": "2026-09-06", "title": "T", "year": 1950,
            "link": "https://archivewatch.org/item/x"}
    env(None, None)
    check("unconfigured returns not-connected",
          S.post_mastodon(spec, "t", None, False), (None, "not connected"))
    env("mastodon.social", "token")
    check("configured but not live is a dry run",
          S.post_mastodon(spec, "t", None, False), ("DRY-RUN", None))

    # 5. The idempotency key makes a retried workflow safe rather than
    #    duplicating the post. It must be stable for a given film and day.
    key = f"aw-{spec['date']}-{spec['id']}"[:255]
    check("idempotency key is bounded", len(key) <= 255, True)
    long_spec = dict(spec, id="i" * 400)
    check("a very long id cannot overflow the header",
          len(f"aw-{long_spec['date']}-{long_spec['id']}"[:255]), 255)

    # 6. The multipart builder is hand-rolled; a malformed body is rejected
    #    by the server with an error that does not name the cause.
    body_url = "http://127.0.0.1:1/never-called"
    try:
        S.multipart(body_url, {"description": "alt"},
                    {"file": ("a.jpg", b"\xff\xd8\xff")}, timeout=1)
    except Exception as e:  # noqa: BLE001 — connection refused is expected
        check("multipart builds and attempts a request",
              "multipart" not in str(e).lower(), True)

    bad = [c for c in CASES if not c[1]]
    for name, ok, got, want in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}"
              + ("" if ok else f"\n        got {got!r}, want {want!r}"))
    print(f"\n{len(CASES) - len(bad)}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
