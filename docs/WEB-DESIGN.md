# Archive Watch — Web Viewer Binding Design Doc

**Binding.** Quote the rule number before proposing any new view, modal, route,
or data path in the viewer (`/watch/`). If no rule fits, propose a NEW rule
first. Companion to `PARITY.md`, `docs/CATALOG-CONTRACT.md`, and
`docs/MULTIPLATFORM-PLAN.md` §4.2. The editorial dashboard (`/index.html`) is a
separate tool with its own conventions (CLAUDE.md) — these rules govern the
**consumer viewer** only.

## §1 Principles

- **§1.1 The web feels like the web.** URL-driven state, shareable everything,
  zero install, works on a phone first. Never port iOS/tvOS chrome.
- **§1.2 No framework, no build step.** Vanilla HTML/CSS/JS served raw by
  GitHub Pages. Revisit only if the viewer passes ~20 components.
- **§1.3 Zero backend.** Static hosting + public CORS APIs only
  (Decision 028). Personalization stays in this browser (IndexedDB).
- **§1.4 Mobile-first.** Every media query is `min-width`. Test 375px before
  1280px.

## §2 Data plane (verified 2026-06-09)

- **§2.1 Browse/search read `catalog-index.json`** (GitHub Pages, CORS ✓,
  popularity-sorted tuples `[id, title, year, contentType, poster, pro, search]`
  — schema 6 (Decision 046); columns are additive, so handle shorter schema-1…5
  rows by treating absent trailing columns as null). Never fetch Release assets
  from the browser (no CORS — verified 206-but-no-ACAO).
- **§2.2 Detail + playback resolve at view time** via `archive.org/metadata`
  (CORS ✓) through `js/api.js` — never `fetch` archive.org endpoints directly
  from view code, and never fetch `archive.org/download/*` with `fetch()`
  (no CORS; verified). `<img>`/`<video>` elements are exempt (no CORS needed).
- **§2.3 Shelves resolve through the index's editorial `shelves` map**
  (schema 3) — the same curated `item_shelves` assignments the apps query.
  Curated shelves may also resolve their explicit `featured.json` items by id.
  **Never compose consumer surfaces from the live Archive scrape API**: a
  2026-06-10 audit showed scrape results bypass the rights audit (Decision
  027) and adult filter (Decision 012) — copyrighted and adult titles surfaced
  on Home — and every `-downloads` shelf returned one identical list. An
  empty/missing shelf renders nothing (never an error card on Home).
- **§2.4 Detail + playback come from the catalog's own detail shards**
  (`details/{00..ff}.json` on Pages, built by `tools/build_web_details.py`,
  FNV-1a low-byte sharding — keep the JS `Details.shardOf` and the Python
  hash in sync). Each record carries the build-time picked `downloadURL`,
  curated synopsis, director, cast, genres, runtime, backdrop. The
  archive.org metadata API is the FALLBACK only (new items not yet sharded),
  always bounded by `AbortSignal.timeout` — measured 2026-06-10: that
  endpoint can hang 30s+ on items we play fine (the baked downloadURL is
  the truth; never make it a runtime dependency).
- **§2.6 Rich metadata rides the existing two files (Decision 046, schema 6).**
  The flat index has no FTS5/join tables, so the web's analog of the apps'
  FTS + keyword/studio join tables is a 7th index column `search` — a
  lowercased space-joined blob of keywords + AKA/original titles + writer +
  studios, null on unmatched films — that the client-side Search box and the
  Browse keyword/studio filters match as a substring (no per-row id map keeps
  the committed index lean; long-tail values stay reachable via free-text
  search). A top-level `facets` object (`{keywords[], studios[]}` — most-common
  names) drives the Browse filter dropdowns. Detail-only fields (writer,
  studios, franchise, tagline, awards, composer, cinematographer, releaseDate,
  originalTitle, cast `tmdbPersonID`) ride the detail shard record at a new
  index-9 `extras` object (present keys only, omitted when empty) + a 3rd cast
  slot. Both are additive — older readers ignore column 6, `facets`, and
  `extras`.
- **§2.5 The upgrade path is chunked SQLite over Pages.** GitHub Pages serves
  `206 + Access-Control-Allow-Origin: *` on GET (verified 2026-06-09 — the
  2026-06-02 "no 206" measurement was a HEAD artifact). When FTS5-grade search
  or enriched detail is needed, deploy a slim chunked `catalog.sqlite` via an
  Actions-based Pages deploy (no git commit — Decision 018) and query with
  `sql.js-httpvfs`. Until then the index + detail shards are the only catalog the browser loads.

## §3 Routing + URL state

- **§3.1 Hash routes**: `#/`, `#/browse`, `#/search`, `#/library`,
  `#/item/{id}`, `#/about`. Filters live in the hash query
  (`#/browse?type=animation&decade=1930&sort=az`) so every filtered view is a
  shareable URL.
- **§3.2 Canonical share URLs are paths**, `/item/{id}` — the
  exact URLs the iOS/tvOS Share buttons emit. `404.html` forwards them into
  the hash router. Never change this shape; shipped apps depend on it.
- **§3.3 One router.** `route()` reads the hash, `showView(name)` toggles
  `<section hidden>`. Per-view `IntersectionObserver`s are disconnected on
  every view switch.

## §4 Surfaces

- **§4.1 Home** = the Marquee hero + Browse-by-Category accent tiles
  (count-gated ≥30, featured.json accents) + featured shelves + Hidden Gems
  (designed art from the popularity tail) + Public Domain Day (year =
  currentYear−95) + Browse-by-Era tiles LAST (the apps' Home order,
  2026-06-11 parity wave)
  (horizontal scroll-snap rails). Order follows `featured.json`; items are
  **cross-shelf deduped** (first shelf claims the item — the apps' Home rule),
  shelves under 4 items are dropped, and the hero pool (top-300) and every
  shelf are **shuffled fresh per visit** — Home is never the same twice
  (owner direction 2026-06-10; deliberately fresher than the apps' daily
  rotation). **Home admits PROFESSIONAL artwork only** (the index's `pro`
  flag — designed posters, never generated frame covers or archive thumbs);
  **TV shelves surface SERIES cards** (TVDB/TVmaze posters, decade parsed
  from the shelf id, tap → episodes) instead of frame-grab tv-specials.
  Shelves that can't field 4 professional posters fall off Home (their
  titles remain in Browse/Search) — Editor's Picks included, until its
  picks carry designed art. **Home shows designed artwork ONLY** — the front
  door is curated visuals; archive-thumb items remain fully reachable in
  Browse/Search (owner direction, 2026-06-10).
- **§4.2 Browse** = type chips + decade/keyword/studio/sort selects +
  infinite-scroll grid (IntersectionObserver sentinel, 60/page). The full count
  is always shown. Keyword + studio filters (Decision 046) are `kw`/`studio`
  hash params matched against the index `search` column (§2.6); their dropdowns
  come from the index `facets`.
- **§4.3 Search** is client-side over the index (all terms must match the
  title OR the `search` column — keywords/AKA/writer/studio per Decision 046,
  §2.6), debounced 180ms, capped at 200 results, query mirrored to the URL.
- **§4.4 Detail** renders instantly from the index row, then hydrates
  synopsis/cast/runtime/playability from its detail shard (§2.4; metadata
  API fallback). When present it also surfaces the tagline (under the title)
  and a facts list — writer / composer / cinematography / studio / series /
  original title / awards (Decision 046, §2.6); studio + series link back into
  Browse/Search so a fact is a door to more. Errors are visible inline
  (never console-only), and the archive.org source link is always present.
  On iOS/Android user agents an **Open in app** action appears: the
  `archivewatch://` scheme on Apple, an `intent://` URL with this page as
  the fallback on Android. Universal Links take over on iOS once the
  Associated Domains capability lands (Decision 030).
- **§4.5 Library** = Continue Watching (progress 10s–95%) + Favorites, both
  IndexedDB. Empty states are explicit sentences, not blank space.
- **§4.6 Modals use `<dialog showModal>`** — the player and the Detail
  share menu (Open in app / Share link / archive.org — keeps the action row
  to Play · ♡ · Share) are the only modals.
  No `position: fixed` overlays (Safari compositor rule).
- **§4.7 The Marquee hero** is a native scroll-snap carousel whose every
  dimension is a `clamp()` in container-query units (`cqi`) — it scales
  CONTINUOUSLY with its container, no breakpoint jumps. Composition per
  slide: ambient blurred-poster layer (key art is never hard-cropped into a
  banner) + sharp 2:3 poster + eyebrow/serif-title/meta/CTA copy block. The
  display serif is a SYSTEM serif stack (§6.2 still binds — no webfonts).
  Auto-advance pauses on hover/touch + hidden tabs and is disabled under
  `prefers-reduced-motion` (which also stops the ambient drift). Dots are
  real buttons with tab semantics, synced from scroll position.
- **§4.8 TV series** route is `#/series/{slug}` (strip the `series:` id
  prefix; `encodeURIComponent` the slug — non-ASCII slugs exist). The spine
  loads from Pages `series/{slug}.json`; episode rows render synchronously
  (never gated on storage) and play their `downloadURL` directly; resume
  badges hydrate from IndexedDB afterward. Old `#/item/series:*` links
  redirect here.


- **§4.9 Surprise** (`#/surprise`, topnav): a re-rollable grid — one random
  designed-art pick per content type plus popular extras, fresh per visit
  (2026-06-11 parity wave).
- **§4.10 Playlists** live in IndexedDB (`playlists` store, schema v2):
  Detail "＋ Playlist" opens the add/create dialog; Library lists playlists →
  `#/playlist/{id}` grid with delete. Same verb as the apps; Drive sync joins
  later (Decision 028 §6).
- **§4.11 Episode binge**: playing an episode passes the season's playable
  queue; `ended` auto-advances to the next episode (the apps' auto-advance).
- **§4.12 More Like This** on Detail: same type, ±15 years, designed art,
  shuffled 12 (index approximation of the apps' related query).

- **§4.13 Channels** (`#/channels`, topnav): a true TV listing — the scroll
  container pins BOTH axes with CSS sticky (rail `left:0`, ruler `top:0`;
  rows/ruler are `width: max-content` so the sticky containing box spans the
  full strip). Pools come precomputed from `channel-pools.json`
  (`tools/build_channel_pools.py`, refreshed by publish-db — the index has no
  runtime/genre); the SCHEDULE is computed in the browser by the JS
  `Scheduler` (FNV-1a + SplitMix64 BigInt port, 6 AM LOCAL broadcast-day
  anchor, the apps' runtime defaults + 2-min buffer). Tuning builds the
  binge queue from the tapped slot with commercials woven between programs,
  joins live slots in progress (`startAt`), and never persists resume
  progress (`persist:false` — the apps' channel rule).

## §5 Playback

- **§5.1 Native `<video controls playsinline>`** in the player dialog. The
  browser's ranged GETs handle seeking; PiP/AirPlay come free from the UA.
- **§5.0 Web behaviour is locked by `tools/test_web.sh`.** Five suites, each
  reading its function out of the SHIPPED `watch.js` so a test cannot drift
  from what runs, plus a parse check and a CSS brace check (appending to a
  stylesheet with `cat >>` silently drops every rule after a truncation). Run
  it before any web commit. Each suite exists because a real defect got
  through: a Fire visitor sent to Google Play, doubled PiP and speed controls,
  a search chip that led to an empty grid, a poster fetched at w780 for a 230px
  box, and a search box that could not find an actor. Every one of those is
  invisible in a screenshot.
- **§5.1a Our chrome never repeats a native control.** Because §5.1 hands the
  browser its own control bar, a control we draw beside it is a SECOND copy —
  the owner reported exactly this on iPad and Mac ("picture-in-picture and
  speed controls... it can get confusing with doubled up controls"). The bar's
  contents differ per engine and are MEASURED, never assumed: Chrome's overflow
  menu carries Captions and Playback speed but has no PiP button (right-click
  only); Safari's bar carries a PiP button and a settings menu with speed;
  Firefox has neither as a bar control. `nativeControlSet()` is the single
  place that decides, it is pure so engines this machine cannot run are still
  testable, and `tools/test_native_controls.mjs` locks the matrix. Our bar
  keeps only what no engine provides: title, close, Cast, and the film-level
  actions. A control that has no native counterpart must not IMITATE one
  either — the Cast button is the word "Cast" because the glyph it used is the
  fullscreen glyph, which read as a second fullscreen button.
- **§5.1b A preference the viewer sets natively is still a preference.** Speed
  persists via a `ratechange` listener rather than via our own control, so
  hiding that control does not silently force the stored rate back on the next
  film.
- **§5.2 Reconnect wrapper** (the Decision 021 analog): on `error`, persist
  position, reload `src`, re-seek, replay immediately. On a `waiting` STALL,
  recovery is two-stage and buffer-preserving (`onStall()`): if bytes are still
  arriving (networkState LOADING + buffered end advancing) wait; else try a
  cheap nudge (`currentTime += 0.1` + play) that un-sticks a transient underrun
  WITHOUT dropping the buffer or paying a fresh 302; only if still stalled after
  ~4s fall through to the full `src`-reset. A full reset discards the whole
  buffer, so never do it on every 12s stall. Surface a visible retry message
  only if the re-play fails.
- **§5.3 Progress persists every 10s** and on close/end to IndexedDB; resume
  seeks when 10s < position < 95%.
- **§5.4 Video is never cached** by the service worker.

## §6 Look

- **§6.1 Dark theater canvas** (`#0A0A0A`), brand chrome per the shared
  system: `--color-primary #FF5C35` for CTA/chrome only, `--color-accent
  #0047FF` for links. Semantic category accents are reserved for content
  meaning (Decision 013) — don't repurpose them as chrome.
- **§6.2 Density from removing chrome**: cards are poster + two text lines,
  nothing else. System font stack; no webfonts (no build step, no FOUT).
- **§6.3 Posters are 2:3** `object-fit: cover`, falling back
  index-poster → `services/img/{id}` on error, with the whole chain retried
  up to twice on jittered backoff (`wireArt`) — archive.org throttles image
  bursts with transient 503s, so a one-shot fallback left tiles broken until
  a manual refresh. When nothing fetchable remains, render the local
  typographic placeholder card (`card-ph`, serif title + Decision-013 accent
  bar), never the Archive's generic gray placeholder. `series:` ids are NOT
  archive.org items — never request `services/img/series:*` (it returns that
  generic placeholder); a poster-less series card goes straight to the
  typographic card.

## §7 PWA + offline

- **§7.1 Installable** from `/watch/manifest.json` (scope `/ (site root)`).
- **§7.2 Service worker**: shell cache-first; `catalog-index.json` +
  `featured.json` network-first with last-good fallback; archive.org requests
  pass through untouched.
- **§7.3 Offline = open + browse cached catalog.** Playback offline is out of
  scope (streams only).

## §8 Attribution + values

- **§8.1 The TMDb verbatim notice** ("This product uses the TMDB API but is
  not endorsed or certified by TMDB.") lives on `#/about`, reachable from the
  persistent footer (Decision 007). Donate-to-Archive link rides with it
  (Decision 010).
- **§8.1a One app banner, and only where the platform has none.** iOS gets
  Safari's native Smart App Banner from the `apple-itunes-app` meta (retargeted
  per route so "Open" deep-links to the film). Android and Fire have no
  equivalent, so `showAppBanner()` renders the counterpart — and ONLY there:
  never on iOS (it would double Safari's) and never on desktop. It links to the
  STORE, because a page cannot detect an installed app and Play/Amazon already
  say "Open" when it is. Fire is tested BEFORE Android — a Fire UA contains
  "Android", so the naive order sends every Fire visitor to Play where the app
  cannot be installed (`tools/test_app_banner.mjs` locks this). Dismissal is
  permanent: an install offer that returns is a nag, which the CLAUDE.md
  four-question test rules out.
- **§8.2 No tracking, no analytics, no third-party scripts.** State never
  leaves the browser.
- **§8.3 Mature filtering is upstream, by ONE predicate** — every artifact
  the viewer reads (`catalog-index.json`, `details/` shards,
  `episodes-index.json`, `aliases.json`) is built with `build_sqlite._is_adult`,
  the same function the apps' default-off setting uses (Decision 105). The
  viewer adds no mature toggle. A builder that re-implements the rule drifts:
  on 2026-09-10 the shards carried their own looser copy, the episode index had
  no gate, and the alias map forwarded saved ids to mature survivors —
  `tools/test_web_adult_gate.py` locks the shared rule.
- **§8.4 Sign-in controls are the providers' own.** Google: a custom button
  built to Google's branding guidelines (the four-colour G at 20px, "Sign in
  with Google", Roboto Medium 14px, 40px tall, the dark theme on this dark
  page; the logo inline so §8.2 holds). Apple: CloudKit JS draws Apple's own
  button, asked for the white theme Apple's HIG prescribes on a dark
  background, never restyled. Both rows align at 40px with the sync status
  beside, and keep the page gutter (`margin: … var(--pad)`).
- **§8.5 The persistent footer is one line on a phone.** `body` is a
  fixed-height column (the Safari rule), so the footer is always on screen;
  below 640px only the "Get the app" label remains, linking to About where
  every store is listed, and the row is `nowrap` with overflow hidden so it
  can never grow. The device links return at width. Measured 2026-09-10: four
  device links wrapped to five rows and took a third of an iPhone screen.

## §9 Parity discipline

- **§9.1** Update `PARITY.md` in the same change set as any user-facing
  feature; quote these rule numbers in proposals.
- **§9.2 Out of scope on web v1**: Channels EPG (needs runtime+type for the
  whole pool — arrives with §2.4), Cartoon Mode, Surprise grid (needs genre
  facets), Google Drive sync (Sign in with Google — planned island per
  Decision 028 §6), autoplay/continuous play.

## §10 Traps this codebase has already paid for

Each of these produced a real defect on 2026-09-07. None of them fails
loudly, and none is visible in a screenshot — which is why they are written
down rather than left to be re-learned.

- **§10.1 Bump `SHELL` in `sw.js` on EVERY web change.** The service worker
  re-registers on load and serves its cached shell, so an unbumped deploy
  reaches nobody. Verifying a change locally needed the cache cleared three
  times before new markup appeared, and `fetch(url, {cache:'no-store'})` does
  NOT bypass a service worker — a fetch that looks like it proves the server
  is wrong may be the worker answering.

- **§10.2 An author `display` beats the UA's `[hidden] { display: none }`.**
  `.thing { display: flex }` on an element you toggle with `hidden` leaves it
  on screen: the app banner shipped a 19px empty bordered strip on every
  desktop page this way. State the display on `.thing:not([hidden])` rather
  than reaching for `!important`.

- **§10.3 Turning an element into `<a>` inherits the bare `a` rule.** Cast
  bubbles became links and every name went accent-blue and underlined on a
  dark page. A link that is not shaped like a link needs `color: inherit;
  text-decoration: none`, with the affordance moved to `:hover`/`:focus-visible`.

- **§10.4 A one-shot render must replace before it appends.** `Home.render()`
  was guarded by a `rendered` flag and only ever appended. The first thing
  that re-rendered it stacked the page — 28 sections to 81, 360 cards to 1021
  — with the stale copy still showing what the new filter had removed.

- **§10.5 A facet must be computed against the other facet's selection.**
  Search chips built from the whole result set promise combinations that do
  not exist; five decade chips emptied the grid once a type was chosen. The
  property to assert is "no offered chip yields zero rows", not "the chips
  look right" (`tools/test_search_facets.mjs`).

- **§10.6 One rule, one function.** Where two callers implement the same rule
  they drift: the category tile row counted documentary specially and the
  preferences list did not, so Documentary had a tile that could not be
  switched off. `categoryCounts()`, `relatedRows()`, `nativeControlSet()` and
  `searchFacets()` all exist because of this.

- **§10.7 Check what exists before building it.** Web `<track>` subtitles were
  fully shipped — blob fetch, WEBVTT validation, SRT conversion, Cast
  carry-over, 5,027 items — while PARITY said they were pending. Read the code
  before believing a status column, in either direction.

- **§10.8 Read `PARITY.md` columns from the HEADER.** A markdown row's
  `split("|")` has a LEADING EMPTY element, so `parts[4]` is macOS and
  `parts[5]` is Web. Four edits silently overwrote the macOS column. Nothing
  fails — the table still renders and the wrong cell reads as fact.

- **§10.9 Trust the instrument only while it is sane.** A Chrome window
  collapsed to zero width reported a banner as 26x282 and a page header as
  32px; `resize_window` returned success twice without changing anything.
  Layout numbers from a zero-width viewport are meaningless, while DOM
  structure queries (counts, classes, attributes) stay valid — prefer those
  when the window is suspect, and never "fix" CSS to satisfy a broken
  instrument.

## §11 What GitHub Pages can still do, and what we deliberately did not take

A research pass on 2026-09-07, prompted by "push the limits of what is
possible with GitHub Pages web apps". Pages serves static files with gzip and
Range support and nothing else, so every item here is a browser capability,
not a server one.

**Taken:**

- **View Transitions** (`document.startViewTransition`) on route changes —
  most of what makes a hash-routed page feel like an app rather than a
  document, at ~15 lines and zero build. Skipped entirely under
  `prefers-reduced-motion`, in JS as well as CSS, because a media query
  cannot cancel a snapshot that has already been taken.

**Already shipped, and checked before rebuilding** (each of these was assumed
missing at some point today and was not): the Web Share API with a clipboard
fallback, `<track>` subtitles from same-origin blobs, MediaSession, PiP,
IndexedDB persistence, container queries on the Marquee hero, and the
service-worker offline shell.

**Deliberately NOT taken, with reasons:**

- **`content-visibility: auto` on shelves.** Home is 28 sections and ~10,400px,
  so skipping off-screen layout is the textbook win. Not applied because the
  shelves carry IntersectionObserver-driven paging and scroll anchoring, and
  the browser window available at the time reported a zero-width viewport —
  applying a rendering optimisation that cannot be MEASURED is how you ship a
  regression that looks like a speed-up. Revisit with real timings.
- **Speculation Rules (prerender).** They pay off across documents; this
  viewer is one document with hash routes, so the only candidates are the
  ~27,000 generated share pages, which already redirect immediately.
- **Background Sync / Periodic Sync.** Support is one engine deep, and the
  work they would do (refreshing a catalog index) is what the service worker's
  stale-while-revalidate already does on the next visit.

## §12 Cold-load weight — measured, with the next moves ranked

Measured against the LIVE site on 2026-09-07, because this is what a visitor
arriving from a social post on a phone actually pays.

A first paint downloads **2.38 MB**, and 98% of it is one file:

| file | over the wire |
|---|---|
| `catalog-index.json` | 2.33 MB (gzip; 7.16 MB raw) |
| `watch.js` | 31 KB |
| `watch.css` | 7 KB |
| `index.html` + `api.js` + manifest | 8 KB |

Two facts settled by measurement, so nobody re-tests them:

- **GitHub Pages does not serve brotli.** `Accept-Encoding: br` alone returns
  the file UNCOMPRESSED at 7.16 MB; only gzip is negotiated. Client-side
  brotli is not a way out either — `DecompressionStream` supports gzip and
  deflate, not brotli.
- **Repeat visits are already cheap.** `cache-control: max-age=600` plus an
  ETag, and a conditional request answers **304 with 0 bytes**. The cost is
  the FIRST visit only; do not spend effort on repeat-visit caching.

Where the index's 2.30 MB of gzip actually goes:

| field | gzip | share |
|---|---|---|
| poster | 0.61 MB | 26.4% |
| search | 0.47 MB | 20.3% |
| id | 0.37 MB | 16.1% |
| title | 0.34 MB | 14.8% |
| backdrop | 0.10 MB | 4.5% |
| director | 0.08 MB | 3.4% |
| everything else | 0.33 MB | 14.5% |

**Ranked next moves, none taken yet — each needs a live browser to verify and
the only one available reported a zero-width viewport:**

1. **Move the `search` blob to a lazily-fetched sidecar** (the `aliases.json` /
   `people.json` pattern, Decision 085). It is used only by Search and by
   Browse's keyword/studio chips, so most visitors never need it: −0.47 MB,
   a 20% cut to first paint. Key it by archiveID rather than by row position —
   positional coupling between two separately-cached files is a silent
   corruption waiting for a partial cache.
2. **Template the poster URLs.** They are overwhelmingly
   `https://image.tmdb.org/t/p/w500/<hash>.jpg`; storing a one-character source
   code plus the hash would take a large bite out of 0.61 MB. Pure encoding,
   round-trippable, testable in node.
3. **`content-visibility: auto` on shelves** — see §11 for why it was refused
   without measurement.

Do not chase 3 before 1: the render cost of a 28-shelf page is invisible next
to 2.3 MB on a phone connection.

