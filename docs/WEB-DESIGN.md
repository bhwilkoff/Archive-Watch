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
- **§2.3 Shelves come from `featured.json`**: curated → index lookup; dynamic →
  Archive scrape API, cached in `sessionStorage` for 1h. A failed shelf renders
  nothing (never an error card on Home).
- **§2.4 The upgrade path is chunked SQLite over Pages.** GitHub Pages serves
  `206 + Access-Control-Allow-Origin: *` on GET (verified 2026-06-09 — the
  2026-06-02 "no 206" measurement was a HEAD artifact). When FTS5-grade search
  or enriched detail is needed, deploy a slim chunked `catalog.sqlite` via an
  Actions-based Pages deploy (no git commit — Decision 018) and query with
  `sql.js-httpvfs`. Until then the index is the only catalog the browser loads.

## §3 Routing + URL state

- **§3.1 Hash routes**: `#/`, `#/browse`, `#/search`, `#/library`,
  `#/item/{id}`, `#/about`. Filters live in the hash query
  (`#/browse?type=animation&decade=1930&sort=az`) so every filtered view is a
  shareable URL.
- **§3.2 Canonical share URLs are paths**, `/Archive-Watch/item/{id}` — the
  exact URLs the iOS/tvOS Share buttons emit. `404.html` forwards them into
  the hash router. Never change this shape; shipped apps depend on it.
- **§3.3 One router.** `route()` reads the hash, `showView(name)` toggles
  `<section hidden>`. Per-view `IntersectionObserver`s are disconnected on
  every view switch.

## §4 Surfaces

- **§4.1 Home** = hero (designed-art pool, 7s rotate) + featured shelves
  (horizontal scroll-snap rails). Order follows `featured.json`.
- **§4.2 Browse** = type chips + decade/sort selects + infinite-scroll grid
  (IntersectionObserver sentinel, 60/page). The full count is always shown.
- **§4.3 Search** is client-side over the index (all terms must match the
  title), debounced 180ms, capped at 200 results, query mirrored to the URL.
- **§4.4 Detail** renders instantly from the index row, then hydrates
  description/playability from the metadata API. Errors are visible inline
  (never console-only), and the archive.org source link is always present.
- **§4.5 Library** = Continue Watching (progress 10s–95%) + Favorites, both
  IndexedDB. Empty states are explicit sentences, not blank space.
- **§4.6 Modals use `<dialog showModal>`** — the player is the only modal.
  No `position: fixed` overlays (Safari compositor rule).

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
  index-poster → `services/img/{id}` on error.

## §7 PWA + offline

- **§7.1 Installable** from `/watch/manifest.json` (scope `/Archive-Watch/watch/`).
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
