# What a viewer said — John Howard, iPhone, 2026-10-20 to 10-27

Five emails from John Howard (echosoft.llc@gmail.com) to ben@learningischange.com,
thread "Archive Watch app suggestions". He is a heavy iPhone user: he has read
all ~2,000 TV Specials and keeps "a vast number of lists". Every item below was
checked against the code and the live catalog, not taken from the email alone;
file references are to `ArchiveWatch/ArchiveWatch/` unless they say otherwise.

## Status at a glance — 2026-10-27

| # | What he reported | What it really is | State |
|---|---|---|---|
| F1 | Fireball XL5's 39 colorized episodes | 39 b/w episodes now play (Decision 167); archive.org holds only 3 colorized | **Done**; reply owed |
| F2 | "Placeholder" uploads: Méliès "Nightmare", "Adam's Rib", "Gaslight" | Not placeholders: four wrong matches of ours, one a copyrighted 1989 feature | **Fixed** in `a7f5e4818`, live at the next publish |
| F3 | Can't remove a film from a playlist, rename one, or sort/reorder lists | True on iPhone: the playlist's contents have no edit path at all | Proposed below |
| F4 | Sort resets; no Z–A; Top Rated looks like A–Z; TV should default A–Z | All four true, on every platform, and Browse→TV's series grid has no sort at all | Proposed below; two owner calls |
| F5 | "Popular" for my lists should be my own arrangement | A manual order, which lists do not have | Proposed with F3 |
| F6 | Tapping TV Specials "queues" hidden Details until Home | A real defect class found; his exact path not reproduced | Repro first; two code fixes regardless |

---

## F1 — Fireball XL5 colorized (10-20)

His request raised Decision 167: `FireballXL5.complete` was served as ONE episode
titled "Fireball XL5." (the trailing period he saw). All 39 episodes now play on
the series page. **The colorized half cannot be met**: that item is black and
white (mean saturation 1.7 against 6.4 for a colorized upload), and archive.org
holds 3 colorized episodes, not 39. The owner's 10-20 reply promised the wider
fix ("about 60 other shows"), which landed as 150 items on 85 shows.

**Owed**: a reply saying the 39 are in, and that only 3 colorized exist.

## F2 — the "placeholder" uploads (10-23)

His theory, that archive.org reserves placeholders with the right catalog data
and a deliberately wrong video, is not what happened. Each upload is honest
about itself in its own archive.org record; we matched it to another film.

| Item | It is (its own record) | We served it as | Fix |
|---|---|---|---|
| `a-nightmare-on-elm-street-5-the-dream-child_202411` | A Nightmare on Elm Street 5 (New Line, 1989, 90 min, color) | Méliès' "A Nightmare" (1896), visible | `not_films` (copyrighted) + `match_rejects` |
| `Gaslight_628` | Fanny by Gaslight (its file; 6,188 s, the same as our `FannyByGaslight`) | MGM's Gaslight (1944) | match cleared, retitled, 1944 |
| `gaslight-1940-colorized-movie-576p-sd` | the 1940 British Gaslight, colorized | MGM's 1944 remake | match cleared, 1940 |
| `AdamsRib_201802` | a 412-second color music video | DeMille's Adam's Rib (1923) | match cleared; year and director scrubbed next pass |

**Why nothing caught the Elm Street one**: its title had been cut to "A
Nightmare" (so the title agreed with the match), and the runtime rule needs the
matched film's runtime, which the OMDb cache lacks for the Méliès short. A sweep
of all 301 visible items the runtime rule spares only on title agreement,
against archive.org's own titles, found no others (the one it found, a Sherlock
Holmes pilot, was fixed earlier today).

**Follow-up worth doing** (not started): the class "catalog title is a
truncation of archive.org's title and the match has no runtime" is still blind.
Closing it needs archive.org's own title for every matched item (~25k paced
fetches, the `fetch_archive_own_meta.py` pattern) and a rule in
`remediate_catalog.runtime_contradicts_match` that compares against it.

## F3 — editing playlists on iPhone (10-23, 10-23 correction, 10-27)

**What exists today** (`iOS/LibraryView_iOS.swift`):
- The playlist LIST is a native `List` sorted newest-first (`@Query(sort:
  \Playlist.createdAt, order: .reverse)`, line 23). Swipe right = Share, swipe
  left = Delete (`.onDelete`, 403-409, through `SyncNudge.recordDeletion`). The
  row's context menu holds only Share. No `EditButton`, no confirmation.
- A playlist's CONTENTS are the shared poster `grid(...)` (277-290), a
  `LazyVGrid` of buttons — not a `List`, so no row editing can attach. A
  long-press shows the generic film menu (`iOS/IPadPlaces_iOS.swift:40-78`:
  Favorites, Share), which does not know it is inside a playlist. Dragging
  (`.draggable`, regular width only) can only ADD to a playlist row.
- The only way to remove a film is Detail → Add to Playlist → untick.
- Nothing on any platform can rename a playlist.

**Other platforms already do more**: tvOS has "Remove from Playlist" in the
tile's context menu (`Views/PlaylistViews.swift:137-144, 187-196`) and Delete in
the playlist's; macOS has "Delete Playlist…" with a confirmation
(`macOS/LibraryView_macOS.swift:72-100`); Android and web have a visible Delete
with a confirmation. **iOS is the only platform where deleting a playlist is a
gesture alone** — the same defect the code's own comment records for Share,
which the owner "could not find" swipe-only (`LibraryView_iOS.swift:368-371`).

**The model** (`Models/UserState.swift:229-235`): `Playlist` has a mutable
`name`, an ordered `archiveIDs`, `createdAt`, `modifiedAt`; sync is
last-writer-wins per whole list (`touch()` + `SyncNudge.nudge`). So rename,
remove and reorder-within-a-list need NO model change. Two gaps do:
- **Order between playlists** has nowhere to live (no `sortIndex`). Adding one
  touches CloudKit (`Services/CloudKitSyncService.swift:69-72`), Android's Drive
  sync and the web, which rebuilds entries from five known fields and would
  DROP an unknown one on write-back (`js/cloudkitsync.js:81-83, 113-115`).
- **`createdAt` is wrong after a sync**: the cloud-insert path builds
  `Playlist(id:name:archiveIDs:)` (`CloudKitSyncService.swift:337`), stamping the
  pull time, so "newest first" means "newest on this device". A defect on its
  own; fix by carrying `e.createdAt`.

**Proposed fixes** (rules quoted are binding; one new rule is needed):
1. **Remove from Playlist** in the tile's context menu when the grid is a
   playlist — the tvOS verb, iOS idiom. *iOS-DESIGN §1.1 "Same verb, native
   idiom"*; *§9.4 every synced mutation goes through `SyncNudge`*.
2. **Rename** from the playlist's title (`navigationTitle($name)` +
   `toolbarTitleMenu { RenameButton() }`) and from the row's context menu.
   A name is the user's own copy, which the no-AI-copy rule permits.
3. **Delete you can see**: Delete (with a confirmation, as macOS words it: "It
   is removed from your other devices too.") in the row's context menu and the
   playlist's toolbar menu, keeping the swipe. *§4.3 "Destructive verbs are
   swipe actions"* needs amending: swipe stays, but a swipe is never the ONLY
   way to a verb — the owner's own Share finding, now John's Delete finding.
4. **Sort and arrange a playlist's contents**: a toolbar Sort menu (*§4.2
   "Facets/sort = a toolbar `Menu` of Pickers"*) with **My order · A–Z · Z–A ·
   Newest · Oldest**, plus **Edit** to drag films into "My order". Reordering
   needs a `List` (`.onMove`), so Edit shows the contents as rows; the grid
   stays the reading view. This is F5: "My order" is his "Popular".
5. **Sort the playlist list**: Name · Recently changed · Recently created. A
   manual order between playlists waits for an owner call (below), because of
   the sync cost above.
6. **Renaming an entry** (to tell a colorized copy apart): not proposed. The
   versions picker already distinguishes copies (Decision 158), and the
   placeholders he wanted to label were wrong matches, now fixed (F2).

New rule to add to `docs/iOS-DESIGN.md` before building (§4.3a, "a playlist is
edited where it is seen"), and rows in `PARITY.md` for remove / rename / sort /
arrange on every platform, since none of them are written down today.

## F4 — the category sort menu (10-23 correction, 10-25)

**Where**: `FilteredGridView` (`iOS/DiscoverSections_iOS.swift:48-158`), reached
from Home's category tiles and Browse→TV's "TV Specials" row. Its toolbar Sort
offers Popular · Top Rated · A–Z · Newest · Oldest.

**What he saw, confirmed in the code**:
- **It resets**: `@State private var sort: CatalogDB.Sort = .popular` (line 59);
  every push builds a new view, and `.id(store.dbVersion)` rebuilds it on every
  catalog swap. No platform remembers a sort (tvOS `@State`, Android
  `remember(route)`, web URL hash only, Roku none).
- **Top Rated = A–Z for TV**: Top Rated orders by `imdbRating`, then votes, and
  stops (`Store/CatalogDB.swift:581-589`). **No TV series card has a rating**:
  `tools/reconcile_tv_catalog.py` `series_card()` writes `imdbRating: None`
  and `popularityScore: None` (lines 81, 89), so every row ties and SQLite returns insertion order, which is
  slug order — it looks alphabetical. TV Specials: 3 of 120 rated in the seed DB.
- **No Z–A** anywhere (`CatalogDB.Sort`, tvOS `BrowseSort`, Android
  `BrowseSort`, web, Roku).
- **Browse→TV's own series grid has no sort control at all**
  (`iOS/BrowseView_iOS.swift:247-281`): always designed art first, then episode
  count.

**Proposed fixes**:
1. **Remember the choice**, per surface, in a UserDefaults key shared by name
   with tvOS (*§9.5 "UserDefaults keys are shared with tvOS by name … never an
   `ios`-suffixed twin"*; *§9.6 no new state without a home*).
2. **Add Z–A** on every platform in one change set (*§12.4 parity discipline*).
3. **Top Rated stops lying**: a tie-break (episode count, then title — tvOS
   already falls back to episode count) on every platform, AND either give
   series a rating or drop Top Rated where no row has one. Ratings could come
   from TVmaze through the `tvmazeID` each spine already stores — data, not
   copy — but which rating is an owner call.
4. **Give Browse→TV's series grid the same Sort chip** as Films (*§4.2a
   "Browse's filters are chips you can see"*).

## F6 — "hidden queued" TV Specials (10-27)

His words: tapping a TV Special "seemingly failed to reveal its catalog", so he
tapped others, and "my multiply chosen videos are hidden queued … before
remembering to press Home."

**On an iPhone held normally, the code pushes onto the visible stack**:
Browse→TV→TV Specials appends to `router.browsePath`
(`BrowseView_iOS.swift:251-254`); a tile calls `router.openDetail`
(`DiscoverSections_iOS.swift:68, 126-128`), which appends to the current tab's
path (`iOS/Router_iOS.swift:69-81`). Every destination is registered
(`RootView_iOS.swift:491-510`). So his exact path was not reproduced from the
code. Two real defects were found that produce exactly his symptom:

1. **Four direct `router.browsePath.append` calls** (`BrowseView_iOS.swift:187,
   196, 253, 269`; `CollectionsView_iOS.swift:29`) break *§2.4 "never mutate
   another tab's path directly"*. In the regular-width TV place
   (`RootView_iOS.swift:251`) they write to the Browse tab's HIDDEN stack: each
   tap does nothing visible and stacks a screen that appears later. Use
   `router.push`. (Home's tiles do the same at `DiscoverSections_iOS.swift:185,
   259`, harmless there but the same pattern.)
2. **No guard against repeated taps**: if a Detail is slow to appear, each
   extra tap stacks another. DetailView runs More Like This on the main thread
   (`DetailView_iOS.swift:646`). Ignore a push while one is in flight, and never
   push the same item twice in a row.

**Before claiming his case fixed** (CLAUDE.md: never iterate on behavior you
cannot observe): reproduce on the iPhone 12 and 15 Pro, portrait and
landscape, and ask him three things — which iPhone, held which way, and whether
"Home" is the app's Home tab or the system Home.

---

## Owner calls — ANSWERED 2026-10-27, built in 1.47.0 (Decision 170)

Owner: *"A-Z sorting by default makes sense with the ability to change and have
it remember. Yes to ratings on TV series (TV maze is great) and then please
implement full manual ordering for playlists, as it is a reasonable request."*
F3, F4, F5 and the two F6 code defects are built on Apple, web, Android and
(sorts only) Roku; the iPhone UI was pressed on the iPhone 12
(`test_30_playlistEditing`, `test_12_playlistShareIsVisible`). F6's exact path
on John's phone is still unreproduced: ask him which iPhone, held which way.

The questions as they were asked:

1. **Default sort for TV**: he wants A–Z; *iOS-DESIGN §5.1b* has the tv-series
   grid lead "deepest shows first by episode count" (Popular). Remembering the
   choice (F4.1) may make the default matter less.
2. **A rating for series**: TVmaze's, IMDb's (via TVmaze externals), or none —
   in which case Top Rated leaves the TV grids.
3. **A manual order between playlists**: worth a new synced field across
   Apple, Android and web, or are Name / Recently changed enough?

## Work order

F6 repro and the two router fixes (small, a defect) → F4.1 remember + F4.2 Z–A
+ F4.3 tie-break (one parity change set) → F3.1-3.3 remove / rename / visible
delete + the `createdAt` sync fix → F3.4 sort + arrange contents → F4.4 and the
owner-call items. Each lands with its `PARITY.md` rows and is pressed on a real
iPhone before it is called done.
