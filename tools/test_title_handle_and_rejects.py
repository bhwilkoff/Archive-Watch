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

# Mature: a synopsis naming an adult genre, or archive.org's whole "Adult" subject.
check("sex-comedy synopsis is mature", rc.is_adult_signal({"title": "Italian Sex", "synopsis": "An Italian sex comedy of 1973."}), True)
check("exact Adult subject is mature", rc.is_adult_signal({"title": "Messe noire", "subjects": ["Adult", "silent"]}), True)
check("CONTROL: 'adult education' subject is not", rc.is_adult_signal({"title": "Night Class", "subjects": ["adult education"]}), False)
check("CONTROL: a burlesque parody is not", rc.is_adult_signal({"title": "A Burlesque on Carmen", "synopsis": "Chaplin's burlesque of the opera."}), False)
check("CONTROL: Haxan's 'erotic film' mention is not", rc.is_adult_signal({"title": "Haxan", "synopsis": "A documentary-style erotic film about witchcraft."}), False)

# A provider subtitle fetched for an IMDb id the item no longer carries is
# another film's dialogue (the Sherlock Holmes pilot kept Abbott and Costello's).
sub = lambda m: {"lang": "en", "source": "subsource", "url": "x.vtt", "matchedIMDb": m}
pilot = {"archiveID": "SherlockHolmes-TheManWhoDisappearedfailedPilot", "imdbID": None,
         "captions": [sub("tt0043255")], "subtitleHLS": "master.m3u8"}
kept = {"archiveID": "abbott-and-costello-meet-the-invisible-man", "imdbID": "tt0043255",
        "captions": [sub("tt0043255")], "subtitleHLS": "master.m3u8"}
own = {"archiveID": "uploader-srt", "imdbID": None,
       "captions": [{"lang": "en", "source": "archive", "url": "y.vtt"}], "subtitleHLS": "master.m3u8"}
check("wrong film's subtitle dropped", rc.drop_wrong_film_subtitles([pilot, kept, own]), 1)
check("its HLS track goes with it", (pilot["captions"], pilot.get("subtitleHLS")), (None, None))
check("CONTROL: the film's own match keeps its subtitle", (len(kept["captions"]), kept["subtitleHLS"]), (1, "master.m3u8"))
check("CONTROL: an uploader's own file has no match to contradict", len(own["captions"]), 1)
check("Sherlock pilot's match is named wrong", "SherlockHolmes-TheManWhoDisappearedfailedPilot" in rej, True)

print("FAILED" if fails else "ALL PASS", fails)
sys.exit(1 if fails else 0)
