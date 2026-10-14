#!/usr/bin/env python3
"""
test_new_arrivals.py — "New to Archive Watch" admits only what arrived, and
only on the marquee's evidence bar (2026-10-14).

Owner: "there are often items that are not fully vetted (somehow sneak through
our filters for PD/dates, etc.)". Measured on the live row: The Palm Beach
Story, The White Cliffs of Dover, The Luck of the Irish and The Loves of Carmen
on `presumed_pd`; a 2009 Prelinger reel on `safe_gov`; and Nosferatu and The
Kid as "new" through the discovery queue's bulk 2026-09-25 stamp.
Run:  python3 tools/test_new_arrivals.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_sqlite as bs  # noqa: E402
from build_catalog_index import hero_safe  # noqa: E402

RECENT = bs.NEW_ARRIVALS_SINCE + "T12:00:00Z"
OLD = "2020-01-01T00:00:00Z"
fails = []


def with_bucket(bucket, **it):
    it.setdefault("archiveID", "t")
    bs._rights_bucket = lambda _it, b=bucket: b
    return bs.NEW_ARRIVALS_SHELF in bs._shelf_ids_for(it)


def case(name, got, want):
    print(f"  {'ok  ' if got == want else 'FAIL'} {name}")
    if got != want:
        fails.append(name)


real_bucket = bs._rights_bucket
case("a 1925 film added this month is new",
     with_bucket("safe_pd_age", year=1925, addedAt=RECENT), True)
case("a 1950 government film added this month is new",
     with_bucket("safe_gov", year=1950, addedAt=RECENT), True)
case("a presumed-PD 1944 studio feature is not (The White Cliffs of Dover)",
     with_bucket("presumed_pd", year=1944, addedAt=RECENT), False)
case("a renewal-zone 1972 feature is not (Twilight People)",
     with_bucket("renewal_zone", year=1972, addedAt=RECENT), False)
case("a 2009 'government' reel is not (a wrong-match year)",
     with_bucket("safe_gov", year=2009, addedAt=RECENT), False)
case("an undated upload is not",
     with_bucket("unknown_year", year=None, addedAt=RECENT), False)
case("control: the same 1925 film added in 2020 is not new",
     with_bucket("safe_pd_age", year=1925, addedAt=OLD), False)
case("a film with no addedAt is not new, whatever the discovery queue says",
     with_bucket("safe_pd_age", year=1922, archiveID="Nosferatu1922VHS"), False)
case("a build that cannot read the audit admits nothing",
     with_bucket(None, year=1925, addedAt=RECENT), False)

# One bar: the row's rule and the marquee's agree on every bucket and year.
buckets = ["safe_pd_age", "safe_gov", "safe_cc", "presumed_pd", "renewal_zone",
           "renewal_zone_bw", "safe_archive_license", "commercial_keep", "unknown_year", None]
years = [None, 1890, 1929, 1950, 1977, 1978, 2009, "1944", "n.d."]
for b in buckets:
    for y in years:
        bs._rights_bucket = lambda _it, b=b: b
        if bs.new_arrival_rights_ok({"year": y}) != hero_safe(b, y):
            case(f"agrees with hero_safe for {b} {y!r}", False, True)
bs._rights_bucket = real_bucket
print("  ok   agrees with hero_safe on", len(buckets) * len(years), "bucket/year pairs"
      if not any(f.startswith("agrees") for f in fails) else "")

print("FAIL" if fails else "PASS", f"{len(fails)} failing")
sys.exit(1 if fails else 0)
