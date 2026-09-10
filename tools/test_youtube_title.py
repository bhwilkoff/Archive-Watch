#!/usr/bin/env python3
"""What a YouTube Shorts title has to do, and where it is read.

Researched (2026 guidance, multiple sources agreeing):
  * the Shorts FEED truncates at ~30-40 characters, search at ~60;
  * YouTube weights keywords appearing EARLY, and the keyword here is the
    film's name and year — not anything we add;
  * hashtags belong in the description, never the title.

The old title was `<film> (<year>) — free to watch` on EVERY video: fifteen
characters of call-to-action that the feed cuts off, that nobody searches
for, and that says the same thing about every upload. The link is in the
description and the channel name says the rest.

    python3 tools/test_youtube_title.py
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
import social_post as sp

def spec(title, year=1943, line=None, genres=("Drama",), director="Carl Theodor Dreyer"):
    frags = [{"kind": "synopsis", "text": "A Danish film."}]
    if line:
        frags.insert(0, {"kind": "line", "text": line})
    return {"title": title, "year": year, "genres": list(genres),
            "director": director, "link": "https://archivewatch.org/item/x",
            "fragments": frags}

def main():
    p = f = 0
    def check(name, ok, detail=""):
        nonlocal p, f
        p, f = (p + 1, f) if ok else (p, f + 1)
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{'' if ok else '  ' + detail}")

    # The defect this replaces.
    for s in (spec("Day of Wrath", line="You cannot burn what you cannot name"),
              spec("Day of Wrath")):
        t = sp.youtube_title(s)
        check("no call to action in the title", "free to watch" not in t.lower(), repr(t))
        check("the film's name is FIRST, for the keyword weight",
              t.startswith("Day of Wrath (1943)"), repr(t))
        check("no hashtags in the title", "#" not in t, repr(t))
        check("within YouTube's hard limit", len(t) <= 100, f"{len(t)}")

    # With a line, the hook follows the name and the whole thing stays readable.
    t = sp.youtube_title(spec("Day of Wrath", line="You cannot burn what you cannot name"))
    check("the burned line becomes the hook", '"You cannot burn' in t, repr(t))
    check("...and it stays inside the searchable window", len(t) <= 60, f"{len(t)}")

    # No line: a bare name beats a padded one.
    t = sp.youtube_title(spec("Day of Wrath"))
    check("with no line the title is just the film", t == "Day of Wrath (1943)", repr(t))

    # A long line is cut at a WORD, with an ellipsis — never mid-word.
    t = sp.youtube_title(spec("Suddenly", year=1954,
                              line="You have got duty in your eyes and it will be the death of you"))
    check("a long line is cut at a word boundary",
          t.endswith('…"') and "  " not in t, repr(t))
    check("...still within the window", len(t) <= 62, f"{len(t)}")

    # A long film NAME owns the title outright rather than being squeezed.
    long_name = "The Cabinet of Dr. Caligari and Other Expressionist Works"
    t = sp.youtube_title(spec(long_name, year=1920, line="a quotable line here"))
    check("a long film name keeps the title to itself",
          t == f"{long_name} (1920)", repr(t))

    # Tags describe THIS film, not every film.
    tags = sp.youtube_tags(spec("Day of Wrath", genres=("Drama", "History")))
    check("tags carry the film's own genres", "drama" in tags and "history" in tags, str(tags))
    check("...its year and decade", "1943" in tags and "1940s" in tags, str(tags))
    check("...and its director", "carl theodor dreyer" in tags, str(tags))

    # The description's visible window must carry the film, not a URL.
    d = sp.compose(spec("Day of Wrath", line="You cannot burn what you cannot name"), "youtube")
    # The bug was the ORDER: "link" led it, so the visible preview opened on a
    # URL. Assert that, not "no link within 100 chars" — a short synopsis can
    # legitimately let the link start at ~90, and my first version of this
    # check failed against correct output for exactly that reason.
    check("the description does not OPEN on a link",
          not d.lstrip().startswith("http") and "http" not in d.split("\n\n")[0],
          repr(d[:60]))
    check("...and the film is what the preview carries",
          "Day of Wrath" in d[:100], repr(d[:100]))
    check("...and hashtags are at the END", d.rstrip().split("\n")[-1].startswith("#"), repr(d[-40:]))

    # THE ADAPTER MUST USE THESE. Testing youtube_title() alone proves the
    # helper works, not that the upload sends it — reverting only the call site
    # left 19 of 20 checks green, which is a test asserting the wrong thing.
    src = pathlib.Path(__file__).with_name("social_post.py").read_text()
    body = src[src.index("def post_youtube"):]
    body = body[:body.index("\ndef ")] if "\ndef " in body[10:] else body
    check("post_youtube builds its title with youtube_title()",
          "title = youtube_title(spec)" in body)
    check("...and its tags with youtube_tags()",
          "youtube_tags(spec)" in body)
    check("...and no hardcoded call to action survives anywhere",
          "free to watch\"" not in src.lower().replace("free to watch: ", ""),
          "a literal '— free to watch' title is back")

    print(f"\n{p} passed, {f} failed")
    return 1 if f else 0

if __name__ == "__main__":
    raise SystemExit(main())
