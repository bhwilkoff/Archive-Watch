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
        # §3.2a: canonical is the URL Pages SERVES (trailing slash) — the
        # no-slash form 301s, and a canonical that redirects is ignored.
        check("canonical is the served url, with its slash",
              '<link rel="canonical" href="https://archivewatch.org/item/suddenly/">' in h,
              True)
        check("og:url is the share url, not the hash route",
              '<meta property="og:url" content="https://archivewatch.org/item/suddenly/">' in h,
              True)
        # THE DEFECT: a forwarding page is a redirect to the site root to
        # Google, which runs scripts; no page was ever indexed. No script at
        # all, so no counter either (privacy unchanged).
        check("no forward", "location.replace" in h, False)
        check("no executable script", "<script>" in h, False)
        check("a Watch now into the viewer",
              'href="https://archivewatch.org/#/item/suddenly">Watch now</a>' in h, True)
        check("schema.org Movie JSON-LD", '"@type":"Movie"' in h, True)
        check("app banner keeps the no-slash argument the apps parse",
              "app-argument=https://archivewatch.org/item/suddenly\"" in h, True)
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

        # The full Detail, from a details record (the shape build_web_details
        # writes, trailing nulls trimmed).
        det = td / "det"
        det.mkdir()
        (det / "00.json").write_text(json.dumps({"suddenly": [
            "u", "A town is held hostage.", "Lewis Allen",
            [["Frank Sinatra", None, 1], ["Sterling Hayden", None, 2]],
            ["Crime", "Drama"], 4620, None, None,
            {"r": 4, "v": 10, "f": 1, "rv": [[5, "Great", "Tense <b>noir</b>.", "fan", "2011-02-19"]]},
            {"w": "Richard Sale", "ct": "Suddenly!", "ss": "tmdb", "tg": "The town that lived in terror"},
            ["thin_item", "nope_not_in_index"]]}), encoding="utf-8")
        r2 = subprocess.run(
            [sys.executable, str(REPO / "tools" / "build_share_pages.py"),
             "--out", str(td / "site2"), "--index", str(idx), "--details", str(det)],
            capture_output=True, text=True)
        check("build with details succeeds", r2.returncode, 0)
        hf = (td / "site2" / "item" / "suddenly" / "index.html").read_text(encoding="utf-8")
        for label, frag in (("full synopsis", "A town is held hostage."),
                            ("synopsis source named as the viewer names it", "Synopsis from TMDb"),
                            ("tagline", "The town that lived in terror"),
                            ("cast", "<span>Sterling Hayden</span>"),
                            ("director first in cast & crew", "Lewis Allen <span class=\"m\">Director</span>"),
                            ("writer", "<dd>Richard Sale</dd>"),
                            ("genres", "<li>Crime</li>"),
                            ("runtime", "77 min"),
                            ("review text, HTML stripped", "Tense noir."),
                            ("related film linked to its own page", 'href="https://archivewatch.org/item/thin_item/"')):
            check(f"page carries the {label}", frag in hf, True)
        check("a related id not in the index is not linked", "nope_not_in_index" in hf, False)
        # "Suddenly!" folds to the same key as "Suddenly", so no also-known-as.
        check("also-known-as folds like the viewer", "Also known as" in hf, False)
        sm = (td / "site2" / "sitemap.xml").read_text(encoding="utf-8")
        check("sitemap index names its files", "sitemap-1.xml" in sm, True)
        s1 = (td / "site2" / "sitemap-1.xml").read_text(encoding="utf-8")
        check("sitemap lists every film page", s1.count("/item/") + s1.count("/series/"), 3)
        check("sitemap lists the A-Z directory", "https://archivewatch.org/films/" in s1, True)
        check("sitemap uses the served url", "https://archivewatch.org/item/suddenly/</loc>" in s1, True)

        epi = td / "epi.json"
        epi.write_text(json.dumps({"fields": ["archiveID", "slug", "series", "season", "episode", "title", "still", "year"],
            "episodes": [["show_s1e2", "the-show", "The Show", 1, 2, "The Second One", None, 1955],
                         ["show_s1e1", "the-show", "The Show", 1, 1, "The Pilot", None, 1955]]}), encoding="utf-8")
        r3 = subprocess.run(
            [sys.executable, str(REPO / "tools" / "build_share_pages.py"),
             "--out", str(td / "site3"), "--index", str(idx), "--details", str(td / "nodetails"),
             "--episodes", str(epi)], capture_output=True, text=True)
        hs3 = (td / "site3" / "series" / "the-show" / "index.html").read_text(encoding="utf-8")
        check("series page lists its episodes in order",
              hs3.find("S1E1 · The Pilot") < hs3.find("S1E2 · The Second One") and "S1E1 · The Pilot" in hs3, True)
        check("an episode opens in the viewer", 'href="https://archivewatch.org/#/item/show_s1e1"' in hs3, True)

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
