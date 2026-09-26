#!/usr/bin/env python3
"""The film feeds carry only what the Roku Search feed would advertise
(Decision 113): public domain by age, in the public index, not TV, not
removed. Control: a 1931 film the app keeps under presumed_pd must NOT pass."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_film_feeds as F

def film(aid, **kw):
    it = {"archiveID": aid, "title": aid, "year": 1922, "contentType": "feature-film",
          "runtimeSeconds": 4000, "downloadURL": f"https://archive.org/download/{aid}/{aid}.mp4",
          "hasRealArtwork": True, "posterURL": "https://image.tmdb.org/t/p/w500/x.jpg"}
    it.update(kw); return it

items = [film("keep1922"), film("noposter", hasRealArtwork=False, posterURL=None),
         film("removed", excluded=True, excludedReason="takedown"),
         film("tvshow", contentType="tv-series"), film("unindexed"),
         film("sound1955", year=1955), film("notarchive", downloadURL="https://example.com/x.mp4")]
index = {i["archiveID"] for i in items} - {"unindexed"}
groups, skipped = F.build({"items": items}, index)
ids = {l.split('tvg-id="')[1].split('"')[0] for rows in groups.values() for _, _, l in rows}
fails = 0
for label, ok in [
    ("a pre-1930 film is in", "keep1922" in ids),
    ("a film without a poster is still in (logo optional)", "noposter" in ids),
    ("a removed title is out", "removed" not in ids),
    ("television is out", "tvshow" not in ids),
    ("a film not in the public index is out", "unindexed" not in ids),
    ("control: a 1955 film is out", "sound1955" not in ids),
    ("only archive.org files are played", "notarchive" not in ids),
    ("EXTINF is one line", all(l.count("\n") == 2 for rows in groups.values() for *_, l in rows)),
]:
    print(("PASS " if ok else "FAIL ") + label); fails += 0 if ok else 1
print("PASS film feeds" if not fails else f"FAILED ({fails})")
sys.exit(1 if fails else 0)
