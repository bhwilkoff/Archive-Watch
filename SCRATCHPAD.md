# Project Scratchpad — Archive Watch

## Current State

- **Status**: M0 in progress — research + networking scaffold complete; Xcode project pending
- **Active milestone**: M0 → M1
- **Last session**: 2026-04-17 — research, decisions, scaffold
- **Next actions**:
  1. Create Xcode tvOS project at repo root (Product Name: `ArchiveWatch`, no spaces, tvOS 17+)
  2. Move Swift files from `ios/` into the Xcode-created `ArchiveWatch/` group, then delete `ios/`
  3. Create `Secrets.xcconfig` (gitignored) with `TMDB_BEARER_TOKEN`
  4. Build an empty tvOS shell on Simulator and verify `AppVersion.xcconfig` is wired
  5. Wire a smoke-test harness against 5 known-good Archive IDs to validate the enrichment cascade
- **Open questions**:
  - Serif body type (New York) on tvOS — distinctive-correct or distracting? Prototype on real panel.
  - Silent preview loop on Detail focus — ship without, or generate 10s clips server-side via GitHub Actions?
  - Per-collection accent color (subtle tint) or strict consistency?

---

## Scope Note

Archive Watch is a **tvOS-first** app (see Decision 006). The `index.html`
/ `css/` / `js/` scaffold is retained only as the future editorial
dashboard for curating `featured.json`. The Dual-Platform Feature Parity
Model does not apply here.

---

## Milestones

### M0 — Project Setup
- [x] Research docs (`docs/research/metadata-sources.md`, `docs/research/design-reference.md`)
- [x] Architecture decisions logged (DECISIONS 006–010)
- [x] Networking + model scaffold in `ios/`
- [x] CLAUDE.md identity filled in
- [ ] Xcode tvOS project created at repo root as `ArchiveWatch`
- [ ] Swift files moved from `ios/` into Xcode group, `ios/` deleted
- [ ] `AppVersion.xcconfig` wired to tvOS target (Debug + Release)
- [ ] `Secrets.xcconfig` created (gitignored) with `TMDB_BEARER_TOKEN`
- [ ] Empty tvOS shell runs on Simulator

### M1 — Watch a film end-to-end
> User launches the app, lands on Home, sees a shelf of enriched titles
> with real posters, opens a detail page, and plays the film through
> native AVPlayer transport controls with resume-on-reopen.

- **Learning check**: [x] Deepens understanding [x] Invites participation [x] Supports agency
- **Acceptance criteria**:
  - [ ] Home has at least 3 shelves populated from curated Archive IDs
  - [ ] Every card shows a TMDb-sourced poster (not Archive thumb) for titles with IMDb IDs
  - [ ] Detail page shows synopsis, cast, year, runtime, source attribution
  - [ ] AVPlayerViewController plays the h.264 MP4 derivative end-to-end
  - [ ] Playback position persists across app launches (SwiftData)
  - [ ] Rate limit handling on 429 (Archive + TMDb) works under load

### M2 — Search + Favorites
> User searches the Archive, filters by facets, and favorites titles to
> return to. Continue Watching appears on Home.

- **Acceptance criteria**:
  - [ ] Siri Remote keyboard + dictation search
  - [ ] Facet chips (Type / Decade / Length)
  - [ ] Favorites tab with SwiftData persistence
  - [ ] Continue Watching shelf (second row on Home), timecode not percent

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
  - [ ] Top Shelf extension (Continue Watching + New This Week)
  - [ ] Ambient dim on focus-hold > 2s
  - [ ] Shuffle Collection action on each shelf
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
- (none yet — template scaffold only)

### Next for Web
- Editorial dashboard for `featured.json` maintenance — not until M1+

---

## Open Questions

- Serif body type (New York) on tvOS — prototype on real panel before committing
- Silent preview clips on Detail focus — ship without, or generate server-side?
- Per-collection accent color — subtle variation or strict consistency?

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
