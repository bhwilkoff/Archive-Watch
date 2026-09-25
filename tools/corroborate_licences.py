#!/usr/bin/env python3
"""Find INDEPENDENT evidence for titles kept only on an uploader's licence.

Owner, 2026-09-25: "Unless we have evidence for CC or PD, an uploader's word
is not enough." audit_rights keeps a license_rescues title only when it
carries `rightsCorroborated`; this tool is what sets it. Two sources, neither
the uploader:

  1. Wikidata: an item whose Internet Archive ID (P724) is this archiveID and
     whose copyright licence (P275) is a Creative Commons licence, or whose
     copyright status (P6216) is public domain (Q19652).
  2. shared/editorial/licence_evidence.json — curated {archiveID: {"source":
     url, "note": text}}: a creator's own release page, a festival record.
     Every entry names where the proof is.

Additive: sets `rightsCorroborated` = {"source", "via", "at"}; never removes
one (a lapsed Wikidata statement is a question for a person, not a script).
Reads/writes ./catalog.json.

    python3 tools/corroborate_licences.py [--dry-run]
"""
import datetime as dt, json, sys, time, urllib.parse, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as AR  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog.json"
EVIDENCE = REPO / "shared" / "editorial" / "licence_evidence.json"
SPARQL = "https://query.wikidata.org/sparql"
UA = "ArchiveWatch/1.0 (https://archivewatch.org; rights corroboration)"
QUERY = """SELECT ?ia ?item ?lic ?status WHERE {
  VALUES ?ia { %s }
  ?item wdt:P724 ?ia .
  OPTIONAL { ?item wdt:P275 ?lic . }
  OPTIONAL { ?item wdt:P6216 ?status . }
}"""
PUBLIC_DOMAIN = "http://www.wikidata.org/entity/Q19652"


def wikidata(ids):
    out = {}
    for i in range(0, len(ids), 150):
        chunk = ids[i:i + 150]
        values = " ".join(json.dumps(a) for a in chunk)
        url = SPARQL + "?" + urllib.parse.urlencode({"query": QUERY % values, "format": "json"})
        for attempt in range(3):
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA,
                                                           "Accept": "application/sparql-results+json"})
                rows = json.load(urllib.request.urlopen(req, timeout=90))["results"]["bindings"]
                break
            except Exception as e:  # noqa: BLE001
                print(f"  [wikidata] chunk {i}: {e} (attempt {attempt + 1})", flush=True)
                time.sleep(5 * (attempt + 1))
        else:
            continue
        for r in rows:
            ia, item = r["ia"]["value"], r["item"]["value"]
            lic = r.get("lic", {}).get("value", "")
            status = r.get("status", {}).get("value", "")
            if status == PUBLIC_DOMAIN:
                out[ia] = (item, "wikidata P6216 public domain")
            elif lic:
                out.setdefault(ia, (item, f"wikidata P275 {lic.rsplit('/', 1)[-1]}"))
        time.sleep(1)
    return out


def main():
    dry = "--dry-run" in sys.argv
    cat = json.loads(CATALOG.read_text(encoding="utf-8"))
    targets = [it for it in cat["items"] if not it.get("rightsCorroborated")
               and AR.license_rescues(it.get("archiveLicense"), it.get("year"), it.get("imdbVotes"))]
    curated = json.loads(EVIDENCE.read_text(encoding="utf-8")) if EVIDENCE.exists() else {}
    wd = wikidata([it["archiveID"] for it in targets])
    now = dt.date.today().isoformat()
    n_cur = n_wd = 0
    for it in targets:
        e = curated.get(it["archiveID"])
        if e and e.get("source"):
            it["rightsCorroborated"] = {"source": e["source"], "via": "curated", "at": now}
            n_cur += 1
        elif it["archiveID"] in wd:
            item, why = wd[it["archiveID"]]
            it["rightsCorroborated"] = {"source": item, "via": why, "at": now}
            n_wd += 1
    if (n_cur or n_wd) and not dry:
        CATALOG.write_text(json.dumps(cat, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"[corroborate] {len(targets):,} licence-only titles checked: {n_wd} by Wikidata, "
          f"{n_cur} by curated evidence{' (dry run)' if dry else ''}", flush=True)


if __name__ == "__main__":
    main()
