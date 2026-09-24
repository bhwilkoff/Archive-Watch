#!/usr/bin/env python3
"""The marquee rule is one rule on every platform (2026-09-24).

Swift `Catalog.Item.heroSafeBuckets` / `heroModernYear`, Kotlin
`CatalogDatabase.heroAnd`, and the index builder's `hero_safe` (which the web
and Roku read) must name the same buckets and the same modern year. The web
and Roku had copied only the year half and admitted 46% / 67% more.
Control: a bucket added to one side only must fail.

    python3 tools/test_hero_rule_parity.py
"""
import re, sys
from pathlib import Path
R = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(R / "tools"))
import build_catalog_index as b

swift = (R / "ArchiveWatch/ArchiveWatch/Models/Catalog.swift").read_text()
kt = (R / "android/app/src/main/java/app/archivewatch/android/data/CatalogDatabase.kt").read_text()
sw_b = set(re.findall(r'"(\w+)"', re.search(r"heroSafeBuckets: Set<String> =\s*\[([^\]]*)\]", swift).group(1)))
sw_y = int(re.search(r"static let heroModernYear = (\d+)", swift).group(1))
hero_kt = re.search(r"heroAnd: String get\(\).*?notCommercial", kt, re.S).group(0)
kt_b = set(re.findall(r"'(\w+)'", re.search(r"rightsBucket IN \(([^)]*)\)", hero_kt).group(1)))
kt_y = {int(y) for y in re.findall(r"year >= (\d+)", hero_kt)}
py_b, py_y = set(b.HERO_SAFE_BUCKETS), b.HERO_MODERN_YEAR

import build_sqlite as bs   # Home shelves use the hero's modern-year bar (2026-09-24)

def check(pb, py):
    return pb == sw_b == kt_b == set(bs.SHELF_MODERN_BUCKETS) and py == sw_y == bs.SHELF_MODERN_YEAR \
        and kt_y == {py}

if check(py_b | {"presumed_pd"}, py_y):
    print("CONTROL FAIL: a one-sided bucket did not break parity"); sys.exit(2)
print(f"swift {sorted(sw_b)} {sw_y} | kotlin {sorted(kt_b)} {sorted(kt_y)} | index {sorted(py_b)} {py_y}")
ok = check(py_b, py_y)
# behaviour: the cases the rule exists for
cases = [("safe_pd_age", 1925, True), ("presumed_pd", 1944, False), ("safe_gov", 2025, False),
         ("safe_archive_license", 1950, False), ("safe_cc", 1960, True), (None, 1920, False)]
for bk, y, want in cases:
    got = b.hero_safe(bk, y)
    ok &= got == want
    print(f"  {'ok  ' if got == want else 'FAIL'} hero_safe({bk}, {y}) = {got}")
for y, bk, want in [(1989, "safe_archive_license", False), (2015, "safe_gov", True), (1950, "presumed_pd", True)]:
    bs._rights_bucket = lambda it, _b=bk: _b
    got = bs.shelf_rights_ok({"year": y})
    ok &= got == want
    print(f"  {'ok  ' if got == want else 'FAIL'} shelf_rights_ok({y}, {bk}) = {got}")
print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
