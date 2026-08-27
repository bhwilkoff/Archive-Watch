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
| Hero carousel (multi-item, L/R cycles) | Single `TvHero` (first item only) — no carousel/cycling | T2 | GAP-DESIGN |
| Continue Watching shelf (resume) | present in payload? verify order + resume seek | | PENDING |
| Category tiles (≥30 gate) → filtered grid | | | PENDING |
| Decade tiles (last row) | | | PENDING |
| Curated + dynamic shelves (D056 playability-gated) | `TvShelfRow` over `rememberHomePayload` (shared w/ phone) | T2 | PENDING (verify shelf SET matches tvOS: 21 priority shelves) |
| Top Rated shelf (votes ≥1000) | | | PENDING |
| Hidden Gems shelf (D050 computed col) | | | PENDING |
| Director shelves | | | PENDING |
| Community shelves (Watching Now / Favorites / Most Discussed) | | | PENDING |
| Classic TV decade shelves (D086: allowStandaloneTV) | Android twin of the D086 conditional was flagged as parity follow-up — likely MISSING | T2 | PENDING |
| Cross-shelf dedup (one ordered seen-set) | | | PENDING |
| Public Domain Day shelf | | | PENDING |

### 2. Movies / Browse (`TvBrowseScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Grid + infinite scroll + real total | 6-col grid, paging | T2 | PENDING |
| Type facet chips | scope chips exist (incl. TV scope) | T2 | PENDING (verify full type vocabulary) |
| Era/decade facet chips | NOT SEEN in TvBrowseScreen | T2 | GAP |
| Sort menu (Popular/Top Rated/A-Z/Newest/…) | hardcoded `BrowseSort.POPULAR` | T2 | GAP |
| Color/B&W filter | | | PENDING |
| Card → Detail routes | | | PENDING |

### 3. TV Shows (series → season → episode)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Series grid (designed-art-first, SNL demoted) | TV scope in Browse → `seriesCards()` (shared, D086-era fix benefits all) | T2 | PENDING |
| TV Specials entry | | | PENDING |
| Season picker → episode list | routes into phone `SeriesDetail`? verify TV-native + D-pad | | PENDING |
| Prev/next episode in player + binge advance | phone has Media3 queue; verify on TV player | | PENDING |
| Episode context actions (favorite/playlist/share) | | | PENDING |

### 4. Channels (EPG)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| EPG guide (proportional blocks, ruler, now-line) | Compose guide exists (focusable blocks) | T1 | PENDING (device verify) |
| Tune-in joins in progress + commercials woven | | | PENDING |
| Full-day schedule per channel | | | PENDING |
| Create user channel | phone dialog — reachable/operable by D-pad? | | PENDING |
| Delete user channel (tombstone) | phone long-press — works with remote? | | PENDING |
| Channel playback never persists progress (ephemeralLineup) | verify PlaySpec.persistProgress=false on TV path | T2 | PENDING |
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
| Type/Era filters over results (present-facets-only) | tvOS gained these in audit fix #4 — verify TV twin | T2 | PENDING |
| Result routes by type (Detail vs SeriesDetail) | | | PENDING |

### 10. Library (`TvLibraryScreen`)
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Favorites grid | | | PENDING |
| Watched / watch history (D078 durable record) | | | PENDING |
| Playlists: create/add/remove/delete + playback | phone dialogs by D-pad? | | PENDING |
| Continue Watching | | | PENDING |

### 11. Surprise
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Re-rollable tiles grid (11 kinds on tvOS) | Route.Surprise from rail | T2 | PENDING (verify tile SET parity) |
| Random Film playable-only guard | | | PENDING |

### 12. Settings
| tvOS element | Android TV state | Tier | Status |
|---|---|---|---|
| Mature filter (D012) | phone Settings screen via rail push — D-pad operable? | | PENDING |
| Category visibility toggles | | | PENDING |
| Hide-watched toggle | | | PENDING |
| Autoplay mode | phone marked 🚧 in PARITY | | PENDING |
| Commercial break cap | | | PENDING |
| TMDb attribution (D007) + donate (D010) | | | PENDING |
| Subtitles: OpenSubtitles account + Get Subtitles | phone has SubtitleAccountSection twin? | | PENDING |
| Live Caption pointer (Android's system captioning) | Android Settings surfaces system Live Caption (2026-08-09) | T2 | PENDING (verify on TV: Live Caption availability differs on TV devices) |

### Cross-cutting
| Element | State | Tier | Status |
|---|---|---|---|
| Detail: Play/Favorite/Share/More-Like-This/cast→person/part-of-series | `TvDetailScreen` — verify every action vs tvOS row | T2 | PENDING |
| Player: D-pad contract (center/seek), resume, resilient loader analogue, load watchdog | | | PENDING |
| Subtitles render + caption choice on TV player | published VTT via Media3; NO engine analogue (no on-device transcription API on Android — recorded platform difference) | T2 | PENDING (verify + record) |
| Alias forwarding (D085: Android never queried item_aliases — fixed 2026-08-20) | | T2 | PENDING (verify on TV build) |
| Deep links route on TV (item/series/surprise/channels) | item verified T1 2026-08-27 (Suddenly Detail via adb) | T1 | PARTIAL |
| Universal empty/error/loading states per TV screen | | | PENDING |
| Back contract (§1.7: never swallowed; exits from root) | | | PENDING |

## Google-TV-native design (the "full advantage" half of the directive)

Candidate adoptions, each to be dispositioned (adopt / reject with reason):

| Google TV element | Purpose | Status |
|---|---|---|
| `tv-material` ImmersiveList idiom — focused card drives a full-bleed backdrop | the Google TV signature look; our Home hero is static | PENDING |
| Focus scale + border per §3.2 via `tv-material` CardScale/Border defaults | verify we use the platform's own focus grammar, not hand-rolled | PENDING |
| Google TV home-screen **channels** (TvProvider: Continue Watching row + editorial channel) | the Top Shelf analogue; §1.4 binds (our editorial + user's own CW only) | PENDING |
| **Watch Next** integration (WatchNextProgram on pause/finish) | Continue Watching on the platform home | PENDING |
| Global search / Assistant integration (searchable provider) | "surprise me" analogue is App Shortcuts; TV global search is separate | PENDING |
| Ambient/screensaver behavior | system-owned on Google TV — likely N/A | PENDING |
| Media session on TV (TV-NP forbids background video → verify pause-on-switch-away) | compliance | PENDING |
| 4K/HDR surface flags + refresh-rate switching | play 4K archive files at native rate where present | PENDING |

## Fix log

| # | Screen | Issue | Class | Fix | Version |
|---|---|---|---|---|---|

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
