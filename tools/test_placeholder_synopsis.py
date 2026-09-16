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
    ("Love That Bob Ep 5x02 Bob and the Dumb Blonde", "Bob and the Dumb Blonde", None),
    ("The Beverly Hillbillies Ep 50 Christmas At The Clampetts", "Christmas At The Clampetts", None),
    ("1932 - Hitlerjugend in den Bergen (20m 15s, 512x384)", "Hitlerjugend in den Bergen", None),
    ("Public domain cartoons of 1937. Work in progress. Corrections on copyright status welcome.",
     "Public Domain Animation", None),
    ("Victor Buono portrays a serial killer who strangles nurses in a city gripped by fear. The .mkv (Matroska) file "
     "is the uploaded file. Download it if your player can handle h.265 (HEVC).", "The Strangler",
     "Victor Buono portrays a serial killer who strangles nurses in a city gripped by fear."),
    ("Category: Drive-In Movie Ads Title: Dr. Pepper Jazz Length- 1:05 Sound: Yes (enhanced) Color "
     "Description: A colorful animated jazz combo plays while the Dr. Pepper logo dances across the screen.",
     "Dr. Pepper Jazz", "A colorful animated jazz combo plays while the Dr. Pepper logo dances across the screen."),
    ("For more programming from C Berry or information about this program, visit Seattle Community Media.",
     "Dr. Moze - Yoga for Earth", None),
    ("The Lucy Show ep Lucy Meets Sheldon Leonard", "Lucy Meets Sheldon Leonard", None),
    ("Wanna Home - Half Shot Shooters - Hoi Polloi -??? -??? -??? Channel 49 - WNYB-TV in Buffalo, NY - Playing the Ponies",
     "The Three Stooges", None),
    ("“Hollywood hooey from Gainsborough” “Mad, bad and wonderful” “Amiable tosh” “What a hoot!” (IMDB reviews quotes). "
     "A dashing young Spaniard falls for a gypsy dancer while a jealous nobleman plots against them both.", "Caravan",
     "A dashing young Spaniard falls for a gypsy dancer while a jealous nobleman plots against them both."),
    ("This riveting Russian documentary takes you inside the trials. The tribunal at Nuremberg hears the evidence "
     "against the surviving leaders of the Third Reich over eleven months.", "Sud narodov",
     "The tribunal at Nuremberg hears the evidence against the surviving leaders of the Third Reich over eleven months."),
    ("For Academic - Educational Use Only", "Inner Sanctum", None),
    ("KNIGHT OF THE TRAIL (1915) Starring: William S.", "Knight of the Trail", None),
    ("All 26 episodes of Room 222 season 2. These are DVDRips in pretty high quality considering the age.",
     "Room 222 - Complete Season 2", None),
    ("This is a banned Talespin cartoon from my collection of banned and censored cartoons. Baloo and Kit are "
     "hired to fly a shipment of explosives across the border, unaware that the buyers are arms dealers.",
     "Flying Dupes", "Baloo and Kit are hired to fly a shipment of explosives across the border, unaware that the buyers are arms dealers."),
    ("Andy Griffith Episode, Opie and the Spoiled Kid", "Opie and the Spoiled Kid", None),
    ("Tales Of Tomorrow ep Time to Go * Season: 1 * Episode: 29 * First Aired: 4/18/1952", "Time to Go", None),
    ("The 1930's had a few bangers apparently, I wouldn't know", "3O's 0Ldies", None),
    ("Here is one interesting Cartoon The Haunted House and The Skeleton Symphony. A Good one for a dark rainy night",
     "The Haunted House and The Skeleton Symphony", None),
    ("Lost in Space: s01e01: The Reluctant Stowaway", "Lost In Space : The Reluctant Stowaway", None),
    ("he Golem is a silent horror film directed by Paul Wegener and Henrik Galeen, based on the Jewish legend.",
     "The Golem", "The Golem is a silent horror film directed by Paul Wegener and Henrik Galeen, based on the Jewish legend."),
    ("'Unicycle: Looking at My World' (1976) 15m, dir. Dan Bessie. The world of 15 year old unicyclist Tony "
     "Marienthal includes school, friends and the long ride home.", "Unicycle: Looking at My World",
     "The world of 15 year old unicyclist Tony Marienthal includes school, friends and the long ride home."),
    ("Freeway Phobia Summary Demonstrates proper freeway driving techniques and describes the hazards of "
     "faulty merging and tailgating.", "Freeway Phobia",
     "Demonstrates proper freeway driving techniques and describes the hazards of faulty merging and tailgating."),
    ("Aired 18 Feb. 1963 Season 1, Episode 22 Actors: Victor Buono; Tracy Stratford Runtime: 23:16 Victor Buono "
     "plays a lonely man who befriends a runaway girl at a roadside diner.", "The New Loretta Young Show",
     "Victor Buono plays a lonely man who befriends a runaway girl at a roadside diner."),
    (["With teacher's guide", "Also issued as videocassette",
      "Producer, Joseph Koenig; director, script writer, and photographer, William Mason; music director, Robert Fleming",
      "Surveys the geological and ecological history of the Great Lakes, accompanied by narration in ballad form."],
     "The Rise and Fall of the Great Lakes",
     "Surveys the geological and ecological history of the Great Lakes, accompanied by narration in ballad form."),
    ("This series has fallen into the Public Domain.", "Captain Video and his Video Rangers", None),
    ("For Academic / Educational Use Only", "Night and the City", None),
    ('SPACE 1999 "Dragon\'s Domain" (1975) Directed by Michael Crichton', "SPACE 1999 S1E8", None),
    ("Department of Energy Response to Mechanical Shock NTIS Price: $105.00 Your Price: $0.00 AVA15026-VNB1 The program "
     "illustrates how components respond to shock loading and how engineers design for it.", "Response to Mechanical Shock",
     "Department of Energy Response to Mechanical Shock The program illustrates how components respond to shock loading "
     "and how engineers design for it."),
    ("Hello again and welcome to the Shocker Internet Drive In's 50th presentation! A mad scientist revives a "
     "gorilla with a human brain and sets it loose on a carnival.", "Shocker Internet Drive In 50",
     "A mad scientist revives a gorilla with a human brain and sets it loose on a carnival."),
    # Controls: a real plot, a short but real description, quotes inside a sentence.
    (BIG, "Under The Big Top", BIG),
    ("Tire making", "Rubber", "Tire making"),
    (SEA, "Sea Hunt", SEA),
    ("Soul Train (Season 2, Episode 19) featuring James Brown performing Get On The Good Foot and Soul Power "
     "before a studio audience in Chicago.", "Soul Train",
     "Soul Train (Season 2, Episode 19) featuring James Brown performing Get On The Good Foot and Soul Power "
     "before a studio audience in Chicago."),
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
