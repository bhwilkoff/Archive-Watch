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
- [x] **A1b — Data-driven probe + 1 collection**: probe now derives REAL
  candidate ids from catalog `collections[]` (silenthalloffame, vintage_cartoons,
  usgovfilms, culturalandacademicfilms, tvprograms, film_scifi…). Added
  mid-century-german-film to DEFAULT_COLLECTIONS. Re-dispatched probe-sources.
- [x] **A1c — Probe fixed + 19 collections added**: probe now uses
  advancedsearch.php numFound (real counts) + fetches the catalog in CI.
  Added 19 probe-verified PD collections (decade classic TV, silenthalloffame,
  film_scifi, feature_films_picfixer, TheVideoCellarCollection, cultural/
  educational, ephemera, german_cinema, classic_cartoons, NASA) — excluded
  Archive admin/umbrella collections. DEFAULT_COLLECTIONS 19 -> 38. Mining now.
- [ ] **A3 (now primary for growth) — NEW EXTERNAL sources**: the main Archive
  collections are mined; biggest remaining growth is non-Archive PD: deeper
  Wikidata-PD SPARQL feeds, LoC subcollections, Wikimedia Commons video. Add a
  CI discovery feed per source.
- [ ] **A2 — Source depth**: raise per-collection scrape caps / paginate
  deeper on the richest collections; measure new-item yield in CI.
- [x] **B3 — Cast/director/genres backfill (OMDb)**: omdb-backfill now applies
  identity fields (apply_identity) from the full record it already fetches —
  cast/director/genres, not just posters. Schema bump re-fetches 13,814 items
  once (950/day) to gain them. Dispatched.
- [x] **B4 — Wikipedia synopses**: enrich_wikipedia_synopsis.py +
  wikipedia-synopsis.yml — real enwiki plot summaries for 2,304 QID items with
  no/short synopsis (QID -> enwiki sitelink -> REST extract). Replaces junk
  uploader descriptions; only upgrades. Dispatched. (OMDb plot already fills
  synopsis for IMDb items via apply_rich.)
- [ ] **A3 — New source research**: Wikimedia Commons video, LoC subcollections,
  Prelinger deep, European/Asian PD archives; add a discovery feed per source.
- [x] **B5 — App image pipeline (already satisfied)**: reviewed iter 7 —
  ImageLoader already does NSCache + ImageIO downsample-to-target + eager decode
  + inflight coalescing + http→https (playbook §7); PosterArt already degrades
  to a branded ProceduralPoster when hasDesignedArtwork is false. No change
  needed.

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
- 2026-06-02 — **Iteration 3 result**: wikidata-posters CI run filled **1,826**
  Commons posters (of 3,449 QID candidates).
- 2026-06-02 — **Iteration 4 (A, source breadth)**: made probe_collections.py
  data-driven (real ids from catalog collections[], excluding mined/fav-*/
  generic/dumping); added mid-century-german-film to DEFAULT_COLLECTIONS;
  re-dispatched probe. Pivoted Track A toward A3 (new external sources) since
  the major Archive collections are already mined.
- 2026-06-02 — **Iteration 5 (B, metadata)**: omdb-backfill now fills
  cast/director/genres (apply_identity), not just posters — closes the
  3,883-no-cast / 1,651-no-genres gaps for IMDb-ID'd items at no extra API cost.
  Schema 2->3 re-fetches 13,814 once (daily cron). Dispatched. Also found the
  data-driven probe STILL returns <100 for all (scrape `total` is wrong) — A1c
  re-scoped to fix the count via advancedsearch.php numFound.
- 2026-06-03 — **Iteration 6 (A, source breadth)**: fixed probe count
  (advancedsearch numFound) + fetch catalog in CI; real counts returned. Added
  19 probe-verified PD content collections to DEFAULT_COLLECTIONS (19 -> 38):
  decade classic TV 1950s-1990s, silenthalloffame, film_scifi,
  feature_films_picfixer, TheVideoCellarCollection, cultural/educational,
  ephemera, german_cinema, classic_cartoons, NASA. Triggered discover-content.
- 2026-06-03 — **Iteration 7 (B, text quality)**: enrich_wikipedia_synopsis.py
  + wikipedia-synopsis.yml — real enwiki plot summaries for 2,304 QID items with
  no/short synopsis. Dispatched. Confirmed B5 (app image pipeline) already
  satisfied — no change. discover-content (19 new collections) + omdb-backfill
  (cast/genres) both succeeded.

## Status (after 7 iterations)
The high-value, safe, agent-doable backlog is largely worked through; the heavy
networked enrichment is now DRAINING in CI over the coming days (13,814 OMDb
re-fetches for cast/genres, ~3.4k Commons posters, ~2.3k Wikipedia synopses, 19
new collections mining). Remaining backlog is either lower-yield or higher-risk:
- A2 (deeper scrape caps), A3 (new external sources: deeper Wikidata-PD / LoC /
  Wikimedia video) — growth.
- B2 (IMDb-id resolution to unlock TMDb for the 41% no-IMDb) — high value but
  DELICATE (false matches degrade quality); do carefully, verify match rate in
  CI before committing broadly.
The CI pipeline is the permanent autonomous executor; the agent loop can space
out / focus on these harder items.
