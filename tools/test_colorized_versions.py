#!/usr/bin/env python3
"""A colorized upload is a VERSION of its black-and-white film, never the default copy.

Owner, 2026-09-30: "The colorized versions should be available via the
versions options on a given title, but should never be the default one
offered." build_sqlite.merge_film_duplicates must merge it into the B&W
film's card, keep the B&W copy as the survivor, and still keep a real
color REMAKE apart."""
import copy
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_sqlite as B

def item(aid, title, year, color, url, **kw):
    d = {"archiveID": aid, "title": title, "year": year, "colorMode": color,
         "contentType": "feature-film", "downloadURL": url, "runtimeSeconds": 4500,
         "imdbID": "tt0021814"}
    d.update(kw)
    return d

bw = item("dracula.-1931", "Dracula", 1931, "bw", "https://a/dracula.mp4")
col = item("dracula-1931-colorized", "Dracula", 1931, "color", "https://a/dracula_4k_2160p.ia.mp4",
           subtitleHLS="x")
remake = item("dracula-1979", "Dracula", 1979, "color", "https://a/d79.mp4", imdbID="tt0079073", runtimeSeconds=6540)

def run(items):
    items = copy.deepcopy(items)
    out = B.merge_film_duplicates(items)
    return out

fails = 0
def check(name, ok):
    global fails
    fails += not ok
    print(("PASS " if ok else "FAIL ") + name)

kept = {i["archiveID"] for i in run([bw, col, remake])}
aliases = B.merge_film_duplicates.aliases
check("the colorized copy merges into the B&W film as a version",
      "dracula-1931-colorized" not in kept and aliases.get("dracula-1931-colorized") == "dracula.-1931")
check("the B&W original is the default copy, even against a 4K captioned colorization",
      "dracula.-1931" in kept)
check("CONTROL: a color remake with its own imdb stays its own card", "dracula-1979" in kept)
check("CONTROL: a colorization is recognised from its id", B._colorized_upload(col) and not B._colorized_upload(bw))
print(f"{4 - fails}/4")
sys.exit(1 if fails else 0)
