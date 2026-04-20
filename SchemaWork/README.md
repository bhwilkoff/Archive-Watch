# Canonical Video Work Registry

A federated database of video works — films, TV, shorts, documentaries, home
movies, industrial films, and everything in between — aggregated from
archive.org, the Library of Congress, AAPB, Wikimedia Commons, and the
European Film Gateway (via Wikidata).

**Design goals:**
- One canonical work can have many sources; the consumer app never chooses
- Score, don't filter: keep the long tail in the DB, hide it via thresholds
- Zero API keys required
- Every pass can be re-run without re-scraping (engagement refresh, rescoring)

## Install & run

```bash
pip install requests

python registry_pipeline.py                      # full run, all sources
python registry_pipeline.py --limit 50           # smoke test
python registry_pipeline.py --sources ia loc     # subset of sources
python registry_pipeline.py --skip-enrichment    # skip Wikidata passes
python registry_pipeline.py --no-score           # skip scoring pass
python registry_pipeline.py --report             # score distribution report, no ingest
python registry_pipeline.py --refresh-engagement # refresh IA engagement, rescore, exit
```

Run the unit tests (no network required):

```bash
python test_registry.py
```

## Architecture

```
                        ┌────────────┐
  archive.org    ──────▶│            │
                        │            │
  loc.gov        ──────▶│            │◀──── Wikidata SPARQL
                        │  registry  │      (P724: IA ID, P2484: EFG ID,
  AAPB (solr)    ──────▶│            │       plus director/cast/poster)
                        │            │
  Wikimedia      ──────▶│            │
  Commons                └────────────┘
                              │
                              ▼
                       scoring pass
                              │
                              ▼
                       works_default (SQL view)
                       — the "good stuff" your app reads
```

Every step is independent: ingest one source, rescore, re-ingest another,
rescore again. Nothing ever requires re-scraping from scratch.

## Canonical IDs

Every work gets one stable canonical ID, chosen in priority order:

1. **`wd:Q12345`** — if Wikidata has an entry (via P724 IA-ID property)
2. **`imdb:tt0012345`** — if IMDb knows it but Wikidata doesn't
3. **`lic:<hash>`** — a locally-issued hash of normalized title + year + creator

The `lic:` namespace is deterministic: the same film ingested from two
sources gets the same ID automatically and merges into one work with two
source rows. When the Wikidata enrichment pass runs, `lic:` IDs get
promoted to `wd:` IDs where possible.

## Sources

| Source | Coverage | Notes |
|---|---|---|
| archive.org | PD feature films, TV, cartoons, shorts, home movies | Only source with engagement data (downloads, ratings) |
| Library of Congress | National Screening Room, Paper Prints, early American cinema | Authoritative masters; downloadable = PD |
| AAPB | Public TV/radio (PBS, NET, local stations) | Usually `rights_reserved_free_stream`, not PD |
| Wikimedia Commons | CC-licensed videos (~135k files) | Direct playable URLs, good license metadata |
| European Film Gateway | European cinema, silent films, newsreels | Metadata-only, links back to partner archives |
| Wikidata | Director, cast, genre, poster, IMDb ID, Wikipedia link | Enrichment layer for everything above |

## Schema

### `works` — one row per canonical work
Columns: `canonical_id` (PK), `id_scheme`, `title`, `title_normalized`,
`year`, `runtime_sec`, `work_type`, `rights_status`, `description`,
`languages`, `subjects`, `quality_score`, `popularity_score`,
`popularity_updated_at`.

### `sources` — many rows per work
Columns: `canonical_id` (FK), `source_type`, `source_id`, `source_url`,
`stream_url`, `format_hint`, `file_size`, `downloadable`, `source_quality`.
UNIQUE on `(source_type, source_id)`.

### `engagement` — view/download counts, refreshable
Columns: `source_type`, `source_id` (PK together), `downloads`,
`num_favorites`, `num_reviews`, `avg_rating`, `week_views`, `refreshed_at`.
Separate from `sources` so it can be refreshed without re-ingesting.

### `enrichment` — Wikidata join data
Columns: `canonical_id` (PK/FK), `wikidata_qid`, `imdb_id`, `tmdb_id`,
`wikipedia_url`, `directors`, `cast_list`, `genres`, `countries`,
`publication_date`, `poster_url`.

### Views

- **`works_with_best_source`** — every work joined to its single best source
- **`works_default`** — the above, filtered to `quality_score ≥ 40 AND popularity_score ≥ 25`

## Controlled vocabularies

**`work_type`**: `feature_film`, `short_film`, `documentary`, `animated_short`,
`tv_episode`, `tv_movie`, `newsreel`, `home_movie`, `industrial_film`,
`educational_film`, `music_video`, `concert`, `lecture`, `sports_footage`,
`trailer`, `unknown`.

**`rights_status`**: `public_domain`, `creative_commons`,
`rights_reserved_free_stream`, `unknown`. Kept separate from `work_type`
because AAPB content is often free to stream but not PD — honest labeling
matters.

## Scoring

Two independent 0-100 scores at the work level:

### `quality_score` — "is this worth keeping at all?"
A hard filter. Reflects how well-formed and watchable the record is.
Factors:
- Runtime (under 60s penalized hard; 10+ min rewarded)
- File size (under 5 MB penalized as likely corrupted)
- Title junk detection (`IMG_1234`, `DSC_0042`, `untitled`, ALL-CAPS ids)
- Description length
- Work type and rights metadata completeness

### `popularity_score` — "would a typical user care?"
The sort key. Reflects engagement signals and cross-source cultural footprint.
Factors:
- Work type baseline (feature_film: 40, home_movie: 5, etc.)
- archive.org engagement: log-normalized downloads, favorites,
  rating × review-count weight
- Wikipedia presence (+15) and per-language edition bonus
- Wikidata completeness: director (+3), cast (+3), IMDb ID (+5), poster (+5)
- Multi-source bonus (+5 for 2 sources, +3 more for 3)
- Pre-1940 survival bonus (+8): if it's still here, it mattered

Log-normalization is important. Raw archive.org download counts are brutally
long-tailed — one item has 300k, most have under 50. `log10(downloads + 1)`
makes the signal combine cleanly with other 0-10 range signals.

## Operations: the typical workflow

**Initial build** (does everything):
```bash
python registry_pipeline.py
```

**Inspect score distributions and decide on cutoffs**:
```bash
python registry_pipeline.py --report
```
This prints histograms, survival counts at various `(quality, popularity)`
thresholds, and sample titles at the bottom / top / borderline slices. Use
this to tune the `works_default` view to match your taste.

**Adjust cutoffs** by editing the `works_default` view definition in SCHEMA,
or just create your own view on top:
```sql
CREATE VIEW my_picks AS
SELECT * FROM works_with_best_source
WHERE quality_score >= 50 AND popularity_score >= 35
ORDER BY popularity_score DESC;
```

**Weekly/monthly cron** to refresh engagement and rescore:
```bash
python registry_pipeline.py --refresh-engagement
```
Pulls fresh download counts, rewrites `popularity_score` for every work,
prints a fresh report. Fast (~10 min for 200k items), no metadata is touched.

**Add a new source collection**:
```bash
python registry_pipeline.py --sources ia --collections newsreels prelinger
```

## Example queries

```sql
-- The default good-stuff feed
SELECT title, year, work_type, best_source_type, best_stream_url,
       popularity_score
FROM works_default
LIMIT 100;

-- Silent-era feature films with posters
SELECT title, year, poster_url, best_source_url
FROM works_default
WHERE work_type = 'feature_film' AND year < 1929 AND poster_url IS NOT NULL
ORDER BY popularity_score DESC;

-- Works preserved in multiple archives (strong quality signal)
SELECT title, year, source_count, popularity_score
FROM works_with_best_source
WHERE source_count > 1
ORDER BY source_count DESC, popularity_score DESC;

-- "Hidden gems" — high quality, low popularity (researcher mode)
SELECT title, year, work_type
FROM works_with_best_source
WHERE quality_score >= 60 AND popularity_score BETWEEN 15 AND 25;

-- Every source for a specific work, best-first
SELECT s.source_type, s.source_url, s.source_quality, s.format_hint
FROM sources s
JOIN works w USING (canonical_id)
WHERE w.title_normalized = 'night of the living dead' AND w.year = 1968
ORDER BY s.source_quality DESC;
```

## Extending: adding a new source type

1. Write a `scrape_xxx()` generator that yields raw items
2. Write an `ingest_xxx_item(conn, item)` that calls `upsert_work(...)` and
   `upsert_source(...)` — the federation logic takes care of merging
3. Add an entry to `SOURCE_TYPE_BASE_SCORE`
4. Add the new source to `ALL_SOURCES` and the main() orchestration

If the new source has engagement data (views, likes, etc.), also write rows
to the `engagement` table and the popularity scoring will pick them up
automatically.

## Known limitations

- **archive.org stream URLs point at the download folder**, not a specific
  MP4. For actual playback, call `https://archive.org/metadata/{id}` and
  pick the best derived file.
- **Wikipedia edition count proxy is currently 1 or 0.** The enrichment
  query stores only the English article URL. A richer pass could pull
  sitelinks count from Wikidata for a better cultural-footprint signal.
- **No fuzzy matching yet.** If archive.org has "The Kid" and LoC has
  "Le Kid", they won't merge. Could add Jaro-Winkler later if needed.
- **TMDB/OMDb not wired in.** Free-tier API keys would fill gaps,
  particularly posters for more obscure PD films.

## Files

```
registry_pipeline.py   # the pipeline (all sources, scoring, report modes)
test_registry.py       # 25 unit tests, no network required
video_registry.db      # output SQLite, created on first run
README.md              # this file
```
