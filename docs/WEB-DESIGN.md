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
  ~2.7 MB, popularity-sorted tuples `[id, title, year, contentType, poster]` —
  schema 2; handle 4-field schema-1 rows). Never fetch Release assets from the
  browser (no CORS — verified 206-but-no-ACAO).
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

- **§4.1 Home** = the Marquee hero + featured shelves
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
- **§4.2 Browse** = type chips + decade/sort selects + infinite-scroll grid
  (IntersectionObserver sentinel, 60/page). The full count is always shown.
- **§4.3 Search** is client-side over the index (all terms must match the
  title), debounced 180ms, capped at 200 results, query mirrored to the URL.
- **§4.4 Detail** renders instantly from the index row, then hydrates
  synopsis/cast/runtime/playability from its detail shard (§2.4; metadata
  API fallback). Errors are visible inline
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

## §5 Playback

- **§5.1 Native `<video controls playsinline>`** in the player dialog. The
  browser's ranged GETs handle seeking; PiP/AirPlay come free from the UA.
- **§5.2 Reconnect wrapper** (the Decision 021 analog): on `error`, or
  `waiting` > 12s, persist position, reload `src`, re-seek, replay. Surface a
  visible retry message only if the re-play fails.
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
- **§8.2 No tracking, no analytics, no third-party scripts.** State never
  leaves the browser.
- **§8.3 Adult filtering is upstream** — the index is already filtered
  (`adultCollections` + rights `excluded`, Decisions 012/027). The viewer adds
  no mature toggle until a full-catalog data layer exists (§2.4).

## §9 Parity discipline

- **§9.1** Update `PARITY.md` in the same change set as any user-facing
  feature; quote these rule numbers in proposals.
- **§9.2 Out of scope on web v1**: Channels EPG (needs runtime+type for the
  whole pool — arrives with §2.4), Cartoon Mode, Surprise grid (needs genre
  facets), Google Drive sync (Sign in with Google — planned island per
  Decision 028 §6), autoplay/continuous play.
