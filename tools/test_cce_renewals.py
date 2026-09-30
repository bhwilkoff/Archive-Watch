#!/usr/bin/env python3
"""The Catalog of Copyright Entries renewal table: films renewed in print are
found; the public-domain canon (never renewed) is not; the parser reads both
the 1950s section format and the 1970s interleaved one."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import corroborate_copyright as C
import fetch_cce_renewals as F

RENEWED = [("Frankenstein", 1931), ("The Invisible Man", 1933), ("Bride of Frankenstein", 1935),
           ("All Quiet on the Western Front", 1930)]
CANON = [("His Girl Friday", 1940), ("Detour", 1945), ("The Stranger", 1946), ("Meet John Doe", 1941),
         ("D.O.A.", 1949), ("It's a Wonderful Life", 1946), ("Scarlet Street", 1945), ("My Man Godfrey", 1936),
         ("Nothing Sacred", 1937), ("Frankenstein", 1910)]
bad = [f"not found: {t} {y}" for t, y in RENEWED if not C.cce_renewal(t, y)]
bad += [f"false claim: {t} {y}" for t, y in CANON if C.cce_renewal(t, y)]

SAMPLE = """
ALL QUIET ON THE WESTERN FRONT, a
photoplay in fourteen reels by
Universal Pictures Corp.
© 17May30; LP1323. Universal Pic-
tures Co., Inc. (PWH); 26Mar58;
R211372.

The Swordsman. By Columbia Pictures
Corporation. 9 reels. 6 17Dec47; L1354.
Columbia Pictures Industries, Inc. (PWH);
8Jan75; R595026.

NEW FILM, a motion picture. © 3Jan58; LP9999.
"""
got = {(r["t"], r["y"], r["r"]) for r in F.parse(SAMPLE, "x")}
want = {("ALL QUIET ON THE WESTERN FRONT", 1930, "R211372"), ("The Swordsman", 1947, "R595026")}
if got != want:
    bad.append(f"parse: got {got}")
for b in bad:
    print("FAIL", b)
print(f"{'PASS' if not bad else 'FAIL'}: {len(RENEWED)} renewals, {len(CANON)} canon controls, parser")
sys.exit(1 if bad else 0)
