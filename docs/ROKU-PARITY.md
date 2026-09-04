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

## Tick 6 — Persistence, Library, and the `*` panel

| Element | Roku | Evidence |
|---|---|---|
| Favorites persist across launches | ✅ | Save pressed, channel relaunched, button read "Saved" |
| Resume position persists | ✅ | played to ~34 s, Back, Detail read "Resume · 83m left" |
| Bookmarks written during playback | ✅ | on the watchdog's 5 s tick and again in `stopPlayback` |
| Library: Continue Watching row | ✅ | `v06_library.jpg` — *Dishonored Lady*, its real poster |
| Library: Favorites row | ✅ | same shot, second row |
| Library states the storage budget | ✅ | "1 saved · 1 in progress · N bytes of 32 KB used" |
| Library empty state | ✅ built | names what to press rather than saying "nothing here" |
| `*` opens Options everywhere but playback | ✅ | `v06_options2.jpg`; the key is Roku's during playback |
| TMDb notice verbatim (Decision 007) | ✅ | in the panel, not behind a second screen |
| Sources + donate line | ✅ | same panel |
| Hide watched titles | ✅ | toggled On, Home re-filtered with no reload |
| Autoplay next episode | ✅ persisted | consumed when the episode queue lands |
| Clear Continue Watching | ✅ | Library reloads underneath if it is open |
| Mature-content toggle | 🚫 by design | the web index drops adult items upstream, so a switch here would change nothing |

**Five more silent failures, and the harness was one of them.**

16. **`deploy` reported OK on an installer response it could not parse.** An
    empty message list was read as "no errors". The device ran a stale channel
    for two full test cycles while every deploy printed green — the same
    already-recorded class as the compile-failure-reported-as-success bug, one
    layer up. The deploy now fails unless it sees an explicit success message.
17. **A `<script>` omission is a RUNTIME error, not a build error.** MainScene
    called `awGetSetting` without including `UserStore.brs`; the channel
    installed cleanly and crashed on the first Home paint with "Function is not
    defined in component's namespace". Scripts are per-component: including a
    file in four components does not include it in the fifth.
18. **Writing `true` to a `focusOn` field that is already `true` fires
    nothing.** After the options overlay took focus, every key fell through to
    the Scene and the remote was dead with no error anywhere. Focus is restored
    by toggling false→true, never by re-asserting the value.
19. **Roku's `Button` centres its text against a decorative bullet.** Four of
    them read nothing like a Roku overlay. `LabelList` is the platform's own
    menu control and was the right answer from the start.
20. **A 150 px nav rail clipped "Collections"** — the label ran under the
    content column. Every dimension here is divisible by 3, so the rail is 216.

## Tick 7 — Playback, measured rather than asserted

Deep linking shipped alongside this because a playback harness that drives the
remote is a harness that tests the remote. `contentId` + `mediaType` open a
film directly (Roku's Direct-to-Play requirement), on a cold start through
`Main`'s args and on a warm channel through `roInput`.

**`tools/roku_playback_audit.py`** — the Roku twin of `download_audit.py`. Two
external oracles, never the app's own opinion:

* **ECP `/query/media-player`** for state, error, codec, resolution and a
  position that has to ADVANCE. This matters more here than anywhere else:
  on several Roku SoCs the video plane is not composited into `screencap`, so
  **a screenshot cannot prove playback on Roku** — a playing film photographs
  as a black rectangle.
* **The console on 8085** for the four things ECP cannot see: the link was
  accepted, the shard resolved a url, a bookmark reached a registry no external
  tool can read, and how often the stall watchdog fired.

| Check | What it proves |
|---|---|
| `quiesced` | nothing was playing when the film was requested |
| `accepted` | the channel received the deep link |
| `resolved` | the detail shard returned a playable url |
| `started` | reached `play` within 30s (Decision 077's bar) |
| `advanced` | position strictly increases, at ~1.0x wall clock |
| `no_error` | ECP reported no error during playback |
| `error_shown` | a film that CANNOT play says so on screen |
| `codec` | video and audio codecs and resolution are reported |
| `replay` | Instant Replay rewinds and playback continues |
| `bookmark` | a resume position was written during playback |

**Run of 2026-09-03 — 68 PASS / 3 FAIL / 2 SKIP across 8 films**, one per
content type, sampled fresh each day (breadth over repetition). Start times
2.2–4.6s, realtime ratio 0.98–1.01, zero stalls.

| Film | Type | Start | Codec | Realtime |
|---|---|---|---|---|
| China: The Roots of Madness | newsreel | 3.5s | mpeg4/aac 320x240 | 1.01x |
| The Hottentot | documentary | 2.2s | mpeg4/aac 640x480 | 1.01x |
| El heredero de Casa Pruna | silent-film | 2.2s | mpeg4/**none** 640x480 | 0.99x |
| The Big Bounce | ephemeral | 4.3s | mpeg4/aac 640x480 | 1.01x |
| December (5h recording) | commercial | 4.6s | mpeg4/aac 640x480 | 0.98x |
| Date with the Angels Ep 207 | tv-episode | 4.5s | mpeg4/aac 640x480 | 0.98x |
| Tarzan and the Rocky Gorge | home-movie | 2.2s | mpeg4/aac 320x240 | 0.99x |
| Heart to Heart | short-film | — | — | **DEAD SOURCE** |

*Heart to Heart* is a real catalog defect, not a Roku one: archive.org answers
**401/403** for `cubanc_000437_access.HD.ia.mp4`. Decision 056's class — a
`playbackVerified` that was true when it was taken and is not true now. The
app's job was to say so, and it did not.

**What the audit found in the app**

1. **A film that cannot play said NOTHING.** The viewer pressed Play, the
   screen blinked, and they were back on the same Detail screen. The player
   knew — it had the error code — and kept it in a diagnostic label nobody
   sees. It now hands the failure up and Detail shows it.
2. **`toast` was set by the save path and rendered by NOWHERE.** Every "Saved
   to your library" and every "your library is full" refusal had been
   invisible since it was written. A state the app knows and does not show is,
   to the viewer, a state that does not exist.
3. **A deep link arriving mid-film left the old film playing** under the new
   Detail screen. It now tears the player down first, which also writes the
   abandoned film's final bookmark.
4. **Home stole focus from the player.** A cold-start deep link can reach
   playback before the 26,965-item catalog finishes parsing, and `onStatus`
   called `focusContent()` unconditionally when it did.

**Five ways the harness lied before it worked**, each recorded because the
failure mode is the reusable part:

21. **`<position>37871 ms</position>` carries its UNIT.** `int()` throws on
    that and the code returned None, which reads downstream as "the device
    would not tell us" rather than "the parser is wrong". Every film reported
    an empty position list while playing perfectly.
22. **`/launch` restarts the channel; `/input` does not.** Deep-linking each
    film with `/launch` spent a ~14s catalog parse per film inside a 30s
    deadline, and reported five healthy films as broken. The state trace says
    it plainly: `close -> startup`.
23. **The previous film is still playing when the next link is sent**, so
    `state == "play"` is a false start signal — every film "started" in 0.1s
    and the harness measured the wrong picture. Quiesce first.
24. **`error` is STICKY**: it describes the last media session, so one broken
    film condemned every film audited after it. Errors before and after the
    start are counted separately.
25. **The debug console REPLAYS a backlog when a client attaches**, so
    "is the channel warm" answered yes from a previous run's log line while
    the channel was not running at all. Marks must be taken before the action
    they are meant to witness — and only ONE client can hold 8085, so a
    `roku.py log` running alongside the audit silently starves it.

## Tick 8 — Collections and the Channels guide

| Element | Roku | Evidence |
|---|---|---|
| Collections: 26 curated rows | ✅ | `v08_collections.jpg`; built in **349 ms**, one index pass |
| Collection blurb + accent follow focus | ✅ | "Shadows, second thoughts, venetian-blind lighting." |
| Collection → Detail | ✅ | shared row-select path |
| Channels: 15-channel guide | ✅ | `v08_channels.jpg` |
| Schedule matches the other platforms | ✅ | **SCHED selftest PASS (6/6 vectors)** on the device |
| Times anchored to the viewer's local 6 AM | ✅ | 7:13 PM → 9:18 PM → 10:47 PM, local clock |
| ON NOW marker + minutes remaining | ✅ | "On now: Meet John Doe · 44 min left" |
| Tune in JOINS live | ✅ | joined at **4795 s**, ECP position advancing |
| A channel never writes a resume position | ✅ | `archiveID` is empty for channel playback |
| Future programme → its Detail | ✅ built | nothing to join yet, so Detail is the honest destination |
| Time-proportional EPG grid | ⚠️ deliberate divergence | see below |

**Why the guide is a list and not the grid the other platforms draw.** tvOS,
iOS and web render a proportional two-axis EPG. Roku ships no EPG component,
its remote has no colour keys, and a horizontal time axis needs custom focus
handling that fights the platform's own engine — the exact class of fight that
produced tick 4's unreachable chips. The shape here is the one Roku live-TV
channels actually use: the channel list beside the selected channel's schedule.
The DATA is identical; the presentation is native.

**The scheduler had to be ported exactly, and BrightScript fought it.** The
listings are defined by 64-bit wraparound arithmetic (FNV-1a 64 + SplitMix64),
and BrightScript has no dependable 64-bit integer — `LongInteger` exists but
its multiply overflow is unspecified. A u64 is therefore four 16-bit limbs with
every operation written out. `SchedSelfTest()` checks six known-answer vectors
against values computed independently in Python, runs on every channel load,
and prints one line. It is the only place this arithmetic can be proven right,
since there is no offline BrightScript runner — and it earned its keep three
times in a row:

26. **A constant transcribed wrong is silent.** `0x100000001b3` puts `0x0100`
    in limb 2, not `0x0001`; `0x94d049bb133111eb` puts `0x1331` in limb 1, not
    `0x3331`. Both produce a perfectly plausible hash that matches nothing.
27. **`Int()` converts to a 32-bit Integer**, and a 16×16-bit partial product
    reaches ~4.29e9 — past 2^31. The split has to happen in Double space first.
28. **A bare `1.0` in BrightScript is a FLOAT**, 24 bits of mantissa. So
    `a[i] * 1.0 * b[j]` rounded every product past 2^24 BEFORE it was assigned
    to the Double variable holding it. This is the one that would never have
    been found by reading the code: the high limbs looked right and only the
    low 32 bits were wrong. Every literal now carries the `#` suffix.
29. **`run` is a BrightScript builtin** — `run = prog[2]` fails to compile with
    "Builtin function call expected", the third reserved-word collision in this
    build after `pos` and the `Str()` overload. The compile error names the
    COMPONENT, not the file, so the console on 8085 is the only place the line
    number appears.
30. **Back from a channel had no Detail to return to.** `closePlayer` assumed
    one existed and left the viewer on a blank screen with the rail focused and
    every surface hidden. Where the player was entered from now decides where
    Back lands.

## Tick 9 — Captions, and the rail that collapses

| Element | Roku | Evidence |
|---|---|---|
| Side-loaded subtitles on a progressive MP4 | ✅ | `availableSubtitleTracks=1`, `currentIndex=eng:1:English` |
| WebVTT accepted directly (no SRT conversion) | ✅ | the device took `.../en.vtt` as published |
| The device's caption mode is respected | ✅ | mode read as "Instant replay"; never overridden |
| Viewer told when a film HAS subtitles they cannot see | ✅ built | one line, only when the mode is not "On" |
| Chrome hidden during playback | ✅ | `v09_player.jpg` — full black, no rail |
| Player draws no duplicate transport | ✅ | Roku's own overlay renders the title; OK not consumed |
| Nav rail collapses to 84px, expands on focus | ✅ | `v09_rail_collapsed.jpg` / `v09_rail_expanded.jpg` |
| Content gains the reclaimed width | ✅ | same Home row: **6 posters, was 4** |
| Captions PROVEN to render on screen | ⚠️ unprovable here | see below |

**The one thing this platform will not let a harness prove.** Roku does not
composite the video plane into `screencap`, so a playing film photographs as a
black rectangle and its captions with it. The track being offered and selected
is provable and is proven; the pixels are not. The device's caption mode is
"Instant replay", which correctly suppresses them during normal playback
anyway — an owner eyeball with the mode set to On is the only way to close
this row, and it is recorded as open rather than claimed.

31. **A rail that never collapses costs 11% of the screen.** It was 216 px on
    every surface. Roku's own channels collapse; ours did not, and nobody
    noticed until the owner asked whether it ever collapses.
32. **A duplicate of a platform control loses to the platform's.** The custom
    player HUD was drawn under Roku's own transport overlay the whole time —
    two titles, one of them worse, and only the screenshot showed it.
33. **`roDeviceInfo.GetCaptionsMode()` explains an entire class of "broken"
    subtitles.** Without reading it, a correctly side-loaded track that draws
    nothing looks exactly like a bug in the app.

## Tick 13/14 — Detail's last gaps, and a layout audit

Cast (one line of five names) and "More like this" (12 films sampled by type
and era) close Detail's information gaps. Then the owner reported text overlap
"throughout the app", which is fair: every collision so far had been found by
eye, one at a time, which is exactly why they kept reappearing.

**`awAuditLayout()`** walks the live scene graph, asks every visible Label
where it ACTUALLY is via `sceneBoundingRect()`, and reports two things: any two
Labels whose rectangles intersect, and any Label crossing 1920x1080. It is
triggered on whatever is on screen by the deep link
`contentId=selftest:layout`, so the harness can walk the app and measure each
surface as it arrives.

Home, Detail and Series: **0 findings**. Its real limitation is recorded rather
than hidden: **text drawn by a list — a RowList's own row labels, a tile
component's caption — is not reachable from the Scene's child tree**, so the
audit measures screen chrome and not shelf captions. That half still needs the
glass, and it is where the two defects below came from.

34. **A `fixedFocusWrap` list draws its own contents AGAIN below a divider.**
    A seven-season show read "Season 18, 19, 23, Unsorted" and then "Season 1,
    Season 2" underneath — which looks exactly like duplicate data. Every list
    short enough to fit on screen is now `floatingFocus`.
35. **Raw HTML reaches the screen.** Archive and TVDb descriptions carry
    `<div>`, `<br />` and `&amp;`, and a Label renders them literally: "Family
    Feud S17 E47<div>Aired July 16, 2022". `StripHTML` now sits on every string
    that travels from the network to a Label — and a closed tag becomes a
    SPACE, not nothing, or "one<br/>two" reads as "onetwo".

## Open questions for the design tick

1. Which Roku idiom carries Home: a `RowList` of poster rows under a hero, or
   the grid-first shape Roku's own channel uses? The design research decides.
2. ~~What the `*` key opens on each surface~~ — answered in tick 6: a
   right-anchored Options panel on every surface except playback, where Roku
   reserves the key.
3. Whether Channels (the EPG) survives as-is on a remote with no colour keys.
4. What sync can mean here at all: Roku has `roRegistrySection` for local state
   and no Google or Apple identity, so cross-device sync may be honestly 🚫.
5. Whether the resilient-playback gap (Decisions 021/031/034) can be partly
   recovered on the `Video` node — the owner asked for this to be investigated
   before the rest of the app is built on top of it.
