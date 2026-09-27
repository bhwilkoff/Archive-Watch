#!/usr/bin/env python3
"""
harvest_member_lists.py — Collections made by archive.org members, in their
own words (ORPHANED-FILMS #1).

Owner, 2026-09-26: "I don't want AI making lists and writing copy. Any time we
can use metadata or user copy/categorization from archive.org." Orphaned
Films writes its lists and their notes with a model; archive.org's members
have already made film lists by hand ("Films of Yasujiro Ozu", "Pre and
post-war Japan through movies"). This brings those in as Collections:

  * WHO: members who favorited 20+ of our visible films (their `fav-<name>`
    collection is on the catalog items). Named lists are only reachable per
    member (`/services/users/@<name>/lists`); there is no global listing.
  * WHICH LISTS: public, a name, at least MIN_OURS of our visible films, and
    at least MIN_SHARE of the list ours — a list that is mostly music or
    books is not a film list with some films in it. Merged-away uploads count
    as their survivor (aliases.json). When two lists share most of their
    films, the larger stays.
  * WORDS: the list's name, verbatim, is the Collection's title; the blurb is
    the attribution and the member's own description, if they wrote one.
    Nothing is written for them.
  * ACCENT: the category most of the list's films carry (a rule, DECISIONS
    013's semantic colors).

Writes the `list-*` entries of shared/editorial/collection_metadata.json,
replacing only those; every other entry is untouched. The builders read
`members` (build_sqlite / build_catalog_index). A member lookup that fails
keeps that member's entries from the previous run, so a flaky night never
deletes a Collection.

    python3 tools/harvest_member_lists.py [--dry-run]
"""
from __future__ import annotations

import argparse
import collections
import concurrent.futures as cf
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
META = REPO / "shared" / "editorial" / "collection_metadata.json"
TOUCHUPS = REPO / "shared" / "editorial" / "collection_touchups.json"
MIN_FAVORITES = 20
MIN_OURS = 8
MIN_SHARE = 0.6
MAX_MEMBERS = 120
OVERLAP = 0.5
# Name rules, all mechanical. A list named for the maker's own queue ("to
# watch", "done", "dads #5") is bookkeeping, not curation; a list named only
# with genre, decade or format words ("Noir", "50's", "Silent Movies")
# repeats a Collection or a Browse filter we already have; a one-word name
# nobody else can read ("Matty", "Whatsit") needs the maker's description to
# say what it is.
PERSONAL = {"watch", "watched", "watching", "rewatch", "done", "todo", "queue",
            "later", "seen", "dads", "dad", "my", "mine", "playlist", "collection",
            "favorites", "favourites", "faves", "saved", "list"}
GENERIC = {"silent", "silents", "movie", "movies", "film", "films", "noir", "classic",
           "classics", "drama", "dramas", "comedy", "comedies", "mystery", "mysteries",
           "war", "historical", "history", "music", "musical", "cool", "cartoon",
           "cartoons", "old", "colorized", "public", "domain", "great", "all", "horror",
           "western", "westerns", "scifi", "sci", "fi", "cinema", "hollywood", "muets",
           "shorts", "short", "feature", "features", "vintage", "misc", "other", "and"}
DECADE = re.compile(r"^(\d{2,4}s?|\d{2}'?s)$")
UA = "ArchiveWatch/1.0 (+https://archivewatch.org; member lists)"

ACCENT = {
    "feature-film": "#FF5C35", "tv-series": "#2D5BFF", "silent-film": "#C9A66B",
    "animation": "#FF4D8D", "newsreel": "#8A8F98", "documentary": "#3FA796",
    "ephemeral": "#7C5BBA", "short-film": "#E8A317",
}


def fetch_lists(user: str) -> list | None:
    url = f"https://archive.org/services/users/@{urllib.parse.quote(user)}/lists"
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=20) as r:
                d = json.load(r)
            if d.get("success"):
                return d.get("value") or []
            return []          # "user does not exist" is an answer, not a failure
        except Exception:  # noqa: BLE001
            time.sleep(2 * (attempt + 1))
    return None


def slug(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:40]


def user_ok(user: str) -> bool:
    # A screen name that carries an email address is not published.
    return not re.search(r"(gmail|yahoo|hotmail|outlook|icloud|aol)(_com)?|_com$|@", user.lower())


def name_ok(name: str, desc: str) -> bool:
    words = [w for w in re.findall(r"[a-z0-9']+", name.lower().replace("\u2019", "'")) if w]
    if not words or any(w.strip("'") in PERSONAL for w in words):
        return False
    if all(w.strip("'") in GENERIC or DECADE.match(w.strip("'")) for w in words):
        return False
    if len(words) == 1 and not desc:
        return False
    return True


def select(user: str, lists: list, visible: dict, aliases: dict) -> list:
    out = []
    if not user_ok(user):
        return out
    for L in lists:
        name = (L.get("list_name") or "").strip()
        desc = re.sub(r"\s+", " ", (L.get("description") or "")).strip()
        if re.match(r"https?://", desc):
            desc = ""
        if L.get("is_private") or not name or len(name) > 60 or not name_ok(name, desc):
            continue
        ids = [m.get("identifier") for m in L.get("members") or [] if m.get("identifier")]
        ours, seen = [], set()
        for i in ids:
            i = aliases.get(i, i)
            if i in visible and i not in seen:
                seen.add(i)
                ours.append(i)
        if len(ours) < MIN_OURS or len(ours) < MIN_SHARE * len(ids) or len(ids) > MAX_MEMBERS:
            continue
        kinds = collections.Counter(visible[i] for i in ours)
        category = kinds.most_common(1)[0][0]
        credit = f"A list by {user} on archive.org."
        out.append({
            "id": f"list-{slug(user)}-{L.get('id')}",
            "title": name,
            "blurb": f"{credit} {desc}".strip() if desc else credit,
            "accent": ACCENT.get(category, "#FF5C35"),
            "category": category if category in ACCENT else "feature-film",
            "source": f"https://archive.org/details/@{user}/lists/{L.get('id')}",
            "members": ours,
        })
    return out


def tidy_name(name: str) -> str:
    """Mechanical only: runs of punctuation become one space, and a name
    written in capitals is title-cased (short words stay lower)."""
    name = re.sub(r"\s*([-_=*~|])\1{1,}\s*", " ", name).strip()
    letters = [c for c in name if c.isalpha()]
    if letters and all(c.isupper() for c in letters) and len(letters) > 3:
        small = {"a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to"}
        words = name.lower().split()
        name = " ".join(w if k and w in small else w[:1].upper() + w[1:] for k, w in enumerate(words))
    return name


def touch_up(entries: list, touchups: dict) -> list:
    """The owner-approved touch-ups (collection_touchups.json), then the
    mechanical name rule for anything not touched up by hand."""
    out = []
    for e in entries:
        t = touchups.get(e["id"], {})
        if t.get("hide"):
            continue
        e = dict(e)
        e["title"] = t.get("title") or tidy_name(e["title"])
        if "description" in t:
            credit = e["blurb"].split(" on archive.org.")[0] + " on archive.org."
            e["blurb"] = f"{credit} {t['description']}".strip()
        out.append(e)
    return out


def fold_overlaps(entries: list) -> list:
    kept = []
    for e in sorted(entries, key=lambda e: (-len(e["members"]), e["id"])):
        s = set(e["members"])
        if any(len(s & set(k["members"])) >= OVERLAP * min(len(s), len(k["members"])) for k in kept):
            continue
        kept.append(e)
    return kept


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--responses", help="saved {user: API answer} JSON instead of fetching (tests, reruns)")
    args = ap.parse_args()

    index = json.loads(Path(args.index).read_text(encoding="utf-8"))
    f = {n: i for i, n in enumerate(index["fields"])}
    visible = {r[f["id"]]: r[f["contentType"]] for r in index["items"]
               if r[f["contentType"]] not in ("tv-episode", "commercial")}
    aliases = json.loads((REPO / "aliases.json").read_text(encoding="utf-8"))
    catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))
    fav = collections.Counter()
    for it in catalog.get("items", []):
        if it.get("archiveID") in visible:
            for c in it.get("collections") or []:
                if str(c).startswith("fav-"):
                    fav[str(c)[4:]] += 1
    users = sorted(u for u, n in fav.items() if n >= MIN_FAVORITES)

    meta = json.loads(META.read_text(encoding="utf-8"))
    previous = [c for c in meta["collections"] if c["id"].startswith("list-")]
    entries, failed = [], 0
    if args.responses:
        saved = json.loads(Path(args.responses).read_text(encoding="utf-8"))
        answers = [(saved[u].get("value") or []) if u in saved and "error" not in saved[u] else None
                   for u in users]
    else:
        with cf.ThreadPoolExecutor(4) as ex:
            answers = list(ex.map(fetch_lists, users))
    if True:
        for user, lists in zip(users, answers):
            if lists is None:
                failed += 1
                entries += [c for c in previous if c["id"].startswith(f"list-{slug(user)}-")]
                continue
            entries += select(user, lists, visible, aliases)
    entries = fold_overlaps(entries)
    try:
        touchups = json.loads(TOUCHUPS.read_text(encoding="utf-8")).get("lists") or {}
    except FileNotFoundError:
        touchups = {}
    entries = touch_up(entries, touchups)
    entries.sort(key=lambda e: (-len(e["members"]), e["id"]))
    print(f"[member-lists] {len(users)} members asked, {failed} unreachable; "
          f"{len(entries)} lists: " + "; ".join(f"{e['title']} ({len(e['members'])})" for e in entries))
    if failed > len(users) // 2:
        print("[member-lists] refusing: most lookups failed", file=sys.stderr)
        return 1
    if args.dry_run:
        return 0
    META.write_text(rewrite(META.read_text(encoding="utf-8"), entries), encoding="utf-8")
    json.loads(META.read_text(encoding="utf-8"))
    return 0


def rewrite(text: str, entries: list) -> str:
    """The file is laid out by hand, one entry per line; replace only the
    `list-*` lines and leave every other byte where it was."""
    lines = [ln for ln in text.split("\n") if '"id": "list-' not in ln]
    end = max(i for i, ln in enumerate(lines) if ln.strip() == "]")
    last = max(i for i in range(end) if lines[i].strip().startswith("{"))
    lines[last] = lines[last].rstrip().rstrip(",") + ("," if entries else "")
    new = [f"    {json.dumps(e, ensure_ascii=False)}" + ("," if k < len(entries) - 1 else "")
           for k, e in enumerate(entries)]
    return "\n".join(lines[:last + 1] + new + lines[last + 1:])


if __name__ == "__main__":
    sys.exit(main())
