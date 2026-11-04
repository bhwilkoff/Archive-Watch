#!/usr/bin/env python3
"""Keep looking for the year of every series that has none (Decision 178).

A series with no year cannot pass the rights audit, so it stays hidden however
good it is. Owner, 2026-11-04: "We should be constantly searching for that
information and making sure that everything that can be displayed in the app is
displayed." This runs in every TV rebuild and writes what it finds, with where it
found it, to shared/editorial/series_years.json; remediate puts it on the card.

Evidence, strongest first: an episode's own air date, TVmaze on an exact title,
and the show's own overview saying when it aired. A year is never taken from a
same-named film: that is how Columbia's 1941 The Iron Claw came to read 1916. An
entry marked "reviewed" is a person's and is never replaced. What cannot be found
is recorded and asked again after RECHECK_DAYS.
"""
import datetime as dt
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TABLE = REPO / "shared/editorial/series_years.json"
RECHECK_DAYS = 30
TVMAZE = "https://api.tvmaze.com/singlesearch/shows?q="
UA = "ArchiveWatch/1.0 (https://archivewatch.org)"
FIRST_TV, LAST = 1928, dt.date.today().year

_AIRED = re.compile(r"\b(?:aired|broadcast|premiered|ran|debuted|first shown|from|in)\b[^.]{0,40}?\b(19[2-9]\d|20[0-2]\d)\b", re.I)


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def episodes(spine):
    return [e for s in spine.get("seasons") or [] for e in s.get("episodes") or []]


def from_air_dates(spine):
    years = [int(e["airDate"][:4]) for e in episodes(spine)
             if re.match(r"\d{4}", str(e.get("airDate") or ""))]
    return min(years) if years else None


def from_overview(spine):
    m = _AIRED.search(spine.get("overview") or "")
    return int(m.group(1)) if m else None


def from_tvmaze(title, fetch):
    show = fetch(title)
    if not show or norm(show.get("name")) != norm(title):
        return None, None
    m = re.match(r"(\d{4})", str(show.get("premiered") or ""))
    return (int(m.group(1)), show.get("url")) if m else (None, None)


def tvmaze_fetch(title):
    req = urllib.request.Request(TVMAZE + urllib.parse.quote(title), headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


def find(spine, fetch):
    """{year, how, source}, or None if nothing vouches for one."""
    y = from_air_dates(spine)
    if y:
        return {"year": y, "how": "air date", "source": None}
    y, url = from_tvmaze(spine.get("title"), fetch)
    if y:
        return {"year": y, "how": "tvmaze", "source": url}
    y = from_overview(spine)
    if y:
        return {"year": y, "how": "overview", "source": None}
    return None


def needs_year(spine, entry):
    if entry and (entry.get("how") == "reviewed" or entry.get("year")):
        return False
    if spine.get("tvmazeID") and spine.get("yearStart"):
        return False           # TVmaze's own premiere: this is the evidence
    return not spine.get("sourceID")


def run(repo=REPO, fetch=tvmaze_fetch, today=None):
    today = today or dt.date.today()
    path = repo / "shared/editorial/series_years.json"
    table = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    found = unknown = errors = 0
    for f in sorted((repo / "series").glob("*.json")):
        spine = json.loads(f.read_text(encoding="utf-8"))
        slug = spine.get("seriesID") or f.stem
        entry = table.get(slug)
        if not needs_year(spine, entry):
            continue
        if entry and entry.get("checked"):
            age = (today - dt.date.fromisoformat(entry["checked"])).days
            if age < RECHECK_DAYS:
                unknown += 1
                continue
        try:
            hit = find(spine, fetch)
            time.sleep(0.3 if fetch is tvmaze_fetch else 0)
        except Exception as e:  # noqa: BLE001  a failed search is not a verdict
            print(f"  {slug}: could not ask ({str(e)[:60]})")
            errors += 1
            continue
        if hit and FIRST_TV <= hit["year"] <= LAST:
            table[slug] = {k: v for k, v in hit.items() if v is not None}
            found += 1
        else:
            table[slug] = {"year": None, "checked": today.isoformat()}
            unknown += 1
    path.write_text(json.dumps(table, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[series years] {found} found, {unknown} still unknown, {errors} could not be asked")
    return found, unknown, errors


if __name__ == "__main__":
    _, _, err = run()
    if err:
        print(f"::warning::{err} series could not be asked; the next run asks again")
    sys.exit(0)
