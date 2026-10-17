"""The CCE drama renewal parser: one sample per printed format, OCR repairs,
and controls that must NOT parse.

    python3 tests/test_cce_drama_renewals.py

Each sample is OCR text as archive.org serves it (lines from the scans,
lightly trimmed). Broken controls, 2026-10-17, each run against a mutated copy:

    renewal window (26-29 years) removed           12/13
    a © statement stops at its first registration  12/13
    the volume-median R check removed              12/13
    no rejoining of an entry split by a blank line 12/13
    (FMT_B tried before FMT_A: 13/13 — the two never both match one entry,
    so their order is not load-bearing.)
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import fetch_cce_drama_renewals as F

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def rows(text, *, pad=True):
    """Parse one sample. `pad` adds ordinary renewals from the same year so
    the volume-median check has a volume to compare against."""
    filler = "\n\nFILLER PLAY, a farce. © 1Jan34; D30001. A. Writer (A); 2Jan62; R288000.\n\n" if pad else ""
    return [r for r in F.parse(text + filler, "vol") if r["title"] != "FILLER PLAY"]


# 1951-1953: under the author, renewal number before the claimant.
@case
def fmt_1951_renewal_first():
    t = """ADE, GEORGE.

The mayor and the manicure, a play in
one act. © 31Dec23, D66801. R75707,
1Mar51, James D. Rathbun (E)
"""
    r = F.parse(t, "v1951")
    assert len(r) == 1, r
    r = r[0]
    assert (r["title"], r["author"], r["reg"], r["orig_date"], r["r"], r["r_date"]) == \
        ("The mayor and the manicure", "ADE, GEORGE", "D66801", "1923-12-31", "R75707", "1951-03-01"), r
    assert r["claimant"].startswith("James D. Rathbun"), r


# 1954-1957: under the author, claimant first, renewal number last.
@case
def fmt_1954_claimant_first():
    t = """GILPATRIC, CAROLYN DRAPER.


Please stand by, a radioletta. © 7Oct26;
D77113, Carolyn Draper Gilpatric (A);
6Jan54; R124678.
"""
    r = F.parse(t, "v1954")
    assert len(r) == 1, r
    r = r[0]
    assert (r["title"], r["reg"], r["orig_year"], r["r"], r["r_date"]) == \
        ("Please stand by", "D77113", 1926, "R124678", "1954-01-06"), r
    assert r["author"] == "GILPATRIC, CAROLYN DRAPER" and r["radio"] and r["radio_why"].lower() == "radio", r


# 1958-1970: under the title in capitals; a series lists every registration
# and one renewal range, which is assigned in order when the counts agree.
@case
def fmt_1962_series_entry():
    t = """THE LONE RANGER; radio program by Francis
Striker. © No.A-9--A-10, 15Aug34,
D30663-30664 ; No.A-11, 17Aug34, D30707.
The Lone Ranger, Inc. (PWH); 13Aug62;
R300173-300175.
"""
    r = rows(t)
    got = [(x["title"], x["reg"], x["orig_date"], x["r"]) for x in r]
    assert got == [("THE LONE RANGER", "D30663", "1934-08-15", "R300173"),
                   ("THE LONE RANGER", "D30664", "1934-08-15", "R300174"),
                   ("THE LONE RANGER", "D30707", "1934-08-17", "R300175")], got
    assert all(x["radio"] and x["author"] == "Francis Striker" and x["r_range"] == "R300173-R300175" for x in r), r
    assert r[2]["episode"] == "A-11", r


# 1971-1977: renewal-number order, each entry headed by its own R number,
# the series in parentheses.
@case
def fmt_1974_series_parenthesis():
    t = """R577542.

How six traveled through the world.
By Nila Mack. (Let's pretend)
© 3May47; D9330. C BS, Inc. (PWH)5
20May74; R577542.
"""
    r = F.parse(t, "v1974")
    assert len(r) == 1, r
    r = r[0]
    assert (r["title"], r["author"], r["series"], r["reg"], r["r"], r["r_date"]) == \
        ("How six traveled through the world", "Nila Mack", "Let's pretend", "D9330", "R577542", "1974-05-20"), r
    assert r["radio"], r


# A series named only in parentheses is flagged radio by its name.
@case
def radio_by_series_name():
    t = """The Phantom of the haunted steeple. By
Evan Wylie. (The Shadow) © 10Dec46;
D6487. The Conde Nast Publications, Inc.
(PWH); 4Jan74; R566228.
"""
    r = F.parse(t, "v1974")
    assert len(r) == 1 and r[0]["series"] == "The Shadow" and r[0]["radio"], r


# OCR repairs: l for 1, O for 0, Ju1 for Jul, a trailing 3/5 for ";".
@case
def ocr_digit_repairs():
    t = """AKINS, ZOE.

Iucifers ladies, a play in three
acts. ©11Ju123, D65019. R73820,
2Feb51, Zoe Akins Rumbold (A)

Nettie, a play in one act. © 3lDec23,
D66800. R75711, 1Mar51; James D.
Rathbun (E)
"""
    r = {x["r"]: x for x in F.parse(t, "v1951")}
    assert r["R73820"]["orig_date"] == "1923-07-11", r
    assert r["R75711"]["orig_date"] == "1923-12-31", r
    t2 = "HITCH-HIKERS; radio script no.1 by Eugene Conrad. © 8Jun36; DU43002. Gloria A. Conrad (W); 4Jun645 R338916."
    r2 = F.parse(t2, "v1964")
    assert len(r2) == 1 and r2[0]["r"] == "R338916" and r2[0]["r_date"] == "1964-06-04", r2


# A registration's D read as p straight after the © date.
@case
def ocr_p_for_d():
    t = "The little liberty, a comedy in one act. © 28Sep27; p81202. Harold Brighouse (A); 7Jan55; R142060."
    r = F.parse(t, "v1955")
    assert len(r) == 1 and r[0]["reg"] == "D81202", r


# An entry split by a blank line keeps its title.
@case
def split_entry_rejoined():
    t = """The Case of the unlucky corpses. By


Norman A. Daniels. (Nick Carter, master
detective) © 23Dec49; D22654. The Conde
Nast Publications, Inc. (PWH); 20Apr77;
R659440.
"""
    r = F.parse(t, "v1977")
    assert len(r) == 1 and r[0]["title"] == "The Case of the unlucky corpses" and r[0]["series"] == "Nick Carter", r


# CONTROL: a current (original) registration carries no renewal: no row.
@case
def control_original_registration_only():
    t = """INNER SANCTUM. (Radio program) Scripts in this
series are by Emile C. Tepperman.
The man who couldn't die. © Columbia
Broadcasting System, Inc.; 3Mar47; DU9456.
"""
    assert rows(t) == [], rows(t)


# CONTROL: a cross-reference names a renewal number but no ©: no row.
@case
def control_cross_reference():
    t = "AGATHA'S aunt. R75700. SEE Toler, Sidney.\n\nALIAS Nora O'Brien. R75698. SEE Short, Marion."
    assert rows(t) == [], rows(t)


# CONTROL: an OCR'd year that puts the renewal 43 years after the original
# cannot be a 1909-Act renewal (filed in the 28th year): no row.
@case
def control_renewal_window():
    t = "GHOST WANTED, a mystery-comedy by Guernsey Le Pelley. © 20Aug31; D81730. Guernsey Le Pelley (A); 29Aug74; R467692."
    assert rows(t) == [], rows(t)


# CONTROL: a renewal number far from the volume's run lost a digit: the
# renewal is kept, its number is not guessed.
@case
def control_implausible_renewal_number():
    t = "".join(f"PLAY {i}, a farce. © {i + 1}Mar29; D85{i:03d}. A. B. (A); {i + 1}May56; R170{i:03d}.\n\n"
                for i in range(9))
    t += "The queen's husband, a comedy in three acts. © 13Mar29; D85278. Madeline H. Sherwood (W); 11May56; R17034."
    r = {x["reg"]: x for x in F.parse(t, "v1956")}
    q = r["D85278"]
    assert q["r"] is None and q["r_printed"] == "R17034" and q["src"].endswith("q=D85278"), q
    assert r["D85000"]["r"] == "R170000", r["D85000"]


# CONTROL: a new registration that merely mentions a renewal in its notes
# (a renewal number with no © registration before it) is not a renewal.
@case
def control_renewal_mentioned_without_registration():
    t = "MY FRIEND CURLEY. (See also My client Curley; 12Mar69; R459961)"
    assert rows(t) == [], rows(t)


if __name__ == "__main__":
    bad = 0
    for fn in CASES:
        try:
            fn()
        except Exception as e:
            bad += 1
            print(f"FAIL {fn.__name__}: {e}")
    print(f"{len(CASES) - bad}/{len(CASES)} passed")
    sys.exit(1 if bad else 0)
