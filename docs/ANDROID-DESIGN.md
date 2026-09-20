# Archive Watch — Android Binding Design Doc

**Binding.** Quote the rule number before proposing any new screen, route,
sheet, or data path in the Android app (`android/`). If no rule fits, propose
a NEW rule first. Companion to `PARITY.md`, `docs/CATALOG-CONTRACT.md`, and
`docs/MULTIPLATFORM-PLAN.md` §4.3. The two sibling contracts are
`docs/iOS-DESIGN.md` and `docs/WEB-DESIGN.md` — the three share verbs, never
idioms (PARITY "same verb, native idiom"). When a rule below inverts an iOS
or tvOS rule, that inversion is deliberate — do not "harmonize" them.

## §1 Principles

- **§1.1 Android feels like Material** (Decision 028). The feature set
  matches the other platforms; the expression is Material 3 — bottom
  bar/rail, FilterChips, DropdownMenus, Switches, TabRow. Never port iOS or
  tvOS chrome; never invent a custom control where an M3 one exists
  (`native-platform-first`).
- **§1.2 Compose-only, single Activity.** No Fragments, no AppCompat, no
  XML layouts beyond the splash/launcher theme. `minSdk 29`, edge-to-edge.
- **§1.3 One shared data plane** (Decisions 017/028). The phone consumes the
  same `catalog.sqlite` (bundled seed → cached → downloaded `.zz`), the same
  `featured.json`, and the same `series/*.json` as every other client. No
  Android-only catalog reads, hosts, or pipelines — and never re-derive
  `isAdult`, rights, or TV clustering (the contract's one rule).
- **§1.4 Manual DI, plain state navigation.** v1 is a single module with an
  `AppContainer` built in `Application` and a sealed `Route` back stack +
  `BackHandler`. Hilt/Navigation3 arrive only when module count or route
  complexity demands them — propose a rule change first.
- **§1.5 Depth ≤ 2 from any tab root.** Tab → grid/list → detail. A would-be
  third push must be a scope chip, dropdown, or sheet. Player and Settings
  are pushed routes; only the player is immersive.

## §2 Data plane (contract compliance)

- **§2.1 `CatalogDatabase` is the only catalog read path.** It implements
  the query verbs of CATALOG-CONTRACT §5 with the same SQL semantics and the
  four standard filter clauses (adult default-deny per Decision 012, hidden
  types, home gate, notCommercial). Screens never touch SQLite, OkHttp, or
  asset files directly — they go through `AppContainer`'s repositories.
- **§2.2 BundledSQLiteDriver, read paths only.** The bundled driver
  guarantees FTS5; never fall back to framework SQLite for the catalog.
  Decode only the rows a screen shows (Decision 017) — no in-memory catalog.
- **§2.3 The refresh ritual is fixed** (contract §4/§9): ETag-conditional
  GET of `catalog.sqlite.zz` → stream-inflate raw DEFLATE
  (`Inflater(nowrap = true)`, 64 KB chunks) to a STAGING file → ≥10 MB size
  floor → open-probe `meta.itemCount` → atomic rename → store ETag → bump
  `dbVersion`. Any failure keeps the cached DB; the bundled seed is the
  floor state. Never publish-side assumptions: the asset is a rolling
  clobber.
- **§2.4 Screens re-query on `dbVersion`.** Every screen that holds query
  results keys its `produceState`/`LaunchedEffect` on
  `catalog.dbVersion` (and `userState.changes` where user records matter) so
  the seed→full-DB swap and filter changes propagate everywhere.
- **§2.5 Editorial JSON is fetched, not re-hosted**: `featured.json` and
  `series/{slug}.json` from raw.githubusercontent (bundled featured.json as
  offline fallback), series slugs percent-encoded (non-ASCII slugs are real).
  Featured shelves resolve through `item_shelves` (`shelf(id)`) — never by
  browsing a contentType (the duplicate-shelf bug, iOS-DESIGN §5.2).
- **§2.6 User state is local-first**: favorites + watch progress in a tiny
  `user.sqlite` (same bundled driver); scalar settings in DataStore
  preferences with the shared key names (`hideAdultContent`,
  `autoplayNext`). Google Drive App Data sync is the next wave (§7) and
  gates ONLY sync — browse/play always work signed-out.

## §3 Navigation shell

- **§3.1 Five content tabs, hard set: Home · Browse · Channels · Search ·
  Library** (Channels added 2026-06-12 with the EPG port — same top-level
  placement as iOS) via
  `NavigationSuiteScaffold` (bottom bar → rail → drawer by window size — one
  hierarchy, never forked per form factor). Settings is NOT a tab; it lives
  behind the gear in Home's top bar. A fifth tab requires amending this rule.
- **§3.2 One route registry.** Every pushable destination is a case of the
  sealed `Route` (`Detail`, `Series`, `Player`, `Settings`) handled in
  `AppRoot`. New destinations extend `Route` — never a per-screen ad-hoc
  overlay.
- **§3.3 System back pops the stack** (`BackHandler`); tab taps clear it.
  A tv-series item always opens `Route.Series`, anything else
  `Route.Detail` (`Nav.openItem`).
- **§3.4 Deep links land in `DeepLinks.pendingItem`** —
  `archivewatch://item/{id}` (same scheme as tvOS/iOS) is parsed in
  `MainActivity` and consumed once by `AppRoot`. New entry points (App
  Links, App Shortcuts) extend this inbox, never push routes from outside
  the composition.

## §4 Surfaces

- **§4.1 Home order is fixed:** hero carousel (7s auto-advance, professional
  designed art only) → Browse-by-Category tiles (featured.json accents,
  count-gated ≥30) → Continue Watching → featured shelves (in
  featured.json order, deduped downward, dropped under 6 items — the stub
  rule) → Hidden Gems → Public Domain Day (`browse(year = currentYear-95)`)
  → Browse-by-Era tiles LAST (2026-06-11 parity wave; matches the other
  platforms). The Home top bar carries a shuffle action → Surprise grid.
  Inserting a section means amending this rule. Hide-watched (Settings
  toggle) filters completed titles from shelves/gems/PD Day.
- **§4.2 Browse** = scope FilterChips (All/Films/TV/Silent/Animation/Shorts/
  Newsreels/Documentary/Ephemera) + decade, sort, **keyword and studio**
  dropdowns + adaptive `LazyVerticalGrid` with paging-on-scroll (60/page) and
  the REAL total from `browseCount`. The TV scope shows `seriesCards` →
  SeriesDetail. The keyword/studio facets (Decision 046, metadata expansion)
  query the value-indexed `item_keywords`/`item_studios` join tables exactly
  like the genre join — `browse`/`browseCount` gained parallel `keyword`/`studio`
  params, and `topKeywords`/`topStudios` feed the facet menus (count-floored,
  hidden when empty; not offered in the TV scope).
- **§4.3 Search** = debounced (~180 ms) full-text search over the catalog's
  FTS5 index (`search` verb), grid results, explicit empty states.
- **§4.4 Detail** = backdrop header → title/meta → **tagline (italic)** → Play
  + Favorite → synopsis → **rich-metadata rows** (writer / music / cinematography
  / studio / series / awards — Decision 046, each shown only when present) → cast
  row (TMDb `w185` profile URLs per contract §7; `tmdbPersonID` decodes for future
  use — no Callsheet on Android) → More Like This. SeriesDetail is the variant
  with a season dropdown (null season = "More Episodes") and an episode list;
  "X of Y episodes" uses `canonicalEpisodesCount`.
- **§4.5 Library** = Favorites / Continue Watching / Playlists / **Clips**
  tabs over `user.sqlite`. The Clips tab lists saved Clip Studio exports
  (§4.8) and re-shares them; long-press deletes. Empty states are explicit
  sentences, never blank space (`universal-feature-states`).
- **§4.6 Tiles are poster + two text lines, nothing else** (density from
  removing chrome). Poster fallback chain per contract §8: `posterURL` →
  `https://archive.org/services/img/{id}`. Stable `key`s on every
  LazyGrid/LazyRow.


- **§4.6 Channels is a proportional EPG grid** (2026-06-12): sticky ruler
  (LazyColumn stickyHeader), fixed rail, custom Layout placing blocks by
  minute offset × px-per-minute on a 120/180-min window (compact/expanded),
  chevron window paging clamped to the broadcast day, NOW snap-back. Tuning
  pushes the existing Media3 queue player with commercials woven between
  programs, `startPositionMs` join-in-progress, and `persistProgress=false`
  (channel playback never pollutes Continue Watching). The scheduler port
  (`data/ChannelScheduler.kt`) keeps the apps' constants — FNV-1a(channel+
  day) seed, SplitMix64, 6 AM local anchor, per-type runtime defaults,
  2-minute buffer. Never regress the guide to a list.

- **§4.8 Clip Studio is the Create surface** (CREATE-STUDIO-PLAN §5,
  Decision 033) — the Android twin of iOS `ClipStudioView`. A scissors
  "Create" action in the Detail action row (`Icons.Default.ContentCut`),
  **rights-gated on `CatalogItem.isClippable`** (playable video + PD/CC or
  absent `rightsStatus`) and **hidden, not disabled**, when not clippable.
  It pushes `Route.ClipStudio` — a single screen with a Cancel/Done
  lifecycle that runs four phases: prepare (probe the REMOTE stream for
  size/duration), edit (live preview + CapCut timeline + reframe/look/speed/
  caption controls), render (Media3 `Transformer`: `ClippingConfiguration`
  trim → look effects → `SpeedChangeEffect` → `Presentation` reframe →
  `OverlayEffect`/`BitmapOverlay` burning the styled caption + the always-on
  `archivewatch.org · Public Domain` provenance credit), and result (preview +
  Save to `MediaStore.Video` + Share via `ACTION_SEND`/FileProvider). Saved
  definitions persist to the `clips` table (mirrors iOS `VideoClip`) so §4.5
  can re-share. **GIF export is deferred on Android** — there is no native
  GIF encoder; we ship MP4 only (PARITY gap; WebP / vendored encoder later).
  The human makes every editorial choice; never a one-tap auto-edit
  (CREATE-STUDIO-PLAN §1, learning-orientation).
  - **v3 — Stream-not-download + CapCut timeline + styled captions
    (CREATE-STUDIO-PLAN §3/§5b, parity with iOS b44/b45/b46).**
    - **STREAM, DON'T DOWNLOAD.** Archive.org films are hours long / multi-GB,
      so nothing is downloaded. The preview `ExoPlayer`, the filmstrip
      thumbnails, and the `Transformer` source all read the remote URL over
      ranged HTTP via `OkHttpDataSource`. The editor's preview uses a
      controls-free `PlayerView` (`useController=false`); thumbnails come from
      `MediaMetadataRetriever.setDataSource(url, headers)`; the Transformer is
      given a `DefaultAssetLoaderFactory` wrapping a `DefaultMediaSourceFactory
      (OkHttpDataSource.Factory)` so only the ≤60 s clip's sample ranges + moov
      are read. The whole-file `prepareSource` download path is gone
      (`ClipExporter.probeSource`/`streamThumbnails`/`exportVideo(sourceURL)`).
    - **CapCut timeline (`ui/ClipTimeline.kt`, custom `View`).** The filmstrip
      SCROLLS under a FIXED center playhead — scrolling IS scrubbing, and the
      preview seeks to the frame under the playhead live (the screen does a
      tolerant `seekTo` on each `onScrub`; clip BOUNDS stay frame-accurate via
      `Set Start`/`Set End`/handle times). `ScaleGestureDetector` PINCH-zooms
      the pixels-per-second, preserving the centered time; `GestureDetector` +
      `OverScroller` give native momentum scrolling. The selection is a
      highlighted band with drag handles, but the PRIMARY mark is the Compose
      `Set Start` / `Set End` buttons (no two-handle dance). Both ends center
      because the content is conceptually padded by half the viewport. During
      playback the strip auto-scrolls (`follow()`) so the playing frame stays
      under the playhead, stopping at the out point. Tap the preview to
      play/pause the selection. (Built as a raw `View`, not a
      `HorizontalScrollView`, so programmatic `follow()` composes cleanly with
      pinch + handle drags — the same reason iOS owns a raw `UIScrollView`.)
    - **Styled, draggable captions (WYSIWYG).** `CaptionStyle` carries a
      normalized position (drag anywhere — on the video or into the letterbox
      bars), font (`CaptionFont`: Sans/Round/Serif/Mono → `Typeface`), size
      (S/M/L), color (white/yellow/black), and background (shadow/box/plain).
      The live preview is a Compose `Text` over the player, draggable to set the
      normalized position; the burn-in renders the same text to a canvas-sized
      `Bitmap` (`ClipExporter.renderOverlayBitmap`) placed at that position via
      `BitmapOverlay`, so what you place is what burns in. Font/Size/Color/
      Background `SegmentedButton`s appear once a caption exists; the credit
      stays pinned bottom-center.
    - **Font mapping (vs iOS `CaptionFont`):** Sans → `Typeface.DEFAULT` bold;
      **Round → `Typeface.SANS_SERIF` bold** (stock Android has no rounded
      system family — documented divergence; nearest native equivalent);
      Serif → `Typeface.SERIF` bold; Mono → `Typeface.MONOSPACE` bold.
  - **v2 — Looks + Speed (CREATE-STUDIO-PLAN §4, Decision 033 v2).** A color-
    grade **Look** `SegmentedButton` (six options mirroring iOS `ClipLook`:
    None / Silent / Noir / Faded / Technicolor / B&W) and a **Speed**
    `SegmentedButton` (0.5× / 1× / 2×, mirroring iOS), both persisted into
    `ClipSpec` and applied at export. iOS grades with CIFilter chains; Media3
    has no named film presets, so `ClipLook.videoEffects()` maps each look to
    the closest **native `androidx.media3.effect`** effect (no third-party):
    Silent → `RgbAdjustment` warm sepia (red up / blue down); Noir →
    `RgbFilter.createGrayscaleFilter()` + `Contrast` lift; Faded → `Contrast`
    down + `HslAdjustment` desaturate; Technicolor → `HslAdjustment` saturation
    up + slight `Contrast`; B&W → `RgbFilter.createGrayscaleFilter()`. The grade
    is prepended to the video-effects list (graded frames, then reframe +
    overlay — the burned caption/credit stay un-graded, matching the iOS
    two-pass intent). Speed adds a video `SpeedChangeEffect(multiplier)` plus a
    matching `SonicAudioProcessor.setSpeed(...)` audio processor so A/V stay in
    sync. **Deferred vs iOS:** no vignette on the Faded look (Media3 1.9.4 has
    no native vignette effect) and no live grade preview on the editor frame
    (the iOS player-side CIFilter preview has no cheap Media3 analog; the live
    preview plays the un-graded source — the grade applies at export) — both
    noted as PARITY gaps.
  - **Deliberately deferred (best-effort items that need a heavy/cloud dep —
    NOT shipped, by Decision 028's no-heavy-third-party rule):**
    - **Blurred-fill reframe** (iOS uses a CIGaussianBlur composite behind the
      letterboxed frame). Media3 1.9.4 has no built-in scaled-blur-fill effect;
      a correct version needs a custom `GlEffect`/AGSL shader doing a two-layer
      (blurred cover + sharp fit) composite. Deferred to keep the wave native +
      lean; the letterbox matte stays. Tracked as a PARITY gap.
    - **Auto-captions (speech → timed cues).** iOS uses on-device
      `SFSpeechRecognizer` against the clip's extracted audio. Android has NO
      good native FILE-based transcription API — `SpeechRecognizer` is
      microphone-oriented and not designed to transcribe an arbitrary media
      file, and ML Kit / a cloud STT would violate the no-heavy-third-party /
      no-cloud rule. Deferred with this reason; the caption STYLING above
      applies to typed captions regardless. Revisit if a native on-device
      file-transcription API lands (e.g. a future `SpeechRecognizer` file mode
      or an AICore on-device model).

## §5 Player

- **§5.1 Media3 `PlayerView` owns transport.** Full-screen, `keepScreenOn`,
  OkHttp `DataSource` over the shared client, and a patient custom
  `LoadErrorHandlingPolicy` (more retries, modest capped backoff) so
  Archive's idle-connection resets resume from the byte offset instead of
  failing playback — the Android analog of the tvOS `ResilientStreamLoader`
  (Decision 021, plan §3). Paired with a time-prioritized `DefaultLoadControl`
  (min 50s / max 120s, `setPrioritizeTimeOverSizeThresholds(true)`, 30s
  back-buffer) so a high-bitrate progressive MP4 banks deep TIME headroom to
  ride out a reset — `DefaultLoadControl`'s default byte cap banks only seconds
  (cap ~120s avoids the high-bitrate `targetBufferBytes` OOM path). We add
  overlays only; never a parallel transport.
- **§5.2 Never a bitrate ceiling.** `downloadURL` is the highest-quality
  derivative, baked in at build time — no runtime derivative selection.
- **§5.3 Progress persists every 10 s and on dispose**; resume seeks when
  10 s < position < 95% of duration. (Channel lineups, when they arrive,
  must NOT persist progress — iOS-DESIGN §8.4 carries over as a verb rule.)

## §6 Theme

- **§6.1 Always-dark brand theme; dynamic color is NOT the default.** The
  dark canvas (#0A0A0A) is the product — a cinema, not a settings app.
  Material You dynamic color may become a Settings opt-in later; it never
  becomes the default.
- **§6.2 Brand vs semantic split is absolute** (Decision 013): primary
  `#FF5C35` and accent `#0047FF` are chrome/CTA only; per-category accents
  from `featured.json` carry content meaning only. Never a brand color for
  meaning, never a semantic accent for chrome.
- **§6.3 M3 typography styles only** — `headlineSmall`, `titleMedium`,
  `bodyMedium/Small`, `labelMedium/Small` with weight modifiers; six
  hierarchy levels, refuse a seventh (CLAUDE.md density rule).

## §7 Out of scope on Android v1 (intentional — next wave)

Per PARITY and plan §8 P5, these ship later, not never; do not partially
implement them without a rule:

- ~~Channels EPG~~ — SHIPPED 2026-06-12 (§4.6): Kotlin `ChannelScheduler`
  port + Compose proportional guide; user-created channels remain next wave.
- **Cartoon Mode / Public Domain Day explorer** — next wave (the PD Day
  Home shelf §4.1 is the v1 foothold; the Surprise grid SHIPPED 2026-06-11).
- **Party Play / screensaver** — lean-back idioms; tablet-leaning at most.
- **Home-screen widgets (Glance), App Shortcuts / App Actions** — the reach
  wave.
- **Google Drive App Data sync (Sign in with Google)** — the Android/Web
  island (Decision 028 §6); requires the shared OAuth client. Never a custom
  sync backend, never CloudKit.
- **Google Cast** — the AirPlay analog, with the player wave.
- **VHS effect** (AGSL `RenderEffect`) — optional polish, last.
- **Category visibility toggles** — with the next personalization pass.
  (Playlists + watched-hiding SHIPPED 2026-06-11 on the §2.6 store.)

## §8 Parity discipline

- **§8.1** Update `PARITY.md` in the same change set as any user-facing
  feature; proposals/commits quote these rule numbers (e.g. "per
  ANDROID-DESIGN §4.2").
- **§8.2** A feature that exists on tvOS/iOS but lands differently here must
  be the *native Material idiom* of the same verb — name the rule it mirrors
  or deliberately inverts.

## §9 Watch Together Studio (binding; Phase 3)

*Feature rules: `docs/WATCH-TOGETHER.md`. This section says only what is
ANDROID-specific, and every rule is a consequence of §5.1, §6.2 or §8.2
rather than a new idea.*

- **§9.1 The Studio is the PLAYER with overlays, never a second player.**
  §5.1 already says it: "We add overlays only; never a parallel transport."
  Going live adds a program to what is already playing — the same
  `PlayerView`, the same Media3 transport, the same resilient load policy.
  A separate broadcast screen would mean two players, two load controls and
  two progress writers for one film.
- **§9.2 On Android "Watch Together" means the WORLD half only.** There is no
  GroupActivities equivalent, so the private half does not exist here
  (PARITY's SharePlay row: 🚫 on Android). The Detail entry is therefore a
  single item, not the submenu Apple shows — §8.2's rule that a feature
  landing differently must be the native idiom of the SAME VERB, and half a
  verb is not a verb. Do NOT invent an Android "watch with friends" on a
  different transport to fill the gap; that is a separate feature with its
  own decision.
- **§9.2a And the entry appears only where the HOST can be in the show**
  (owner 2026-09-20, Decision 132): `Context.canHostWatchTogether()` requires a
  camera AND a microphone, so **Google TV and Fire TV show no Watch Together
  entry at all** while phones do. The owner's reason is the rule: *"a broadcast
  with no camera and no microphone is not watching together — everyone might as
  well just watch the movie on their own. The point is to stream the video and
  have the ability to provide commentary or conversation on top of it."* The
  test is never "can this device encode" — every box can, which is exactly why
  a television silently offered this for as long as it did. Apply the predicate
  at BOTH entry points in one change; the phone's overflow row and the
  television's button are the same decision. Use `FEATURE_CAMERA_ANY`, not
  `FEATURE_CAMERA` (which means a REAR camera), and do NOT reach for
  `isTelevision()`: the question is hardware, not form factor.
- **§9.2b The host's surface is NOT the program's shape** (2026-09-20, the
  first run on a PHONE). `setVideoSurface` is exclusive, so the engine draws
  the program twice and the host sees the program (Decision 129) — and the
  display pass set `glViewport` to the whole surface. That is right on a
  television, where both surfaces are 16:9, and wrong on a Pixel 8a, where the
  surface is 1080x2400: the program was stretched to 2.22:1 and the owner
  reported the film as *"heavily stretched vertically"*. The display viewport
  is now the program's aspect FITTED inside the surface, centred, surround
  black. The §9 warning that "the viewport belongs to the surface" was already
  written — from the same defect in its other form, the program drawn into a
  corner — and it named 1920x1080 as the host's size, which is how the
  assumption survived.
- **§9.2c The host's screen omits the lower third.** Owner, same run: it *"has
  the overlay which no other interface shows (other than the livestream)"* —
  Android was alone in it, because every other platform lets the host see the
  bare film. The film and the camera tile are what a host needs; the title card
  is furniture for the audience. This gives up Decision 129's *"a host watching
  what their audience is watching cannot be surprised by it"*, and it is one
  boolean (`drawProgram(withOverlay:)`) to put back.
- **§9.2d All five camera placements, not two** (2026-09-20, Decision 131's
  parity rule applied). Android had `layoutShowsCamera` — a boolean and a
  hardcoded corner tile — so `film` and `corner` existed and `theatre`, `side`
  and `host` were offered nowhere. `StudioLayout.kt` is a PORT of the Swift
  `rects(in:cameraAspect:)`, number for number, and `StudioLayoutTest` pins it
  to the values §8.22 printed so the two cannot drift apart silently. The panel
  offers the five as a radio list in the SHARED words (`StudioLayout.label`).
  Two things worth keeping: the rects are a plain `LayoutRect` rather than
  `android.graphics.RectF`, because RectF is a JVM stub and a unit test of it
  throws "not mocked" while every assertion reads 0.0 — geometry two platforms
  must agree on has to be testable without a device; and the camera is
  aspect-FIT inside its rect where Apple crops, which is identical for every
  layout but `host` because each camera rect is derived from the camera's own
  aspect.
- **§9.3 The program panel is a Material bottom sheet**, the native idiom of
  the iOS §4.5 medium-detent sheet (§8.2): layout, the two faders, the cards.
  Not a dialog — the program must stay visible behind it, because changing
  what an audience sees without seeing it is a guess, not a control.
- **§9.4 Health is ALWAYS on screen while live, and outside `PlayerView`'s
  own controls.** Media3's controller auto-hides; health may not
  (`docs/WATCH-TOGETHER.md` §4). It is a surface pinned over the player, and
  it states the one current problem in words — a phone in a stand is not
  being read closely.
- **§9.5 The Studio is a GOOGLE-FLAVOUR feature.** The `amazon` flavour is
  minSdk 23 for Fire TV (Decision 100/115), Fire TV has no camera, and the
  encode path assumes APIs the Google flavour's minSdk 29 guarantees. Gate it
  at the flavour, not with a runtime check that degrades.
- **§9.6 Camera and microphone are asked for AT THE POINT OF GOING LIVE**,
  never at launch and never as a precondition for browsing. A viewer who
  never broadcasts is never asked, which is the same rule §1 applies to every
  other permission — and the Studio runs without either, saying so, rather
  than refusing to start (a paired phone can be asleep; a TV has no camera at
  all).
- **§9.8 ONE show clock feeds BOTH tracks, and the audio clock counts what it
  THREW AWAY.** Video was stamped `frame * 1s / frameRate` — a frame counter,
  which advances per RENDERED frame rather than per elapsed second — while
  audio was stamped from its sample count, which tracks real time. They agree
  only while the renderer holds the nominal rate, and a dongle does not: the
  two tracks drifted **19.6 seconds** apart. Both now count real nanoseconds
  from one `showStartNanos`, and the AAC encoder's clock advances by PCM it had
  to DROP as well as PCM it took, or refused audio becomes permanent lag rather
  than one brief gap (`docs/WATCH-TOGETHER.md` §9.qq).
- **§9.9 The video encoder is CHOSEN, not accepted — and the profile is what the
  codec ADVERTISES.** `MediaCodec.createEncoderByType` returns the first codec
  the platform lists and is not promised to be hardware; on a Google TV dongle
  it returns Android's SOFTWARE AVC encoder, because that device has no
  hardware H.264 encoder at all. Ask for a hardware encoder explicitly with
  `configure` as the test, then request the best profile the chosen codec
  advertises (High → Main → Baseline). **Asking for a profile the encoder does
  not have is silently ignored** — requesting High produced Constrained
  Baseline, no error, identical frame rate. Do NOT gate candidates on
  `isSizeSupported`, which reports false for a size the encoder is demonstrably
  encoding, and do NOT set `KEY_LEVEL`: omitting it lets the encoder pick an
  accurate level (4.1 for 720p30) instead of the over-declared highest it
  advertises (§9.uu, §9.xx, §9.zz).
- **§9.10 The film's audio tap is installed when the PLAYER IS BUILT, never at
  go-live.** A Media3 audio processor belongs to the `AudioSink` chain, which is
  fixed at `ExoPlayer.Builder` time, so a tap attached when a host presses Go
  Live reaches nothing. The previous shape asked for the tap by film id at
  go-live and was called from nowhere, and **every Android broadcast published
  with no audio track at all**. The tap therefore rides every playback and its
  idle path must not allocate (§9.mm).
- **§9.11 Signing in is a QR CODE AND A CODE, shown together, and the token
  lands on THIS device.** Android ships on phones and on televisions, and a
  television has no keyboard — so the sign-in is Twitch's Device Code Grant:
  the screen shows where to go and what to type, the host authorises on their
  phone, and the token is stored here. This is the same conclusion the owner
  reached for tvOS (*"you are logging in on the TV using that other device"*),
  but it arrives here for a different reason: Apple can lean on
  `ASWebAuthenticationSession` handing the session to a nearby iPhone
  (WATCH-TOGETHER §9.yyy), and **Android has no equivalent hand-off**, so the
  device flow is the road rather than a fallback.
  - **Both, always.** The QR is useless to a host whose phone is in another
    room; eight characters read off the screen always work. Neither replaces
    the other.
  - **The QR carries the most complete URI the platform returns.** Twitch's
    `verification_uri` already embeds the user code — measured, twice,
    independently on Apple and on the Google TV dongle — so scanning reaches a
    pre-filled page. Do not assume RFC 8628's optional
    `verification_uri_complete` is present, and do not assume its absence means
    the URI is bare.
  - **Beside the QR, print the short host+path**, never the full URI. A host
    typing it needs `twitch.tv/activate`, and the full string reads as noise
    directly above the code it already contains (the mistake tvOS made first).
  - **The row names the ACCOUNT once signed in**, not just the fact of it.
    "Signed in" is a storage fact; it does not say whose channel a broadcast
    reaches, and it is the host's own name going out.
  - **YouTube is not offered here until it can work.** Android cannot reuse
    Apple's Google client (an iOS-type client is refused by TYPE, measured) and
    needs a "TVs and Limited Input devices" client with a secret. An unreachable
    button is the §10.2b defect; the surface says what is missing instead.

- **§9.7 A live broadcast needs a foreground service with the right TYPES.**
  From Android 14 a service that touches the camera or microphone must
  declare `camera` / `microphone` in `foregroundServiceType`, and the
  notification is not optional. The film is composited from the decoder's
  frames — **never `MediaProjection`** — so the `mediaProjection` type is
  wrong here and asking for it would be asking to screen-record the user's
  device (`WATCH-TOGETHER` §3.3 is absolute on this).
- **§9.12 The mix is TWO CHANNELS on a 0–10 scale, and auto-duck is a
  CONTROL.** The same rule as every other platform — tvOS-DESIGN Rule 8.8c,
  iOS-DESIGN §8.8c, macOS-DESIGN §B13h — because it is a statement about
  people rather than about a platform. Owner, 2026-09-20: *"a scale of 0 to 10
  rather than ... decibles that most people won't understand."*
  **8 is unity**, the source's own level and the default, so a host who never
  opens the panel is already there; 0–8 cuts 5 dB a step to silence and 8–10
  boosts 3 dB a step to +6. `MixLevel` in `studio/StudioAudioMix.kt` is the
  one conversion. **`Slider` is the native control here** — as it is on iOS
  and macOS, and unlike tvOS where it does not exist — so only the SCALE and
  the readout are ours. **The meter reads on the fader's own scale, never
  linearly**: a linear 0–1 meter draws 2% for speech at RMS 0.02 and that is
  how a working microphone reads as a broken one. **Auto-duck is a switch**,
  because otherwise the fader lies — a host who sets Film to 9 and then
  speaks hears it drop 12 dB anyway and reasonably concludes the control is
  broken. The microphone channel and the switch appear only when a voice
  EXISTS; a television says so in words instead (§8.8's rule that an absent
  camera is normal, applied to the panel).
- **§9.13 The voice is mixed INTO the film's buffers; it never drives the
  clock.** `StudioFilmAudioTap` is the timeline. When a film buffer arrives
  the microphone's accumulated samples are added to it in place and the same
  samples with the same timestamps go to the encoder. A mixer pulling both
  sources on its own cadence would be a SECOND clock, and §9.8 is what a
  second clock already cost this platform once. Consequences that follow from
  it, and are not negotiable: the microphone records at the FILM's sample
  rate (mixing is sample-for-sample, so a mismatch pitch-shifts the host, and
  a device that will not do that rate is refused with a sentence rather than
  opened at another); the capture ring is **FIFO** and bounded at **120 ms**,
  because a live voice that arrives late is worse than one with a gap; and
  the sum **CLIPS** rather than wrapping, since an overflowed Int16 flips sign
  and that is a crack on every peak which would be blamed on the encoder.
- **§9.14 `VOICE_COMMUNICATION`, not `MIC`.** On a phone the film plays out of
  the same speakers the microphone is listening to, so a raw `MIC` source
  feeds the film back into the broadcast on top of itself — an echo that gets
  worse with every duck. `VOICE_COMMUNICATION` is the source Android documents
  as carrying acoustic echo cancellation and noise suppression, which is
  exactly this job.
