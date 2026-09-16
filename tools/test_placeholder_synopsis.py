#!/usr/bin/env python3
"""What an uploader typed INSTEAD of a description is not a synopsis: "To
come.", "510", the title echoed, "The Red Dragon 1929 Warner Oland, Neil
Hamilton", a run of quoted IMDb review titles. A pasted-source prefix and a
NARA catalog stamp come off; an ownership disclaimer in any language leaves.
Cases from a 30-item random sample of the live catalog (2026-09-16)."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

SEA = ('Mike Nelson (Lloyd Bridges) is hired to investigate the disappearance of the "Sea Witch", '
       'the "Mary Ann" and the "Lucky Star" off the coast.')
BIG = ("Sara Post (Marjorie Main) has molded her niece, Penny, into a crowd-pleasing trapeze performer. "
       "The main attraction at the circus is in danger.")
CASES = [
    ("To come.", "Home Movie: 97165", None),
    ("510", "510", None),
    ("Enter the Lone Ranger.", "Enter The Lone Ranger", None),
    ("otr", "Tonightandeverynight", None),
    ("The Red Dragon 1929 Warner Oland, Neil Hamilton, Jean Arthur, O. P. Heggie", "The Red Dragon", None),
    ("The Snowman 1933 Color Sound Cartoon", "The Snowman", None),
    ('"Buzzard of Mars" "Possibly the most pointless movie ever made" "No doubt the worst Mars movie" (IMDb)',
     "Horrors of the Red Planet", None),
    ("From The Public Domain Movie Database: Bluto plays all sorts of gags on Popeye and Olive on April Fool's Day.",
     "Popeye: Cooking With Gags", "Bluto plays all sorts of gags on Popeye and Olive on April Fool's Day."),
    ("All musik, ljud och bild går till dess rätta ägare. Amerikansk långfilm från 1948 om den sexistiske "
     "författaren Owen som möter sin överkvinna.", "Ord I Rättan Tid",
     "Amerikansk långfilm från 1948 om den sexistiske författaren Owen som möter sin överkvinna."),
    ("Ad for 1941 cars and trucks in the new Lincoln line. ARC Identifier 91500", "1941 Lincoln Advertising",
     "Ad for 1941 cars and trucks in the new Lincoln line."),
    ("GOOD NIGHT, NURSE! (1918) Starring: Roscoe Arbuckle, Buster Keaton, Al St. John, Alice Lake "
     "Written and Directed by Buster Keaton and Eddie Cline Camera by Elgin Lessley Produced by Joseph M. Schenck",
     "Good Night, Nurse!", None),
    ("The Blue Lamp with Dirk Bogarde (1950). british, english, england, uk, united kingdom, black and white, "
     "film, crime, murder, noir, dirk bogarde, police, policemen, british police, 1950", "The Blue Lamp", None),
    # Controls: a real plot, a short but real description, quotes inside a sentence.
    (BIG, "Under The Big Top", BIG),
    ("Tire making", "Rubber", "Tire making"),
    (SEA, "Sea Hunt", SEA),
    ("Directed by Roscoe Arbuckle, this comedy follows a drunk who is committed to a sanitarium, where he "
     "falls for a nurse and is chased by a doctor.", "Good Night, Nurse!",
     "Directed by Roscoe Arbuckle, this comedy follows a drunk who is committed to a sanitarium, where he "
     "falls for a nurse and is chased by a doctor."),
]


def main():
    fails = 0
    for src, title, want in CASES:
        it = {"synopsis": src, "synopsisSource": "archive", "title": title, "archiveID": "x"}
        R.sanitize_synopsis(it)
        got = it.get("synopsis") or None
        ok = got == want
        fails += not ok
        print(f"{'ok ' if ok else 'FAIL'} {got!r}"[:110])
    print(f"{len(CASES) - fails}/{len(CASES)} placeholder-synopsis cases")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
