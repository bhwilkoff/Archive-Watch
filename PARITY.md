# Archive Watch — Cross-Platform Feature Parity

> **Single source of truth** for what ships where. Updated in the SAME change set
> as any user-facing feature. Companion to `CLAUDE.md`, `SCRATCHPAD.md`,
> `DECISIONS.md`, and the full strategy in `docs/MULTIPLATFORM-PLAN.md`.
>
> Per-platform binding design docs (create when each platform's UI complexity
> warrants): `docs/tvOS-DESIGN.md` (exists), `docs/iOS-DESIGN.md`,
> `docs/WEB-DESIGN.md`, `docs/ANDROID-DESIGN.md`.

## Legend
- ✅ **Shipped** · 🚧 **In progress** · ⏳ **Planned (committed)** · 🔮 **Future (agreed, no date)** · 🚫 **Out of scope (with reason)** · n/a **platform-inapplicable**

## Parity rule
**Same verb, native idiom.** The feature (the verb) is identical across platforms;
the *idiom* is whatever is native — `.searchable` on iOS, `SearchBar` on Android,
`<input type=search>`+URL on web, the focus-driven `.searchable` on tvOS. Update
this table in the same change set; cross-link the platform design doc.

---

## 1. Navigation shell

| Verb | tvOS | iOS | Web | Android | Notes (native idiom) |
|---|---|---|---|---|---|
| Top-level nav | ✅ `TabView(.sidebarAdaptable)` | ⏳ `TabView` bottom bar (iPhone) / `NavigationSplitView` sidebar (iPad) | ⏳ responsive top/side nav + URL routes | ⏳ `NavigationSuiteScaffold` (bottom bar→nav rail→drawer by window size) | Same destinations; idiom differs per form factor |
| Per-tab back stack | ✅ `NavigationStack` ×tab | ⏳ `NavigationStack` ×tab + swipe-back | ⏳ History API + View Transitions | ⏳ Compose `NavHost` + predictive back | |
| Deep-linkable surfaces | ✅ `archivewatch://` | ⏳ Universal Links + scheme | ✅ canonical URLs (the web superpower) | ⏳ App Links + scheme | Web makes every surface a shareable URL |

## 2. Discover — Home

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Hero / featured banner | ✅ focus carousel | ⏳ paged `TabView` carousel (touch swipe) | ⏳ scroll-snap carousel | ⏳ `HorizontalPager` | Same pool/logic; 10-foot sizing → touch sizing |
| Curated + dynamic shelves | ✅ | ⏳ horizontal `ScrollView` rows | ⏳ horizontal scroll rows | ⏳ `LazyRow`s | `featured.json` shared verbatim |
| Category tiles | ✅ | ⏳ | ⏳ | ⏳ | accent colors from `featured.json` |
| Decade tiles | ✅ | ⏳ | ⏳ | ⏳ | |
| Hidden Gems shelf | ✅ | ⏳ | ⏳ | ⏳ | shared query |
| Director shelves | ✅ | ⏳ | ⏳ | ⏳ | shared query |
| Continue Watching | ✅ | ⏳ | ⏳ | ⏳ | progress store (see §6) |
| Modes row | ✅ | ⏳ | ⏳ | ⏳ | links to §5 |
| Public Domain Day section | ✅ | ⏳ | ⏳ | ⏳ | seasonal, shared |

## 3. Discover — Movies / TV / Collections / Search

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Movies grid + facets + sort | ✅ | ⏳ `LazyVGrid` + `searchScopes`/`Menu` | ⏳ CSS grid + `<button>` chips + URL params | ⏳ `LazyVerticalGrid` + `FilterChip` + `DropdownMenu` | shared `CatalogDB.browse` |
| Infinite scroll / paging | ✅ | ⏳ `.onAppear` paging | ⏳ IntersectionObserver | ⏳ paging on scroll | |
| TV series → season → episode | ✅ | ⏳ | ⏳ | ⏳ | `series/*.json` shared |
| Prev/next episode in player | ✅ | ⏳ | ⏳ | ⏳ | |
| Collections landing + blurbs | ✅ | ⏳ | ⏳ | ⏳ | `collection_metadata.json` shared |
| Full-text search (FTS5) | ✅ | ⏳ `.searchable` | ⏳ `sql.js-httpvfs` FTS5 over range requests | ⏳ `SearchBar` | same FTS5 index in `catalog.sqlite` |

## 4. Detail + Playback

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Detail (backdrop, metadata, cast) | ✅ | ⏳ `.zoom` hero transition | ⏳ View Transitions | ⏳ `sharedBounds` hero | shared item record |
| More Like This | ✅ | ⏳ | ⏳ | ⏳ | shared `related` query |
| Video playback | ✅ AVPlayerVC | ⏳ AVPlayerVC (reused) | ⏳ HTML5 `<video>` | ⏳ Media3 `PlayerView` | |
| Resilient streaming | ✅ `ResilientStreamLoader` | ✅ reuse Swift loader | ⏳ range-native + reconnect wrapper | ⏳ `ResolvingDataSource` + `LoadErrorHandlingPolicy` | Archive idle-reset resilience per platform |
| Resume across launches | ✅ | ⏳ | ⏳ | ⏳ | progress store (§6) |
| Subtitles / audio / speed | ✅ | ⏳ native AVKit | ⏳ `<track>` + rate control | ⏳ Media3 track selector | |
| Autoplay / continuous play | ✅ F4 engine | ⏳ port engine | ⏳ port engine (JS) | ⏳ Media3 playlist | F4 queue logic ported per platform |
| Picture-in-Picture | n/a | ⏳ AVKit PiP | ⏳ `requestPictureInPicture()` | ⏳ Media3 PiP | new affordance on mobile/web |
| Cast / AirPlay | ✅ AirPlay | ⏳ AirPlay | ⏳ Remote Playback API | ⏳ Google Cast | each platform's native cast |

## 5. Surprise + Immersive modes

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Surprise / random actions | ✅ | ⏳ | ⏳ | ⏳ | shared random queries |
| Channels (EPG guide) | ✅ proportional grid | ⏳ touch guide | ⏳ CSS-grid guide | ⏳ Compose lazy guide | `ChannelScheduler` (date-seeded) shared |
| Create / user channels | ✅ | ⏳ | ⏳ | ⏳ | filter spec shared |
| Cartoon / Kids mode | ✅ | ⏳ | ⏳ | ⏳ | color/B&W flags shared |
| Party Play (muted) | ✅ | 🔮 (iPad-leaning) | ⏳ | 🔮 (tablet-leaning) | ambient mode; phone de-emphasized |
| Cover-art screensaver | ✅ + idle trigger | 🔮 ambient (iPad) | ⏳ ambient (desktop) | 🔮 ambient (tablet) | idle auto-trigger is a 10-foot/lean-back idiom |
| VHS effect overlay | ✅ Metal | 🔮 Metal (reuse) | 🔮 WebGL/CSS | 🔮 AGSL `RenderEffect` | optional polish; per-platform shader |

## 6. Personalization + sync

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Favorites | ✅ | ⏳ | ⏳ | ⏳ | local store per platform |
| Playlists | ✅ | ⏳ | ⏳ | ⏳ | |
| Watched / hide-watched | ✅ | ⏳ | ⏳ | ⏳ | |
| Continue Watching progress | ✅ | ⏳ | ⏳ | ⏳ | |
| Local persistence | ✅ SwiftData | ⏳ SwiftData (reuse) | ⏳ IndexedDB | ⏳ Room + DataStore | |
| Cross-device sync (Apple) | ✅ CloudKit | ⏳ CloudKit (reuse → syncs WITH the Apple TV) | n/a | n/a | iOS+tvOS share one iCloud DB for free |
| Cross-ecosystem sync (all 4) | 🔮 | 🔮 | 🔮 | 🔮 | needs a neutral backend — **open decision**, see plan §6 |

## 7. Settings + account

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Mature-content filter (default ON) | ✅ | ⏳ | ⏳ | ⏳ | `isAdult` flag baked into catalog (Decision 012/adult pass) |
| Category visibility toggles | ✅ | ⏳ | ⏳ | ⏳ | |
| Autoplay/playback options | ✅ | ⏳ | ⏳ | ⏳ | |
| TMDb attribution (required) | ✅ | ⏳ | ⏳ | ⏳ | Decision 007 — verbatim notice all platforms |
| Donate to Internet Archive | ✅ | ⏳ | ⏳ | ⏳ | Decision 010 |
| Sign-in (sync gate) | ✅ Sign in w/ Apple | ⏳ Sign in w/ Apple | 🔮 email/OAuth | 🔮 Sign in w/ Google | only gates sync; browse/play always work |
| Account deletion | ✅ | ⏳ | 🔮 | 🔮 | App/Play review requirement |

## 8. Platform reach + integration

| Feature | tvOS | iOS | Web | Android | Notes |
|---|---|---|---|---|---|
| Home-screen surface | ✅ Top Shelf | ⏳ WidgetKit widgets | 🚫 (PWA shortcuts only) | ⏳ home-screen widgets | "Continue Watching / Editor's Picks / What's New" |
| Voice / shortcuts | ✅ App Intents + Siri | ⏳ App Intents + Siri | n/a | ⏳ App Actions + App Shortcuts | "surprise me", "random animation" |
| Spotlight / system search | n/a | 🔮 Core Spotlight | n/a | 🔮 App Search | |
| Installable app | App Store | App Store | ⏳ **PWA (installable, offline)** | Play Store | web = zero-install reach |
| Handoff / continuity | 🔮 | 🔮 | n/a | n/a | NSUserActivity already declared |

## 9. Shared backend / data plane (consumed by ALL clients — no per-platform copy)

| Service / asset | Purpose | Where | Consumed by |
|---|---|---|---|
| `catalog.sqlite.zz` (+ `seed.sqlite`) | full catalog + FTS5, query-on-disk | GitHub Release (rolling) | tvOS, iOS, Android (download+inflate); web (range-query in place) |
| `catalog.json` | editorial source of truth | GitHub Release | pipeline only |
| `catalog-index.json` | slim search index | GitHub Pages | web fallback / public tool |
| `featured.json` | shelves, categories, accent colors, adult deny-list | git + Pages | all clients |
| `series/*.json` | TVmaze canonical episode spines | git + Pages | all clients |
| `collection_metadata.json` | curated collections + blurbs | git | all clients |
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
