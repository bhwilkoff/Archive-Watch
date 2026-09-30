"""A title hidden only for want of a year is asked about renewals once a year
arrives; a title hidden for another reason is not (control)."""
import datetime as dt, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import corroborate_copyright as C

base = {"title": "Scrooge", "year": 1970, "contentType": "feature-film", "collections": ["feature_films"]}
dated = {**base, "archiveID": "a", "excluded": True, "rightsAudit": "no_evidence"}
other = {**base, "archiveID": "b", "excluded": True, "rightsAudit": "copyright_claim_evidence"}
got = {i["archiveID"] for i in C.targets([dated, other], dt.date(2026, 9, 30))}
assert "a" in got, f"a newly dated title was not asked: {got}"
assert "b" not in got, "a title hidden for another reason was asked"
print("claim_check_yearless: ok")
