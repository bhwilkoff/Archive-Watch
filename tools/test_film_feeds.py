#!/usr/bin/env python3
"""The IPTV feeds (build_film_feeds.py): one playlist with the channels and
every film, the guide it names, and the Xtream data — each rule with a check
that would fail if it were broken."""
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "tools"))
import build_film_feeds as F  # noqa: E402

fails = 0


def check(name, ok, detail=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + (f" — {detail}" if detail and not ok else ""))
    fails += 0 if ok else 1


out = Path(tempfile.mkdtemp())
r = subprocess.run([sys.executable, str(REPO / "tools/build_film_feeds.py"), "--out", str(out)],
                   capture_output=True, text=True)
check("the builder succeeds", r.returncode == 0, r.stderr[-300:])
feeds = out / "feeds"
m3u = (feeds / "archivewatch.m3u").read_text()
lines = m3u.splitlines()
check("the header names the guide", lines[0].startswith("#EXTM3U") and 'x-tvg-url="https://archivewatch.org/feeds/guide.xml"' in lines[0])
extinf = [l for l in lines if l.startswith("#EXTINF")]
urls = [l for l in lines if l and not l.startswith("#")]
check("every entry has its address", len(extinf) == len(urls))
sched = json.loads((REPO / "channel-schedule.json").read_text())
n = len(sched["channels"])
live = extinf[:n]
check("the channels come first, under Live Channels, numbered",
      all('group-title="Live Channels"' in l and f'tvg-chno="{k + 1}"' in l for k, l in enumerate(live)))
check("a channel address is the Worker's /live/<id>, not a file",
      all(u.startswith(F.WORKER + "/live/") and not u.endswith(".mp4") for u in urls[:n]))
films = extinf[n:]
check("every film is marked a movie, grouped, and carries a length",
      len(films) > 1000 and all('tvg-type="movie"' in l and 'group-title="' in l and not l.startswith("#EXTINF:-1") for l in films))
check("films play archive.org's file directly", all(u.startswith("https://archive.org/download/") for u in urls[n:]))
groups = {re.search(r'group-title="([^"]+)"', l).group(1) for l in films}
check("no per-kind playlists are published", not list(feeds.glob("*-film.m3u")), str(list(feeds.glob("*.m3u"))))
check(f"films are grouped by kind ({len(groups)} groups)", 3 <= len(groups) <= 12, str(groups))
live_only = (feeds / "live.m3u").read_text().splitlines()
check("live.m3u is the channels alone", sum(l.startswith("#EXTINF") for l in live_only) == n)

g = ET.parse(feeds / "guide.xml").getroot()
progs = g.findall("programme")
with_desc = sum(1 for p in progs if p.find("desc") is not None)
check("the guide's channels match the playlist's tvg-ids",
      {c.get("id") for c in g.findall("channel")} == {re.search(r'tvg-id="([^"]+)"', l).group(1) for l in live})
check(f"the guide carries film details ({with_desc}/{len(progs)} with a synopsis)", with_desc > len(progs) * 0.5)
order = ["title", "desc", "credits", "date", "category", "icon", "url", "star-rating"]
bad = [p for p in progs[:500] if [c.tag for c in p] != sorted((c.tag for c in p), key=order.index)]
check("programme children follow XMLTV's DTD order", not bad)

x = feeds / "xtream"
streams = json.loads((x / "vod_streams.json").read_text())
ids = [s["stream_id"] for s in streams]
check("every film has its own Xtream id", len(ids) == len(set(ids)) == len(films))
s0 = streams[0]
info = json.loads((x / "info" / f"{s0['stream_id'] % F.INFO_SHARDS}.json").read_text())[str(s0["stream_id"])]
check("get_vod_info carries plot, cast and director",
      bool(info["info"]["plot"]) and "director" in info["info"] and "cast" in info["info"])
check("the stream id is stable (a hash of the archive id)",
      F.stream_id("TheGeneral720p1926") == F.stream_id("TheGeneral720p1926") != F.stream_id("TheGeneral720p1927"))
# Control: a playlist built without the channels would fail the first check.
check("control: the film-only prefix would not pass as channels",
      not all('group-title="Live Channels"' in l for l in films[:n]))
print(f"\n{fails} failure(s)")
sys.exit(1 if fails else 0)
