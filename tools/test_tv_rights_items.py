#!/usr/bin/env python3
"""
test_tv_rights_items.py — the TV audit judges an EPISODE by its own year.

audit_tv_rights skipped a whole spine when the show began before 1978, so a
1992 Saturday Night Live episode under the 1975 spine was never judged and
reached an Apple TV search (2026-09-28). Run:  python tools/test_tv_rights_items.py
"""
from __future__ import annotations
import json
import sys
import tempfile
from pathlib import Path
REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import audit_tv_rights as T  # noqa: E402
import audit_rights as AR  # noqa: E402

GOV = sorted(AR.GOV)[0]
SPINE = {"title": "Sketch Show", "yearStart": 1975, "seasons": [{"episodes": [
    {"archiveID": "sketch-1992", "title": "S18E06", "year": 1992},
    {"archiveID": "sketch-1976", "title": "S01E10", "year": 1976},
    {"archiveID": "sketch-1985-gov", "title": "Newsreel", "year": 1985},
    {"archiveID": "sketch-undated", "title": "S02E01", "year": None},
]}]}
CACHE = {
    "sketch-1992": {"ok": True, "licenseurl": "", "rights": "", "collections": ["television"], "year": 1992},
    "sketch-1985-gov": {"ok": True, "licenseurl": "", "rights": "", "collections": [GOV], "year": 1985},
}


def run(episode_years: bool):
    with tempfile.TemporaryDirectory() as tmp:
        (Path(tmp) / "sketch-show-1975.json").write_text(json.dumps(SPINE))
        spines = T.load_spines(Path(tmp))
    need, title_years = T.collect_need(spines, episode_years=episode_years)
    drop, _, _ = T.judge(need, title_years, CACHE)
    return need, drop


CASES = []
def check(name, got, want): CASES.append((name, got == want, got, want))


def main() -> int:
    need, drop = run(True)
    check("a 1992 episode under a 1975 show is REMOVED", "sketch-1992" in drop, True)
    check("its 1976 episode is kept with no fetch requested", "sketch-1976" in need, False)
    check("a 1985 episode in a government collection is kept",
          "sketch-1985-gov" in need and "sketch-1985-gov" not in drop, True)
    check("an undated episode under a pre-1978 show is not fetched", "sketch-undated" in need, False)
    check("an air date stands in for a missing year",
          T.episode_year({"year": None, "airDate": "1983-02-01"}), 1983)

    # CONTROL: the whole-spine skip must fail the first case, or this test
    # cannot tell the fix from the defect.
    _, drop_old = run(False)
    check("CONTROL: the old whole-spine rule removes nothing", len(drop_old), 0)

    bad = [c for c in CASES if not c[1]]
    for n, ok, g, w in CASES:
        print(f"  {'PASS' if ok else 'FAIL'}  {n}" + ("" if ok else f"\n        got {g!r}, want {w!r}"))
    print(f"\n{len(CASES)-len(bad)}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
