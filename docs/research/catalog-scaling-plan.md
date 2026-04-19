# Catalog Scaling Plan — 53 → 1000+ with Continuous Updates

Date: 2026-04-19.
Supersedes nothing; complements DECISIONS 008 and 011.

## The problem

The v0 catalog builder resolves 10 shelves × 24 items = ~240 candidates, dedupes
to 53 unique items, and reaches 62% full-enrichment. The ceiling isn't the
cascade — it's the intake. Archive.org has **27,285 items in `feature_films`
alone, 11,192 in `classic_tv`, 10,206 in `prelinger`, 3,526 in `silent_films`**
(verified 2026-04-19 via `advancedsearch.php?...&rows=0`). The scrape API's
cursor pagination has no practical ceiling; we were reading the first page.

## Verified facts (as of 2026-04-19)

| Source | What / how many |
| --- | --- |
| Archive `mediatype:movies` | 15.9M items total |
| Archive scrape cursor | returns ≥1000/page, cursor continues; the `total` field is NOT filter-scoped and is useless — use `advancedsearch.php?rows=0` for counts |
| Archive `advancedsearch` | deep-paging capped at 10,000 results; switch to scrape for bulk |
| Wikidata `P724` (Archive ID) ∧ `P6216=Q19652` (public-domain) | **880 films**, pre-matched, pre-verified |
| Wikidata `P724` alone | **5,241 films** pre-matched to Archive IDs |
| Wikidata `P6216=Q19652` (PD films overall) | 34,137 films — tail has no Archive ID yet |
| IMDb non-commercial TSV dump | 220 MB, updated daily; non-commercial license covers us (Decision 010) |
| Wikipedia "List of films in the public domain in the US" | ~800 entries, each with Wikidata Q-number |

## Plan shape

Two catalogs, two refresh cadences:

1. **`catalog.json`** — bundled with the app (~1–3 MB). Hand-curated shelves
   + top items from each major collection. Refreshed when we ship a new app
   build. Today ~53 items, target **~500 items**.
2. **`catalog-full.json`** (new) — fetched from GitHub Pages on first launch
   and cached. Much bigger (~10–20 MB), targets **5,000–10,000 items**.
   Refreshed weekly by a GitHub Action. This is how we get past 1,000.

The app reads bundled first (instant), then merges the full catalog in the
background once downloaded. First-launch UX never waits on network.

---

## Phase 1 — Discovery (find more candidates)

### 1a. Wikidata P724 sweep — **do first**

A single SPARQL query returns up to 5,241 items already mapped to Archive
identifiers, with IMDb + Wikidata + Commons P18 image in one shot. This is the
single highest-leverage addition.

```sparql
SELECT ?film ?filmLabel ?archiveId ?imdbId ?image ?date ?director ?directorLabel WHERE {
  ?film wdt:P31/wdt:P279* wd:Q11424 .
  ?film wdt:P724 ?archiveId .
  OPTIONAL { ?film wdt:P345 ?imdbId }
  OPTIONAL { ?film wdt:P18  ?image  }
  OPTIONAL { ?film wdt:P577 ?date   }
  OPTIONAL { ?film wdt:P57  ?director }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}
```

Every returned `?archiveId` is a seed; run existing enrichment cascade to
confirm playability and flesh out cast/synopsis via TMDb.

Expected yield: **~5,000 catalog candidates** after filtering for playability
(many Wikidata P724 entries point at audio-only or dark items).

### 1b. Archive scrape with cursor pagination per collection

Replace the current "top 24 per shelf" with "walk every collection with cursor
until exhausted or quality floor reached". Apply `downloads >= 100` floor via
post-filter (scrape can't filter by downloads directly).

Collections to walk fully:
- `feature_films` (27k)
- `classic_tv` (11k)
- `prelinger` (10k)
- `silent_films` (3.5k)
- `film_noir`, `sci-fi_horror`, `newsandpublicaffairs`, `classic_commercials`,
  `classic_cartoons`, `documentaries`, `short_films`, `experimentalfilms`

Expected yield: **~60k raw candidates**. After quality floor + dedup against
(1a), ~5,000–8,000 distinct enrichable items.

### 1c. Wikipedia PD list → Wikidata Q-numbers → Archive IDs

Fetch the Wikipedia list via the REST API (`/api/rest_v1/page/html/...`),
extract Q-numbers from `data-wikidata-id` attributes in the HTML, then run a
second SPARQL to pull P724 for each. Yields ~700–800 pre-verified PD titles,
most of which overlap with (1a) but the intersection with (1b) is the
"definitely PD" signal we use for the default filter.

### 1d. PublicDomainMovies.net sitemap scrape — optional

Every movie page embeds `archive.org/embed/{identifier}`. Regex-mine the
sitemap + per-movie pages. Yield: ~600–1000 curator-vetted identifiers.
Low-priority because (1a) likely covers 80% of these; add only if stats show
a gap.

### 1e. National Film Registry intersection — editorial prestige shelf

Scrape LoC's National Film Registry list (~900 entries), match each by
(title, year) against the pool we've built from (1a)+(1b). The intersection
(~100–200 titles) becomes a permanent hero shelf: "National Film Registry on
Archive.org". High curator signal per item.

### 1f. Heavy-uploader RSS watchlist — continuous discovery

Archive's per-uploader RSS feed (`archive.org/services/collection-rss.php?
mediatype=movies&collection={handle}`) gives new uploads. Hand-curate a list
of 10–20 trusted uploaders in `featured.json` under a new `uploaderWatchlist`
key. Weekly GitHub Action promotes fresh items to a "Fresh Finds" shelf.

---

## Phase 2 — Enrichment (resolve metadata better)

Current cascade: `Archive IMDb → Wikidata P724 → TMDb /find → TMDb /search
by title+year → Wikidata P18 poster → Archive thumb`.

Insertions, in priority order:

### 2a. Archive description regex-mining — **free, do first**

Before any network call, regex-mine the Archive item's own `description`
field for:
- `Directed by (.+?)(?:\.|$|\n)` → director candidate
- `(?:Starring|Cast|Featuring):?\s*(.+?)(?:\.|$|\n)` → cast candidate
- `\((19|20)\d\d\)` → year candidate
- `(\d+)\s*min(?:ute)?s?` → runtime candidate
- `urn:wikidata:(Q\d+)` in external-identifier — some uploaders include it

Results go in as low-confidence hints; TMDb promotes to high-confidence.
Zero rate-limit cost, catches films where description is the only source.

### 2b. IMDb TSV title+year resolver — **biggest single leverage**

Nightly GitHub Action downloads `title.basics.tsv.gz` (220 MB), builds a
sharded JSON index keyed on `normalize(title) | year` → `tconst`, publishes
to GitHub Pages. Archive Watch fetches the relevant shard on demand (or
bundles the whole ~50 MB index with the app — to be decided based on shard
size).

Resolution flow for an Archive item missing `urn:imdb:tt`:
1. Normalize title (lowercase, strip punctuation, collapse spaces)
2. Lookup `title|year` → tconst
3. Feed tconst into existing TMDb `/find` step

Expected impact: **62% → ~85% full-enrichment**. IMDb's title index covers
~10M titles including silents and shorts — catches the long tail TMDb
`/search` misses because of title ambiguity.

License: IMDb's non-commercial dataset explicitly permits personal/
non-commercial use (aligns with Decision 010). Re-distribution of the raw
TSV is forbidden — we ship a derived index (title+year+tconst tuples only),
which is defensible as factual extraction.

### 2c. Wikimedia Commons category walk — posters for pre-1940

When TMDb has no poster, query Commons via MediaWiki API:
```
action=query&list=categorymembers
  &cmtitle=Category:Films_of_{year}
  &cmtitle=Category:{country}_film_posters
```
Filter for JPEG/PNG, find files whose title matches the film's title
(exact or fuzzy), pick highest-resolution with ~2:3 aspect ratio.

Expected recall for silent-era posters where TMDb fails: ~30–40%. Strong
signal when it hits because Commons content is guaranteed free.

### 2d. Europeana — European films fallback (optional)

Gated on `language` ∈ {fr, de, it, nl, sv, ru, es, pl, da} or country
hint. Free API key, 10k req/day, CC0 metadata. Catches BFI, EYE, Deutsche
Kinemathek, CNC holdings that Hollywood-centric TMDb misses. Defer to
phase 3 — complexity cost is high, yield is the European tail.

### 2e. Library of Congress `/pictures/` — pre-1930 American posters

Final artwork fallback for pre-1930 US films. `loc.gov/pictures/
search/?q={title}+{year}+poster&fo=json`. Good for Paper Print Collection
era (1894–1912) and WPA-era ephemera. Already in scaffold's
`ArtworkResolver` — just needs wiring.

---

## Phase 3 — Continuous refresh via GitHub Action

A single workflow that runs weekly (or on-demand via `workflow_dispatch`):

```yaml
# .github/workflows/rebuild-catalog.yml — sketch, not final
on:
  schedule: [{ cron: '0 5 * * 1' }]   # Mondays 05:00 UTC
  workflow_dispatch:
jobs:
  rebuild:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
      - run: node tools/build-catalog.mjs --full --out=catalog-full.json
        env: { TMDB_BEARER_TOKEN: ${{ secrets.TMDB_BEARER_TOKEN }} }
      - run: node tools/build-catalog.mjs --curated --out=catalog.json
      - uses: peter-evans/create-pull-request@v6
        with:
          commit-message: "Weekly catalog refresh"
          title: "Catalog refresh — $(date +%F)"
          body: "Auto-generated. Review stats before merging."
```

Review gate: PR opens with the new catalog + stats delta. Curator eyeballs
the stats (match rate, new-item count, disappearance count), merges if
reasonable. Prevents a regression from Archive.org API drift silently
corrupting the live catalog.

On merge: GitHub Pages serves the updated `catalog-full.json`. tvOS app
checks `If-Modified-Since` on launch, downloads if newer, writes to
`Application Support/catalog-full.json`, uses at next launch.

---

## Phase 4 — Architecture changes to the builder

`tools/build-catalog.mjs` needs three new modes:

- `--seed-from-wikidata` : pulls Phase 1a, writes (archiveID, imdbID, qid,
  image) tuples as an input to the main loop, short-circuiting the cascade's
  first two steps.
- `--full` : walks every major collection via scrape cursor, applies quality
  floor, enriches. Produces `catalog-full.json`.
- `--curated` : produces the small bundled `catalog.json` from the
  `featured.json` curated shelves + top-N-per-category slice from the full
  catalog.

Quality floor:
- `downloads >= 500` for feature_films / classic_tv
- `downloads >= 50` for silent / prelinger / shorts (smaller pool expected)
- Has a playable derivative (tier 1–7 in DerivativePicker)
- Not in `featured.json.adultCollections`
- Has a title and a year OR (title and matched tconst)

Split output by category:
- `catalog.json` — bundled, ~500 items, all categories balanced
- `catalog-full.json` — full, 5–10k items
- Possibly: `catalog-{category}.json` — sharded per category if the full
  catalog grows past 20 MB

---

## Success metrics

| Metric | Today | Target (post-P1+P2) |
| --- | --- | --- |
| Total items | 53 | 5,000–10,000 |
| Fully enriched | 62% | ≥85% |
| Items with IMDb ID | 49% | ≥80% |
| Items with TMDb poster | 62% | ≥70% |
| Items per major category | ≤25 | ≥500 |
| Catalog refresh cadence | manual | weekly via GHA |
| First-launch data | bundled only | bundled + background-updated |

---

## What to build first, concretely

1. `tools/build-catalog.mjs`: add `--seed-from-wikidata` that runs the
   Phase 1a SPARQL, dumps a JSON of (archiveID, imdbID, qid, imageURL)
   tuples into `.cache/wikidata-seed.json`, then merges into the main
   enrichment loop before shelf resolution.
2. `tools/build-catalog.mjs`: add cursor pagination to scrape resolver so
   `--per-shelf` can go past 100.
3. `tools/build-imdb-index.mjs`: new tool. Downloads `title.basics.tsv.gz`,
   filters to `titleType ∈ {movie, tvMovie, short}`, emits
   `imdb-index.json` (or sharded by first letter). Committable — it's
   factual data, ~30–50 MB.
4. `tools/build-catalog.mjs`: add IMDb-index lookup step between
   description-regex and Wikidata.
5. `.github/workflows/rebuild-catalog.yml`: weekly PR-creating action.
6. App: add `CatalogRefreshService` in `Services/` that checks for
   `catalog-full.json` updates on launch, merges into the in-memory catalog.
