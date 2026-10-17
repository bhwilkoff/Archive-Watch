# Research — the 2026-10-15 App Store review: serials, cartoon series, "Open Archive"

*2026-10-17. Research only; nothing built. Every number below was measured
against live archive.org metadata, today's `catalog.json` and the published
`catalog.sqlite`.*

## The review

5 stars, USA, iPhone, "jollyoldsaintnickname2", 2026-10-15
(`00000193-ec32-3f03-6a7f-cdc700000000`, not yet answered). Pulse clamps
bodies at 1,200 characters (`tools/pulse_collect.py:164`); the full text was
read from App Store Connect (`v1/customerReviews/<id>`). The parts that ask for
something:

> The only improvement I can suggest is to reorganize the More menu for
> identifying serial episodes with a numerical index. For example, Spy Smasher
> (1942) series. I am currently watching the Anderson's UFO (1969) series of 26
> episodes at 50 minutes each. I am going by whatever default sort but only
> seeing file type and size. Sorting options would help. Even an artificial
> index would be an improvement.

It then lists the series the reviewer collects: Buck Rogers (1939); Felix the
Cat, Mutt & Jeff, Molly Moo-Cow, Goofy Goat, Eshbaugh's snowman cartoon, Bosko,
Cubby Bear, the Van Beuren Tom & Jerry, Fleischer's Betty Boop, Gabby, Superman,
Color Classics, Stone Age and features, Joseph Sunn's 1926 clay films, George
Pal's Puppetoons, Tom Terrific, Lariat Sam, Baby Huey, Little Audrey. It ends
with: *"there is something called Open Archive certified public domain content
that is used on the Heartland+ app, which also sources curated content from
archive.org streaming."*

Three ideas, in order of value: **(1) one item that holds a whole series or
serial**, **(2) theatrical cartoon series as groupings**, **(3) "Open Archive"
as a rights source**.

---

## 1. One archive.org item that holds a whole series or serial

### What the reviewer sees

iPhone Detail → **More** (`iOS/DetailView_iOS.swift:107-179`) → **Choose
Version** (:128-139) → `Components/VersionMenuContents.swift`. Rows come from
`Services/ArchiveVersions.swift`:

- `files(on:)` (:162-192) makes every mp4/mov/m4v over 5 MB a "Version".
- `label` (:53-64) is `height · format · size — origin`.
- `ordered()` (:194-211) sorts by **height, then size, descending**. The file
  name (`stem`, :217-230) appears only when two labels would be identical.

That design is right for its purpose (alternative transfers of one film,
multi-reel disambiguation) and wrong for a bundle:

- **`UFO.complete`** (tv-special, 1969, tmdb 2560): 26 files named
  `UFO.01.Identified.mp4` … `UFO.26.The Long Sleep.mp4`. The picker shows 26
  rows like `480p · H.264 · 319.8 MB — Archive derivative`, ordered by size
  (01, 06, 25, 07, …). 21 of them carry no episode identity at all.
- **`spy-smasher-episode-1-1942-colorized-serial-720p-hd`** ("Complete Serial:
  12 Episodes", typed `short-film`): files `…episode{1..12}…`. They sort as
  2, 3, 1, 9, 4, 7, … and **the card's default copy is chapter 9**, because
  `tools/archive_lib.py:58 pick_video` takes the largest file in a tier. The
  same applies to Flash Gordon (1936), which defaults to chapter 3.

### Root cause

The data model has no idea that the files of one item can be episodes or
chapters:

- **Series spines** (Decisions 016/036/045): one episode is one *item*;
  `Episode` identity is `archiveID` (`Models/Catalog.swift:754-781`).
- Bundles are deliberately kept out of spines (`_NOT_SINGLE`,
  `tools/dedupe_orphan_episodes.py:51-53`; `tools/link_orphan_episodes.py:44-62`).
- **Catalog items** get one default file (largest wins).
- **The versions picker** presents every other file as another copy of the
  same film.

Progress and Watched are keyed by `archiveID` (`iOS/PlayerView_iOS.swift:1205-1209`),
so all 26 UFO episodes would share one resume point. That is inferred from the
code, not measured.

**Scale**: a title regex finds **76 visible bundle titles**. Examples: Captain
Marvel, The Phantom (15 chapters), Stingray, Captain Scarlet, Leave It to
Beaver, Survivors, The Persuaders, Department S, Quatermass. Several default to
something other than episode 1: Leave It to Beaver plays a season 7 bonus, The
Monkees plays *Head*, Captain Scarlet plays an interviews reel.

### Same on every platform

| Platform | Surface | State |
|---|---|---|
| iOS / macOS | `VersionMenuContents` | as above |
| tvOS | `Views/VersionPickerView.swift`; player "Version" menu (`DetailView.swift:2392-2408`) | same `ArchiveVersions` |
| Android phone / TV | `data/ArchiveVersions.kt:127-135` | same sort, stem only on duplicates |
| Web | `watch.js:343-361`, dialog :3119-3150 | worse: whole-MB sizes, no disambiguator, so many rows are identical |
| Roku | `components/VersionsTask.brs:30-128` | archive.org's alphabetical order, so UFO comes out right by accident and Spy Smasher reads 1, 10, 11, 12, 2…; lists .mkv |

### The index is in the data

The file names carry the number (and often the title), so this needs no
written copy:

- `UFO.NN.<Title>`: some files also have a metadata `title`
- `…-episodeN-…`: Spy Smasher, Flash Gordon, Captain Marvel
- `ChapterNN-<Title>`: The Phantom
- `SxxEyy`, `1x01`, `Ep03`, `Episode 23`: sometimes under `Season N/` folders

There are parsers to reuse:

- `parse_se` / `_SXE` (`tools/dedupe_orphan_episodes.py:44-70`)
- `_BARE_EP` / `_RANGE` (`tools/link_orphan_episodes.py:44-50`)
- `backfill_tv_episodes.parse_se` (:72)
- `tools/remediate_catalog.py:2359` (`part|reel|chapter|episode`)

All of them run on item titles and ids. None runs on the files inside an item.

### Options, smallest first

**A. Picker only (all five clients).** When an item's files parse as a
numbered run, the picker:

- orders by that number, with a natural sort as the fallback;
- leads each row with the number and the file's own title ("12 · The Long
  Sleep"), keeping height · format · size as the secondary line;
- groups by season when `Season N/` or `SxxEyy` is present.

The pipeline also makes episode/chapter 1 the default file for such an item
(`pick_video`). That fixes Spy Smasher starting at chapter 9.

Cost: `ArchiveVersions.swift` (covers three Apple platforms),
`ArchiveVersions.kt`, `watch.js`, `VersionsTask.brs`, `archive_lib.py`. This
answers the review exactly, but it still says "Choose Version" over what are
episodes, and the episodes still share one resume point.

**B. A bundle becomes an episode list.** A pipeline pass writes per-file
episode entries (`archiveID` + file path, number, title from the file name or
metadata) for items whose files parse as a run. Detail shows an **Episodes**
list (the series surface each platform already has) instead of Choose
Version, and progress and Watched key on `archiveID/file`. Decision 143's room
copy path is already `<item>/<file>`, so rooms fit.

Cost:

- the `Episode` identity (`Models/Catalog.swift`)
- progress keys on every platform, with a migration from `archiveID`
- the DB schema and the web index
- each platform's episode UI

Needs a NEW design-doc rule on every platform first. No doc covers "one item
holds a series".

**C. Fold bundles into spines.** Where a TVmaze spine exists (Thunderbirds
does, UFO does not), attach the bundle's files as its episodes. This depends
on B's per-file identity, so it is a follow-on, not an alternative.

**Recommendation**: ship **A** first. It is small, it touches only data the
clients already fetch, and it answers the reviewer word for word. Then propose
**B** through the design docs, because a shared resume point across 26
fifty-minute episodes is the real defect the reviewer will hit next. Whether
Spy Smasher, typed `short-film`, belongs in Movies at all is Decision 036's
question once B exists.

Rules a change must quote:

- iOS-DESIGN §3.5b. The doc says "Choose a Copy" and the code says "Choose
  Version": existing drift.
- ANDROID-DESIGN §10, WEB-DESIGN §4.4b, tvOS-DESIGN 4.1a.
- The literal-label rule (`ArchiveVersions.swift:50-52`).
- PARITY.md :456 and :471.

---

## 2. Theatrical cartoon series as groupings

### Coverage (visible app cards; duplicate merging is incomplete for Felix and Betty Boop)

| Series | Cards | Hidden | Note |
|---|---|---|---|
| Felix the Cat | 74 | 13 | many duplicate cards |
| Betty Boop | 86 | 23 (12 renewals) | many duplicate cards |
| Bosko | 54 | 22 (10 dead playback, 5 renewals) | |
| Van Beuren Tom & Jerry | 23 | 0 | only 1 upload says "Tom and Jerry" in its title |
| Color Classics | 32 | 5 renewals | |
| Superman (Fleischer/Famous) | 20 | 0 | all 17 shorts; **already a Collection** |
| Mutt & Jeff | 7 | 0 | |
| Molly Moo-Cow | 4 | 0 | all four |
| Gabby | 4 | 1 | |
| Puppetoons | 1 real | — | Ship of the Ether (1934); the other "Pal" hits are his features |
| Cubby Bear | 3 | 0 | |
| Tom Terrific | 3 | 1 | |
| Joseph Sunn clay, 1926 | 3 | 0 | archive.org confirms Sunn ("Ralph Wolfe's Mud Stuff") |
| Little Audrey / Baby Huey | 3 / 2 | 1 / 2 | archive.org has 108 / 64 hits |
| Stone Age | 2 | 0 | most of the 12 absent |
| Goofy Goat / Eshbaugh's *The Snowman* | 1 / 1 | 0 | *The Snowman* (1933) is presumably the reviewer's "Abominable Snowman" |
| Lariat Sam | 0 | — | 2 archive.org uploads never ingested |

Series serials: Spy Smasher 3 cards (a colorized feature, the bundle, B&W
chapter 1). Buck Rogers has only a colorized compilation and *Planet
Outlaws*, with no black-and-white chapters.

### How cartoons are grouped today

- Era shelves: `animation-all`, `vintage-cartoons`, `classic-cartoons`.
- archive.org collections.
- Studio browse (`item_studios`, `CatalogDB.byStudio`).
- A few keywords (`bosko`).
- `series-*` Collections (commit 32ecdcb07). These join on TMDb
  `belongs_to_collection`, which is **empty for every cartoon series measured**
  except Superman. Bosko has 50 of 54 cards with a tmdbID and 0 with a
  franchise.

Cartoon mode (`kidsCartoonPool`) is color-weighted, so silent Felix, Mutt &
Jeff and the Sunn films never appear there.

### A source that satisfies "no AI-written lists"

**Wikidata P179 ("part of the series")**, which the pipeline does not fetch
today. Joined live on our imdbIDs:

| Series | Films on Wikidata | Would join our catalog |
|---|---|---|
| Betty Boop | 33 | 22 |
| Color Classics | 22 | 21 |
| Superman | 17 | 17 |
| Looney Tunes (incl. Bosko) | 456 | 78 |
| Merrie Melodies | 476 | 59 |
| Popeye the Sailor | 54 | 26 |
| Aesop's Fables | 16 | 9 |
| Gabby | 1 | 1 |

Nothing was found for Felix, Mutt & Jeff, Molly Moo-Cow, Cubby, the Van Beuren
Tom & Jerry, Puppetoons, Baby Huey or Little Audrey. Those would need
archive.org subjects (uploaders' words, already in the catalog: "Felix the Cat"
20, "Betty Boop" 41, "Talkartoon" 11, "Screen Songs" 49, "Van Beuren Studios")
or a rule over fields: studio × years × a title pattern ("Molly Moo-Cow and…",
"Cubby's…").

**Proposal**: add P179 as a second feeder of the existing `series-*`
Collections, next to TMDb `franchise`. That is the same mechanism, the same
test (`tools/test_series_collections.py`) and no new surface. A series earns a
Collection only past a floor of joined, visible titles. Subject-based and
rule-based series are a second step, each needing its own control against
false members.

Ingest gaps (Lariat Sam, about 20 Mr. Bug uploads, the Stone Age shorts, Baby
Huey, Little Audrey) are a separate wants-list pass, and anything ingested
still faces the rights audit. Famous Studios and Terrytoons titles are being
hidden on renewals (Decisions 151/157), so expect a share of those to stay
hidden.

---

## 3. "Open Archive certified public domain" and Heartland+

**Not a usable source; nothing to build.**

- **Heartland+** is real: Get After It Media, the former Luken Communications,
  which owns The Heartland Network and Retro TV. It launched 2026-07-08 and is
  built by YuppTV.
- It does **not stream archive.org**. Its public API
  (`lukentv-api.revlet.net`) serves house assets from its own CDN as Widevine
  DRM DASH. No field mentions archive.org, public domain or any certification.
- **No "Open Archive" certification program could be found.**
  open-archive.org is the OpenArchive nonprofit's "Save" app for preserving
  journalists' and human-rights defenders' media, and it certifies nothing
  about film rights. Real clearance in this market is paid, private per-title
  copyright reports, which are not evidence a reader can open (Decision 151).
- Likely origin, inferred and not confirmed: a 2026-10-09 review on Heartland+'s
  own App Store page recommends Archive Watch, and Archive Watch shows under its
  "You Might Also Like". The reviewer may have merged the two apps.

Sources:

- https://en.wikipedia.org/wiki/Get_After_It_Media
- https://cordcuttersnews.com/?p=247070
- https://apps.apple.com/us/app/heartland/id6759033147
- https://ffdweb.org/projects/openarchive

---

## Owner calls

1. Whether to do option A (the picker) in the next update, and whether B (a
   bundle as an episode list, with per-episode progress) is wanted. B needs
   new design-doc rules on every platform.
2. Whether Wikidata P179 may feed `series-*` Collections. It is data, not
   copy, but it adds Collections to every platform.
3. The reply to the reviewer. It is outward-facing and posted under the
   developer's name, so it is not sent from here.
