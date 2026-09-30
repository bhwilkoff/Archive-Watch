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
- B. ✅ v1.42.948 Settings > Commercial breaks (default on, as iOS and the
  web), read by the channel weave. Pixel, one channel, muted: queue 22 with
  it off, 43 (22 programs + 21 breaks) with it on; the owner's value is back
  on. Also cut three captions that explained their own switch ("Hidden by
  default. Applies everywhere.", "Completed titles disappear from Home
  shelves.", "Keep playing when an episode or film ends."), CLAUDE.md's
  essential-information rule.
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
- H. ✅ v1.42.949 PARITY's Android cells rewritten from the code and the glass:
  PiP ✅ (seen on the Pixel: a channel pinned over the home screen, muted),
  category toggles ✅, playback options ✅, three Glance widgets ✅, Cast 🚧
  (hand-off built, never seen on a receiver). §8b sync was already right.
- V. Background play, MEASURED before building: a muted channel on the Pixel,
  another app brought to the front (the app went to PiP), audio "started" at
  5, 30, 60 and 120 s. The case PiP does not cover is screen-off, which cannot
  be tested here (owner: never sleep a test device), and a mediaPlayback
  foreground service would add a Play Console FGS declaration to the next
  release. Not built on a failure nobody has observed; PARITY stays ⏳ with
  this reason.
- I. ✅ v1.42.950 ANDROID-DESIGN rewritten against the code: §3.2 names all
  14 routes, §4.2b (TV Detail has Scenes), §4.5 (History tab, Join a room),
  §5.3 (channel history by seconds watched, up/down, Up Next), §7 (seven
  "next wave" items had shipped; Downloads, background audio and VHS remain).
  TV-DESIGN §2 was done with E.

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
- W. ✅ v1.42.951 Surface walk (phone: Browse, Library, Collections, Search;
  TV: Browse, Library, Collections, Settings). Fixed and seen: TV Settings
  read "SETTINGS" over "Settings", its title 48 dp in from its sections
  (TvPageHeader's own inset doubled the column's); TV Browse drew a "·"
  between the sort and era chips that read as a speck; phone Search's empty
  page restated the field's placeholder in a sentence. Checked and kept: the
  Library tab row scrolls ("Clip…" at the edge is Material's scroll cue),
  and Collections' descriptions are archive.org's own words.
- X. ✅ v1.42.952 Capped lists shown as totals, phone and TV: the decade and
  category grid read "1930s · 240 titles" and ENDED at 240 (4,534 exist);
  every collection's count was a 240-capped list's size (Film Noir 559,
  Feature Films 12,104) and its page stopped at 240. Now a COUNT for the
  number and paging (60 / 120 at a time, as Browse does) for the grid. Seen:
  "4,534 titles" and the TV grid past row 16; Collections' real counts on
  both; Feature Films on the Pixel well past 120. Cartoon Mode's "240
  cartoons" is its lineup pool, not a catalog count (left for now).
- Y. OWNER CALL (content, Decision 027/105): "Devil In Miss Jonas" (1974,
  a West German sex comedy by its own synopsis) is isAdult=0 and kept in the
  1964-77 renewal band, so it shows in Feature Films with mature content
  hidden.
- Z. ✅ v1.42.953 Back lost the viewer's place, phone and TV: a tab left
  composition under a pushed title, so Home rebuilt (spinner, new hero, scroll
  at the top) and the TV put focus back on the hero. Now a per-tab
  SaveableStateHolder keeps scroll and tab state, Home's last payload is
  reused for the same inputs, and the TV Home returns focus to the tile last
  focused (the hero clears it). Seen: the Pixel came Back to Silent Hall of
  Fame exactly; the Google TV to Carson City Kid in Popular Feature Films;
  Library stays on Playlists.
- AA. ✅ v1.42.953 Phone playlists: Delete removed a playlist in one tap (the
  TV asks); it asks now (pressed Cancel on the Pixel, the playlist stayed).
  "1 titles" -> "1 title". The Person page's "Titles featuring <name>" under
  the name is gone (the TV header shows the count instead).
  Test residue: "Phone Glass Test", a playlist a 2026-09-14 test imported
  (commit e4c0030ea), was deleted through the app, so its tombstone reaches
  Drive.
- AB. ✅ v1.42.954 TV Series (and tvOS, the same code shape): "1 season" was
  counted from the episodes held and sat over the only one, S3 · E1 of a
  six-season show (Here's Lucy); the count shows now only when every episode
  is held. The footer "1 of 144 episodes available — more are added as they
  surface in the archive." repeated the header's "1 of 144 episodes" and
  explained itself; removed on both. Seen on the Google TV; tvOS, iOS and
  macOS build clean, not run on an Apple TV.
- AC. ✅ v1.42.955 TV Search results: four fixed columns beside the keyboard
  squeezed each tile to ~80 dp, so titles broke inside words ("Dishonor / ed
  Lady"); now adaptive, three across. And the grid anchored on its first
  visible KEY as the query grew ("noi" -> "noir"), so a new search opened
  scrolled past its first results; the grid state is keyed on the query and
  filters now. Seen on the Google TV: "noir" opens on Noir (1946). The phone
  grid had the same anchor; fixed in v1.42.956 and seen on the Pixel (typed
  n-o-i-r a letter at a time, opens on Noir, 1946).
- Y (more): "Messe noire" shows nudity in its poster in TV search results
  with mature content hidden; the same owner call as Devil In Miss Jonas.
- AD. ✅ v1.42.957 Library, phone and TV: Continue Watching showed no time
  left or progress (Home has since v1.42.935); one shared
  `continueWithProgress()` now feeds Home and both Libraries. TV Watch
  Together: the join keypad needed ~555 dp under the tabs, which leave ~420,
  so G-Q was cut and R-Z unseen; it is two columns now (title and slots,
  keypad and Delete), every key reachable. And the Watch Together and empty
  Playlists sections fell through to the grid's empty message ("Nothing in
  progress…" under the keypad); History had borrowed that message too. Seen
  on the Google TV and the Pixel.
- AE. ✅ v1.42.958 An episode's More Like This (phone and TV, one query) was
  the type-and-era fallback: other shows' episodes, the same show repeated
  (Lucy and the Little League -> 13 Demon Street x2, 26 Men x3). Now the
  episode's own series first (its episodes and specials), then one card per
  other show. Seen on the Google TV: three Lucy Show titles lead the row.
  tvOS scores episodes by shared collections and was not changed.
- AF. ✅ v1.42.959 Clip Studio's filmstrip stayed EMPTY (Pixel, The General,
  two minutes). Two causes. The timeline's AndroidView update read the
  thumbnail list's reference, never its contents, so arriving frames never
  re-ran it and a paused editor never redrew; it reads a copy now. And the
  frames came from MediaMetadataRetriever over the remote film, one frame in
  two minutes; they come from archive.org's own per-minute frames for that
  file now (`ArchiveVersions.frames`, shared with Scenes), the decoder only
  when a copy has none. Seen: the strip fills. Measured: an open costs ~30 MB
  (the preview's buffer and the probe) and stays flat for 160 s idle.
- AG. OWNER CALL (claim, all platforms incl. the Mac Creation Studio): an
  exported clip burns "archivewatch.org · Public Domain" whenever the rights
  status is not Creative Commons, and the catalog marks 1964-77
  renewal-zone and commercial_keep titles "public_domain" too, so a
  fair-use clip (Decision 146) of such a title would claim public domain.
- AH. ✅ v1.42.960 Clip Studio, exported end to end on the Pixel (The
  General, 15 s, 9:16): a valid 1080x1920 H.264 + AAC file, credit burned in.
  Found and fixed: (1) the result page's 9:16 preview at full width was taller
  than the phone, so Save, Share and Done were below the screen with no way
  to scroll; the preview now takes the height left over. (2) The file said it
  was made on 1970-01-01 and carried no source link, while the editor promised
  "the source link in their file metadata"; the muxer now writes the creation
  time and Apple's title + description ("Public-domain source: <details URL>
  · Clipped with Archive Watch"), read back with ffprobe. (3) Library > Clips:
  a long press deleted with no question and left the video file; it asks and
  removes the file now. A clip whose cached file is gone says so on tap.
  Rows no longer repeat the title and read "15.0 s · 9:16", not VERTICAL.
  The empty state no longer says "public-domain title" (Decision 146).
  Test residue: three exports landed in Clips; deleted through the dialog,
  clips 3 -> 0 and cache/clips 3 -> 0 files (baseline 0).
- AI. ✅ v1.42.961 Party Play's mix showed "Women" (2021), a horror film's
  poster, on a room-filling lineup. It is `Women-at-NASA`, a 4-minute NASA
  short: the uploader-cruft rule `@\s*\S+` read "@ NASA" as a handle and cut
  the title to "Women", and TMDb matched the 2021 film (poster, synopsis,
  year). The rule is `@\w\S*` now (a handle has no space after its @; none of
  the 36 catalog titles with an @ changes today); the title is restored by
  title_corrections.json; and a new shared/editorial/match_rejects.json
  ({archiveID: reason}) clears a match a person names wrong, through the same
  path as the runtime rule (cleared_editorial, so the scrub drops the borrowed
  2021 year). tools/test_title_handle_and_rejects.py holds both, with controls.
  Takes effect at the next publish.
  TV Party page: its header was written copy ("A silent wall of color for the
  room — …"); it says only "Plays muted — hold Select for sound." And the page
  opened scrolled with its title off the top and no way up (a lazy list with
  two items); it is a plain Column that fits the screen. Seen on the Google TV.
- AJ. ✅ v1.42.962 Cartoon marathon opened on "NASA eClips Video Series 360",
  NASA's 30-minute magazine program. Two layers. The app: Android's Cartoon
  pool took ANY animation; it is now Apple's KidsContent rule (designed art,
  never silent, no scary genres/subjects, color-leaning; the full character
  list) in one `CartoonMode` shared by phone and TV, read from list rows plus
  four json_extract fields (800 full decodes had cost 9.9 s on the Google TV;
  now 4.7 s). The data: nasa_360 wore IMDb "NASA Seals", whose Animation genre
  typed it animation, and the cleared-match scrub (Decision 150) let the
  TYPING vouch for the genre — circular. Only the item's own subjects or
  collections vouch now, and a cleared match left with no animation genre is
  re-typed by content_type.classify. Measured on the live catalog: exactly 5
  visible items change type, all live action: The Gaucho (1928), You And Me
  (1938, Lang), Phantom Ship, A Christmas Carol (1910), a NASA "moon" clip;
  no genuine cartoon moves. nasa_360 is in match_rejects.json. Tests:
  test_title_handle_and_rejects.py (+2 cases with a control),
  test_scrub_cleared_match.py unchanged and passing. Takes effect at the
  next publish.
  Player Options now offers "Autoplay next" only on a film the viewer chose:
  on a marathon, a lineup or an episode run it did nothing.
- AK. ✅ v1.42.963 Phone Create a Channel: the Type chips were raw ids
  ("feature film", "silent fi…") and the lists were shorter than Apple's;
  they are Apple's words and lists now (16 genres; Documentary in place of TV
  Special, since a channel is built of films). Deleting a user channel was a
  long press with no question; it asks. Created "Comedy Feature Film" on the
  Pixel (it led the guide: A Bucket of Blood, …), deleted it through the
  dialog: channels 0 again, a `ch` tombstone written so Drive drops it too.
- AL. ✅ v1.42.964 (data) Library sort titles left inverted ("Ravager, The",
  "Evenings on the farm near Dikanka, the."): sanitize_title returned early
  with an AUDITED title that was itself in sort form, skipping the inversion;
  and ", the." with a period never matched. Both fixed; measured on the live
  catalog: exactly 4 visible titles change, the four found. Tests added with
  a control. Next publish.
- AM. 🚧 v1.42.965 Watch Together on the phone offered Twitch sign-in only;
  Decision 136's "use my own stream key" was never built on Android, which
  also left Android no route to YouTube. The go-live dialog now has "Sign in /
  Stream key": YouTube or Twitch, a masked key, "Find your stream key"; the
  key goes to the platform's documented RTMPS ingest, held in memory for the
  show and cleared by StudioController.end. Seen on the Pixel; NOT yet run
  with a real key (that needs the owner's key and is a broadcast).
- AN. ✅ v1.42.966 Phone Detail and Series: the white status bar and back arrow
  sat straight on the backdrop and vanished on a bright one (The General); a
  top scrim now carries them. Seen on the Pixel.
- AO. ✅ v1.42.967 Phone Browse: the Decade, Length, Keyword and Studio menus
  were siblings of their buttons, so each opened against the scrolling row's
  left edge (the Keyword list covered the status bar on the left, far from its
  button). Each is anchored in a Box with its button now. Seen on the Pixel.
- AP. ✅ v1.42.968 Phone Series page: the season menu had the same missing
  anchor (it would open from the header's corner) — anchored, and it carries a
  dropdown arrow so it reads as a menu. The show's synopsis was cut at four
  lines with no way to read the rest ("…together they ser…", Adam-12); a tap
  opens and closes the whole text. All unanchored menus in the app are now
  checked (Search's sit in their own Column and were fine). Seen on the Pixel.
- AQ. ✅ v1.42.969 Phone Settings walked (Subtitles, Live Caption, Sync,
  About): working; the signed-in Drive line names the account and last sync.
  Two captions tightened to what a viewer cannot discover: Live Caption is one
  sentence (how to turn it on), and signed-in Sync reads "Syncing through your
  Google Drive · <account>". The signed-out text keeps its privacy fact and the
  TMDb notice is required attribution. Widgets are NOT placed on the owner's
  home screen to test (that changes their launcher); code-read only.
- AR. ✅ v1.42.972 OWNER: "we can probably only claim creative commons or fair
  use for created works with Archive Watch." Decision 153: every exported clip
  says "archivewatch.org · Creative Commons" or "· Fair use", never Public
  Domain, on Android, iOS and the Mac Creation Studio (credit, file
  description, explanatory text). All five builds clean.
- AS. ✅ v1.42.974 OWNER: "Any 'mature movie' should be marked as such ...
  hidden from Party Play by default unless mature items are turned on." The
  existing `isAdult` flag already does all of that (shelves, hero, Party Play,
  every surface: `adultAnd` in Android's `browse`, the same gate on Apple, web
  and Roku) — what was missing was the MARKING. `is_adult_signal` now also
  reads archive.org's whole "Adult" subject and a synopsis naming an adult
  genre (sex comedy, softcore, sexploitation, erotic drama/comedy/thriller,
  nudie). Measured: 22 visible titles newly marked (Messe noire, Felicia, The
  Boob Tube, Maid For Pleasure...); controls in the test: "adult education",
  a burlesque parody, Haxan. Takes effect at the next publish.

- AT. ✅ v1.42.975 OWNER: "You should be able to remove items from history
  if you want." No platform could except iOS (swipe). Now: Android phone
  long-press and TV held Select (TvConfirm), web × per card, tvOS held Select,
  Mac right-click. One stone kind, Apple's `wp:<id>`; the Drive merges on
  Android and the web now honor it (Apple's CloudKit pull already did). Pressed
  on the Pixel (the three leftover test entries removed; a restart's Drive
  merge against a cloud copy that still held them kept them gone), the Google
  TV (Cancel returns focus to the card, Remove to its neighbor; history
  byte-identical to before), Kitchen (tvOS) and the web (stale cloud copy stays
  gone; a later watch returns). The Mac item is built, not clicked.
- AU. ✅ v1.42.975 Library opened History scrolled to the middle: one grid
  state shared across tabs anchored on the first visible KEY (Favorites' first
  film, which sits deep in History). A state per tab, phone and TV.
- AV. Observed, not a defect: my "Phone Glass Test" playlist was still on
  Apple after the Android delete — Android and Apple are separate sync islands
  bridged only by a web session signed in to both (D102). Deleted on Kitchen.
  Also observed on tvOS: after a context-menu removal, focus stays on the
  next card but its focus effect is not drawn until the next press.

- AW. ✅ v1.42.976 Release lint, both flavors: NewApi 0 (Decision 141 holds);
  errors 41/44 -> 0. Real: a FocusRequester made during composition (mine, AT),
  LocalContext cast to Activity (LocalActivity now), a literal byte-order mark
  in OpenSubtitlesClient's trim (now an escape), and a British "initialised"
  on the microphone's error (test_us_english now knows the family). The 27
  opt-in errors were one cause: StudioController and StudioFilmAudioTap were
  annotated @UnstableApi, which REQUIRES opt-in of every caller, where they
  meant to opt in themselves. Suppressed with the reason at the site: tvprovider
  builders (RestrictedApi on its own documented calls), and the amazon flavor's
  camera/mic/service checks (the Studio's sources sit in main, Decision 132).
  122 warnings remain, next.

- AX. ✅ v1.42.977 Lint warnings 122 -> 43, and the 43 are all dependency /
  AGP / targetSdk / version-catalog notices (next, as their own tested pass).
  Behavior found on the way: the Studio held the ACTIVITY statically for a
  whole show (now the application context); the foreground-service types were
  passed from Android 10, where they do not exist (now 11+); timecodes and
  "Clip 15.0s" formatted in the device locale inside English text (now US);
  PiP entered from onUserLeaveHint only — Android 12+ now auto-enters with the
  film's own rect as the source hint (seen on the Pixel: pinned on Home);
  ClipTimeline allocated six rects every frame. lintFix's KTX rewrite broke
  StudioTokenStore.save's Boolean (the one-time Twitch refresh token must
  report whether it landed) — restored by hand. Clip Studio's "Drag the
  filmstrip to scrub…" explained the control's own behavior: cut (owner's
  essential-information rule).

- AY. ✅ v1.42.978 Dependencies, stage A: Kotlin 2.1.21 -> 2.4.20 (the build
  was already running KGP 2.2.10 through AGP, under a catalog that said 2.1),
  Media3 1.11.1, Compose BOM 2026.09, Coil 3.6.3, coroutines/serialization 1.11,
  lifecycle 2.11, activity 1.13, datastore 1.2.1, sqlite 2.7.1 and the rest; the
  six inline versions moved into the catalog. The manifest merge caught two that
  need Android 7 — material3 1.5.0-alpha20+ and play-services-auth 22 — so both
  are held, with the reason in lint.xml (Decision 141). Seen: the RELEASE (R8)
  build on the Pixel launches, renders Home and plays (media session PLAYING,
  volume restored); the debug build plays on the Google TV (AudioTrack started,
  client-muted, ~25 fps decoding). Left: AGP 9.4 / Gradle 9.8, OkHttp 5,
  targetSdk 37. The TV's own Play copy (1.42.691) crashed once on a catalog
  swap — Pulse's known build-60 defect, fixed in 1.42.692, awaiting approval.

- AZ. ✅ v1.42.979 Dependencies, stage B: AGP 9.2.1 -> 9.4.1, Gradle 9.5.1 ->
  9.8.0 (wrapper regenerated). Floor still 23; the new R8's release build
  launches and plays on the Pixel. Also walked: a shared-list link (3 of 4
  titles, the missing one named in a count) and both launcher shortcuts, which
  land correctly but drew Android 2's menu glyphs (ic_menu_rotate /
  ic_menu_view) — now adaptive icons in the brand's dark and marquee orange.
  Watch Next publishes on the Google TV (row inserted after 17 s of play), and
  Remove from history left that row on the launcher; it now removes it too
  (seen: "watchNext remove … rows=1", history back to its five rows).
  Left: OkHttp 5, targetSdk 37.

- BA. ✅ v1.42.980 MY REGRESSION, from stage A (v1.42.978): the Google TV
  crashed opening Settings — `AbstractMethodError: CustomStyle.applyStyle`.
  material3 was held at 1.5.0-alpha19 for the floor, but Coil 3.6.3 pulled
  Compose foundation to 1.12.0 stable, past the 1.12.0-alpha02 alpha19 is
  built on. Both flavors compiled; only the glass could see it. Coil and the
  BOM are back where material3 needs them, and foundation is pinned STRICTLY,
  so the next drift fails the build (control: Coil 3.6.3 refuses to resolve).
  Seen: TV Settings renders; phone Settings/Surprise/Collections, no crash.
  Owner, the same hour: floor low, modern devices not hamstrung — Decision 154.
  OkHttp 5 (debug-verified: posters from an empty cache, playback) is held out
  of this commit until its release build has run.

- BB. ✅ v1.42.981 Dependencies, stage C: OkHttp 4.12 -> 5.5 (Media3's and
  Coil's OkHttp adapters now run on 5). Seen: posters from an emptied image
  cache and playback in the debug build; launch and playback in the R8 release
  build on the Pixel. TV Detail: the synopsis stop (kept so a long synopsis can
  scroll into view) showed focus only as grey-to-white text — from the couch,
  focus vanished between Version and the cast row. It now rings like every
  other stop, text still aligned with the title. The "Something wrong?" form's
  prefilled ids (film, where) match the issue template. Only targetSdk 37 is
  left of the dependency notices.

- BC. ✅ v1.42.982 Dependencies, stage D: targetSdk 36 -> 37, after reading
  Android 17's target-gated changes against the code: no reflection
  (MessageQueue / static final); widget posters are 300x450 (~0.5 MB each,
  far under the RemoteViews limit); no app-owned LAN socket (Cast discovery
  runs in Play services; the Studio sends only to YouTube/Twitch); audio plays
  only while visible (the Studio's service carries camera/microphone types);
  the fullscreen landscape request is merely ignored on tablets. Seen on the
  Pixel, which RUNS Android 17: launch, playback, PiP with the audio track
  still started, Drive sync merge, no SecurityException. The TV is Android 14.
  Lint: the dependency notices are gone apart from the documented holds.
- BD. OPEN — Cast has never been seen working on Android (PARITY already says
  "on-device verification needed"). With a Google TV (mediashell running) on
  the same subnet, the player shows no Cast button at targetSdk 36 AND 37:
  the Cast framework loads, Play services' mDNS for _googlecast answers ("B6t"),
  yet MediaRouter's Cast provider holds no routes. Next: observability first —
  log the selector, route callbacks and CastState in CastSupport, and compare
  with a known sender (YouTube) on the same phone before changing anything.
  Measured 2026-09-29 17:13 (AWCAST, debug-only diagnostics in CastSupport):
  CastState 1 (NO_DEVICES) and ZERO routes after 30 s of active scanning for
  our receiver AND for Google's Default Media Receiver — so it is not our
  receiver's registration. From the Mac, `dns-sd -B _googlecast._tcp` finds ONE
  Cast device on the LAN: "Fireplace Projector" (LPU9DS, 10.0.0.148, video
  capable); the Google TV dongle does not advertise Cast at all (mediashell runs,
  Chromecast built-in presumably off). The Pixel pings the projector in 12 ms,
  yet the system's own Cast provider lists no routes. Blocked on a receiver the
  phone can discover — an owner call (see the loop's report).

- BE. ✅ v1.42.984 The amazon (Fire TV) flavor after the whole dependency pass:
  no Fire TV on the bench, so it ran on the Google TV in place of the google
  build (same debug package; data kept, google build restored after) — Home,
  then Sherlock Jr. muted with the AudioTrack started, no crash. The GMS audit
  on its APK: zero GMS/Firebase classes, and the control finds Cast in the
  google release. Fire OS itself (Decision 115's Fire OS 7 floor) is still
  verified only by the store's device count.

- BF. ✅ v1.42.985 OWNER: "Verify casting works on the android app ... I just
  think you haven't enabled the casting feature inside the video player."
  Right: Cast had never worked on Android, for three stacked reasons, each
  found by a measurement rather than a guess:
  1. Android 17 hands LAN Cast devices to an app only with ACCESS_LOCAL_NETWORK
     (AWCAST: zero routes for our receiver AND the Default Media Receiver;
     granted -> "Basement" and "Fireplace Projector" at once). The google
     manifest declares it and the player asks ONCE on 17+ (system prompt seen).
  2. MediaRouteButton threw on construction — "background can not be
     translucent: #0" — and `runCatching` swallowed it, so the player showed an
     empty slot on EVERY device, every Android version. The app theme now has
     an opaque colorBackground; the button gets an AppCompat wrapper; the
     failure is logged.
  3. Tapping it then crashed: "The activity must be a subclass of
     FragmentActivity". MainActivity is a FragmentActivity (fragment-ktx 1.8.9,
     minSdk 21), and MediaTransferReceiver makes Android 13+ open the SYSTEM
     output switcher, which the code had asked for all along.
  Seen: output switcher lists Basement + Fireplace Projector; Basement's Cast
  shell logged "App running: 58AF34C3 (Archive Watch)", FULL_SCREEN, "Media has
  started", AudioTrack started; the phone's remote session PLAYING at the resume
  point; Stop casting returned the TV to its launcher with no audio.
  OPEN, found on the way: while casting, the phone's volume keys moved the
  PHONE (the Cast volume stayed near max) — our MediaSession still wraps the
  local ExoPlayer rather than the Cast session (media3-cast's CastPlayer is
  already a dependency). Next.

- BG. ✅ v1.42.986 While casting, the phone's volume keys now move the TV:
  MainActivity routes VOLUME_UP/DOWN to the Cast session while one is
  connected (our Media3 session wraps the local player, so the keys had moved
  the phone). First attempt stepped from session.volume, which reads back the
  old value until the receiver confirms — 22 presses all set 0.83; it now steps
  from the last value asked for, within a 1.5 s burst. Seen: 0.78 -> 0.00 in
  22 presses, and the SYSTEM output switcher's Basement slider at zero, muted.
  On a Google TV the Cast volume IS the set's volume: the TV was left muted at
  0 and had to be restored with its own volume key to 22 (shell volume
  commands are refused there; read back after every restore).
  Also: the Kotlin warnings had been hidden by `-q` all session. 55 found;
  37 fixed (OkHttp 5's non-null ResponseBody, Kotlin 2.4's sharper null
  checks, Object() locks, Media3's deprecated SpeedChangeEffect -> one
  EditedMediaItem.setSpeed that re-times audio and video together). The 18
  left are security-crypto's deprecated EncryptedSharedPreferences — next,
  as its own migration (it holds the Twitch token and OpenSubtitles login).
  Owner saw PiP and a full-screen player at once: two INSTALLS (my release
  build in PiP, the debug build full screen) — test residue, closed; a single
  copy cannot do both.

- BH. ✅ v1.42.988 Warnings: 0 across both flavors AND the test sources
  (measured without -q, --rerun-tasks). The last 18 were security-crypto's
  deprecation: EncryptedSharedPreferences is replaced by SecretStore — an
  AES-256-GCM key held in the Android Keystore (API 23+, no fallback needed at
  the floor), 12-byte IV + ciphertext per value in plain app-private prefs,
  Google's own guidance. Old files migrate once and are deleted
  (LegacyEncryptedPrefs, the only code left on the deprecated API). Proved with
  DEBUG doors on BOTH devices' Keystores: a token planted in the OLD format
  (`aw_secret_plant`) came back through the real StudioTokenStore
  (`aw_secret_check`): access and refresh intact, old file gone, no plaintext
  on disk, clear -> null. (The TV's first run was killed before onCreate by an
  8 s wait — harness, not product.)
  Cast in the RELEASE (R8) build: verified — "load issued … at 731381ms", the
  TV's cast_shell "Media has started". The earlier release "failure" was my
  harness: the first Continue tile had changed, so no player was open to hand
  off. Load now logs issued / failed / skipped instead of failing silently.

- BI. ✅ v1.42.989 Clip Studio speed after the Media3 change (BG): a 15.0 s
  selection at 2x exports 7.50 s video / 7.51 s audio (48 fps from 24, no
  frames dropped) — measured with ffprobe on the Pixel's file. The Clips list
  then said "15.0 s" for it: the saved row kept the SELECTION length. It saves
  what the clip runs. My first edit landed on the export spec instead (a text
  match on the first `durationSeconds = clipDuration`) and halved the export to
  3.75 s — caught because the file was measured, not the label; fixed and
  re-measured (7.50 s file, 7.5 row). Test clips removed through the app's own
  Delete: 0 rows, 0 files.

- BJ. ✅ v1.42.990 Accessibility, measured from the device's own tree
  (uiautomator; a clickable node with no text or description anywhere inside
  it is silent to TalkBack): 9 phone surfaces checked. Home, Detail, Surprise,
  Collections, Browse, Search, Library: 0. Settings: 10 — each Switch sat apart
  from its text ("Switch, off"); the phone row is now one `toggleable`
  (Role.Switch) named by its title, and tapping the TEXT now flips it too
  (seen: true -> false -> true); the TV row merges its semantics the same way
  (6 switch rows, 0 unlabeled). Channels: 27 — the narrow guide blocks that
  lost their text in the sliver fix (AE) had nothing to speak; they now say
  "title, time". Both screens re-measured at 0.

- BK. ✅ v1.42.991 Accessibility on the Google TV, 10 surfaces. The phone
  check counted CLICKABLE nodes; TV controls are FOCUSABLE, so the first TV pass
  read 0 everywhere and proved nothing — recounted on focusable nodes. Real:
  the Home hero, a 1600x680 stop with no name (its title is drawn beside it);
  it now says the film ("The Farmer's Wife"). The two other hits are offscreen
  slivers at the capture edge (a Surprise tile, a Browse chip), labeled below
  the fold. All other TV surfaces 0.

## Queue

1. ✅ J — phone launch doors: one shared `Nav.collectStartDoors()` in both roots (v1.42.933); the Pixel opened Library, the TV Search
2. Walk every surface on both devices; the glass decides C, E and the hero
3. ✅ Kotlin warnings: 8 distinct (16 across both flavors) -> 0, both compile tasks re-run (v1.42.932)
4. D, E, G, A, B; then H and I with each change; F is its own project
