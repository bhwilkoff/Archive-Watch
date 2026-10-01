"""An undated upload on likely_modern.json is hidden; the same item off the list
is kept as unknown_year (control); and a year found later is judged normally."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import audit_rights as A

A.likely_modern.ids = {"listed"}
base = {"title": "Popeye", "contentType": "feature-film", "collections": ["feature_films"],
        "imdbID": "tt0081353", "runtimeSeconds": 6840}
listed = {**base, "archiveID": "listed"}
other = {**base, "archiveID": "other"}
b, v = A.bucket(listed)
assert (b, v) == ("likely_modern_unidentified", "hide"), (b, v)
assert b in A.HIDE_BUCKETS
assert A.bucket(other)[0] == "unknown_year", A.bucket(other)
dated = {**listed, "year": 1980}
assert A.bucket(dated)[0] != "likely_modern_unidentified", A.bucket(dated)
print("likely_modern: ok")
