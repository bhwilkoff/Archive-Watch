#!/usr/bin/env python3
"""
test_audit_rights.py — fast, network-free regression guard for the rights audit
(Decision 027). Verifies the keep/hide bucketing, the licenseurl rescue logic
(esp. the old-style `licenses/publicdomain` URL that must NOT rescue a modern
film), and that build_sqlite + the seed selection actually SKIP excluded items.

Run: python tools/test_audit_rights.py   (exit 0 = pass)
"""
import sys, sqlite3, tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as A
import build_sqlite as B

CC0 = "http://creativecommons.org/publicdomain/zero/1.0/"
PDMARK = "http://creativecommons.org/publicdomain/mark/1.0/"
OLDPD = "http://creativecommons.org/licenses/publicdomain/"   # the substring trap
CCBYSA = "https://creativecommons.org/licenses/by-sa/4.0/"

CASES = [
    # CC0 keeps any year; PD-Mark/old-PD/no-license do NOT rescue a modern film
    ({"archiveID": "a", "title": "Peanuts", "year": 2015, "contentType": "feature-film",
      "rightsStatus": "public_domain", "colorMode": "color", "artworkSource": "tmdb",
      "tmdbID": 1, "archiveLicense": PDMARK, "rightsConfirmed": True}, "modern_copyright_confirmed"),
    ({"archiveID": "a", "title": "Sita", "year": 2008, "contentType": "feature-film",
      "rightsStatus": "public_domain", "archiveLicense": CC0, "rightsConfirmed": True}, "safe_archive_license"),
    ({"archiveID": "a", "title": "CCbysa", "year": 2012, "contentType": "feature-film",
      "rightsStatus": "public_domain", "archiveLicense": CCBYSA, "rightsConfirmed": True}, "safe_archive_license"),
    # the substring trap: old-style licenses/publicdomain must be year-gated
    ({"archiveID": "a", "title": "modern oldPD", "year": 2014, "contentType": "feature-film",
      "rightsStatus": "public_domain", "archiveLicense": OLDPD, "rightsConfirmed": True}, "modern_copyright_confirmed"),
    ({"archiveID": "a", "title": "1972 oldPD", "year": 1972, "contentType": "feature-film",
      "rightsStatus": "public_domain", "archiveLicense": OLDPD, "rightsConfirmed": True}, "safe_archive_license"),
    # year tiers + collections
    ({"archiveID": "a", "title": "NotLD", "year": 1968, "contentType": "feature-film",
      "rightsStatus": "public_domain", "colorMode": "bw"}, "renewal_zone_bw"),
    ({"archiveID": "a", "title": "silent", "year": 1922, "contentType": "silent-film",
      "rightsStatus": "public_domain"}, "safe_pd_age"),
    ({"archiveID": "a", "title": "NASA", "year": 2019, "contentType": "documentary",
      "rightsStatus": "public_domain", "collections": ["nasa"]}, "safe_gov"),
    ({"archiveID": "a", "title": "presumed", "year": 1955, "contentType": "feature-film",
      "rightsStatus": "public_domain"}, "presumed_pd"),
    # modern needs confirm before it can be hidden; bw modern routes to re-date
    ({"archiveID": "a", "title": "unconf", "year": 2011, "contentType": "feature-film",
      "rightsStatus": "public_domain", "colorMode": "color"}, "modern_copyright_unconfirmed"),
    ({"archiveID": "a", "title": "bwunconf", "year": 2011, "contentType": "feature-film",
      "rightsStatus": "public_domain", "colorMode": "bw"}, "wrongmatch_bw"),
    # commercials: own surface
    ({"archiveID": "a", "title": "ad2025", "year": 2025, "contentType": "commercial",
      "rightsStatus": "public_domain"}, "commercial_modern_risk"),
    ({"archiveID": "a", "title": "jeans83", "year": 1983, "contentType": "commercial",
      "rightsStatus": "public_domain"}, "commercial_keep"),
    ({"archiveID": "bandicam-2023-x", "title": "Logos compilation", "year": 1985,
      "contentType": "commercial", "rightsStatus": "public_domain"}, "commercial_slop"),
]


def main():
    fails = 0
    for it, exp in CASES:
        got = A.bucket(it)[0]
        if got != exp:
            fails += 1
            print(f"  FAIL bucket {it['title']!r}: expected {exp}, got {got}")
    print(f"bucket logic: {len(CASES) - fails}/{len(CASES)} pass")

    cat = {"version": 1, "items": [
        {"archiveID": "keep1", "title": "K", "year": 1955, "contentType": "feature-film", "artworkSource": "archive"},
        {"archiveID": "hide1", "title": "H", "year": 2015, "contentType": "feature-film", "artworkSource": "tmdb", "excluded": True},
        {"archiveID": "keep2", "title": "K2", "year": 1960, "contentType": "feature-film", "artworkSource": "archive"},
    ]}
    tmp = Path(tempfile.mktemp(suffix=".sqlite"))
    B.build_db_obj(cat, tmp)
    con = sqlite3.connect(str(tmp))
    ids = sorted(r[0] for r in con.execute("SELECT archiveID FROM items"))
    con.close(); tmp.unlink()
    if ids != ["keep1", "keep2"]:
        fails += 1
        print(f"  FAIL build_sqlite skip: got {ids}")
    else:
        print("build_sqlite excluded-skip: OK")

    seed = sorted(it["archiveID"] for it in B.select_seed_items(cat["items"]))
    if "hide1" in seed:
        fails += 1
        print(f"  FAIL seed skip: {seed}")
    else:
        print("seed excluded-skip: OK")

    print("ALL PASS" if not fails else f"{fails} FAILURES")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
