"""A year a person set survives the B&W-and-modern wrong-match rule; the same
item with the match's year is still cleared (control)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import remediate_catalog as R

base = {"archiveID": "InvasionOfTheBeeGirls", "title": "Invasion of the Bee Girls",
        "contentType": "feature-film", "artworkSource": "tmdb", "colorMode": "bw",
        "year": 1973, "decade": 1970, "posterURL": "https://image.tmdb.org/x.jpg"}
hand = {**base, "yearSource": "agent-reviewed"}
assert R.fix_wrong_external_matches(hand) is None and hand["year"] == 1973, hand
match = dict(base)
R.fix_wrong_external_matches(match)
assert match["year"] is None, f"control: the match's modern year on a B&W copy should clear: {match['year']}"
print("hand_year_survives: ok")
