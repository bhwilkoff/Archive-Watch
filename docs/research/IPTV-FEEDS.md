# IPTV feeds: how Archive Watch reaches other players

Researched 2026-09-27 for the owner's request: *"make a single link for all
categories of video and the live tv ... I noticed the information about the
films isn't coming through on the playlist. Is that possible? Can you research
well structured IPTV feeds to figure out how to best structure ours?"*
Built by `tools/build_film_feeds.py` (deploy-pages) and `worker/src/xtream.js`
+ `live.js`. Page: `/feeds/`, reached only from the website footer and one
About card (WEB-DESIGN §8.6).

## What players read

- **M3U attributes read almost everywhere**: `tvg-id` (joins the EPG),
  `tvg-name`, `tvg-logo`, `group-title`; `#EXTINF` duration in seconds, `-1`
  for a live stream. Header `x-tvg-url` (and the older `url-tvg`) names the
  guide. <https://en.wikipedia.org/wiki/M3U>,
  <https://github.com/kodi-pvr/pvr.iptvsimple/blob/Omega/README.md>
- **`tvg-chno`** numbers channels (Kodi, TiviMate, Channels DVR's
  `channel-number`). **`tvg-type="movie"`** marks a film for players that honor
  it (SmartOne documents it; not a standard).
- **No M3U attribute for plot, cast or rating is read by any player.** That is
  why the owner saw no film details: a playlist cannot carry them.
- **Splitting Live / Movies / Series** has no cross-player standard. Parsers
  chain: an explicit attribute, then group words, then the Xtream URL shape
  (`/movie/`, `/series/`). Jellyfin/Emby treat every M3U entry as a live
  channel; Infuse has no IPTV support; VLC shows a flat list.
  <https://github.com/notsurewhoisthis/iptv-m3u-playlist-parser>,
  <https://jellyfin.org/docs/general/server/live-tv/setup-guide/>,
  <https://community.firecore.com/t/does-infuse-support-iptv/50562>

## Where film details come from

- **XMLTV**, for channels: each `<programme>` can carry `desc`, `credits`
  (director, actors), `date`, `category`, `icon`, `url`, `star-rating`. Ours
  carries all of them.
- **The Xtream Codes API**, for films: `player_api.php?action=get_vod_streams`
  (list, poster, rating, category) and `get_vod_info` (plot, cast, director,
  genre, release date, duration, poster, backdrop, tmdb_id). UHF, TiviMate and
  IPTV Smarters build their Movies section from it.
  <https://pkg.go.dev/github.com/tellytv/go.xtream-codes>,
  <https://apps.apple.com/us/app/uhf-love-your-iptv/id6443751726>
  Served here by the existing free Worker from JSON the pipeline publishes; any
  username and password are accepted, and playback is a 302 to archive.org.

## Live channels without a streaming server

HLS cannot use a progressive MP4 as a segment (RFC 8216 §3), and the tools
that make linear channels from files (Tunarr, ErsatzTV) transcode on a server.
**But archive.org serves any MP4 from a given second**: `?start=600` on The
General (6,405 s) returns a 5,805 s file whose first frame matches the
reference frame at 600 s (37 dB), measured 2026-09-27. So `/live/<channel>`
redirects to the program the one clock (Decision 144) says is airing, at the
second it has reached; when it ends, a player that reconnects is sent to the
next. Channel URLs carry no `.mp4` extension, so players do not file them as
films.

**A short film's last seconds are not joinable**: `?start=100` on a 104 s
film returns 4 s and 39 KB, which may hold no whole picture (the owner's
Documentary channel "wouldn't play" on *Egyptian Fakir with Dancing Monkey*,
2026-09-27). Inside the last minute, or the last quarter of a short film, the
channel starts the NEXT program from its beginning instead (`live.js joinURL`).

**Unverified on a real player**: whether UHF and TiviMate reconnect a live
channel when its film ends, rather than stopping. The owner's devices do not
have UHF or TiviMate installed, and installing an app is the owner's step.

## The files

| Address | What |
|---|---|
| `/feeds/archivewatch.m3u` | everything: 15 channels (`group-title="Live Channels"`, `tvg-chno`), every film (`tvg-type="movie"`, grouped by kind, poster, length), every series episode (`tvg-type="series"`, grouped by series); header names the guide |
| `/feeds/live.m3u` | the channels only |
| `/feeds/guide.xml` | XMLTV, every programme with synopsis, credits, year, genres, poster, rating |
| Worker `/player_api.php`, `/movie/…`, `/series/…`, `/live/…`, `/get.php`, `/xmltv.php` | the Xtream API: Live, Movies and Series |
| `/feeds/films.m3u` | the same as archivewatch.m3u, kept for players added 2026-09-26; not listed |

**Scope (Decision 145)**: everything the apps show. The first version carried
only the Roku feed's public-domain-by-age tier (6,315 films); the owner:
*"the Xtream feed has a much smaller selection, very few items in each
category, and the tv shows are not separated into 'series' as apps like UHF
expect."* Now: every film in the served index (19,848 on 2026-09-27) and every
series spine with the episodes the served episode index carries (290 series,
2,674 episodes), as the Xtream Series section and, in the M3U, as episodes
named `Show S01E02 Title` with `tvg-serie` / `tvg-season` / `tvg-episode`.

**The Worker passes lists through untouched** (a 6 MB list parsed per request
would exceed the free plan's CPU): whole lists and per-category lists are
separate files, and lookups are 256 small shards.
