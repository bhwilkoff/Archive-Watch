"""archive.org's own movie_trailers collection marks a silent-era trailer posing
as the feature (turner_video_9, 119 s, was the catalog's only "The Kid"), with
controls for every exception the rule keeps: a full-length film in that
collection, a pre-1905 film that really is a minute long, a trailer that says
so in its title, a commercial, and a silent fragment outside the collection."""
import sys
from collections import Counter
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

T = ["movie_trailers_unsorted", "movie_trailers", "moviesandfilms"]


def item(**kw):
    base = {"archiveID": "x", "title": "The Kid", "year": 1921, "contentType": "silent-film",
            "isSilentFilm": True, "collections": T, "fileRuntimeSeconds": 119,
            "runtimeSeconds": 119, "imdbID": "tt0012349", "imdbVotes": 144275}
    base.update(kw)
    return base


def flagged(it):
    stats = Counter()
    R.flag_trailers([it], stats)
    return bool(it.get("excluded")), it


cases = [
    ("the Turner promo of The Kid", item(), True),
    ("control: Abraham Lincoln, 85 min, in the same collection",
     item(title="Abraham Lincoln", year=1930, isSilentFilm=False, fileRuntimeSeconds=5080,
          runtimeSeconds=5080), False),
    ("control: Sherlock Holmes Baffled (1900) runs a minute whole",
     item(title="Sherlock Holmes Baffled", year=1900, fileRuntimeSeconds=51, runtimeSeconds=51), False),
    ("control: a trailer that says so",
     item(title="Trailer for Hallelujah", year=1929), False),
    ("control: a commercial", item(contentType="commercial"), False),
    ("control: a silent fragment outside the collection",
     item(collections=["silent_films"]), False),
]
for name, it, want in cases:
    got, after = flagged(it)
    assert got == want, (name, got, after)
    assert R._trailer_test(item(**{k: v for k, v in it.items() if k in ("title", "year", "contentType", "collections", "fileRuntimeSeconds", "runtimeSeconds", "isSilentFilm")})) == want or not want, name
    if want:
        assert after["trailerEvidence"] == "archive.org collection movie_trailers", after
        assert after["contentTypeWas"] == "silent-film", after
print(f"trailer_collection: {len(cases)} ok")
