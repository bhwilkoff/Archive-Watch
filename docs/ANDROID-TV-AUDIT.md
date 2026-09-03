# Android TV / Google TV — Full Screen, Button & Interface-Element Audit — 2026-09

Owner directive: *"I don't believe we have done a full audit of every screen,
button, and interface element. Please write up a full audit for Android TV and
test each component to be sure that it works as intended."*

This is the audit's **living ledger**, patterned on `docs/TVOS-AUDIT.md` (the
44/44 on-device pass) and continuing `docs/ANDROID-TV-PARITY.md` (which
measured PARITY — this one measures every ELEMENT, one row per control).

## Method

Two real devices, no emulator (owner's standing rule):

| Device | Flavor | Package | adb |
|---|---|---|---|
| Google TV Streamer (SEI Dongle_R_4K, Android 14) | `google` | `com.archivewatch.app.debug` | `10.0.0.55:5555` |
| Fire TV Stick 4K (AFTKRT, Fire OS) | `amazon` (zero GMS) | same | `10.0.0.139:5555` |

    ./gradlew :app:assembleGoogleDebug      # or :app:assembleAmazonDebug
    adb -s 10.0.0.55:5555 install -r android/app/build/outputs/apk/google/debug/app-google-debug.apk
    python3 tools/gtv_scenario.py launch --es aw_start_tab browse
    python3 tools/gtv_scenario.py go "Play" ; python3 tools/gtv_scenario.py select "Play"
    AW_TV_HOST=10.0.0.139 python3 tools/gtv_scenario.py rail_walk    # Fire TV

Evidence channels, all EXTERNAL to the app:

- **focus tree** (`uiautomator dump`) + **AWFOCUS logcat trace**
  (`--ez aw_focus_log true`) — the only proof a control is REACHABLE. A
  screenshot proves rendering and nothing else.
- **screenshots + OCR** (`/tmp/awocr`) — the only channel for Compose
  overlays, which are ABSENT from the uiautomator tree.
- **logcat** (`AWTV`, `AWHOME`, decoder frames, `dumpsys audio`).

Tiers, as in TVOS-AUDIT: **T1 device** (observed on the glass) · **T2 code**
(wiring read end-to-end) · **T3 owner** (feel/visual). A row that could not be
exercised is **SKIP with the reason** — never PASS.

Instrument facts already paid for (do not re-derive):

- `input tap` is INERT on the TV profile; the D-pad is the only channel.
- Focus enters the rail at the VERTICALLY NEAREST row, so blind key counts
  mislabel screens. Navigate by the tree.
- BACK from a tab ROOT exits the app (§1.7) — only press it after a pushed route.
- This SoC never composites the video plane into `screencap`: a black player
  frame is NOT "no video". Use decoder frame progression, the transport clock,
  `dumpsys audio state:started`, and the `AWTV` dispose log.
- Media3's PlayerView controller NEVER shows on TV; no MediaSession is
  registered on TV, by design.

Build under test: **1.42.2 / versionCode 52**, HEAD `31d4b6fad`, installed to
both devices at the start of this audit.

## Screen & element ledger

Evidence lives in `build/qa/gtv-2026-09-03/`. "focus" = a uiautomator focused-node
read; "AWFOCUS" = the app's own focus trace, read from logcat.

### 0. Shell — nav rail (`TvAppRoot.TvNavRail`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| 10 rail rows reachable + selectable | Home/Browse/Channels/Search/Library/Collections/Cartoons/Party/Surprise/Settings | T1 | **PASS** — `rail_walk` 10/10 (`walk-*.png`), each OCR-asserted |
| Left from leftmost shelf tile → rail | tvOS §3.4 contract | T1 | PASS — `AWFOCUS rail:Party` from Browse grid col 0 |
| Left from Browse grid col 0 → nearest rail row | recorded idiom (not Home) | T1 | PASS — landed on Party, the vertically nearest |
| Rail expands on focus, **collapses when focus leaves** | 88dp at rest, 220dp focused | T1 | **FAIL → FIXED #2** — was permanently expanded from first paint; content began at x=488 and Browse's scope chips were clipped at the screen edge. After: rail labels absent at rest, hero box starts at **x=224**, labels appear on the rail and vanish again on return |
| Rail hidden while a route is pushed | Detail/Player own the screen | T1 | PASS — no rail nodes on Detail/Player/Series |
| BACK from a tab root exits to launcher | §1.7 | T1 | PASS — observed twice (Channels, Home) |
| Pushed route claims initial focus | §3.1 — something is ALWAYS focused | T1 | **FAIL → FIXED #6** — `runCatching{requestFocus()}.isSuccess` is true when no EXCEPTION is thrown, so the claim loop exited on its first pass; SeriesDetail (a network fetch behind a spinner) arrived with `focused: NONE`. After: Back button focused on arrival |

### 1. Home (`TvHomeScreen`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Hero renders + claims initial focus | §3.1 | T1 | PASS — `A01-home-top.png`, focus box (224,20,1872,700) |
| Hero RIGHT cycles forward | carousel | T1 | PASS — Day the Earth Stood Still → Iola's Promise → Moonbird |
| Hero LEFT cycles back (falls to rail at index 0) | tvOS hero contract | T1 | PASS — Moonbird → Iola's Promise |
| Hero page dots | | T3 | PASS (rendered, `A05`–`A08`) |
| Hero SELECT → Detail | | T1 | PASS — `A09-detail-from-hero.png`, Play focused |
| Continue Watching shelf | present when in progress | T1 | PASS (see Library row — populated then correctly emptied at 100%) |
| 17 editorial + community + director + PD-Day shelves | populated, focus-scrollable | T1 | PASS — `AWHOME content shelves=17 hero=true`; walked to the last row (Public Domain Day 1931) |
| Tile focus keeps one tile of context | §3.3 | T1 | PASS — AWFOCUS `tile:*` all the way down |
| **Browse by Category tiles** | ≥1 row of category doors, each routing | T1 | **FAIL → FIXED #1** — the row was TV-branded in `DiscoverScreens` but never rendered on TV Home; there were no category doors at all. After: "Browse by Category" (Feature Films / Classic TV / Animation / Documentary / Newsreels & Footage / Silent Era), `AWFOCUS category:Silent Era`, Select → Silent Era grid (`K02`, `K03`) |
| **Browse by Era tiles (last row)** | the apps' order | T1 | **FAIL → FIXED #1** — absent. After: `AWFOCUS decade:1900` at the foot of Home (`K04`) |
| DOWN from the last row lands in the rail | Compose spatial search | T1 | OBSERVED, benign — reachability preserved; recorded, not fixed |

### 2. Browse (`TvBrowseScreen`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Title + real total | "Browse · N titles" | T1 | PASS — 23,695 titles |
| 9 scope chips filter | All/Films/TV/Silent/Animation/Shorts/Newsreels/Documentary/Ephemera | T1 | PASS — every chip exercised, distinct counts: 8,986 / 290 / 4,884 / 2,810 / 4,805 / 1,067 / 1,020 / 1,085 / 23,695 |
| Refine chips hidden for the TV scope | series carry their own order | T1 | PASS |
| 5 sort chips | Popular / Top Rated / A–Z / Newest / Oldest | T1 | PASS (selectable) — but see next row |
| **"Oldest" actually sorts oldest-first** | | T1 | **FAIL → FIXED #3** — `i.year ASC` puts SQLite NULLs FIRST, so page one was Flash Gordon, The Astral Factor, Zeitgeist: Addendum. After: 22, 1065, 1803, 1812, 1874, 1874 — ascending, year-less items last |
| Era chips (All eras + 1890s–2020s) | | T1 | PASS — 1920s → 3,369; 1950s → 2,483 |
| Grid paging on focus approach | 60/page | T1 | PASS — scrolled well past page 1, no gaps |
| Tile → Detail | | T1 | PASS |
| Scope-chip row clipped at the right edge | §4.2 overscan | T1 | Was a symptom of the rail bug — "Documentary" clipped at x=1920, Ephemera off-screen. Improved by FIX #2 (264px reclaimed); the row still scrolls, so all 9 remain reachable |

### 3. Detail (`TvDetailScreen`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Poster/backdrop visible on arrival (D097) | never cropped to a sliver | T1 | PASS — `A13-share-qr.png` shows the whole frame |
| Play claims initial focus | §3.1 | T1 | PASS — `inside=['Play']` on every open |
| Play → Player | | T1 | PASS — AudioTrack `state:started` from our pid |
| Favorite toggles + label flips | | T1 | PASS — "Favorite" → "Favorited", persisted across overlays and re-entry |
| Mark Watched toggles + label flips | | T1 | PASS — "Mark Watched" → "Watched" |
| Add to Playlist overlay opens, claims focus | | T1 | PASS — header "Add to Playlist", Done focused on an empty list |
| **Playlist overlay: reach Create/Done from the name field** | | T1 | **FAIL → FIXED #4** — focus entered "New playlist name" and six DOWN presses never left it; Create/Done unreachable, so a playlist could not be created on a TV. After: DOWN from the field reaches **Done** |
| Back dismisses the overlay, not the route | | T1 | PASS — returned to Detail with Play focused |
| Share → scannable QR | | T1 | PASS — QR + `https://archivewatch.org/item/PreviewIolasPromise` + "Press Back to close" |
| Version → "Choose a Copy" with the REAL file list | | T1 | PASS — "Pipeline pick (default)" + "480p · MPEG4 · 15 MB — uploader original" |
| Synopsis is focusable + scrollable-to | tvOS reachability rule | T1 | PASS — DOWN from Play focuses the synopsis block (96,324,1340,738) |
| Cast/crew chips → Person | | T1 | PASS — Mary Pickford → Person grid, tiles focusable |
| Community stats + archive.org reviews | | T1 | PASS (focus stops on a review card) |
| More Like This shelf | | T1 | PASS — `AWFOCUS tile:Buster Keaton's "Cops"` |
| "Part of <series>" on an episode | D045 | T2 | VERIFIED by reading (button present when `seriesID != null`); episode Detail exercised via Series |
| "Get Subtitles" action | tvOS has it on captionless films | T2 | **GAP** — shipped on the PHONE Detail only; `TvDetailScreen` has no entry point. Recorded, not fixed (a new TV surface is out of an audit's scope) |

### 4. Player (`PlayerScreen`, TV branch)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Playback starts | | T1 | PASS — `dumpsys audio` AudioTrack `state:started` u/pid 10100/31799, MediaCodec async adapter created |
| No overlay during playback | D037 fade contract | T1 | PASS — OCR of `A16-player.png` empty |
| A key press raises the title+description overlay | | T1 | PASS — `A19-overlay-up.png` |
| Overlay fades after 4s of playback | | T1 | PASS (empty OCR after settle) |
| Two-stage BACK (overlay → exit) | §1.7 | T1 | PASS mid-film — first BACK cleared the overlay, second left the film |
| D-pad seek / play-pause / media keys | TV-PC / TV-PP | T2 | VERIFIED by reading `tvPlaybackKeys`; RIGHT-seek exercised T1 (the film advanced to its end) |
| Options panel on DPAD UP / MENU | Play Next / Mute / Autoplay / Subtitles / Copies | T1 | PASS — `A17`: "Player Options / Mute / Autoplay next Off / Copies / 480p · MPEG4 · 15 MB"; on a queue it also shows "Play Next Episode" |
| Resume | | T1 | PASS — `AWTV player dispose id=… pos=105588 dur=105578 persist=true` |
| Ephemeral lineups never persist progress | channels/party/cartoons | T1 | PASS — `persist=false` on the cartoon marathon and on Party Play |
| **End of playback leaves the viewer stranded** | | T1 | **FAIL — NOT FIXED (PlayerScreen.kt is owned by the main session)** — see defect P1 below |

### 5. Channels (`ChannelsScreen`, TV branch)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| EPG renders (rail, ruler, NOW line, proportional blocks) | | T1 | PASS — `E01-channels.png`, window "4:03 PM – 7:03 PM" |
| Focus claimed on the AIRING block, not the chrome | | T1 | PASS — `inside=['Samurai Rebellion','2:56 PM']` |
| Earlier / Later chevrons reachable | | T1 | PASS — focusables at (456,128) and (1808,128) |
| "Now" snap-back button | appears once paged | T2 | VERIFIED by reading (`windowStartMs != null` gate) |
| "+" Create channel button | | T1 | PASS — SELECT opened "Create a Channel" |
| Dialog: Genre / Type / Era pick rows | | T1 | PASS — DOWN walks Drama → feature film → 1900s |
| **Dialog: reach Create / Cancel** | | T1 | **FAIL → FIXED #4** — focus fell into the name field and six DOWNs never left it, so a channel could NEVER be created on a TV. After: DOWN → Cancel, RIGHT → Create, SELECT → **a "Drama" user channel now leads the guide** (`K07`, `K08`) |
| Create is disabled until a facet is chosen | | T1 | PASS (correct) — un-focusable while `genre/type/decade` are all null |
| Long-press a user channel's rail → delete | | T1 | PASS — long-press removed "Drama" from the guide; "Drama Theater" (built-in) untouched |
| Tune-in joins in progress, commercials woven | | T2 | VERIFIED by reading + the 2026-08 ledger's T1 pass |
| BACK from the dialog | | T1 | PASS — 1 BACK closes the IME, 1 more closes the dialog |
| Full-day schedule per channel | tvOS has one | T2 | **N/A on Android** — no such screen exists; the rail tap is a deliberate no-op with the ripple suppressed. Recorded, unchanged |

### 6. Search (`TvSearchScreen`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| On-screen keycap keyboard, focus claimed | | T1 | PASS — first keycap 'A' focused on entry |
| Typing produces results | | T1 | PASS — "KEATON" → "100 results" |
| Result filter chips, present-facets-only with counts | | T1 | PASS — "Feature film (14)", "Tv episode (5)", "1910s (15)", "1920s (55)" |
| A filter chip re-filters | | T1 | PASS — 1910s (15) → "15 results" |
| Result → Detail | | T1 | PASS — Good Night, Nurse! |
| "Or browse without typing" doors | decade + type | T1 | PASS — 1920s → filtered grid |
| Chip label capitalisation | ten-foot polish | T3 | "Tv episode" should read "TV episode" — cosmetic, owner's call, not fixed |

### 7. Library (`TvLibraryScreen`)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| 4 section chips reachable + selectable | Favorites / Continue Watching / Watch History / Playlists | T1 | PASS — all four exercised |
| Favorites reflects a Detail favorite | | T1 | PASS — Iola's Promise appeared after favoriting |
| Continue Watching | | T1 | PASS — empty with the honest message once the film completed |
| Watch History (D078) | | T1 | PASS — Iola's Promise listed |
| Playlists empty state | | T1 | **FAIL → FIXED #5** — it read "add titles from any film's page **on your phone or the web**", though TV Detail creates playlists. Now: "open any film and choose Add to Playlist" |
| Playlist tile → PlaylistScreen, delete action | | T2 | VERIFIED by reading (`Route.Playlist` + the top-bar delete IconButton) |
| Item-level "remove from playlist" | tvOS added it 2026-08 | T2 | **GAP (cross-platform, not TV-specific)** — Android has no per-item removal on any form factor. Recorded |

### 8. Collections / Person / Filtered / Cartoons / Party / Surprise

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Collections list (curated only, counts, blurbs) | | T1 | PASS — Film Noir 240, Sci-Fi & Horror 240, Comedy 240 … |
| Collection → grid | | T1 | PASS — Film Noir grid |
| Person grid from a cast chip | | T1 | PASS — Mary Pickford, tiles focusable |
| Filtered grid from a category/era/decade door | | T1 | PASS — Silent Era, 1920s, 1950s |
| Decade deep-link title | the old `${it}s` literal bug | T1 | PASS — reads "1950s" |
| Cartoon Mode character shelves | | T1 | PASS — Popeye shelf |
| Cartoon Marathon | plays a lineup, never persists | T1 | PASS — playback + `persist=false` in the dispose log |
| Party Play: Start + "What's in the mix" | | T1 | PASS |
| Party Play starts MUTED | | T1 | PASS — the options panel reads **"Unmute"** |
| **Surprise grid** | 12 re-rollable random picks | T1 | **FAIL → FIXED #7** — the grid was COMPLETELY EMPTY (3 focusable nodes: Back, Cartoons, Re-roll). `randomPlayable()`/`randomFeatureFilm()` read LITE rows and then filter on `downloadURL`, which a lite row never carries, so every pick was null. After: 15 focusable nodes, tiles on the glass (`K01`) |
| Surprise Re-roll + Cartoons actions | | T1 | PASS — both focusable and reachable |
| Collection/Person producers use `awaitDb()` | the 2026-08-27 fix #1 class | T2 | **FIXED #8** — two sites still read `container.catalog.db?`, which yields a permanent spinner (Collection) or a false "Nothing here yet." (Person) if the db is momentarily null. Converted; code-found, not glass-reproduced |

### 9. Series (`SeriesDetailScreen`, TV branch)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Series resolves from a deep link | | T1 | PASS — The Beverly Hillbillies |
| Initial focus claimed | §3.1 | T1 | **FAIL → FIXED #6** — `focused: NONE` on arrival (poster-only screen, dead remote). After: the Back button holds focus |
| Header: title, "1962–1971 · CBS · 10 of 274 episodes", overview | | T1 | PASS (below the 16:9 hero; reached by scrolling) |
| Season picker | | T1 | PASS — "Season 1" opens a menu listing Season 1 + More Episodes |
| Episode rows focusable, ordered | | T1 | PASS — S01E01/02/03 with synopses |
| Episode → its own Detail (D045) | | T2 | VERIFIED by reading (`nav.openItem(aid, …, "tv-episode")`) |
| Hero occupies the whole first screen | | T3 | The arrival view is a full-bleed poster; the title/episodes need one DOWN. Owner-visual call, recorded |

### 10. Settings (shared `SettingsScreen` — **do-not-edit in this audit**)

| Element | Expected | Tier | Status / evidence |
|---|---|---|---|
| Screen opens, Back focusable | | T1 | PASS |
| "Show mature collections" toggle | D012 | T1 | PASS (present, focusable) |
| "Show categories" — 8 per-type toggles | | T1 | PASS (present, focusable, walked) |
| "Hide watched titles on Home" | | T1 | PASS |
| "Autoplay next" | | T1 | PASS (consumed by the player's options panel, which reads its value) |
| **Everything below the OpenSubtitles fields** | reachable by remote | T1 | **FAIL — NOT FIXED** — see defect S1 |
| OpenSubtitles username/password/Connect | | T1 | Present; the username field is where the D-pad dies |
| Live Caption pointer + "Open caption settings" | | T1 | Renders; focusable — reachable only via `KEYCODE_TAB` |
| **Sync — "Sign in with Google"** | reachable, launches Google's UI, BACK returns | T1 | **1 FAIL / 2 PASS** — see the Sync rows below |
| TMDb attribution (D007), donate address (D010), Version | must be READABLE at ten feet | T1 | **FAIL — NOT FIXED** — see defect S2 |

#### Sync section (Settings → Sync, `google` flavor, OAuth client configured)

| # | Check | Status / evidence |
|---|---|---|
| 1 | "Sign in with Google" is REACHABLE BY D-PAD | **FAIL** — unreachable. Walking DOWN from the toggles lands in the OpenSubtitles username field and the remote dies there (`focused: NONE`, DOWN×4 no movement, `G03-settings-focus-lost.png`). The button IS focusable — `KEYCODE_TAB` reaches it at (32,406,327,502) — but no TV remote sends Tab. Fault is TV focus/reachability, not the sync layer |
| 2 | SELECT launches Google's account chooser | **PASS** — `mCurrentFocus=com.google.android.gms/…auth.api.credentials.authorization.ui.AuthorizationActivity`; on screen: "Choose an account · Archive Watch is requesting access to your Google Account · Ben Wilkoff benwilkoff@gmail.com". Sign-in deliberately not completed |
| 3 | BACK returns to Settings, app still usable | **PASS** — back in MainActivity, focus restored to "Sign in with Google", UP moved to "Open caption settings", and the section showed the honest error "Sign-in was not completed." |

### 11. Deep links

| Link | Status / evidence |
|---|---|
| `archivewatch://item/<id>` | PASS — Detail |
| `archivewatch://series/<slug>` | PASS — Series |
| `archivewatch://surprise` | PASS — Surprise (empty before FIX #7, populated after) |
| `archivewatch://channels` | PASS — Channels tab |
| `--es aw_start_route decade:1950` | PASS — "1950s" grid |
| `--es aw_start_tab <5 tabs>` | PASS — used throughout this audit |

## Fix log

Each fix was measured on the Google TV Streamer BEFORE and AFTER, on the glass.
Nothing here is a new feature; every row restores behaviour the app already
claims, on a platform where it was not happening.

| # | Screen | Defect | Class | Fix | File |
|---|---|---|---|---|---|
| 1 | Home | **No category and no era tile rows.** `payload.categories` / `payload.decades` are computed by the shared `rememberHomePayload`, and `CategoryTilesRow` / `EraTilesRow` were given TV focus treatment months ago — but `TvHomeScreen` never rendered either, so the TV Home had no category doors at all and the last row was Public Domain Day. | Parity gap (dead code on one platform) | Both rows rendered in the phone/tvOS positions: categories right after the hero, eras LAST. | `ui/tv/TvHomeScreen.kt` |
| 2 | Shell | **The nav rail expanded on the transient focus every cold start hands its first focusable and NEVER collapsed** — 220dp of a 1920px canvas spent permanently, against its own stated design; Browse's scope-chip row was clipped at the right edge as a result. | Design regression | `Modifier.onFocusChanged { expanded = it.hasFocus }` on the rail column. | `ui/tv/TvAppRoot.kt` |
| 3 | Browse | **"Oldest" did not sort oldest-first.** SQLite orders NULL FIRST on ASC, so `i.year ASC` led the grid with year-less items (Flash Gordon, The Astral Factor, Zeitgeist: Addendum). | Data/ordering bug | `i.year IS NULL, i.year ASC` — the idiom `RATING` in the same enum already uses. | `data/CatalogDatabase.kt` |
| 4 | Detail + Channels | **A Compose `TextField` is a FOCUS TRAP on a remote**: it consumes every D-pad direction for its own cursor, so the buttons below it were unreachable. Measured: six DOWN presses left focus on "New playlist name", and six on the create-channel name field. **Creating a playlist and creating a channel were both impossible on Android TV.** | Reachability (§3.1/§3.4) | New `Modifier.tvTextFieldEscape()` (vertical only, TV-gated where the screen is shared) moves focus out via `LocalFocusManager`. | `ui/tv/TvFocus.kt`, `ui/tv/TvDetailScreen.kt`, `ui/screens/ChannelsScreen.kt` |
| 5 | Library | Playlists empty state sent the viewer to "your phone or the web" for something the TV does. | Wrong copy | "open any film and choose Add to Playlist". | `ui/tv/TvLibraryScreen.kt` |
| 6 | Shell | **A pushed route could arrive with NOTHING focused.** `runCatching { requestFocus() }.isSuccess` reports only that no EXCEPTION was thrown — a `focusGroup` whose children have not composed answers it happily without taking focus, so the 12-try claim loop exited on its FIRST pass. Any screen that renders a spinner first (SeriesDetail — its data is a network fetch) landed with `focused: NONE` and a dead remote. | Focus race | Keep re-requesting until the group actually holds focus (`onFocusChanged { hasFocus }`), bounded at ~9s. | `ui/tv/TvAppRoot.kt` |
| 7 | Surprise | **The Surprise grid was completely empty** — three focusable nodes, no tiles, on TV *and* phone. `randomPlayable()` / `randomFeatureFilm()` read LITE rows and then `.firstOrNull { it.downloadURL != null }`; a lite row never carries `downloadURL`, so every one of the twelve picks was null. | Regression from the lite-row perf work | Both queries read the full `item_json` blob, exactly as `browse(full = true)` does. | `data/CatalogDatabase.kt` |
| 8 | Collections / Person | Two producers still read `container.catalog.db?` instead of `awaitDb()` — the 2026-08-27 fix #1 class. A momentarily-null db leaves the collection grid on a permanent spinner and shows the person grid a false "Nothing here yet." | Race / universal-states | Converted both to `awaitDb()`. Code-found, not glass-reproduced. | `ui/screens/ExploreScreens.kt` |

**The pattern in 1, 4, 6 and 7 is worth naming**: none of them is broken code.
Each is a *seam* — a row that exists but is never rendered, a modifier that
exists but is never applied, a retry that exists but exits immediately, a query
that exists but reads the wrong row shape. A compile proves nothing about any
of them, and four of the five would pass any screenshot review, because what
fails is reachability and emptiness, not drawing.

## Defects found and NOT fixed (files owned by the main session)

### P1 — At the end of a film the viewer is stranded, and BACK is eaten
`ui/screens/PlayerScreen.kt` — **do not edit** per this audit's brief.

Measured on the Google TV: when a film reaches its end, Media3's `PlayerView`
transport controller **appears on TV** (`A22-state-now.png` — play button, ±5/15
skips, progress bar, CC, gear, fullscreen) and:

- `focused: NONE` — nothing holds focus, so the D-pad is dead;
- the controller's own visibility listener writes `controlsVisible = true`
  (`AWPLAYER controller visibility=0`, and `View.VISIBLE == 0`), so the TV
  `BackHandler(enabled = controlsVisible)` consumes BACK to "dismiss the
  overlay" — and Media3 immediately re-shows the controller, arming it again;
- it took **four BACK presses** to leave the player.

This contradicts the invariant this project has written down twice ("Media3's
PlayerView controller NEVER shows on TV"): it is true during playback, and false
in the ENDED state, because `controller_auto_show` shows the controller when the
player is idle or ended.

**Root cause**: `useController = true` is set unconditionally in the
`AndroidView` factory, and `setControllerVisibilityListener` writes the app's own
`controlsVisible` on TV as well as phone.

**Suggested remedy** (one line each, for the owning session): set
`useController = !isTv` (the TV already owns every remote key through
`tvPlaybackKeys` and draws its own overlay), and register the visibility
listener only when `!isTv` so the app's state machine cannot be driven by a
controller it never shows. Then re-verify: play a short film to its end and
assert (a) something still holds focus and (b) ONE back press leaves.

### S1 — Settings: the OpenSubtitles text fields kill the remote, and everything below them is unreachable
`ui/screens/SettingsScreen.kt` — **do not edit** per this audit's brief.

Walking DOWN from the toggles lands in "OpenSubtitles username" and the D-pad
dies there: `focused: NONE`, DOWN×4 and UP×1 move nothing, even after BACK
dismisses the IME (`G03-settings-focus-lost.png`). Everything below is
therefore unreachable by remote: **Open caption settings, the whole Sync
section (Sign in with Google), the TMDb attribution, the donate address and the
Version row.** `KEYCODE_TAB` reaches them all, which is how rows 2 and 3 of the
Sync check were exercised — but no TV remote sends Tab.

**Suggested remedy**: apply the same `Modifier.tvTextFieldEscape()` this audit
added (`ui/tv/TvFocus.kt`) to both OpenSubtitles fields, TV-gated with
`LocalIsTelevision.current`, exactly as `ChannelsScreen` now does. Verified to
work on both other fields on the device.

### S2 — Settings: the attribution, donate address and version cannot be scrolled to
Same file. `TMDB_NOTICE`, `SOURCES`, the TV donate address and the Version row
are plain `Text` — not focusable. A TV `verticalScroll` only scrolls to
FOCUSABLE children, so even with S1 fixed the tail of Settings can be reached
only if some focusable sits below it. This is the exact defect tvOS fixed on
2026-08-28 with `ReadableTextBlock` (a focusable, rendered-focus text block),
after the owner's directive that *everything on the TV should be viewable, even
without a toggle to flip*. Decision 007 makes the TMDb notice non-optional, so
this is a compliance surface, not only a polish one.

**Suggested remedy**: an Android twin of `ReadableTextBlock` — `Modifier
.tvFocusable(onClick = {})` on the attribution/donate/version blocks when
`LocalIsTelevision.current`.

### X1 — Cross-platform: the same "Oldest" NULL-year bug is live on Apple
`ArchiveWatch/ArchiveWatch/Store/CatalogDB.swift:374` — `case .oldest: order =
"i.year ASC"`. Identical to FIX #3 and identically wrong; the Swift twin is
deliberately untouched here because the Apple targets are mid-submission. The
fix is the same clause: `"i.year IS NULL, i.year ASC"`.

## Owner-visual checklist (T3 — a machine cannot close these)

- Rail expand/collapse animation feel now that it actually collapses.
- Ambient backdrop intensity on Home (carried over from the 2026-08 ledger).
- The Series screen opens on a full-bleed poster; the title and episode list
  need one DOWN. Correct, or should the hero be shorter?
- Search filter chips read "Tv episode" rather than "TV episode".
- Data blemish now visible in Browse → Oldest: items with years 22, 1065, 1803.
  These are catalog values, not a client bug — a pipeline sanity rule for
  implausible years would clean the first page of that sort.

## Fire TV Stick 4K (AFTKRT, Fire OS — `amazon` flavor, zero GMS)

Same source, `assembleAmazonDebug`, installed over adb at 10.0.0.139.

| Check | Status / evidence |
|---|---|
| Rail walk, all 10 rows | **PASS 10/10** — same harness, OCR-asserted (`walk-*.png`, Fire pass) |
| Nav rail collapsed at rest (FIX #2) | **PASS** — zero rail label nodes; hero focus box starts at x=224 |
| Detail renders + Play claims focus | **PASS** — Iola's Promise with Play / Favorite / Mark Watched / Add to Playlist / Share / Version |
| Search: keyboard, typing, results, facet chips | **PASS** — "KEATON" → 100 results; "Feature film (14)", "Tv episode (5)", "Short film (4)" |
| Player options panel (DPAD UP) | **PASS** — Player Options / Mute / Autoplay next / Copies |
| **Films actually play** | **FAIL — see defect P2** |
| Cast/Drive sync absent by design | N/A — zero-GMS flavor (`audit_fire_tv_gms.py` gates this in CI) |

### P2 — On the Fire TV Stick 4K a film opens but never plays
`ui/screens/PlayerScreen.kt` — **do not edit** per this audit's brief.

Measured with NO keys pressed after Play, on two different titles:

| | Google TV Streamer | Fire TV Stick 4K |
|---|---|---|
| Iola's Promise (1:46) | plays — AudioTrack `state:started` from our pid, decoder frames, resume written | **00:00 · 01:46** after 25s, then 12s more |
| His Girl Friday (91 min) | — | **00:00 · 1:31:45** after 30s |
| Focus during playback | the player SURFACE (0,0,1920,1080) | Media3's controller **Play** button (908,488,1012,592), stable from t+4s through t+24s |
| Active AudioTrack for our uid | yes | **none** |

`MediaCodecLogger` shows the Fire TV decoder starting, rendering a first frame
at 29.970 fps, and then **flushing and stopping** ~10-14s in, with
`AWPLAYER controller visibility=0` (`View.VISIBLE == 0`) at the same moment.
No ExoPlayer error is logged; `ExoPlayerImpl: Init … [karat, AFTKRT, Amazon, 30]`
is clean.

**Not caused by this audit's changes**: the identical build plays correctly on
the Google TV (the negative control), nothing here touches the player path, and
the controller already holds focus at t+4s — before the shell's focus retry
window could matter.

**What this shares with P1**: on Fire OS the Media3 `PlayerView` controller is
visible during what should be playback and OWNS focus, which is the same
`useController = true` root the Google TV only exposed at end-of-film. Fixing
P1 (`useController = !isTv`) is the first thing to re-measure here.

## Loop state

- Built and installed 1.42.2-debug (vc52) on **both** devices at the start.
- Google TV: rail walk 10/10, then an element-level sweep of Home, Browse,
  Detail, Player, Channels, Search, Library, Collections, Person, Filtered,
  Cartoons, Party, Surprise, Series, Settings and six deep links.
- Eight fixes landed, rebuilt, reinstalled, and each re-verified on the glass.
- Fire TV: amazon flavor built, installed, rail walk 10/10, Detail + Search
  PASS, playback FAIL (P2).
- Nothing was committed; version numbers untouched.

## Counts

**PASS 71 · FAIL 13 (8 fixed and re-verified, 5 handed over) · SKIP/N-A 5.**

The five handed over are P1 and P2 (`PlayerScreen.kt`), S1 and S2
(`SettingsScreen.kt`) — all four in files this audit was told not to edit — and
X1, the Apple twin of FIX #3.

The five SKIP/N-A rows, each with its reason: the Channels full-day schedule
screen (does not exist on Android — the rail tap is a deliberate no-op), Detail
"Get Subtitles" (shipped on the phone only; adding a TV surface is beyond an
audit), playlist item-removal (missing on Android at every form factor, not a
TV defect), Cast/Drive on the amazon flavor (excluded by design), and completing
the Google sign-in (reaching Google's consent UI was the agreed pass).
