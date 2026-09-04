# Roku Channel Store listing — Archive Watch

Paste-ready copy and the staged assets. Everything here is written to Roku's
own limits and CHECKED against them, not estimated: the Dashboard truncates
silently.

Assets live in `build/roku-store/` (gitignored build output — regenerate with
the commands in this file if they are missing).

## Names and copy

**App name** (max 30 chars): `Archive Watch` — 13

**On-device description** (max 300 chars, 268 used):

```
Thousands of public-domain films, free and without an account: feature films, silent cinema, classic television, animation, newsreels and vintage commercials from the Internet Archive. Browse by era or genre, tune a live retro channel, or let the archive surprise you.
```

**Online description** (max 1500 chars, 1459 used):

```
Archive Watch turns the Internet Archive's moving-image collection into a cinematheque on your television. Around 27,000 titles, all public domain or openly licensed, all free, and no account to make.

BROWSE
Feature films, classic TV, silent cinema, animation, short films, newsreels, documentaries, ephemeral and industrial film, and vintage commercials. Filter by type, decade or genre, sort by what is popular, newest, oldest, best rated or simply shuffled.

CHANNELS
Fourteen curated channels run to a real schedule with vintage commercial breaks between programmes, so you can tune in the way you used to and join whatever is already playing. Build your own from a genre and a decade.

SURPRISE
Fifteen doors into the collection when you do not know what you want: a random feature, a random silent, a random newsreel, a whole decade to wander, a cartoon marathon by character, and a wall of cover art to browse by poster alone.

YOUR LIBRARY
Save films, pick up where you stopped, and make playlists. Everything stays on this device.

Titles are presented with posters, cast, synopses and ratings drawn from TMDb, OMDb, TheTVDB, Wikidata and Wikimedia Commons, so archival cinema gets the same care as anything else on your television.

Archive Watch is free and always will be. The Internet Archive is a non-profit library — if you value this, support it at archive.org/donate.

This product uses the TMDB API but is not endorsed or certified by TMDB.
```

The last line is not optional: Decision 007 requires the TMDb notice verbatim
wherever TMDb data is presented, and a store listing that describes the
metadata is exactly that.

## Assets

| Asset | Spec | File |
|---|---|---|
| Channel poster | 540x405 | `channel_poster_540x405.png` |
| Screenshot 1 — Home | 1920x1080 | `store_1_home.png` |
| Screenshot 2 — Channels guide | 1920x1080 | `store_2_channels.png` |
| Screenshot 3 — Collections | 1920x1080 | `store_3_collections.png` |
| Screenshot 4 — Detail | 1920x1080 | `store_4_detail.png` |
| Screenshot 5 — Surprise | 1920x1080 | `store_5_surprise.png` |
| Screenshot 6 — Cover Art Wall | 1920x1080 | `store_6_wall.png` |

The screenshots are captured from the real channel on the real device with
`tools/roku.py shot`, not mocked. Anything a store shot shows is something the
app does.

**One caution when re-capturing:** the device carries whatever state the last
session left. The first Channels capture showed two leftover TEST channels,
one of which matched nothing in the catalog — a screenshot of a bug. Delete
user channels and clear test playlists before shooting.

## Dashboard fields the owner must decide

| Field | Note |
|---|---|
| Category | "Movies & TV" is the obvious fit |
| Age rating | The catalog is unrated pre-1978 cinema; adult items are filtered upstream (Decision 012), but some titles carry period content that has not aged well — see the editorial note in CATALOG-VERSION-SELECTION §6 |
| Kids' designation | No |
| Countries | Public domain status is US-specific (Decision 027 anchors on US law), so US-only is the defensible answer |
| Monetization | Free |
| Privacy policy URL | https://archivewatch.org/privacy.html — live, 200 |
| Support URL | https://archivewatch.org/support.html — live, 200 |
| Deep link test parameters | `contentId=el-candidato-1959`, `mediaType=movie` |

## Regenerating the assets

```bash
# Six screenshots from the live channel
python3 tools/roku.py launch --settle 4
python3 tools/roku.py shot store_1_home        # after arrowing into the shelves
# ... go: links for the rest, see the tick-31 commit

# The 540x405 poster, composed from the photographic master
# (memory: app_icon_photographic_only — that still IS the icon)
```
