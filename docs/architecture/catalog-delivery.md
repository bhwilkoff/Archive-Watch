# Catalog delivery architecture — keeping the database lean on tvOS

*Researched 2026-06-02. Status: proposed (see DECISION 017).*

## The problem

The app ships a bundled seed catalog and refreshes a full `catalog.json`
from GitHub Pages (`CatalogRefreshService`), decoding the whole thing into
`AppStore` as `[Catalog.Item]`. Home/Browse/Search/Detail all read from that
in-memory array.

At 29,782 items this works, but it does not scale, and the binding
constraint is **memory, not download**:

| Concern | Measured / researched | Verdict |
|---|---|---|
| Download size | `catalog.json` is 97 MB raw but **18.9 MB over the wire** — GitHub Pages serves `content-encoding: gzip` and URLSession auto-decompresses. | Fine now; ~60 MB gzipped at 100k. Not the crisis. |
| **Resident memory** | The 97 MB JSON is decompressed in RAM, then decoded into ~29k structs held in `@Observable`. Easily 150–250 MB resident today; **500 MB–1 GB at 100k**. | **The real limit.** Apple TV 4K has 3 GB RAM shared with tvOS + 4K AVPlayer decode buffers. This is jetsam territory as we grow. |
| Bandwidth | GitHub Pages soft cap **100 GB/month**. A full refresh is ~19 MB now. ETag/`Last-Modified` are present, so unchanged catalogs aren't re-downloaded. | OK at low scale; every catalog change re-pushes 19–60 MB to every user. |
| Local writable storage | tvOS only allows writes to `Library/Caches` (purgeable) + `tmp`. No Application Support/Documents. | Cache the catalog in `Caches` (already do). |
| HTTP range requests | Tested against our Pages: `Range:` returns `200` full body, not `206`. | **Byte-range partial fetch is out.** |

## Options considered

### A. Sharded JSON (lean index + on-demand detail)
Split into a compact browse/search **index** (id, title, year, decade,
contentType, posterURL, sort keys, searchable names, shelf membership) plus
per-shard/per-item **detail** (synopsis, full cast, backdrop, videoFile,
downloadURL, subjects) fetched when a Detail screen opens.

- **Pros:** incremental; reuses Codable; no new dependency; resident memory
  drops to ~the index.
- **Cons:** search still needs the whole index resident; the index itself
  grows (100k × ~80 B ≈ 8 MB raw, decoded to a big array); lots of files to
  manage; doesn't fundamentally fix the "hold it all in RAM" model — just
  shrinks the constant.

### B. Prebuilt SQLite served from GitHub Pages  ← recommended
The pipeline exports `catalog.sqlite` (with an FTS5 search index), gzips it,
and publishes `catalog.sqlite.gz` to Pages. The app downloads it once,
gunzips into `Library/Caches`, opens it **read-only**, and **queries** for
shelves / browse / search / detail. Only the rows for the current view are
ever resident.

- **Pros:** fixes memory at the root (on-disk queries; resident = visible
  rows, KB–MB); scales to 1M+ items; **FTS5** gives fast title/cast search
  without loading everything; single static file on Pages; **SQLite is built
  into tvOS** (`libsqlite3`, FTS5 since iOS/tvOS 11) so no third-party Swift
  package (honors the project's no-SPM rule).
- **Cons:** bigger app change (a SQLite data layer replaces the in-memory
  array as the source of truth for derived lists); prebuilding the DB in the
  pipeline (trivial — Python's stdlib `sqlite3`); whole-file re-download on
  update (gzipped, fine; version the filename for cache-busting).

### C. Real backend / search service
Rejected — the project is explicitly backend-free (Decision 010/011);
GitHub Pages static hosting is a hard constraint and a feature (zero cost,
zero ops).

## Recommendation: Option B (prebuilt SQLite on Pages), phased

SQLite-on-disk is the architecturally-correct fit for "a large catalog on a
memory-constrained 10-foot device served from static hosting." It is exactly
the shape Apple's bundled `libsqlite3` + FTS5 exist for.

### Schema (sketch)
```
items(archiveID PK, title, year, decade, contentType, runtimeSeconds,
      posterURL, hasRealArtwork, imdbID, imdbRating, popularityScore,
      isSilent, rightsStatus, ...lean browse fields...)
item_detail(archiveID PK, synopsis, cast_json, backdropURL, videoFile_json,
            downloadURL, subjects_json, director, ...heavy fields...)
shelf_members(shelfID, archiveID, position)
items_fts USING fts5(title, names, content='items', ...)   -- search
series(seriesID PK, ...), episodes(seriesID, season, number, ...)
meta(key, value)   -- generatedAt, schemaVersion, counts
```
`item_detail` split keeps the hot path (browse/search) reading only lean
columns; detail columns are fetched by PK on the Detail screen.

### App data layer
- `CatalogDB` actor wrapping `libsqlite3` (read-only, `Caches` path).
- Replace `AppStore` derived lists with queries:
  - Home shelves → `SELECT ... JOIN shelf_members WHERE shelfID=? ORDER BY position LIMIT n`.
  - Browse grid → `WHERE contentType=? AND decade=? ORDER BY popularity LIMIT/OFFSET` (paginated).
  - Search → `items_fts MATCH ?`.
  - Detail → `item_detail WHERE archiveID=?` (lazy).
  - **Dedup-by-IMDb** moves into the export (pick best row per IMDb id at
    build time) instead of an in-memory pass.
- Bundled seed: a small prebuilt `seed.sqlite` (or keep the JSON seed for
  first paint, then swap to the downloaded DB).

### Refresh
- `CatalogRefreshService` downloads `catalog.sqlite.gz` with `If-None-Match`
  (ETag). On change: gunzip to a temp file in `Caches`, validate
  (`PRAGMA integrity_check` + row count vs. a floor), atomically swap, reopen.
- Version the published filename (`catalog-<generatedAt>.sqlite.gz`) + a tiny
  `catalog-manifest.json` pointer, so CDN caching never serves a stale DB.

### Pipeline
- New `tools/build_sqlite.py`: read the committed `catalog.json` + `series/`
  → write `catalog.sqlite` (+ FTS5) → gzip. Runs after the existing catalog
  writers. The JSON stays as the editorial/source-of-truth + dashboard input;
  SQLite is the app-delivery format.

### Phasing (non-breaking)
- **Phase 1:** `build_sqlite.py` + publish `catalog.sqlite.gz` to Pages
  alongside the JSON. App unchanged. Verifiable independently.
- **Phase 2:** `CatalogDB` + migrate Home/Browse/Search/Detail to queries
  behind the existing view APIs; keep JSON seed for first paint.
- **Phase 3:** Retire the in-app monolithic JSON load; JSON remains for the
  dashboard + pipeline.

### Interim mitigations (cheap, do anytime)
- Keep the bundled seed lean (done — bulk ingest is `--no-seed`).
- Ensure refresh uses ETag/`If-None-Match` (already partly there).
- Move the IMDb dedup + heavy-field trimming into the export so even the
  JSON path carries less.

## Sources
- GitHub Pages limits (1 GB site, 100 GB/mo bandwidth, on-the-fly gzip):
  https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits
- Live header probe of our Pages site (gzip 97 MB→18.9 MB, ETag present,
  range → 200 not 206): captured 2026-06-02.
- SQLite FTS5 (iOS/tvOS 11+, external-content tables, inverted index):
  https://sqlite.org/fts5.html ; https://www.nutrient.io/blog/leveraging-sqlite-full-text-search-on-ios/
- URLSession auto gzip (`Accept-Encoding: gzip`, transparent decompress):
  https://developer.apple.com/forums/thread/84036
- Apple TV 4K RAM = 3 GB (shared with system + AVPlayer).
