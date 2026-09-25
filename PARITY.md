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
| Hero / featured banner | ✅ focus carousel | ✅ paged carousel (7s auto-advance) | ✅ `HeroBanner` — full-width **16:9 aspect-locked, never cropped at any window size** (no height cap; macOS windows resize, see macOS-DESIGN §B4) | ✅ Marquee scroll-snap carousel | ✅ 7s auto-advance hero | Same pool/logic; sizing per idiom. **One rights bar everywhere** (2026-09-24): positive evidence only — `safe_pd_age`/`safe_gov`/`safe_cc`, nothing 1978+ unless PD by age. Apple `isHeroRightsSafe`, Android `heroAnd`, web + Roku index col 16 `heroSafe`; `tools/test_hero_rule_parity.py`. **Community rows** (Most Discussed / Community Favorites / Watching Now) take the same bar on every platform (owner, 2026-09-25): Apple `heroRightsAnd`, Android `heroAnd`, web/Roku + Top Shelf via the index (`HERO_SQL`) |
| Curated + dynamic shelves | ✅ | ✅ horizontal rows, deduped | ✅ shelves (Top Rated / Watching Now / Hidden Gems / Community Favorites / Most Discussed) | ✅ scroll-snap rails | ✅ `LazyRow`s | `featured.json` shared |
| Category tiles | ✅ | ✅ tile row → filtered grid | ✅ tile row → filtered grid | ✅ accent tiles | ✅ tile row → filtered grid | accent colors shared; count-gated ≥30 |
| Decade tiles | ✅ | ✅ era tiles + counts | ✅ era tiles + counts | ✅ era tiles | ✅ era tiles | |
| Hidden Gems shelf | ✅ | ✅ | ✅ | ✅ | ✅ | **shared computed `hiddenGem` column** (Decision 050) — all five query the pipeline's flag, none restates a threshold. Was silently EMPTY on all four apps 2026-06-29→08-07 (client constant vs a rescaled popularityScore); web had a different, weaker definition (popularity-tail shuffle). |
| Top Rated shelf (IMDb) + rating sort in Browse | ✅ | ✅ | ✅ shelf + Browse sort (`CatalogDB.Sort`) | ✅ Home shelf (index `top-rated`); Browse rating sort ⏳ | ✅ | votes floor ≥1,000. Membership is COMPUTED in `build_catalog_index`, never restated client-side (D050) |
| Community shelves (Watching Now / Favorites / Most Discussed) | ✅ | ✅ | ✅ | ✅ | ✅ | archive.org signals; vote-floored ≥1,000 |
| Detail community (stats + genuine reviews) | ✅ | ✅ | ✅ | ✅ | ✅ | reviews filtered in the pipeline (`comment_fit.py`), baked into the catalog |
| Director shelves | ✅ | ✅ | ✅ | ✅ grouped on the index's `director` column | ✅ | ordered by the pipeline's popularity rank (`director_rank` / index `directorRank`, owner 2026-09-25), film count as fallback; Roku too. Web skips a director a curated shelf already covers |
| "New to Archive Watch" shelf | ✅ | ✅ | ✅ | ✅ | ✅ | owner 2026-09-25, all platforms. `new-arrivals` in featured.json (type `computed`); membership = `addedAt` within 45 days, computed in `build_sqlite._shelf_ids_for` for every platform (D050). Second featured shelf in the canonical order; Roku by featured.json file order |
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
| Collections landing + blurbs | ✅ | ✅ | ✅ `CollectionsList` | ✅ `#/collections` | ✅ | `collection_metadata.json` shared. **Film series** (2026-09-24): 19 `series-*` entries (Rathbone Holmes, Our Gang silents, Superman cartoons, Why We Fight…) whose members are films carrying a listed `franchise`; Apple/Android via `item_collections`, web/Roku via the index. Apps show them after an app update (bundled metadata); web on deploy; Roku on package. Carry On withheld (Decision 114 band) |
| Full-text search (FTS5) | ✅ | ✅ | ✅ `SearchView` over FTS5 | 🚧 title + keyword/AKA/writer/studio blob + **director**, accent-folded. plus **cast** via the lazily-fetched `people.json` sidecar (the `aliases.json` pattern, D085) — 27,490 people, 1.4 MB gzipped, fetched only on the first person search | ✅ debounced FTS5 | same FTS5 index |
| Search result filters | ⏳ | ✅ type/decade menu | ✅ type/decade menu | ✅ type + decade chips over the results, each facet computed against the other's selection | ✅ chips | |

## 4. Detail + Playback

| Feature | tvOS | iOS | macOS | Web | Android | Notes |
|---|---|---|---|---|---|---|
| Detail (backdrop, metadata, cast) | ✅ | ✅ | ✅ poster + metadata + cast row | ✅ | ✅ | shared item record |
| "Also known as" alternate release title | ✅ under the hero title | ✅ under the title | ✅ under the title | ✅ under the title | ✅ phone + TV Detail | Decision 100 — `canonicalTitle` only, ligature+diacritic folded; 1,646 items. Web carries it as `extras.ct` in the detail shards |
| More Like This | ✅ | ✅ | ✅ `store.related` | ✅ | ✅ | **Ranked once in the pipeline** (Decision 139, `item_related`; web + Roku via detail shard index 10): shared series, director, cast, writer, keywords lead, then the old type + era query fills the row. Roku: `moreLike` leads with index 10, then samples by type + era — verified on the Stick 4K 2026-09-24 against the live shards: `AWSVC moreLike type='silent-film' ranked= 10 pool= 2118 shown= 12` (Metropolis). Web verified in headless Chrome: Metropolis → M, Dr. Mabuse, Woman in the Moon … Spies |
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

#### JOINING A ROOM is a fourth column, and it is NOT the third mode (2026-09-21)

The table above is about what a device can HOST. §11.10 adds the question it
never asked — what a device can JOIN — and the answers differ, which is the
whole point:

| | can HOST a room | can JOIN a room |
|---|---|---|
| **macOS** | ✅ shipped — Watch Together ▸ Start a room, code shown to read aloud | ✅ shipped — Watch Together ▸ Join a room |
| **tvOS** | 🚫 the broadcast half needs a camera (Decision 132) | ✅ **shipped** — a sidebar row and a focus grid, no keyboard |
| **iOS / iPadOS** | ⏳ not built | ✅ **shipped** — a toolbar item on Library, not a sixth scope (the picker is at its measured width limit) |
| **Android phone** | ⏳ not built | ✅ **shipped** — the Library app bar, not a sixth tab (the bottom bar carries five) |
| **Android TV / Fire TV** | 🚫 same as tvOS | ✅ **shipped** — a Library section and a focus grid, no keyboard. Both flavours build, so Fire TV has it too |
| **Web** | 🚫 cannot broadcast | ✅ **shipped** — `/together/#code-film` forwards into the hash router and the `<video>` follows the room |
| **Roku** | 🚫 cannot broadcast | 🚧 **RUN on a Roku 2026-09-24 (v1.42.628), not yet in a store package** — the first device run re-seeked on almost every poll (a Float epoch, and no hold while a seek buffered); fixed, and now one join seek, one catch-up, then in step. Launch door `awRoom=<code>`. Library ▸ Options ▸ *Join a Watch Together room…*: a `StandardKeyboardDialog`, the room read once off the render thread, the film started at the room's position, `PlayerScreen.roomCode` following (ROKU-DESIGN §8a). No rate nudge (the `Video` node has no rate control): inside a second it is left, beyond it is seeked. The clock is a Double and a blip no longer ends the room (v1.42.614) |

**Joining needs no camera and no microphone**, which is why a television —
removed from the hosting table entirely on 2026-09-20 — is the best device to
join from. Decision 132's sentence was about a HOST offering a broadcast
nobody is in; a guest is in somebody else's show and the conversation is on
the call they are already on. §11.10 scopes that decision rather than
weakening it.

**Built and DEPLOYED** (2026-09-21; rate limits, validation and the hourly
sweep added 2026-09-23). The sync transport (`worker/src/together.js`) runs on
the Worker that already serves the privacy counter, on the D1 already bound to
it — no infrastructure of its own, which is why it fits the $0 constraint
rather than merely being cheap. Proved LIVE on 2026-09-23: a Mac guest (join,
seek, nudge, host pause on the exact frame, host end) and a browser guest on
archivewatch.org (§8.66, headless Chrome: in step to 0.03 s, pause on the
host's frame).

Proved against a running Worker rather than reasoned about: §8.27 the
arithmetic, §8.28 the codes, §8.29 the app/Worker parity of one rule in two
languages, §8.30 the routes, §8.31 a real host and a real guest agreeing.

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
worth a setting. Position was not available to distinguish it (a centered strip
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
reading tvOS's code rather than the docs, and all the same shape — a behavior
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
| tvOS | ✅ **added 2026-09-21** — a "Show a card" submenu in the live transport menu (Rule 8.8g), with a checkmark on the one on air. Not in the mixer: 8.8c's duck toggle is the only focusable control there by design, and a second button would break the faders. **Intermission verified on the wire from an Apple TV 4K** |
| Web | 🚫 no broadcast at all |

##### Chat ON the program, 2026-09-22

| | |
|---|---|
| Twitch | ✅ read anonymously over IRC since 2026-09-18 (no account needed), on every Apple platform |
| **YouTube** | ✅ **added 2026-09-22** — `liveChat/messages` polled at the interval YouTube itself returns, armed from the `liveChatId` the broadcast's own creation hands back. macOS, iOS and tvOS, because the id is carried by the shared `StudioGoLive.Destination` rather than by any one platform's file. **Not yet seen on air** — the reader has never met a live chat id |
| Android | ⏳ neither. `TwitchLive.kt` speaks helix but no chat reader exists, and YouTube on Android is absent entirely |
| Web | 🚫 no broadcast at all |

The renderer was never the gap: `StudioOverlay.chat` and its cached column
have drawn since 2026-09-18. The gap was that `StudioGoLive.destination()`
returned a bare `URL?`, so the chat id was read out of the broadcast and
dropped in the same function. §8.36 now guards the whole chain.

##### Framing the camera, 2026-09-22 (macOS-DESIGN §D14a)

| | |
|---|---|
| macOS | ✅ OBS's canvas pattern in the STREAM preview — drag to move, corner to resize, **edge to reshape (which IS the crop, since the tile is aspect-filled)**, scroll to zoom the source, ⌥-drag to pan it. No sliders; a readout and a Reset. Verified on the glass: tile dragged bottom-right → centre, reshaped to portrait, corner-resized, `zoom > 1` confirmed by the Pan line appearing, and a negative control (scrolling OUTSIDE the box changes nothing) |
| iOS · tvOS · Android | ⏳ the ENGINE carries `StudioCameraFraming` on every Apple platform, so the composite honours it wherever it is set; no other surface offers the gestures. A pointer-and-scroll interaction does not port to a Siri Remote or a touchscreen unchanged, and inventing one for each is a design question rather than a port |
| Web | 🚫 no broadcast at all |

##### A card of the host's OWN WORDS, 2026-09-22 (macOS-DESIGN §D10)

Owner: *"I'd like to be able to have a 'free text' option for the Cards.
Ideally with multiple lines of different weights as the cards exist now."*

| | |
|---|---|
| macOS | ✅ four lines, each with a rank (Display / Heading / Body / Caption), in the Studio's Inputs column. Rendered by `StudioOverlayRenderer` at 1920x1080 and LOOKED AT (`build/qa/studio-overlay/card-custom*.png`) — empty lines dropped, one-line and four-line cards both optically centered, same wordmark and rule as the three fixed cards |
| iOS · tvOS · Android | ⏳ the ENGINE carries it on every Apple platform (`StudioOverlay.Card.custom` is in shared Swift, so the renderer draws it wherever it is set) and no surface on those platforms offers the editor yet. Android's `Card` is a separate Kotlin enum and does not have the case at all |
| Web | 🚫 no broadcast at all |

**A deliberate defer, not an oversight.** The editor is four text fields and
four pickers, which is a pointer-and-keyboard surface. On tvOS it would be
four focusable text fields behind an on-screen keyboard during a live show,
which is the kind of thing Rule 8.8c exists to refuse; on a phone it is
plausible and unasked-for. The owner asked for it on the Mac.

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
| **Watch Together — with the world** (Studio) | 🚧 player + overlays (tvOS-DESIGN §8.8): transport-menu entry, rights gate, ten-foot readout verified on the glass; Continuity Camera is the camera + mic (the mic is an `AVAudioSession` PORT, not a capture device). **GO LIVE EXISTS ON THE TELEVISION** (2026-09-18, Rules 8.8a + 8.8b): `GoLiveTV` is a focus-driven confirmation carrying the film, the destination, an EDITABLE title pre-filled from the audited catalog record, `unlisted` by default, and §3.4a's warning inline — so the old one-time "Before your first broadcast" alert is gone, because a television now HAS the informed moment iOS and macOS always had. `runStudio` resolves a real destination through the shared `StudioGoLive` instead of `destination: nil` (§9.ccc closed). Two columns because the first build put Go live below the fold on a screen with no scrollbar. Verified on an Apple TV 4K 3rd gen against two different films; the commit path is compiled and UNRUN until a host signs in | 🚧 player + overlays (iOS-DESIGN §8.8): go-live sheet, layout/faders/cards sheet, health capsule, all verified on an iPhone 12 | 🚧 Phase 2 (macOS-DESIGN §B13): the Studio is the player in a production mode, `StudioSession` owns the show because §B2a makes the player the window root, readout pinned outside the AVPlayerView HUD, control panel (layout/faders/cards) verified on the glass, camera entitlement + usage string added. **The whole program — film + camera tile + lower third — pulled back from a real publish by the SHIPPING app.** **Go Live exists on the Mac** (§9.mmm, Rule B13g approved 2026-09-18): a menu command opens the same form sheet as iOS §8.9, disabled with no film playing, and on commit resolves a real destination through the now-shared `StudioGoLive`. **THE MAC HAS NOW SIGNED IN AND THE STUDIO IS A REAL WINDOW** (2026-09-21, macOS-DESIGN **Part D**). This cell said the commit path was 'compiled and UNRUN until client ids exist'; the ids had existed since 09-18 and macOS could still not sign in, for two reasons found only by running the sheet on a Mac: `Info-macOS.plist` never declared `YOUTUBE_CLIENT_ID`/`TWITCH_CLIENT_ID` (nothing for the build setting to substitute into, so `info(...)` returned nil on every Mac build ever made) nor the OAuth redirect scheme, which is the bundle id; and once fixed, the callback TRAPPED — `ASWebAuthenticationSession` is not `NS_SWIFT_UI_ACTOR`, so its completion closure inherited main-actor isolation and macOS delivers it on an XPC reply queue (`{ @Sendable ... }` fixes it). Sign-in now completes. **§D6 is built out**: a `Window("Watch Together Studio")` with the PROGRAM PREVIEW fed from the engine's own `CVPixelBuffer` (§D5 — not a second composite, so what the host sees cannot diverge from what is sent); **device pickers** (§D2 — this Mac reports 4 cameras and 7 microphones that `AVCaptureDevice.default` was silently choosing between, §8.24); **output settings** (§D4 — size and frame rate locked while live because an RTMP ingest will not accept a change, bitrate live because the encoder does, §8.25); **a call's audio as a fourth input** (§D2/Decision 131 — `AudioHardwareCreateProcessTap` over a named app, a third mixer channel that ducks the film as the host's voice does, §8.26; what a SIGNED SANDBOXED app gets from TCC is NOT yet measured); **a preview that runs before going live**, which exposed that `isLive` never meant on-air — `isOnAir` and `isRehearsing` now say which is meant; and **a Watch Together sidebar section** whose landing page names the three modes, which is where Decision 131's rule finally lands **THE STUDIO IS NOW THE WHOLE SURFACE** (2026-09-22, macOS-DESIGN §D7-§D13, from the owner running the shipped build): a FILM CHOOSER inside the Studio (search the catalog, rights-refused titles SHOWN with their reason rather than hidden); the film's own player hosted in a **SOURCE** pane beside the **PROGRAM** preview, OBS's preview/program split (§D8), with "Open in a separate window" MOVING the film to the ordinary player window for projection (never copying it — two `AVPlayer`s on one film was the sixth defect); the whole go-live checklist moved out of Rule B13g's sheet and into the **Output** column (§D9), so the sheet is gone and ⇧⌘L and the player's toolbar button both open the Studio; **the camera is ASKED FOR** (§D11) — nothing in the macOS product path had ever called `requestAccess`, so `authorizationStatus` was `.notDetermined` for the life of the app and the camera row read "not attached" forever with nothing to press; **device pickers are live at all times** (§D11 replaces §D2's "next broadcast" sentence — the capture session is not the encoder, the tile is composited, and the wire never learns which device made the pixels); and closing the Studio window ends the show (§D12). | 🚫 a browser cannot speak RTMP; only a server-side compositor (Phase 4) can publish from the web | 🚧 Phase 3 — NO RootEncoder: our own `RtmpPublisher.kt` proved against a real server from the JVM **and two real devices** (Google TV API 34, Fire TV API 30); **the encode path too** — GLES into MediaCodec's input Surface (zero-copy), verified from the server's OWN RECORDING (1280×720 h264, the drawn green 0.35 decoding to 0.341). **and the FILM** — ExoPlayer→external OES texture→GLES aspect-fit, verified from the server's recording as a real 1916 intertitle. **and the whole COMPOSITE** — film + corner tile + lower third in one GLES pass, with the provenance line on screen. **the film's AUDIO** (TeeAudioProcessor → AAC) **and the ASSEMBLED engine** (ANDROID-DESIGN §9) — health reporting LIVE with the server's recording carrying both tracks **in the HARNESS**. On the PRODUCT path there was no audio track at all until 2026-09-18: `StudioController.audioTapFor` was called from nowhere, so every Android broadcast published video-only (mediamtx: `tracks: [H264]`) while the film's own 44.1 kHz AAC sat there unread. A Media3 audio processor is fixed at `ExoPlayer.Builder` time, so the only moment it can be installed is when the player is BUILT — never at go-live. Now wired on the product path and measured from the server: both tracks, mean **-19.7 dB** / peak **-3.7 dB** over 45 s (§9.mm). **A/V alignment measured and corrected IN THE HARNESS**: audio was 47 ms late (AAC priming, invisible to FLV), now +4.5–11 ms against Apple's 10 ms — but that harness fed the encoder directly, so both tracks shared a base. **On the PRODUCT path the two tracks are on unrelated clocks: first video PTS 20.000 s against first audio PTS 39.613 s, a +19.6 SECOND split** (macOS on the same instrument: 0 ms). Video is stamped from MediaCodec's Surface clock, audio from its own sample count; nothing gives them a common origin. Invisible until §9.mm put audio on the product path at all — a video-only stream cannot disagree with anything. **FIXED** (§9.qq): video was stamped by a FRAME COUNTER (`frame * 1s / fps`) so it advanced at the achieved render rate rather than real time — 10.5 fps on this dongle — while audio tracked real time; and the audio sample clock did not count PCM the codec refused, so drops became permanent lag. One `showStartNanos` now feeds both and the clock counts OFFERED bytes: **+19,613 ms → -720 ms over 100 s**, and the offset CLOSES across the run instead of opening. Residual drift measured at DURATION for the first time (§9.eee): a ten-minute Android soak drifted **-533 ms over 9.3 min** and the offset CLOSED (1,544 → 1,011 ms), i.e. sublinear and converging — so a feature-length film does not desynchronise by tens of seconds, which the short-run rate would have predicted. 12.5 fps held over the whole ten minutes. **Lip sync is now MEASURED and it is WRONG: audio leads video by ~0.7 s** (§9.ggg) — a flash-and-beep clip, simultaneous within 16 ms at source, came back with six consecutive offsets of -683 to -749 ms. Constant, not growing, which is why the timestamp analysis could not see it: both tracks were internally consistent while describing different moments. ITU tolerance for audio-leads is ~45 ms. **CORRECTED to -174 ms** (§9.iii): the tap runs 0.565 s ahead of playback because `TeeAudioProcessor` sits on the way INTO the audio sink, and the engine now adds THIS device's measured lead to the audio timestamps before a single frame is sent. 712 → 174 ms, against a predicted 147 ms residual. **Still out of tolerance** — ITU's audio-leads guidance is ~45 ms — and the remainder is the video path, stamped at RENDER time after its content was current. The dongle's 10.5 fps was mostly BOXING — both send paths built their FLV tag as `mutableListOf<Byte>() + data.toList()`, boxing every byte of a 50 kB keyframe on the render thread: video drain 16.5 → ~3 ms, audio 29.0 → ~6 ms, program **9-10 → 12-13 fps** (§9.rr). ~13 fps is the dongle's real composite+encode throughput at 720p — `eglSwapBuffers` blocks on the encoder's surface queue, proved by a pacing change that predicted 22 fps and delivered 13. The publish handshake no longer blocks the render thread (§9.ss): it runs on its own daemon thread and the loop adopts the finished publisher, so the publishing second went from `drain=2306.5`/fps=1 to no spike at all, steady state 12-15 fps and drift -315 ms / 117 s. The ~13 fps ceiling is EXPLAINED (§9.uu): this dongle has **no hardware H.264 encoder at all** (both AVC candidates are software; `Dongle R 4K` is a playback device), so the program is encoded on the CPU. The draw split also refutes §9.rr's guess — the encoder swap is ~1.5 ms a frame, the GL draw ~26 ms. The encoder is now chosen explicitly (hardware if the platform has one, `configure` as the test); on this dongle it correctly finds none. Whether the GL cost shrinks behind a real hardware encoder is UNTESTED and needs the Pixel 8a (owner item 8). The **~12 s** gap before the first published packet was MEASURED (§9.tt) and is the FILM, not the Studio: first film frame at 13.2 s / 9.7 s on two titles, with everything the Studio does after it — warm-up, avcC, AAC config, handshake — totalling **~1.0 s**. §6.2's 8-second audio deadline has never been reached (the config takes 70 ms). That makes it Decision 077's playback-latency question, not a Studio defect. Detail entry + rights refusal wired (§9.2), 7/7 on the decision — but its APPEARANCE is unverified: the bench has only televisions, which run the tv surfaces. §9.4 readout + §9.3 sheet built and SEEN on the Google TV (the PlayerScreen is shared). **Dual-surface render built**: the host sees the PROGRAM (film + lower third), verified on the Google TV. Render cost measured A/B on one device: the second pass is **+3.9 ms (within noise)** and a SINGLE pass already costs 37.4 ms against a 33.3 ms budget — the dongle is the bottleneck, not the architecture. Left: a phone-class measurement, a phone to look at, and a real camera | One shared `StudioEngine` + our own `RTMPPublisher` (no third-party encoder — Decision 127). **Android now sends H.264 MAIN, not Baseline** (§9.xx): the encoder asks for the best profile the chosen codec actually advertises (High → Main → Baseline). Asking for High had been inert — Android ignores a profile the encoder lacks, silently, and this dongle advertises no High at all — so the stream stayed Constrained Baseline while the code said otherwise. Verified in the stream: `profile=Main` at an accurate **level 4.1** (§9.zz — asking for a level over-declared 720p30 as 5.0; not asking lets the encoder pick honestly, which is what Apple's AutoLevel does), at the same 12-14 fps, so CABAC costs nothing here and improves the picture at the same bitrate. A phone's hardware encoder should take High and match Apple. **Encoder identity is now REPORTED, not assumed** (§9.vv): macOS measured `hwenc=true` on an M3 at 30 fps / 0 dropped, and the SDK documents VideoToolbox's hardware opt-in as true by default, so Apple never had Android's software-encoder defect. `Require…` is deliberately not set — a slow broadcast beats none. tvOS/iOS carry it in `StudioHealth` and print it on the readout in DEBUG, but have not been READ yet. **§9.ccc is CLOSED on Apple**: the credential path (token → platform API → stream key) was constructed only in `StudioPlayerContainer_iOS`; it now lives in the shared `StudioGoLive`, and iOS, macOS and tvOS all resolve a real destination through it. Both client ids are registered. **Android has TWITCH OAuth and a configured client id** (corrected 2026-09-20 — the previous claim of "no OAuth or platform client at all" was stale): `TwitchLive.kt` speaks helix and reads the ingest-PoP list, `StudioPlatformAuth` runs the device flow, `StudioSignIn.kt` shows twitch.tv/activate and the user code, and `awTwitchClientId` is set. What is missing is a SIGN-IN on the device — so Android still publishes only to the bench destination, for want of one approval rather than for want of code. YouTube on Android remains genuinely absent. One owner step remains for the television: a Google client of type "TVs and Limited Input devices", which is the ONE credential in this app carrying a secret (Decision 128's named cost, now paid deliberately). Binding rules in `docs/WATCH-TOGETHER.md` |
| Watch Together — a camera that dies mid-show | ✅ said out loud on the ten-foot readout, and RECOVERED. Measured 2026-09-19 — a Continuity camera ran a clean 30/s for ten seconds then stopped dead for eighty while every other number stayed healthy | ✅ warning 2026-09-20; recovery landed in `StudioSession`'s pump that afternoon and was INERT here until the evening — iOS does not run that pump (see below) | ✅ warning + recovery 2026-09-20 | 🚫 n/a | ✅ **added 2026-09-20** — `CameraStallRecovery.kt`, a port of the Swift rule with the same thresholds, called from `StudioController.pollHealth` (the loop Android actually runs). It had no guard because until that morning it had no CAMERA to stall; a phone's camera stops whenever a call arrives, so it needs this more than a television does. `StudioCameraStallTest` asserts the same 8 cases, three of them controls — **and it has FIRED ON HARDWARE**: another app was made to take the camera (what a phone call does; Android's camera is exclusive), the framework logged `onDisconnected`, the Studio logged `camera stopped at 585 frames — recovery attempt 1 of 3` and `recovery 1: re-attached`, and the tile came back in the server's own recording | `CameraStallRecovery` (`Studio/StudioCameraStall.swift`) is the SHARED rule: four dead ticks while attached, on air and having once delivered; three attempts a show; frames resuming reset the grace. It lived inside `Views/DetailView.swift` — the tvOS view — so it existed on ONE platform while this row said "no recovery yet" for the other two, and the same doc noted macOS can use an iPhone as its camera and therefore drops exactly as a television does. tvOS now calls the same rule, so the thresholds cannot drift from the ones §8.23 asserts (9 assertions, four of them controls: a camera that NEVER started, an off-air show, no camera at all, and a healthy one). The guard is still `cameraAttached && cameraFramesReceived > 0 && rate == 0`: the middle term matters, because between the attach and the first delivered frame a camera is legitimately attached at zero |
| Watch Together — the host in the show (camera + voice) | ✅ Continuity Camera + its microphone, both verified on the wire | ✅ the phone's own camera and microphone | ✅ camera and microphone, verified from the server's own recording | 🚫 n/a | 🚧 **BUILT 2026-09-20, UNPROVEN ON A DEVICE.** It was structurally absent that morning — the manifest declared only `INTERNET`, there was no `AudioRecord` anywhere, and the camera's receiving end existed with nothing to feed it. Now: `CAMERA` + `RECORD_AUDIO` in the **google** flavour only (verified by reading both merged manifests — Fire TV gets neither, having neither), `StudioCamera` on **Camera2** (no new dependency, Decision 127) choosing a size the sensor actually advertises and setting it on the texture, `StudioMicAudio` on `VOICE_COMMUNICATION` (the film plays from the same speakers the mic hears, so a raw `MIC` source feeds the film back on itself), both opened and released with the show, and the permissions asked for on the GO-LIVE dialog and nowhere else. **Nothing has run on hardware**: the Pixel's adb pairing is expired and no television has a camera or a microphone, so Camera2 opening, `AudioRecord` at the film's rate and the echo cancellation are all compile-time claims only | On phones this IS the feature — a watch-along without the host is a film. SCRATCHPAD item 8 listed "a real camera tile" as waiting on the Pixel 8a, i.e. as a TESTING gap; it is a BUILDING gap, and the pairing would not have shown a tile. Android's Studio is film-only until a capture source and two permissions exist |
| Watch Together — the mix controls | ✅ `StudioMixerTV`, reached from the Watch Together transport item while live (Rule 8.8c): two channels on a **0–10** scale with a tick per whole level and the unity tick at 8 drawn taller than the knob, adjusted by ROLLING the clickpad (`GCMicroGamepad.dpad` + `reportsAbsoluteDpadValues`, because `UIRotationGestureRecognizer` is `API_UNAVAILABLE(tvos)`); auto-duck toggle; play/pause pauses the film without ending the broadcast. Verified on the glass, Ben Bedroom | ✅ the same **0–10** scale and the same auto-duck toggle in `StudioControlsSheet` (2026-09-20). It was `Slider(value: gain, in: 0...1.5)` — a raw linear amplitude, no number, a +3.5 dB ceiling against the television's +6, and auto-duck stated as a fact rather than offered as a control. `Slider` stays, because it IS the native control here (`@available(tvOS, unavailable)` is why the television draws its own); only the scale and the readout changed | ✅ the same, in `StudioMacPanel` (2026-09-20). **`StudioSession.setAudio` had no `duckEnabled` parameter at all** — Rule 8.8c added it to `StudioEngine` and it stopped there, so every caller that goes through a session, i.e. macOS and iOS, could not reach it | 🚫 a browser cannot hold a stream key | 🚧 **BUILT 2026-09-20, UNPROVEN ON A DEVICE.** There was nothing to convert that morning — `grep` for gain, duck or mic returned nothing at all. Now `StudioAudioMix` carries the same **0–10** scale (`MixLevel` ported: 8 is unity, 0–8 cuts 5 dB a step, 8–10 boosts 3 dB to +6), the same auto-duck **toggle**, and meters on the fader's own scale; the panel draws them with Material's `Slider`, the native control here as on iOS and macOS. **It mixes INTO the film's own buffers and drives nothing** — the film tap stays the timeline, because a mixer on its own cadence is a second clock and §9.qq is what a second clock cost Android (video and audio 19.6 s apart). 12 unit tests with controls cover the gains, the duck, the clip and the mute; the CAPTURE is not covered and cannot be off a device | `MixLevel` is SHARED (`Studio/StudioAudio.swift`): 8 is unity, 0–8 cuts 5 dB a step to silence, 8–10 boosts 3 dB a step to +6. It lived inside `StudioMixerTV.swift` behind `#if os(tvOS)` for one afternoon — the same mistake §9.ccc found with the go-live request. **The meters read on the fader's own scale**, not linearly: a linear 0–1 meter draws 2% for speech at RMS 0.02 and looks dead |
| Watch Together — rights gate | ✅ refusal verified on the glass (Apple TV 4K) | ✅ both branches verified (iPhone 12) | ✅ refusal verified on the glass (macOS 27) — and it caught a STALE schema-1 cache unprompted, on a film the published DB marks `safe_pd_age` | 🚫 a browser cannot hold a stream key | ✅ ported to Kotlin, 8/8 unit tests + **the refusal verified on the glass (Google TV: His Girl Friday, 1940, `presumed_pd`)**; `rightsBucket` now rides the Android lite select behind a schema probe. **`tools/test_studio_rights_parity.py` proves Apple and Android say the IDENTICAL sentence for all 24 buckets**, negative-controlled | `StudioRights`, tier `guaranteed` = `safe_pd_age` only — **4,210 of 24,943 films** (16.9%). An unknown verdict REFUSES. Every bucket has a human sentence, guarded by `tools/test_studio_rights_coverage.py` |
| Watch Together — a dropped connection |  🚧 shared code; the END path is on the glass (the alert a host reads), the REBUILD itself has never been driven here — a tvOS bench destination hits the same Local Network gate as iOS (§9.dd) |  ✅ **DRIVEN ON AN iPHONE 12, 2026-09-20.** A severing proxy cut the link at 25 s and the phone rebuilt it in **0.7 s**, confirmed from BOTH sides: the app logged `socket closed (was publishing): NWError 54 — Connection reset by peer` then `publishing — the server accepted the stream`, and mediamtx logged `closed: EOF` at 19:29:35 with a new connection publishing at 19:29:36. Recordings: 24.4 s before the cut, 82.2 s after | ✅ shared code — §6.6 | 🚫 no RTMP from a browser at all | ✅ **proved ON THE GLASS** (Google TV, shipping app, severed link rebuilt — `conn 2: open`, server re-ingesting to 9.45 MB) — same schedule as Swift (1/2/4/8/15 s, 60 s deadline, one attempt at a time), RECONNECTING outranks OFFLINE. The supervisor is deliberately NOT on the render dispatcher: a 15 s backoff there would freeze the picture. Timestamps continue for free (they come from the encoders). Proved through the severing proxy with the SERVER as witness (`RtmpReconnectTest`): the path came ready again after the cut, control did not. No device run yet | §6.6: a severed link is reconnected on the shared `RTMPReconnectPolicy` schedule (1/2/4/8/15 s, 60 s deadline, matched to the ingests’ own grace windows), the new session restores transaction id 0 + chunk size 128 + the sequence headers and OPENS ON A KEYFRAME, the timestamp base is KEPT, and the readout says RECONNECTING. When the deadline expires the show ENDS rather than pretending. Proved on a real mediamtx through a severing proxy, asserted from the server’s own recording, with a no-reconnect control that dies at the cut (`tools/test_rtmp_reconnect.swift`, §9.x: 18.9 s vs the control’s 5.1 s, post-cut A/V 0.02 s). The ENGINE’s supervisor (backoff + deadline + the forced keyframe) is wired but not yet exercised on a device |
| Watch Together — thermal pressure |  ✅ `.critical` verified ON THE GLASS (the alert, Apple TV 4K 3rd gen) via the engine seam; the bitrate step is shared code, measured on the Mac |  🚧 shared code; never driven here (same Local Network gate) | ✅ shared code — §6.5 | 🚫 n/a | ✅ **proved ON THE GLASS through the real platform API** (Google TV: `cmd thermalservice override-status 3` → the wire drops 2604→**1462 kbps**, 44%; status 4 ends the show; §6.5 asks 40%) — `PowerManager` SEVERE(3) steps the bitrate via `PARAMETER_KEY_VIDEO_BITRATE`, CRITICAL(4)+ ends the show. Binds harder than Apple: the codec is CBR, so there is no `DataRateLimits` to get wrong. The decision is a pure function the loop calls (`StudioThermalTest` 6/6); the status is INJECTED, so the harness seam and the platform seam are the same one. No device run yet | §6.5, CORRECTED: `.serious` lowers the **bitrate** to 60% and says so; `.critical` calls `endShow`. It previously said "halve the RESOLUTION", which an RTMP ingest will not accept mid-publish (format parameters must not change during a stream) — and it was implemented nowhere, which is the only reason it never broke a broadcast. Enforced by `DataRateLimits` at 1.15×, not by `AverageBitRate` alone: at the old 2× cap a 40% step moved the wire 7%. Proved on the REAL engine against mediamtx (`tools/test_studio_thermal.swift`, §9.y: 2893 → 1959 kbps, resolution held) |
| Watch Together — a narrow uplink |  🚧 shared code, measured on the Mac product path; never driven on a television |  ✅ **DRIVEN ON AN iPHONE 12, 2026-09-20**, from the publisher's OWN counters: open — queued 0, 30 fps, 0 dropped; throttled to 200 kbps — queued 1.2-1.6 MB, video **1.8 fps**, 834 dropped, audio **unbroken at 43.8/s**; recovered — queued 0, 30 fps, drops frozen. The picture yields and the voice does not | ✅ **proved on the PRODUCT path** (Mac app at 6 Mbps throttled to 400 kbps: queue pinned at the 1.15 MB cap, video frozen, 492 dropped, audio +43/s unbroken) | 🚫 n/a | ✅ **ported** — writer thread + §6.4a budget; it mattered MORE here, since the old synchronous socket write BLOCKED the single render thread instead of shedding frames. Proved through the same throttling proxy (`RtmpBackPressureTest`): peak 476 kB against a 474 kB cap, 0 drops before / 64 during, **audio 425 of 425 delivered** | §6.4/§6.4a: past a **1.5-second** latency budget of the show’s own bitrate, VIDEO inter-frames yield until the next keyframe and AUDIO is never dropped — structurally, `send(audioFrame:)` has no drop path. The budget was a flat 2 MB, which at 2.5 Mbps is 6.4 s of delay and never once fired. Proved on the REAL engine through a throttling proxy (`tools/test_studio_backpressure.swift`, §9.z): at 400 kbps the queue crossed the cap only while throttled, video fell to **1 fps** and recovered to **30.1**, and audio held **43 frames in the worst congested second**. The same run found every broadcast opening with **59 dropped frames — two seconds blind** — because only the reconnect path asked for an opening keyframe; now both do |
| Watch Together — platform sign-in | ✅ **VERIFIED END TO END ON THE TELEVISION 2026-09-18.** YouTube: `ASWebAuthenticationSession` on tvOS presents Apple's OWN hand-off — "Sign in with Apple Device · You will get a notification on a nearby iPhone or iPad" — so the phone does the Google sign-in and approves the channel, and the token lands on the TV. Proved with the EXISTING `YOUTUBE_CLIENT_ID`: the host approved on their phone, the surface showed "Signed in to YouTube", and a read-only `channels.list` returned their own channel from the Apple TV. **No second Google client and no client secret** — an earlier claim that both were required was reasoning from docs, not measurement, and is withdrawn. Twitch: **a QR code and the host's phone** (owner direction 2026-09-18: *"you are logging in on the TV using that other device"*) — Twitch's device flow VERIFIED on an Apple TV 4K 3rd gen, QR + code on the glass, one press from the go-live surface. `GoogleDeviceAuth` is kept as a fallback for a platform with no such hand-off (Android TV later) and is selected only when a TV client is configured; our iOS client really is refused there (`invalid_client` / *"Invalid client type."*, measured), which is why that fallback needs its own registration if it is ever used. **The live gate now is Google's consent screen: it is in TESTING, so the host clicks through "Google hasn't verified this app" and refresh tokens expire in 7 days** (Google's own wording) — publishing + OAuth verification of the sensitive `…/auth/youtube` scope is a prerequisite for shipping the YouTube half | ✅ written + on the glass (iPhone 12): the unconfigured state renders, Go Live greys out | ⏳ same code, Phase 2 surface | 🔮 Phase 3 — the same two flows, AppAuth or hand-rolled | 🚫 a browser cannot hold a stream key | **Two DIFFERENT flows, because the platforms differ**: YouTube = authorization code + PKCE (S256); Twitch = the **Device Code Grant**, since Twitch offers a public client no PKCE and implicit returns no refresh token. Tokens in the Keychain. Redirect scheme is the BUNDLE ID, not the reversed client id (it must be in Info.plist at build time). Decision 128; `tools/test_studio_signin.swift` 26/26 incl. RFC 7636's own vector |
| Watch Together — your own stream key (Decision 136) | ⏳ not offered — a 40-character key typed on a Siri Remote is its own design question | 🚧 **BUILT v1.42.580**: "Sign in / Stream key" in the go-live sheet, a SecureField, "Find your stream key" to the platform page; resolved by the shared `StudioGoLive`; not yet seen on a device | 🚧 built in the Output column; not yet run with a real key | 🚫 a browser cannot speak RTMP | ⏳ not built | No sign-in, no API call, no shared quota — so no chat, viewer count or thumbnail. The key is held for the sheet only and never saved |
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
| Party Play (muted) | ✅ | 🔮 | ✅ `Modes_macOS` | ✅ Surprise → Party Play; muted lineup from the channel pools, never persisted | ✅ `TvPartyScreen` (TV) | ambient mode; Roku ✅ (Surprise door, whole-catalog color pool) |
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
| Channels (EPG) | ✅ focusable program blocks, tune-in by remote | ✅ | the EPG layout was already a ten-foot idiom; it needed focusability, not a rewrite |
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

##### Staging a card before it goes out, 2026-09-22 (macOS-DESIGN §D19)

A host prepares the intermission card while the film is still running, then
takes it. §D19 is the one place the Studio deliberately shows something the
audience cannot see, and it says so in the panel: **NEXT · not on air**.

| Platform | State |
|---|---|
| macOS | ✅ a "Prepare" picker and a NEXT thumbnail in the Studio's new **On screen** column, rendered through the program's OWN `StudioOverlayRenderer` at 640×360 so it cannot draw a card the engine would draw differently. "Show it now" is the only route to the audience and it clears the staging. §8.39 asserts structurally that `stagedCard` reaches the thumbnail and TAKE and nothing else — the wire proves one value at one moment, the source check proves there is no path at all |
| iOS · tvOS · Android | ⏳ not offered. Only a CARD is stageable by design (§D19's table: a placement, a film or a lower-third change would each need a second composite, which is §D5's whole objection), so this is a small port rather than a missing capability |

##### The Studio's fourth column, 2026-09-22 (macOS-DESIGN §D20)

The control row is **Inputs · Mixer · On screen · Output**. Found by
screenshotting the running Studio to verify §D19 and seeing the Inputs column
run off the bottom of the window at "Crop", with the card picker and the whole
NEXT panel below the fold while the Mixer column beside it was half empty. A
camera is a source; a lower third is a drawing — the line OBS draws between
Sources and the Audio Mixer.

| Platform | State |
|---|---|
| macOS | ✅ four columns, minimum width 1120; the framing legend is one sentence rather than a five-row table, which is the four rows by which NEXT had been falling off the screen |
| iOS · tvOS · Android | n/a — their Studio surfaces are sheets and menus, not columns |

##### When the film stops reaching the program, 2026-09-22 (macOS-DESIGN §D21)

| Platform | State |
|---|---|
| macOS | ✅ `StudioFilmStall.reason(_:)` names the cause under the film row after three silent seconds — no player, an item nilled by a rebuilt window, paused, buffering, an item error, or an honest "playing and no frames are arriving". §8.40 covers every branch AND the order, because a nilled item also reads as paused |
| iOS · tvOS · Android | ⏳ the readout shows the rate and says nothing about why. The reason is a pure function in shared Swift, so the two Apple ports are a call site each |

**Open, and not claimed as fixed**: the fault that prompted §D21 — the Mac's
program going black while the FILM pane plays — reproduced twice in eight
runs and has no signature. `AWSURFACE register` / `forget` / `engine
attaching` now carry the `AVPlayer`'s identity so the next occurrence names
itself.

##### Chat: whose, whether, where, and what is filtered — 2026-09-22 (macOS-DESIGN §D22, §D22a)

Owner, on seeing chat render for the first time: *"I don't see any controls for
the chat (turning it on or off, moving it on the screen, filtering, etc.).
Surely, that has to be a part of the feature, right?"* — and then, on seeing it
over a rehearsal: *"Shouldn't there be no chat on a stream that isn't going
anywhere...?"*

| Platform | State |
|---|---|
| macOS | ✅ **Show chat**, **Side** (Left/Right), **Hide bot commands**, **Hide links**, and a hide-these-people field, in the Studio's On screen column. The column draws ONLY while on air (§D22a). `StudioChatFilter` is a pure function — §8.43 covers every rule, the interactions, and the two over-matches that would eat real conversation (a mid-sentence `!`, a filename with a dot in it). §8.42 covers the column's geometry and caught a defect the hour it was written |
| iOS · tvOS | 🚧 the on-air gate and the host's-own-channel fix are in shared Swift, so both have them. Neither offers the CONTROLS yet — a sheet, not a column, so it is a design question rather than a port |
| Android | ⏳ no chat at all |

**Twitch chat had no product path until today.** All three Apple surfaces read
the channel from the `AW_STUDIO_CHAT` debug door and nowhere else, under a
comment saying it would come from the host's account "once sign-in exists" —
which it had, since 2026-09-18. It is now `StudioPlatformAuth.twitchAccount()`,
the same read the readiness gate already makes. YouTube was always correct: its
`liveChatId` comes back from the insert that created the broadcast.

**A chat message that could not be broken was drawn past its own pill**, seen
on air the same day: `wrap` split on spaces only, so a single unbroken token —
most of Twitch — was emitted whole and clipped mid-glyph, its tail sitting on
the film with no ground behind it. Fixed; §8.42 asserts it wraps. The first
version of that test PASSED with the defect reinstated and was thrown away.

##### The call's picture, 2026-09-22 (macOS-DESIGN §D23)

| Platform | State |
|---|---|
| macOS | ✅ capture AND the sixth arrangement. Capture MEASURED on the product path — `SCContentFilter(desktopIndependentWindow:)`, `start=true problem=none`, 82 frames in 4 s, no TCC prompt for a signed sandboxed app. No audio (the process tap owns sound), never our own window, no titles in diagnostics, no substring matching. **`StudioLayout.guests` — "Film, you, and your guests"** puts the call directly above the host's tile at the same width, derived from the host's rect so the two cannot drift apart; proved through the menu's own `startGuests` with `guestsAttached=true` read at the ENGINE and the tile seen in the composited frame. A guest tile is NOT framable and that is written down rather than implied (§D23). The source SURVIVES going live (§D23a) — which it did not at first: pressing Go Live builds a second engine and would have dropped the guests silently, with the picker still naming the window and the capture still running. This amends Rule 8.8e, which named five placements |
| everywhere else | 🚫 ScreenCaptureKit is macOS-only, which is the same reason Decision 131 makes the Mac the only host for this mode |

##### Framing the guests, and one call being one choice — 2026-09-23 (macOS-DESIGN §D24, §D25)

Owner: *"we need to be able to move and crop the 'guest window' in the same
way you can manipulate the camera for your own video. Additionally, the mixer
should have audio from the call to be able to determine the levels for the
other people talking on the call."*

| Platform | State |
|---|---|
| macOS | ✅ **§D24** the call's tile takes §D14's gestures in full — drag to move, corner to resize, edge to crop, scroll to zoom, ⌥-drag to pan — with a **Framing: You / Your guests** picker, because §D23 stacks the two tiles in one column and overlapping handles would make a drag ambiguous. One accessor (`activeFraming`) carries every gesture, so no gesture can drive the wrong tile. ✅ **§D25** choosing the window taps that call's audio too: the mixer gains a third fader with a live level, and the film ducks under it. Verified on the glass — the tile moved and reshaped, and `AWCALL app=Google Chrome level=0.5293` with the fader on screen |
| iOS · tvOS · Android | 🚫 no guest picture at all — ScreenCaptureKit is macOS-only (Decision 131) |

**This reverses §D23's "a guest tile is not framable"**, which argued a host
frames only themselves because a call window "is already a grid somebody
else's app arranged". The owner's correction is the better reading: Zoom and
Meet wrap the grid in chrome, so a call window needs cropping **more** than a
webcam, not less.

**And the audio match is by BUNDLE ID, not pid.** `StudioAudioProcesses`
groups an app's audio objects into one row keeping the lowest pid — which for
a browser is a HELPER, and a browser is where most calls happen. Matching on
the window's pid found nothing and produced faces with no voices; the prefix
test (`com.google.Chrome` against `com.google.Chrome.helper`, either way
round) is what actually works.

##### The audience can reach the screen — 2026-09-23 (macOS-DESIGN §D26, §D26a)

Owner: *"It must also be designed well and create genuine opportunities for
connection for all involved."*

Auditing against that sentence found the thing the feature list hides:
**everything the Studio could put on screen came from the host.** Chat
arrived and was *displayed*; nothing an audience member did could reach the
program, so a person watching had no evidence they were heard.

| Platform | State |
|---|---|
| macOS | ✅ an **AUDIENCE** pane beside FILM and STREAM — forty recent lines, post-filter, appearing when a broadcast does. **Show** (or a double-click) puts a message on the broadcast under its author's own name for twelve seconds; what is on air sits at the top of the pane with **Take down**, and clears itself. Verified on the glass through the product's own chain — clicked a row on a live bench broadcast, read the banner back out of the STREAM preview, watched it expire and the chat column return |
| iOS | ✅ **seen on the wire from an iPhone 12** (v1.42.515): the Show door pressed line 4 through `showShoutOut` and the server's frames carry `crazyspecz` / "my grandmother saw this in a theater in 1924" above the lower third, chat yielding, and gone after twelve seconds. As built in v1.42.512: an **Audience** section heads the controls sheet when there is a conversation — fifteen recent lines newest first, **Show** or "too long to show", what is on air with **Take down**. The container's own loop expires it (the macOS expiry lives in a pump iOS does not run) and every overlay push keeps it, where a fresh overlay used to take a viewer off the air whenever a control moved. The demo-conversation door feeds only the macOS session, so there is no bench path to it yet |
| tvOS | ⏳ the ENGINE carries it; no surface offers a list. Rule 8.8c ("two channels, a rotation, and nothing else") makes that an owner question, not a port |
| Android | 🚫 `StudioOverlayBitmap` has no shout-out and the Kotlin engine no chat reader |
| Web | 🚫 a browser cannot hold a stream key |

**A message too long to draw is SHOWN and REFUSED, never truncated** — the
row stays in the reader carrying "too long to show" and offers no button,
because cutting a stranger's sentence in half and putting their name under the
remainder is worse than declining to show it.

**And the name is drawn in the case its owner typed.** Every other uppercase
run in the overlay is a label we wrote; a handle is not ours to restyle. The
first build said `CRAZYSPECZ`, and §8.48's one assertion that cannot pass with
the defect reinstated is that two spellings render to different widths.

**Two cache keys were incomplete in the same morning.** The lower third's
named the title, year and provenance and not the shout-out, so a banner could
never appear and, once up, could never expire; the chat column's named its x
and WIDTH and not its height, so a column shortened to clear the banner was
drawn at its old size. **A cache key that names some of its inputs is a cache
that is wrong about the rest** — and neither is visible to a harness that
builds a fresh renderer per call, which §8.48 did until it was made to reuse
one.

##### Record the show to a file — 2026-09-23 (macOS-DESIGN §D35)

macOS ✅ Record… (Save panel, Movies) writes the program's own encoded samples to
an MP4 — no second encode. Proved: 30.8 s recorded from a bench show, ffprobe
reads H.264 1920×1080 (922 frames) + AAC 44.1 kHz (1327 packets), tracks aligned,
audio −31.7 dB mean, the frame is the program. **Limit**: going live builds a new
engine, so a recording started in rehearsal is saved at Go Live and the host
records again. iOS / tvOS 🚫 not built.

##### Rooms from the Studio, thumbnails, and no orphans — 2026-09-23 (macOS-DESIGN §D33, §D34)

| Feature | macOS | iOS · tvOS | Proof |
|---|---|---|---|
| On-air Output: "Live on …", as the account, the AUDIENCE link with Copy/Open, End (§D33) | ✅ | 🚫 not these surfaces | seen on a real unlisted YouTube show (`qbHX46p9X_U`) |
| Friends' room opened from the Studio (§D34) | ✅ | 🚫 hosting is macOS-only (SHAREPLAY §11.13) | LIVE Worker: room RWT2 held the Studio's film; 404 after the show ended; a quit now closes it too (B07S: 200 -> 404) |
| A friend follows the room | — | ✅ iPhone (the join path every platform shares) | iPhone 12 joined 1VGP: landed 0.26 s from the anchor, in step from +2 s (the seek now aims ahead) |
| YouTube thumbnail = a still of the show, never a card | ✅ | ✅ (engine -> session path) | i.ytimg.com serves The General with its lower third for `bsxZSp6Ydqc` |
| A never-live YouTube broadcast is deleted, not orphaned | ✅ | ✅ (iOS via its end(); tvOS on start failure) | forced start failure: `qY5p-Vcgq90 … deleted`; Upcoming gained nothing |
| Stream key never in a log (§5, §8.53) | ✅ | ✅ | the session's start line printed the full key until today |

##### The MAC STUDIO proved on YouTube AND Twitch, with a real viewer — 2026-09-23

The instrument that finally worked: the TEST iPhone 12 playing the stream in
Safari in the foreground (a hidden Chrome tab never loads media).

| Feature | YouTube (`Fl0YCSDtyqM`) | Twitch (licbhwilkoff) |
|---|---|---|
| "N watching" (§D27) | ✅ `concurrentViewers` present, read `1` every poll; the AUDIENCE header shows "👥 1 watching" on the glass | ✅ `viewer_count` read 0, then `1` once the phone's view registered |
| Chat | ✅ YouTube chat only — the Twitch-chat leak fix held (0 Twitch attaches) | ✅ the show's own channel |
| Scene switch + crossfade (§D31) | ✅ (5shlTXfHNUA) | ✅ Intermission, card up |
| Chapter marker (§D30) | n/a (YouTube has none) | ✅ `AWMARKER placed "Intermission"` — Twitch accepted it |
| End | ✅ marked complete | ✅ ended at 240 s |

Still unproved on a platform: Share the film in chat from the Mac BUTTON (the
door path is proved), and Twitch chat posting (needs a new scope).

##### The MAC STUDIO proved on YouTube — 2026-09-23, broadcast `5shlTXfHNUA` (Learning is Change, unlisted)

The owner, correctly: *"We are testing the full Watch Together studio that we've
built for the mac."* Run through the Mac Studio's own session and end path:
latency=low / DVR / recordFromStart / embed HELD; YouTube chat read; **Share the
film in chat** posted; a **scene switch mid-broadcast** (Discussion, side by
side) with the 0.4 s crossfade; **End** marked the broadcast complete after
240 s. "N watching" still read `absent` throughout — no counted viewer.
It also caught the Twitch-chat leak fixed in v1.42.522.

##### Proved on YouTube itself — 2026-09-23, broadcast `GYAQsLMDwho` (iPhone 12, Learning is Change, unlisted)

The owner: *"make sure anything we are adding can actually work on the systems
we are building for."* Run on the product path, read back from YouTube:

| Feature | On YouTube |
|---|---|
| `latencyPreference: low`, DVR, recordFromStart, embed | ✅ YouTube HOLDS `latency=low dvr=1 recordFromStart=1 embed=1` (read back with `liveBroadcasts.list`) |
| YouTube chat read on iOS (fixed v1.42.517 — only macOS read it before) | ✅ `[AWSTUDIOCHAT] reading YouTube live chat` |
| Share the film in chat (§D32) | ✅ posted, and on YouTube's own page under `@bhwilkoff`: "Now watching: The Man Who Laughs — 1928 · Paul Leni. Public domain, free to watch: https://archive.org/details/…" — the API; the macOS BUTTON is still unpressed on a real broadcast |
| End completes the broadcast (§8.49, iOS had never completed one) | ✅ `YouTube broadcast GYAQsLMDwho marked complete`; YouTube's page reads "Streamed live 3 minutes ago" |
| "N watching" (§D27) | ❌ **FAILED**: YouTube showed "1 watching now" for over a minute and the app logged no count. Every read now reports its result in DEBUG (v1.42.518). **The read itself is proved** against a live public stream from the same phone (Lofi Girl `nI725iVsyoQ`: `concurrentViewers` present, parsed as 791), so the failure is timing (YouTube's API count lagging its page) or the poller during our show — the next run's per-read log says which |

##### Share the film in chat — 2026-09-23 (macOS-DESIGN §D32)

macOS ⏳ built (v1.42.516): **Share the film in chat** heads the AUDIENCE pane
on a YouTube broadcast, posting one line — title, year, director, "public
domain, free to watch" and the archive.org link — under the host's name. The
message rule is tested (§8.52); **not yet posted to a real YouTube chat** (no
signed-in broadcast since it was built). Twitch 🚫 until `user:write:chat` is
granted (a new scope — every host re-consents). **iOS** ⏳ the button heads the
Audience section on a YouTube broadcast (v1.42.519); the call behind it is
PROVED on YouTube (GYAQsLMDwho), the button itself not yet pressed live.
tvOS 🚫 (Rule 8.8c).

##### Scenes — 2026-09-23 (macOS-DESIGN §D31)

| Platform | State |
|---|---|
| macOS | ⏳ phase 1 (v1.42.508): the scene bar above STREAM, ⌘1-⌘9 under Broadcast ▸ Scenes, five editable starters, add / rename / delete, the two toggles in Scene settings, saved across launches, a Twitch chapter per switch. **Verified**: a switch to Intermission reached the wire (the server's frame is the card) and the selection survived a relaunch. **The toggles are verified** in the running app by `AW_STUDIO_SCENE_SELFTEST=1` (8 checks through the real controls; its negative control — capture ignoring the audio toggle — fails 4), and the Mixer column and Framing label say "shared" or "this scene" (v1.42.509). **Crossfade** (v1.42.510): 0.4 s `CIDissolveTransition` from a COPIED last frame, held until the scene's changes land; measured on the wire as a smooth YAVG ramp 35.2 → 27.6 over ~9 frames with no leading step. Scene settings ▸ Crossfade between scenes turns it off |
| macOS | ✅ Pause the film from the keyboard (v1.42.535, §D36): Broadcast ▸ Pause the Film / Play the Film, ⇧⌘Space; the friends' room pauses with it — verified from the live Worker (paused:true, then false, position held). iOS/tvOS: the player's own transport, no Studio key |
| macOS · iOS · tvOS | ✅ YouTube chat is read only when the host turns on "Show chat from YouTube" (v1.42.547, Decision 136) — off by default, remembered; Twitch chat is free and ungated. Android has no YouTube |
| iOS | ⏳ later, as a compact switcher |
| tvOS | 🚫 Rule 8.8c ("two channels, a rotation, and nothing else") |
| Android | 🚫 not planned |

##### A card is a chapter on the Twitch replay — 2026-09-23 (macOS-DESIGN §D30)

macOS · iOS · tvOS ⏳ built on the shared path (`StudioEngine.setOverlay`), the
mapping tested (§8.51); not yet placed against a real Twitch channel. YouTube
🚫 (no chapter API for live). Android 🚫 (no card-to-marker hook).

##### The STREAM header is the host's status bar — 2026-09-23 (macOS-DESIGN §D28)

macOS ✅ "● LIVE 1:11 · 2.4 Mbps" (+ dropped / reconnecting when true), verified
on a bench broadcast. The values (`onAirSince`, `sendingBitsPerSecond`) live
on the shared `StudioSession`, which only macOS drives (Decision 133) — iOS
and tvOS have their own readouts and do not show elapsed time. ⏳

##### The host knows how many people are watching — 2026-09-23 (macOS-DESIGN §D27)

| Platform | State |
|---|---|
| macOS | ✅ "N watching" in the AUDIENCE pane header, from the platform's own count, every 30 s. Built on all three Apple targets; **not yet read against a live broadcast** — the Debug build was signed out of both platforms when it was checked |
| iOS · tvOS | ✅ built (v1.42.506): the phone's live capsule shows 👥 N (VoiceOver: "N watching"); the television's readout shows "N watching" beside the bitrate. Same caveat as macOS — never yet read from a live platform |
| Android | 🚫 no poller |
| Web | 🚫 a browser cannot host |

YouTube broadcasts are created at `latencyPreference: low` on every Apple
platform (one shared `YouTubeLive.prepare`). Android does not create YouTube
broadcasts.

