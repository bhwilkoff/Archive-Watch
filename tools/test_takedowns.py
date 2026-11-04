#!/usr/bin/env python3
"""A removal request hides whatever it names and keeps it hidden (Decision 175).

A listed item leaves as a card and as every episode or file served from it; a
listed file leaves alone; a listed show leaves whole. Unlisted neighbors are
the controls. Run: python3 tools/test_takedowns.py
"""
import json, sys, tempfile
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R
import audit_rights as A
import takedown_lib as T

tmp = Path(tempfile.mkdtemp())
(tmp / "shared/editorial").mkdir(parents=True)
(tmp / "series").mkdir()
T.path(tmp).write_text(json.dumps({
    "_how": "ignored",
    "asked-to-remove": {"date": "2026-09-26", "case": "TD-TEST0001"},
    "whole-upload": {"date": "2026-09-26", "case": "TD-TEST0002"},
    "bundle@s1e02": {"date": "2026-09-26", "case": "TD-TEST0003"},
    "series:gone-show": {"date": "2026-09-26", "case": "TD-TEST0004"},
    "only-source": {"date": "2026-09-26", "case": "TD-TEST0005"}}))

def ep(aid, source=None):
    return {"archiveID": aid, "sourceID": source, "title": aid}

def spine(slug, eps, **kw):
    (tmp / f"series/{slug}.json").write_text(json.dumps(
        {"seriesID": slug, "episodesCount": len(eps),
         "seasons": [{"seasonNumber": 1, "episodes": eps}], **kw}))

spine("mixed", [ep("whole-upload@e01", "whole-upload"), ep("whole-upload@e02", "whole-upload"),
                ep("bundle@s1e01", "bundle"), ep("bundle@s1e02", "bundle"), ep("kept-episode")])
spine("gone-show", [ep("gone-1"), ep("gone-2")])
spine("emptied-show", [ep("only-source@e01", "only-source")])
spine("untouched", [ep("other-1")])

R.REPO = tmp
items = [{"archiveID": "asked-to-remove"}, {"archiveID": "left-alone"},
         {"archiveID": "series:gone-show", "seriesID": "gone-show"},
         {"archiveID": "series:emptied-show", "seriesID": "emptied-show"},
         {"archiveID": "series:mixed", "seriesID": "mixed"},
         {"archiveID": "series:untouched", "seriesID": "untouched"}]
stats = Counter()
R.exclude_takedowns(items, stats)
ok = True
def check(label, cond):
    global ok
    print(("PASS " if cond else "FAIL ") + label); ok &= bool(cond)
by = {i["archiveID"]: i for i in items}
check("the listed film is hidden", by["asked-to-remove"].get("excluded") is True)
check("with the takedown marker", by["asked-to-remove"].get("excludedReason") == "takedown")
check("CONTROL: an unlisted film is untouched", "excluded" not in by["left-alone"])
check("the _how note is not an id", stats["takedown_excluded"] == 3)

left = [e["archiveID"] for s in json.loads((tmp / "series/mixed.json").read_text())["seasons"]
        for e in s["episodes"]]
check("a listed item takes all of its files", not any(a.startswith("whole-upload") for a in left))
check("a listed file goes alone", "bundle@s1e02" not in left and "bundle@s1e01" in left)
check("CONTROL: an unlisted episode stays", "kept-episode" in left)
check("the count follows", json.loads((tmp / "series/mixed.json").read_text())["episodesCount"] == 2)
check("a listed show loses its spine", not (tmp / "series/gone-show.json").exists())
check("and its card", by["series:gone-show"].get("excludedReason") == "takedown")
check("a show with nothing left loses its spine", not (tmp / "series/emptied-show.json").exists())
check("and its card", by["series:emptied-show"].get("excludedReason") == "takedown")
check("CONTROL: a show that keeps episodes keeps its card", "excluded" not in by["series:mixed"])
check("CONTROL: an unrelated show is untouched", (tmp / "series/untouched.json").exists()
      and "excluded" not in by["series:untouched"])

spine("gone-show", [ep("gone-1")])
spine("mixed", [ep("bundle@s1e02", "bundle"), ep("kept-episode")])
r = T.strip_spines(repo=tmp)
check("a rebuilt spine cannot bring a removal back", not (tmp / "series/gone-show.json").exists()
      and r["episodes"] == 2)

(tmp / "series/claimed-show.json").write_text(json.dumps(
    {"seriesID": "claimed-show", "sourceID": "claimed-upload", "seasons": []}))
items2 = [{"archiveID": "series:claimed-show", "seriesID": "claimed-show", "excluded": True,
           "copyrightClaimEvidence": {"via": "renewal"}},
          {"archiveID": "claimed-upload"}, {"archiveID": "unrelated-upload"}]
R.exclude_sources_of_claimed_series(items2, Counter())
check("a claim on a show reaches the upload that is the show", items2[1].get("excluded") is True
      and items2[1].get("copyrightClaimFrom") == "series:claimed-show")
check("CONTROL: another upload stays", "excluded" not in items2[2])
spine("yearless-show", [ep("yearless-1")])
(tmp / "catalog.json").write_text(json.dumps({"items": items2 + [
    {"archiveID": "series:untouched", "seriesID": "untouched"},
    {"archiveID": "series:yearless-show", "seriesID": "yearless-show", "excluded": True,
     "rightsAudit": "no_evidence"}]}))
check("a series under a claim is left out of the build", T.drop_hidden_series(tmp) == 1
      and not (tmp / "series/claimed-show.json").exists())
check("CONTROL: a visible series stays in it", (tmp / "series/untouched.json").exists())
check("CONTROL: a card hidden only for want of a year keeps its episodes",
      (tmp / "series/yearless-show.json").exists())

import reconcile_tv_catalog as RC
was = {"archiveID": "series:x", "title": "Old", "excluded": True, "rightsAudit": "copyright_claim",
       "copyrightClaimEvidence": {"via": "RE1"}}
now = RC.with_audit({"archiveID": "series:x", "title": "New"}, was)
check("a rebuilt series keeps the claim the audit found", now.get("copyrightClaimEvidence") == {"via": "RE1"}
      and now.get("excluded") is True and now.get("rightsAudit") == "copyright_claim")
check("and takes everything else from the rebuild", now["title"] == "New")
check("CONTROL: a new series has nothing to keep",
      "excluded" not in RC.with_audit({"archiveID": "series:y"}, None))

src = Path(A.__file__).read_text()
check("the rights reconcile keeps excludedReason (it will not un-hide it)",
      '"excludedReason"' in src.split("FOREIGN = (", 1)[1].split(")", 1)[0])
real = json.loads(T.path().read_text())
check("the public list names no person: only a date and a case number",
      all(set(v) <= {"date", "case"} for k, v in real.items() if not k.startswith("_")))
sys.exit(0 if ok else 1)
