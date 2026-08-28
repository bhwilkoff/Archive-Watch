# Android TV / Google TV Parity Audit — 2026-08

Owner directive: *"build a Google TV version of the app that has full parity
with the Apple TV version (including all pages, functionalities, and
features) … built specifically for Google TV and takes full advantage of the
full design elements available there … Android TV should be a first class
app."*

This is the audit's **living ledger**, patterned on `docs/TVOS-AUDIT.md`
(whose 44/44 on-device pass is the parity TARGET). Every row gets a
disposition before the loop closes. PARITY.md §8b's "all surfaces
D-pad-verified (12/12)" measured *reachability*, not parity — this ledger
measures the full feature surface against tvOS.

## Method

The owner's **Google TV device** (SEI `Dongle_R_4K`, Android 14, 10.0.0.55,
paired for network ADB — see `google_tv_adb_harness` memory) is the oracle:

    ADB=~/Library/Android/sdk/platform-tools/adb
    PORT=$($ADB mdns services | awk '/GZ25.*_adb-tls-connect/ {split($3,a,":"); print a[2]}' | head -1)
    $ADB connect 10.0.0.55:$PORT
    $ADB -s 10.0.0.55:$PORT install -r android/app/build/outputs/apk/google/debug/app-google-debug.apk
    # launch hooks = deep links (no env vars needed):
    $ADB -s ... shell am start -a android.intent.action.VIEW -d "archivewatch://item/<id>" com.archivewatch.app.debug
    # evidence channels: exec-out screencap -p · logcat (fully readable!) ·
    # uiautomator dump (focus tree) · input keyevent KEYCODE_DPAD_*

Verification tiers (same as TVOS-AUDIT): **T1 device** (screenshot/logcat/
focus-tree evidence on the Google TV) · **T2 code** (wiring read end-to-end)
· **T3 owner** (feel/visual). The standing rule from
`atv_external_observation_harness` binds here too: claims ship on external
evidence, never the app's own console alone — but logcat makes T1 far
cheaper here than it ever was on tvOS.

Harness: `tools/gtv_scenario.py` (adb twin of `tools/atv_scenario.py`) — to
be built in this loop. Existing: `tools/verify_tv_focus.sh` (12/12
reachability, emulator-era).

## Ground rules

- **TV-DESIGN.md binds** (IA inherited from tvOS-DESIGN §2; focus contract
  §3; §1.5 forbids a lean-back-only degraded build).
- **Same verb, native idiom** (PARITY.md rule). Parity ≠ pixel copy: the
  Google TV expression uses Compose-for-TV / `tv-material` idioms —
  immersive backdrops, focus-scaled cards, rail nav — not tvOS chrome.
- Deliberate platform differences are recorded as N/A **with the reason**,
  exactly like TVOS-AUDIT did in the reverse direction (e.g. tvOS has no
  Home shuffle button because Surprise is a sidebar tab).
- Known tvOS-only verbs stay out of scope: Top Shelf (→ Google TV
  home-screen channels are the analogue, §8 below), AirPlay receiver, Siri,
  CloudKit sync (Drive App Data is the Android analogue, owner-gated on the
  OAuth client), Clip/Creation Studio (never on TV, D033/D042).

## Screen inventory (tvOS 12-tab ledger mapped to Android TV)

### 1. Home (`TvHomeScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Hero carousel (multi-item, L/R cycles) | Right cycles forward, Left back until first (then rail) + page dots + crossfade | T1 | **FIXED #3** (dots advanced on device) |
| Continue Watching shelf (resume) | present in payload? verify order + resume seek | | PENDING |
| Category tiles (≥30 gate) → filtered grid | | | PENDING |
| Decade tiles (last row) | | | PENDING |
| Curated + dynamic shelves (D056 playability-gated) | `TvShelfRow` over `rememberHomePayload` (shared w/ phone) | T2 | PENDING (verify shelf SET matches tvOS: 21 priority shelves) |
| Top Rated shelf (votes ≥1000) | | | PENDING |
| Hidden Gems shelf (D050 computed col) | | | PENDING |
| Director shelves | | | PENDING |
| Community shelves (Watching Now / Favorites / Most Discussed) | | | PENDING |
| Classic TV decade shelves (D086: allowStandaloneTV) | twin EXISTS and is wired (`HomeScreen.kt:145` passes per-shelf category) | T2 | VERIFIED |
| Cross-shelf dedup (one ordered seen-set) | | | PENDING |
| Public Domain Day shelf | | | PENDING |

### 2. Movies / Browse (`TvBrowseScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Grid + infinite scroll + real total | 6-col grid, paging | T2 | PENDING |
| Type facet chips | scope chips exist (incl. TV scope) | T2 | PENDING (verify full type vocabulary) |
| Era/decade facet chips | second chip row (All eras + 1890s–2020s), hidden for TV scope | T1 | **FIXED #2** (rendered on device) |
| Sort menu (Popular/Top Rated/A-Z/Newest/Oldest) | sort chips row — all 5 `BrowseSort` values | T1 | **FIXED #2** (rendered on device) |
| Color/B&W filter | | | PENDING |
| Card → Detail routes | | | PENDING |

### 3. TV Shows (series → season → episode)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Series grid (designed-art-first, SNL demoted) | TV scope in Browse → `seriesCards()` (shared, D086-era fix benefits all) | T2 | PENDING |
| TV Specials entry | | | PENDING |
| Season picker → episode list | routes into phone `SeriesDetail`? verify TV-native + D-pad | | PENDING |
| Prev/next episode in player + binge advance | **FIXED #8** — episode binge queue REGRESSED on ALL Android paths when D045 moved episodes to Detail-first routing (PARITY's ✅ was stale); `episodeBingeQueue` rebuilds the season queue at both Detail seams (phone + TV), and MEDIA_NEXT/PREVIOUS join the TV key contract (the Media3 controller's buttons never show on TV). Device-verified: MEDIA_PREVIOUS advanced to the other playable episode (dispose id flipped, independent progress, Watch Next row) | T1 | VERIFIED |
| Episode context actions (favorite/playlist/share) | | | PENDING |

### 4. Channels (EPG)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| EPG guide (proportional blocks, ruler, now-line) | renders (cold repro: full guide at 30s) | T1 | VERIFIED — after **FIX #1** (see fix log) |
| Tune-in joins in progress + commercials woven | tuned The Manchurian Candidate at 41:52 (startAt honored); commercials weave = T2 (scheduler shared) | T1 | VERIFIED |
| Full-day schedule per channel | | | PENDING |
| Create user channel | phone dialog — reachable/operable by D-pad? | | PENDING |
| Delete user channel (tombstone) | phone long-press — works with remote? | | PENDING |
| Channel playback never persists progress (ephemeralLineup) | dispose log: `persist=false` on a channel tune-in | T1 | VERIFIED |
| Commercial break length cap (Settings) | | | PENDING |

### 5. Cartoons / Kids mode
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Character/theme shelves (kid-safe, color-leaning) | Route.Cartoon reachable from rail? (grep shows route exists) | T2 | PENDING |
| Marathon lineup | | | PENDING |

### 6. Party Play | no Android analogue shipped | | GAP (deliberate-defer? record either way) |
### 7. Screensaver | no Android analogue (system screensaver owns the TV idle) | | likely N/A — confirm + record |

### 8. Collections
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Curated collections landing + blurbs | Route.Collections exists — TV-native or phone screen? | T2 | PENDING |
| Collection → filtered grid | | | PENDING |

### 9. Search (`TvSearchScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| FTS results (keyboard + no-typing browse doors §3.6) | TV-native screen exists | T2 | PENDING |
| Type/Era filters over results (present-facets-only) | **FIXED #7** — TvFilterChip row: present-facets-only w/ counts, active chip self-clears, reset on new query | T2 | SHIPPED (T1 blocked on harness type_text) |
| Result routes by type (Detail vs SeriesDetail) | | | PENDING |

### 10. Library (`TvLibraryScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Favorites grid | section present | T2 | VERIFIED |
| Watched / watch history (D078 durable record) | **FIXED #6** — Watch History section added (db.itemsByIDs over userState.history()) | T2 | SHIPPED |
| Playlists: create/add/remove/delete + playback | phone dialogs by D-pad? | | PENDING |
| Continue Watching | | | PENDING |

### 11. Surprise
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Re-rollable tiles grid (11 kinds on tvOS) | shared grid resolves random picks (Sunrise, Don Quixote 1915, …) + Re-roll + Cartoons door; shell focus claim makes it D-pad-operable (recorded as the PARITY §8b idiom) | T1 | VERIFIED |
| Random Film playable-only guard | | | PENDING |

### 12. Settings
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Mature filter (D012) | row present, focus-claimed screen | T1 | VERIFIED (presence; toggle flip left untested to avoid catalog flip mid-audit) |
| Category visibility toggles | NOT on Android Settings (phone parity row also absent) | T2 | GAP (cross-platform, not TV-specific) |
| Hide-watched toggle | row present | T1 | VERIFIED (presence) |
| Autoplay mode | "Autoplay next" row present | T1 | VERIFIED (presence) |
| Commercial break cap | | | PENDING |
| TMDb attribution (D007) + donate (D010) | | | PENDING |
| Subtitles: OpenSubtitles account + Get Subtitles | phone has SubtitleAccountSection twin? | | PENDING |
| Live Caption pointer (Android's system captioning) | Android Settings surfaces system Live Caption (2026-08-09) | T2 | PENDING (verify on TV: Live Caption availability differs on TV devices) |

### Cross-cutting
| Element | State | Tier | Status |
|---|---|---|---|
| Detail: Play/Favorite/More-Like-This | present | T1 | VERIFIED |
| Detail: Add to Playlist | **FIXED #4** — TV-native right-panel overlay (toggle rows, create via leanback IME, Back dismisses + logs, empty list claims Done focus) | T1 | VERIFIED (overlay + Back on device) |
| Detail: cast → person chips + part-of-series | **FIXED #4** — director-first chips w/ role captions → Route.Person; episode gets "Part of <series>" | T1 | VERIFIED (chips OCR'd on device; series link T2) |
| Detail: Share | NOT SHIPPED — tvOS uses a QR ShareSheet; Android has no native QR generator (no third-party deps rule) | T2 | DEFERRED (needs in-repo QR encoder or a decision) |
| Player: playback + transport + resume | VERIFIED T1 (Girl o' My Dreams): decoder frames 673→1805 @~24fps, AudioTrack started from our pid, transport clock 01:51/1:02:51 matches wall time, title+description overlay (D037), **resume at 02:17 after exit** | T1 | VERIFIED |
| Player: subtitles render | caption text OCR'd on the glass during playback | T1 | VERIFIED |
| Player: Back with controls up dismisses controls first, second Back exits | **FIXED #5** — BackHandler gated on controllerVisible (TV only) | T1 | VERIFIED (34/35/36 captures) |
| Player: D-pad seek | seek keys in tvPlaybackKeys (T2); glass check folded into closing gate | T2 | SHIPPED |
| Subtitles render + caption choice on TV player | published VTT via Media3; NO engine analogue (no on-device transcription API on Android — recorded platform difference) | T2 | PENDING (verify + record) |
| Alias forwarding (D085: Android never queried item_aliases — fixed 2026-08-20) | | T2 | PENDING (verify on TV build) |
| Deep links route on TV (item/series/surprise/channels) | item verified T1 2026-08-27 (Suddenly Detail via adb) | T1 | PARTIAL |
| Universal empty/error/loading states per TV screen | | | PENDING |
| Back contract (§1.7: never swallowed; exits from root) | | | PENDING |

## Google-TV-native design (the "full advantage" half of the directive)

Candidate adoptions, each to be dispositioned (adopt / reject with reason):

| Google TV element | Purpose | Status |
|---|---|---|
| `tv-material` ImmersiveList idiom — focused card drives a full-bleed backdrop | ambient layer SHIPPED: focused card's backdrop at 0.30 alpha under scrim, 300ms rest debounce, 600ms crossfade | SHIPPED (T3: intensity = owner taste) |
| Focus scale + border per §3.2 via `tv-material` CardScale/Border defaults | verify we use the platform's own focus grammar, not hand-rolled | PENDING |
| Google TV home-screen **channels** (TvProvider: Continue Watching row + editorial channel) | **Watch Next SHIPPED + device-verified** (insert logged: watch_next_program/245679250; finished films removed at ≥95%; card deep-links to Detail). Editorial channel row still open | PARTIAL |
| **Watch Next** integration (WatchNextProgram on pause/finish) | SHIPPED — publish on player dispose via container.scope | VERIFIED T1 |
| Global search / Assistant integration (searchable provider) | "surprise me" analogue is App Shortcuts; TV global search is separate | PENDING |
| Ambient/screensaver behavior | system-owned on Google TV — likely N/A | PENDING |
| Media session on TV (TV-NP forbids background video → verify pause-on-switch-away) | compliance | PENDING |
| 4K/HDR surface flags + refresh-rate switching | play 4K archive files at native rate where present | PENDING |

## Fix log

| # | Screen | Issue | Class | Fix | Version |
|---|---|---|---|---|---|
| 1 | ALL data-producing screens (18 sites, 10 files) | `container.catalog.db ?: return@produceState` bails without a value when the db is momentarily null (startup, or the refresh swap window on a fresh install) — produceState never re-runs, so the screen spins FOREVER. Measured on the Google TV: Channels spinner in two captures ~20s apart minutes after a fresh install; cold repro rendered fine, which is what separated race from slowness. | Race / universal-states | `CatalogRepository.awaitDb()` suspends on the dbVersion flow until the db is open; all 18 bail-outs converted. Phone screens carried the same latent bug. | android google-debug 2026-08-27 |
| 2 | TV Browse | Sort hardcoded to POPULAR; no era facet — tvOS has 5 sorts + Type/Era chips (tvOS audit fix #4 class: parity that never returned to a platform) | Parity gap | `TvRefineChips` row: all 5 BrowseSort chips + All-eras/1890s–2020s decade chips, hidden for the TV-series scope; wired into browse()/browseCount() + focus-driven paging keeps working | android google-debug 2026-08-27 |

## Loop state

- Tick 1 (2026-08-27): ledger created from code inventory. TV layer measured
  at ~2,085 lines / 10 files. Known-by-reading gaps seeded: single-item hero
  (no carousel), Browse locked to POPULAR sort, no era chips on TV Browse.
  Fresh 1.3.460-debug installed on the device; first T1 sweep
  (build/qa/gtv-2026-08-27/): Search screen VERIFIED T1 (TV-native keyboard
  + no-typing decade doors render + focus visible); **Channels FAILS T1 —
  perpetual spinner, no EPG, in two captures ~20s apart** (root: TV tab
  drops in the phone `ChannelsScreen` unchanged; no crash in logcat);
  Back from a root exits to launcher (correct §1.7). Blind-count D-pad
  walks mislabel screens — `gtv_scenario.py` must navigate by uiautomator
  focus tree, not step counts. Next: diagnose Channels via logcat; port
  the harness; close Browse sort/era gaps.
- Tick 2 (2026-08-27): **Fix #1** (awaitDb — the Channels forever-spinner
  race, latent in all 18 producer sites incl. phone screens) + **Fix #2**
  (TV Browse sort + era chips), both verified on the glass (12-browse-chips
  .png: 5 sorts + era row + 23,722 titles + first-tile focus). Channels EPG
  VERIFIED rendering from cold (08/09-channels-cold). Focus topology decoded:
  entering the rail lands on the VERTICALLY NEAREST item, not Home — blind
  step-count walks are structurally unreliable; `input tap` is inert on the
  TV profile. Harness must read uiautomator focus bounds between presses
  (press-verify loop proven this tick). New ledger row: hero synopsis leaks
  "Title: X Summary:" cruft (data or client strip needed). ADB: port 5555
  (classic) is STABLE across sleeps; the TLS port rotates — prefer 5555.
- Tick 3 (2026-08-27): **tools/gtv_scenario.py shipped** — connect-first
  (5555 + mdns fallback), tree-driven goto_tab, OCR assertions; first full
  run 7/7 tabs verified (its own first bug: BACK after a tab root exits the
  app per §1.7 — now BACK only after pushed routes). **Fix #3**: hero is a
  real carousel (L/R + dots, tvOS contract: Left at index 0 falls to rail).
  **Immersive ambient backdrop shipped** (Google TV signature). Pipeline:
  remediate `_strip_title_summary_dump` — 609 IMDb-scrape "Title: X
  Summary:" synopses (593 cleaned / 16 nulled, control untouched) — all
  platforms benefit at next publish. Android version is hand-set in
  build.gradle.kts (vc35/1.3.460) — bump at next Android release.
- Tick 4 (2026-08-27): **Fix #4** — TvDetail parity wave: Add-to-Playlist
  overlay (three on-device defects found + fixed in-loop: "Done" label wrap,
  empty-list focus falling through to the dimmed background (§3.1), Back
  popping the route instead of the overlay — final run logs "playlist
  overlay dismissed by Back" and stays on Detail), cast→person chips
  (OCR-verified: Stevenson/Robeson/Hardwicke/Lee with roles), part-of-series
  button, detail producers moved to awaitDb. Latent bug fixed: decade
  deep-link titles rendered the LITERAL string "${it}s" (python-patch
  escaping artifact in TvAppRoot). Share deferred pending a QR decision.
- Tick 5 (2026-08-27): player contract T1 pass. Instrument lessons: this
  SoC's video plane never composites into screencap (black frame ≠ no
  video — use decoder frameIndex progression + transport clock + AudioTrack
  state); `dumpsys media_session` ERROR belonged to BLUETOOTH, not us (make
  the instrument say WHOSE error before believing it) — the app correctly
  registers NO MediaSession on TV (TV-NP). Resume verified end to end.
  Minor gap: Back with controls up exits the player instead of dismissing
  controls first. Device catalog still shows the Title:/Summary: cruft
  until the next publish (expected — remediate is pipeline-side).
- Tick 6 (2026-08-27): **Fix #5** player two-stage Back (verified on glass:
  controls hide on first Back, player exits on second); **Fix #6** Library
  gains Watch History (D078) + stale playlist empty-state message updated;
  **Fix #7** Search result filters (type/era, present-facets-only, counts).
  Blind keycap navigation failed AGAIN (landed on a Detail) — harness needs
  a focus-verified type_text() keycap driver before search T1 closes.
- Tick 7 (2026-08-27): **type_text keycap driver** (closed-loop, rail-escape
  handling) — search T1 CLOSED ("199 results" + "Short film (56)" chip on
  glass). **Watch Next shipped + verified** (row 245679250 inserted). Three
  latent bugs found by its instrumentation: (a) dispose-time saveProgress
  launched on the dying composition scope — a silent no-op forever (the 5s
  ticker masked it); now container.scope. (b) On TV the Media3 controller
  never shows, so controlsVisible NEVER updated — the title overlay never
  faded (D037 broken on TV since the port) and my tick-6 Back fix became a
  Back TRAP; overlay visibility is now the app's own state machine (key
  interaction shows, fades 4s after real playback, Back dismisses then
  exits). Verified: overlay-up-on-key, two-stage Back, dispose log, insert
  log. (c) fade now waits out slow archive starts.
- Tick 8 (2026-08-27): sweeps — Settings rows on glass (mature/hide-watched/
  autoplay/Live Caption/attribution), Surprise grid resolves + Re-roll,
  Channels tune-in VERIFIED (join at 41:52, audio live, `persist=false` in
  the dispose log — the tvOS-audit-fix-#2 invariant holding on this
  platform). Episode binge deferred to next tick.
- Tick 9 (2026-08-27): **Fix #8** episode binge — a CROSS-PLATFORM
  regression found from the TV: no Android play path built the episode
  queue since D045's Detail-first routing (marathon/channels kept theirs;
  PARITY's ✅ was stale). Season queue now built at play time from the
  series spine at BOTH Detail seams; MEDIA_NEXT/PREVIOUS added to the TV
  key contract. Also fixed: `archivewatch://series/{slug}` was absent from
  the Android manifest + MainActivity parser (tvOS scheme parity). Bonus
  T1: episode Detail's "Part of <series>" button on glass. Note: spine
  season 1 lists only 2 playable eps for Four Star Playhouse vs 101 in the
  DB — a SPINE COVERAGE question for the pipeline, flagged (not a client
  bug).

## CLOSED — 2026-08-27. Final state

**7/7 clean-install rail-walk gate PASSED** (fresh install, full-catalog
download window included — the awaitDb fix proven under the original
failure conditions). **Android 1.3.469 (versionCode 36) published to the
Play production track** with all 8 fixes. Two of the fixes were
cross-platform regressions found from this TV (episode binge dead on every
Android path; dispose-time progress save a silent no-op).

The audit's product: this ledger, `tools/gtv_scenario.py` (connect-first,
tree-driven navigation, closed-loop type_text, OCR + logcat + focus-tree
evidence), the AWTV dispose/watchNext diagnostics left in the app, and the
recorded deferrals below — the only rows a loop cannot close alone:

- Detail **Share** — needs a QR decision (no native Android QR generator).
- **Editorial home-screen channel row** (Watch Next's sibling) — next wave.
- **Ambient backdrop intensity** — owner taste (T3).
- **Per-category visibility toggles** — missing on Android entirely
  (cross-platform row, not TV-specific).
- **Series spine coverage** (e.g. Four Star Playhouse: 2 playable S1
  episodes in the spine vs 101 in the DB) — pipeline follow-up.
- **Fire TV** — blocked on the owner's ADB Debugging toggle; takes the
  amazon (zero-GMS) flavor and the same harness.

## Polish pass — 2026-08-28 (owner: "large blocky text / huge selection indicator / persistent overlays")

- **Native type ramp** on every TV surface (hero 36 Medium, headers 18,
  chips 14, detail 36, synopsis 15/22, rail 20dp icons + 14sp) replacing
  the 56/32/24 Bold/SemiBold hand-rolled scale.
- **Native focus grammar**: 1.10 scale + 2.5dp WHITE hairline + quiet
  lift; accent rings retired; the ring frames the ARTWORK only, caption
  outside (the native card layout). Verified on both devices.
- **Player overlay cycle PROVEN on-glass**: no overlay during playback,
  overlay on pause, gone 4s after resume (OCR three-state check). The
  "persistent overlay" the owner saw is the shipped vc32; vc36 (in Play
  review) carries the state-machine fix.
- Three more literal-dollar artifacts fixed (Browse era chip "${d}s";
  Channels create-dialog era picker x2).
- Fire TV runs the identical build (amazon flavor) — Browse capture
  matches Google TV pixel-for-pixel in grammar.
- Final sweep: playlist overlay clean at native scale (no label wrap,
  focus claimed); all action-button rings now WHITE (the last accent ring);
  Detail/Library/Surprise/Channels-guide at the new scale. Data blemish
  measured and noted: 3 of 26,321 synopses are doubled (e.g. Smuggled
  Cargo) — below the threshold for a pipeline rule. **1.3.470 (vc37)
  shipped to the Play production track with the full native polish.**

## Element-level chronicle vs tvOS — 2026-08-28 (owner: "whole pages missing…")

tvOS ground truth: **12 tabs** (Home, Movies, TV Shows, Channels,
Collections, Search, Surprise, Cartoons, Party Play, Screensaver, Library,
Settings) · **7 Detail buttons** (Play, Favorite, Watched, Share, Playlist,
Versions, Get Subtitles) + community stats/reviews + photographed cast +
IMDb rating · player transport menu (Play Next / Mute / Subtitles /
Version / Autoplay mode).

Closed this tick (device-verified on Suddenly):
- Detail: cast/crew AVATARS (AvatarImage + TMDb photos), **Mark Watched**
  (new `UserStateStore.setWatched`/`isWatched`), **IMDb ★ in the meta**
  (`imdbRating` was never decoded into the Kotlin model — added), community
  stats row (views/favorites/viewer rating) + archive.org review cards
  (data was always in the DB; the TV screen never rendered it).
- Rail: **Collections** and **Cartoons** pages added (routes existed,
  unreachable from the TV shell). Harness rail map updated to 9 rows.

- **Versions picker SHIPPED + device-verified** (Horror Hotel: live
  /metadata list — "480p · H.264 · 474 MB — Archive derivative" etc.,
  pipeline-default row, per-title choice persisted by file NAME, honored
  by the player for single items AND queue entries; Kotlin port of the
  tvOS ArchiveVersions service).

- **Player Options panel SHIPPED + device-verified** (the tvOS transport
  menu): D-pad UP / MENU during playback → Play Next (queue), Mute,
  Autoplay-next toggle, Subtitles (Off/tracks), Choose a Copy
  (position-preserving mid-film swap). OCR-verified on Reefer Madness.
  Harness note: Compose overlays are ABSENT from uiautomator dumps —
  OCR is the evidence channel for them.

- **Party Play SHIPPED + device-verified**: the tvOS immersive mode
  ported whole — visual-scored color-short pool (the tvOS keyword list),
  Start button + "What's in the mix" preview, lineup plays MUTED
  (options panel reads "Unmute" — the on-glass proof), never persists
  progress. New rail page; Nav state encode/decode carries it.
  Debug lesson: a failed compile hid behind a grep that ate the error —
  and `strings` CANNOT see dex MUTF-8, so two "not in APK" verdicts were
  false; the glass is the gate.

Remaining queue: Get Subtitles (no OpenSubtitles client on Android —
decision), Share (QR decision), Screensaver (system-owned on Android —
N/A), Movies/TV as Browse scopes = accepted idiom.

## CHRONICLE CLOSED — 2026-08-28. Element-level parity state

**10/10 rail-walk gate PASSED** (Home, Browse, Channels, Search, Library,
Collections, Cartoons, Party Play, Surprise, Settings). Against tvOS's 12
tabs: Movies + TV Shows live as Browse scopes (recorded idiom);
Screensaver is system-owned on Google TV (N/A). Detail carries Play,
Favorite, Mark Watched, Add to Playlist, **Share (scannable QR,
zxing:core)**, Version, part-of-series — plus IMDb rating, photographed
cast, community stats and archive.org reviews. The player carries the
transport-menu set (UP/MENU panel) and the fade contract.
**1.3.471 (vc38) shipped to the Play production track.**

ONE OPEN DECISION (owner): **Get Subtitles** — tvOS offers per-film
OpenSubtitles search with a BYO account (QR signup + credentials typed on
the TV). Porting it to Android means a Kotlin OpenSubtitlesClient +
account section + download flow. Today Android relies on published tracks
+ system Live Caption (documented in Settings). Say the word and it gets
built; recorded here rather than guessed at.
