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

**Remaining (2026-09-28 13:47, updated 16:28):** code — Clip Studio keys (I/O, Space),
channel-surf ↑/↓ (now testable with XCUITest), context menus on Scenes /
More Like This / guide blocks, an App Intents film entity (Siri + Spotlight,
all Apple), the Studio's Mac-only features that port to iPad (film-stall
reason, custom card, Record); verify — a film window's close control, picture-in-picture restore; owner — none.

## Found, data (for the copyright/scrub work, not the iPad)

- `SelfCons1951` "Self-Conscious Guy" (Coronet, 10 min) leads Home's hero with
  a TMDb backdrop (tmdb 444546) that looks like a modern color film still.
- Browse shows Yojimbo (1961), The Pink Panther, Gentlemen Prefer Blondes; the
  Classic TV channel carries Monty Python's Flying Circus and Rumpole of the
  Bailey (1978-); the Documentary channel carries Triumph des Willens (the
  Decision 149 flag removes it from channels at the next publish).

## Queue

1. Menu bar + keyboard shortcuts (shared with the Mac's MenuCommands where possible)
2. Multiple windows: "Open in New Window" for a film
3. Sidebar `TabSection`s: Library places and Browse scopes in the sidebar
4. Pointer hover on cards; drag and drop of films into playlists
5. Parity table from the code audit (pending)
