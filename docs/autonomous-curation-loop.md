# Autonomous Curation Loop

A standing agenda for continuously **growing the collection** and **enriching
its metadata + artwork**. This file is the loop's memory: each iteration reads
it, executes the next item, and logs the result.

## Two layers (important)
- **Sustainable executor = GitHub Actions** (runs on GitHub, reaches Archive/
  TMDb/OMDb, no Mac dependency — see `catalog_delivery_architecture` /
  Decisions 017–018). All high-volume, network-dependent discovery + enrichment
  happens here on a schedule. THIS is what keeps the catalog improving forever.
- **Agent loop = high-judgment improvement.** The local sandbox CANNOT reach
  archive.org, so the agent does NOT probe/enrich over the network directly. It
  improves the *tools, sources, taxonomy, and app*, verifies locally
  (build/actool/dry-run on the committed catalog), commits, and triggers CI to
  do the networked work + drain sources.

## Rules
- **Native Apple APIs only** for app work (SwiftUI, AVFoundation, Compression,
  SQLite3, App Intents…). No third-party Swift packages. Follow
  `docs/tvos-playbook.md` and the `all-ios-skills:*` / `tvos-platform-patterns`
  skills for any UI/focus/animation/image work.
- **Verify before commit**: `xcodebuild` (or `actool` for icons), or a
  `--dry-run` on the catalog, every iteration.
- **Respect CI gates**: large catalog restructures go through the existing
  workflows (which open PRs where appropriate); don't bypass them.
- **Small, verified increments**: commit + push each iteration (per the
  always-commit-and-push preference); trigger the relevant workflow for
  networked execution.
- Each iteration: do ONE backlog item, then log it under "Iteration log".

## Baseline (2026-06; ~30.6k items, movie-type ~30.2k)
- Sources mined: ~17 Archive collections (feature_films, silent_films,
  classic_tv, prelinger, animation, film_noir, SciFi_Horror, comedy_films,
  short_films, news/affairs, documentary_films, FedFlix, nasa, ephemera,
  universal_newsreels, computerchronicles, academic_films) + Wikidata PD + LoC.
- Quality gaps (movie-type): **52% no real poster** (Archive thumbnails),
  ~33% no genres (was 47% before the subject-genre fallback), 53% no cast,
  46% no director, 41% no IMDb ID, 5% no synopsis.

## Backlog (prioritized; A = growth, B = quality)
- [x] **B1 — Posters via Wikidata/Commons**: enrich_wikidata_posters.py +
  wikidata-posters.yml fill Commons P18 posters for the 3,449 QID items lacking
  artwork (not just no-IMDb). Dispatched; weekly + on-demand.
- [ ] **B2 — IMDb resolution**: raise the title+year→IMDb match rate for
  archiveOnly items (unlocks TMDb posters + cast + genres downstream).
- [x] **A1 — Source breadth (probe)**: added tools/probe_collections.py +
  probe-sources.yml (CI scrape-count probe of candidate PD collections).
- [ ] **A1b — Add worthy collections (BLOCKED: probe found none)**: the first
  probe-sources run reported NO candidate with >=100 items — the guessed
  collection ids are likely wrong (Archive collection identifiers differ from
  display names). Next A iteration: fix the probe — derive REAL candidate
  collection ids from the data (the `collections[]` already on catalog items
  that are NOT yet in DEFAULT_COLLECTIONS — those are proven-existing ids), then
  re-probe + add the worthy ones.
- [ ] **A2 — Source depth**: raise per-collection scrape caps / paginate
  deeper on the richest collections; measure new-item yield in CI.
- [ ] **B3 — Cast/director backfill** via OMDb/TMDb after B2.
- [ ] **B4 — Synopsis backfill** for the 5% missing (OMDb/TMDb/Wikidata).
- [ ] **A3 — New source research**: Wikimedia Commons video, LoC subcollections,
  Prelinger deep, European/Asian PD archives; add a discovery feed per source.
- [ ] **B5 — App image pipeline**: ensure tvOS `RemoteImage` downsamples/caches
  optimally at 4K and degrades gracefully when only an Archive thumb exists
  (native ImageIO; per playbook §7).

## Iteration log
- 2026-06-02 — **Iteration 1 (B, genres)**: activated the dead
  `subjectKeywordMap` in `remediate_catalog.py` → fills genres from existing
  subjects with no network. 4,176 items gained genres (47% → ~33% gap).
  Self-healing in discover-content + publish-db. Committed + published.
- 2026-06-02 — **Iteration 2 (A, source breadth)**: added
  `tools/probe_collections.py` + `probe-sources.yml` — a read-only CI probe of
  candidate PD Archive collections (the sandbox can't reach Archive). Dispatched;
  next iteration reads the counts and adds the worthy ones (A1b). Also hardened
  CI: tv-canonical + faststart now remediate before publishing catalog-source.
- 2026-06-02 — **Iteration 3 (B, artwork)**: enrich_wikidata_posters.py +
  wikidata-posters.yml — Commons P18 posters for 3,449 QID items with no real
  artwork (House on Haunted Hill, White Zombie, Carnival of Souls…). Dispatched.
  Note: the iter-2 probe found NO worthy collections (guessed ids wrong) — A1b
  re-scoped to derive real candidate ids from catalog items' own collections[].
