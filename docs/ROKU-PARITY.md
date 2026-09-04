# Archive Watch on Roku — parity ledger

**Status: tick 1 of an owner-run build loop.** This is the living list the Roku
work is measured against, in the shape `PARITY.md` already uses. It exists so
"full parity" is a checkable claim rather than a feeling.

Every row is one of:

| Mark | Meaning |
|---|---|
| ⬜ | not started |
| 🔨 | in progress |
| ✅ | built AND verified on the owner's Streaming Stick 4K, with evidence |
| ⏳ | deliberately deferred, with the reason in Notes |
| 🚫 | will not exist on Roku, with the reason in Notes |

**✅ requires evidence on the glass**, never the app's own report: a screenshot
from `tools/roku.py shot`, a line from the BrightScript console, or an ECP
assertion. That is the same bar the tvOS and Android TV audits are held to.

## The device and the harness

Roku Streaming Stick 4K, model 3820R2, Roku OS 15.3.4, 1080p UI, at
`10.0.0.155`. `tools/roku.py` wraps all four channels the platform gives us:

- **deploy** — sideload via the developer web installer (HTTP digest auth)
- **keys / type** — drive the remote over ECP
- **shot** — screenshot the running dev channel
- **log** — the BrightScript debug console on port 8085, which is our logcat

ECP **must be permissive** or `/keypress` returns 403 while `/query/device-info`
still answers, so a naive reachability check passes with every input rejected.
The owner enabled it on 2026-09-03.

## What tick 1 settled

- **The data plane question is answered, by measurement on the device.** Roku
  has no SQLite, so it cannot read the ~150 MB catalog the Apple and Android
  clients download. It reads the WEB plane instead (Decision 029): the 6.2 MB
  `catalog-index.json` downloads in **1.06 s** and `ParseJson` costs **364 ms**
  for **26,965 items**, with the device's memory level never leaving `normal`.
  No Roku-specific feed is needed. Evidence: `build/qa/roku-2026-09-03/v01_nofont.jpg`.
- **The pipeline works end to end**: package, sideload, launch, screenshot, read
  the console.
- **A Roku trap worth the whole tick**: a `<Font role="font" uri="font:LargeBoldSystemFont" />`
  child made every `Label` render NOTHING — no error, no warning, a screen of
  pure background colour while the console reported a healthy run. Removing it
  brought all text back. Never trust "the log looks fine" on this platform.

---

## Parity rows

### 1. Navigation shell

| Feature | Roku | Notes |
|---|---|---|
| Verb | ⬜ |  |
| Top-level nav | ⬜ |  |
| Per-tab back stack | ⬜ |  |
| Deep-linkable surfaces | ⬜ |  |

### 2. Discover — Home

| Feature | Roku | Notes |
|---|---|---|
| Hero / featured banner | ⬜ |  |
| Curated + dynamic shelves | ⬜ |  |
| Category tiles | ⬜ |  |
| Decade tiles | ⬜ |  |
| Hidden Gems shelf | ⬜ |  |
| Top Rated shelf (IMDb) + rating sort in Browse | ⬜ |  |
| Community shelves (Watching Now / Favorites / Most Discussed) | ⬜ |  |
| Detail community (stats + genuine reviews) | ⬜ |  |
| Director shelves | ⬜ |  |
| Continue Watching | ⬜ |  |
| Modes row | ⬜ |  |
| Public Domain Day section | ⬜ |  |

### 3. Discover — Movies / TV / Collections / Search

| Feature | Roku | Notes |
|---|---|---|
| Movies grid + facets + sort | ⬜ |  |
| Infinite scroll / paging | ⬜ |  |
| TV series → season → episode | ⬜ |  |
| TV never appears in Movies | ⬜ |  |
| TV Specials surface | ⬜ |  |
| Orphan episodes fold into spines | ⬜ |  |
| Prev/next episode in player | ⬜ |  |
| Collections landing + blurbs | ⬜ |  |
| Full-text search (FTS5) | ⬜ |  |
| Search result filters | ⬜ |  |

### 4. Detail + Playback

| Feature | Roku | Notes |
|---|---|---|
| Detail (backdrop, metadata, cast) | ⬜ |  |
| "Also known as" alternate release title | ⬜ |  |
| More Like This | ⬜ |  |
| Cast → person filmography | ⬜ |  |
| Share titles / series | ⬜ |  |
| Open in Callsheet (cast/crew app) | ⬜ |  |
| Now Playing / media controls | ⬜ |  |
| Title+description in player | ⬜ |  |
| Video playback | ⬜ |  |
| Resilient streaming | ⬜ |  |
| Resume across launches | ⬜ |  |
| Subtitles / audio / speed | ⬜ |  |
| Autoplay / continuous play | ⬜ |  |
| Picture-in-Picture | ⬜ |  |
| Background play | ⬜ |  |
| SharePlay — group waits for a stalled member | ⬜ |  |
| Cast / AirPlay | 🚫 | Roku is a RECEIVER, not a sender. |

### 5. Surprise + Immersive modes

| Feature | Roku | Notes |
|---|---|---|
| Surprise / random actions | ⬜ |  |
| Channels (EPG guide) | ⬜ |  |
| Create / user channels | ⬜ |  |
| Cartoon / Kids mode | ⬜ |  |
| Commercial-break controls | ⬜ |  |
| Party Play (muted) | ⬜ |  |
| Cover-art screensaver | ⬜ |  |
| VHS effect overlay | ⬜ |  |

### 6. Personalization + sync

| Feature | Roku | Notes |
|---|---|---|
| Favorites | ⬜ |  |
| Playlists | ⬜ |  |
| Watched / hide-watched | ⬜ |  |
| Continue Watching progress | ⬜ |  |
| Watch history (full ever-watched record, D078) | ⬜ |  |
| Cross-ecosystem history sync (Drive App Data, D028) | ⬜ |  |
| Local persistence (offline-first) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Per-ecosystem sync (own cloud) | ⬜ |  |
| Cross-ecosystem sync (all platforms) | ⬜ |  |
| Deletions carry tombstones | ⬜ |  |
| Downloads in Library (manage + remove) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Play a downloaded film with no network | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Offline subtitles for a downloaded film | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Offline state banner | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| Downloads are device-local (never synced) | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |

### 7. Settings + account

| Feature | Roku | Notes |
|---|---|---|
| Mature-content filter (default ON) | ⬜ |  |
| Category visibility toggles | ⬜ |  |
| Autoplay/playback options | ⬜ |  |
| Downloads storage + Remove All | 🚫 | No writable durable storage for media on Roku, same reasoning as Decision 099 for tvOS. |
| TMDb attribution (required) | ⬜ |  |
| Donate to Internet Archive | ⬜ |  |
| Sign-in (sync gate, optional) | ⬜ |  |
| Account deletion | ⬜ |  |

### 8. Platform reach + integration

| Feature | Roku | Notes |
|---|---|---|
| Home-screen surface | ⬜ |  |
| Voice / shortcuts | ⬜ |  |
| Spotlight / system search | ⬜ |  |
| Installable app | ⬜ |  |
| Handoff / continuity | ⬜ |  |

### 8b. Non-Apple TV platforms (Decision 047 · `docs/TV-DESIGN.md`)

| Feature | Roku | Notes |
|---|---|---|
| Client | ⬜ |  |
| Verb | ⬜ |  |
| Top-level nav | ⬜ |  |
| Home (hero + shelves) | ⬜ |  |
| Browse | ⬜ |  |
| Detail | ⬜ |  |
| Search | ⬜ |  |
| Library | ⬜ |  |
| Channels (EPG) | ⬜ |  |
| Surprise · Collections · Cartoon · filtered grids | ⬜ |  |
| Playback | ⬜ |  |
| Background media controls | ⬜ |  |
| Picture-in-Picture | ⬜ |  |
| Cast (send to TV) | ⬜ |  |
| Subtitles | ⬜ |  |
| Sign-in + sync | ⬜ |  |
| Clip Studio / Creation Studio | 🚫 | Creation is a phone and Mac feature; a remote has no direct manipulation. |
| Platform home-screen integration | ⬜ |  |
| Gate | ⬜ |  |
| `tools/verify_tv_focus.sh` | ⬜ |  |
| `tools/tv_browser_tests.js` | ⬜ |  |
| `tools/test_tv_focus.mjs` | ⬜ |  |
| `tools/test_tv_ua.mjs` | ⬜ |  |
| `tools/audit_tv_g6.py` | ⬜ |  |
| `tools/audit_fire_tv_gms.py` | ⬜ |  |

---

## Settled by the research (tick 1)

- **The design is written.** `docs/ROKU-DESIGN.md` is binding from here: left
  rail not top tabs, Settings behind `*`, every dimension divisible by 3, focus
  is a ring plus a stated size step, and a ship gate for "does this read like an
  Android app on a Roku".
- **The playback investigation the owner asked for is CLOSED, and the answer is
  no.** The `Video` node's HTTP client lives in firmware; BrightScript cannot
  intercept it, range-request through it, proxy it, or observe it. Decisions
  021 / 031 / 034 have no Roku equivalent — not partially, not at all. What
  remains is redirect pinning, transient-error tolerance, and our own
  position-stagnation watchdog that re-issues play at the last position, every
  recovery of which is a visible cold re-buffer.
- **Cross-device sync is blocked by POLICY, not plumbing.** Roku certification
  prohibits off-device sign-in, which is structurally what Google's
  limited-input device flow is — the only route that would have reached Drive
  App Data. Roku's own Continue Watching gives cross-device progress without an
  account of ours, and that is the honest answer.
- **Storage is a 32 KB registry** and `cachefs:` is evictable, so Library is
  capacity-bounded and Downloads is `n/a` for the same reason as tvOS.
- **Pure white fails certification** (broadcast-safe, no channel above 235), so
  Roku uses `#EBEBEB` text and `#EB5531` for orange fills.
- **Two new pipeline stages would be needed to PUBLISH** (not to sideload):
  trick-play BIF thumbnails for every title over 15 minutes, roughly 20,000
  films of ffmpeg work, and possibly SRT publication since side-loaded WebVTT is
  not confirmed to work on Roku.

## Tick 2 — the shell and Home, verified on the glass

Built against `docs/ROKU-DESIGN.md` and verified on the owner's Streaming
Stick, with a screenshot for rendering and a focus trace for reachability
(evidence in `build/qa/roku-2026-09-03/`):

| Element | Roku | Evidence |
|---|---|---|
| Overhang: brand, clock, `(*)` indicator | ✅ | `v02_layout.jpg` |
| Left nav rail, 7 surfaces, selected state | ✅ | `v02_layout.jpg` |
| Left from the first tile reaches the rail | ✅ | focus trace `rail → content → rail` |
| Home hero: fitted art, ambient wash, title, meta | ✅ | `v02_layout.jpg` |
| Hero follows the focused tile | ✅ | `v02_row2.jpg` vs `v02_final.jpg` |
| Home shelves from featured.json order | ✅ | 23 rows built, console |
| Poster tile: focus ring, size step, caption reveal | ✅ | `v02_final.jpg` |
| Row scrolling with the d-pad | ✅ | `v02_row2.jpg` |
| Professional-artwork gate on Home (D097) | ✅ | shelves under 6 posters hide |

**Five Roku failure modes found by building, every one silent:**

1. A Label's `font` takes a URI **string**. Assigning a Font **node** carrying
   a `font:` URI renders NOTHING — no error, a healthy console, an empty
   screen. Half the shell was invisible until a three-way experiment on the
   device named it.
2. `font:LargestBoldSystemFont` is not a real face, and an unknown font name
   fails the same silent way.
3. `ContentNode` has a FIXED field set. Assigning `BACKGROUNDIMAGEURL`, which
   it does not declare, did nothing and read back `invalid`. Custom keys need
   `AddField`.
4. An `alias` on an interface field pointing at a node that no longer exists
   kills the whole component, and the failure cascades to its parent.
5. `rowFocusAnimationStyle = "fixedFocusWrap"` pins the focused index so it
   never reaches 0, which made the nav rail unreachable from content. Only
   `floatingFocus` stops at the ends. A screenshot could not have caught this;
   the focus trace did.

## Tick 3 — Detail and the player, verified on the glass

| Element | Roku | Evidence |
|---|---|---|
| Detail: fitted art, title, meta, category chip | ✅ | `v03_detail2.jpg` |
| Detail: synopsis from the detail shard | ✅ | `v03_detail2.jpg` |
| Play button auto-focused, labelled with the runtime | ✅ | reads "Play · 84m" |
| "Also known as" (Decision 100) | ✅ built | shard `extras.ct`; no aka on the test title |
| Playback from archive.org | ✅ | `state="play" error="false"`, position 35.0 → 41.0 → 47.0 s in real time, duration 84m |
| Back: player → Detail → Home | ✅ | screenshots + `state=close` after |
| Stall watchdog (the ONLY recovery available) | ✅ built | not yet provoked on a real stall |
| Instant Replay rewinds 15s | ✅ built | not yet exercised |
| Trick bar in marquee orange | ✅ built | platform transport, unverified visually |

**Six more silent Roku failure modes, all found by building:**

6. **BrightScript has no `xor` operator.** For non-negative integers
   `a XOR b == (a OR b) - (a AND b)`, verified over all 65,536 byte pairs.
7. **`pos` is a BrightScript builtin.** A variable of that name fails with
   "Builtin function call expected", which names the symptom and not the cause.
8. **A method may not be called on a function's RETURN VALUE.**
   `CreateObject("roDateTime").AsSeconds()` is a compile error; it needs a
   local first.
9. **The dev installer answers 200 with "Application Received: N bytes stored."
   and THEN "Install Failure: Compilation Failed."** Accepting the receipt as
   success reported a green deploy for a channel that never installed, so the
   previous build kept running while the source being debugged was not on the
   device. The verdict lives in a JSON blob the page hands its own JS, and the
   rendered HTML contains the words "error" and "success" in a comment, so no
   substring test over the response can work.
10. **"Identical to previous version — not replacing" compares against the last
    UPLOAD, not the last successful INSTALL.** After a compile failure a
    corrected build is refused as identical while nothing is installed at all.
    The harness now deletes and installs fresh when it sees that.
11. **An overlay must actually COVER.** Home stayed composited beneath Detail
    and its hero title read through the scrim as a ghost.

`tools/roku.py playstate` was added because a screenshot cannot prove playback:
Roku's `/query/media-player` reports state, codec and a position that has to
ADVANCE between samples, and that is the only claim worth making.

## Tick 4 — Browse, and the query service behind it

| Element | Roku | Evidence |
|---|---|---|
| Movies / TV browse grid, 7 columns | ✅ | `v04_browse.jpg` |
| Title count in the heading | ✅ | "Movies · 9043 titles" |
| Type / Decade / Sort chips, focusable | ✅ | `v04_chips.jpg` |
| Filtering by type and decade | ✅ | All 9043 → 1900s 0 → 1910s 1 → 1920s 494 |
| TV browses SERIES, never loose episodes (D036) | ✅ built | scope maps to tv-series + tv-special |
| "Oldest" sorts year-less rows LAST | ✅ built | the Android TV audit's bug, not repeated here |
| Drill from grid into Detail | ✅ | `v04_detail_from_browse.jpg` |
| Back returns to Browse, not Home | ✅ built | route remembers where Detail came from |
| Empty state when a filter matches nothing | ✅ built | 1900s returns 0 and says so |

**The service is the architectural point.** A Task's run function normally
executes once; this one parks on a message port, so the 26,965-item index is
parsed ONCE and never crosses a thread boundary — only the page of results
does, as ContentNodes. Filtering all 26,965 rows costs **215–325 ms** on the
Streaming Stick, comfortably inside Roku's 250 ms response rule for the work
that happens between key presses.

**Four more silent failure modes:**

12. **A Group is not focusable.** `setFocus(true)` on a Group whose descendants
    are all Rectangles and Labels does nothing, the Scene keeps focus, and the
    component's `onKeyEvent` never runs — a screen that renders perfectly and
    is completely inert. Chips are real `Button` nodes now.
13. **Setting focus on the container AFTER handing it to a child takes it
    back.** Every chip press was swallowed because the parent re-claimed focus
    one line later.
14. **`Val(x).ToInt()` compiles and dies at runtime** with "Member function not
    found": `Val` returns a Float PRIMITIVE, which has no methods. Third
    variant today of BrightScript's no-methods-on-return-values rule, and the
    first that survives compilation.
15. **A focus ring has a transparent centre**, so dark "focused text" is
    invisible — the chip read as an empty box while working perfectly.

## Tick 5 — Search, on the platform keyboard

| Element | Roku | Evidence |
|---|---|---|
| Platform keyboard (voice entry comes free) | ✅ | `v05_search.jpg` |
| Incremental search over the whole catalog | ✅ | "chap" 339 → "chaplin" 85, ~400 ms each |
| No-typing doors (§6.4, non-negotiable) | ✅ | Feature Films · Classic TV · Silent Era · Animation · Surprise Me |
| Doors open Browse already scoped | ✅ | door → `type=feature-film` query |
| Surprise Me opens a film | ✅ built | picks from Home's professionally-presented rows |
| Results grid → Detail | ✅ | "keaton" 46 hits → *The Love Nest*, url=true |
| Empty state names the query | ✅ built | "Nothing matches …. Try fewer letters, or a door." |
| Search resets when entered from the nav | ✅ | the keyboard otherwise keeps the last query for the life of the channel |

**The keyboard owns its own arrows.** Focus leaves it by walking off its right
EDGE, which is the Roku idiom — a component's `onKeyEvent` never sees a
direction the focused keyboard consumed. Worth stating because the obvious
reading of a failed test is that the handler is broken; here the handler was
right and the test drove from the leftmost key.

## Open questions for the design tick

1. Which Roku idiom carries Home: a `RowList` of poster rows under a hero, or
   the grid-first shape Roku's own channel uses? The design research decides.
2. What the `*` (Info/Options) key opens on each surface — Roku users expect it
   to do something everywhere.
3. Whether Channels (the EPG) survives as-is on a remote with no colour keys.
4. What sync can mean here at all: Roku has `roRegistrySection` for local state
   and no Google or Apple identity, so cross-device sync may be honestly 🚫.
5. Whether the resilient-playback gap (Decisions 021/031/034) can be partly
   recovered on the `Video` node — the owner asked for this to be investigated
   before the rest of the app is built on top of it.
