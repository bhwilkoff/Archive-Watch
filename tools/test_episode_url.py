#!/usr/bin/env python3
"""
test_episode_url.py — an episode url must be a URL.

48% of the episodes in the spines carried a raw filename with spaces, which
Python refuses outright and the Roku's Video node cannot open: the episode
appeared in the app and would not play. Films were 0% affected, which is what
kept it invisible. Run:  python tools/test_episode_url.py
"""

from __future__ import annotations

import glob
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
from build_canonical_tv import _safe_url  # noqa: E402

# The characters RFC 3986 does not allow raw in a path segment.
ILLEGAL = re.compile(r'[ "<>\\^`{|}]')
CASES = []


def check(name, got, want):
    CASES.append((name, got == want, got, want))


def main() -> int:
    base = "https://archive.org/download/2-stupid-dogs-season-1/"

    # The reported film. A space is the common case by far.
    got = _safe_url(base + "S01E05 - Pie in the Sky.ia.mp4")
    check("spaces are encoded",
          got, base + "S01E05%20-%20Pie%20in%20the%20Sky.ia.mp4")
    check("the encoded url is legal", bool(ILLEGAL.search(got)), False)

    # IDEMPOTENT. This runs on every spine build, and double-encoding would
    # turn %20 into %2520 and break the urls that already work.
    check("already-encoded is unchanged", _safe_url(got), got)
    check("twice is the same as once", _safe_url(_safe_url(got)), got)

    # A clean url must not be disturbed.
    clean = base + "S01E05.mp4"
    check("a clean url is untouched", _safe_url(clean), clean)

    # Only the FILENAME is encoded — quoting the whole url would destroy the
    # scheme and the host separators.
    check("the scheme survives", _safe_url(base + "a b.mp4").startswith("https://"), True)
    check("the path separators survive",
          _safe_url(base + "a b.mp4").count("/"), clean.count("/"))

    # Degenerate inputs must not raise: this runs inside the spine build.
    check("None passes through", _safe_url(None), None)
    check("empty passes through", _safe_url(""), "")
    check("a bare word passes through", _safe_url("nothing"), "nothing")

    # A '#' or '?' in a FILENAME is part of the name on archive.org, not a
    # fragment or a query, so it must be encoded rather than left to split.
    got = _safe_url(base + "Ep #3.mp4")
    check("a hash in a filename is encoded", "%23" in got, True)

    # And the live corpus: after the repair no spine may carry an illegal url.
    bad = []
    for f in glob.glob(str(REPO / "series" / "*.json")):
        try:
            d = json.loads(Path(f).read_text(encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        for s in d.get("seasons") or []:
            for e in s.get("episodes") or []:
                u = e.get("downloadURL") or ""
                if u and ILLEGAL.search(u):
                    bad.append((Path(f).name, u))
    check(f"no shipped spine carries an illegal url ({len(bad)} found)",
          len(bad), 0)
    for f, u in bad[:3]:
        print(f"      {f}: {u[:90]}")

    fails = [c for c in CASES if not c[1]]
    for name, ok, got, want in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}"
              + ("" if ok else f"\n        got {got!r}, want {want!r}"))
    print(f"\n{len(CASES) - len(fails)}/{len(CASES)} passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
