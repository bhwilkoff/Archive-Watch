#!/usr/bin/env python3
"""An uploader's @handle is cruft; a spaced "@" is a word ("Women @ NASA").
And a match named wrong in match_rejects.json is cleared by remediate 0b1.

The handle rule was `@\\s*\\S+`, which let whitespace follow the "@": "Women @
NASA" became "Women" and was matched to a 2021 horror film. Controls: a real
handle is still stripped, and an item not named in match_rejects keeps its ids.
"""
import copy, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
import remediate_catalog as rc

fails = 0
def check(name, got, want):
    global fails
    ok = got == want
    fails += not ok
    print(("PASS" if ok else "FAIL"), name, repr(got), "" if ok else f"(want {want!r})")

check("spaced @ is a word", rc._strip_uploader_cruft("Women @ NASA"), "Women @ NASA")
check("spaced @ mid-title", rc._strip_uploader_cruft("Freeze Out @ The End (Ground Control)"),
      "Freeze Out @ The End (Ground Control)")
check("CONTROL: a handle is stripped", rc._strip_uploader_cruft("FAASLE 1985@malikjee"), "FAASLE 1985")
check("CONTROL: a spaced-free handle after text", rc._strip_uploader_cruft("Film @someuploader"), "Film")

rej = rc._load_match_rejects()
check("Women-at-NASA is named", "Women-at-NASA" in rej, True)
check("notes are not entries", any(k.startswith("_") for k in rej), False)

item = {"archiveID": "Women-at-NASA", "tmdbID": 719164, "imdbID": "tt4600982",
        "posterURL": "https://image.tmdb.org/x.jpg", "synopsis": "A detective...", "synopsisSource": "omdb"}
cleared = copy.deepcopy(item)
rc._clear_wrong_artwork(cleared, None)
check("cleared ids", (cleared["tmdbID"], cleared["imdbID"], cleared["posterURL"], cleared["synopsis"]),
      (None, None, None, None))
check("CONTROL: an unnamed item is not in the list", "TheGeneral720p1926" in rej, False)

# A cleared match's animation TYPING is not evidence (The Gaucho, 1928).
gaucho = {"archiveID": "the-gaucho_1928", "title": "The Gaucho", "year": 1928, "contentType": "animation",
          "genres": ["Animation", "Romance"], "matchVerdict": "cleared_runtime", "collections": ["feature_films"],
          "subjects": [], "runtimeSeconds": 5700}
rc.scrub_cleared_match(gaucho, own_meta={}, siblings={})
check("cleared, no own evidence -> re-typed", (gaucho["contentType"], "Animation" in gaucho["genres"]),
      ("feature-film", False))
felix = {"archiveID": "felix-x", "title": "Felix X", "year": 1925, "contentType": "animation",
         "genres": ["Animation"], "matchVerdict": "cleared_runtime", "collections": ["animationandcartoons"],
         "subjects": ["cartoon"], "runtimeSeconds": 420}
rc.scrub_cleared_match(felix, own_meta={}, siblings={})
check("CONTROL: its own cartoon subject keeps it animation", (felix["contentType"], felix["genres"]),
      ("animation", ["Animation"]))

# A library sort title is un-inverted, with or without a closing period.
check("sort article", rc._invert_sort_article("Ravager, The"), "The Ravager")
check("sort article with period", rc._invert_sort_article("Evenings on the farm near Dikanka, the."),
      "The Evenings on the farm near Dikanka")
check("CONTROL: a comma title is left alone", rc._invert_sort_article("Hello, Dolly"), "Hello, Dolly")

print("FAILED" if fails else "ALL PASS", fails)
sys.exit(1 if fails else 0)
