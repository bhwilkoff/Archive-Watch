#!/usr/bin/env python3
"""Every platform must say something ABOUT THE FILM.

A post that names a film and links to it and says nothing else is a database
row. That was fixed for Bluesky in September 2026 by putting `synopsis` in its
order as the fallback when no quoted review exists — and Mastodon, which has
the same problem for the same reason, was left out. Measured on the live post
for Day of Wrath (1943): Mastodon used 207 of its 500 characters and carried
"Published in 1943, in the public domain in the United States" where Bluesky
carried Dreyer and the Nazi occupation of Denmark, from the SAME spec.

    python3 tools/test_social_compose.py
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import social_post as sp

SPEC = {
    "title": "Day of Wrath", "year": 1943,
    "link": "https://archivewatch.org/item/day.-of.-wrath.-1943",
    "genres": ["Drama", "History"],
    "fragments": [
        {"kind": "synopsis", "text": "A notable Danish film directed by Carl "
         "Theodor Dreyer, released in 1943 during the Nazi occupation of Denmark."},
        {"kind": "rights", "text": "Published in 1943, in the public domain in "
         "the United States."},
        {"kind": "meta", "text": "Feature film · 97 min · dir. Carl Theodor Dreyer"},
    ],
}

def main():
    p = f = 0
    def check(name, ok, detail=""):
        nonlocal p, f
        p, f = (p + 1, f) if ok else (p, f + 1)
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else '  ' + detail}")

    for platform in ("bluesky", "mastodon", "threads", "instagram", "youtube"):
        text = sp.compose(SPEC, platform)
        # The film's own words must be there — not the rights boilerplate.
        check(f"{platform} says something about the film",
              "Dreyer" in text, repr(text[:90]))
        check(f"{platform} names the film and links it",
              "Day of Wrath" in text and "archivewatch.org" in text)
        check(f"{platform} fits its limit",
              len(text) <= sp.LIMITS[platform],
              f"{len(text)}/{sp.LIMITS[platform]}")

    # The specific regression: rights alone is not a description.
    m = sp.compose(SPEC, "mastodon")
    check("mastodon does not fall back to rights INSTEAD of the film",
          not (("public domain" in m) and ("Dreyer" not in m)), repr(m[:90]))

    print(f"\n{p} passed, {f} failed")
    return 1 if f else 0

if __name__ == "__main__":
    raise SystemExit(main())
