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
