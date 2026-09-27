#!/usr/bin/env python3
"""
build_film_feeds.py — M3U playlists of our films, for the media players we
will never build an app for (VLC, Kodi, Jellyfin, Plex, Infuse, TiviMate).

Orphaned Films research #3 (2026-09-26). Owner rule: this lives on ONE page of
the website's documentation (/feeds/) and nowhere in any app — finding and
playing films in Archive Watch is the core, and a feed is a side door.

WHAT GOES IN is exactly what the Roku Search feed advertises (Decision 113),
because a feed is a list we hand to a third party as free to watch:
`build_roku_search_feed.eligibility` at the `guaranteed` tier — public domain
by AGE, in the public index, not television, not a commercial, not removed —
with any art (an M3U logo is a thumbnail, not an advertisement). Each entry
plays the film's own file on archive.org; Archive Watch hosts no video.

/feeds/guide.xml is an XMLTV guide to Archive Watch's channels, read from
channel-schedule.json — the one UTC clock every app plays from (owner,
2026-09-27; ORPHANED-FILMS #2). Times are written in UTC, which every guide
reader shows in its own zone; each programme links to the film's page.

Files: /feeds/films.m3u (everything), /feeds/<kind>.m3u per kind of 100 or
more (the same KIND words the Roku feed uses), /feeds/manifest.json (counts, for the
deploy's floor check and the page).

    python3 tools/build_film_feeds.py --out _site
"""
from __future__ import annotations

import argparse
import collections
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_roku_search_feed import KIND, eligibility  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FEED_DIR = "feeds"
FLOOR = 1000
# A kind gets a playlist of its own only when it is big enough to be worth
# choosing; the rest are in films.m3u under their group title.
KIND_FILE_MIN = 100


def slug(kind_label: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", kind_label.lower()).strip("-")


def clean(s) -> str:
    # EXTINF is one line, and a comma ends its attribute list.
    return re.sub(r"\s+", " ", str(s or "")).replace('"', "'").strip()


def entry(item: dict) -> str | None:
    url = item.get("downloadURL") or ""
    if not url.startswith("https://archive.org/download/"):
        return None
    kind = KIND.get(item.get("contentType"), "Film")
    title = clean(item.get("title"))
    label = f"{title} ({item['year']})" if item.get("year") else title
    attrs = [f'tvg-id="{clean(item["archiveID"])}"', f'group-title="{kind}"']
    if item.get("hasRealArtwork") and item.get("posterURL"):
        attrs.append(f'tvg-logo="{clean(item["posterURL"])}"')
    secs = int(item.get("runtimeSeconds") or -1)
    return f"#EXTINF:{secs} {' '.join(attrs)},{label}\n{url}\n"


def build(catalog: dict, index_ids: set) -> tuple[dict, collections.Counter]:
    """kind label -> [(popularity, line)], and why the rest were left out."""
    groups, skipped = collections.defaultdict(list), collections.Counter()
    for item in catalog.get("items", []):
        why = eligibility(item, index_ids, "guaranteed", "any")
        if why == "no_poster":
            why = None       # a thumbnail is optional in a playlist
        if why:
            skipped[why.split(":")[0]] += 1
            continue
        line = entry(item)
        if not line:
            skipped["no_archive_file"] += 1
            continue
        kind = KIND.get(item.get("contentType"), "Film")
        groups[kind].append((-(item.get("popularityScore") or 0), item.get("title") or "", line))
    return groups, skipped


def guide(schedule: dict, years: dict) -> str:
    from datetime import datetime, timezone
    from xml.sax.saxutils import escape, quoteattr

    def stamp(t: int) -> str:
        return datetime.fromtimestamp(t, timezone.utc).strftime("%Y%m%d%H%M%S +0000")

    out = ['<?xml version="1.0" encoding="UTF-8"?>\n',
           '<tv generator-info-name="Archive Watch" generator-info-url="https://archivewatch.org/">\n']
    for ch in schedule["channels"]:
        out.append(f'  <channel id={quoteattr(ch["id"] + ".archivewatch.org")}>'
                   f'<display-name>{escape(ch["title"])}</display-name>'
                   f'<url>https://archivewatch.org/#/channels</url></channel>\n')
    for ch in schedule["channels"]:
        cid = quoteattr(ch["id"] + ".archivewatch.org")
        for key in sorted(ch["days"]):
            day = ch["days"][key]
            t = day["start"]
            for pid, secs in day["slots"]:
                prog = schedule["programs"].get(pid)
                if prog:
                    year = years.get(pid)
                    out.append(
                        f'  <programme start="{stamp(t)}" stop="{stamp(t + secs)}" channel={cid}>'
                        f'<title>{escape(prog[0])}</title>'
                        + (f"<date>{year}</date>" if year else "")
                        + f"<url>https://archivewatch.org/item/{escape(pid)}</url></programme>\n")
                t += secs + schedule["gap"]
    out.append("</tv>\n")
    return "".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--out", default=str(REPO / "_site"))
    args = ap.parse_args()
    catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))
    index = json.loads(Path(args.index).read_text(encoding="utf-8"))
    index_ids = {row[0] for row in index.get("items", [])}

    groups, skipped = build(catalog, index_ids)
    out = Path(args.out) / FEED_DIR
    out.mkdir(parents=True, exist_ok=True)
    head = "#EXTM3U\n"
    counts, everything = {}, []
    for kind, rows in sorted(groups.items()):
        rows.sort()
        lines = [r[2] for r in rows]
        everything += rows
        counts[kind] = {"films": len(lines)}
        if len(lines) >= KIND_FILE_MIN:
            name = f"{slug(kind)}.m3u"
            (out / name).write_text(head + "".join(lines), encoding="utf-8")
            counts[kind]["file"] = name
    everything.sort()
    (out / "films.m3u").write_text(head + "".join(r[2] for r in everything), encoding="utf-8")
    total = len(everything)
    (out / "manifest.json").write_text(json.dumps(
        {"films": total, "kinds": counts, "tier": "guaranteed"}, indent=1), encoding="utf-8")
    print(f"[film-feeds] {total} films in {len(counts)} kinds; left out: {dict(skipped)}")
    sched_path = REPO / "channel-schedule.json"
    if sched_path.exists():
        schedule = json.loads(sched_path.read_text(encoding="utf-8"))
        years = {i["archiveID"]: i["year"] for i in catalog.get("items", []) if i.get("year")}
        (out / "guide.xml").write_text(guide(schedule, years), encoding="utf-8")
        print(f"[film-feeds] guide.xml: {len(schedule['channels'])} channels")
    else:
        print("[film-feeds] no channel-schedule.json — guide.xml not written", file=sys.stderr)
        return 1
    if total < FLOOR:
        print(f"[film-feeds] refusing: {total} films is under the floor of {FLOOR}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
