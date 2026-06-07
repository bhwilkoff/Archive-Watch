# TV Metadata Sources

Research for the TV enrichment program (posters, summaries, cast/crew, episode
listings). Audit the current state any time with `python tools/audit_tv.py`.

## Baseline gaps (first audit)

| Field | Coverage | Source of the gap |
|---|---|---|
| Series cast/crew | **0%** | never fetched by any tool |
| Episode overviews | 22% | builder stored stills, not summaries |
| Episode air dates | 44% | builder didn't store airdate |
| Series summaries | 76% | TVmaze/TMDb blanks for obscure PD shows |
| Series posters | 87% (all tvmaze/archive, **0 professional TMDb**) | builder used TVmaze art only |
| Episode titles | 100% | — |
| Episode stills | 89% | TVmaze |
| Playable episode | 100% | — |

## Sources, by value

### 1. TVmaze — free, no key (PRIMARY)
- `/shows/{id}/cast` → cast + characters + actor images. **Now used** by
  `tools/enrich_tv_cast.py` (the 0% cast gap). 273 series carry a `tvmazeID`.
- `/shows/{id}/episodes?specials=1` → per-episode `summary` (~60%), `airdate`
  (~100%), `image`. **Now used** by `tools/backfill_tv_episode_meta.py` to fill
  the missing overviews/airdates.
- `/shows/{id}` → series summary, image, genres, network.
- `externals.imdb` → the bridge to TMDb (below).

### 2. TMDb — have token (BEST for professional posters)
- `/tv/{id}` → professional 2:3 poster (`poster_path`), summary,
  `aggregate_credits` cast. The catalog's TV cards have NO TMDb posters yet — this
  is the upgrade path for "well-produced posters."
- `/tv/{id}/season/{n}` → episode overviews/stills/airdates (richer than TVmaze for
  some shows). `tools/enrich_tv_episodes.py` already does this **when a tmdb_id is
  known** — the gap is the many tvmaze-only series.
- **Bridge**: TVmaze `externals.imdb` → TMDb `/find/{imdb}?external_source=imdb_id`
  → `tmdb_id`. This unlocks TMDb posters + episode data for the tvmaze-only series.
  (Next build step.)

### 3. TheTVDB — v4 API, free key (NEW source, owner step)
- The canonical TV database; deepest artwork breadth (posters, season posters,
  banners) + episodes + cast, especially for obscure/old shows TMDb misses.
- Requires a free API key (`THETVDB_API_KEY`) — owner adds it like the others.
  Best as the fallback poster/episode source after TMDb.

### 4. OMDb — have key (fallback)
- TV series plot + poster by `imdbID`; episode-level via `&Season=&Episode=`.
- Use to fill series summaries/posters where TVmaze + TMDb both blank.

### 5. Wikidata / Wikipedia (last resort)
- Series summaries (already wired for movies) + Wikipedia episode tables for
  overviews. Messy; only for shows missing everywhere else.

## Plan / priority
1. **Cast** — TVmaze. ✅ `enrich_tv_cast.py`
2. **Episode overviews + air dates** — TVmaze backfill ✅
   `backfill_tv_episode_meta.py`; then TMDb (via the imdb bridge) for the rest.
3. **Professional posters** — TMDb via the TVmaze→imdb→tmdb bridge; TheTVDB for the
   remainder (needs key).
4. **Series summaries** — TVmaze/TMDb/OMDb fill the missing ~24%.

All series enrichment writes to `series/*.json` (committed, served from Pages, read
by SeriesDetailView at runtime) and is reconciled into the catalog tv-series cards
by `reconcile_tv_catalog.py`.
