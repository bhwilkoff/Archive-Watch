# Archive Watch on Roku — parity ledger

**Status: tick 1 of an owner-run build loop.** This is the living list the Roku
work is measured against, in the shape `PARITY.md` already uses. It exists so
"full parity" is a checkable claim rather than a feeling.

Every row is one of:

| Mark | Meaning |
|---|---|
| ⬜ | not started |
| 🔨 | in progress |
| ✅ | built AND verified on the owner's Streaming Stick 4K, with evidence |
| ⏳ | deliberately deferred, with the reason in Notes |
| 🚫 | will not exist on Roku, with the reason in Notes |

**✅ requires evidence on the glass**, never the app's own report: a screenshot
from `tools/roku.py shot`, a line from the BrightScript console, or an ECP
assertion. That is the same bar the tvOS and Android TV audits are held to.

## The device and the harness

Roku Streaming Stick 4K, model 3820R2, Roku OS 15.3.4, 1080p UI, at
`10.0.0.155`. `tools/roku.py` wraps all four channels the platform gives us:

- **deploy** — sideload via the developer web installer (HTTP digest auth)
- **keys / type** — drive the remote over ECP
- **shot** — screenshot the running dev channel
- **log** — the BrightScript debug console on port 8085, which is our logcat

ECP **must be permissive** or `/keypress` returns 403 while `/query/device-info`
still answers, so a naive reachability check passes with every input rejected.
The owner enabled it on 2026-09-03.

## What tick 1 settled

- **The data plane question is answered, by measurement on the device.** Roku
  has no SQLite, so it cannot read the ~150 MB catalog the Apple and Android
  clients download. It reads the WEB plane instead (Decision 029): the 6.2 MB
  `catalog-index.json` downloads in **1.06 s** and `ParseJson` costs **364 ms**
  for **26,965 items**, with the device's memory level never leaving `normal`.
  No Roku-specific feed is needed. Evidence: `build/qa/roku-2026-09-03/v01_nofont.jpg`.
- **The pipeline works end to end**: package, sideload, launch, screenshot, read
  the console.
- **A Roku trap worth the whole tick**: a `<Font role="font" uri="font:LargeBoldSystemFont" />`
  child made every `Label` render NOTHING — no error, no warning, a screen of
  pure background colour while the console reported a healthy run. Removing it
  brought all text back. Never trust "the log looks fine" on this platform.

---

## Parity rows

### 1. Navigation shell

| Feature | Roku | Notes |
|---|---|---|
| Verb | ⬜ |  |
| Top-level nav | ⬜ |  |
| Per-tab back stack | ⬜ |  |
| Deep-linkable surfaces | ⬜ |  |

### 2. Discover — Home

| Feature | Roku | Notes |
|---|---|---|
| Hero / featured banner | ⬜ |  |
| Curated + dynamic shelves | ⬜ |  |
| Category tiles | ⬜ |  |
| Decade tiles | ⬜ |  |
| Hidden Gems shelf | ⬜ |  |
| Top Rated shelf (IMDb) + rating sort in Browse | ⬜ |  |
| Community shelves (Watching Now / Favorites / Most Discussed) | ⬜ |  |
| Detail community (stats + genuine reviews) | ⬜ |  |
| Director shelves | ⬜ |  |
| Continue Watching | ⬜ |  |
| Modes row | ⬜ |  |
| Public Domain Day section | ⬜ |  |

### 3. Discover — Movies / TV / Collections / Search

| Feature | Roku | Notes |
|---|---|---|
| Movies grid + facets + sort | ⬜ |  |
| Infinite scroll / paging | ⬜ |  |
| TV series → season → episode | ⬜ |  |
| TV never appears in Movies | ⬜ |  |
| TV Specials surface | ⬜ |  |
| Orphan episodes fold into spines | ⬜ |  |
| Prev/next episode in player | ⬜ |  |
| Collections landing + blurbs | ⬜ |  |
| Full-text search (FTS5) | ⬜ |  |
| Search result filters | ⬜ |  |

### 4. Detail + Playback

| Feature | Roku | Notes |
|---|---|---|
| Detail (backdrop, metadata, cast) | ⬜ |  |
| "Also known as" alternate release title | ⬜ |  |
| More Like This | ⬜ |  |
| Cast → person filmography | ⬜ |  |
| Share titles / series | ⬜ |  |
| Open in Callsheet (cast/crew app) | ⬜ |  |
| Now Playing / media controls | ⬜ |  |
| Title+description in player | ⬜ |  |
| Video playback | ⬜ |  |
| Resilient streaming | ⬜ |  |
| Resume across launches | ⬜ |  |
| Subtitles / audio / speed | ⬜ |  |
| Autoplay / continuous play | ⬜ |  |
| Picture-in-Picture | ⬜ |  |
| Background play | ⬜ |  |
| SharePlay — group waits for a stalled member | ⬜ |  |
| Cast / AirPlay | 🚫 | Roku is a RECEIVER, not a sender. |

### 5. Surprise + Immersive modes

| Feature | Roku | Notes |
|---|---|---|
| Surprise / random actions | ⬜ |  |
| Channels (EPG guide) | ⬜ |  |
| Create / user channels | ⬜ |  |
| Cartoon / Kids mode | ⬜ |  |
| Commercial-break controls | ⬜ |  |
| Party Play (muted) | ⬜ |  |
| Cover-art screensaver | ⬜ |  |
| VHS effect overlay | ⬜ |  |

### 6. Personalization + sync

| Feature | Roku | Notes |
|---|---|---|
| Favorites | ⬜ |  |
| Playlists | ⬜ |  |
| Watched / hide-watched | ⬜ |  |
| Continue Watching progress | ⬜ |  |
| Watch history (full ever-watched record, D078) | ⬜ |  |
| Cross-ecosystem history sync (Drive App Data, D028) | ⬜ |  |
| Local persistence (offline-first) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Per-ecosystem sync (own cloud) | ⬜ |  |
| Cross-ecosystem sync (all platforms) | ⬜ |  |
| Deletions carry tombstones | ⬜ |  |
| Downloads in Library (manage + remove) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Play a downloaded film with no network | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Offline subtitles for a downloaded film | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Offline state banner | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Downloads are device-local (never synced) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |

### 7. Settings + account

| Feature | Roku | Notes |
|---|---|---|
| Mature-content filter (default ON) | ⬜ |  |
| Category visibility toggles | ⬜ |  |
| Autoplay/playback options | ⬜ |  |
| Downloads storage + Remove All | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| TMDb attribution (required) | ⬜ |  |
| Donate to Internet Archive | ⬜ |  |
| Sign-in (sync gate, optional) | ⬜ |  |
| Account deletion | ⬜ |  |

### 8. Platform reach + integration

| Feature | Roku | Notes |
|---|---|---|
| Home-screen surface | ⬜ |  |
| Voice / shortcuts | ⬜ |  |
| Spotlight / system search | ⬜ |  |
| Installable app | ⬜ |  |
| Handoff / continuity | ⬜ |  |

### 8b. Non-Apple TV platforms (Decision 047 · `docs/TV-DESIGN.md`)

| Feature | Roku | Notes |
|---|---|---|
| Client | ⬜ |  |
| Verb | ⬜ |  |
| Top-level nav | ⬜ |  |
| Home (hero + shelves) | ⬜ |  |
| Browse | ⬜ |  |
| Detail | ⬜ |  |
| Search | ⬜ |  |
| Library | ⬜ |  |
| Channels (EPG) | ⬜ |  |
| Surprise · Collections · Cartoon · filtered grids | ⬜ |  |
| Playback | ⬜ |  |
| Background media controls | ⬜ |  |
| Picture-in-Picture | ⬜ |  |
| Cast (send to TV) | ⬜ |  |
| Subtitles | ⬜ |  |
| Sign-in + sync | ⬜ |  |
| Clip Studio / Creation Studio | 🚫 | Creation is a phone and Mac feature; a remote has no direct manipulation. |
| Platform home-screen integration | ⬜ |  |
| Gate | ⬜ |  |
| `tools/verify_tv_focus.sh` | ⬜ |  |
| `tools/tv_browser_tests.js` | ⬜ |  |
| `tools/test_tv_focus.mjs` | ⬜ |  |
| `tools/test_tv_ua.mjs` | ⬜ |  |
| `tools/audit_tv_g6.py` | ⬜ |  |
| `tools/audit_fire_tv_gms.py` | ⬜ |  |

---

## Open questions for the design tick

1. Which Roku idiom carries Home: a `RowList` of poster rows under a hero, or
   the grid-first shape Roku's own channel uses? The design research decides.
2. What the `*` (Info/Options) key opens on each surface — Roku users expect it
   to do something everywhere.
3. Whether Channels (the EPG) survives as-is on a remote with no colour keys.
4. What sync can mean here at all: Roku has `roRegistrySection` for local state
   and no Google or Apple identity, so cross-device sync may be honestly 🚫.
5. Whether the resilient-playback gap (Decisions 021/031/034) can be partly
   recovered on the `Video` node — the owner asked for this to be investigated
   before the rest of the app is built on top of it.
