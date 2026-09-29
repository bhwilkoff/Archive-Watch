# Android design loop — phone and Google TV (2026-09-29)

Owner: *"Let's do a full audit of the android surfaces and app as well. This
includes both a full rundown of all features that show on Android Phone as well
as all features and interface elements on the Android/Google TV implementation
as well."*

Binding docs: `docs/ANDROID-DESIGN.md` (phone), `docs/TV-DESIGN.md` (Android TV
+ web-TV). Parity: `PARITY.md`. Method as in the tvOS, Mac and iPad loops:
inventory from the code, then every surface on the glass, one commit a tick.

## Devices

- **Pixel 8a**, Android 17 beta, `10.0.0.175` over TLS ADB. Kept losing its
  pairing: `adb_allowed_connection_time` was 604800000 ms (7 days), which
  revokes a computer's wireless-debugging trust; set to 0 on 2026-09-29.
- **Google TV Streamer** (SEI Dongle R 4K), Android 14, `10.0.0.55:5555`. Drops
  its ADB connection when it wakes from the screensaver; reconnect.
- Debug build `com.archivewatch.app.debug`, flavor `google`, versionCode 65.
- Use only `~/Library/Android/sdk/platform-tools/adb` (a second adb binary
  restarts the server).

## First look (tick 1)

- **Google TV Home**: TONIGHT · The Farmer's Wife (1928) leads the hero, with a
  three-line synopsis; the rail is icons only and holds Cartoons (palette) and
  Party Play (confetti) as their own entries.
- **Phone Home**: the hero showed Tanned Legs (1929), not the Tonight film;
  Continue Watching shows the year under each poster, not the time left, and
  no progress bar.

## Inventory (tick 1, from the code)

**Shell.** One activity; `isTelevision()` picks `TvAppRoot` or `AppRoot`;
navigation is plain state (`Nav`: a tab + one route stack, 14 route cases).
- Phone: `NavigationSuiteScaffold` — Home, Browse, Channels, Search, Library;
  Settings and Surprise from Home's top bar.
- TV: `TvNavRail` (icons, expands on focus) — Home, Browse, Channels, Search,
  Library, then Collections, Cartoons, Party, Surprise, Settings.

**Phone surfaces**: Home (hero + Tonight eyebrow, category tiles, Continue,
featured, Top Rated, Watching Now, Community, Most Discussed, Hidden Gems,
director shelves, PD Day, eras) · Browse (scope chips, decade/length/facet/
sort menus) · Search · Channels (proportional guide, create channel) · Library
(Favorites, Continue, Playlists, History, Clips; Join a room) · Detail (action
row: Play, Favorite, Playlist, Watched, Choose a copy, Get subtitles, Clip,
Share; ⋮ Watch Together / View on archive.org / Something wrong) · Series ·
Player (options sheet: next episode, speed, subtitles, copies, autoplay; PiP;
Cast) · Filtered/PD explorer · Surprise · Playlist · Collections · Person ·
Cartoons · Shared list · Clip Studio · Settings · 3 widgets, 2 shortcuts.

**TV surfaces**: Home (TvHero, left/right cycles) · Browse · Channels (shared) ·
Search (keycaps, browse-without-typing doors) · Library (Favorites, Continue,
History, Playlists, Watch Together join keypad) · Detail (Play, Favorite,
Watched, Playlist, Share QR + report toggle, Watch Together, Version, Part of
series; Cast & Crew, reviews, Scenes, More Like This) · Series · Collections ·
Cartoons · Party · Surprise · Settings · Player (options panel on Up/Menu) ·
Google TV Watch Next.

## Findings (tick 1)

Parity gaps (another platform has it, Android does not):
- A. ✅ v1.42.942 Channel up/down, phone and TV (`ChannelSurf.kt`, Apple's
  rule). TV: Up/Down and CH+/CH-, the channel named over the program, a held
  Select or Menu opens Player Options. Phone: a ▲ channel ▼ capsule. Pressed
  on the Google TV (down, down, up = Comedy Hour, Crime & Mystery, Comedy
  Hour) and tapped on the Pixel, muted. The first phone tap CRASHED the app:
  the next player's MediaSession was built before the old one was released,
  and both took the default id; each session now has its own. Also: a
  channel's options no longer offer "Play Next Episode" or "Autoplay next"
  (skipping breaks the one clock), and a Party lineup's skip reads "Play
  Next". New DEBUG door `--ez aw_mute true`: this box's volume is HDMI-owned
  and `media_session volume --set 0` does nothing.
- B. Commercial Breaks on/off: no setting on Android (PARITY ⏳).
- C. ✅ v1.42.935 Continue Watching shows the time left and a progress bar on
  phone and TV, in the Apple apps' words ("1h 8m left", "43m left"). On the
  way: progress saved under a merged-away id found its card and lost its
  numbers (Alice in Wonderland, Caligari showed a year) — keyed now by the
  card shown (CatalogDatabase.itemsByIDsKeyed). Seen on both devices.
- D. ✅ v1.42.938 Phone Series page: Favorite and Share beside the title,
  under the series card's own `series:<slug>` id as on TV and tvOS, sharing
  archivewatch.org/series/<slug>. On the Pixel (The Lucy Show): the heart
  filled and favorites went 13 -> 14, and back to 13 on the second tap.
- E. ✅ v1.42.939 Cartoons and Party Play leave the TV rail (now eight
  entries) and open from Surprise, beside Re-roll, as on every platform
  (owner 2026-09-28, tvOS-DESIGN §2.2a). On the Google TV: Party Play opened
  from Surprise ("Mixing the party reel…") and Back returned to it.
- F. Downloads (PARITY ⏳, six rows) — the largest gap.
- G. Not a defect. tvOS carries the report inside its Share sheet too
  (`ShareSheet.reporting`), and TV-DESIGN/tvOS-DESIGN say it is "never a
  primary control". Android matches.

Stale records:
- H. PARITY cells say ⏳ for things in code: PiP, background play, autoplay,
  category toggles, widgets; §8b sync.
- I. ANDROID-DESIGN §3.2 (routes), §4.2b (TV Scenes "not built"), §4.5
  (Library), §7 (out-of-scope list contradicts the code); TV-DESIGN §2
  (Movies/TV rail entries that do not exist).

Harness:
- J. `aw_start_tab` / `aw_start_route` are collected only by `TvAppRoot`; the
  phone can be driven only by `archivewatch://` hosts and taps.

- K. ✅ v1.42.934 (seen on the Google TV) **TV Search: the keyboard's sixth column is cut off** — F, L, R, X, 3
  and 9 sit half under the "Or browse without typing" panel (1920-wide
  capture, so not a crop). A fixed 430 dp column left 362 dp inside the
  overscan margin for six 58 dp keys that need 388; the column is now sized
  from its keys. The decade doors run to the 2020s and every decade has
  titles in the live index (2020s: 84), from db.decadeCounts() — kept.

- L. ✅ v1.42.937 Google TV Home: a category tile lost its background once
  focus had passed through it (Silent Era read (24,24,24), the page). The
  tile painted its gradient OUTSIDE tvFocusable's scaled, shadowed layer, so
  the focused tile scaled its label and not its color, and the layer left
  behind drew nothing. Focus now wraps the paint, as on TvPosterTile; focused
  and after focus left, the tile stays gold (seen on the Google TV).
- M. ✅ v1.42.936 "1m left" on Nosferatu (93 min) and Alice in Wonderland: the
  TV's user.sqlite (copied off with run-as) stores a ~2-minute duration for
  both, and for Four Horsemen (100% of it, so "watched"), all 2026-09-18 —
  written by the DEBUG `aw_play_url` door, which plays a local sync clip
  under the film's id during the Studio bench runs. The door no longer
  writes progress. The three records were deleted from the Google TV's
  user.sqlite (7 -> 4 rows, integrity ok; the TV never signed in to Drive sync,
  so nothing restores them); Continue Watching now reads Morocco, Caligari,
  Sherlock Jr., Battleship Potemkin.

- N. ✅ v1.42.941 Surprise took 6.3 s to fill on the Google TV (measured:
  twelve picks at ~350 ms, the first 2.4 s; the DB was already open). Each
  pick joined every matching row's JSON blob before the random sort, then
  decoded twenty to keep one. Ids are now drawn first, verified-playable
  only (a playable row always has a URL), one per pick, and the seven
  feature films come from one query: 1.6-2.3 s over two cold launches. One
  shared `surpriseDoors()` serves the phone and the TV, which had copies.
  Also "Broken Stings" (1940) -> "Broken Strings" (id, poster, IMDb
  tt0135173), seen in the phone's Surprise.
- O. A title missing its first letter: "tate Speeds Case Against Hauptmann"
  (1935), as archive.org's own title spells it; its id says "State". Fixed
  by title_corrections.json (takes effect at the next publish). 133 visible
  titles start lower-case, most of them an upload's id ("thegreatestquestion",
  "md45465423", "von Sternberg, Josef" for Der blaue Engel): a catalog
  cleanup, logged here, to be done in the pipeline.
- P. ✅ v1.42.947 A channel program with minutes left (or a short cartoon) was
  a sliver whose title wrapped a letter a line ("I • 1" on the Google TV,
  "P A ' T" in Cartoon Classics on the Pixel). Under 110 dp (TV) or 72 dp
  (phone) a block now shows no text, as tvOS does since v1.42.852. Two more
  on the way: the TV guide row was 64 dp while its blocks asked for 84, so a
  two-line title ran into its time; and a block's color was painted outside
  its focus layer (inset under the ring, the Silent Era tile's mistake). Seen
  on both devices.
- R. ✅ v1.42.943 "Autoplay next" was read by NOTHING that plays: the switch
  in Settings and both options panels wrote a preference no player consulted.
  Now a film chosen by the viewer that ends with it on shows an Up Next card
  (the first unwatched More Like This film, 8 s, Play Now / Cancel; the web's
  end card, Apple's More Like This mode); never for a channel, lineup, room
  or live broadcast. Seen on both: Coughs and Sneezes -> So Much for So
  Little, muted; TV focus lands on Play Now. The owner's setting (Off) was
  restored on both devices and read back from the DataStore file.
- S. ✅ v1.42.944 Player Options > Copies marked nothing until the viewer had
  chosen one; the pipeline's copy is now read off the playing URL
  (`ArchiveVersions.playingKey`) and marked, phone (radio) and TV (✓). The
  TV row's two-line cap then cut the marked label ("Archive deri…"); the cap
  is gone. The shortened names ("and_sneezes_TNA_512kb") are by design: the
  stem is cut at a separator only when two copies would read the same.
- T. ✅ v1.42.945 Phone Detail: the action row SCROLLED, so Share and More
  sat off the screen behind a half-drawn icon. Now Decision 134's rule: the
  actions in priority order (Favorite, Playlist, Clip, Share, Watched, Choose
  a copy, Get subtitles), as many as the width holds stay icons, the rest
  head the More menu with their words. Pixel 8a: Play, Favorite, Playlist,
  Clip, Share, More; More opens with Mark as watched, Choose a copy, Get
  subtitles, then Watch Together, View on archive.org, Something wrong.
- U. ✅ v1.42.945 A channel tune-in entered the watch history within five
  seconds: the 60-second rule read the PLAYHEAD, and a channel joins its
  program minutes in. Decision 078 says 60 seconds of viewing. It counts
  seconds played now. Google TV: two 20 s tune-ins wrote nothing; the
  control, 75 s on one channel, wrote its program (then removed).
  Test residue: my runs today wrote rows to both devices' histories. The TV
  (no sync) is restored to its four rows, byte-matched. The Pixel's rows
  (Coughs and Sneezes, So Much for So Little, Beggars in Ermine, and a bumped
  The Bold Caballero) had already synced to Drive, and history is a union
  with no tombstone (Decision 078), so a local delete would come back:
  asked the owner.
  tvOS had the same defect (`WatchProgress.record` guarded `position < 60`
  with the playhead); v1.42.946 feeds it seconds watched. Built for tvOS,
  iOS and macOS with zero warnings (two stray `await`s fixed on the way);
  NOT run on an Apple TV, because its history syncs to the owner's iCloud.

## Queue

1. ✅ J — phone launch doors: one shared `Nav.collectStartDoors()` in both roots (v1.42.933); the Pixel opened Library, the TV Search
2. Walk every surface on both devices; the glass decides C, E and the hero
3. ✅ Kotlin warnings: 8 distinct (16 across both flavors) -> 0, both compile tasks re-run (v1.42.932)
4. D, E, G, A, B; then H and I with each change; F is its own project
