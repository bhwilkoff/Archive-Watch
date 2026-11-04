# Archive Watch — Decisions 161–170

Archived verbatim from DECISIONS.md (Decision 092).

## 161 — A narrow link is answered with the bitrate before a dropped frame, and a drop ends at the next keyframe it can ask for
*Date: 2026-10-02*

`RTMPPublisher.send(video:)` returns how full its queue is, what the link carried
over the last second while a queue stood, and whether a drop is under way; the
engine steps the bitrate down past 60% of the §6.4a budget — straight to 80% of
the measured link — asks for a keyframe as soon as a drop has drained to half the
budget, and steps back up 20% after ten clear seconds (WATCH-TOGETHER §6.4b).

**Why**: the owner: *"It said dropped 451 (it did stutter occasionally)."* §6.4a's
drop was the only defence, and each drop froze the picture until the next
scheduled keyframe, up to two seconds. On one throttle (6 Mbps program, 1.8 Mbps
link) dropping alone lost 263 frames; stepping by quarters 80; stepping to the
measured link 0. A queue depth is a symptom; what the link carried is the number
to steer by.

**How to apply**: never answer congestion with resolution or frame rate (§6.5).
`setLinkAdaptation(false)` / `AW_STUDIO_LINK_ADAPT=off` is the control, and §8.6
runs with it so it keeps testing the last resort. A throttle the program fits
under proves nothing — §8.79 refuses to judge unless its control drops frames.

## 162 — The Samsung TV floor is 2022 (Tizen 6.5, Chromium 85), held by a polyfill file and a build gate
*Date: 2026-10-03*

The Tizen package declares `required_version="6.5"` and is released to the
2022-2026 model groups. The shared web code that runs inside it stays within
Chromium 85: `js/compat.js` loads before every other script and fills
`AbortSignal.timeout` and `replaceChildren`; the CSS uses longhands instead of
`inset`/`padding-inline`/`margin-inline`, `:focus` instead of `:focus-visible`
on TV, and puts `color-mix()` and `overflow: clip` behind `@supports`.
`tools/test_tv_compat.py` enforces the CSS rules (with planted controls) and
`tv/build-tv-packages.sh` refuses to package when it fails.

**Why**: the owner, preparing the Samsung submission: *"I'd like to be able to
support everything from 2022 onward."* The config had claimed Tizen 6.0, but
nothing ever ran the app on an engine older than the test set's Chromium 120.
Rendered in a real Chromium 85 build, Home was empty (`replaceChildren` threw
while drawing it, and every bounded fetch threw on `AbortSignal.timeout`), the
overscan padding was gone, sheets fell out of center, and the category tiles
had no color because `color-mix()` with `var()` passes the parser and fails at
compute time, voiding the fallback written above it.

**How to apply**: a new web-platform feature in code the TV loads is checked
against Chromium 85 first; fill it in `js/compat.js`, gate it with
`@supports`, or don't use it. Never raise `required_version` to dodge a fix:
that drops a model year from the store silently. Re-render the TV layer in the
Chromium 85 snapshot after a CSS change (recipe: docs/tizen-submission.md
§2b), with a fresh profile every run.

## 163 — archive.org's own trailer collection outweighs the silent-era guard
*Date: 2026-10-08*

An item in archive.org's `movie_trailers` collection that runs five minutes or
less, is dated 1905 or later, is not a commercial and does not say "trailer",
"preview" or "teaser" in its title is a trailer posing as its feature, whatever
its era: `remediate_catalog._archive_trailer` hides it as `excludedReason:
trailer` and records `trailerEvidence`. Decision 052's other tests are unchanged.

**Why**: the first iPhone Duo screenshots ranked films by votes, and the
catalog's only "The Kid" was `turner_video_9` — a 119-second Turner Classic
Movies promo carrying the film's identity and 144k votes; three copies of The
Gold Rush were the same. Decision 052 spares short silents because a four-minute
silent is usually a surviving fragment, and that guard is right in general —
but here the archive's own collection says what the file is. Measured: 64 visible
items in the collection; 50 hide (The Kid, The Gold Rush, Nosferatu, Caligari,
The General, Wings...), 14 stay (Abraham Lincoln and Know Your Enemy: Japan run
feature length, The Great Train Robbery 12 minutes, Sherlock Holmes Baffled is a
1900 film that is a minute long, and the vintage trailers titled as trailers).

**How to apply**: an honestly labeled vintage trailer is an archival object and
stays; only one wearing a film's identity leaves. A real film wrongly filed in
the collection comes back by evidence (a runtime over five minutes, a year
before 1905), never by dropping the collection test. `tools/test_trailer_collection.py`
holds the case and five controls.

## 164 — Roblox is shelved: the films are what it cannot carry well
*Date: 2026-10-15*

Archive Watch does not build for Roblox. The research stays in
`docs/research/ROBLOX.md` and `docs/research/roblox/01-09`, with the pathway
and the conditions for reopening in ROBLOX.md §8. Nothing was built, no
account was created and no Robux were spent.

**Why**: the owner, after the research: *"I don't think we should pursue the
roblox platform for the time being. Make sure that we have fully documented the
pathway, but I don't think that it is worth the time and effort for such a
compromised experience."* Roblox plays only video it hosts: 5-minute assets at
2,000 Robux each (~$400 a feature, ~$7M for the catalog). The free route that
stays inside its rules, films as moderated image flipbooks, plays at 256x192
and 12 fps and suits only a curated silent program. Streaming from off-platform,
as "YouTube in Roblox" projects do, is what Roblox staff told creators not to
do. The theaters, rooms, interface and tooling all fit; the films do not.

**How to apply**: do not start Roblox work on a new idea for playback alone;
reopen only on a trigger in ROBLOX.md §8.1 (video terms, URL playback, the
VideoPlayer API, a real image quota, or the owner choosing a silent
cinematheque), and then follow §8.2's order: free measurements before any
spend or build. Whatever changes, never stream frames from off-platform or hide
video inside images.

## 165 — The Play build's floor is Android 7, because Play's automatic protection requires it; Fire TV keeps Android 6
*Date: 2026-10-15*

The `google` flavor declares `minSdk = 24` (Android 7.0); the `amazon` flavor
keeps `minSdk = 23` (Android 6.0), so Decision 141's floor now holds for Fire
TV only.

**Why**: the crash-fix release (versionCode 67) was refused at upload — *"Play
automatic protection requires a minimum SDK version of 24 or higher. The
uploaded App Bundle has a minimum SDK version of 23."* versionCode 66 had
uploaded at 23 on 2026-09-30, so the requirement arrived on Play's side in
between. Asked to choose between switching automatic protection off, raising
the Play floor, or holding the release, the owner chose to raise the Play
floor. Play withholds per-API user counts below its minimum audience, so how
many Android 6 viewers this drops could not be measured; they keep the version
they have and stop receiving Play updates.

**How to apply**: do not lower the google flavor below 24 while automatic
protection is on. Fire TV is the Android 6 build now: lint NewApi and
`canHostShow` still have to hold at 23 there, and the ISRG roots in
network_security_config.xml are still what let it download the catalog.

## 166 — A series held in one archive.org item is a series: its files become episodes, `<item>@<token>`, on evidence the item itself gives
*Date: 2026-10-18*

An archive.org item whose files are a whole show or serial — `UFO.complete`
(26 files), Leave It to Beaver's six seasons in one item, Spy Smasher's 12
chapters — becomes a spine of its own (`tools/build_bundle_series.py`, in
tv-canonical before the reconcile that makes its card). Each file is an
episode with the id `<item>@<token>`: `e01` (no season), `s2e05`, or
`x-<slug>` for an unnumbered extra, and the token is the file's own number,
never its position. The spine and every episode carry `sourceID`; the item's
own card is not published and its id forwards to `series:<slug>`; its TV
shelves pass to the series card (never its film shelves: Decision 036).
Every client splits an id at the first `@` to reach archive.org, and lists
only the episode's own file and its derivatives as copies.

**Why**: the owner, 2026-10-18 — *"We have many serialized tv shows in the
database. These should function in the same way, especially if we have the
data/metadata to support it."* They were film cards that played one file of
dozens, with no episodes, progress or next. Measured over the catalog: 8,421
items fetched (an item ≥3x its default file and ≥45 files), 241 parse as
numbered works, **141 shows and 3,589 episodes** pass the rules below, every
sampled file and still answers 200. `@` because archive.org ids never contain
it, the Worker's id regexes accept it, and it is safe in a URL path and the
Roku registry; `/` broke deep links and the 404 router, `~` the Worker.

**What is NOT a series**, each measured against a real false positive: a
film in pieces (`nosferatu-1of5`, a DVD's `VTS_01_3`, any `reel1`; "Part 3"
only when the item is typed television — Insurrection, 1966, is an eight-part
drama), numbered works with no MP4 (Apple's player opens no Ogg or Matroska,
and no visible film card carries one), commercial breaks, home movies, audio
items, anything `noRecommend` or in archive.org's own `deemphasize`
collection (a numbered "Protocols of the Elders of Zion" audiobook passed
every file rule). Numbered files alone are lectures, launch coverage and
audiobooks as often as shows, so a series needs evidence of its own: episode
words in its file names (episode/ep/chapter/E01/S01E01), a television
typing, a title per episode, a run of ten or more, or its own metadata saying
serial/series/episodes. Two uploads of one show: the fuller is the spine; a
serial in halves with no number in common is merged (`sourceIDs`).

**How to apply**: never key an episode by its position or its file name —
a token that moved would lose every viewer's progress. A new client that
builds an archive.org URL from an id splits at the first `@`. Tune a false
positive by a rule with a control in `tools/test_bundle_series.py`, never by
a list of ids. The scan caches each item's verdict and the files a spine
needs (`shared/editorial/bundle_scan.json`, re-checked after 60 days or when
the item's size changes), so the build itself needs no network.

**Consequences**: serials typed as films (Spy Smasher, Flash Gordon, Radar
Men from the Moon) leave Movies for TV. A source item keeps its film card
until its `series:<slug>` card is in the catalog (`bundle_sources(cards)`),
because the card is made by tv-canonical's reconcile and the DB can be built
between the two. App builds made before this change show the series and play
its episodes, but split no ids, so archive.org details and copies for an `@`
episode fail until the next store builds. The bundled seed DB (first launch
only) still shows the source items as film cards until the downloaded catalog
replaces it.

## 167 — A whole series filed in one item and matched onto a TVmaze show becomes that show's episodes, placed by title
*Date: 2026-10-20*

When an item whose files are a whole show (Decision 166's rules) has been
matched onto a TVmaze spine, `build_canonical_tv.expand_bundles` replaces it
with one row per file, `<item>@<token>` with an episode-level `sourceID`, read
from `bundle_scan.json` (which now scans the items TVmaze spines serve, not only
catalog cards). Each file is placed on a canonical episode by its OWN TITLE
first, and by its number (and the season its item names: "Room-222-Season-2")
only when it states no title. A file whose episode is already played by another
copy is dropped; a file under four minutes, or under 40% of its episode's
running time, is not that episode. Items that are one episode each place first,
then the fullest upload, and a colorized upload last (Decision 158). The
re-pick is skipped for these files: by item id it would swap in the item's
largest file, another episode.

**Why**: a viewer, 2026-10-20, asking for Fireball XL5's 39 episodes and noting
the last entry under More episodes ended in a period. That entry was
`FireballXL5.complete`, 39 files, served as ONE episode titled "Fireball XL5."
and playing episode 25; the show page listed 5 of 39. Decision 166 never saw it
because its scan read catalog cards, and an item on a TVmaze spine is not one.
Measured over every TVmaze spine: 150 such items on 85 shows, ~4,800 files (The
Prisoner, Space: 1999, Supercar, The Dick Van Dyke Show, The Addams Family's five
uploads, Ozzie and Harriet's 436). Numbers alone mislead: the uploader numbered
by production, so "08. Space Immigrants" is TVmaze's 1x03.

**How to apply**: every tool that reads spine episodes must take the item from
`sourceID` (or `item_of`), never from the `@` id: the rights audit asks
archive.org about the item and removes all its files with it; the series audit,
the derivative repair and the re-pick leave these files alone; reconcile,
backfill and discovery count the item as served; `build_sqlite.bundle_sources`
forwards the item's id to the series. A bundle SPINE's source keeps its catalog
card (166); an item expanded into a TVmaze spine loses it. The colorized request
that raised this could not be met: archive.org holds 3 colorized Fireball XL5
episodes, not 39, and `FireballXL5.complete` is black and white (mean saturation
1.7 against 6.4 for the colorized upload). `tools/test_bundle_in_tvmaze.py`
holds the cases with a single-item, promo and fragment control, and gates the
tv-canonical build.

## 168 — Correction to 167: each file of a whole-series item is judged by its own year; its item answers only for the licence
*Date: 2026-10-20*

`audit_tv_rights` judges every episode of a TVmaze spine by the episode's OWN
year, and a file of a whole-series item (`X@s3e01`) asks archive.org about its
item `X` (`item_of`) for the licence and collections. It does not judge the
item as a whole, and it does not remove an item's other files when one is
removed. Decision 167's "removes all its files with it" was the defect, not the
rule.

**Why**: the first tv-canonical run with 167 keyed the year by item, so the first
1978 file of `George_and_Mildred` set the year for all 39, and every file was
removed, the 1976 and 1977 episodes with them; Logan's Run and The Tony Randall
Show lost their spines entirely (111 files in all). Judged per file: 47 files,
every one aired 1978 or later, and every show stays.

**How to apply**: never key the audit's `need` by item; fetch and cache by item,
judge by file. The 111 manifest rows were removed and the five spines restored
and rebuilt, since `tv_rights_removed.csv` re-removes by id on every run.
`test_tv_rights_items.py` holds a 1976 and a 1978 file of one upload.

## 169 — A single-episode upload is placed by its own file name and id, and a person's "never serve this" binds every series
*Date: 2026-10-27*

`build_canonical_tv.map_items_to_canonical` places an upload that is one
episode by its OWN words, its file name and archive.org id, never by the
`title` it carries: a title it states that names a TVmaze episode places it
there (exact, leading articles ignored, then fuzzy unless the candidates differ
only by a part number or the years disagree); a number it states ("S04E03",
"4x03", "Season 4, Episode 3") places it only when its title shares a word with
that slot or states none; a promo, trailer or "next week" reel is never placed
and is listed as "Promo: <episode>". Colorized singles place last (Decision
158), "colorized" is dropped from a show name before TVmaze is asked, and an
unplaced title loses the show's name in front. `not_films.json` and the new
`shared/editorial/episode_rejects.json` ({archiveID: {notIn: slug|"*", why}})
are dropped from every rebuilt spine.

**Why**: the owner, 2026-10-27: *"There is no reason to leave bad data rather
than investigating and fixing it."* 109 editorial ids warned "not in the
catalog" every build; they were series episodes, and reading their spines
found three defects. An episode is re-pooled carrying the canonical title of
the slot it holds, so a misplacement confirmed itself every build:
"s01e01.The.Speckled.Band" was Sherlock Holmes' "Cunningham Heritage", a 1953
Humphrey Bogart Jack Benny was 1951's 1x03, Twilight Zone promo reels were
"The Silence" and "The Parallel", Victory at Sea's "09_Sea_And_Sand" was 1x02.
Measured against TVmaze for all 236 spines: 306 placements change, about 230
of them files that now find their episode (Four Star Playhouse, William Tell,
The Buccaneers, Loretta Young), each reviewed against its file name. Second,
`not_films` bound only the catalog, so LTT101, a Looney Tunes rip from Tubi, was
some 260 episodes of the Looney Tunes spine through Decision 167. Third, other
programs sat inside shows with their years clamped to the show's run, where
the TV rights audit keeps an undated episode on the show's year: the 2002
Twilight Zone and 1995 Outer Limits revivals, 2020-21 Family Feud in The Smith
Family, 1999 Emmerdale, a Marvel cartoon clip in The Avengers (1961).

**How to apply**: never place a single upload by `title`; read `_own_texts`. A
wrong placement is fixed by a rule with a control in
`tools/test_tv_episode_placement.py` (gated in tv-canonical), never a list of
ids; an upload that is another program goes in `episode_rejects.json` with what
its own file or record says it is. A stated year was measured as a general
rule and refused: Space: 1999, Studio One's "1984" and a KNTV accession number
read as modern years. Editorial ids that are series episodes are reported as
such, and a `not_films` id a spine still serves is a warning.

## 170 — A sort is remembered per kind of grid and television starts A–Z; a playlist's place among playlists is synced, and every sync writer carries it
*Date: 2026-10-27*

Every Browse grid keeps the viewer's sort per KIND of grid — `browseSort.tv`,
`.browse`, `.category`, `.collection`, the same key names on every platform —
and television grids start on A–Z (the rest on Popular). Sort gains Z–A
everywhere. Top Rated orders a series by its TVmaze rating (`tvmazeRating`: a
spine field, a series-card field, the last `items` column, the index's rating
column for tv-series rows) and breaks every tie, ending in title. Playlists
gain "My Order": `Playlist.sortIndex`, synced with the list, a list with none
first; a playlist's films are arranged by the order of `archiveIDs`. Remove,
Rename and a confirmed Delete sit where the list is seen (iOS-DESIGN §4.2c,
§4.3a).

**Why**: a viewer, John Howard, over five emails (docs/USER-FEEDBACK-2026-10.md):
the sort reset on every visit, Top Rated looked like A–Z, and he could neither
remove a film from a list nor arrange one. The owner, 2026-10-27: *"A-Z sorting
by default makes sense with the ability to change and have it remember. Yes to
ratings on TV series (TV maze is great) and then please implement full manual
ordering for playlists, as it is a reasonable request."* Top Rated "looked like
A–Z" because no series card had any rating, every row tied, and SQLite returned
insertion order, which is slug order. Memory per kind rather than per grid: a
choice made in one genre is expected in the next.

**How to apply**: a new grid takes its sort from `SortMemory` (Apple),
`BrowseSort.remembered` (tvOS) or its platform's equivalent, never a bare
`@State`/`remember` default; Random/Shuffle is never remembered. The TVmaze
number is never displayed or written as IMDb's — it is its own column, guarded
by `columnExists` because older DBs lack it. Any code that writes playlists to
a sync store (CloudKit on Apple and web, Drive on Android and web) must read and
write `sortIndex`: a writer that rebuilds an entry from the fields it knows
erases the viewer's arrangement on every other device, and the web did exactly
that for unknown fields before this change. `Playlist.arrange` stamps only
lists whose place changed, so a move syncs as a move. A synced playlist keeps
its own `createdAt` (it used to take the pull time).
