#!/usr/bin/env python3
"""Find films split into two cards ONLY because their copies disagree on color.

The owner sees a duplicate card; the cause is a chroma reading, not the merge
rule. `build_sqlite._same_film` (Decision 040) refuses to merge two copies whose
`colorMode` disagrees, because a B&W original and a color remake of one title
are different works — a guard that is right, and that a bad reading turns into
a duplicate on the shelves.

Report-first, like every other audit here: it names the pairs and emits the
archiveIDs so `classify_color.py --ids-file` can re-measure exactly those and
nothing else. Re-probing a whole 30k catalog to settle 70 items would be the
kind of local archive.org sweep that has stalled the owner's Apple TV before.

  python3 tools/audit_color_disputes.py --db catalog.sqlite --ids-out disputed.txt
"""
import argparse, json, sqlite3, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_sqlite import (_dupe_title_key, _same_film, _color_compatible,   # noqa: E402
                          _colorized_upload, color_confident)

FILM_TYPES = ("feature-film", "tv-special", "feature")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", help="published catalog.sqlite (item_json)")
    ap.add_argument("--catalog", help="catalog.json — what CI already has on disk")
    ap.add_argument("--ids-out")
    args = ap.parse_args()

    if args.catalog:
        cat = json.load(open(args.catalog))
        items = cat["items"] if isinstance(cat, dict) else cat
    elif args.db:
        items = []
        for aid, j in sqlite3.connect(args.db).execute(
                "SELECT archiveID, json FROM item_json"):
            try:
                d = json.loads(j)
            except Exception:
                continue
            d["archiveID"] = aid
            items.append(d)
    else:
        ap.error("pass --catalog or --db")

    clusters = {}
    for it in items:
        if it.get("contentType") not in FILM_TYPES:
            continue
        k = _dupe_title_key(it.get("title"))
        if len(k) >= 4:
            clusters.setdefault(k, []).append(it)

    disputed, stated = [], []
    for group in clusters.values():
        for i in range(len(group)):
            for j in range(i + 1, len(group)):
                a, b = group[i], group[j]
                if _same_film(a, b) or _color_compatible(a, b):
                    continue
                # Would everything ELSE have merged them?
                probe = dict(b); probe["colorMode"] = a.get("colorMode")
                if not _same_film(dict(a), probe):
                    continue
                (stated if (_colorized_upload(a) or _colorized_upload(b))
                 else disputed).append((a, b))

    print(f"{len(disputed) + len(stated)} pairs held apart by color alone")
    print(f"  {len(stated):3} — an upload states it is colorized (the guard is right)")
    print(f"  {len(disputed):3} — no such claim; at least one reading is suspect\n")

    ids = set()
    for a, b in disputed:
        for x in (a, b):
            ids.add(x["archiveID"])
        conf = "".join("C" if color_confident(x) else "?" for x in (a, b))
        print(f"  [{conf}] {(a.get('title') or '')[:34]:34} "
              f"{a['archiveID'][:38]:38} ({a.get('colorMode')}, sat={a.get('colorSat')}) | "
              f"{b['archiveID'][:38]} ({b.get('colorMode')}, sat={b.get('colorSat')})")

    if args.ids_out and ids:
        Path(args.ids_out).write_text("\n".join(sorted(ids)) + "\n")
        print(f"\n{len(ids)} ids -> {args.ids_out}")
        print("re-measure with: python tools/classify_color.py --ids-file "
              f"{args.ids_out} --workers 4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
