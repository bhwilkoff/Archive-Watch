# Top Shelf + Widgets — research & plan (Archive Watch)

Research-first brief for making Top Shelf (Apple TV) and Widgets (iOS / iPadOS /
macOS) **best-in-class**. Two web-research passes (cited below) + a code audit of
the existing, inert-ish extensions. Build plan at the end; nothing here is built
yet.

---

## 0. Current-state audit (what's actually in the package)

Both extension targets exist and are partially wired — they are **v0 stubs**, not
dead, but they are far from best-in-class.

**Top Shelf (`ArchiveWatchTopShelf`, tvOS):**
- `TopShelfSnapshot` (app target) writes Continue Watching / Editor's Picks /
  Popular Now into the App Group; `TopShelfUpdater()` is embedded in
  `RootView.swift:51`, so the snapshot IS written + refreshed on progress/catalog
  changes.
- `ContentProvider.swift` reads it and returns a **`TVTopShelfCarouselContent(.details)`** hero.
- Problems: (1) the carousel is **16:9** but the catalog's designed art is mostly
  **2:3 posters** — the provider requires `backdropURL` and falls back to a poor/empty
  hero when wide art is missing; (2) it **never calls
  `TVTopShelfContentProvider.topShelfContentDidChange()`**, so a fresh snapshot
  isn't picked up promptly; (3) no `playbackProgress` resume bar; (4) no light/dark
  `ImageTraits`; (5) none of the distinctive rows.

**Widgets (`ArchiveWatchWidgets`, iOS only):**
- One `StaticConfiguration` widget ("Continue Watching" / Editor's Picks),
  `.systemSmall` + `.systemMedium`. `WidgetSnapshotWriter.write` IS called from
  `HomeView_iOS.swift:142` and reloads timelines.
- Problems: (1) **text-only, zero poster art** — the #1 filler tell; the snapshot
  carries only id/title/year, no art; (2) only 2 families; (3) **no Lock Screen
  accessory widgets, no Large, no Control widget, no StandBy**; (4) **no macOS
  widget target at all** (the appex is `platformFilter = ios`).

**Plumbing (good):** App Group `group.app.archivewatch.tvos` is on every relevant
target (main tvOS/iOS/macOS + both extensions). Extension bundle ids are
`app.archivewatch.tvos.topshelf` / `app.archivewatch.tvos.widgets`.

**Net:** to reach "best-in-class" we (a) redesign Top Shelf around **poster
sections with resume**, fix refresh + art; (b) rebuild widgets around **pre-cached
poster art**, add families + Lock Screen + a Control widget, and (c) **add a macOS
widget target**.

---

## 1. Top Shelf — API facts & best-in-class (tvOS 26)

`TVTopShelfContentProvider.loadTopShelfContent` returns ONE of three content
objects; returning the wrong shape or `nil` = the system falls back to the static
asset-catalog image (looks broken).

| Style | Class | Treatment | Best for |
|---|---|---|---|
| **Sectioned** | `TVTopShelfSectionedContent` → `[TVTopShelfItemCollection]` → `[TVTopShelfSectionedItem]` | Titled rows of poster/square/16:9 tiles; supports a **resume bar** via `playbackProgress` | Resume-first media libraries (Plex/Infuse/Jellyfin) |
| **Carousel** | `TVTopShelfCarouselContent(style: .details/.actions)` → `[TVTopShelfCarouselItem]` | Full-screen rotating hero, optional cinemagraph + preview video | One editorial hero (Apple TV+, Disney+) |
| **Inset** | `TVTopShelfInsetContent` → `[TVTopShelfItem]` | Row of large near-full-width images | Overarching theme art / games |

**Image specs:** sectioned **poster 2:3 = 404×608 px** (safe 380×570), square 1:1 =
608×608; inset = 1940×692 (safe 1740×620); carousel = 1920×1080 @1x and @2x.
`setImageURL(_:for:)` takes light/dark `ImageTraits` (supply both for tvOS 26
Liquid Glass legibility).

**Actions:** each item has `displayAction` (select → route to **detail**) and
`playAction` (Play button → route **straight to playback**). `playbackProgress`
(0–1) draws the resume bar. WWDC guidance: **5–10 items** per surface.

**Lifecycle / why it can show nothing:** the provider is queried by the system
(notably when the icon is in the Home top row) — you can only invalidate via
`topShelfContentDidChange()`. The extension is a separate process: the **app writes
a small App-Group snapshot** (ids, titles, image URLs, progress, action URLs) then
calls `topShelfContentDidChange()`; the extension reads it. **Memory budget is
tight (~16 MB, tightened post-13.4)** — downsize art, `autoreleasepool`, never block
on network for first paint, or you get an OOM/blank. Swift 6 gotcha: the `async`
overload trips a non-`Sendable` `TVTopShelfContent` error — **use the
completion-handler overload** (we already do).

**What the best apps surface:** Plex/Infuse/Jellyfin lead with **Continue Watching
posters + resume**; Apple TV+/Disney+/Max use an **editorial carousel** for "what's
new." Netflix notably *doesn't* integrate the system surface (cautionary). The two
idioms: resume-first sectioned posters, and a single editorial hero.

**Recommendation:** default to **`TVTopShelfSectionedContent`** with **poster
tiles** — it fits our art, gives a resume bar, and is more "doorways than funnel"
(the wander-the-repertory ethos). Rows, ≤6, ≤8 tiles each, Continue Watching first:

1. **Continue Watching** (posters + `playbackProgress`; `playAction`=resume)
2. **On Now (Channels)** — current program per lane via `ChannelScheduler` (distinctive)
3. **Editor's Picks** (`displayAction`=detail — invite a look, not autoplay)
4. **What's New**
5. **Public Domain Day** (catalog-native curiosity hook)
6. **Surprise Me** (single tile; `playAction`=`archivewatch://random`)

Reserve a `TVTopShelfCarouselContent` hero for special moments (PD Day, a
retrospective) — not as the permanent default (most passive choice).

*Sources:* [TVTopShelfContentProvider](https://developer.apple.com/documentation/tvservices/tvtopshelfcontentprovider) ·
[SectionedItem](https://developer.apple.com/documentation/tvservices/tvtopshelfsectioneditem) ·
[CarouselItem](https://developer.apple.com/documentation/tvservices/tvtopshelfcarouselitem) ·
[InsetContent](https://developer.apple.com/documentation/tvservices/tvtopshelfinsetcontent) ·
[TVTopShelfAction](https://developer.apple.com/documentation/tvservices/tvtopshelfaction) ·
[tvOS 26 release notes](https://developer.apple.com/documentation/tvos-release-notes/tvos-26-release-notes) ·
[WWDC19 S211](https://asciiwwdc.com/2019/sessions/211) ·
[Brightec: Top Shelf](https://www.brightec.co.uk/blog/creating-top-shelf-content-your-tvos-app) ·
[Mohit Bhalla: Top Shelf integration](https://mohit-bhalla.medium.com/enhancing-your-tvos-app-with-top-shelf-integration-98e40d2cc01e) ·
[Infuse Top Shelf](https://community.firecore.com/t/top-shelf-issues/50281) ·
[ext memory limits](https://developer.apple.com/forums/thread/20997)

---

## 2. Widgets — API surface & best-in-class (iOS/iPadOS/macOS 18–26)

**Families:** `.systemSmall/Medium/Large` (iOS+iPadOS+macOS), `.systemExtraLarge`
(iPadOS only). **Lock Screen:** `.accessoryCircular/Rectangular/Inline` (render
`.vibrant`/accented — shape+contrast, not color). **StandBy** (iOS 17+): small
widgets appear automatically; branch on `@Environment(\.widgetLocation)`.
**macOS** widgets are interactive on the desktop and auto-tint to the wallpaper.
**watchOS complications need a watch app** → out of scope (no watch target).

**Control widgets (iOS 18):** one `ControlWidget` surfaces in **Control Center,
Lock Screen, AND the Action button** — `ControlWidgetButton(action: AppIntent())`
is ideal for **"Surprise Me."**

**Interactive widgets:** only `Button(intent:)` / `Toggle(intent:)` backed by a
fast `AppIntent` run in-widget (toggle a favorite, shuffle); richer navigation must
`widgetURL`-deep-link.

**Live Activities (ActivityKit):** **don't fit AVPlayer playback** (Apple routes
that to Now Playing / MediaPlayer; HIG forbids marketing use). The *legitimate* fit
is a **time-bound "On Now / Up Next" Channels program** with a known end time
(`Text(timerInterval:)`). Constraints: ≤4 KB payload, no video, budgeted updates,
~8 h cap.

**Refresh:** `AppIntentTimelineProvider` (configurable) or `TimelineProvider`;
`placeholder` must be synchronous; `TimelineReloadPolicy` = `.atEnd/.after(date)/.never`;
app pushes refresh via `WidgetCenter.reloadTimelines(ofKind:)`. **Budget ≈ 40–70
reloads/day** — match cadence to real data change (daily Pick of the Day,
schedule-aligned Channels, on-write Continue Watching).

**Survey of real streaming widgets:** Disney+ ships **"Keep Watching"** (progress)
+ **"Discover"** (fresh recs); Apple TV "Up Next"; Hulu continue/recs; Plex "On
Deck"; Spotify recently-played (lock-screen redesign lost cover art → backlash).
**Most big streamers under-invest in widgets** — an opportunity to stand out. The
praised ones = **Continue Watching with real progress + poster art** and **fresh,
tappable recommendations.** Filler = static brand tiles / artless lists.

**What separates best-in-class from filler:** glanceable (one idea), fresh (current
state), **specific tap target** (per-element `Link` in medium/large), respects the
budget, and **beautiful pre-rendered art**.

**Recommended widget set for Archive Watch** (learning lens: lead with *discovery*,
not a consumption loop):

| Widget | Families | Shows | Refresh | Deep link | Interactive |
|---|---|---|---|---|---|
| **Continue Watching** | S/M/L, accessoryRectangular | recent in-progress + poster + *time remaining* | on-write + daily floor | `://item/{id}` (resume) | opt. dismiss-finished `Button(intent:)` |
| **Pick of the Day** ⭐ | S/M (+StandBy) | one curated/PD gem, backdrop + one-line why | `.after(midnight)` | `://item/{id}` | no |
| **Surprise Me** ⭐ | S widget **+ Control widget** | dice/reel glyph; tile previews a random poster | low | `://surprise` | **yes** (Control/Action button) |
| **On This Day / PD Day** ⭐ | M/L | films entering PD / today's anniversary | `.after(midnight)` | PD Day route | no |
| **On Now (Channels)** | M/L | current+next program per chosen channel | `.after(program end)` | `://channels` | per-program `Link` |
| **Favorites** | S/M, accessoryCircular | favorite posters / count | on favorites change | `://item/{id}` | opt. |
| **Channels Live Activity** (optional) | Lock Screen + Dynamic Island | on-now title + countdown to program end | program boundaries | `://channels` | transport-free |

Make Pick of the Day / On Now / Favorites **configurable** via
`AppIntentConfiguration` (choose category/channel/playlist).

**Gotchas:** widgets **can't reliably async-load remote art** (~30 MB, no
AsyncImage cache) → **pre-cache poster/backdrop into the App Group from the main
app**; **CloudKit must be read from a main-app-projected snapshot**, never in the
timeline provider; accessory widgets are vibrant/accented; macOS auto-tints (test
light+dark desktops); `placeholder` synchronous.

*Sources:* [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) ·
[Creating controls (iOS 18)](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system) ·
[Accessory widgets & complications](https://developer.apple.com/documentation/widgetkit/creating-accessory-widgets-and-watch-complications) ·
[ActivityKit / Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities) ·
[HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities/) ·
[WidgetKit push (iOS 18)](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications) ·
[macOS Sonoma widgets](https://www.macrumors.com/guide/how-widgets-work-macos-sonoma/) ·
[Disney+ widgets](https://www.disneyplus.com/explore/articles/disney-plus-ios-widgets) ·
[Plex On Deck](https://forums.plex.tv/t/on-deck-continue-watching-recently-added/666191) ·
[SwiftSenpai: refresh budget](https://swiftsenpai.com/development/refreshing-widget/) ·
[SwiftSenpai: remote data in a widget](https://swiftsenpai.com/development/widget-load-remote-data/)

---

## 3. Shared foundation work (both surfaces depend on it)

1. **Art pre-cache in the App Group.** A shared `WidgetArtCache` the main app fills:
   download each surfaced item's poster (and a backdrop for Top Shelf/On Now) once,
   write a downsized JPEG into the group container keyed by archiveID; the widget /
   Top Shelf read the local file (never the network). Evict by LRU/age.
2. **Richer snapshots.** Extend both snapshots to carry the cached art filename +
   `playbackProgress` + per-surface action URLs. Keep them slim.
3. **`topShelfContentDidChange()`** after every Top Shelf snapshot write.
4. **Snapshot writers on every platform.** Today only iOS writes the widget
   snapshot (from `HomeView_iOS`) and only tvOS writes Top Shelf. Add a macOS
   widget snapshot writer + a shared projection so Continue Watching / Pick of the
   Day / Favorites are populated on iOS, iPadOS, and macOS from the shared store.
5. **Deep-link routes:** confirm `://item`, `://play`, `://surprise`, `://channels`,
   PD-Day all resolve via the existing `IntentInbox`/`onOpenURL` on each platform.

---

## 4. Proposed phasing

- **Phase 1 — Foundation + the two highest-value surfaces.** Art cache + richer
  snapshots + `topShelfContentDidChange()`. Top Shelf → **sectioned posters with
  Continue Watching + resume + Editor's Picks + What's New**. iOS/iPadOS widget →
  **Continue Watching with real poster art** (S/M/L) + Lock Screen accessory.
- **Phase 2 — Discovery + Mac + Control.** Pick of the Day, Surprise Me widget +
  **Control widget / Action button**, Favorites; **add the macOS widget target**
  (same code, native Mac). Top Shelf adds **On Now (Channels)** + **PD Day** + a
  **Surprise tile**.
- **Phase 3 — Configurable + Live Activity (optional).** App-Intent-configurable
  widgets (pick category/channel); **Channels "On Now" Live Activity** + Dynamic
  Island; StandBy-tuned Pick of the Day.

**Learning-orientation note:** Continue Watching supports *agency*; the discovery
widgets (Pick of the Day, Surprise Me, On This Day, On Now) are where the
repertory-wander ethos lives — favor them over a pure consumption loop. The
Surprise Me Control / Action button is the single most on-ethos build: a hardware
button that "sends you somewhere you wouldn't have chosen."
