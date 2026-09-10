#!/usr/bin/env python3
"""
test_roku_search_feed.py — locks the Roku Search feed's contract.

Pure-function tests over synthetic items, so they run in CI with no catalog.
Each case names the Roku rule or the observed defect behind it; the first
case of each group is the NEGATIVE CONTROL (the thing that must still pass),
because a gate that rejects everything also "rejects" every bad item.

Run:  python tools/test_roku_search_feed.py
"""

from __future__ import annotations

import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))

import build_roku_search_feed as F  # noqa: E402

CASES = []


def check(name, got, want):
    ok = got == want
    CASES.append((name, ok, got, want))
    return ok


def item(**over):
    base = {
        "archiveID": "the_general_1926", "title": "The General", "year": 1926,
        "runtimeSeconds": 4500, "contentType": "silent-film",
        "synopsis": "A Confederate engineer fights to save his train and his girl.",
        "posterURL": "https://image.tmdb.org/t/p/w780/abc.jpg",
        "backdropURL": "https://image.tmdb.org/t/p/w1280/bg.jpg",
        "hasRealArtwork": True, "genres": ["Comedy", "Action", "film noir"],
        "director": "Buster Keaton, Clyde Bruckman",
        "cast": [{"name": "Buster Keaton"}, {"name": "Marion Mack"}],
        "imdbID": "tt0017925", "rightsStatus": "public_domain",
        "collections": ["silent_films"], "isSilentFilm": True, "colorMode": "bw",
        "releaseDate": "1926-12-31", "contentRating": "Passed",
        "videoFile": {"name": "TheGeneral720p1926.mp4"},
    }
    base.update(over)
    return base


def main() -> int:
    ids = {"the_general_1926", "x"}

    # ---- eligibility -----------------------------------------------------
    check("control: a pre-1930 indexed film is eligible",
          F.eligibility(item(), ids, "catalog"), None)
    check("a film absent from the public index is out (the channel cannot resolve it)",
          F.eligibility(item(archiveID="not-indexed"), ids, "catalog"), "not_in_public_index")
    check("an excluded item is out", F.eligibility(item(excluded=True), ids, "catalog"), "excluded")
    check("television is out (never rights-audited)",
          F.eligibility(item(contentType="tv-series"), ids, "catalog"), "tv_or_commercial")
    check("commercials are out",
          F.eligibility(item(contentType="commercial"), ids, "catalog"), "tv_or_commercial")
    # 1964-77 with no confirmation is a REPORT bucket: visible in the app by
    # owner policy, but not a claim made to a third party.
    check("renewal-zone (1970, unconfirmed) is out of the feed",
          F.eligibility(item(year=1970, imdbVotes=50, contentType="feature-film"), ids, "catalog"),
          "rights:renewal_zone_bw")
    check("presumed-PD (1950) is IN the catalog tier",
          F.eligibility(item(year=1950, contentType="feature-film"), ids, "catalog"), None)
    check("presumed-PD (1950) is OUT of the strict tier",
          F.eligibility(item(year=1950, contentType="feature-film"), ids, "strict"), "rights:presumed_pd")
    check("a 1977 film with an uploader CC mark is IN strict (safe_cc) but OUT of guaranteed",
          (F.eligibility(item(year=1977, rightsStatus="creative_commons", contentType="feature-film"), ids, "strict"),
           F.eligibility(item(year=1977, rightsStatus="creative_commons", contentType="feature-film"), ids, "guaranteed")),
          (None, "rights:safe_cc"))
    check("pre-1930 is IN guaranteed", F.eligibility(item(), ids, "guaranteed"), None)
    # The catalog year came from a wrong match; the archive id says 2022.
    check("a 'pre-1930' item whose id carries 2022 is out (The Tinder Swindler as 'The Swindler' 1919)",
          F.eligibility(item(archiveID="the.-tinder.-swindler.-2022.720p", year=1919), {"the.-tinder.-swindler.-2022.720p"}, "guaranteed"),
          "year_contradicted_by_id")
    check("a 'pre-1930' item whose releaseDate is 1941 is out (Kipps)",
          F.eligibility(item(releaseDate="1941-01-01", year=1921), ids, "guaranteed"), "year_contradicted_by_id")
    check("control: an id year BEFORE 1930 does not contradict ('TheGeneral720p1926' is fine)",
          F.year_contradicted({"archiveID": "TheGeneral720p1926", "year": 1926}), False)
    check("control: a 4-digit run inside a longer number is not a year ('720p1926' vs '19260')",
          F.id_year("film-19260-restored"), None)
    check("no poster -> out, counted", F.eligibility(item(hasRealArtwork=False), ids, "catalog"), "no_poster")
    check("control: a TMDb poster passes the professional-art gate",
          F.eligibility(item(artworkSource="tmdb"), ids, "strict", "professional"), None)
    check("a generated frame cover is out under --art professional",
          F.eligibility(item(artworkSource="generated"), ids, "strict", "professional"), "art_not_professional")
    check("a generated frame cover is still IN under --art any",
          F.eligibility(item(artworkSource="generated"), ids, "strict", "any"), None)
    check("no runtime -> out", F.eligibility(item(runtimeSeconds=0), ids, "catalog"), "no_runtime")
    # A yearless item is unjudgeable to the rights audit (Decision 027), which
    # is the gate that answers first; the year check behind it is for a year
    # the audit could read but the feed cannot state.
    check("no year -> out, as the rights audit's own verdict",
          F.eligibility(item(year=None), ids, "catalog"), "rights:unknown_year")

    # ---- ids ---------------------------------------------------------------
    long_id = "ptp_the-ten-commandments_cecil-b-demille_blu-ray_x264_mkv_720p_180770"
    check("control: a short archive id is the asset id", F.asset_id("suddenly"), "suddenly")
    d = F.asset_id(long_id)
    check("a >50-char archive id gets a 50-char derived id", len(d), 50)
    check("the derived id is stable across runs", F.asset_id(long_id), d)
    check("two long ids sharing a prefix do not collide",
          F.asset_id(long_id) == F.asset_id(long_id + "x"), False)
    a = F.build_asset(item(archiveID=long_id))
    check("playId is ALWAYS the archive id (what the channel takes as contentId)",
          a["content"]["playOptions"][0]["playId"], long_id)

    # ---- type --------------------------------------------------------------
    check("control: 75 min is a movie", F.roku_type(item()), "movie")
    check("15:00 exactly is shortform (Roku: 15 minutes or less)", F.roku_type(item(runtimeSeconds=900)), "shortForm")
    check("15:01 is a movie", F.roku_type(item(runtimeSeconds=901)), "movie")
    check("tv-special is a movie by default (store build predates tvSpecial autoplay)",
          F.roku_type(item(contentType="tv-special")), "movie")
    check("tv-special is tvspecial only when asked",
          F.roku_type(item(contentType="tv-special"), tv_specials=True), "tvSpecial")

    # ---- genres ------------------------------------------------------------
    check("control: known genres map to Roku's vocabulary",
          F.roku_genres(item()), ["comedy", "action", "crime drama"])
    check("an unknown label is dropped, never guessed",
          F.roku_genres(item(genres=["flashback film", "Drama"])), ["drama"])
    check("nothing mappable falls back by content type",
          F.roku_genres(item(genres=["Short"], contentType="newsreel")), ["news"])
    check("nothing at all is 'entertainment', not 'drama'",
          F.roku_genres(item(genres=[], contentType="feature-film")), ["entertainment"])

    # ---- ratings -----------------------------------------------------------
    check("control: PG-13 is MPAA", F.advisory_rating("PG-13"), {"source": "MPAA", "value": "PG-13"})
    check("TV-G is USA_PR", F.advisory_rating("TV-G"), {"source": "USA_PR", "value": "TV-G"})
    check("Hays-era 'Passed' is honestly UR", F.advisory_rating("Passed"), {"source": "MPAA", "value": "UR"})
    check("no rating is UR", F.advisory_rating(None), {"source": "MPAA", "value": "UR"})

    # ---- images (Roku's 1920x1080 ceiling) ---------------------------------
    check("control: a TMDb w500 poster is left as is",
          F.image_url("https://image.tmdb.org/t/p/w500/a.jpg"), "https://image.tmdb.org/t/p/w500/a.jpg")
    check("a TMDb w780 poster (780x1170) is asked for at w500",
          F.image_url("https://image.tmdb.org/t/p/w780/a.jpg"), "https://image.tmdb.org/t/p/w500/a.jpg")
    check("a TMDb original backdrop is asked for at w1280",
          F.image_url("https://image.tmdb.org/t/p/original/b.jpg", "background"),
          "https://image.tmdb.org/t/p/w1280/b.jpg")
    check("a Commons FilePath loses its width hint (the resolver needs the bare title)",
          F.image_url("https://commons.wikimedia.org/wiki/Special:FilePath/X.jpg?width=600"),
          "https://commons.wikimedia.org/wiki/Special:FilePath/X.jpg")
    check("an upload.wikimedia original is LEFT ALONE (a forced thumb 400s past the original width)",
          F.image_url("https://upload.wikimedia.org/wikipedia/en/b/b1/Star_Reporter_%281939%29.jpg"),
          "https://upload.wikimedia.org/wikipedia/en/b/b1/Star_Reporter_%281939%29.jpg")
    check("a non-http value is no image", F.image_url("pkg:/images/x.png"), None)

    # ---- the resolver: Roku's validator does NOT follow a redirect ----------
    rv = F.ImageResolver(network=False)
    rv.node_prefix = "https://ia601609.us.archive.org/27/items/archivewatch-covers/"
    check("control: a direct TMDb URL passes through the resolver untouched",
          rv.resolve("https://image.tmdb.org/t/p/w500/a.jpg"), "https://image.tmdb.org/t/p/w500/a.jpg")
    check("an archive.org cover is rewritten onto the storage node (no 302 left)",
          rv.resolve("https://archive.org/download/archivewatch-covers/x.1a2b.jpg"),
          "https://ia601609.us.archive.org/27/items/archivewatch-covers/x.1a2b.jpg")
    import tempfile
    tmp = Path(tempfile.mkdtemp())
    (tmp / "x.1a2b.jpg").write_bytes(b"")
    rl = F.ImageResolver(network=False, covers_dir=tmp)
    rl.node_prefix = rv.node_prefix
    check("a cover present in the Pages artifact is served from archivewatch.org (archive.org refuses Roku)",
          rl.resolve("https://archive.org/download/archivewatch-covers/x.1a2b.jpg"),
          "https://archivewatch.org/roku-search/covers/x.1a2b.jpg")
    check("a cover absent from the artifact still goes to the node",
          rl.resolve("https://archive.org/download/archivewatch-covers/y.9f.jpg"),
          "https://ia601609.us.archive.org/27/items/archivewatch-covers/y.9f.jpg")
    check("a locally served cover needs no measurement (400x600 by construction)",
          F.image_verdict("https://archivewatch.org/roku-search/covers/x.jpg", {}), "ok")
    rv.commons["Sterling_Hayden_in_the_movie_\"Suddenly\".jpg"] = \
        "https://upload.wikimedia.org/wikipedia/commons/4/4c/Sterling_Hayden_in_the_movie_%22Suddenly%22.jpg"
    check("a Commons FilePath resolves through the imageinfo answer",
          rv.resolve("https://commons.wikimedia.org/wiki/Special:FilePath/Sterling_Hayden_in_the_movie_%22Suddenly%22.jpg"),
          "https://upload.wikimedia.org/wikipedia/commons/4/4c/Sterling_Hayden_in_the_movie_%22Suddenly%22.jpg")
    before = rv.unresolved
    kept = rv.resolve("https://commons.wikimedia.org/wiki/Special:FilePath/Unknown.jpg")
    check("an unanswered Commons title is kept as-is and COUNTED, never invented",
          (kept.endswith("/Unknown.jpg"), rv.unresolved - before), (True, 1))
    check("commons_title decodes the file name", F.commons_title(
        "https://commons.wikimedia.org/wiki/Special:FilePath/Achtung_Feind_h%C3%B6rt_mit.svg"),
        "Achtung_Feind_hört_mit.svg")
    a_svg = F.build_asset(item(posterURL="https://commons.wikimedia.org/wiki/Special:FilePath/Logo.svg"))
    check("an unresolved Commons image fails validation (Roku refuses svg and redirects)",
          sorted(F.validate_asset(a_svg)), ["image format (jpg/png/gif only)", "image redirects (unresolved Commons)"])

    # ---- aspect: Roku's validator accepts 2:3 and 16:9 ONLY ----------------
    check("control: 500x750 is 2:3", F.aspect_ok(500, 750), True)
    check("1280x720 is 16:9", F.aspect_ok(1280, 720), True)
    check("500x707 (+6%) was refused by Roku -> bad", F.aspect_ok(500, 707), False)
    check("300x400 (exactly 3:4) was refused by Roku -> bad", F.aspect_ok(300, 400), False)
    check("300x300 (1:1) was refused by Roku -> bad", F.aspect_ok(300, 300), False)
    dims = {"https://m.media-amazon.com/x.jpg": [300, 229],
            "https://image.tmdb.org/t/p/w500/ok.jpg": [500, 750],
            "https://image.tmdb.org/t/p/w500/dead.jpg": 0}
    check("a generated cover needs no measurement",
          F.image_verdict("https://ia601609.us.archive.org/27/items/archivewatch-covers/x.jpg", dims), "ok")
    check("a TMDb w1280 backdrop needs no measurement",
          F.image_verdict("https://image.tmdb.org/t/p/w1280/b.jpg", dims), "ok")
    check("an unmeasured image is unknown, not bad",
          F.image_verdict("https://m.media-amazon.com/unmeasured.jpg", dims), "unknown")
    check("a dead (404) image is bad", F.image_verdict("https://image.tmdb.org/t/p/w500/dead.jpg", dims), "bad")
    a_bad = F.build_asset(item(posterURL="https://m.media-amazon.com/x.jpg",
                               backdropURL="https://image.tmdb.org/t/p/w1280/bg.jpg"), dims=dims)
    check("an off-aspect poster is replaced by the 16:9 backdrop as main",
          [i["type"] + ":" + i["url"] for i in a_bad["images"]],
          ["main:https://image.tmdb.org/t/p/w1280/bg.jpg"])
    check("an off-aspect poster with no backdrop drops the asset",
          F.build_asset(item(posterURL="https://m.media-amazon.com/x.jpg", backdropURL=None), dims=dims), None)
    check("an unmeasured poster ships as-is (Roku judges it)",
          F.build_asset(item(posterURL="https://m.media-amazon.com/unmeasured.jpg"), dims=dims)["images"][0]["url"],
          "https://m.media-amazon.com/unmeasured.jpg")

    # ---- gates the validator taught us ----------------------------------
    check("59 seconds is out (ASSET_DURATION_SHORT)", F.eligibility(item(runtimeSeconds=59), ids, "catalog"), "under_60s")
    check("60 seconds is in", F.eligibility(item(runtimeSeconds=60), ids, "catalog"), None)
    check("year 1065 is out (ASSET_INVALID_RELEASE_YEAR)", F.eligibility(item(year=1065), ids, "catalog"), "implausible_year")
    check("year 1899 is out (Roku: ASSET_ALL_RELEASE_REMOVED on every 1890s film)",
          F.eligibility(item(year=1899), ids, "catalog"), "implausible_year")
    check("year 1900 is in", F.eligibility(item(year=1900), ids, "catalog"), None)
    emoji = "Explore the app my friend made. " + "\U0001F4BF " * 90
    check("lengths are counted in UTF-16 units, as Roku counts them",
          F.ulen(F.descriptions(item(synopsis=emoji))[0]) <= 195, True)
    long_text = "Word " * 80
    check("descriptions stay five under Roku's limits",
          (len(F.descriptions(item(synopsis=long_text))[0]) <= 195,
           len(F.descriptions(item(synopsis=long_text))[1]) <= 495), (True, True))

    # ---- descriptions ------------------------------------------------------
    cal = ("A man named Francis relates a story about his best friend Alan and "
           "his fiancée Jane. Alan takes him to a fair where they meet Dr. "
           "Caligari, who exhibits a somnambulist, Cesare, that can predict the "
           "future. When a friend is murdered, Francis suspects Cesare.")
    short = F.clip(cal, 200)
    check("control: short description fits 200", len(short) <= 200, True)
    check("a clip never ends on an honorific ('...meet Dr.')", short.endswith("Dr."), False)
    s, l = F.descriptions(item(synopsis=None))
    check("no synopsis -> an honest generated line, no long description",
          (s, l), ("Silent film from 1926 by Buster Keaton, Clyde Bruckman, preserved by the Internet Archive.", None))
    s2, _ = F.descriptions(item(synopsis=["Part one.", "Part two."]))
    check("a list-valued synopsis is joined", s2, "Part one. Part two.")

    # ---- credits -----------------------------------------------------------
    check("control: two directors split on the comma",
          [c["name"] for c in F.credits(item()) if c["role"] == "director"],
          ["Buster Keaton", "Clyde Bruckman"])
    check("'Florenz Ziegfeld, Jr.' is one person",
          F.split_people("Florenz Ziegfeld, Jr."), ["Florenz Ziegfeld, Jr."])
    check("cast carries role actor", F.credits(item())[-1], {"name": "Marion Mack", "role": "actor"})

    # ---- release / quality / tags ------------------------------------------
    check("control: a real release date is used", F.release(item()), {"releaseDate": "1926-12-31"})
    check("a release date from a different year than `year` is distrusted -> year",
          F.release(item(releaseDate="2015-01-01")), {"releaseYear": 1926})
    check("720p in the file name is hd", F.quality(item()), "hd")
    check("no hint is sd", F.quality(item(videoFile={"name": "x.mp4"}, archiveID="x", title="X")), "sd")
    check("tags stay under 20 chars and name the decade",
          F.tags(item(), "safe_pd_age"), ["1920s", "public domain", "silent film", "black and white", "internet archive"])

    # ---- whole asset + pagination ------------------------------------------
    a = F.build_asset(item())
    check("control: a full asset validates", F.validate_asset(a), [])
    check("IMDb ids are OFF by default (Roku's published schema rejects the source)",
          "externalIds" in a, False)
    check("--imdb emits the IMDb id as an externalId",
          F.build_asset(item(), imdb=True).get("externalIds"), [{"source": "IMDB", "id": "tt0017925"}])
    check("title is never decorated with the year", a["titles"][0]["value"], "The General")
    check("a background image is included when the catalog has one", len(a["images"]), 2)
    pages = F.paginate([a] * 5, 2, "https://archivewatch.org/roku-search", "ab12cd")
    check("5 assets at 2/page is 3 pages; the stamp is in the NAME (the CDN ignores query strings)",
          [n for n, _ in pages], ["feed.json", "feed-2-ab12cd.json", "feed-3-ab12cd.json"])
    check("every page but the last chains nextPageUrl",
          [d.get("nextPageUrl") for _, d in pages],
          ["https://archivewatch.org/roku-search/feed-2-ab12cd.json",
           "https://archivewatch.org/roku-search/feed-3-ab12cd.json", None])
    check("every page is a complete root (version, language, countries)",
          all(d["version"] == "1" and d["defaultLanguage"] == "en"
              and d["defaultAvailabilityCountries"] == ["us"] for _, d in pages), True)

    bad = 0
    for name, ok, got, want in CASES:
        print(("PASS " if ok else "FAIL ") + name)
        if not ok:
            bad += 1
            print(f"      got:  {got!r}\n      want: {want!r}")
    print(f"\n{len(CASES) - bad}/{len(CASES)} passed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
