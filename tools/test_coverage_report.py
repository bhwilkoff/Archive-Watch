"""coverage_report counts a served title owed a renewal check, and not one
already asked (control), nor a hidden one."""
import datetime as dt, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import corroborate_copyright as C
import coverage_report as R

today = dt.date(2026, 9, 30)
base = {"title": "White Zombie", "year": 1932, "contentType": "feature-film",
        "collections": ["feature_films"], "playbackVerified": True,
        "playbackCheckedAt": "2026-09-20", "hasRealArtwork": True, "synopsisSource": "tmdb"}
owed = {**base, "archiveID": "a", "copyrightChecked": "2026-09-30", "copyrightRule": 4,
        "copyrightCheckedFor": "White Zombie|1932"}
asked = {**owed, "archiveID": "b", "copyrightRule": C.CCE_RULE}
hidden = {**owed, "archiveID": "c", "excluded": True}
assert "renewal" in R.owed(owed, today), R.owed(owed, today)
assert "renewal" not in R.owed(asked, today), R.owed(asked, today)
assert not R.served(hidden)
assert R.owed(asked, today) == [], R.owed(asked, today)
spine = {**asked, "archiveID": "d", "contentType": "tv-series", "playbackVerified": None,
         "downloadURL": None}
assert "playback" not in R.owed(spine, today), R.owed(spine, today)
film_unverified = {**asked, "archiveID": "e", "playbackVerified": None}
assert "playback" in R.owed(film_unverified, today), "control: an unverified film owes playback"
print("coverage_report: ok")
