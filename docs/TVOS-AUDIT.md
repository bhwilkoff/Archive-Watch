# tvOS Feature, Screen & Interface-Element Audit — 2026-08

Owner directive: *"fully test each feature and screen … all buttons and filters
… write a full feature, interface element, and screen audit document and
systematically go through them … fix any issues you find in design, feature
completion/functionality, and parity."*

This is the audit's **living ledger**. Every row gets a disposition before the
audit is done; PENDING rows are the loop's queue. Updated per iteration.

## Method

The paired **Bedroom Apple TV** (AppleTV14,1, tvOS 27) is the oracle:

    xcodebuild … -destination 'generic/platform=tvOS' -configuration Debug build
    xcrun devicectl device install app --device C3FBA9DE-… <app>
    xcrun devicectl device process launch --console --terminate-existing \
      -e '{…env…}' --device C3FBA9DE-… app.archivewatch.tvos

Verification tiers, in order of strength — every row is tagged with the tier
that dispositioned it:

- **T1 device** — behaviour observed via the device console (env hooks:
  `AW_START_TAB`, `AW_START_ITEM`, `AW_AUTOPLAY`, `AW_START_MODE`,
  `AW_CAPTION_DIAG`, `AW_CAPTION_TRACE`, and the functional audit harness
  `AW_UI_AUDIT` this audit adds).
- **T2 code** — wiring verified by reading: the action a control invokes
  exists, mutates real state, and that state is consumed somewhere.
- **T3 owner** — needs human eyes on the panel (focus feel, animation,
  rendering) — collected into a short checklist at the bottom rather than
  blocking the loop.

Existing automated checks that stay in force: `LayoutCheck` (UIAudit.swift,
DEBUG launch — typography/truncation), Caption Diagnostics (Settings),
`tools/test_*` harnesses.

## Screen inventory (12 tabs + modal surfaces)

### 1. Home (`HomeView` + shelves)
| Element | Behaviour to verify | Tier | Status |
|---|---|---|---|
| Hero carousel | populates; Left/Right cycles; Select → Detail; initial focus claimed | T1+T3 | PENDING |
| Shuffle button → Surprise grid | routes | T1 | PENDING |
| Continue Watching shelf | shows in-progress items w/ resume; Select resumes | T1 | PENDING |
| Category tiles (≥30-item gate) | each routes to filtered grid; counts sane | T1 | PENDING |
| Decade tiles (last row) | each routes; decade filter applied | T1 | PENDING |
| Curated/dynamic shelves | populated, playability-gated (D056), no cross-shelf repeats | T1 | PENDING |
| Top Rated shelf | populated, votes-floored | T1 | PENDING |
| Hidden Gems shelf | populated (D050 computed column) | T1 | PENDING |
| Director shelves | populated; person routing | T1 | PENDING |
| Community shelves (Watching Now / Favorites / Most Discussed) | populated, vote-floored | T1 | PENDING |

### 2. Movies (`BrowseView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Grid + infinite scroll | pages at 300/page; real total shown | T1 | PENDING |
| Facet chips: Type | each value filters; count updates | T1 | PENDING |
| Facet chips: Decade | each value filters | T1 | PENDING |
| Facet chips: Length | each value filters | T1 | PENDING |
| Sort menu (Popular / Top Rated / …) | each sort reorders; rating sort votes-floored | T1 | PENDING |
| Color/B&W filter (if surfaced) | filters by colorMode | T2 | PENDING |
| "Shuffle again" button | re-rolls | T2 | PENDING |
| Card Select → Detail | routes | T1 | PENDING |

### 3. TV Shows (`TVShowsView` → `SeriesDetailView` → `EpisodePlayerScreen`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Series grid (poster-gated) | populated; SNL demoted last (D: deprioritizedSeries) | T1 | PENDING |
| TV Specials entry | grid populated, only explicit tv-special | T1 | PENDING |
| Series sort | rating + episode-depth order | T2 | PENDING |
| Season picker | switches seasons | T1+T3 | VERIFIED T2 (seasonPicker → episode list; feel = T3) |
| Episode row Select | plays episode | T1 | VERIFIED T2 (fullScreenCover → EpisodePlayerScreen(series:initialEpisode:)) |
| Prev/Next episode in player | advances; binge auto-advance | T1 | PENDING |
| Episode context menu (favorite/playlist/share) | actions fire (D045 episodes-as-items) | T2 | VERIFIED (contextMenu → toggleFavorite / AddToPlaylistSheet / ShareSheet, all by episode archiveID) |
| Series/episode Share | archivewatch.org/series/{slug} QR | T2 | VERIFIED (ShareSheet sheets wired; URL contract verified 2026-06-10 session) |

### 4. Channels (`ChannelsView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| EPG guide renders | proportional blocks, ruler, now-line | T3 | PENDING |
| Channel rail Select | full-day schedule | T1+T3 | PENDING |
| Tune-in | joins in progress (startAt), commercials woven | T1 | PENDING |
| "Back" button | returns | T2 | PENDING |
| Create Channel form | creates; persists; appears in rail | T1 | PENDING |
| Delete user channel | removes + tombstone sync | T2 | PENDING |
| Channel playback never pollutes Continue Watching | persistProgress=false | T2 | **FIXED** (#2 — the gate had been lost; lineups persisted every 5s) |
| Commercial break length cap (Settings) | honored | T2 | VERIFIED (forwardPlaybackEndTime in setupPlayer) |

### 5. Cartoons / Kids mode (`KidsModeView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Character/theme shelves | populated, kid-safe pool, color-leaning | T1 | PENDING |
| Marathon | lineup plays, advances | T1 | PENDING |
| Group NavigationLinks | route | T1 | PENDING |

### 6. Party Play (`ImmersiveModePages`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Party pool starts; mute toggle persists across advances | | T1+T3 | PENDING |
| No B&W in party pool (D025) | | T2 | VERIFIED (partyLineup drops isSilentFilm + isBlackAndWhite; ≤15min; visual-scored) |

### 7. Screensaver (`ScreensaverView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Opt-in; idle trigger; never over playback | | T2+T3 | VERIFIED T2 (screensaverIdleEnabled + !isPlayingVideo + scenePhase gate; reset on tab/playback) |
| Exit on any press | | T3 | PENDING |

### 8. Collections (`CollectionsView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Curated collections only (no fav-*) | | T1 | PENDING |
| Collection Select → shelf/grid | populated | T1 | PENDING |

### 9. Search (`SearchView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| FTS results (keyboard + dictation) | relevant, includes episodes, excludes tv-special | T1 | PENDING |
| Type/decade filters over results | only present facets offered; ✕ clears | T1 | PENDING |
| Result Select → Detail / SeriesDetail | routes by type | T1 | PENDING |

### 10. Library (`FavoritesView` + `PlaylistViews`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Favorites grid | add/remove reflects; syncs (AWSync) | T1 | PENDING |
| Watched list | populated from completions | T1 | PENDING |
| Playlists: create / add / remove / delete | persist; tile spacing (no focus overlap) | T1+T3 | PENDING |
| Playlist playback | plays sequence | T1 | PENDING |

### 11. Surprise (`SurpriseView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| 11 re-rollable tiles | each re-rolls; each routes correctly | T1 | PENDING |
| Random Film | playable item only, ≤3 re-rolls on failure (D014) | T1 | PENDING |
| Random Category / Collection | land on filtered views | T1 | PENDING |
| Siri App Intents | IntentInbox routes | T2 | VERIFIED — shipped set is SurpriseMe / RandomFilm / RandomCategory (RandomCollection was the D014-era plan, superseded; the Surprise grid carries collection randomness) |

### 12. Settings (`SettingsView` + `SubtitleAccountSection` + `CaptionDiagnosticsView`)
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Sign in with Apple | flow works; sync status shows | T3 | PENDING |
| Sync Now | fires; Last sync updates | T2 | VERIFIED (Button → CloudKitSyncService.sync; status @Observable) |
| Sign Out / Delete Account (+ Cancel) | confirm flow; tombstones | T2 | VERIFIED (signOut(); Delete behind destructive confirm) |
| OpenSubtitles username/password + Connect | validates; quota shown; errors visible | T2 | PENDING |
| OpenSubtitles "Create a free account" | **was a no-op Link (no browser)** | T1 | **FIXED → QR** (this audit, #1) |
| Caption Diagnostics | runs; results persist; hardware line | T1 | **VERIFIED** (889/890 work) |
| Visibility toggles (per-category) | hide everywhere; Home reacts | T1 | PENDING |
| Hide-watched toggle | Home excludes completed | T2 | PENDING |
| Mature toggle (D012) | default off; flips visibleItems | T1 | PENDING |
| Autoplay mode default | consumed by player | T2 | VERIFIED (sessionMode ?? store.autoplayMode at menu + end-observer) |
| Commercial break cap | consumed by Channels | T2 | VERIFIED (commercialBreakMaxSeconds → forwardPlaybackEndTime) |
| Screensaver opt-in | consumed by idle timer | T2 | PENDING |
| Attribution (TMDb verbatim, D007) + About + version | present | T2 | PENDING |
| Donate QR (D010) | renders; bottom scroll anchor works | T3 | PENDING |

### Cross-cutting surfaces
| Element | Behaviour | Tier | Status |
|---|---|---|---|
| Detail: Play / Favorite / Share / Get subtitles / More Like This / cast chips / "Part of series" | each fires | T1+T2 | VERIFIED T2 (favorite→SwiftData+tombstone sync; cast chips→BrowseFilter(person:); MoreLikeThis→dbRelated; Part-of-series link; Share/GetSubtitles sheets; Play exercised T1 this session) |
| Detail: autoplay menu / Play Next / mute toggle in transport | | T2 | PENDING |
| Player: resume, watchdog (60s), stall fallback, captions tiers | | T1 | **VERIFIED** (this session) |
| Deep links: archivewatch://item /play /random/* | route (incl. play → resume, D049) | T1 | PENDING |
| Top Shelf: rotation + Continue Watching + play action | | T2 | VERIFIED (D049 harness) |
| Sidebar: tab switch resets NavigationPath | | T2 | VERIFIED (tabSelection binding resets outgoing AND incoming paths) |
| Universal empty/error/loading states per screen | user-visible, not console-only | T2 | VERIFIED (sampled: root LoadErrorView + loading; Browse EmptyState; Search placeholder+EmptyState; Favorites emptyState w/ focusable CTA; SeriesDetail loadError view) |

## Fix log

| # | Screen | Issue | Class | Fix | Build |
|---|---|---|---|---|---|
| 1 | Settings | OpenSubtitles "Create a free account" was a SwiftUI `Link` — on tvOS it renders as a focusable button that does nothing (no browser). Owner-reported. | Design/dead control | Replaced with a sign-up QR + instruction on tvOS (donate-QR precedent, D010); `Link` kept on iOS/macOS. Repo-wide sweep found no other `Link`/`openURL` on tvOS. | 891 |
| 2 | Channels/Party/Cartoons | Lineup playback persisted WatchProgress every 5s — the "channels never pollute Continue Watching" invariant (Channels EPG design) had been silently lost. Half-watched channel programs entered Continue Watching and SYNCED across devices. | Functionality regression | `persistProgress` now gates on `lineup == nil`; autoplay of single films still persists (normal viewing). | 891 |

## Owner-visual checklist (T3, collected — not blocking)

- Hero carousel focus feel; Left-edge → sidebar behaviour
- Channels EPG rendering (blocks proportional, now-line placement)
- Playlist tile focus spacing
- Donate QR bottom-anchor scroll
- Screensaver idle trigger + exit
- Sign in with Apple end-to-end

## Loop state

- Iteration 1: document created; fix #1 (OpenSubtitles QR); `Link` sweep clean.
- Iteration 2: **functional audit harness shipped** (`FunctionalAudit.swift`,
  `AW_UI_AUDIT=1` — ~40 checks: every Home shelf gate, every Browse facet +
  all 5 sorts + paging + TV-leak guard, TV/search/collections/surprise spines,
  Settings toggle CONSUMPTION with restore, deep-link parsing incl. the
  id-less-URL regression). Device run blocked once: the Apple TV was ASLEEP
  ("foreground app launch forbidden") and devicectl has no wake verb — retry
  next iteration. Discovered `devicectl device capture screenshot` works
  (3840×2160) — visual T1 evidence is now available to the audit. Fix #2
  (lineup progress pollution). T2 rows dispositioned: nav-path reset,
  screensaver gating, autoplay + commercial-cap consumption.
- Iteration 3: TV still asleep (launch probes denied) — T2 sweep instead.
  Dispositioned 10 rows: Detail buttons, SeriesDetail (picker/episodes/context
  menu/share), Siri intents (shipped set = SurpriseMe/RandomFilm/
  RandomCategory — RandomCollection superseded), Party B&W rule, Sync/Sign-out
  wiring, and the universal-states sample (root/Browse/Search/Favorites/
  SeriesDetail all have real empty/error surfaces — the old "loadError never
  surfaced" v1 gap is long closed by LoadErrorView).
- Next: the AW_UI_AUDIT device run (first launch attempt each iteration),
  T1 disposition of Home/Browse/facet rows from its output; remaining T2:
  series sort, TV Specials entry, Channels create/delete, kids pool.
