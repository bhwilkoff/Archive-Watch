"""Harvest the Old Time Radio Researchers' episode logs (otrr.org's public JSON
endpoint, found in its own site JS; robots.txt allows all): 3,918 programs with
logs, 219,203 log rows (MEASURED 2026-10-17, docs/research/radio/03 §0).

Each log row names the archive.org identifier and file that play it, so this is
the bridge from a broadcast to its recordings, and the people credited. FACTS
only: the `plots` and `infos` fields are mostly RadioGOLDINdex's prose ("[G
Plot]") and are not kept. Resumable; 1.5 s between requests.
"""
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
import ia_lib as ia

OT = "https://www.otrr.org/php/jqSelectM7.php"
UA = "Mozilla/5.0 ArchiveWatch-RadioCatalog (catalog build; credits OTRR)"
DELAY = 1.5


def q(**params):
    d = ia.get(OT, params, ua=UA, timeout=180)
    time.sleep(DELAY)
    return d


def title(t):
    m = re.match(r"^(.*), (The|A|An)$", (t or "").strip())
    return f"{m.group(2)} {m.group(1)}" if m else (t or "").strip() or None


def slim(row):
    files = []
    for f in (row.get("files") or "").split("`"):
        p = f.split("|")
        if len(p) >= 5 and p[0].startswith("archive.org"):
            files.append({"archive_id": p[1], "file": p[2], "seconds": p[3], "bytes": p[4]})
    people = []
    for x in (row.get("people") or "").split("`"):
        p = x.split("|")
        if len(p) >= 5 and p[0]:
            people.append({"id": p[0], "name": " ".join(s for s in (p[1], p[2]) if s).strip(), "role": p[4] or "cast"})
    return {"eid": row.get("eid"), "idp": row.get("idp"), "program": row.get("pTitle"),
            "date": row.get("date") if row.get("date", "").startswith(("19", "20")) and "-00" not in row.get("date", "") else None,
            "epnum": row.get("epnum") or None, "title": title(row.get("etitle")),
            "exists": row.get("exists") == "1", "files": files, "people": people}


def main():
    out = os.path.join(ia.CACHE, "otrr")
    os.makedirs(os.path.join(out, "programs"), exist_ok=True)
    progs = q(qid="otterlog")
    if not progs:
        raise SystemExit("otterlog unreadable")
    ia.write_json(os.path.join(out, "otterlog.json"), progs)
    for name in ("certified", "progPedia"):
        path = os.path.join(out, name + ".json.gz")
        if not os.path.exists(path):
            d = q(qid=name)
            if d is None:
                raise SystemExit(f"{name} unreadable")
            ia.write_json(path, d, gz=True)
    failed = []
    for i, p in enumerate(progs):
        path = os.path.join(out, "programs", p["idp"] + ".json.gz")
        if os.path.exists(path) or p.get("nEps") in ("0", None):
            continue
        rows = q(qid="epprogram", pid=p["idp"])
        if rows is None:
            failed.append(p["idp"])
            continue
        ia.write_json(path, {"idp": p["idp"], "program": p["ptitle"], "episodes": [slim(r) for r in rows]}, gz=True)
        if i % 200 == 0:
            print(f"{i}/{len(progs)}", file=sys.stderr, flush=True)
    ia.write_json(os.path.join(out, "failed.json"), failed)
    print(f"{len(progs)} programs; failed {len(failed)}", file=sys.stderr)


if __name__ == "__main__":
    main()
