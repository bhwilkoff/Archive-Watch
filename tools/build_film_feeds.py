#!/usr/bin/env python3
"""
build_film_feeds.py — Archive Watch for the IPTV players we will never build
an app for (UHF, TiviMate, IPTV Smarters, VLC, Kodi, Jellyfin, Plex).

Orphaned Films research #3. Owner rule: this lives on ONE page of the website
(/feeds/) and nowhere in any app. Owner, 2026-09-27: "Let's simplify and make a
single link for all categories of video and the live tv. We can still have a
separate live tv link, but having the different category feeds doesn't make
sense since you can open up the different categories from within the playlist.
Also, I noticed the information about the films isn't coming through on the
playlist."

WHAT A PLAYER CAN READ (researched 2026-09-27, docs/research/IPTV-FEEDS.md):
an M3U entry carries a title, a poster (tvg-logo), a group (group-title) and a
length, and nothing else any player reads — no synopsis, cast or rating. Film
details reach players two ways, so both are published:
  * the XMLTV guide, for the channels: every programme carries its synopsis,
    year, genres, director, cast, poster and rating;
  * the Xtream API (served by the Worker, worker/src/xtream.js, from the JSON
    written here), which UHF, TiviMate and IPTV Smarters read for a Movies
    section with plot, cast, director, rating and backdrop.

Files (/feeds/):
  archivewatch.m3u   everything: the channels first, then every film, grouped
                     by kind — ONE address to add
  live.m3u           the channels only
  guide.xml          XMLTV for the channels (the one UTC clock, Decision 144)
  films.m3u          the same as archivewatch.m3u, for players added before
                     2026-09-27 (not listed on the page)
  xtream/*.json      the Xtream API's data
  manifest.json      counts, for the deploy's floor check

WHICH FILMS: exactly what the Roku Search feed advertises (Decision 113) —
`build_roku_search_feed.eligibility` at the `guaranteed` tier, public domain by
AGE — because a list handed to another company's app is a list we call free to
watch. A CHANNEL plays what the apps' Channels play (Decision 144), through
the Worker's /live/<channel>, which joins the film at the second it has
reached.

    python3 tools/build_film_feeds.py --out _site
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_roku_search_feed import KIND, eligibility  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
FEED_DIR = "feeds"
FLOOR = 1000
SITE = "https://archivewatch.org"
WORKER = "https://archivewatch-pulse.benwilkoff.workers.dev"
GUIDE = f"{SITE}/feeds/guide.xml"
LIVE_GROUP = "Live Channels"
INFO_SHARDS = 256
# Group names a viewer reads in the player: plural, like a store's shelves.
GROUP = {
    "Feature film": "Feature Films", "Silent film": "Silent Films",
    "Short film": "Short Films", "Animated film": "Animated Films",
    "Television special": "Television", "Newsreel": "Newsreels",
    "Documentary": "Documentaries", "Ephemeral film": "Ephemeral Films",
    "Home movie": "Home Movies", "Film": "Films",
}


def clean(s) -> str:
    # EXTINF is one line, and a comma ends its attribute list.
    return re.sub(r"\s+", " ", str(s or "")).replace('"', "'").strip()


def stream_id(archive_id: str) -> int:
    """A stable integer for the Xtream API, which numbers its streams: the
    same film keeps its number across builds, so a player's favorites hold."""
    return int(hashlib.sha1(archive_id.encode()).hexdigest()[:7], 16) + 1000


def label(item: dict) -> str:
    title = clean(item.get("title"))
    return f"{title} ({item['year']})" if item.get("year") else title


def group(item: dict) -> str:
    return GROUP.get(KIND.get(item.get("contentType"), "Film"), "Films")


def poster(item: dict) -> str | None:
    return item.get("posterURL") if item.get("hasRealArtwork") else None


def films(catalog: dict, index_ids: set) -> tuple[list, collections.Counter]:
    out, skipped = [], collections.Counter()
    for item in catalog.get("items", []):
        why = eligibility(item, index_ids, "guaranteed", "any")
        if why == "no_poster":
            why = None       # a poster is optional in a playlist
        if why:
            skipped[why.split(":")[0]] += 1
            continue
        if not (item.get("downloadURL") or "").startswith("https://archive.org/download/"):
            skipped["no_archive_file"] += 1
            continue
        out.append(item)
    out.sort(key=lambda i: (group(i), -(i.get("popularityScore") or 0), i.get("title") or ""))
    return out, skipped


def film_entry(item: dict) -> str:
    attrs = [f'tvg-id="{clean(item["archiveID"])}"', f'tvg-name="{label(item)}"',
             'tvg-type="movie"', f'group-title="{group(item)}"']
    if poster(item):
        attrs.append(f'tvg-logo="{clean(poster(item))}"')
    secs = int(item.get("runtimeSeconds") or -1)
    return f"#EXTINF:{secs} {' '.join(attrs)},{label(item)}\n{item['downloadURL']}\n"


def channel_entry(ch: dict, number: int) -> str:
    attrs = [f'tvg-id="{ch["id"]}.archivewatch.org"', f'tvg-name="{clean(ch["title"])}"',
             f'tvg-chno="{number}"', f'tvg-logo="{SITE}/assets/app-icon/app-icon.png"',
             f'group-title="{LIVE_GROUP}"']
    return f"#EXTINF:-1 {' '.join(attrs)},{clean(ch['title'])}\n{WORKER}/live/{ch['id']}\n"


def header() -> str:
    return f'#EXTM3U x-tvg-url="{GUIDE}" url-tvg="{GUIDE}"\n'


def credits_xml(item: dict | None) -> str:
    if not item:
        return ""
    parts = []
    if item.get("director"):
        parts.append(f"<director>{escape(item['director'])}</director>")
    for c in (item.get("cast") or [])[:6]:
        if c.get("name"):
            parts.append(f"<actor>{escape(c['name'])}</actor>")
    return f"<credits>{''.join(parts)}</credits>" if parts else ""


def guide(schedule: dict, by_id: dict) -> str:
    def stamp(t: int) -> str:
        return datetime.fromtimestamp(t, timezone.utc).strftime("%Y%m%d%H%M%S +0000")

    out = ['<?xml version="1.0" encoding="UTF-8"?>\n',
           f'<tv generator-info-name="Archive Watch" generator-info-url="{SITE}/">\n']
    for ch in schedule["channels"]:
        out.append(f'  <channel id={quoteattr(ch["id"] + ".archivewatch.org")}>'
                   f'<display-name>{escape(ch["title"])}</display-name>'
                   f'<icon src="{SITE}/assets/app-icon/app-icon.png"/>'
                   f'<url>{SITE}/#/channels</url></channel>\n')
    for ch in schedule["channels"]:
        cid = quoteattr(ch["id"] + ".archivewatch.org")
        for key in sorted(ch["days"]):
            day = ch["days"][key]
            t = day["start"]
            for pid, secs in day["slots"]:
                prog = schedule["programs"].get(pid)
                item = by_id.get(pid)
                if prog:
                    # XMLTV's DTD fixes the child order: title, desc,
                    # credits, date, category, icon, url, star-rating.
                    x = [f'  <programme start="{stamp(t)}" stop="{stamp(t + secs)}" channel={cid}>',
                         f"<title>{escape((item or {}).get('title') or prog[0])}</title>"]
                    if item and item.get("synopsis"):
                        x.append(f"<desc>{escape(item['synopsis'])}</desc>")
                    x.append(credits_xml(item))
                    if item and item.get("year"):
                        x.append(f"<date>{item['year']}</date>")
                    for g in (item or {}).get("genres") or []:
                        x.append(f"<category>{escape(g)}</category>")
                    if item and poster(item):
                        x.append(f"<icon src={quoteattr(poster(item))}/>")
                    x.append(f"<url>{SITE}/item/{escape(pid)}</url>")
                    if item and item.get("imdbRating"):
                        x.append(f'<star-rating system="IMDb"><value>{item["imdbRating"]}/10</value></star-rating>')
                    x.append("</programme>\n")
                    out.append("".join(x))
                t += secs + schedule["gap"]
    out.append("</tv>\n")
    return "".join(out)


def xtream(items: list, schedule: dict, out: Path) -> None:
    """The Xtream API's data. The Worker answers player_api.php from these
    files and adds nothing of its own."""
    x = out / "xtream"
    (x / "info").mkdir(parents=True, exist_ok=True)
    groups = sorted({group(i) for i in items})
    cat = {g: str(k + 1) for k, g in enumerate(groups)}
    (x / "vod_categories.json").write_text(json.dumps(
        [{"category_id": cat[g], "category_name": g, "parent_id": 0} for g in groups]))
    streams, shards = [], collections.defaultdict(dict)
    for n, i in enumerate(items):
        sid = stream_id(i["archiveID"])
        rating = i.get("imdbRating") or 0
        cast = ", ".join(c["name"] for c in (i.get("cast") or [])[:10] if c.get("name"))
        streams.append({
            "num": n + 1, "name": label(i), "stream_type": "movie", "stream_id": sid,
            "stream_icon": poster(i) or "", "rating": str(rating),
            "rating_5based": round(rating / 2, 1), "added": "0",
            "category_id": cat[group(i)], "container_extension": "mp4",
            "custom_sid": "", "direct_source": i["downloadURL"],
        })
        secs = int(i.get("runtimeSeconds") or 0)
        shards[sid % INFO_SHARDS][str(sid)] = {
            "info": {
                "name": i.get("title") or "", "o_name": i.get("title") or "",
                "plot": i.get("synopsis") or "", "description": i.get("synopsis") or "",
                "cast": cast, "actors": cast, "director": i.get("director") or "",
                "genre": ", ".join(i.get("genres") or []),
                "releasedate": i.get("releaseDate") or (str(i["year"]) if i.get("year") else ""),
                "year": str(i.get("year") or ""),
                "rating": str(rating), "duration_secs": secs,
                "duration": f"{secs // 3600:02d}:{secs // 60 % 60:02d}:{secs % 60:02d}",
                "movie_image": poster(i) or "", "cover_big": poster(i) or "",
                "backdrop_path": [i["backdropURL"]] if i.get("backdropURL") else [],
                "tmdb_id": str(i.get("tmdbID") or ""),
                "country": ", ".join(i.get("countries") or []), "youtube_trailer": "",
            },
            "movie_data": {
                "stream_id": sid, "name": label(i), "added": "0",
                "category_id": cat[group(i)], "container_extension": "mp4",
                "custom_sid": "", "direct_source": i["downloadURL"],
            },
            "url": i["downloadURL"],
        }
    ids = [s["stream_id"] for s in streams]
    if len(ids) != len(set(ids)):
        raise SystemExit("[film-feeds] two films share an Xtream stream id — widen stream_id()")
    (x / "vod_streams.json").write_text(json.dumps(streams, ensure_ascii=False, separators=(",", ":")))
    for k in range(INFO_SHARDS):
        (x / "info" / f"{k}.json").write_text(
            json.dumps(shards.get(k, {}), ensure_ascii=False, separators=(",", ":")))
    (x / "live_categories.json").write_text(json.dumps(
        [{"category_id": "1", "category_name": LIVE_GROUP, "parent_id": 0}]))
    (x / "live_streams.json").write_text(json.dumps([
        {"num": n + 1, "name": ch["title"], "stream_type": "live", "stream_id": n + 1,
         "stream_icon": f"{SITE}/assets/app-icon/app-icon.png",
         "epg_channel_id": f"{ch['id']}.archivewatch.org", "added": "0",
         "category_id": "1", "custom_sid": "", "tv_archive": 0, "direct_source": "",
         "tv_archive_duration": 0, "channel": ch["id"]}
        for n, ch in enumerate(schedule["channels"])], separators=(",", ":")))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--catalog", default=str(REPO / "catalog.json"))
    ap.add_argument("--index", default=str(REPO / "catalog-index.json"))
    ap.add_argument("--schedule", default=str(REPO / "channel-schedule.json"))
    ap.add_argument("--out", default=str(REPO / "_site"))
    args = ap.parse_args()
    catalog = json.loads(Path(args.catalog).read_text(encoding="utf-8"))
    index = json.loads(Path(args.index).read_text(encoding="utf-8"))
    index_ids = {row[0] for row in index.get("items", [])}
    schedule = json.loads(Path(args.schedule).read_text(encoding="utf-8"))
    by_id = {i["archiveID"]: i for i in catalog.get("items", [])}

    items, skipped = films(catalog, index_ids)
    out = Path(args.out) / FEED_DIR
    out.mkdir(parents=True, exist_ok=True)
    live = "".join(channel_entry(ch, n + 1) for n, ch in enumerate(schedule["channels"]))
    everything = header() + live + "".join(film_entry(i) for i in items)
    (out / "archivewatch.m3u").write_text(everything, encoding="utf-8")
    (out / "films.m3u").write_text(everything, encoding="utf-8")
    (out / "live.m3u").write_text(header() + live, encoding="utf-8")
    (out / "guide.xml").write_text(guide(schedule, by_id), encoding="utf-8")
    xtream(items, schedule, out)
    kinds = collections.Counter(group(i) for i in items)
    (out / "manifest.json").write_text(json.dumps(
        {"films": len(items), "channels": len(schedule["channels"]), "groups": kinds,
         "tier": "guaranteed"}, indent=1), encoding="utf-8")
    print(f"[film-feeds] {len(items)} films in {len(kinds)} groups + "
          f"{len(schedule['channels'])} channels; left out: {dict(skipped)}")
    if len(items) < FLOOR:
        print(f"[film-feeds] refusing: {len(items)} films is under the floor of {FLOOR}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
