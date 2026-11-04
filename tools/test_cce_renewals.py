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
           ("All Quiet on the Western Front", 1930), ("Flash Gordon", 1936), ("Batman", 1943), ("Jungle Jim", 1937),
           ("Spy Smasher", 1942), ("The Phantom", 1943), ("Laura", 1944)]
CANON = [("His Girl Friday", 1940), ("Detour", 1945), ("The Stranger", 1946), ("Meet John Doe", 1941),
         ("D.O.A.", 1949), ("It's a Wonderful Life", 1946), ("Scarlet Street", 1945), ("My Man Godfrey", 1936),
         ("Nothing Sacred", 1937), ("Frankenstein", 1910), ("Charade", 1963), ("Night of the Living Dead", 1968),
         ("A Star Is Born", 1937), ("Gulliver's Travels", 1939), ("Terror by Night", 1946), ("The Woman in Green", 1945)]
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
# Printed as they are in the volumes, OCR and all (Decision 179).
SERIAL = """
THE ADVENTURES OF FRANK MERRIWELL, a
series of photoplays by Universal
Productions. 2 reels each, © Uni-
versal Pictures Co., Inc. (PWH)
Between savage foes. © 27Feb36;

LP6166. 30Jan64; R331016. .

The crash in the chasm. © 13Mar36;

LP6208. 27Feb64; R332765. .
Imprisoned in a dungeon. © 4Mar36;
LP6184, 27Feb64; R332763.


AFTER THE THIN MAN, a photoplay in
twelve reels by Metro-Goldwyn-Mayer
Corp. ©21Dec36; 16821. Metro-Gold-
wyn-Mayer, Inc. (PWH); 27Dec63;
R328940.


KANSAS CYCLONE, a photoplay in six reels by Republic Productions. © 24Junt1; L10615.
Repix, Inc. (PWH); 29May69; R460000.


THE SECRET CODE, a series of photoplays
by Columbia Pictures Corp. 2 reels
each (no.1, 3 reels) © Columbia
Pictures Industries, Inc. (PWH)

Chap. no.
1. Enemy passport.
2h Aug70; R490023.
5. Wireless warning. © 20ctH2;
L11625. 21Sep70; R494658.
6. Flaming oil. © 90ct42; 111626.
21Sep70; R494659.


FIERY DANGER. See
LOST CITY OF THE JUNGLE. 5.


SPY SMASHER, a series of photoplays by
Republic Productions. 2 reels
each (no.1, 3 reels) © Repix, Inc. (PWH)

Chap. no.
1-6. © 4Apr}2; 111235. 23May69;
R462316.


THE IRON CLAW. See
SPY SMASHER. Chap. no.3.


PARAMOUNT NEWS, a series of motion pictures by Paramount.
© Paramount Pictures Corp. (PWH)
506. © 30Oct36; MP6936. 28Sep64; R345642.


FOLIES PARISIENNE, a photoplay in two
reels by Universal Pictures Co.
© 9Apr40O; LP9529. Universal Pictures, Inc. (PWH); 2May67; R408977.
THEY HAD TO SEE PARIS, a photoplay in ten reels by Fox Film Corp.
© 11Sep29; L675. Twentieth Century-Fox Film Corp. (PWH); 5Nov56; R179928.
"""
rows = F.parse(SERIAL, "x")
by = {(r["t"].upper(), r.get("s", "").upper()): r for r in rows}
SEEN = [("BETWEEN SAVAGE FOES", "THE ADVENTURES OF FRANK MERRIWELL", 1936, "R331016"),
        ("THE CRASH IN THE CHASM", "THE ADVENTURES OF FRANK MERRIWELL", 1936, "R332765"),
        ("IMPRISONED IN A DUNGEON", "THE ADVENTURES OF FRANK MERRIWELL", 1936, "R332763"),
        ("AFTER THE THIN MAN", "", 1936, "R328940"),
        ("KANSAS CYCLONE", "", 1941, "R460000"),       # "24Junt1"
        ("ENEMY PASSPORT", "THE SECRET CODE", 1942, "R490023"),         # its date lost, and the header's only chapter
        ("WIRELESS WARNING", "THE SECRET CODE", 1942, "R494658"),       # "20ctH2"
        ("FLAMING OIL", "THE SECRET CODE", 1942, "R494659"),            # "90ct42"
        ("SPY SMASHER", "SPY SMASHER", 1942, "R462316"),                # "4Apr}2"
        ("THE IRON CLAW", "SPY SMASHER", 1942, "R462316"),              # named only by its cross-reference
        ("FOLIES PARISIENNE", "", 1940, "R408977"),                     # "9Apr40O"
        ("THEY HAD TO SEE PARIS", "", 1929, "R179928")]
for t, sr, y, r in SEEN:
    got = by.get((t, sr))
    if not got or (got["y"], got["r"]) != (y, r):
        bad.append(f"serial parse: {t} / {sr}: {got}")
if by.get(("FLAMING OIL", "THE SECRET CODE"), {}).get("sr") != 1:
    bad.append("a series of photoplays must read as a serial")
if by.get(("PARAMOUNT NEWS", "PARAMOUNT NEWS"), {}).get("sr"):
    bad.append("a newsreel's numbered issues are not one work")
# The renewal date fixes a year OCR ruined, and overrules one it misread.
d = lambda s: F.DATE.search(s)
for raw, renewed, want in [("4Junt0", (1968, 6, 19), 1940), ("2Oct4O", (1970, 9, 21), 1942), ("16Ju145", (1971, 5, 27), 1943),
                           ("31Mar59", (1966, 12, 8), 1939), ("8Dec39", (1966, 12, 7), 1939)]:
    got = F.original_year(d(raw), renewed)[0]
    if got != want:
        bad.append(f"year {raw} renewed {renewed}: {got}, want {want}")

C._CCE = {}
for r in rows + [{"t": "THE RAVEN", "y": 1942, "reg": "M1", "r": "R1", "rl": 1, "vol": "x"},
                 {"t": "A MOTH", "y": 1941, "reg": "L1", "r": "R2", "rl": 7, "vol": "x"},
                 {"t": "Chapter 1", "s": "BATMAN", "ch": "1", "sr": 1, "y": 1943, "r": "R3", "reg": "", "vol": "x"},
                 {"t": "The electrical brain", "s": "BATMAN", "ch": "1", "sr": 1, "y": 1943, "r": "R4", "reg": "", "vol": "x"}]:
    C._CCE.setdefault(C.norm_title(r.get("s") or r["t"]), []).append(r)
    if r.get("s"):
        C._CCE.setdefault("\0" + C.norm_title(r["s"]), []).append(r)
CASES = [("Spy Smasher", 1942, None, None, True), ("Spy Smasher", 1944, None, None, False),
         ("The Secret Code", 1942, None, None, True),
         ("Secret Code", 1918, None, None, False),                # same name, another year
         ("Wireless Warning", 1942, None, None, False),           # a chapter's name is not a film of that name
         ("The Iron Claw", 1942, None, None, False),
         ("Paramount News", 1936, None, None, False),             # a renewed issue says nothing of the rest
         ("The Raven", 1942, 92, "feature-film", False),          # Le Corbeau is not the one-reel The Raven
         ("The Raven", 1942, 9, "animation", True),
         ("A Moth", 1941, 7, "animation", False),                 # a cartoon is not a piece of a photoplay
         ("A Moth", 1941, 12, "feature-film", True)]              # a fragment of the film still is the film
for t, y, m, k, want in CASES:
    if bool(C.cce_renewal(t, y, m, k)) != want:
        bad.append(f"match {t} {y} {m} {k}: want {want}")
if not C.cce_chapter("Batman", "The electrical brain", None, 1943):
    bad.append("a chapter on record must be found")
if not C.cce_chapter("Batman", "", 1, 1943):
    bad.append("a chapter on record must be found by its number")
if C.cce_chapter("Batman", "The bat's cave", 2, 1943) or C.cce_chapter("Flash Gordon", "The electrical brain", 1, 1943):
    bad.append("a chapter not on record must not be claimed")

for b in bad:
    print("FAIL", b)
print(f"{'PASS' if not bad else 'FAIL'}: {len(RENEWED)} renewals, {len(CANON)} canon controls, {len(SEEN)} printed entries, "
      f"{len(CASES)} matches")
sys.exit(1 if bad else 0)
