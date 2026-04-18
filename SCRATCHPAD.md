# Project Scratchpad — Archive Watch

## Current State

- **Status**: M0 mostly done — Xcode project creation is the only blocker. Editorial pipeline, What's New ticker, app icon master, tvOS integration plan, seed catalog pipeline all shipped.
- **Active milestone**: M0 → M1
- **Last session**: 2026-04-19 — categorization schema (collection registry), seed catalog generator (browser), SeedCatalog Swift loader, first-launch prime wiring
- **Next actions**:
  1. **(Owner, any device)** Push to GitHub Pages (Settings → Pages → main branch root) so the dashboard + build-catalog + what's-new ticker are live
  2. **(Owner, any device)** Once live, open `build-catalog.html` on your phone or laptop, paste your TMDb v4 bearer token, hit Build. Download the resulting `catalog.json` and commit it to the repo root.
  3. **(Owner, at desk)** Create Xcode tvOS project at repo root (Product Name: `ArchiveWatch`, no spaces, tvOS 17+)
  4. Move Swift files from `ios/` into the Xcode-created `ArchiveWatch/` group, then delete `ios/`
  5. Add `catalog.json` and `collections.json` to the app bundle as resources (copy to bundle root; SeedCatalog + CollectionRegistry read them via `Bundle.main`)
  6. Create `Secrets.xcconfig` (gitignored) with `TMDB_BEARER_TOKEN`
  7. Run `tools/validate-pipeline.sh --tmdb` to sanity-check TMDb match rate
- **Open questions** (resolved):
  - Adult content filtered by default? **Yes** — Decision 012
  - Per-category accent colors? **Yes** — Decision 013
  - Random actions in M1? **Yes** — Decision 014
  - App icon direction? **Photographic film frame on bold category color** — see `docs/design/app-icon.md`
  - Serif body type? **Yes — stylized + bold** (Fraunces in dashboard; New York or similar on tvOS, prototype on panel)
- **Open questions** (still open):
  - Which still goes in the v1 app icon? Méliès moon recommended; needs owner sign-off
  - Silent preview loop on Detail focus — ship without, or generate 10s clips server-side via GitHub Actions?

---

## Scope Note

Archive Watch is a **tvOS-first** app (see Decision 006). The `index.html`
/ `css/` / `js/` scaffold is retained only as the future editorial
dashboard for curating `featured.json`. The Dual-Platform Feature Parity
Model does not apply here.

---

## Milestones

### M0 — Project Setup
- [x] Research docs (`docs/research/metadata-sources.md`, `docs/research/design-reference.md`, `docs/research/tvos-home-screen-integration.md`)
- [x] Architecture decisions logged (DECISIONS 006–015)
- [x] Networking + model scaffold in `ios/`
- [x] CLAUDE.md identity filled in
- [x] `featured.json` seed (curated picks + dynamic shelves + categories)
- [x] Editorial dashboard (replaces template `index.html`; doubles as live pipeline validator)
- [x] What's New curation ticker (`whats-new.html`) with seen-tracking + dashboard handoff via localStorage
- [x] `tools/validate-pipeline.sh` (CLI smoke test for the cascade)
- [x] App icon spec (`docs/design/app-icon.md`) + master SVG (`assets/app-icon/icon-1024.svg`) + Méliès moon (`assets/app-icon/melies-moon.svg`) + multi-size preview page (`assets/app-icon/preview.html`)
- [x] tvOS home-screen integration plan (Top Shelf + NSUserActivity + App Intents)
- [x] Categorization schema: `docs/taxonomy/collections.json` + Swift `CollectionRegistry` (expanded subject-to-genre map, collection weights, adult deny-list)
- [x] Seed catalog pipeline: browser generator (`build-catalog.html`), `catalog.json` schema, Swift `SeedCatalog.prime(into:)` first-launch loader wired into the app shell via `RootView`
- [ ] `catalog.json` generated from real Archive + TMDb data (owner runs build-catalog.html once Pages is live + TMDb token is in hand)
- [ ] Xcode tvOS project created at repo root as `ArchiveWatch`
- [ ] Swift files moved from `ios/` into Xcode group, `ios/` deleted
- [ ] `AppVersion.xcconfig` wired to tvOS target (Debug + Release)
- [ ] `Secrets.xcconfig` created (gitignored) with `TMDB_BEARER_TOKEN`
- [ ] Empty tvOS shell runs on Simulator
- [ ] GitHub Pages enabled (so the dashboard goes live)

### M1 — Watch a film end-to-end
> User launches the app, lands on Home, sees shelves of enriched titles
> with real posters, opens a detail page, plays the film through native
> AVPlayer transport controls with resume-on-reopen, and can hit
> "Surprise Me" to be sent to a random film.

- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency
- **Acceptance criteria**:
  - [ ] Home reads `featured.json` from GitHub Pages and renders curated + dynamic shelves
  - [ ] Every card shows a TMDb-sourced poster (not Archive thumb) for titles with IMDb IDs
  - [ ] Detail page shows synopsis, cast, year, runtime, source attribution
  - [ ] AVPlayerViewController plays the h.264 MP4 derivative end-to-end
  - [ ] Playback position persists across app launches (SwiftData)
  - [ ] Rate limit handling on 429 (Archive + TMDb) works under load
  - [ ] Three random actions wired: Random Movie, Random Category, Random Collection (Decision 014)
  - [ ] Adult-content filter on by default; toggle in Settings (Decision 012)
  - [ ] Per-category accent colors applied to shelf titles + focus glow (Decision 013)

### M2 — Search + Favorites + Siri reach
> User searches the Archive, filters by facets, favorites titles, and
> can launch random actions or save items via Siri.

- **Acceptance criteria**:
  - [ ] Siri Remote keyboard + dictation search
  - [ ] Facet chips (Type / Decade / Length)
  - [ ] Favorites tab with SwiftData persistence
  - [ ] Continue Watching shelf (second row on Home), timecode not percent
  - [ ] Deep link routing: `archivewatch://item/{id}`, `/play/{id}`, `/random/...` (Decision 015)
  - [ ] NSUserActivity declared on Detail screens — "Hey Siri, add this to my Up Next" works (Decision 015)
  - [ ] Three App Intents: SurpriseMe, RandomCategory, RandomCollection (Decisions 014 + 015)

### M3 — Browse + Taxonomy
> User browses by decade, genre, and collection; list/grid toggle
> persists; can correct a wrong TMDb match.

- **Acceptance criteria**:
  - [ ] Browse tab with facet panel
  - [ ] Inline-expanding collection cards (UHF pattern)
  - [ ] Grid/list toggle persists
  - [ ] "Wrong match? Re-link." escape hatch on Detail (Channels pattern)

### M4 — Polish + App Store submission
> Top Shelf extension, ambient dim, Shuffle Collection, and full App
> Store / TestFlight submission.

- **Acceptance criteria**:
  - [ ] Top Shelf extension target with `.sectioned` content (Continue Watching + Editor's Picks + What's New) — Decision 015
  - [ ] App Group container `group.com.bhwilkoff.archivewatch` with snapshot writers in main app
  - [ ] BGAppRefreshTask updates the What's New cache periodically
  - [ ] Ambient dim on focus-hold > 2s
  - [ ] Shuffle Collection action on each shelf
  - [ ] App icon shipped (master at `assets/app-icon/icon-1024.svg`; layered tvOS variants exported per `docs/design/app-icon.md`)
  - [ ] App Store screenshots + promotional copy
  - [ ] Attribution screen (TMDb logo + notice, Archive, Wikidata, Commons, LoC)
  - [ ] Privacy policy (trivial: "no data leaves your device except API calls to public services")
  - [ ] TestFlight → App Store

---

## Enrichment Pipeline Status

### Done
- [x] Research (`docs/research/metadata-sources.md`)
- [x] Architecture decision (DECISION 008)
- [x] `ArchiveClient` — scrape / metadata / download URL
- [x] `TMDbClient` — find-by-IMDb / movie detail / image URLs
- [x] `WikidataClient` — P724 SPARQL fallback
- [x] `DerivativePicker` — pure video-file selection logic
- [x] `ArtworkResolver` — cascading poster/backdrop resolution
- [x] `EnrichmentService` — orchestrator that produces a `ContentItem`
- [x] `ContentItem` SwiftData model + `Taxonomy` controlled vocabulary
- [x] `CollectionRegistry` — Archive collection → category + weight + adult filter, shared by Swift and JS via `docs/taxonomy/collections.json`
- [x] `SeedCatalog` — Swift loader that populates SwiftData from bundled `catalog.json` on first launch
- [x] Browser catalog generator (`build-catalog.html`) — produces `catalog.json` from live Archive + TMDb data, runs on any device

### Next for Enrichment
- [ ] `Secrets.xcconfig` with TMDb bearer token (M0)
- [ ] Smoke-test harness: 5 Archive IDs across decades, print full
      enrichment results to the console (M0)
- [ ] Background enrichment job (actor-gated, batched) for when titles
      arrive from scrape without IMDb IDs (M1)
- [ ] `featured.json` curated picks on GitHub Pages (M1)

---

## iOS App Status

### Completed
- Research, decisions, and networking/model scaffold in `ios/`

### Next for iOS (tvOS)
- Create Xcode project, wire scaffold, build empty shell

---

## Web App Status

### Completed
- Editorial dashboard (`index.html` + `js/app.js` + `js/api.js` + `css/styles.css`) — live `featured.json` editor with metadata preview that doubles as a pipeline validator
- What's New ticker (`whats-new.html` + `js/whats-new.js` + `css/whats-new.css`) — recent uploads from each major collection, tracks "seen" in localStorage, hands off picks to dashboard via `aw_pending` queue
- `featured.json` seed with 7 personal favorites + 9 dynamic popularity shelves + 8 categories + adult-content filter list + random-action config
- App icon master + Méliès moon SVG + multi-size preview at `assets/app-icon/preview.html`

### Next for Web
- Enable GitHub Pages on `main` (Owner action — Settings → Pages → branch: main, root)
- Once live, link the dashboard URL in README
- Open `build-catalog.html` once Pages is live to generate the real `catalog.json`
- (Future) Drag-and-drop reorder for shelves and items (currently up/down buttons)
- (Future) Node CLI equivalent of build-catalog for scheduled GitHub Actions refresh

---

## Open Questions

- Méliès moon icon shipped as vector master at `assets/app-icon/icon-1024.svg`; production version may swap the illustration for a high-res photographic still from the 1902 film (PD via LoC / Wikimedia Commons). Owner to decide post-launch.
- Silent preview clips on Detail focus — ship without, or generate server-side?
- Serif body type on tvOS — Fraunces in dashboard works; prototype the same on tvOS panel before committing
- Should the Top Shelf "What's New" section pull from the editorial-picks list or directly from the Archive recent-uploads feed? (See `docs/research/tvos-home-screen-integration.md` open questions.)

---

## Session Log

### 2026-04-17 — Archive Watch foundation
- **State found**: Empty dual-app template on `claude/archive-org-apple-tv-5bKXB`
- **Work done**:
  - Researched Archive.org API, TMDb, Wikidata, Wikimedia Commons, Library of Congress
  - Studied Apple TV / UHF / Channels for tvOS design patterns
  - Wrote `docs/research/metadata-sources.md` (enrichment pipeline, taxonomy, schema sketch)
  - Wrote `docs/research/design-reference.md` (visual + structural spec)
  - Logged Decisions 006–010 (tvOS-only, TMDb, identifier chain, no accounts, free release)
  - Filled CLAUDE.md project identity (Archive Watch, tvOS primary)
  - Rewrote SCRATCHPAD with M0–M4 milestones
  - Scaffolded `ios/Networking/` and `ios/Models/`: HTTPClient, ArchiveClient,
    TMDbClient, WikidataClient, DerivativePicker, ArtworkResolver,
    EnrichmentService, ContentItem, Taxonomy, response types
- **State left**: Ready for Xcode tvOS project creation (M0 final gate before M1 UI work).

### 2026-04-19 — Categorization schema + seed catalog pipeline
- **State found**: Editorial + icon + tvOS integration plan complete; owner asked to start the categorization schema and the cache database of popular videos for launch.
- **Work done**:
  - Authored `docs/taxonomy/collections.json` as the authoritative
    Archive-collection registry. 15 major collections with category
    mapping, display names, weights (for disambiguating overlapping
    collection membership), adult deny-list, and an extended
    subject-keyword → Genre map shared between Swift and JS.
  - Added `ios/Models/CollectionRegistry.swift` reading the bundled
    JSON, exposing `info(for:)`, `isAdult(_:)`, `containsAdult(_:)`,
    `genre(forSubject:)`, `dominantCollection(from:)`. Rewired
    `ContentTypeClassifier.classify(...)` to consult the registry
    first, fall back to the string-contains heuristics for
    unregistered collections.
  - Defined `catalog.json` (root) as the tvOS seed-catalog schema,
    initialised as an empty placeholder so the repo always compiles.
  - Built the browser catalog generator (`build-catalog.html` +
    `js/build-catalog.js` + `css/build-catalog.css`). Reads
    `featured.json`, resolves every dynamic shelf against Archive's
    scrape API, fetches per-item metadata, and — if you paste a TMDb
    v4 bearer token — enriches each result with poster/backdrop/
    credits/runtime. Concurrency-limited, stop-able mid-run. Outputs
    a downloadable `catalog.json`. Works from a phone.
  - Added `ios/Services/SeedCatalog.swift` — `@MainActor enum`
    `SeedCatalog.prime(into:)` that reads the bundled `catalog.json`
    and inserts non-existing items into the app's SwiftData store
    on first launch. Idempotent. Maps catalog fidelity to
    `EnrichmentTier` (fullyEnriched / identifierResolved /
    archiveOnly) so the live refresh knows which items to
    prioritize.
  - Wired the primer into `AppNameApp.body` via a tiny `RootView`
    wrapper that pulls `@Environment(\\.modelContext)` from the same
    `.modelContainer(for:)` the content views use.
- **State left**: Seed catalog schema + loader + generator are
  shipped, but `catalog.json` itself is still empty — needs a run
  of the browser generator (blocked on GitHub Pages going live).
  All other M0 boxes done.

### 2026-04-18 (later) — Méliès moon, What's New ticker, tvOS integration plan
- **State found**: Editorial pipeline + decisions in place; owner approved going forward with Méliès moon icon + What's New ticker, asked for tvOS home-screen integration research.
- **Work done**:
  - Researched tvOS home-screen integration surfaces (Top Shelf
    extension styles, NSUserActivity for "add to Up Next" via Siri,
    App Intents for voice-launched random actions, Apple TV App
    partner program). Wrote
    `docs/research/tvos-home-screen-integration.md` covering
    architecture, App Group plumbing, deep-link routes, milestone
    landing, and known gotchas.
  - Logged Decision 015: ship Top Shelf (`.sectioned`) + NSUserActivity
    + App Intents in M2 + M4; defer Apple TV App partner program to v2.
  - Designed and implemented the Méliès moon as a hand-illustrated
    SVG (`assets/app-icon/melies-moon.svg`) — anthropomorphic moon
    face with rocket lodged in right eye, scaled to read clearly
    from 64px to 1024px. Composed full app icon master
    (`assets/app-icon/icon-1024.svg`) with bold orange field,
    sprocketed black film frame (10 perforations top + bottom),
    charcoal photo gutter, and the moon centered inside.
  - Built `assets/app-icon/preview.html` — multi-size icon preview
    plus a Home Screen mock with Apple TV / Netflix / Disney+ / Plex
    neighbors so the brand signal can be evaluated at a glance.
  - Built the What's New ticker (`whats-new.html` +
    `js/whats-new.js` + `css/whats-new.css`) — collection-tabbed feed
    of the 8 major collections, sorted by `-publicdate`, with
    seen-tracking in localStorage, IMDb + Playable badge hydration
    per item, copy-to-clipboard, and "Send to Picks" which queues
    archiveIDs in `aw_pending`. Dashboard now shows a banner when
    pending items are waiting and offers a one-click "Add to
    Editor's Picks" merge.
- **State left**: Curation tooling fully assembled (dashboard +
  ticker + pipeline validator). Icon master ready for export. tvOS
  integration plan documented end-to-end. Still awaiting owner-at-desk
  steps: Xcode project, GitHub Pages enable, validator run.

### 2026-04-18 (earlier) — Editorial pipeline, validator, decisions, app icon spec
- **State found**: Owner away from desktop; needed productive non-Xcode work.
- **Work done**:
  - Tried to live-validate the cascade against the 7 personal favorites via `curl`
    and `WebFetch` — both blocked by sandbox policy on archive.org. Pivoted.
  - Drafted `featured.json` seed (8 categories with accent colors, 1 curated
    "Editor's Picks" shelf with the 7 favorites, 9 dynamic popularity shelves,
    `adultCollections` filter list, `randomActions` config).
  - Built the editorial dashboard (`index.html` + `js/app.js` + `js/api.js`
    + `css/styles.css`): loads `featured.json`, lets the curator add/remove/
    reorder/edit-note Archive IDs with live metadata preview from
    Archive.org. Each row surfaces an "IMDb ✓ / No IMDb" badge and a
    "Playable ✓ / Not playable" badge — same checks the Swift
    `EnrichmentService` will run, so the dashboard doubles as a pipeline
    validator that runs in any browser.
  - Wrote `tools/validate-pipeline.sh` — a Bash + curl + jq script that
    runs the same checks from the command line for the desktop
    smoke-test workflow. Optional `--tmdb` flag probes TMDb /find when
    `TMDB_BEARER_TOKEN` is set. `--json` for machine output.
  - Logged Decisions 011 (hybrid curation: editor's picks + dynamic
    popularity shelves), 012 (adult content filter on by default),
    013 (per-category accent palette), 014 (random actions in M1).
  - Drafted `docs/design/app-icon.md` — photographic film frame on
    bold category color; layered tvOS icon variants; recommended
    starting still: Méliès moon.
- **State left**: Editorial pipeline live (pending GitHub Pages enable).
  Validation harness ready for desktop. Scaffold + dashboard + decisions
  in sync. Next time at desk: create Xcode project, run validator,
  enable Pages.
