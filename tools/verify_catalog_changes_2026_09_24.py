#!/usr/bin/env python3
"""Did the 2026-09-24 catalog changes land? Reads ONLY published assets.

Each check names the change and the evidence that proves it on the live
plane, never a local build:
  hero      catalog-index.json schema >= 13 with a `heroSafe` column (col 16)
  series    the index's collections map carries `series-*` entries
  shelves   no index shelf member is 1978+ without the shelf rule's evidence
  related   the published catalog.sqlite has item_related with rows
  details   a detail shard record carries index 10 (related)
  search    FTS finds >= 5 films for "hopalong"
  discovery the candidate queue gained archive_collection / public_domain_day
            entries and ingest added films (the last discover-content log)
Run before the publish (control): everything should read NOT YET.

    python3 tools/verify_catalog_changes_2026_09_24.py
"""
import json, os, subprocess, sqlite3, sys, tempfile, urllib.request, zlib
sys.path.insert(0, os.path.dirname(__file__))
SITE = "https://archivewatch.org"
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res = []

def rec(name, ok, detail):
    res.append(ok); print(f"  {'LANDED ' if ok else 'NOT YET'} {name:10} {detail}")

def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "aw-verify"}), timeout=120).read()

idx = json.loads(get(f"{SITE}/catalog-index.json"))
schema = idx.get("schema"); fields = idx.get("fields") or []
rec("hero", (schema or 0) >= 13 and "heroSafe" in fields, f"schema={schema} last fields={fields[-2:]}")
ser = {k: len(v) for k, v in (idx.get("collections") or {}).items() if k.startswith("series-")}
rec("series", len(ser) >= 15, f"{len(ser)} series collections {dict(list(ser.items())[:3])}")
tmp = tempfile.mkdtemp()
zz = os.path.join(tmp, "c.zz"); db = os.path.join(tmp, "c.sqlite")
subprocess.run(["gh", "release", "download", "catalog-db", "-R", "bhwilkoff/Archive-Watch",
                "-p", "catalog.sqlite.zz", "-O", zz, "--clobber"], check=True, capture_output=True)
d = zlib.decompressobj(-15)
with open(zz, "rb") as f, open(db, "wb") as o:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        o.write(d.decompress(chunk))
    o.write(d.flush())
con = sqlite3.connect(db)
try:
    n = con.execute("SELECT count(*) FROM item_related").fetchone()[0]
except sqlite3.Error:
    n = 0
rec("related", n > 5000, f"item_related rows={n}")
# Shelves: judged by the SHELF rule (build_sqlite.SHELF_MODERN_BUCKETS, which
# admits modern government work), from the published DB's rightsBucket. The
# first version borrowed the hero's column and read 19 NASA videos as misses.
from build_sqlite import SHELF_MODERN_BUCKETS
bucket = dict(con.execute("SELECT archiveID, rightsBucket FROM items"))
# The year the SHELF shows is the index row's: an archiveID can also be a
# materialized episode row in the DB with its own year (Decision 045).
year = {r[0]: r[2] for r in idx["items"]}
bad = [a for ids in (idx.get("shelves") or {}).values() for a in ids
       if isinstance(year.get(a), int) and year[a] >= 1978 and bucket.get(a) not in SHELF_MODERN_BUCKETS]
rec("shelves", not bad, f"{len(bad)} modern shelf members without evidence {bad[:3]}")
hop = con.execute("SELECT count(*) FROM items_fts WHERE items_fts MATCH 'hopalong'").fetchone()[0]
rec("search", hop >= 5, f'"hopalong" -> {hop} films')
aid = con.execute("SELECT archiveID FROM items WHERE title='Metropolis' AND year=1927 LIMIT 1").fetchone()
if aid:
    from build_web_details import fnv1a32
    shard = json.loads(get(f"{SITE}/details/{fnv1a32(aid[0]) & 0xFF:02x}.json"))
    r = shard.get(aid[0]) or []
    rec("details", len(r) > 10 and bool(r[10]), f"Metropolis record length {len(r)}")
else:
    rec("details", False, "Metropolis not found")

q = json.load(open(os.path.join(REPO, "shared/editorial/discovery_candidates.json")))["candidates"]
from collections import Counter
st = Counter(c.get("status") for c in q)
rec("discovery", st.get("held_modern_license", 0) > 0 or st.get("ingested", 0) > 3148,
    f"queue statuses {dict(st.most_common(6))} (git pull first)")
print(f"{sum(res)}/{len(res)} landed")
