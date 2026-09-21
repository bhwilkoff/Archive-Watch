# Archive Watch — Cross-Platform Feature Parity

> **Single source of truth** for what ships where. Updated in the SAME change set
> as any user-facing feature. Companion to `CLAUDE.md`, `SCRATCHPAD.md`,
> `DECISIONS.md`, and the full strategy in `docs/MULTIPLATFORM-PLAN.md`.
>
> Per-platform binding design docs (create when each platform's UI complexity
> warrants): `docs/tvOS-DESIGN.md` (exists), `docs/iOS-DESIGN.md`,
> `docs/macOS-DESIGN.md` (exists), `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md`.

## Legend
- ✅ **Shipped** · 🚧 **In progress** · ⏳ **Planned (committed)** · 🔮 **Future (agreed, no date)** · 🚫 **Out of scope (with reason)** · n/a **platform-inapplicable**

> **macOS (Decision 042): parity face SHIPPED + Mac-EXCLUSIVE Creation Studio.**
> Native AppKit/SwiftUI app (`ArchiveWatch/ArchiveWatch/macOS/`, shares the
> `app.archivewatch.tvos` App Store record — Decision 042/owner 2026-06-24).
> `NavigationSplitView` shell over the SHARED Swift Core (`CatalogDB`,
> `ResilientStreamLoader` w/ node failover, models, `CloudKitSyncService` — same
> container as tvOS/iOS): Home (hero + shelves), Movies/TV/Collections/Search,
> Detail (More Like This, cast→person, Share, Callsheet, reviews), AVPlayerView
> playback (resilient MP4 + HLS captions + speed + resume), Channels, Surprise,
> Cartoon mode, Library (favorites/playlists/watched), Settings (Sign in with
> Apple → CloudKit, mature filter, attribution, donate). **Creation Studio** is the
> Mac-only multi-clip editor (§4c). **Widgets** ship on macOS (§8). All four
> targets build green vs the 26 SDKs; on-device spot-checks owner-pending.
>
> **Android Phase P4 v1 spine (2026-06-09): SHIPPED** — native Kotlin + Compose M3
> (`android/`, applicationId `com.archivewatch.app`): contract-compliant data
> layer (seed → .zz download/inflate/swap via BundledSQLiteDriver FTS5), Home /
> Browse / Search / Detail / SeriesDetail / Media3 player (resilient
> LoadErrorHandlingPolicy) / Library / Settings, deep links. assembleDebug green +
> emulator-verified (full 27k catalog on-device). Next wave: Channels, modes,
> widgets, Drive App Data sync — see docs/ANDROID-DESIGN.md §7.
>
> **Web P3 (2026-06-09): SHIPPED + LIVE** at archivewatch.org/
> — Decision 029 data plane, installable PWA, /item share-URL forwarder.
>
> **iOS Phase 1+2 (2026-06-09): COMPLETE.** Home discovery, Surprise grid + PD Day
> explorer, Channels touch guide, Cartoon Mode, playlists, manual prev/next
> episode, hide-watched + per-category Settings toggles. iOS + tvOS build green;
> on-device spot-checks owner-pending. (iOS is a universal target with tvOS via
> `#if os` guards; a WidgetKit extension + Sign in with Apple → CloudKit share the
> Apple TV's private DB.)

## Parity rule
**Same verb, native idiom.** The feature (the verb) is identical across platforms;
the *idiom* is whatever is native — `.searchable` on iOS, `NavigationSplitView` +
AppKit on macOS, `SearchBar` on Android, `<input type=search>`+URL on web, the
focus-driven `.searchable` on tvOS. Update this table in the same change set;
cross-link the platform design doc. Apple platforms are grouped (tvOS · iOS ·
macOS) since they share the Swift Core.

---

## 1. Navigation shell

| Verb | tvOS | iOS | macOS | Web | Android | Notes (native idiom) |
|---|---|---|---|---|---|---|
| Top-level nav | ✅ `TabView(.sidebarAdaptable)` | ✅ `TabView(.sidebarAdaptable)` (bottom bar iPhone → sidebar iPad) | ✅ `NavigationSplitView` sidebar (Home/Movies/TV/Channels/Collections/Surprise/Search/Library + **Create**) | ✅ top nav + hash routes (`/watch/`) | ✅ `NavigationSuiteScaffold` + sealed routes | Settings = a Mac Settings scene / a Home cog elsewhere |
| Per-tab back stack | ✅ `NavigationStack` ×tab | ✅ `NavigationStack` ×tab + swipe-back | ✅ `NavigationStack` detail column (`AppRouter`) | ✅ hash history (browser back) | ✅ `BackHandler` route stack | |
| Deep-linkable surfaces | ✅ `archivewatch://` | ✅ scheme; Universal Links UNBLOCKED — AASA live at archivewatch.org/.well-known (owner: add Associated Domains capability, Decision 030) | ✅ `archivewatch://` + Universal Links (onOpenURL; associated-domains entitlement) | ✅ archivewatch.org/item/{id} canonical + 404-forwarder | ✅ `archivewatch://item/{id}` | Web makes every surface a shareable URL |

## 2. Discover — Home

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Hero / featured banner | ✅ focus carousel | ✅ paged carousel (7s auto-advance) | ✅ `HeroBanner` — full-width **16:9 aspect-locked, never cropped at any window size** (no height cap; macOS windows resize, see macOS-DESIGN §B4) | ✅ Marquee scroll-snap carousel | ✅ 7s auto-advance hero | Same pool/logic; sizing per idiom |
| Curated + dynamic shelves | ✅ | ✅ horizontal rows, deduped | ✅ shelves (Top Rated / Watching Now / Hidden Gems / Community Favorites / Most Discussed) | ✅ scroll-snap rails | ✅ `LazyRow`s | `featured.json` shared |
| Category tiles | ✅ | ✅ tile row → filtered grid | ✅ tile row → filtered grid | ✅ accent tiles | ✅ tile row → filtered grid | accent colors shared; count-gated ≥30 |
| Decade tiles | ✅ | ✅ era tiles + counts | ✅ era tiles + counts | ✅ era tiles | ✅ era tiles | |
| Hidden Gems shelf | ✅ | ✅ | ✅ | ✅ | ✅ | **shared computed `hiddenGem` column** (Decision 050) — all five query the pipeline's flag, none restates a threshold. Was silently EMPTY on all four apps 2026-06-29→08-07 (client constant vs a rescaled popularityScore); web had a different, weaker definition (popularity-tail shuffle). |
| Top Rated shelf (IMDb) + rating sort in Browse | ✅ | ✅ | ✅ shelf + Browse sort (`CatalogDB.Sort`) | ✅ Home shelf (index `top-rated`); Browse rating sort ⏳ | ✅ | votes floor ≥1,000. Membership is COMPUTED in `build_catalog_index`, never restated client-side (D050) |
| Community shelves (Watching Now / Favorites / Most Discussed) | ✅ | ✅ | ✅ | ✅ | ✅ | archive.org signals; vote-floored ≥1,000 |
| Detail community (stats + genuine reviews) | ✅ | ✅ | ✅ | ✅ | ✅ | reviews filtered in the pipeline (`comment_fit.py`), baked into the catalog |
| Director shelves | ✅ | ✅ | ✅ | ✅ top 4 by film count, grouped on the index's `director` column | ✅ | shared query. Web skips a director a curated shelf already covers |
| Continue Watching | ✅ | ✅ | ✅ progress + widget + Home shelf | ✅ | ✅ | progress store (§6) |
| Modes row | ✅ | ➖ removed (Channels tab; modes via Surprise grid) | ➖ (Cartoon via Modes; Channels/Surprise are sidebar) | ➖ removed, as on iOS/macOS — Channels is top-level nav and the modes live on Surprise (Cartoon Mode, Party Play) | ⏳ | links to §5 |
| Public Domain Day section | ✅ | ✅ Home shelf + year-chip explorer | ⏳ | ✅ Home shelf | ✅ Home row | seasonal, shared |

## 3. Discover — Movies / TV / Collections / Search

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Movies grid + facets + sort | ✅ | ✅ | ✅ `LazyVGrid` + decade/sort `Picker`s + real counts + paging | ✅ CSS grid + chips | ✅ grid + chips | shared `CatalogDB.browse` |
| Infinite scroll / paging | ✅ | ✅ | ✅ offset paging | ✅ IntersectionObserver | ✅ | |
| TV series → season → episode | ✅ | ✅ | ✅ `seriesCards()` → `SeriesDetail` → episode play | ✅ `#/series/{slug}` | ✅ phone `SeriesDetailScreen`; **Google TV: `TvSeriesScreen`, a TV-native scene** (TV-DESIGN §4.9, 2026-09-04) — hero, eyebrow, meta, favorite/share, season chips selecting on focus, episode rows | `series/*.json` shared |
| TV never appears in Movies | ✅ | ✅ | ✅ | ✅ | ✅ | Decision 036 (shared `CatalogDB`) |
| TV Specials surface | ✅ | ✅ | ✅ TVBrowseView | ✅ | ✅ | Decision 036 |
| Orphan episodes fold into spines | ✅ pipeline | — | — | — | — | Decision 036; pipeline-side, benefits all via `series/*.json` |
| Prev/next episode in player | ✅ | ✅ | 🚧 | ✅ | ✅ | EpisodeQueue / PlaybackQueue (macOS wiring pending) |
| Collections landing + blurbs | ✅ | ✅ | ✅ `CollectionsList` | ✅ `#/collections` | ✅ | `collection_metadata.json` shared |
| Full-text search (FTS5) | ✅ | ✅ | ✅ `SearchView` over FTS5 | 🚧 title + keyword/AKA/writer/studio blob + **director**, accent-folded. plus **cast** via the lazily-fetched `people.json` sidecar (the `aliases.json` pattern, D085) — 27,490 people, 1.4 MB gzipped, fetched only on the first person search | ✅ debounced FTS5 | same FTS5 index |
| Search result filters | ⏳ | ✅ type/decade menu | ✅ type/decade menu | ✅ type + decade chips over the results, each facet computed against the other's selection | ✅ chips | |

## 4. Detail + Playback

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Detail (backdrop, metadata, cast) | ✅ | ✅ | ✅ poster + metadata + cast row | ✅ | ✅ | shared item record |
| "Also known as" alternate release title | ✅ under the hero title | ✅ under the title | ✅ under the title | ✅ under the title | ✅ phone + TV Detail | Decision 100 — `canonicalTitle` only, ligature+diacritic folded; 1,646 items. Web carries it as `extras.ct` in the detail shards |
| More Like This | ✅ | ✅ | ✅ `store.related` | ✅ | ✅ | shared `related` query |
| Cast → person filmography | ✅ | ✅ | ✅ tappable cast (TMDb photos) → byPerson | ✅ cast bubble → search, resolved through the `people.json` sidecar | ✅ | |
| Share titles / series | ✅ ShareSheet + QR | ✅ ShareLink | ✅ `ShareLink` (item + series) | ✅ share menu | ✅ ACTION_SEND | archivewatch.org URLs (Decision 030) |
| Open in Callsheet (cast/crew app) | n/a | ✅ (App Store fallback) | ✅ `NSWorkspace` open/probe + App Store fallback | n/a | n/a | Decision 038 (+macOS amendment 2026-06-23) |
| Now Playing / media controls | ✅ externalMetadata | ✅ AVKit (lock screen + Control Center) | ✅ AVPlayerView (system media keys) | ✅ MediaSession | ✅ Media3 MediaSession | |
| Title+description in player | ✅ native Info tab | ✅ native externalMetadata | ✅ window title bar "Title (Year)" — macOS AVPlayerItem has NO `externalMetadata`; do NOT use the composition metadata-override (it blanks video, macOS-DESIGN §B5) | ✅ overlay mirrors controls | ✅ Media3 visibility listener | Decision 037 |
| Video playback | ✅ AVPlayerVC | ✅ AVPlayerVC | ✅ AVPlayerView (AppKit) | ✅ `<video>` in `<dialog>` | ✅ Media3 | |
| Resilient streaming | ✅ `ResilientStreamLoader` | ✅ reuse | ✅ reuse (resume-on-reset + node failover) | ✅ range + reconnect | ✅ OkHttp + patient policy | Decision 021/031/034 |
| Resume across launches | ✅ | ✅ | ✅ `WatchProgress` | ✅ IndexedDB | ✅ user.sqlite | progress store (§6) |
| Subtitles / audio / speed | ✅ | ✅ native AVKit | ✅ HLS captions + speed control | ✅ `<track>` subs (5,027 items) via the browser's own caption menu; speed is native too (WEB-DESIGN §5.1a) | ✅ subtitle button + speed | Decision 039 |
| Autoplay / continuous play | ✅ | ✅ | ⏳ | 🚧 queue binge ✅ (episodes, channels, cartoon marathon); a standalone film ends with a **Watch next chooser** rather than autoplay — a choice, not a decision (CLAUDE.md) | ⏳ | F4 queue shared via Core |
| Picture-in-Picture | ✅ AVKit | ✅ AVKit + auto-PiP | ⏳ (AVPlayerView PiP) | ✅ presentation-mode | ⏳ Activity PiP | |
| Background play | n/a | ✅ | n/a (desktop) | ✅ | ⏳ | |

### What "Watch Together" MEANS on each platform

One name covers three different things, and which of them a device can do is
decided by hardware and by what each OS offers — not by how much of the app we
have got round to writing. This table is the canonical answer; the rows below
it carry the engineering detail.

| | **With Friends**<br>SharePlay call, film in sync | **With the World**<br>broadcast to YouTube/Twitch, ONE camera + mic | **With Friends AND the World**<br>film synced across Archive Watch + a call everyone already uses, mixed into the broadcast |
|---|---|---|---|
| **tvOS** | ✅ join + start the session; cannot start the CALL (no `GroupActivitySharingController` on tvOS) | ✅ camera + mic are a Continuity iPhone | 🚫 cannot tap another app's audio (`API_UNAVAILABLE(tvos)`) |
| **iOS / iPadOS** | ✅ full — start the call and the session | ✅ **PROVED END TO END on an iPhone 12, 2026-09-20** — front camera + mic + film to YouTube RTMPS, confirmed by YouTube's own broadcast count 59→61 | 🚫 same |
| **macOS** | ✅ full | ✅ its own or a Continuity camera | ⏳ **the only platform that can HOST one** — §10 |
| **Android phone** | 🚫 no GroupActivities equivalent | 🚧 **RUNS on a Pixel 8a, 2026-09-20** — 20-22 fps, H264+AAC to a real server, film aspect correct; camera and microphone still not attached by any path | 🚫 no per-process audio capture without a rooted device |
| **Android TV / Google TV** | 🚫 same | 🚫 **no camera, no microphone** — entry removed 2026-09-20 | 🚫 same |
| **Fire TV** | 🚫 same | 🚫 same — entry removed 2026-09-20 | 🚫 same |
| **Web** | 🚫 | 🚫 a browser cannot speak RTMP | 🚫 |

**Placement is PROVED ON THE WIRE on every platform that has it** (2026-09-20),
each read back from a server's own recording rather than from a control's
appearance: tvOS `side` at x=143..1137 of 1920; iOS `side` film-left /
camera-right; macOS `side` the same through the armed path; Android `side` both
from a door and by TAPPING the panel mid-broadcast. Four defects were found
doing it, all one shape — a value that never reached the engine.

**So the honest one-line answer per device**: two things on tvOS, iOS and
iPadOS; **three on macOS**; one on an Android phone; and **nothing on the
Android television boxes**, which is the correct answer rather than a gap.

**Naming is binding.** These three are *With Friends*, *With the World*, and
*With Friends and the World*. A surface may not invent a fourth phrase for one
of them, and the third is never called "multi-cam" or "group broadcast" — it is
the second one with the first one's people in it.

#### Two places the code disagreed with this table, found and CLOSED 2026-09-20

Both were found by grepping rather than by reasoning, and both are the same
shape: **a capability that is absent is documented, and a capability that is
present by accident is not.**

- **Google TV offered Go Live**, with no television check and no camera check,
  on boxes that have no camera and no microphone and measured 37.4 ms a frame
  against a 33.3 ms budget with no hardware H.264 encoder at all.
- **Fire TV compiled the whole Studio.** Decision 129 says Google-flavour; that
  is true only of the CAMERA. `CAMERA`/`RECORD_AUDIO` are in
  `src/google/AndroidManifest.xml` but all 18 Studio sources are in
  `src/main/`, so the `amazon` build shipped the engine, the publisher and the
  dialog.

**Both are now gated on the HOST being able to be in the show**, which is the
owner's rule and a better one than either option I offered them:

> *"There is no reason to build/have a feature that shows as 'watch together'
> with only the ability to stream from the Android/google/fire tv box without a
> camera and microphone to go along with it. Everyone might as well just watch
> the movie on their own. The point of watching together is to stream the video
> and have the ability to provide commentary or conversation on top of it."*

`StudioCapability.canHostShow(hasCamera:hasMicrophone:)` — both required —
behind `Context.canHostWatchTogether()`, applied at BOTH Android entry points
in one change, because the phone's overflow row and the television's button
are the same decision and fixing one is how a defect survives in the other.
`FEATURE_CAMERA_ANY`, not `FEATURE_CAMERA`, since the latter means a REAR
camera and a front-only device should pass. Four unit tests, and the two
single-sense cases are asserted separately because `&&` written as `||` passes
both-true and both-false and fails only those.

#### Camera placement, verified 2026-09-20 (§8.22)

Owner: *"I'm not sure the different settings for where your camera will go on
the livestream from iOS (which actually should be available on all platforms)
are actually working as they should."* They were not, and the geometry says so
rather than a screenshot — `StudioLayout.rects` is shared by every Apple
platform, so it is the one place the answer lives. In a 1280x720 program with
a 16:9 camera:

| layout | camera rect, BEFORE | AFTER |
|---|---|---|
| film | none | none |
| corner | 883,64 332x187 | unchanged |
| **theatre** | **883,0 332x187** | **729,0 486x273** |
| side | 853,239 427x240 | unchanged |
| host | full frame | unchanged |

**"Theatre row (you along the bottom)" was "corner" moved down 64 pixels** —
the same 332x187 tile in the same corner, so a host who chose it saw no change
worth a setting. Position was not available to distinguish it (a centred strip
lands on the lower third, found on the glass 2026-09-17), so SIZE is: at 0.38
of frame height the host is a presence along the bottom rather than a
thumbnail. §8.22 now asserts each layout against what its own LABEL promises,
that all five are tellable apart, and that none but `host` touches the lower
third — `host` is exempt because its camera IS the frame, and an earlier
version of that assertion failed the product when the test was wrong.

**Two parity gaps the same question exposed**, both still open:
- ~~Android implements `corner` only~~ **CLOSED 2026-09-20**: `StudioLayout.kt`
  ports `rects(in:cameraAspect:)` number for number, the GLES pass draws into
  arbitrary rects, the panel offers all five in the shared words, and
  `StudioLayoutTest` pins the Kotlin numbers to the ones §8.22 printed.
  **`side` verified on a Pixel 8a from the server's own recording, and the
  PICKER seen on the phone** — "Where you go", five radio rows in the shared
  words, corner selected (2026-09-20).
- ~~tvOS has no layout picker at all~~ **CLOSED AND PROVED ON THE WIRE
  2026-09-20.** The picker itself is still unphotographed (see below), but the
  thing that matters was verified end to end instead: a bench broadcast driven
  with `side` came back from the server's own recording showing the film fit
  into the LEFT TWO THIRDS — x=143..1137 of 1920, exactly 4:3 inside a 1280
  column — with the right third empty because no camera is paired. That is
  better evidence than a photograph of a control.
  **AND THE FIRST RUN OF THAT TEST FAILED, which is why it was worth running**:
  `DetailView` called `engine.setLayout(.corner)` with the value HARDCODED, so
  the picker set the request and the engine ignored it. A picker whose value
  never reaches the engine is worse than no picker, because it looks like it
  worked. Now `studioRequest?.layout ?? .corner`.
  Original note: `GoLiveTV` built its request with `layout: .corner` HARDCODED, so a
  television could only ever broadcast one of the five. Rule 8.8e adds a
  "Where you go" column to the go-live screen in the shared words — deliberately
  NOT in the live mixer, which Rule 8.8c settles as "two channels, a rotation,
  and nothing else". It compiles and the suite is green, and the on-glass
  capture is outstanding: `devicectl device capture screenshot` failed five
  times running on Ben Bedroom this evening (`com.apple.Mercury.error 1001`),
  which is the documented flake rather than an app fault. Changing the layout
  MID-broadcast is still not offered on a television; that is an amendment to
  8.8c and an owner call.

#### macOS Studio, exercised on its own product path 2026-09-20

The three things macOS had not learned from the television were all found by
reading tvOS's code rather than the docs, and all the same shape — a behaviour
written into one platform's file and believed to be the product's:

| | where it had lived | why macOS needed it |
|---|---|---|
| camera-stall recovery | `Views/DetailView.swift` (tvOS view) | macOS can borrow an iPhone, so it drops exactly as a television does |
| "the film's audio is not being sent" | the same tvOS view | macOS uses the `MTAudioProcessingTap`, the very path that fails to attach; tvOS pulls by film position and needs the warning LEAST |
| the Continuity preset CRASH fix | `StudioContinuity.swift` (tvOS only) | an iPhone used as a Mac's camera IS a Continuity Camera |

**Verified on the Mac's own product path**, not merely compiled — the door
drives the same commit chain the sheet does, and the evidence is the server's
recording: `AWCAM preset=hd1280x720 device=FaceTime HD Camera` (a built-in
keeps its preset), `AWCAM attached camera=FaceTime HD Camera mic=MacBook Pro
Microphone`, `AWPUB publishing`, `AWMACDOOR engineLive=true after=7.2s`, both
tracks on the wire. The **theatre** layout renders at 729 px of a 1920 frame —
the 0.38 sizing, materially larger than corner's 499 — with the film
pillarboxed and no collision with the lower third.

The frames from that run were DELETED rather than kept: a Mac's camera points
at the owner's home, and the standing rule about never capturing their whole
screen is the same consideration.

#### Cards, 2026-09-20

| | |
|---|---|
| macOS | ✅ panel + door |
| iOS | ✅ controls sheet |
| **Android** | ✅ **added 2026-09-20** — panel radio list, proved on the wire |
| tvOS | 🚫 none, and deliberately left open: Rule 8.8c settles the mixer as "two channels, a rotation, and nothing else", so a four-way choice needs an owner decision rather than a quiet addition |
| Web | 🚫 no broadcast at all |

Verified the way everything else was today — by TAPPING "Intermission" on a
Pixel during a live broadcast and reading the card back from the server's own
recording: wordmark, rule, "Intermission", the film's name, "back shortly", on
an opaque ground with the film fully replaced. `StudioCardTest` pins the words
to Apple's.

#### The rule this produces

**A device says which of the three it can do, and why it cannot do the others.**
Never a missing button. This is Decision 128's finding ("a missing credential is
a STATE") applied to hardware: the unconfigured state was written as an absence
rather than as a screen somebody reads, and four defects hid in it. A television
that cannot carry a camera should say so where the host looks for one, in the
same sentence that offers what it CAN do.


| **Watch Together — with friends** (SharePlay) | ✅ join + start session; **cannot start the CALL** (`GroupActivitySharingController` does not exist on tvOS, checked in the 27.0 SDK) so it shows an alert instead | ✅ join + start session + start the call (UIKit sheet) | ✅ join + start session + start the call (**added 2026-09-01**; the Mac could previously only JOIN, and joining opened nothing) | 🚫 no Apple GroupActivities equivalent | 🚫 same | Shared `WatchTogether` service; coordination is by **archiveID**, never URL, since every title plays through a private `aw-stream://` scheme and Decision 077 can swap copies mid-film. Binding rules in `docs/SHAREPLAY.md`; Decision 098. Verified end to end on real hardware 2026-09-01 |
| **Watch Together — with the world** (Studio) | 🚧 player + overlays (tvOS-DESIGN §8.8): transport-menu entry, rights gate, ten-foot readout verified on the glass; Continuity Camera is the camera + mic (the mic is an `AVAudioSession` PORT, not a capture device). **GO LIVE EXISTS ON THE TELEVISION** (2026-09-18, Rules 8.8a + 8.8b): `GoLiveTV` is a focus-driven confirmation carrying the film, the destination, an EDITABLE title pre-filled from the audited catalog record, `unlisted` by default, and §3.4a's warning inline — so the old one-time "Before your first broadcast" alert is gone, because a television now HAS the informed moment iOS and macOS always had. `runStudio` resolves a real destination through the shared `StudioGoLive` instead of `destination: nil` (§9.ccc closed). Two columns because the first build put Go live below the fold on a screen with no scrollbar. Verified on an Apple TV 4K 3rd gen against two different films; the commit path is compiled and UNRUN until a host signs in | 🚧 player + overlays (iOS-DESIGN §8.8): go-live sheet, layout/faders/cards sheet, health capsule, all verified on an iPhone 12 | 🚧 Phase 2 (macOS-DESIGN §B13): the Studio is the player in a production mode, `StudioSession` owns the show because §B2a makes the player the window root, readout pinned outside the AVPlayerView HUD, control panel (layout/faders/cards) verified on the glass, camera entitlement + usage string added. **The whole program — film + camera tile + lower third — pulled back from a real publish by the SHIPPING app.** **Go Live exists on the Mac** (§9.mmm, Rule B13g approved 2026-09-18): a menu command opens the same form sheet as iOS §8.9, disabled with no film playing, and on commit resolves a real destination through the now-shared `StudioGoLive`. Seen on the glass with the unconfigured sign-in state and Go Live correctly greyed; the commit path is compiled and UNRUN until client ids exist. Window+audio capture for a guest call is still ahead | 🚫 a browser cannot speak RTMP; only a server-side compositor (Phase 4) can publish from the web | 🚧 Phase 3 — NO RootEncoder: our own `RtmpPublisher.kt` proved against a real server from the JVM **and two real devices** (Google TV API 34, Fire TV API 30); **the encode path too** — GLES into MediaCodec's input Surface (zero-copy), verified from the server's OWN RECORDING (1280×720 h264, the drawn green 0.35 decoding to 0.341). **and the FILM** — ExoPlayer→external OES texture→GLES aspect-fit, verified from the server's recording as a real 1916 intertitle. **and the whole COMPOSITE** — film + corner tile + lower third in one GLES pass, with the provenance line on screen. **the film's AUDIO** (TeeAudioProcessor → AAC) **and the ASSEMBLED engine** (ANDROID-DESIGN §9) — health reporting LIVE with the server's recording carrying both tracks **in the HARNESS**. On the PRODUCT path there was no audio track at all until 2026-09-18: `StudioController.audioTapFor` was called from nowhere, so every Android broadcast published video-only (mediamtx: `tracks: [H264]`) while the film's own 44.1 kHz AAC sat there unread. A Media3 audio processor is fixed at `ExoPlayer.Builder` time, so the only moment it can be installed is when the player is BUILT — never at go-live. Now wired on the product path and measured from the server: both tracks, mean **-19.7 dB** / peak **-3.7 dB** over 45 s (§9.mm). **A/V alignment measured and corrected IN THE HARNESS**: audio was 47 ms late (AAC priming, invisible to FLV), now +4.5–11 ms against Apple's 10 ms — but that harness fed the encoder directly, so both tracks shared a base. **On the PRODUCT path the two tracks are on unrelated clocks: first video PTS 20.000 s against first audio PTS 39.613 s, a +19.6 SECOND split** (macOS on the same instrument: 0 ms). Video is stamped from MediaCodec's Surface clock, audio from its own sample count; nothing gives them a common origin. Invisible until §9.mm put audio on the product path at all — a video-only stream cannot disagree with anything. **FIXED** (§9.qq): video was stamped by a FRAME COUNTER (`frame * 1s / fps`) so it advanced at the achieved render rate rather than real time — 10.5 fps on this dongle — while audio tracked real time; and the audio sample clock did not count PCM the codec refused, so drops became permanent lag. One `showStartNanos` now feeds both and the clock counts OFFERED bytes: **+19,613 ms → -720 ms over 100 s**, and the offset CLOSES across the run instead of opening. Residual drift measured at DURATION for the first time (§9.eee): a ten-minute Android soak drifted **-533 ms over 9.3 min** and the offset CLOSED (1,544 → 1,011 ms), i.e. sublinear and converging — so a feature-length film does not desynchronise by tens of seconds, which the short-run rate would have predicted. 12.5 fps held over the whole ten minutes. **Lip sync is now MEASURED and it is WRONG: audio leads video by ~0.7 s** (§9.ggg) — a flash-and-beep clip, simultaneous within 16 ms at source, came back with six consecutive offsets of -683 to -749 ms. Constant, not growing, which is why the timestamp analysis could not see it: both tracks were internally consistent while describing different moments. ITU tolerance for audio-leads is ~45 ms. **CORRECTED to -174 ms** (§9.iii): the tap runs 0.565 s ahead of playback because `TeeAudioProcessor` sits on the way INTO the audio sink, and the engine now adds THIS device's measured lead to the audio timestamps before a single frame is sent. 712 → 174 ms, against a predicted 147 ms residual. **Still out of tolerance** — ITU's audio-leads guidance is ~45 ms — and the remainder is the video path, stamped at RENDER time after its content was current. The dongle's 10.5 fps was mostly BOXING — both send paths built their FLV tag as `mutableListOf<Byte>() + data.toList()`, boxing every byte of a 50 kB keyframe on the render thread: video drain 16.5 → ~3 ms, audio 29.0 → ~6 ms, program **9-10 → 12-13 fps** (§9.rr). ~13 fps is the dongle's real composite+encode throughput at 720p — `eglSwapBuffers` blocks on the encoder's surface queue, proved by a pacing change that predicted 22 fps and delivered 13. The publish handshake no longer blocks the render thread (§9.ss): it runs on its own daemon thread and the loop adopts the finished publisher, so the publishing second went from `drain=2306.5`/fps=1 to no spike at all, steady state 12-15 fps and drift -315 ms / 117 s. The ~13 fps ceiling is EXPLAINED (§9.uu): this dongle has **no hardware H.264 encoder at all** (both AVC candidates are software; `Dongle R 4K` is a playback device), so the program is encoded on the CPU. The draw split also refutes §9.rr's guess — the encoder swap is ~1.5 ms a frame, the GL draw ~26 ms. The encoder is now chosen explicitly (hardware if the platform has one, `configure` as the test); on this dongle it correctly finds none. Whether the GL cost shrinks behind a real hardware encoder is UNTESTED and needs the Pixel 8a (owner item 8). The **~12 s** gap before the first published packet was MEASURED (§9.tt) and is the FILM, not the Studio: first film frame at 13.2 s / 9.7 s on two titles, with everything the Studio does after it — warm-up, avcC, AAC config, handshake — totalling **~1.0 s**. §6.2's 8-second audio deadline has never been reached (the config takes 70 ms). That makes it Decision 077's playback-latency question, not a Studio defect. Detail entry + rights refusal wired (§9.2), 7/7 on the decision — but its APPEARANCE is unverified: the bench has only televisions, which run the tv surfaces. §9.4 readout + §9.3 sheet built and SEEN on the Google TV (the PlayerScreen is shared). **Dual-surface render built**: the host sees the PROGRAM (film + lower third), verified on the Google TV. Render cost measured A/B on one device: the second pass is **+3.9 ms (within noise)** and a SINGLE pass already costs 37.4 ms against a 33.3 ms budget — the dongle is the bottleneck, not the architecture. Left: a phone-class measurement, a phone to look at, and a real camera | One shared `StudioEngine` + our own `RTMPPublisher` (no third-party encoder — Decision 127). **Android now sends H.264 MAIN, not Baseline** (§9.xx): the encoder asks for the best profile the chosen codec actually advertises (High → Main → Baseline). Asking for High had been inert — Android ignores a profile the encoder lacks, silently, and this dongle advertises no High at all — so the stream stayed Constrained Baseline while the code said otherwise. Verified in the stream: `profile=Main` at an accurate **level 4.1** (§9.zz — asking for a level over-declared 720p30 as 5.0; not asking lets the encoder pick honestly, which is what Apple's AutoLevel does), at the same 12-14 fps, so CABAC costs nothing here and improves the picture at the same bitrate. A phone's hardware encoder should take High and match Apple. **Encoder identity is now REPORTED, not assumed** (§9.vv): macOS measured `hwenc=true` on an M3 at 30 fps / 0 dropped, and the SDK documents VideoToolbox's hardware opt-in as true by default, so Apple never had Android's software-encoder defect. `Require…` is deliberately not set — a slow broadcast beats none. tvOS/iOS carry it in `StudioHealth` and print it on the readout in DEBUG, but have not been READ yet. **§9.ccc is CLOSED on Apple**: the credential path (token → platform API → stream key) was constructed only in `StudioPlayerContainer_iOS`; it now lives in the shared `StudioGoLive`, and iOS, macOS and tvOS all resolve a real destination through it. Both client ids are registered. **Android has TWITCH OAuth and a configured client id** (corrected 2026-09-20 — the previous claim of "no OAuth or platform client at all" was stale): `TwitchLive.kt` speaks helix and reads the ingest-PoP list, `StudioPlatformAuth` runs the device flow, `StudioSignIn.kt` shows twitch.tv/activate and the user code, and `awTwitchClientId` is set. What is missing is a SIGN-IN on the device — so Android still publishes only to the bench destination, for want of one approval rather than for want of code. YouTube on Android remains genuinely absent. One owner step remains for the television: a Google client of type "TVs and Limited Input devices", which is the ONE credential in this app carrying a secret (Decision 128's named cost, now paid deliberately). Binding rules in `docs/WATCH-TOGETHER.md` |
| Watch Together — a camera that dies mid-show | ✅ said out loud on the ten-foot readout, and RECOVERED. Measured 2026-09-19 — a Continuity camera ran a clean 30/s for ten seconds then stopped dead for eighty while every other number stayed healthy | ✅ warning 2026-09-20; recovery landed in `StudioSession`'s pump that afternoon and was INERT here until the evening — iOS does not run that pump (see below) | ✅ warning + recovery 2026-09-20 | 🚫 n/a | 🚧 no camera-stall guard | `CameraStallRecovery` (`Studio/StudioCameraStall.swift`) is the SHARED rule: four dead ticks while attached, on air and having once delivered; three attempts a show; frames resuming reset the grace. It lived inside `Views/DetailView.swift` — the tvOS view — so it existed on ONE platform while this row said "no recovery yet" for the other two, and the same doc noted macOS can use an iPhone as its camera and therefore drops exactly as a television does. tvOS now calls the same rule, so the thresholds cannot drift from the ones §8.23 asserts (9 assertions, four of them controls: a camera that NEVER started, an off-air show, no camera at all, and a healthy one). The guard is still `cameraAttached && cameraFramesReceived > 0 && rate == 0`: the middle term matters, because between the attach and the first delivered frame a camera is legitimately attached at zero |
| Watch Together — the host in the show (camera + voice) | ✅ Continuity Camera + its microphone, both verified on the wire | ✅ the phone's own camera and microphone | ✅ camera and microphone, verified from the server's own recording | 🚫 n/a | 🚧 **BUILT 2026-09-20, UNPROVEN ON A DEVICE.** It was structurally absent that morning — the manifest declared only `INTERNET`, there was no `AudioRecord` anywhere, and the camera's receiving end existed with nothing to feed it. Now: `CAMERA` + `RECORD_AUDIO` in the **google** flavour only (verified by reading both merged manifests — Fire TV gets neither, having neither), `StudioCamera` on **Camera2** (no new dependency, Decision 127) choosing a size the sensor actually advertises and setting it on the texture, `StudioMicAudio` on `VOICE_COMMUNICATION` (the film plays from the same speakers the mic hears, so a raw `MIC` source feeds the film back on itself), both opened and released with the show, and the permissions asked for on the GO-LIVE dialog and nowhere else. **Nothing has run on hardware**: the Pixel's adb pairing is expired and no television has a camera or a microphone, so Camera2 opening, `AudioRecord` at the film's rate and the echo cancellation are all compile-time claims only | On phones this IS the feature — a watch-along without the host is a film. SCRATCHPAD item 8 listed "a real camera tile" as waiting on the Pixel 8a, i.e. as a TESTING gap; it is a BUILDING gap, and the pairing would not have shown a tile. Android's Studio is film-only until a capture source and two permissions exist |
| Watch Together — the mix controls | ✅ `StudioMixerTV`, reached from the Watch Together transport item while live (Rule 8.8c): two channels on a **0–10** scale with a tick per whole level and the unity tick at 8 drawn taller than the knob, adjusted by ROLLING the clickpad (`GCMicroGamepad.dpad` + `reportsAbsoluteDpadValues`, because `UIRotationGestureRecognizer` is `API_UNAVAILABLE(tvos)`); auto-duck toggle; play/pause pauses the film without ending the broadcast. Verified on the glass, Ben Bedroom | ✅ the same **0–10** scale and the same auto-duck toggle in `StudioControlsSheet` (2026-09-20). It was `Slider(value: gain, in: 0...1.5)` — a raw linear amplitude, no number, a +3.5 dB ceiling against the television's +6, and auto-duck stated as a fact rather than offered as a control. `Slider` stays, because it IS the native control here (`@available(tvOS, unavailable)` is why the television draws its own); only the scale and the readout changed | ✅ the same, in `StudioMacPanel` (2026-09-20). **`StudioSession.setAudio` had no `duckEnabled` parameter at all** — Rule 8.8c added it to `StudioEngine` and it stopped there, so every caller that goes through a session, i.e. macOS and iOS, could not reach it | 🚫 a browser cannot hold a stream key | 🚧 **BUILT 2026-09-20, UNPROVEN ON A DEVICE.** There was nothing to convert that morning — `grep` for gain, duck or mic returned nothing at all. Now `StudioAudioMix` carries the same **0–10** scale (`MixLevel` ported: 8 is unity, 0–8 cuts 5 dB a step, 8–10 boosts 3 dB to +6), the same auto-duck **toggle**, and meters on the fader's own scale; the panel draws them with Material's `Slider`, the native control here as on iOS and macOS. **It mixes INTO the film's own buffers and drives nothing** — the film tap stays the timeline, because a mixer on its own cadence is a second clock and §9.qq is what a second clock cost Android (video and audio 19.6 s apart). 12 unit tests with controls cover the gains, the duck, the clip and the mute; the CAPTURE is not covered and cannot be off a device | `MixLevel` is SHARED (`Studio/StudioAudio.swift`): 8 is unity, 0–8 cuts 5 dB a step to silence, 8–10 boosts 3 dB a step to +6. It lived inside `StudioMixerTV.swift` behind `#if os(tvOS)` for one afternoon — the same mistake §9.ccc found with the go-live request. **The meters read on the fader's own scale**, not linearly: a linear 0–1 meter draws 2% for speech at RMS 0.02 and looks dead |
| Watch Together — rights gate | ✅ refusal verified on the glass (Apple TV 4K) | ✅ both branches verified (iPhone 12) | ✅ refusal verified on the glass (macOS 27) — and it caught a STALE schema-1 cache unprompted, on a film the published DB marks `safe_pd_age` | 🚫 a browser cannot hold a stream key | ✅ ported to Kotlin, 8/8 unit tests + **the refusal verified on the glass (Google TV: His Girl Friday, 1940, `presumed_pd`)**; `rightsBucket` now rides the Android lite select behind a schema probe. **`tools/test_studio_rights_parity.py` proves Apple and Android say the IDENTICAL sentence for all 24 buckets**, negative-controlled | `StudioRights`, tier `guaranteed` = `safe_pd_age` only — **4,210 of 24,943 films** (16.9%). An unknown verdict REFUSES. Every bucket has a human sentence, guarded by `tools/test_studio_rights_coverage.py` |
| Watch Together — a dropped connection |  🚧 shared code; the END path is on the glass (the alert a host reads), the REBUILD itself has never been driven here — a tvOS bench destination hits the same Local Network gate as iOS (§9.dd) |  ✅ **DRIVEN ON AN iPHONE 12, 2026-09-20.** A severing proxy cut the link at 25 s and the phone rebuilt it in **0.7 s**, confirmed from BOTH sides: the app logged `socket closed (was publishing): NWError 54 — Connection reset by peer` then `publishing — the server accepted the stream`, and mediamtx logged `closed: EOF` at 19:29:35 with a new connection publishing at 19:29:36. Recordings: 24.4 s before the cut, 82.2 s after | ✅ shared code — §6.6 | 🚫 no RTMP from a browser at all | ✅ **proved ON THE GLASS** (Google TV, shipping app, severed link rebuilt — `conn 2: open`, server re-ingesting to 9.45 MB) — same schedule as Swift (1/2/4/8/15 s, 60 s deadline, one attempt at a time), RECONNECTING outranks OFFLINE. The supervisor is deliberately NOT on the render dispatcher: a 15 s backoff there would freeze the picture. Timestamps continue for free (they come from the encoders). Proved through the severing proxy with the SERVER as witness (`RtmpReconnectTest`): the path came ready again after the cut, control did not. No device run yet | §6.6: a severed link is reconnected on the shared `RTMPReconnectPolicy` schedule (1/2/4/8/15 s, 60 s deadline, matched to the ingests’ own grace windows), the new session restores transaction id 0 + chunk size 128 + the sequence headers and OPENS ON A KEYFRAME, the timestamp base is KEPT, and the readout says RECONNECTING. When the deadline expires the show ENDS rather than pretending. Proved on a real mediamtx through a severing proxy, asserted from the server’s own recording, with a no-reconnect control that dies at the cut (`tools/test_rtmp_reconnect.swift`, §9.x: 18.9 s vs the control’s 5.1 s, post-cut A/V 0.02 s). The ENGINE’s supervisor (backoff + deadline + the forced keyframe) is wired but not yet exercised on a device |
| Watch Together — thermal pressure |  ✅ `.critical` verified ON THE GLASS (the alert, Apple TV 4K 3rd gen) via the engine seam; the bitrate step is shared code, measured on the Mac |  🚧 shared code; never driven here (same Local Network gate) | ✅ shared code — §6.5 | 🚫 n/a | ✅ **proved ON THE GLASS through the real platform API** (Google TV: `cmd thermalservice override-status 3` → the wire drops 2604→**1462 kbps**, 44%; status 4 ends the show; §6.5 asks 40%) — `PowerManager` SEVERE(3) steps the bitrate via `PARAMETER_KEY_VIDEO_BITRATE`, CRITICAL(4)+ ends the show. Binds harder than Apple: the codec is CBR, so there is no `DataRateLimits` to get wrong. The decision is a pure function the loop calls (`StudioThermalTest` 6/6); the status is INJECTED, so the harness seam and the platform seam are the same one. No device run yet | §6.5, CORRECTED: `.serious` lowers the **bitrate** to 60% and says so; `.critical` calls `endShow`. It previously said "halve the RESOLUTION", which an RTMP ingest will not accept mid-publish (format parameters must not change during a stream) — and it was implemented nowhere, which is the only reason it never broke a broadcast. Enforced by `DataRateLimits` at 1.15×, not by `AverageBitRate` alone: at the old 2× cap a 40% step moved the wire 7%. Proved on the REAL engine against mediamtx (`tools/test_studio_thermal.swift`, §9.y: 2893 → 1959 kbps, resolution held) |
| Watch Together — a narrow uplink |  🚧 shared code, measured on the Mac product path; never driven on a television |  ✅ **DRIVEN ON AN iPHONE 12, 2026-09-20**, from the publisher's OWN counters: open — queued 0, 30 fps, 0 dropped; throttled to 200 kbps — queued 1.2-1.6 MB, video **1.8 fps**, 834 dropped, audio **unbroken at 43.8/s**; recovered — queued 0, 30 fps, drops frozen. The picture yields and the voice does not | ✅ **proved on the PRODUCT path** (Mac app at 6 Mbps throttled to 400 kbps: queue pinned at the 1.15 MB cap, video frozen, 492 dropped, audio +43/s unbroken) | 🚫 n/a | ✅ **ported** — writer thread + §6.4a budget; it mattered MORE here, since the old synchronous socket write BLOCKED the single render thread instead of shedding frames. Proved through the same throttling proxy (`RtmpBackPressureTest`): peak 476 kB against a 474 kB cap, 0 drops before / 64 during, **audio 425 of 425 delivered** | §6.4/§6.4a: past a **1.5-second** latency budget of the show’s own bitrate, VIDEO inter-frames yield until the next keyframe and AUDIO is never dropped — structurally, `send(audioFrame:)` has no drop path. The budget was a flat 2 MB, which at 2.5 Mbps is 6.4 s of delay and never once fired. Proved on the REAL engine through a throttling proxy (`tools/test_studio_backpressure.swift`, §9.z): at 400 kbps the queue crossed the cap only while throttled, video fell to **1 fps** and recovered to **30.1**, and audio held **43 frames in the worst congested second**. The same run found every broadcast opening with **59 dropped frames — two seconds blind** — because only the reconnect path asked for an opening keyframe; now both do |
| Watch Together — platform sign-in | ✅ **VERIFIED END TO END ON THE TELEVISION 2026-09-18.** YouTube: `ASWebAuthenticationSession` on tvOS presents Apple's OWN hand-off — "Sign in with Apple Device · You will get a notification on a nearby iPhone or iPad" — so the phone does the Google sign-in and approves the channel, and the token lands on the TV. Proved with the EXISTING `YOUTUBE_CLIENT_ID`: the host approved on their phone, the surface showed "Signed in to YouTube", and a read-only `channels.list` returned their own channel from the Apple TV. **No second Google client and no client secret** — an earlier claim that both were required was reasoning from docs, not measurement, and is withdrawn. Twitch: **a QR code and the host's phone** (owner direction 2026-09-18: *"you are logging in on the TV using that other device"*) — Twitch's device flow VERIFIED on an Apple TV 4K 3rd gen, QR + code on the glass, one press from the go-live surface. `GoogleDeviceAuth` is kept as a fallback for a platform with no such hand-off (Android TV later) and is selected only when a TV client is configured; our iOS client really is refused there (`invalid_client` / *"Invalid client type."*, measured), which is why that fallback needs its own registration if it is ever used. **The live gate now is Google's consent screen: it is in TESTING, so the host clicks through "Google hasn't verified this app" and refresh tokens expire in 7 days** (Google's own wording) — publishing + OAuth verification of the sensitive `…/auth/youtube` scope is a prerequisite for shipping the YouTube half | ✅ written + on the glass (iPhone 12): the unconfigured state renders, Go Live greys out | ⏳ same code, Phase 2 surface | 🔮 Phase 3 — the same two flows, AppAuth or hand-rolled | 🚫 a browser cannot hold a stream key | **Two DIFFERENT flows, because the platforms differ**: YouTube = authorization code + PKCE (S256); Twitch = the **Device Code Grant**, since Twitch offers a public client no PKCE and implicit returns no refresh token. Tokens in the Keychain. Redirect scheme is the BUNDLE ID, not the reversed client id (it must be in Info.plist at build time). Decision 128; `tools/test_studio_signin.swift` 26/26 incl. RFC 7636's own vector |
| Watch Together — the §3.4a host warning | ✅ one-time confirmation before the first broadcast, verified on an Apple TV 4K 3rd gen | ✅ **read on the glass** — iPhone 15 Pro (landscape) and iPad Pro 12.9-inch (regular width), via the `AW_GOLIVE_SCROLL=warning` verification hook, since it sits below the fold | ✅ macOS program panel | 🚫 n/a | ✅ Android panel, parity-tested sentence-for-sentence | One string, `StudioRights.hostWarning`, identical on every platform (`tools/test_studio_rights_parity.py`). It names the two limits the rights gate cannot close: a platform's automatic matcher can interrupt or end a stream even when rights are clear, and a silent film's modern recorded score may still be under copyright. §3.4a |
| Watch Together — chat in the program | ✅ **DRIVEN ON THE GLASS 2026-09-20** — real Twitch chat composited into the program on an Apple TV 4K and read back from the server's own recording: eight pills, left column, wrapped, stopping above the lower third | ✅ **DRIVEN ON THE GLASS 2026-09-20** — the same, on an iPhone 12, with the camera tile in frame beside it | ✅ **proved in the server’s own recording** — real Twitch chat composited into the program, twice, including a live subscription event in marquee orange | 🚫 a browser cannot hold a stream key, and chat is part of the program | ✅ **DRIVEN ON A TELEVISION** (Google TV, 2026-09-18) — real Twitch chat composited into the program and read back from the server's own recording: 8 pills in frame, wrapped, legible over a bright intertitle. `StudioChatTwitch.kt` (anonymous IRC on a raw SSLSocket, no third-party dep) + `StudioOverlayBitmap.withChat`, re-rendered only when the line ids change because the Android overlay is ONE texture. Apple's pill alphas on purpose. The device run found two faults the compile could not: the channel arrived via `System.getenv`, which on Android reads the **zygote's** environment and so could never have been set by `am start` (now the `aw_studio_chat` intent extra); and the chat column's floor was a second guess at where the lower third begins, which at 720p put its two newest pills **on top of the film's title** — both edges now come from one expression (§9.mm) | **Twitch reads with NO credential** — anonymous `justinfan` IRC, verified against tmi.twitch.tv, so this half was never owner-blocked. `StudioChatTwitch` + `StudioEngine.attachTwitchChat` (§6.4/§6.4a): the ENGINE reads and draws, a surface only names the channel — it lived in `StudioSession` for one commit, which is macOS-first, so it reached the Mac alone. YouTube still needs the host’s OAuth: `liveChatMessages.list` is quota-metered, dictates its own `pollingIntervalMillis`, and its history is bounded by the first request | **The tvOS run caught a stress case worth keeping**: a five-line spam message still respected the lower-third floor, which is the bound §9.mm added after two pills landed on the film's title at 720p.
| SharePlay — group waits for a stalled member | ✅ | ✅ | ✅ | n/a | n/a | `.stallRecovery` suspension driven centrally from `WatchTogether.attach`. Was declared and **called by nothing on any platform** until 2026-09-01 — every player had a coordinator that never suspended, so a buffering viewer drifted instead of the group waiting |
| Cast / AirPlay | n/a (Apple TV IS the receiver — tvOS does not send) | ✅ AirPlay route-swap | ✅ AirPlay route-swap (**added 2026-08-08**; macOS had the AVPlayerView route button but no swap, so it failed on every title) | ✅ Cast sender (receiver 58AF34C3) | ✅ Cast sender, google flavor only | Shared `AirPlayRouting` picks the receiver-fetchable URL (HLS first, so captions survive). AirPlay WORKS on iOS + macOS. Apple does not support video AirPlay through a custom resource loader and every local path is loader-backed, so the route swap is what makes it work — Decision 051. Fire TV excluded: Cast is GMS-dependent |

## 4b. Create — Clip Studio (phone-differentiating; Decision 033)

> The native PHONE apps create single clips. On macOS this is superseded by the
> multi-clip **Creation Studio** (§4c) — so macOS = n/a here, not a gap.

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Single-clip create (trim/reframe/caption/looks/speed/GIF/export) | n/a (lean-back) | 🚧 full v1+v2 suite (`docs/CREATE-STUDIO-PLAN.md`) | n/a → Creation Studio (§4c) | 🚫 (viewer) | 🚧 Media3 port (MP4 only) | engine 100% native each platform |

## 4c. Create — Creation Studio (Mac-EXCLUSIVE; Decision 042)

> The Mac assembles a FILM (multi-clip timeline across archive.org titles), not one
> clip. Belongs only on macOS (filesystem + document model + heavy compute +
> pointer/keyboard editor). Binding spec: `docs/macOS-DESIGN.md`. Engine = native
> AVFoundation (cache-then-export, two-pass grade→overlay). Learning gate: yields an
> EDITABLE timeline, never a one-tap auto-cut.

| Feature | macOS | Other platforms | Notes |
|---|---|---|---|
| `.archiveproj` document (proxy clips, non-destructive) | ✅ ReferenceFileDocument package; durable embedded media | n/a | Library ≠ Project |
| Multi-clip timeline (AppKit `NSView`+`CALayer`) | ✅ trim/split/zoom/markers/snapping/ripple | n/a | the one custom UI element |
| Transitions (cross-dissolve / wipe / push) | ✅ native opacity/transform/crop ramps | n/a | no Metal needed |
| Color Looks · speed · music bed · voiceover | ✅ | n/a | per-clip graded source files |
| Text → Supercut (caption-validated word timing) | ✅ find + compose (longest-match) + forced-aligned word index + loudness | n/a | flagship #9; macOS-26 SpeechAnalyzer |
| Stock-shot mining (scene-detect + CLIP tags) | ✅ `clips.sqlite` index (CI) | n/a | #6; CLIP-on-Linux, not Apple Vision |
| Export (MP4 / multi-format) + provenance credit | ✅ cache-then-export | n/a | source embedded in metadata |
| Publish (Internet Archive IAS3) | ✅ | n/a | #7; YouTube deferred on OAuth verification |

## 5. Surprise + Immersive modes

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Surprise / random actions | ✅ | ✅ | ✅ `SurpriseView` | ✅ `#/surprise` | ✅ | shared random queries |
| Channels (EPG guide) | ✅ | ✅ touch EPG | ✅ `ChannelsView` (shared `ChannelScheduler`) | ✅ CSS listing | ✅ Compose guide | date-seeded scheduler ported per platform |
| Create / user channels | ✅ synced | ✅ synced | ⏳ | ✅ local | ✅ local | |
| Cartoon / Kids mode | ✅ | ✅ | ✅ `Modes_macOS` | ✅ | ✅ | color/B&W flags shared |
| Commercial-break controls | ✅ | ✅ toggle | ⏳ | ✅ About → Preferences, default on (a channel without them is not a channel) | ⏳ | |
| Party Play (muted) | ✅ | 🔮 | ✅ `Modes_macOS` | ✅ Surprise → Party Play; muted lineup from the channel pools, never persisted | ✅ `TvPartyScreen` (TV) | ambient mode; Roku ✅ (Surprise door, whole-catalog colour pool) |
| Synopsis provenance caption (Decision 124) | ✅ under the synopsis | ✅ | ✅ | ✅ `.item-desc-source` | ✅ phone + TV | Roku ✅ in-line prefix for uploader text only (no caption row) |
| Lineup player verbs: sound toggle / open title / remember | ✅ transport-bar actions (tvOS-DESIGN §9.3a) | n/a (no lineup player) | ⏳ sound is native; open/remember not yet | ⏳ sound is the native control; open/remember not yet | ✅ options panel, D-pad Up (TV-DESIGN §5.6); phone n/a | Roku ✅ Up → options (ROKU-DESIGN §6.9). Ephemeral lineups also write history-only after 60 s on tvOS + Android |
| Cover-art screensaver | ✅ + idle trigger | 🔮 | 🔮 | 🔮 as on iOS — a web page should not take over an idle screen; the OS and browser own idle | 🔮 | 10-foot/lean-back idiom |
| VHS effect overlay | ✅ Metal | 🔮 | 🔮 | 🔮 | 🔮 | optional polish |

## 6. Personalization + sync

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Favorites | ✅ | ✅ | ✅ Detail heart + Library | ✅ | ✅ | local store per platform |
| Playlists | ✅ | ✅ | ✅ `PlaylistSheet` + Library | ✅ | ✅ | |
| Watched / hide-watched | ✅ | ✅ | ✅ `hideWatchedOnHome` filter | ✅ `everDone` tracked already; toggle in About → Preferences, applied to every Home shelf | ✅ | |
| Continue Watching progress | ✅ | ✅ | ✅ | ✅ | ✅ | |
| Watch history (full ever-watched record, D078) | ✅ Library History | ✅ Library tab | ✅ Library shelves | ✅ Library grid | ✅ Library tab | durable everCompleted + playCount + firstWatchedAt; Apple synced via CloudKit |
| Cross-ecosystem history sync (Drive App Data, D028) | n/a (CloudKit) | n/a (CloudKit) | n/a (CloudKit) | ✅ LIVE | ✅ LIVE (google flavor only) | OAuth configured 2026-09-03; VERIFIED Pixel 8a ↔ browser both ways incl. deletions — docs/google-oauth-setup.md |
| Local persistence (offline-first) | ✅ SwiftData | ✅ SwiftData | ✅ SwiftData | ✅ IndexedDB | ✅ user.sqlite | |
| Per-ecosystem sync (own cloud) | ✅ CloudKit | ✅ CloudKit | ✅ CloudKit (SAME container; Settings → Account; `CloudKitSyncService`) | ✅ Drive App Data + ✅ CloudKit JS (Sign in with Apple, live 2026-09-10) | ✅ Drive App Data (Settings → Sync) | Apple islands converge on one iCloud private DB; the WEB is the only client that can hold both — Apple token created 2026-09-10 (docs/web-apple-sync.md) |
| Cross-ecosystem sync (all platforms) | 🚫 | 🚫 | 🚫 | ✅ Google Drive (D102) + Apple via CloudKit JS, both live; one merge (Decision 078) | 🚫 | Out of scope as a BACKEND (D028). The web is the exception: signed into both clouds it merges Apple + Google state with one set of rules |
| Deletions carry tombstones | ✅ | ✅ | ✅ | ✅ | ✅ | without one, a removed favorite is resurrected by the next pull — Apple's #84, now closed on Android + web too |
| **Download a film for offline viewing** | 🚫 **platform cannot** | ✅ Detail ⬇ → copy-picker sheet · **22/22 on iPhone 12 + iPad Pro** | ✅ Detail Download menu · **verified on this Mac** | 🚫 | ⏳ Media3 `DownloadManager` | Decision 099. tvOS has NO durable storage — a purgeable `Caches` plus ~500 KB of `NSUserDefaults`, no Documents dir — so a download there is a promise the OS may delete between launches. Web: browser quota will not hold a feature film. Background `URLSession` → Application Support, `isExcludedFromBackup` |
| Downloads in Library (manage + remove) | 🚫 | ✅ Downloads section, swipe delete / pause / resume | ✅ Downloads rows + Remove | 🚫 | ⏳ | Downloads is the FIRST Library section and the tab opens there when offline |
| Play a downloaded film with no network | 🚫 | ✅ plain `AVPlayerItem(url: file://)` — decoded off disk on both devices | ✅ **proven with the network DENIED to the process** (negative control: archive.org unreachable) | 🚫 | ⏳ | iOS-DESIGN §8.7 / macOS-DESIGN §B9b — the resilient loader is skipped; nothing to be resilient about |
| Offline subtitles for a downloaded film | 🚫 | ✅ downloaded WebVTT via the caption overlay | ✅ same (`liveLine`) | 🚫 | ⏳ | `OfflineSubtitles`. An HLS master cannot carry it — its video rendition is a remote URL (D099) |
| Offline state banner | n/a (always connected) | ✅ "Offline — your downloads still play" + jump to Library (OCR-verified on iPhone + iPad) | 🔮 | ✅ informational only — never gates playback (a captive portal reports online) | ⏳ | `NWPathMonitor`. Browse/Search keep working from the local catalog DB; only streaming stops |
| Downloads are device-local (never synced) | n/a | ✅ | ✅ | n/a | ⏳ | iOS-DESIGN §9.7 — a favorite is an intention, a download is bytes on ONE device |

## 7. Settings + account

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Mature-content filter (default ON) | ✅ | ✅ | ✅ `hideAdultContent` toggle | n/a (pre-filtered) | ✅ | Decision 012 |
| Category visibility toggles | ✅ | ✅ | ⏳ | ✅ About → Preferences; hides the tile AND the items, sharing one count with the tile row | ⏳ | |
| Autoplay/playback options | ✅ | ✅ | ⏳ | ✅ About → Preferences: opt-in autoplay (countdown on the end card, stoppable), commercials, hide-watched, categories. Speed is the browser's own (§5.1a) | 🚧 | |
| Downloads storage + Remove All | 🚫 | ✅ + cellular toggle (OFF by default) | ✅ (no cellular question on a Mac) | 🚫 | ⏳ | Decision 099 |
| TMDb attribution (required) | ✅ | ✅ | ✅ verbatim notice | ✅ | ✅ | Decision 007 |
| Donate to Internet Archive | ✅ | ✅ | ✅ | ✅ | ✅ | Decision 010 |
| Sign-in (sync gate, optional) | ✅ Apple | ✅ Apple | ✅ Sign in with Apple | ✅ Google (+ ⏳ Apple) | ✅ Google (phone AND TV) | only gates sync; status row shows account / last sync / last error / Sync now |
| Account deletion | ✅ | ✅ | ⏳ | 🔮 | 🔮 | review requirement |

## 8. Platform reach + integration

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Home-screen surface | ✅ **Top Shelf** (`.sectioned` poster rows, Continue-Watching-first with resume bar + Play-resumes; ~15 named editorial rows rotated on a 6h window from the published `topshelf.json` pools; tvOS-DESIGN §15, Decision 049) | ✅ **WidgetKit suite**: Continue Watching (S/M/L + Lock Screen, art + resume bar), Pick of the Day, Favorites, Surprise Me (+ Lock Screen) + iOS-18 **Surprise Me Control** (Control Center / Action button) | ✅ **WidgetKit** (S/M/L): Continue Watching, Pick of the Day, Favorites, Surprise Me (sandboxed appex embedded in the Mac app) | 🚫 (PWA shortcuts only) | ⏳ home-screen widgets (Glance) | art pre-cached into the App Group (`WidgetArtCache`); deep-links into the app; `docs/research/topshelf-and-widgets.md` |
| Voice / shortcuts | ✅ App Intents + Siri | ✅ App Intents + Siri | 🚧 (shared App Intents; Spotlight/Siri surface TBD) | n/a | ✅ App Shortcuts | "surprise me", "random film" |
| Spotlight / system search | n/a | 🔮 Core Spotlight | 🔮 Core Spotlight | n/a | 🔮 App Search | |
| Installable app | App Store (cloud-built) | App Store (cloud-built) | **App Store — UPLOADED 1.3.249/771** via the cloud workflow (`.github/workflows/appstore-build.yml`, GitHub `macos-26` runner = released macOS + Xcode 26.6 → clears ITMS-90301 beta-OS + ITMS-90111 floor; free for this public repo). Same `app.archivewatch.tvos` record (Decision 042); manual `.p12` signing; macOS-DESIGN §C2c. Local `submit-appstore.sh` only works on a released-macOS box. | ✅ PWA | Play Store | All 3 Apple platforms build cloud-side now |
| Handoff / continuity | 🔮 | 🔮 | 🔮 | n/a | n/a | NSUserActivity declared |

## 8b. Non-Apple TV platforms (Decision 047 · `docs/TV-DESIGN.md`)

Two new **clients**, not two new products. They are tracked in their own section
rather than as two more columns above because the existing tables are already
six wide, and because a TV client's parity question is *"which wave is this
surface in?"* — the per-surface waves are binding in TV-DESIGN §2.

| Client | Reuse vehicle | Ships to | Status |
|---|---|---|---|
| **Android TV** | the SAME `android/` app + AAB + `applicationId`, TV branched at runtime on `UiModeManager` | Google TV / Android TV **and** Amazon Fire TV | ✅ all surfaces D-pad-verified (12/12); compliance gates pass; Play TV form factor opted in — only the asset upload remains (owner) |
| **Web-TV** | the SAME root PWA + `tv.js`/`tv.css` layer | LG webOS, Samsung Tizen, VIDAA / Titan / Zeasn | 🚧 focus engine + packaging staged |
| **Google Cast** | hosted HTML receiver + web/Android senders | Chromecast, Google TV, Chromecast-built-in (incl. most **Vizio**) | ✅ **PUBLISHED** `58AF34C3`; both senders wired + declared in the console. ⏳ on-device verification (needs a Cast device) |
| **AirPlay** | **needed new code** — see below | Apple TV + AirPlay-2 TVs (Samsung, LG, Vizio, Sony, TCL, Roku TV) | ✅ built, ⏳ owner device QA |
| **Roku** | none — 0% reuse, BrightScript/SceneGraph rewrite | Roku (#1 US CTV) | 🔮 separate funded decision |
| **Vizio native** | — | — | 🚫 no self-serve program; BD-gated and ad-aligned post-Walmart. Reached via Cast/AirPlay instead. |

| Verb | Android TV | Web-TV | Notes (native idiom) |
|---|---|---|---|
| Top-level nav | ✅ focusable rail, expands on focus | ✅ topnav + spatial focus | a bottom tab bar is a touch affordance; it reads as an error at ten feet |
| Home (hero + shelves) | ✅ shares `rememberHomePayload` with phone | ✅ existing shelves + TV breakpoint | shelf order + cross-shelf dedup single-sourced so they cannot drift |
| Browse | ✅ TV-native: scope chips + 6-col D-pad grid, focus-driven paging | ✅ | grid uses FIXED columns so "first column" is knowable |
| Detail | ✅ TV-native: full-bleed hero, focus-first Play, More Like This | ✅ | |
| Search | ✅ TV-native: on-screen keyboard **+ no-typing browse doors** | ✅ | §3.6 — a keyboard-only Search is a dead end on a remote |
| Library | ✅ TV-native: focusable sections; **Clips tab omitted** | ✅ | Clip Studio is never on TV (§2) |
| Channels (EPG) | ✅ focusable programme blocks, tune-in by remote | ✅ | the EPG layout was already a ten-foot idiom; it needed focusability, not a rewrite |
| Surprise · Collections · Cartoon · filtered grids | ✅ operable via shared focusable tiles + shell focus claim | ✅ | |
| Playback | ✅ Media3 + D-pad centre/seek + media keys | ✅ `<video>` + remote key contract | TV-PC / TV-PP |
| Background media controls | 🚫 **gated off — TV-NP forbids it for video apps** | 🚫 n/a | phone keeps its MediaSession; TV pauses on switch-away |
| Picture-in-Picture | 🚫 gated off on TV (TV-NP wants a pause) | 🚫 n/a | |
| Cast (send to TV) | ⏳ needs `CastPlayer` wiring; flavor split ✅ done | ✅ sender shipped | Cast is GMS — `google` flavor only, never `amazon`/Fire |
| Subtitles | ✅ Media3 `SubtitleConfiguration` — **verified rendering on TV** | ✅ `<track>` via a same-origin **blob** — **verified 1,947 cues** | cross-origin `<track>` fails silently and `crossorigin` on `<video>` would break playback (no CORS on archive.org storage nodes) |
| Sign-in + sync | 🚫 first wave | 🚫 first wave | no CloudKit off Apple; Drive App Data deferred |
| Clip Studio / Creation Studio | 🚫 **never** | 🚫 **never** | a remote has no text entry or direct manipulation (Decisions 033 / 042) |
| Platform home-screen integration | 🔮 Google TV channels / Fire TV catalog | n/a | constrained by §1.4 — our editorial + the user's own Continue Watching, never an opaque model row |

**Verification (all runnable, all green):**

| Gate | Covers | Result |
|---|---|---|
| `tools/verify_tv_focus.sh` | Android TV surfaces by remote (incl. shared Settings/Library via the a11y tree) | 12/12 |
| `tools/tv_browser_tests.js` | web-TV in Chrome | 20/20 |
| `tools/test_tv_focus.mjs` | web-TV focus algorithm | 10/10 |
| `tools/test_tv_ua.mjs` | platform detection vs real UAs | 5/5 |
| `tools/audit_tv_g6.py` | 64-bit + 16 KB page sizes | PASS |
| `tools/audit_fire_tv_gms.py` | Fire TV zero-GMS (amazon flavor) | PASS |

**Submission packs drafted:** `docs/webos-submission.md` (UX scenario +
self-checklist — LG auto-rejects thin checklists), `docs/tizen-submission.md`
(Samsung manual-QA pass + the US-only tier decision).

**Compliance gates (Google TV app quality).** ✅ TV-ML leanback launcher · ✅ TV-MT
touchscreen not required · ✅ TV-LB/TV-BN 320×180 banner with app name · ✅ TV-PS
`minSdk` 29 ≤ 31 · ✅ **TV-G6 64-bit + 16 KB page sizes** (measured, all 12 native
libs — `tools/audit_tv_g6.py`) · ✅ TV-G1 AAB · ✅ **Fire TV zero-GMS**
(`tools/audit_fire_tv_gms.py`) · ⏳ TV-DP full D-pad reachability (needs the
remaining ten-foot passes + device QA).

## 9. Shared backend / data plane (consumed by ALL clients — no per-platform copy)

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `catalog.sqlite.zz` (+ `seed.sqlite`) | full catalog + FTS5, query-on-disk | GitHub Release (rolling) | tvOS, iOS, **macOS**, Android (download+inflate); web (range-query in place) |
| `catalog.json` | editorial source of truth | GitHub Release | pipeline only |
| `catalog-index.json` | slim search index | GitHub Pages | web fallback / public tool |
| `featured.json` | shelves, categories, accent colors, adult deny-list | git + Pages | all clients |
| `series/*.json` | TVmaze canonical episode spines | git + Pages | all clients |
| `collection_metadata.json` | curated collections + blurbs | git | all clients |
| `clips.sqlite` / `subtitle.sqlite` | Creation Studio stock-shot + word-timing indices | GitHub Release (CI) | **macOS** (Creation Studio) — Decision 042 |
| Archive.org | video streams + posters | archive.org | all clients (playback + images) |
| `archivewatch-covers` | generated frame covers | archive.org item | all clients (images) |
| Python pipeline (`tools/`) | discovery, enrichment, rights audit, covers, color, match-verify | CI / local | build-time only — **no per-platform reimplementation** |
| `excluded` (rights) + `isAdult` flags | copyright + mature filtering | baked into `catalog.sqlite` | every client filters for free |

---

## Maintenance protocol
1. Find the feature's row; add one under the right section if new.
2. Update each platform's symbol; note deltas in Notes.
3. Cross-link the governing platform design doc.
4. When a platform rejects a feature, record it as an Out-of-scope row in that
   platform's design doc and mark 🚫 here with the reason.
5. Apple platforms (tvOS · iOS · macOS) share the Swift Core — a shared-Core
   change usually moves all three columns; verify each builds.
