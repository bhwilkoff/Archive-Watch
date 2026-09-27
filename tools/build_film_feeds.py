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

WHICH TITLES: everything the apps show (Decision 145). Owner, 2026-09-27, on
the first feeds, which carried only the Roku feed's public-domain-by-age tier:
"the Xtream feed has a much smaller selection, very few items in each category,
and the tv shows are not separated into 'series' as apps like UHF expect." So
the films are every film in the served index (the gate every client reads:
the rights audit, takedowns, the mature filter), and television is every
series spine with the episodes the served episode index carries. A CHANNEL
plays what the apps' Channels play (Decision 144), through the Worker's
/live/<channel>, which joins the film at the second it has reached.

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
from build_roku_search_feed import KIND  # noqa: E402

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


def label(item: dict) -> str:
    title = clean(item.get("title"))
    return f"{title} ({item['year']})" if item.get("year") else title


def group(item: dict) -> str:
    """One category per film (the Xtream API allows one). Documentary is the
    GENRE for features, shorts and silents, as in the apps' own Documentary
    category (contentType "documentary" held four films); ephemeral films and
    newsreels keep their own categories, and home movies sit with the
    ephemeral films rather than in a category of 53."""
    ctype = item.get("contentType")
    if ctype in ("feature-film", "short-film", "silent-film", "documentary") and \
            "Documentary" in (item.get("genres") or []):
        return "Documentaries"
    if ctype == "home-movie":
        return "Ephemeral Films"
    return GROUP.get(KIND.get(ctype, "Film"), "Films")


def poster(item: dict) -> str | None:
    return item.get("posterURL") if item.get("hasRealArtwork") else None


NOT_FILMS = {"tv-series", "tv-episode", "commercial", "excerpt"}


def films(catalog: dict, index_ids: set) -> tuple[list, collections.Counter]:
    out, skipped = [], collections.Counter()
    for item in catalog.get("items", []):
        if item.get("archiveID") not in index_ids:
            skipped["not_in_public_index"] += 1
            continue
        if item.get("contentType") in NOT_FILMS:
            skipped[item.get("contentType")] += 1
            continue
        if not (item.get("downloadURL") or "").startswith("https://archive.org/download/"):
            skipped["no_archive_file"] += 1
            continue
        out.append(item)
    out.sort(key=lambda i: (group(i), -(i.get("popularityScore") or 0), i.get("title") or ""))
    return out, skipped


def series_list(repo: Path, episodes_index: dict) -> list:
    """Every series spine, with only the episodes the served episode index
    carries (the TV rights audit's gate, Decision 140's television half)."""
    f = {n: i for i, n in enumerate(episodes_index["fields"])}
    served = collections.defaultdict(set)
    for row in episodes_index["episodes"]:
        served[row[f["slug"]]].add(row[f["archiveID"]])
    out = []
    for slug in sorted(served):
        path = repo / "series" / f"{slug}.json"
        if not path.exists():
            continue
        spine = json.loads(path.read_text(encoding="utf-8"))
        eps = []
        for season in spine.get("seasons") or []:
            for e in season.get("episodes") or []:
                if e.get("archiveID") in served[slug] and \
                        (e.get("downloadURL") or "").startswith("https://archive.org/download/"):
                    eps.append(e)
        if eps:
            spine["slug"] = slug
            spine["served"] = eps
            out.append(spine)
    return out


def number_ids(keys: list) -> dict:
    """Stable integers for the Xtream API, which numbers its streams and whose
    players often hold them in a 32-bit int: a hash of the id, and on the rare
    collision the next free number, in id order so the result is repeatable."""
    taken, out = set(), {}
    for k in sorted(keys):
        n = int(hashlib.sha1(k.encode()).hexdigest()[:8], 16) % 2_000_000_000 + 1000
        while n in taken:
            n += 1
        taken.add(n)
        out[k] = n
    return out


def episode_order(spine: dict) -> list:
    """(season, episode, item) with numbers for every episode: the spine's own
    where it has them, else in the spine's order within season 1."""
    out, counter = [], collections.Counter()
    for e in spine["served"]:
        season = e.get("seasonNumber") or 1
        counter[season] += 1
        out.append((season, e.get("episodeNumber") or counter[season], e))
    return out


def episode_name(spine: dict, season: int, number: int, e: dict) -> str:
    title = clean(e.get("title"))
    base = f"{clean(spine['title'])} S{season:02d}E{number:02d}"
    return f"{base} {title}" if title and title != clean(spine["title"]) else base


def episode_entry(spine: dict, season: int, number: int, e: dict) -> str:
    art = e.get("stillURL") or spine.get("posterURL")
    attrs = [f'tvg-id="{clean(e["archiveID"])}"', f'tvg-name="{episode_name(spine, season, number, e)}"',
             'tvg-type="series"', f'tvg-serie="{clean(spine["title"])}"',
             f'tvg-season="{season}"', f'tvg-episode="{number}"',
             f'group-title="{clean(spine["title"])}"']
    if art:
        attrs.append(f'tvg-logo="{clean(art)}"')
    secs = int(e.get("runtimeSeconds") or -1)
    return f"#EXTINF:{secs} {' '.join(attrs)},{episode_name(spine, season, number, e)}\n{e['downloadURL']}\n"


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


def hms(secs: int) -> str:
    return f"{secs // 3600:02d}:{secs // 60 % 60:02d}:{secs % 60:02d}"


def cast_names(people, n=10) -> str:
    return ", ".join(c["name"] for c in (people or [])[:n] if c.get("name"))


def write_json(path: Path, body) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(body, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")


def xtream(items: list, shows: list, schedule: dict, out: Path) -> dict:
    """The Xtream API's data, laid out so the Worker PASSES FILES THROUGH
    rather than parsing them (the free Worker has ~10 ms of CPU a request):
    whole lists and per-category lists are separate files, and the lookups
    (a film's details, an episode's address) are small shards."""
    x = out / "xtream"
    # -- films
    groups = sorted({group(i) for i in items})
    cat = {g: str(k + 1) for k, g in enumerate(groups)}
    write_json(x / "vod_categories.json",
               [{"category_id": cat[g], "category_name": g, "parent_id": 0} for g in groups])
    ids = number_ids([i["archiveID"] for i in items])
    streams, by_cat, shards = [], collections.defaultdict(list), collections.defaultdict(dict)
    for n, i in enumerate(items):
        sid = ids[i["archiveID"]]
        rating = i.get("imdbRating") or 0
        row = {"num": n + 1, "name": label(i), "stream_type": "movie", "stream_id": sid,
               "stream_icon": poster(i) or "", "rating": str(rating),
               "rating_5based": round(rating / 2, 1), "added": "0",
               "category_id": cat[group(i)], "container_extension": "mp4",
               "custom_sid": "", "direct_source": ""}
        streams.append(row)
        by_cat[row["category_id"]].append(row)
        secs = int(i.get("runtimeSeconds") or 0)
        shards[sid % INFO_SHARDS][str(sid)] = {
            "info": {
                "name": i.get("title") or "", "o_name": i.get("title") or "",
                "plot": i.get("synopsis") or "", "description": i.get("synopsis") or "",
                "cast": cast_names(i.get("cast")), "actors": cast_names(i.get("cast")),
                "director": i.get("director") or "", "genre": ", ".join(i.get("genres") or []),
                "releasedate": i.get("releaseDate") or (str(i["year"]) if i.get("year") else ""),
                "year": str(i.get("year") or ""), "rating": str(rating),
                "duration_secs": secs, "duration": hms(secs),
                "movie_image": poster(i) or "", "cover_big": poster(i) or "",
                "backdrop_path": [i["backdropURL"]] if i.get("backdropURL") else [],
                "tmdb_id": str(i.get("tmdbID") or ""),
                "country": ", ".join(i.get("countries") or []), "youtube_trailer": "",
            },
            "movie_data": {"stream_id": sid, "name": label(i), "added": "0",
                           "category_id": cat[group(i)], "container_extension": "mp4",
                           "custom_sid": "", "direct_source": ""},
            "url": i["downloadURL"],
        }
    write_json(x / "vod_streams.json", streams)
    for c, rows in by_cat.items():
        write_json(x / "vod_streams" / f"{c}.json", rows)
    for k in range(INFO_SHARDS):
        write_json(x / "info" / f"{k}.json", shards.get(k, {}))

    # -- television, as Series
    genres = sorted({(s.get("genres") or ["Television"])[0] for s in shows})
    scat = {g: str(k + 1) for k, g in enumerate(genres)}
    write_json(x / "series_categories.json",
               [{"category_id": scat[g], "category_name": g, "parent_id": 0} for g in genres])
    sids = number_ids([s["slug"] for s in shows])
    eids = number_ids([e["archiveID"] for s in shows for e in s["served"]])
    rows, by_scat, eshards = [], collections.defaultdict(list), collections.defaultdict(dict)
    for n, sp in enumerate(shows):
        sid = sids[sp["slug"]]
        g = (sp.get("genres") or ["Television"])[0]
        info = {"name": sp["title"], "title": sp["title"], "cover": sp.get("posterURL") or "",
                "plot": sp.get("overview") or "", "cast": cast_names(sp.get("cast")),
                "director": sp.get("creator") or "", "genre": ", ".join(sp.get("genres") or []),
                "releaseDate": str(sp.get("yearStart") or ""), "last_modified": "0",
                "rating": "0", "rating_5based": 0,
                "backdrop_path": [sp["backdropURL"]] if sp.get("backdropURL") else [],
                "youtube_trailer": "", "episode_run_time": "", "category_id": scat[g]}
        row = {"num": n + 1, "series_id": sid, **info}
        rows.append(row)
        by_scat[scat[g]].append(row)
        seasons, episodes = {}, collections.defaultdict(list)
        for season, number, e in episode_order(sp):
            eid = eids[e["archiveID"]]
            secs = int(e.get("runtimeSeconds") or 0)
            episodes[str(season)].append({
                "id": str(eid), "episode_num": number, "season": season,
                "title": episode_name(sp, season, number, e), "container_extension": "mp4",
                "info": {"movie_image": e.get("stillURL") or sp.get("posterURL") or "",
                         "plot": e.get("overview") or "", "releasedate": e.get("airDate") or "",
                         "duration_secs": secs, "duration": hms(secs)},
                "custom_sid": "", "added": "0", "direct_source": ""})
            seasons.setdefault(season, {"season_number": season, "name": f"Season {season}",
                                        "episode_count": 0, "id": season, "overview": "",
                                        "air_date": "", "cover": sp.get("posterURL") or "",
                                        "cover_big": sp.get("posterURL") or ""})
            seasons[season]["episode_count"] += 1
            eshards[eid % INFO_SHARDS][str(eid)] = e["downloadURL"]
        write_json(x / "series_info" / f"{sid}.json",
                   {"seasons": [seasons[k] for k in sorted(seasons)], "info": info,
                    "episodes": dict(episodes)})
    write_json(x / "series.json", rows)
    for c, r in by_scat.items():
        write_json(x / "series" / f"{c}.json", r)
    for k in range(INFO_SHARDS):
        write_json(x / "episodes" / f"{k}.json", eshards.get(k, {}))

    # -- channels
    write_json(x / "live_categories.json",
               [{"category_id": "1", "category_name": LIVE_GROUP, "parent_id": 0}])
    write_json(x / "live_streams.json", [
        {"num": n + 1, "name": ch["title"], "stream_type": "live", "stream_id": n + 1,
         "stream_icon": f"{SITE}/assets/app-icon/app-icon.png",
         "epg_channel_id": f"{ch['id']}.archivewatch.org", "added": "0",
         "category_id": "1", "custom_sid": "", "tv_archive": 0, "direct_source": "",
         "tv_archive_duration": 0, "channel": ch["id"]}
        for n, ch in enumerate(schedule["channels"])])
    return {"series": len(rows), "episodes": len(eids)}


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
    shows = series_list(REPO, json.loads((REPO / "episodes-index.json").read_text(encoding="utf-8")))
    out = Path(args.out) / FEED_DIR
    out.mkdir(parents=True, exist_ok=True)
    live = "".join(channel_entry(ch, n + 1) for n, ch in enumerate(schedule["channels"]))
    tv = "".join(episode_entry(sp, se, ep, e) for sp in shows for se, ep, e in episode_order(sp))
    everything = header() + live + "".join(film_entry(i) for i in items) + tv
    (out / "archivewatch.m3u").write_text(everything, encoding="utf-8")
    (out / "films.m3u").write_text(everything, encoding="utf-8")
    (out / "live.m3u").write_text(header() + live, encoding="utf-8")
    (out / "guide.xml").write_text(guide(schedule, by_id), encoding="utf-8")
    counts = xtream(items, shows, schedule, out)
    kinds = collections.Counter(group(i) for i in items)
    (out / "manifest.json").write_text(json.dumps(
        {"films": len(items), "channels": len(schedule["channels"]), "groups": kinds,
         **counts, "scope": "served index",
         # The Worker keys its cache on this, so a publish replaces every
         # list it serves within minutes (xtream.js build()).
         "build": datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")}, indent=1), encoding="utf-8")
    print(f"[film-feeds] {len(items)} films in {len(kinds)} groups, {counts['series']} series "
          f"({counts['episodes']} episodes), {len(schedule['channels'])} channels; "
          f"left out: {dict(skipped)}")
    if len(items) < FLOOR:
        print(f"[film-feeds] refusing: {len(items)} films is under the floor of {FLOOR}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
