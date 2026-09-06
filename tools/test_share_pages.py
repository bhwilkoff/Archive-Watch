#!/usr/bin/env python3
"""
test_share_pages.py — locks the contract of the share pages.

Every case here is a defect that was actually shipped or nearly shipped while
this was built, so each assertion has a real failure behind it rather than a
hypothetical one. Run:  python tools/test_share_pages.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import build_share_pages as B  # noqa: E402

CASES = []


def check(name, got, want):
    ok = got == want
    CASES.append((name, ok, got, want))
    return ok


def main() -> int:
    # 1. A synopsis here is frequently a quoted review. Clipping it mid-quote
    #    left an opening quotation mark with nothing to close it, and that
    #    dangling quote SHIPPED in the first generated batch.
    q = ('"Three gunmen, who have been hired to assassinate the President, '
         'hold a family hostage while waiting for their target. Interesting '
         'B film which focuses on a psychopathic killer well-portrayed '
         'against type by Frank Sinatra." - noir expert Spencer Selby')
    assert len(q) > 220, "the fixture must be long enough to be CLIPPED"
    clipped = B.clip(q, 180)
    assert clipped.count('"') <= 1, "the fixture must clip INSIDE the quote"
    check("clipped mid-quote drops the orphan opener",
          clipped.startswith('"'), False)
    check("clipping keeps the sentence, minus the opener",
          clipped.startswith("Three gunmen"), True)
    check("a whole balanced quote keeps both marks",
          B.clip('"Short and closed."', 180), '"Short and closed."')
    check("unquoted text is untouched",
          B.clip("Plain synopsis.", 180), "Plain synopsis.")
    check("smart quotes balance too",
          B.balance_quotes("“Open only").startswith("“"), False)

    # 2. Records in details/*.json have TRAILING NULLS TRIMMED, so a sparse
    #    film yields a SHORT list. An unguarded positional read raises
    #    IndexError, which would kill the whole build for one thin item.
    check("at() tolerates a trimmed record", B.at(["url"], B.D_BACKDROP), None)
    check("at() tolerates a missing record", B.at(None, 1), None)
    check("at() reads a present field", B.at([0, "syn"], B.D_SYNOPSIS), "syn")

    # 3. An archiveID becomes a directory name.
    check("refuses traversal", B.safe_segment("../../etc"), None)
    check("refuses a bare dotfile", B.safe_segment(".git"), None)
    check("accepts a normal id", B.safe_segment("suddenly"), "suddenly")

    # 4. Build a real page and assert its shape. The CSS was moved to a shared
    #    stylesheet by a patch that SILENTLY DID NOT APPLY — leaving bare CSS
    #    text in the head under an orphan </style> — so the absence of an
    #    inline style block is asserted, not assumed.
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        idx = td / "index.json"
        idx.write_text(json.dumps({"items": [
            # A full row, and a THIN one with no year, poster or director.
            ["suddenly", "Suddenly", 1954, "feature-film", "http://x/p.jpg",
             1, "", None, 1, 0, 68, 7583, "Lewis Allen", "Drama", "b"],
            ["thin_item", "Thin", None, "ephemeral", None],
            ["series:the-show", "The Show", 1955, "tv-series", "http://x/s.jpg"],
        ]}), encoding="utf-8")
        r = subprocess.run(
            [sys.executable, str(REPO / "tools" / "build_share_pages.py"),
             "--out", str(td / "site"), "--index", str(idx),
             "--details", str(td / "nodetails")],
            capture_output=True, text=True)
        check("build succeeds with a thin record", r.returncode, 0)

        page = (td / "site" / "item" / "suddenly" / "index.html")
        check("item page exists", page.exists(), True)
        h = page.read_text(encoding="utf-8") if page.exists() else ""
        check("no inline style block", "<style" in h or "</style>" in h, False)
        check("links the shared stylesheet", 'href="/share.css"' in h, True)
        check("shared stylesheet is written",
              (td / "site" / "share.css").exists(), True)
        check("canonical url has no #",
              '<link rel="canonical" href="https://archivewatch.org/item/suddenly">' in h,
              True)
        check("og:url is the share url, not the hash route",
              '<meta property="og:url" content="https://archivewatch.org/item/suddenly">' in h,
              True)
        check("forwards to the hash route",
              'location.replace("https://archivewatch.org/#/item/suddenly")' in h,
              True)
        check("carries the iOS app banner", "apple-itunes-app" in h, True)
        # A 2:3 poster inside a wide card is letterboxed by every platform.
        check("poster-only film uses the small card",
              'name="twitter:card" content="summary"' in h, True)

        thin = td / "site" / "item" / "thin_item" / "index.html"
        check("thin item still gets a page", thin.exists(), True)
        ht = thin.read_text(encoding="utf-8") if thin.exists() else ""
        check("no image tags when there is no art",
              "og:image" in ht, False)
        check("thin item still has a description",
              'property="og:description"' in ht, True)

        ser = td / "site" / "series" / "the-show" / "index.html"
        check("series page exists at /series/<slug>", ser.exists(), True)
        hs = ser.read_text(encoding="utf-8") if ser.exists() else ""
        check("series declares a tv_show type",
              'content="video.tv_show"' in hs, True)

    bad = [c for c in CASES if not c[1]]
    for name, ok, got, want in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}"
              + ("" if ok else f"\n        got {got!r}, want {want!r}"))
    print(f"\n{len(CASES) - len(bad)}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
