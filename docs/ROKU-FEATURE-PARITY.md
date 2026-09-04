# Roku vs Apple TV — FEATURE-level parity

The structural matrix in `ROKU-PARITY.md` tracks screens. This one tracks the
**buttons and behaviours inside them**, enumerated from the tvOS sources
(`ArchiveWatch/ArchiveWatch/Views/*.swift`) rather than from memory, because a
surface that exists and does nothing is worse than one that is missing: it
promises.

Legend: ✅ built + verified on the device · 🔨 built, not yet verified ·
⏳ not built · 🚫 not possible on Roku, with the reason.

## Detail

| tvOS | Roku | Note |
|---|---|---|
| Play / Resume with runtime or position | ✅ | "Resume · 83m left" verified |
| Favorite (Save / Saved) | ✅ | persists across relaunch |
| More → Mark as watched / not watched | ✅ | state-aware; watched = a ≥95% progress row, so Library, hide-watched and the resume label agree by construction |
| More → Start from the beginning | ✅ | offered only when a bookmark exists |
| More → Save / Remove from Library | ✅ | duplicated in the menu deliberately: the menu is where a viewer looks for verbs |
| Choose version (pick a copy) | ⏳ | needs the item's file list from archive.org; see CATALOG-VERSION-SELECTION §2 for why this matters |
| Add to Playlist | ⏳ | blocked on playlists |
| More Like This row | ⏳ | |
| Next Episode button | ✅ | via the series queue, not a Detail button |
| Also known as (Decision 100) | ✅ | |
| Cast / crew | ⏳ | shard carries them with profile images |
| Share (QR to archivewatch.org) | ⏳ | |
| "Can't play this title" error | ✅ | plus the reason, on screen |

## Home

| tvOS | Roku | Note |
|---|---|---|
| Hero carousel | ✅ | pool of 12, backdrop-only |
| Curated + dynamic shelves | ✅ | 23 rows from featured.json + index |
| Continue Watching | ⏳ | exists in Library; not yet a Home row |
| Hidden Gems (Decision 050) | ⏳ | computed column exists in the DB plane, not the web index |
| Top Rated | ⏳ | index has no rating column (the same gap PARITY records for web) |
| Public Domain Day | ⏳ | |
| Community Favorites / Most Discussed | ⏳ | |
| Director shelves | ⏳ | index has no director column |
| Browse by Category tiles | ⏳ | |
| Browse by Era tiles | ⏳ | |
| Cross-shelf dedup | ⏳ | tvOS guarantees no title repeats across Home |

## Browse (Movies / TV)

| tvOS | Roku | Note |
|---|---|---|
| Type facet | ✅ | |
| Decade / Era facet | ✅ | |
| Sort (Popular / Newest / Oldest / A–Z) | ✅ | year-less rows sort LAST |
| Top Rated sort | ⏳ | no rating in the index |
| Genre / Keyword / Studio facets | ⏳ | index carries a search blob, not facet columns |
| Result count in the heading | ✅ | |
| Empty state that says what to change | ✅ | |
| Shuffle again | ⏳ | |
| TV browse → series drill-in | ✅ | **was a dead end until this tick** |

## Series

| tvOS | Roku | Note |
|---|---|---|
| Season list | ✅ | unnumbered seasons named "Unsorted" |
| Episode list with still, number, blurb | ✅ | |
| Honest episode count | ✅ | "18 of 39 episodes here" |
| Per-episode resume bar | ✅ | read from the registry |
| Play episode | ✅ | verified: position advancing |
| Autoplay next episode | ✅ | honours the Options setting |
| Favorite a series | ⏳ | |
| Add series to playlist | ⏳ | blocked on playlists |

## Channels

| tvOS | Roku | Note |
|---|---|---|
| Guide with real listings | ✅ | schedule proven identical to the other platforms |
| Tune in joins live | ✅ | verified at 4795 s in |
| Never writes resume progress | ✅ | |
| Commercial breaks woven | ⏳ | pool ships 60 commercials; not yet scheduled between programmes |
| VHS look | ⏳ | |
| User-created channels | ⏳ | |

## Library

| tvOS | Roku | Note |
|---|---|---|
| Favorites | ✅ | |
| Continue Watching | ✅ | |
| Watched list | ⏳ | |
| Playlists (create / add / Play All / remove / delete) | ⏳ | the largest single gap |
| Storage budget stated | ✅ | Roku-specific: 32 KB registry |

## Search

| tvOS | Roku | Note |
|---|---|---|
| Keyboard search over the catalog | ✅ | ~400 ms across 26,965 items |
| No-typing doors | ✅ | five |
| Result filters (type / era) | ⏳ | tvOS gained these in the 2026-08 audit |
| Series results route to the series | ✅ | now that series drill-in exists |

## Surprise

| tvOS | Roku | Note |
|---|---|---|
| Surprise Me | ✅ | as a Search door |
| Random Film / Decade / Animation / Newsreel / Ephemera / Commercial / TV Episode / Sci-Fi | ⏳ | tvOS has 11 actions; Roku has one |
| Cartoon Mode | ⏳ | |
| Party Play | ⏳ | |
| Cover Art Wall | ⏳ | |

## Settings (behind `*`)

| tvOS | Roku | Note |
|---|---|---|
| TMDb attribution verbatim (Decision 007) | ✅ | |
| Sources & Attribution | ✅ | |
| Support the Internet Archive | ✅ | |
| Hide Watched on Home | ✅ | |
| Autoplay Next | ✅ | consumed by the episode queue |
| Clear Continue Watching | ✅ | |
| Mature content toggle | 🚫 | the web index this platform reads drops adult items upstream, so the control would change nothing |
| Sign in / sync across devices | 🚫 | Roku has no Apple or Google identity; `roRegistrySection` is device-local (32 KB) |
| Commercial breaks / VHS look toggles | ⏳ | blocked on the features themselves |
| Idle screensaver | 🚫 | ROKU-DESIGN §11 — a channel may not draw one; Roku owns the screensaver |

## Player

| tvOS | Roku | Note |
|---|---|---|
| Resume from bookmark | ✅ | |
| Bookmarks written during playback | ✅ | every 5 s and on exit |
| Instant Replay | ✅ | |
| Trick play | ✅ | Roku's own, coloured to brand |
| Title / description overlay | ✅ native | Roku's transport already draws it; ours was a duplicate and was removed |
| Subtitles | ✅ | WebVTT accepted directly; display governed by the device's caption mode |
| Stall recovery | ✅ | watchdog re-issues play at the last position |
| Next / previous episode | ✅ | next via the queue; previous ⏳ |
