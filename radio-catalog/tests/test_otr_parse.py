"""File-name parsing against real archive.org names (docs/research/radio/07)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "tools"))
import otr_parse as P

EXPECT = [
    ("Suspense 420617 001 The Burning Court (128-44) 28455 30m00s.mp3", "Suspense", "1942-06-17", 1, "The Burning Court"),
    ("Whistler_42-05-16_ep001_Retribution.mp3", "Whistler", "1942-05-16", 1, "Retribution"),
    ("Dragnet_49-06-10_ep002_Homicide.mp3", "Dragnet", "1949-06-10", 2, "Homicide"),
    ("Gunsmoke 52-04-26 (001) Billy the Kid.mp3", "Gunsmoke", "1952-04-26", 1, "Billy the Kid"),
    ("FMM 1931-06-01 (xx) Smackout.mp3", "FMM", "1931-06-01", None, "Smackout"),
    ("Father Knows Best (055) 1950-11-02 Too Many Problems.mp3", "Father Knows Best", "1950-11-02", 55, "Too Many Problems"),
    ("XMinusOne55-04-24001NoContact.mp3", "XMinusOne", "1955-04-24", 1, "NoContact"),
    ("Inner_Sanctum_-_450109_Desert_Death.mp3", "Inner Sanctum", "1945-01-09", None, "Desert Death"),
    ("42-06-17_Burning_Court.mp3", None, "1942-06-17", None, "Burning Court"),
    ("01 38-07-11 Dracula.mp3", None, "1938-07-11", None, "Dracula"),
    ("TSP420617.mp3", "TSP", "1942-06-17", None, None),
    ("04 Rex Stout's Nero Wolfe 04 82-02-06 The Cop Killer.mp3", "Rex Stout's Nero Wolfe", "1982-02-06", 4, "The Cop Killer"),
]
NO_DATE = ["UIUC_Archives_1306005_1470_B.mp3", "Dimension X 011 Zero Hour.mp3"]


def main():
    failed = 0
    for name, series, date, num, title in EXPECT:
        p = P.parse(name)
        got = (p["series"], p["date"], p["num"], p["title"])
        if got != (series, date, num, title):
            failed += 1
            print(f"FAIL {name}: {got}")
    for name in NO_DATE:
        if P.parse(name)["date"]:
            failed += 1
            print(f"FAIL (control) {name} got a date {P.parse(name)['date']}")
    tag = P.parse_album_tag("04/26/52, episode 1")
    if tag != {"date": "1952-04-26", "num": 1}:
        failed += 1
        print(f"FAIL album tag {tag}")
    n = len(EXPECT) + len(NO_DATE) + 1
    print(f"{n - failed}/{n} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
