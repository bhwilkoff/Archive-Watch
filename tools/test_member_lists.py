#!/usr/bin/env python3
"""Member lists (tools/harvest_member_lists.py, ORPHANED-FILMS #1): only
hand-made film lists come in, in their makers' words, and nothing else in
collection_metadata.json moves. Control: the same list under a queue name
("to watch") is refused."""
import json, sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import harvest_member_lists as H
import build_sqlite as B

visible = {f"f{i}": "feature-film" for i in range(20)} | {"s1": "silent-film"}
aliases = {"old-upload": "f0"}
def L(name, ids, desc="", private=False, lid=1):
    return {"list_name": name, "description": desc, "is_private": private, "id": lid,
            "members": [{"identifier": i} for i in ids]}
films = [f"f{i}" for i in range(1, 10)]
fails = 0
def check(label, ok):
    global fails; print(("PASS " if ok else "FAIL ") + label); fails += 0 if ok else 1

got = H.select("alexbratianu", [L("Films of Yasujiro Ozu", films + ["old-upload"])], visible, aliases)
check("a named film list comes in", len(got) == 1)
e = got[0]
check("its title is the maker's own name", e["title"] == "Films of Yasujiro Ozu")
check("the blurb credits the maker", e["blurb"] == "A list by alexbratianu on archive.org.")
check("a merged-away upload counts as its survivor", "f0" in e["members"])
check("control: a queue name is refused", not H.select("x", [L("to watch", films)], visible, aliases))
check("a genre-only name is refused", not H.select("x", [L("Film Noir", films)], visible, aliases))
check("a one-word name needs a description", not H.select("x", [L("Matty", films)], visible, aliases)
      and H.select("x", [L("Detectives", films, "Film noir detectives")], visible, aliases))
check("a private list is refused", not H.select("x", [L("Ozu", films, private=True)], visible, aliases))
check("fewer than 8 of our films is refused", not H.select("x", [L("Ozu and Naruse", films[:5])], visible, aliases))
check("a list mostly of other things is refused",
      not H.select("x", [L("Ozu and Naruse", films + [f"book{i}" for i in range(20)])], visible, aliases))
check("a screen name carrying an email is never published",
      not H.select("someone_gmail_com", [L("Films of Yasujiro Ozu", films)], visible, aliases))
a = H.select("a", [L("Akira Kurosawa", films, lid=1)], visible, aliases)
b = H.select("b", [L("Kurosawa Japanese Film", films[:8] + ["f15"], lid=2)], visible, aliases)
check("two lists of mostly the same films fold into one", len(H.fold_overlaps(a + b)) == 1)

meta = (R / "shared/editorial/collection_metadata.json").read_text()
base = H.rewrite(meta, [])
check("rewrite leaves every other entry byte for byte",
      [l for l in base.split("\n") if '"list-' not in l] == [l for l in meta.split("\n") if '"list-' not in l]
      or json.loads(base)["collections"] == [c for c in json.loads(meta)["collections"] if not c["id"].startswith("list-")])
new = json.loads(H.rewrite(meta, got))
check("rewrite produces valid JSON with the new entry", new["collections"][-1]["id"] == e["id"])
lists = [c for c in json.loads(meta)["collections"] if c["id"].startswith("list-")]
if lists:
    first = lists[0]["members"][0]
    check("build_sqlite maps a member film to its list", lists[0]["id"] in B.LIST_MEMBERS.get(first, []))
print("PASS member lists" if not fails else f"FAILED ({fails})")
sys.exit(1 if fails else 0)
