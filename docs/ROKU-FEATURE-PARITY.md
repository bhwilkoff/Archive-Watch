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
| Choose version (pick a copy) | ✅ | real files, real facts; verified switching fiddlesticks_1930 from a 618x480 derivative to its 928x720 original |
| Add to Playlist | ✅ | existing lists, or a new one named on Roku's keyboard |
| More Like This row | ✅ | 12 sampled by type + era; the index has no genre column, so similarity is honest about its inputs |
| Next Episode button | ✅ | via the series queue, not a Detail button |
| Also known as (Decision 100) | ✅ | |
| Cast / crew | ✅ | one line of five names; the shard's TMDb portraits are deliberately not drawn — see below |
| Share (QR to archivewatch.org) | ⏳ | |
| "Can't play this title" error | ✅ | plus the reason, on screen |

## Home

| tvOS | Roku | Note |
|---|---|---|
| Hero carousel | ✅ | pool of 12, backdrop-only |
| Curated + dynamic shelves | ✅ | 23 rows from featured.json + index |
| Continue Watching | ✅ | leads Home, resolved against the WHOLE index |
| Hidden Gems (Decision 050) | ⏳ | computed column exists in the DB plane, not the web index |
| Top Rated | ⏳ | index has no rating column (the same gap PARITY records for web) |
| Public Domain Day | ⏳ | |
| Community Favorites / Most Discussed | ⏳ | |
| Director shelves | ⏳ | index has no director column |
| Browse by Category tiles | ✅ | typographic cards, 8 categories, route to a scoped Browse |
| Browse by Era tiles | ✅ | 1900s–1970s; verified landing on "The 1920s · 3428 titles" |
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
| Add series to playlist | ⏳ | film-level playlists ship; a series is not an item |

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
| Watched list | ⏳ | watched state exists; no dedicated row yet |
| Playlists (create / add / Play All / remove / delete) | ✅ | store proven by an 18-assertion on-device self-test; Roku's own KeyboardDialog names them |
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
| Surprise Me | ✅ | Search door + its own surface |
| Random Film / Feature / Silent / Animation / Short / Newsreel / Ephemera / Commercial / Documentary / TV Episode / Decade | ✅ | eleven doors, each re-rolls; reservoir-sampled in one index pass |
| Cartoon Marathon | ✅ | 40-item shuffled queue, verified playing 1/40 |
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


## Why cast is a line and not a row of faces

The detail shard carries TMDb profile paths for every credited actor, so a row
of portraits was available for free. It is not drawn, because on a 1080-line
screen the vertical budget under the synopsis is about 340 pixels and it is
already spending it on the buttons and a "more like this" row. A row of six
faces would push the synopsis off the screen to show information nobody opened
the page for. Five names on one line answers "who is in this" at a glance and
costs 24 pixels.

Every number in that stack was moved after seeing it collide on the glass:
the synopsis is capped at four lines, the cast line sits at 672, the buttons at
738, the row label at 834 and the row at 882 with 108x162 tiles so its bottom
lands at 1056.
