# iPad design loop (2026-09-28)

Owner, starting the loop: *"The last apple-based platform that needs a full
audit and design polish is the iPad. Please proceed with all updates that are
necessary for full functionality/parity with the other apple platforms and a
native-first iPad-centric version that works well for that platform."*
Test device: the owner's iPad Pro 12.9 (5th gen, iPadOS 27), landscape.
Binding rules: `docs/IPAD-DESIGN.md` (extends `docs/iOS-DESIGN.md`).

## First sweep (Home, Browse, Channels, Search, Library, Detail)

Already right and not to be "fixed": the sidebar shell, the width-capped hero,
Browse's 8 poster columns with visible filter chips, Detail's two columns
(art beside identity) with labeled actions and a 700pt synopsis, Library as a
list of places.

## Research (session scratchpad `ipad-research.md`, sources there)

iPadOS 26/27 expect what this build has none of: a **menu bar** (the same
`.commands` the Mac target already has builds it on iPad; WWDC25 208/256),
**windows** (`UIApplicationSupportsMultipleScenes` + `WindowGroup(for:)` +
`openWindow`), **keyboard shortcuts**, **pointer hover**, **drag and drop**
(`Transferable`), and sidebar-only **`TabSection`** children. Each needs a
rule in IPAD-DESIGN.md before it ships (binding-design-doc discipline).

## Done

- v1.42.867: **Channels guide** (iOS, seen on the iPad): a block under 84pt
  draws no title ("Moo / nbird", "Lun / ch…" broke mid-word between 44 and
  84pt) and names itself to a pointer (`.help`); the ruler marks the clock's
  own :00/:30 (it labeled window start + 30 min: "12:31, 1:01") and none in
  the last quarter hour (a "3:0…" was cut at the edge; tvOS given the same
  guard). **Search's** empty state drops its explanation line.

- v1.42.868: **Detail picks two columns by the width it has**, not by size
  class alone (`ViewThatFits`, identity column at least 360pt): regular width
  in Stage Manager or an 11-inch in portrait squeezed Play to ~150-350pt
  (§5.2; code audit). Full-screen landscape still two columns (seen). **The
  synopsis offers More only when four lines hide something** (measured, as on
  tvOS): it offered More on any synopsis over 240 characters, which at the
  iPad's 700pt fits whole — seen: His Girl Friday no More, The Big Parade More.
  iPhone gets the same measured rule.

- v1.42.869: **Series page** Play/Resume/Next + Favorite on iPhone and iPad
  (shared `SeriesUpNext`, the tvOS rule); a series card always opens the series
  page (the Detail destination routes it). Seen: "Play S1, E1" on The Lone Ranger.
- v1.42.870: **Menu bar** (Go, Film, Help in the Mac's words; Settings… ⌘,),
  **film windows** (Open in New Window; a Router per window; the scene key
  `UIApplicationSceneManifest~ipad` in the built plist), **sidebar places**
  (Browse and Library sections, Surprise, Watch Together; customizable),
  **pointer** lift on tiles, **drag and drop** of films onto playlists and
  Favorites (IPAD-DESIGN §8-§12). Fixed on merge: the Go menu gave ⌘1..⌘16 to
  sixteen tabs ("⌘10" traps) — now six named places; Settings left the sidebar
  (loose entries render above sections; ⌘, and Home's gear instead); Home's
  shuffle hidden on iPad; and **the iPhone grew a More tab** (sidebar places
  counted toward its bar despite `.hidden, for: .tabBar`) — places now exist
  only at regular width, and a window narrowed to compact hands a selected
  place to its tab. Seen: iPad sidebar; iPhone 12 bar = Home, Browse, Channels,
  Library + Search. NOT yet seen: the menu bar and new windows (no keyboard
  on the iPad), drag and drop, hover.

- v1.42.871: **Prose shares an edge** (owner: *"Is there a reason why the
  summary/description text ... doesn't take up the same space as every other
  interface element?"*, answered "align to a column"). iPad Detail: the synopsis
  sits in the trailing column under Play (IPAD-DESIGN §3.1a). iPad series page:
  two columns like Detail (backdrop at its own 16:9 instead of a 4.75:1 strip),
  a measured More, episodes ending at the column's edge. tvOS Detail: synopsis,
  tagline and facts exactly as wide as the action row; tvOS series: as wide as
  the hero text, 900-1100 pt (tvOS-DESIGN §3.4c). Seen on the iPad Pro
  (Nosferatu; The Lone Ranger). tvOS NOT yet seen: Fireplace was off and
  Kitchen's 720p capture crops the right edge.

- v1.42.872: **Collections** in columns at regular width (adaptive, 340 pt
  minimum; pointer highlight on each row) instead of one list with its chevrons
  ~1000 pt from their titles; a collection's archive.org description capped at
  the §2.1 measure; the Cartoon Marathon button capped at 480 pt (§2.2). Seen:
  Collections, two columns, on the iPad Pro. NOT changed, with reasons:
  On Now at regular width (the grid's leading edge answers it, as on tvOS);
  ↑/↓ surfing (rule 8.3 gives the player its keys, and without a keyboard on
  the iPad whether AVKit answers ↑/↓ is unmeasured — a guess either way).

- v1.42.873: **Return and Esc** on every iPad sheet (Create Channel, Join a
  Room, Go Live, Clip Studio, Downloads, Cast, Add to Playlist, Settings) — the
  Mac's convention; Add to Playlist's Return stays with its name field.
  **A channel's day** ends at the §2.1 measure (content margins, so the list
  still scrolls full width), and its **time column** no longer broke
  "12:01 PM" in two: it is as wide as the locale's widest time at the current
  text size (it was a fixed 76 pt — iPhone too). Seen on the iPad Pro (Drama
  Theater). Keys not pressed: no keyboard on the iPad.

- v1.42.875: **Library lists at the reading width** — History, Downloads,
  Playlists, Clips and a channel's day share `readableListWidth()` (content
  margins, so scrolling, swipe-to-delete and the background still fill the
  window). Seen: History on the iPad Pro. Owner: no Party Play and no Creation
  Studio on iPad (§13). Keyboard/trackpad: the owner connected the Mac's over
  Universal Control; synthesizing keys from the Mac was refused by the
  session's permission check, so the menu bar, shortcuts, windows and drag are
  still unverified.

- v1.42.876: **Keyboard and pointer, driven and measured on the iPad Pro**
  (owner connected the Mac's keyboard and trackpad; the owner: "The whole point
  is for you to run the whole test"). Synthesizing keys on the Mac was refused
  by the session's permission check, so the input comes from XCUITest inside
  the app instead — `IPadInputUITests`, 5 of 5 on the device:
  ⌘5 opens Search, ⌘1 Home, ⌘, Settings and ⌘. closes it (§8.1); ⌘[ goes
  back (§8.1); More -> Open in New Window opens a second window and ⌘W closes
  it (§9.1); a Home poster dragged onto the sidebar's Favorites lands first in
  Favorites (§12.2) — and is un-favorited again, leaving the library as found;
  a pointer hover runs (the lift is not legible in a still). Found on the way:
  More's spoken name was "More actions" while it reads "More" (Voice Control's
  "tap More" missed it); **cast names were cut to one line** ("John Gil…") —
  a lazy row takes its height from its first member, so it is a plain row now
  (iPhone too). NOT yet seen: the menu bar drawn at the top (XCUITest cannot
  reveal it), and a new window's own close control.

- v1.42.877: **CORRECTION — iPadOS's cancel key is ⌘., not Esc.** v1.42.873
  said every sheet takes "Return and Esc"; measured, Esc never closed Settings
  (three runs), ⌘. did. `.keyboardShortcut(.cancelAction)` is ⌘. on iPadOS;
  an invisible Esc twin was tried and also did not fire under XCUITest, so it
  was removed rather than shipped unproven. Close-only Done buttons (Settings,
  Cast, Downloads, Add to Playlist) now take ⌘. instead of Return — Settings has
  a password field whose Return must stay in the field. The v1.42.876 run's
  single Esc pass was not reproducible and is withdrawn. `IPadInputUITests`
  starts every test from the main window (a film window left open restores in
  front and broke the next test) and passes **10 of 10 across two iterations**.

- v1.42.878: **Handoff** (audit #32): the iPhone/iPad and Mac film pages
  advertise the film (`com.bhwilkoff.archivewatch.viewing`, with its
  archivewatch.org link), and iOS (through the IntentInbox, for a cold start)
  and macOS continue it. Built on both; NOT seen: with the iPhone 12 on a film,
  the Mac's Dock showed no Handoff item at all — not even the browser fallback
  a webpage URL always gets — so Handoff itself is not active between these
  two devices (Apple Account or setting), which says nothing about the code.
  Also: rights-audit run 36467063171 marked **985** claims (CI); tonight's
  publish-db applies the hide.

- v1.42.879: **Search's episode results in columns** at regular width
  (adaptive, 360 pt; titles on two lines; pointer highlight) — asserted by
  `test_15` (two rows share a line) and seen with "lone ranger".
  **A test that had changed the owner's library**: `test_13`'s cleanup found
  the film again by its tile and, when that missed, said nothing — four runs
  left The Big Parade, Brute Force, Reefer Madness and The Tingler in the
  owner's Favorites (seen on the iPad). All four removed and the list checked
  against the 12:58 photograph; the cleanup now relaunches on the film's page
  by id and ASSERTS the heart is empty.
  Handoff: the owner says the iPhone 12 and this Mac are on different Apple
  Accounts on purpose; iPad -> Mac also showed no Dock item, still unseen.

- v1.42.881: **The extra-large widget, seen on the owner's Home Screen**
  (they placed it; photographs cropped to the widget, the rest deleted). First
  sight found three faults, all fixed and seen: a landscape still (His Girl
  Friday, Utopia) made its tile twice as wide — the frame is now 2:3 whatever
  the art; the words were centered on the still's width and cut at the tile's
  edges ("Girl Friday", "in left") — the art is a background now; and the
  widget draws .caption2 so large on iPad that titles cut after one word — a
  fixed small size in the compact tile. Rows take 8 films (Continue Watching
  now writes 8). The large widget (iPhone and iPad) is two rows of three
  instead of six slivers, on the same tile. `test_98` holds the Home Screen so
  a widget can be photographed.

- v1.42.882: **Clip Studio at regular width** (audit #23): a page, not a form
  sheet; the picture (up to 560 pt) and trim lead, the settings are a 380 pt
  column beside them. Seen on the iPad Pro; `test_16` asserts the column.

- v1.42.883: **The menu bar, seen** (owner turned on Windowed Apps; "You
  gain access to the menu by clicking on ArchiveWatch at the top of the
  windowed app"): ArchiveWatch · File · Edit · View · Go · Film · Window ·
  Help, and Go lists every place with its key. `test_17` opens it by clicking
  the app's name (the small element at the top edge — the window carries the
  same label) and asserts Films is in Go. Found: **Search was in Go twice**
  (⌘5 as a place, ⌘F below the divider); it is once now, in its place, with ⌘F
  as on the Mac, and Favorites is ⌘5. Owner answers recorded (IPAD-DESIGN
  §13.2-13.4): no More Like This reason; no Watch Together room from an iPad,
  iPhone or Apple TV Studio. Suite: 9 of 9.

- v1.42.884: owner's two answers. **"Archive Watch"** is the display name on
  iPhone, iPad and Apple TV (the shared Info.plist never set one, so the
  system showed the bundle's "ArchiveWatch"); seen in the iPad's status bar.
  **The Birth of a Nation and Check and Double Check leave every
  recommendation** ("Keep off recommendations") as sourced `add` entries in
  `propaganda.json` — named one by one, not a new rule; they take effect at
  the next publish and stay in Search and Browse.

- v1.42.885: **↑/↓ channel surfing — NOT shipped, and why.** Three routes,
  each measured on the iPad with the strip's own "Previous channel, <name>"
  button as the instrument (a name on screen proves nothing: the guide behind
  the player lists every channel), and none tuned a channel: (1) Go menu
  commands on ↑/↓ published by the surf player; (2) UIKeyCommands with
  priority on an AVPlayerViewController subclass; (3) the same, with the player
  taking first responder on appear. An earlier "pass" was that instrument
  fault and is withdrawn. Unknown still: whether XCUITest's arrow key reaches
  the app at all — the next step is that control (an arrow where the app is
  known to act on it) plus an on-screen DEBUG counter of key commands
  received, before any fourth implementation. Code reverted.
  Also: the menu-bar test follows the new name ("Archive Watch"), and a test
  that opens a full-screen player cleans windows on a plain launch first (the
  cleanup read a player as a film window and pressed ⌘W on it).

- v1.42.886: **A poster has a menu** (audit #5, IPAD-DESIGN §11.2): right-
  click or long press on any poster tile — Home, every grid, More Like This —
  offers Open in New Window (where windows exist), Add to / Remove from
  Favorites and Share…, on iPhone too. Favorite state is read when the menu
  opens, so a grid does not observe every favorite. Seen on the iPad Pro
  (His Girl Friday in Films) and asserted by `test_19`, which chooses nothing.

- v1.42.887: **Clip Studio I and O** (audit #24): the Mac editor's keys on
  Set Start / Set End. `test_20` measures them where they land — at the film's
  first second O turns "Clip 15.0s" into "Clip 0.5s" and I turns it back —
  with nothing played or created. **This also narrows the ↑/↓ question**: a
  plain, modifier-free key from XCUITest DOES reach the app in a sheet, so
  the channel failure is the full-screen player holding the arrows, not the
  instrument. Space (play) not added: it would play the film aloud to test.

- v1.42.888: **Channels guide blocks carry the film's menu** (audit #44):
  the same Open in New Window / Favorites / Share as a poster, since every
  program is a film; seen and asserted (`test_21`). Scene frames get none —
  their tap already plays from that moment (IPAD-DESIGN §11.2).

- (no build) **A film window's close control — not seen, and why.** With
  Windowed Apps on, Open in New Window opens the film FULL SCREEN, where
  iPadOS hides a window's controls; hovering the top-left corner revealed
  none, and a `.defaultSize` on the film WindowGroup did not change how it
  opened (reverted — it proved nothing). The window closes with ⌘W (the
  suite's cleanup depends on it) and from the Window menu. Next step, if the
  owner wants it: what iPadOS 26 uses to open a second window as a floating
  window rather than full screen — research before a fourth attempt.

- v1.42.889: **Open Film** for Siri and Shortcuts on iPhone and iPad (audit
  #33): a Film entity resolved by the catalog's own search (the shared
  ranking), and an App Shortcut — "Open a film in Archive Watch" — that asks
  "Which film?" and opens its page through the IntentInbox (cold-start safe,
  as links are). **Seen working by the owner** (2026-09-28: "The shortcuts
  implementation works. I just tested it"); XCUITest could not open Spotlight
  to drive it, and Siri would speak aloud. Spotlight indexing of the ~27k titles is not done (a larger
  job: CSSearchableIndex from the catalog, kept current per publish).

- v1.42.890: **Your own card** in the iPhone/iPad Studio (Mac §D10): a
  heading and a message in the card's own type, live while it is up, refused
  while empty, kept for the session. The film-stall reason the audit listed
  was already on iOS (StudioPlayerContainer_iOS) — the audit note was stale.
  Built; NOT seen: running the Studio attaches the owner's camera and mic.

- v1.42.892 (owner away: "you can test on any device"): **the custom card,
  seen on the wire** — a bench broadcast from the iPad Pro (mic and film
  muted by the door) recorded the film, then "Intermission in ten / Back at
  nine sharp" in the card's own type at 16 s, then the edited message at
  24 s: edits reach the audience while the card is up. Door:
  `AW_STUDIO_IOS_CARD="Heading|Message@T"`. **Found on the same frames: the
  iPhone/iPad on-air rights line still said "PUBLISHED 1928, BEFORE 1930"** —
  Decision 137 fixed the Mac's StudioSession and never reached
  StudioPlayerContainer_iOS, which builds its own overlay (Decision 133's
  shared-type-is-not-shared-path, again). Fixed and re-recorded: "PUBLIC
  DOMAIN — PUBLISHED 1928".

- (no build) **Picture-in-picture restore — still not driven.** Three
  XCUITest routes on the iPad: the Home press (it does not background the app
  under Windowed Apps — seen twice today), then tapping the video to reveal
  AVKit's controls — the accessibility tree listed the film's page and no
  player controls at all, so there was no Picture-in-Picture button to press.
  SCRATCHPAD already names this as the one path not automatable; it stays a
  one-tap check for the owner. Nothing shipped; the test is removed.

- v1.42.893: **Clips rows are buttons** (audit #16): the row was a tap
  gesture, so it answered neither the pointer nor the keyboard; now a button
  with a highlight, captions on two lines, and a menu (Open Film, Share…,
  Delete Clip) beside the existing swipe-to-delete. Seen on the iPad Pro;
  `test_24` looks at the menu and chooses nothing (it holds Delete).

- (research, no build) **Why a film window opened full screen**: iPadOS 26
  opens `openWindow` on top of the current window, full screen when that one
  is, and ignores `defaultSize` then (Apple Developer Forums 792596) — the
  platform's rule; recorded as IPAD-DESIGN §9.4. The test launched the app
  full screen, so its film window was too. **↑/↓ on the player**: no source
  says which keys AVPlayerViewController claims on iPad; the next step is
  still a DEBUG on-screen counter of key commands received, not a guess.

- v1.42.894: **Touch is how channels change** (owner: "Most iPad users do
  not use a keyboard at all ... Can we make sure that there are actual touch
  controls"). The capsule's ▲/▼ were already there; a tap on ▼ is now
  asserted on the iPad Pro (`test_25`, the capsule's own button as the
  instrument), and at regular width the capsule is finger-sized: 60 pt
  chevrons (44 on the phone), headline text. The picture behind it plays (a
  30 s capture); earlier black frames were only the seconds before it began.

**Remaining (2026-09-28 13:47, updated 17:40):** code — Clip Studio Space (I/O done),
channel-surf ↑/↓ (three routes failed; control first),  Spotlight indexing (Open Film for Siri is built), the Studio's Record (the custom card is built; film-stall reason was already there); verify — picture-in-picture restore;  owner — none.

## Found, data (for the copyright/scrub work, not the iPad)

- `SelfCons1951` "Self-Conscious Guy" (Coronet, 10 min) leads Home's hero with
  a TMDb backdrop (tmdb 444546) that looks like a modern color film still.
  **Checked 2026-09-28 (v1.42.920)**: the match is right (the TMDb poster is
  the film's own Coronet title card) and the BACKDROP is wrong — a modern
  photo of a couple passing an "ADULTS ONLY" sign. New
  shared/editorial/image_rejects.json names that one image; remediate clears
  it every build (tested with a control carrying another backdrop, kept).
- **Checked 2026-09-28 (v1.42.921)**: Yojimbo left with Decision 151; The
  Pink Panther (1963) and Gentlemen Prefer Blondes (1953) have renewals the
  check MISSED — the Office's "; motion picture photoplay" title tail, and a
  25-record page (Pink Panther's renewal is record 54 of 5,525). Match rule 2
  fixes both and re-checks every title under it; 3/3 known renewals match,
  0/17 public-domain controls do.
  **Measured** (rights-audit run 36510976309, 2026-09-28 20:53 MT): 15,391
  kept titles rechecked, **258 more renewals**, copyright_claim_evidence
  985 -> 1,243 (hidden at the next publish). A 25-title sample and a scan
  against ~45 public-domain classics found no wrong catch. Owner question
  raised: Sita Sings the Blues (Nina Paley's own CC BY-SA/CC0 release) is
  hidden by the commercial-votes gate, which runs before licence evidence.
- Browse shows Yojimbo (1961), The Pink Panther, Gentlemen Prefer Blondes; the
  Classic TV channel carries Monty Python's Flying Circus and Rumpole of the
  Bailey (1978-); the Documentary channel carries Triumph des Willens (the
  Decision 149 flag removes it from channels at the next publish).
  **Checked 2026-09-28 (v1.42.919)**: Monty Python (1969-74) stays by the
  1964-77 keep band. Rumpole was never television to the TV audit: one catalog
  item (tv-special) holding all 43 Thames episodes, 1978-1992, dated 1975 by
  its uploader (the earlier BBC play's year), so it sat in the keep band.
  year_corrections.json now says 1978 (S01E01 aired 3 April 1978); the audit
  then reads modern_copyright_unconfirmed -> confirm, and the nightly confirm
  hides it (no licenseurl).

## Queue

1. Menu bar + keyboard shortcuts (shared with the Mac's MenuCommands where possible)
2. Multiple windows: "Open in New Window" for a film
3. Sidebar `TabSection`s: Library places and Browse scopes in the sidebar
4. Pointer hover on cards; drag and drop of films into playlists
5. Parity table from the code audit (pending)

## Cross-platform queue (2026-09-28 17:45, from a code-verified review of all four loops)

Owner: *"go through all of the audits that we have done for Apple TV iPad and
iPhone to make sure that everything that we have learned across each of those
platforms is informing the other platforms."* Each line cites code, not docs.

1. ✅ v1.42.895 Captions never clamped — iOS PlayerView_iOS.swift:871/926 (numberOfLines 4), Mac PlayerWindow_macOS.swift:334 (lineLimit 4)
2. ✅ v1.42.899 (seen: Nosferatu's first review, whole at four lines, no longer offers "Show more") Measured More — reviews on iOS use a 260-character guess (CommunityDetailSection.swift:73)
3. ✅ v1.42.895 (seen: iPad and Mac Home, 7-film hero) Hero chosen in SQL — iOS HomeView_iOS.swift:250, Mac HomeView_macOS.swift:64 still decode dbBrowse(limit: 3000)
4. ✅ v1.42.897 (seen on the Mac: Play S1, E1 · Favorite · More) Series page Play/Resume + Favorite — Mac SeriesDetail_macOS.swift:66-76
5. ✅ v1.42.898 (seen on the iPad: bars + "1h 32m left"; Mac built, the row below its window's fold) Continue Watching time-left/progress — iOS HomeView_iOS.swift:51, Mac HomeView_macOS.swift:34
6. ✅ v1.42.901 built (NOT seen: the iPad asked for its passcode to re-enable UI Automation, the owner's to enter) Version menu checks the playing copy; one name ("Choose Version") — iOS DetailView_iOS.swift:153/163, Mac DetailView_macOS.swift:527
7. ✅ v1.42.896 (measured: hung >20 s on a 3 s timeout; now 3.2 s) RTMPPublisher task-group timeout waits on cancellation-blind children (Studio/RTMPPublisher.swift:931) — test with a server that never answers
8. ✅ v1.42.905 VoiceOver headings on iOS section titles (HomeView_iOS:361, DetailView_iOS:621/658/729, SearchView_iOS:120/133)
9. ✅ v1.42.903 built (right-click not driven: no synthesized input on the owner's Mac) Mac poster/guide menus lack Favorites/Share (Cards_macOS.swift:54, ChannelsView_macOS.swift:243)
10. ➖ no change — seen on the Mac guide: titles wrap at words ("Black / Oxen"), narrow blocks draw none; 48 pt suits the Mac's smaller caption. Mac guide titles from 48 pt (ChannelsView_macOS.swift:248)
11. ✅ v1.42.902 Mac cast row is a LazyHStack (DetailView_macOS.swift:632)
12. ✅ v1.42.902 (seen: The Big Parade — six lines under Play, More, cast on the first screen) Mac synopsis has no width cap (DetailView_macOS.swift:68)
13. ✅ v1.42.904 Explanatory copy / disabled-without-reason — SurpriseView_iOS:42, ChannelsView_iOS:852/876, tvOS ChannelsView:523/544/560, SearchView_macOS:45, LibraryView_iOS:422 ("Create button")
14. ✅ v1.42.906 (seen: a highlighted toggle button in the Channels toolbar) iOS commercial breaks is an icon swap, not a Toggle (ChannelsView_iOS:79)
15. ✅ v1.42.904 Title Case / one wording — DetailView_iOS:197/160, LibraryView_iOS:393
16. ✅ v1.42.905 (now "Play a Surprise Film", which plays, via Router.autoplayItemID) iPad Go menu: "Surprise" and "Surprise Me" open the same page (MenuCommands_iOS:52/80)
17. ✅ v1.42.906 built iPad Film menu lacks Subtitles… and Watch Together (MenuCommands_iOS:113)
18. ✅ v1.42.908 (seen on Kitchen: Film Noir leads with archive.org's description) tvOS collection page lacks its description; card title 1 line (BrowseView.swift:163, CollectionsView.swift:98)
19. ✅ v1.42.909 (in both apps' App Intents metadata; not yet run by voice) Open Film intent on tvOS and macOS (none on Mac at all)
20. ✅ v1.42.917 Mac drag of films onto playlists/Favorites — macOS-DESIGN §B15 written first; FilmTransfer shared; built on all three, not yet dragged (no pointer automation on the owner's Mac); ✅ v1.42.918 an empty Mac playlist shelf keeps its title and says "Empty playlist" (it had vanished, so a playlist whose films all left the catalog could not be seen, dropped on or deleted)
21. ▲/▼ surfing on tvOS/Mac players — OWNER CALL (Siri Remote conflicts)
22. ✅ v1.42.907 (seen on Kitchen: the Movies row's posters share a top edge) tvOS poster caption reserves no lines (PosterTile.swift:43)

Found on the way (v1.42.900): **214 archive.org reviews are stored garbled**
(mojibake — "doesnÃÂt"; one French review almost entirely "ÃÂÃÂ"),
checked at the source: archive.org's own metadata carries the damage, and the
bytes that would reverse it are gone. The build now removes the garbage runs
(comment_fit.clean_text) — nothing added to the reviewer's words — and drops a
review only when too little is left to read (the floor every review shares;
the full keep_review was measured to drop 24 genuine reviews and rejected).
All 214 are cleaned and kept; a second pass changes nothing.

Shared-function candidates: ✅ v1.42.910 the rights/lower-third line (5 copies → StudioRights.provenanceLine / lowerThirdSubtitle, pinned in test_studio_rights), ✅ v1.42.912 measured
More (4 → TruncationReader / readsTruncation; seen on the Mac synopsis and iPad reviews), the hero pool (3), ✅ v1.42.915 the caption overlay (3: the drawing stays per framework; the Mac now takes the viewer's system caption style like iPhone, iPad and Apple TV — SystemCaptionStyle.resolved), ✅ v1.42.913 the version menu (2 → VersionMenuContents; built, not yet opened on glass),
✅ v1.42.916 IntentInbox + intents (2: the files stay per platform; the lessons crossed — widget play links now route on iPhone, iPad and Mac, and a bare item/ link no longer parses as a film named "/"), ✅ v1.42.911 the Handoff type literal (4 → ArchiveHandoff.viewing), ✅ v1.42.911 Create Channel
canSave (3 → UserChannel.canCreate), guide-block thresholds (3), review cards (2). Also: ✅ v1.42.914 the Mac
poster card is a Button (was onTapGesture; looks unchanged on Home, Tab reach not yet seen).
