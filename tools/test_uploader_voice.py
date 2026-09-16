#!/usr/bin/env python3
"""An uploader's sentences about themselves, the copy, or the viewer leave a
synopsis; the plot stays. Cases from the 2026-09-16 audit."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R  # noqa: E402

CASES = [
    ("The First 'production' of Buster Keaton VERY comic!!! =D I Love this film. "
     "Please, click in 'MPEG4' and save the film!!", None),
    ("A drifter arrives in a small town. The sheriff suspects him of murder.",
     "A drifter arrives in a small town. The sheriff suspects him of murder."),
    ("A very good doctor treats the miners. The mine collapses.",
     "A very good doctor treats the miners. The mine collapses."),
    ("Great film, a must watch. The story follows a nurse in wartime Manila.",
     "The story follows a nurse in wartime Manila."),
    ("In the year 2000 mankind is ruled by machines. 10/10 would watch again.",
     "In the year 2000 mankind is ruled by machines."),
    ("This one is 480p but is clearly not dvd quality. A bank clerk inherits a circus from his uncle in Ohio.",
     "A bank clerk inherits a circus from his uncle in Ohio."),
    ("High-quality military trucks cross the desert under fire.",
     "High-quality military trucks cross the desert under fire."),
    ("(uploaders note; This is a very bad encode.", None),
    ("A Little Audrey Cartoon, downloaded from Public Domain Movie Torrents.", None),
    ("This is the best copy available. Thanks Dave from San Francisco for the video. Cinderella is bullied "
     "by her stepsisters until a fairy godmother sends her to the ball.",
     "Cinderella is bullied by her stepsisters until a fairy godmother sends her to the ball."),
    ("Harvard Film Archive, projection print somewhat scratched, HFA Item no: 9675. Footage of the ruins of "
     "Hiroshima and Nagasaki shot by a Japanese crew in the weeks after the bombings.",
     "Footage of the ruins of Hiroshima and Nagasaki shot by a Japanese crew in the weeks after the bombings."),
    ("A good print of a bad film about a decent man who scans the horizon for the ship carrying his brother home.",
     "A good print of a bad film about a decent man who scans the horizon for the ship carrying his brother home."),
    ("Although I do receive great joy from sharing these uploads with you, I have no wish to infringe on any "
     "existing copyright law. Ann Marie is an aspiring actress in New York who takes odd jobs between auditions.",
     "Ann Marie is an aspiring actress in New York who takes odd jobs between auditions."),
    ("A tour of the immense Ford Motor Company assembly plant in Dearborn. This film can be purchased on DVD and "
     "higher quality copies are available.", "A tour of the immense Ford Motor Company assembly plant in Dearborn."),
    ("Her house is invaded by lively crows and she finds a scarecrow to frighten them away. This cartoon might be "
     "her best from that year.", "Her house is invaded by lively crows and she finds a scarecrow to frighten them away."),
    ("The best man at the wedding loses the ring and the bride's father chases him across the county fair.",
     "The best man at the wedding loses the ring and the bride's father chases him across the county fair."),
    ("I've been researching newly public domain films from 1929 and earlier, so I'm uploading the best copies.",
     None),
]


def main():
    fails = 0
    for src, want in CASES:
        it = {"synopsis": src, "synopsisSource": "archive", "title": "x"}
        R.sanitize_synopsis(it)
        got = it.get("synopsis") or None
        ok = got == want
        fails += not ok
        print(f"{'ok ' if ok else 'FAIL'} {got!r}"[:100])
    tmdb = "I love this film. A drifter arrives in a small town and the sheriff suspects him of murder."
    it = {"synopsis": tmdb, "synopsisSource": "tmdb", "title": "x"}
    R.sanitize_synopsis(it)
    ok = it["synopsis"] == tmdb
    fails += not ok
    print(f"{'ok ' if ok else 'FAIL'} tmdb text untouched")
    print(f"{len(CASES) + 1 - fails}/{len(CASES) + 1} uploader-voice cases")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
