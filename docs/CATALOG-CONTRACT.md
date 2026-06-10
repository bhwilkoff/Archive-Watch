# Archive Watch — Catalog Data Contract

The shared data plane all four clients (tvOS, iOS, Web, Android) implement
against. Called for by Decision 028 and `docs/MULTIPLATFORM-PLAN.md` §1.
Source of truth for everything below: `tools/build_sqlite.py`,
`tools/catalog_release.py`, `.github/workflows/publish-db.yml`,
`ArchiveWatch/ArchiveWatch/Store/CatalogDB.swift`,
`ArchiveWatch/ArchiveWatch/Models/Catalog.swift`, `featured.json`,
`shared/editorial/collection_metadata.json`, `series/*.json`,
`catalog-index.json`. When this doc and the code disagree, the code wins —
then fix this doc in the same change.

---

## 1. Overview + the one rule

The catalog pipeline (Python, `tools/`, CI) compiles ~38k Archive.org items
plus editorial JSON into **one published SQLite database** with rights
(`excluded`, Decision 027), adult flags (`isAdult`, Decision 012), artwork,
and TV spines baked in at build time. Clients are **consumers only**.

**The one rule (Decision 028):** no client re-implements or re-hosts any part
of the pipeline. No client re-derives `isAdult`, re-audits rights, re-matches
TMDb, re-clusters TV, or publishes its own catalog copy. Every client
downloads the one published `catalog.sqlite` (or queries it in place), reads
the same editorial JSON, and reproduces the **query verbs** in §5 natively.
Sync state (favorites/progress/playlists) is per-ecosystem on the user's own
cloud and is **out of scope** for this contract.

---

## 2. Published assets

| Asset | URL | Host | CORS | Range |
|---|---|---|---|---|
| `catalog.sqlite.zz` (raw-DEFLATE DB, ~33 MB) | `https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite.zz` | Release `catalog-db` (rolling) | **none** | no 206 |
| `catalog.sqlite` (uncompressed, ~124 MB) | `https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog.sqlite` | Release `catalog-db` | **none** | no 206 |
| `catalog-manifest.json` | `https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-db/catalog-manifest.json` | Release `catalog-db` | **none** | — |
| `catalog.json.gz` (pipeline source, ~20 MB) | `https://github.com/bhwilkoff/Archive-Watch/releases/download/catalog-source/catalog.json.gz` | Release `catalog-source` | **none** | — |
| `featured.json` | `https://bhwilkoff.github.io/Archive-Watch/featured.json` | GitHub Pages | yes (`*`) | see note |
| `series/{seriesID}.json` | `https://bhwilkoff.github.io/Archive-Watch/series/{seriesID}.json` | GitHub Pages | yes (`*`) | — |
| `catalog-index.json` (~2.9 MB) | `https://bhwilkoff.github.io/Archive-Watch/catalog-index.json` | GitHub Pages | yes (`*`) | — |
| `collection_metadata.json` | bundled per app (repo: `shared/editorial/collection_metadata.json`; also served by Pages under `/Archive-Watch/shared/editorial/`) | repo / Pages | yes (`*`) | — |
| `seed.sqlite` (first-paint, top ~1,500 + TV + shelf items) | bundled in each app, committed at `ArchiveWatch/ArchiveWatch/seed.sqlite` | app bundle | n/a | n/a |

Notes:

- **Release assets send no CORS header** (verified — this is *why*
  `catalog-index.json` exists for the browser tool) and redirect (302) to
  `objects.githubusercontent.com`. Native clients (URLSession, OkHttp) are
  unaffected; a browser cannot `fetch()` them.
- **Byte-range caveat**: the repo's own measurement
  (`docs/architecture/catalog-delivery.md`, 2026-06-02) found `Range:`
  requests against our Pages returned `200` full-body, **not `206`** —
  while `docs/MULTIPLATFORM-PLAN.md` §2 plans the web client on
  `sql.js-httpvfs` range queries. **Re-verify 206 support before building the
  web data layer**; the fallback is `catalog-index.json` search + per-item
  fetch.
- Refresh cadence: `publish-db.yml` rebuilds + clobbers the `catalog-db`
  assets daily (cron `30 4 * * *`) and on `series/**` pushes. Use
  **ETag-conditional GET** (`If-None-Match`) on `catalog.sqlite.zz` — the
  tvOS client stores the ETag and treats 304 as "keep cache".
- `catalog.json.gz` (`catalog-source`) is **pipeline-internal** (Decision
  018). Clients must never consume it.
- The app does not fetch `catalog-manifest.json` today (tvOS goes straight
  to the `.zz` with ETag); it is published for tooling and for clients that
  want a cheap version probe. Shape:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-06-08T09:49:31.728Z",
  "itemCount": 28223,
  "seriesCount": 378,
  "episodeCount": 4456,
  "dbBytes": 123613184,
  "zzBytes": 33350107,
  "asset": "catalog.sqlite.zz"
}
```

---

## 3. SQLite schema (`schemaVersion` 1)

Exact DDL from `tools/build_sqlite.py::create_schema` + `create_indexes`.
(The module docstring there still mentions an `item_detail` table and a
`.gz` output — both stale; this DDL is what ships.)

```sql
CREATE TABLE items (
  archiveID TEXT PRIMARY KEY, title TEXT, year INTEGER, decade INTEGER,
  runtimeSeconds INTEGER, contentType TEXT, posterURL TEXT,
  hasRealArtwork INTEGER, artworkSource TEXT, imdbID TEXT,
  imdbRating REAL, imdbVotes INTEGER, popularityScore INTEGER,
  qualityScore INTEGER, isSilentFilm INTEGER, rightsStatus TEXT,
  contentRating TEXT, language TEXT, network TEXT, director TEXT,
  seriesID TEXT, yearEnd INTEGER, seasonsCount INTEGER, episodesCount INTEGER,
  isAdult INTEGER
);
CREATE TABLE item_json (archiveID TEXT PRIMARY KEY, json TEXT);
CREATE TABLE item_genres (archiveID TEXT, genre TEXT);
CREATE TABLE item_collections (archiveID TEXT, collection TEXT);
CREATE TABLE item_shelves (shelfID TEXT, archiveID TEXT, position INTEGER);
CREATE TABLE series (
  seriesID TEXT PRIMARY KEY, title TEXT, yearStart INTEGER, yearEnd INTEGER,
  overview TEXT, posterURL TEXT, backdropURL TEXT, networks_json TEXT,
  genres_json TEXT, creator TEXT, tvmazeID INTEGER,
  episodesCount INTEGER, canonicalEpisodesCount INTEGER
);
CREATE TABLE episodes (
  seriesID TEXT, seasonNumber INTEGER, episodeNumber INTEGER, title TEXT,
  overview TEXT, stillURL TEXT, airDate TEXT, year INTEGER,
  runtimeSeconds INTEGER, downloadURL TEXT, videoFile_json TEXT, position INTEGER
);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE VIRTUAL TABLE items_fts USING fts5(archiveID UNINDEXED, title, names, extra);

CREATE INDEX idx_items_type     ON items(contentType);
CREATE INDEX idx_items_decade   ON items(decade);
CREATE INDEX idx_items_pop      ON items(popularityScore DESC);
CREATE INDEX idx_items_series   ON items(seriesID);
CREATE INDEX idx_genres_genre   ON item_genres(genre);
CREATE INDEX idx_genres_item    ON item_genres(archiveID);
CREATE INDEX idx_coll_coll      ON item_collections(collection);
CREATE INDEX idx_items_director ON items(director);
CREATE INDEX idx_items_quality  ON items(qualityScore);
CREATE INDEX idx_shelves_shelf  ON item_shelves(shelfID);
CREATE INDEX idx_episodes_series ON episodes(seriesID, position);
```

### Table semantics

- **`items`** — lean scalar columns for WHERE/ORDER scans (the hot path).
  Never SELECT display fields from here; JOIN `item_json` and decode.
- **`item_json`** — the **full item as compact JSON** (§7), one row per item.
  This is the canonical record; the app decodes it with the same `Codable`
  model used for `catalog.json`. Clients JOIN it only for rows a screen shows.
- **`item_genres`** — `(archiveID, genre)` exploded from `item.genres`.
- **`item_collections`** — ONLY collections registered in
  `collection_metadata.json` (26 curated ids), not all ~48 noisy Archive
  memberships per item.
- **`item_shelves`** — Home-shelf membership: the item's stored `shelves`
  array UNION any `featured.json` dynamic shelf whose `collection:X` query
  token matches one of the item's collections. `position` is the
  **date-seeded rotation** order (below).
- **`series` / `episodes`** — compiled from `series/*.json`. `episodes.position`
  is a 0-based flat index across the file's seasons in document order; iterate
  `ORDER BY position` for canonical play order. `videoFile_json` /
  `networks_json` / `genres_json` are embedded JSON strings.
- **`items_fts`** — FTS5, **four columns**: `archiveID` (unindexed), `title`,
  `names` (director + cast names + producer), `extra` (genres + seriesName +
  network + countries + first 400 chars of synopsis). A bare
  `items_fts MATCH ?` searches all indexed columns; `byPerson` scopes with
  `names:"token"*`.
- **`meta`** — keys: `schemaVersion` (`"1"`), `generatedAt` (ISO-8601 string
  copied from catalog.json), `itemCount`, `seriesCount`. All values TEXT.

### Build-time computed/derived columns

| Column | Computed as (build_sqlite.py) |
|---|---|
| `isAdult` | `1` if item JSON `isAdult` is truthy, OR any item collection (lowercased) contains an adult marker substring. Markers = `featured.json.adultCollections` lowercased (fallback list `pron, adult, erotica, sexploitation, nudism, mature-content`), with `"fav-"` excluded. Decision 012. |
| `isSilentFilm` | `1` if item `isSilentFilm` is truthy OR `contentType == "silent-film"`. |
| `hasRealArtwork` | `1` if item `hasRealArtwork` is truthy OR `artworkSource` not in (`null`, `"archive"`). Note: `"generated"` frame-covers count as real artwork here (Decision 023); the *professional*-art distinction lives only in the client model (`hasProfessionalArtwork` excludes `"generated"`). |
| `decade` | NOT computed here — copied from item JSON (set upstream by `remediate_catalog.py` / `build-catalog.mjs` as `floor(year/10)*10`, nulled when the year is implausible). |

### Rows that never reach the DB

1. **`excluded == true`** (rights audit, Decision 027): skipped entirely from
   `items`/`item_json`/FTS, in both the full DB and the seed. The item stays
   in `catalog.json` (reversible flag).
2. **IMDb dedup**: one best row per `imdbID` (items without an id all kept).
   Best = highest `(score, imdbVotes, archiveID)` where score = +8 real
   artwork, +4 `enrichmentTier=="fullyEnriched"`, +2 `.mp4` downloadURL,
   +1 has `runtimeSeconds`. Clients never dedup in memory.

### Daily shelf rotation

`item_shelves.position` is shuffled per shelf with seed
`random.Random(f"{shelfID}:{rotateSeed}")` where `rotateSeed` defaults to the
UTC build date `YYYYMMDD`. Leading titles rotate daily; the **query** still
orders `hasRealArtwork DESC, position`, so rotation only reshuffles within
the real-artwork band — a poster-less tile never leads.

### seed.sqlite selection

Same schema, subset of items (post-`excluded` filter): every
`contentType == "tv-series"` card, every item with a non-empty `shelves`
array, plus the top **1,500** by `popularityScore`. All series/episodes rows
included. Purpose: instant first paint from the bundle while the full DB
downloads; swap when the full DB validates.

---

## 4. Compression contract (Decision 019)

`catalog.sqlite.zz` is **raw DEFLATE** (RFC 1951, no zlib header, no gzip
container): Python `zlib.compressobj(9, zlib.DEFLATED, wbits=-15)`. It is
served `application/octet-stream` with **no `Content-Encoding`**, so HTTP
stacks will not auto-decompress — every client inflates explicitly:

| Platform | Inflate with |
|---|---|
| tvOS / iOS | `Compression` framework, `compression_stream` + `COMPRESSION_ZLIB` (its native input IS raw DEFLATE). **Stream file→file in ~64 KB chunks**; let the framework advance `src_ptr`/`src_size` through a stable buffer and refill only when a chunk is fully consumed — re-binding the source pointer every iteration silently corrupts well-compressing data (verified bug). See `CatalogRefreshService.inflate`. |
| Android | `java.util.zip.Inflater(nowrap = true)` (`nowrap` = raw DEFLATE), streamed. |
| Web | `DecompressionStream("deflate-raw")` (or pako `{ raw: true }`). Only relevant if the web client downloads the DB rather than range-querying. |

Never publish gzip or zlib-wrapped variants under the `.zz` name — the
shipped tvOS inflater expects raw DEFLATE and a `.gz` fails outright.

---

## 5. Query verbs (every client reproduces these)

Reference implementation: `CatalogDB.swift` (tvOS/iOS, reused verbatim).
Other platforms implement the same verbs with the same SQL semantics. All
item-returning verbs `SELECT j.json FROM … JOIN item_json j` and decode; all
are LIMIT-bounded.

### The four standard filter clauses

| Clause | SQL | Meaning |
|---|---|---|
| `adultAnd` | `AND i.isAdult = 0` | Decision 012 filter; applied when the user setting "hide adult" is on (**default on**). Toggling off removes the clause. |
| `typeAnd` | `AND i.contentType NOT IN ('…',…)` | User-hidden content-type categories (Settings). Empty set → no clause. App-defined values, safe to inline. |
| `homeAnd` | `AND (i.rightsStatus IN ('public_domain','creative_commons') OR (i.year >= 1888 AND i.year <= 1977))` | Home-advertising gate: never headline a modern, uncertain-rights film. Applied to **Home surfaces only** — never Browse/Search. `year IS NULL` + non-PD fails it (intended). |
| `notCommercial` | `AND i.contentType != 'commercial'` | Commercials are interstitial/collection content only. Applied to every general surface; only the three intentional surfaces omit it (Commercials collection via `byCollection`, `randomPlayable(contentType:"commercial")`, `randomCommercials`). |

### Verbs

| Verb | Inputs | SQL semantics | Filters |
|---|---|---|---|
| `shelf(shelfID, limit=80)` | shelf id | `item_shelves JOIN item_json JOIN items WHERE shelfID=? ORDER BY i.hasRealArtwork DESC, s.position LIMIT n` | adult, home, notCommercial, type |
| `itemsByIDs(ids)` | archiveIDs | `item_json WHERE archiveID IN (…)`, then reorder client-side to the requested order | none (curated lists bypass filters) |
| `browse(contentType?, decade?, genre?, year?, sort, limit=60, offset, homeOnly=false)` | facets + sort + page | base `WHERE i.contentType != 'tv-series'`; `+ i.contentType = ?` / `i.decade = n` / `i.year = n`; genre via `JOIN item_genres g ON g.archiveID=i.archiveID AND g.genre=?`. Sorts: popular → `popularityScore DESC, imdbVotes DESC`; alphabetical → `title COLLATE NOCASE ASC`; newest → `year DESC`; oldest → `year ASC`. `LIMIT n OFFSET m`. | adult, type; notCommercial **unless** caller asked `contentType == "commercial"`; home only if `homeOnly` |
| `browseCount(…)` | same facets | `COUNT(*)` mirroring `browse`'s WHERE exactly (no limit) — real grid totals | same as browse |
| `browsePageJSON(…)` | same | same SQL, returns raw JSON strings so decode can run off the main thread | same |
| `search(query, limit=200)` | free text | `items_fts MATCH ? ORDER BY rank` joined to items/item_json. Query hygiene: lowercase, split on non-alphanumerics, drop tokens < 2 chars, each token quoted + `*` suffix, joined by spaces (implicit AND). | adult, notCommercial, type |
| `seriesCards()` | — | `items WHERE contentType='tv-series' ORDER BY episodesCount DESC` | adult, type |
| `item(archiveID)` | id | single `item_json` row | none (Detail must resolve anything) |
| `related(to, limit=20)` | item | same `contentType`, not self, `ORDER BY popularityScore DESC` | adult, type |
| `hiddenGems(limit=20)` | — | `hasRealArtwork=1 AND qualityScore>=60 AND popularityScore<=40 ORDER BY qualityScore DESC` | adult, home, notCommercial, type |
| `topDirectors(minFilms=3, limit=4)` | — | `GROUP BY director HAVING count>=n ORDER BY c DESC, director`, requiring non-empty director + `hasRealArtwork=1` | adult, home, notCommercial, type |
| `byDirector(name, limit=20, homeOnly=false)` | director | `director=? AND hasRealArtwork=1 ORDER BY popularityScore DESC` | adult, notCommercial, type; home if homeOnly |
| `byPerson(name, limit=120)` | person | FTS with **column-scoped** all-token query `names:"tok"* names:"tok2"*` so "John Wayne" doesn't pull every John; `ORDER BY popularityScore DESC` | adult, type |
| `byCollection(collection, limit=2000)` | registered collection id | `item_collections WHERE collection=? ORDER BY popularityScore DESC` | adult only (this is how commercials surface) |
| `collectionCount(collection)` | id | `COUNT(*)` of the above | adult |
| `randomPlayable(contentType?)` | optional type | non-series, `ORDER BY RANDOM() LIMIT 1`; excludes commercials unless asked for them | adult, type |
| `randomCommercials(limit=12)` | — | `contentType='commercial' ORDER BY RANDOM()` (channel-break batches) | adult, type |
| `randomSeries()` | — | `contentType='tv-series' ORDER BY RANDOM() LIMIT 1` | type |
| `randomByGenre(genres)` | genre list | JOIN item_genres `IN (…)`, non-series, `ORDER BY RANDOM() LIMIT 1` | adult, notCommercial, type |
| `seriesCard(slug)` | seriesID | `items WHERE seriesID=? AND contentType='tv-series' LIMIT 1` | none |
| `decadeCounts()` | — | `GROUP BY decade` with sanity clamp `decade BETWEEN 1890 AND 2029` | adult, notCommercial |
| `topGenres(limit=24)` | — | `item_genres GROUP BY genre ORDER BY count DESC, genre` | adult |
| `searchableCount` | — | live `COUNT(*) FROM items_fts` (not the meta value — reflects seed vs full DB) | none |
| `metaInt(key)` / `metaString(key)` | meta key | `SELECT value FROM meta WHERE key=?` | none |

Invariants every implementation keeps:

- Open the DB **read-only**; treat a failed open or a missing
  `meta.itemCount` as "not our DB".
- Decode only the rows a screen shows; never materialize the whole catalog
  in memory (Decision 017's entire point).
- Curated content (`itemsByIDs`, `item`) bypasses the home gate but UI
  surfaces that *advertise* (shelves, gems, directors) are home-gated.

---

## 6. JSON editorial files

### 6.1 `featured.json` (bundled in each app; also on Pages for the dashboard)

Top-level: `version` (1), `schemaVersion`, `updatedAt`, `notes`,
`categories[]`, `shelves[]`, `browseFacets{}`, `adultCollections[]`,
`randomActions{}`, `donationLink{}`.

- **Category**: `{ id, displayName, shortName?, accent (hex), posterAspect?, note? }`.
  9 categories incl. `commercial` (which intentionally has **no Home shelf**).
- **Shelf**: `{ id, title, subtitle?, category?, type, items?|query?, sort?, limit?, source? }`.
  `type` is `"curated"` (explicit `items: [{archiveID, note?}]`),
  `"dynamic"` (Archive scrape `query` + `sort` + `limit` — also the source of
  the build-time `collection:X` → shelf mapping in §3), or `"seeded"`
  (`source: "wikidata-p724"`, pipeline-resolved).
- `adultCollections`: `["adult", "moviesandfilms_adult", "stagvideos"]` —
  feeds the build-time `isAdult` substring markers.
- `browseFacets`: `decades` (1890–2020), `genres` (16), `runtimeBuckets`.
- `randomActions`: configs for `randomMovie` / `randomCategory` /
  `randomCollection` (Decision 014).
- `donationLink`: `{ label, url: "https://archive.org/donate" }` (Decision 010).

Example shelf:

```json
{ "id": "film-noir", "title": "Film Noir",
  "subtitle": "Shadows and second thoughts — the Archive's curated noir collection",
  "category": "feature-film", "type": "dynamic",
  "query": "mediatype:movies AND collection:Film_Noir",
  "sort": ["downloads desc"], "limit": 48 }
```

### 6.2 `shared/editorial/collection_metadata.json` (bundled per app)

The ONLY browseable collections (26 entries) — `item_collections` stores
just these ids. Never show a raw slug; look up the title here, fall back to
de-slugging for unknown ids.

```json
{ "id": "Film_Noir", "title": "Film Noir",
  "blurb": "Shadows, second thoughts, venetian-blind lighting.",
  "accent": "#FF5C35", "category": "feature-film" }
```

Fields: `id` (Archive slug, verbatim in queries), `title`, `blurb`,
`accent` (hex), `category` (app contentType vocabulary; optional).

### 6.3 `series/{seriesID}.json` (fetched lazily from Pages; Decision 016)

Per-show episode spine, version 2. The catalog carries only the series
*card* (a `Catalog.Item` with `contentType == "tv-series"`); the full
episode list loads on demand from
`https://bhwilkoff.github.io/Archive-Watch/series/{seriesID}.json`.
**seriesID slugs can contain non-ASCII** (e.g.
`1973-la-isla-misteriosa-y-el-capitán-nemo-2023`) — percent-encode the path
component or the fetch 404s (real iOS bug). Cache: memory + disk,
network-first with disk fallback. New/renamed files take effect only after a
push to `main` (Pages deploy).

Shape (from `series/26-men-1957.json`):

```json
{
  "version": 2, "seriesID": "26-men-1957", "tvmazeID": 1234,
  "title": "26 Men", "yearStart": 1957, "yearEnd": 1959,
  "overview": "…", "posterURL": "https://…", "backdropURL": null,
  "genres": ["western"], "networks": ["Syndication"], "creator": null,
  "seasons": [
    { "seasonNumber": 1,
      "episodes": [
        { "archiveID": "…", "seasonNumber": 1, "episodeNumber": 2,
          "title": "…", "overview": null, "stillURL": "https://…",
          "airDate": "1957-10-15", "year": 1957, "runtimeSeconds": 1538,
          "videoFile": { "name": "…", "format": "h.264", "sizeBytes": 1, "tier": 1 },
          "downloadURL": "https://archive.org/download/{id}/{file}" } ] } ],
  "episodesCount": 26, "canonicalEpisodesCount": 78,
  "tvdbID": "…", "artworkSource": "tvdb",
  "cast": [ { "name": "…", "character": "…", "order": 0, "profilePath": null } ]
}
```

`seasonNumber` may be `null` (render as "More Episodes").
`canonicalEpisodesCount` (TVmaze full run) vs `episodesCount` (what we have)
drives the "X of Y" affordance. `tvdbID`/`artworkSource`/`cast` are additive.

### 6.4 `catalog-index.json` (Pages; web search fallback / editorial tool)

Slim positional-tuple index because Release assets have no CORS. Excludes
`excluded` items and adult-collection items (it feeds a PUBLIC tool); sorted
by popularity.

```json
{ "schema": 1, "updatedAt": "", "count": 32257,
  "fields": ["id", "title", "year", "contentType"],
  "items": [ ["WhiteZombie", "White Zombie", 1932, "feature-film"], … ] }
```

Each item is `[archiveID, title, year|null, contentType]` — derive thumbnails
in the browser as `https://archive.org/services/img/{archiveID}`.

---

## 7. Item JSON schema (`item_json.json` / `catalog.json` items)

Canonical decoder: `Models/Catalog.swift` `Catalog.Item`. The catalog file
top level is `{ version: 2, generatedAt, generator, stats{}, items[] }`.

**Additive-fields rule**: every field added after the v1 schema is optional;
unknown keys MUST be ignored (pipeline-only keys ride along in `item_json`).
New pipeline fields are always additive — clients never require them.

Core fields (present on every item; nullable as marked):

| Field | Type | Notes |
|---|---|---|
| `archiveID` | string | PK; the Archive.org identifier |
| `title` | string | |
| `year`, `decade` | int? | decade = floor(year/10)*10, nulled if implausible |
| `runtimeSeconds` | int? | |
| `synopsis` | string? | HTML-stripped by the pipeline; strip again defensively |
| `collections`, `subjects` | [string] | raw Archive memberships/subjects |
| `mediatype`, `language` | string? | |
| `imdbID`, `tmdbID`, `wikidataQID`, `tvmazeID` | string?/int? | external ids |
| `videoFile` | object? | `{ name, format, sizeBytes?, tier }` |
| `downloadURL` | string? | direct playable URL (§8); null = not playable |
| `posterURL`, `backdropURL` | string? | absolute URLs |
| `hasRealArtwork` | bool? | see §3 computed column |
| `artworkSource` | string | one of: `tmdb, generated, archive, commons, omdb, tvdb, tvmaze, fanart, external, aapb, wikidata, none` |
| `contentType` | string | `feature-film, silent-film, short-film, animation, tv-series, tv-special, documentary, newsreel, ephemeral, home-movie, commercial` |
| `genres`, `countries` | [string] | |
| `cast` | [object] | `{ name, character?, order, profilePath? }` — `profilePath` may be a bare TMDb path (prefix `https://image.tmdb.org/t/p/w185`) or absolute |
| `director`, `producer`, `seriesName`, `network` | string? | |
| `enrichmentTier` | string? | `fullyEnriched / identifierResolved / archiveOnly / archiveCurated` |
| `shelves` | [string] | shelf ids (unioned with collection-derived shelves at build) |

Optional/additive fields (decode-tolerant; absent on older catalogs):

| Field | Type | Source / meaning |
|---|---|---|
| `rightsStatus` | string? | `public_domain` (96%), `creative_commons`, `rights_reserved_free_stream`, `unknown` |
| `qualityScore`, `popularityScore` | int? | pipeline scores (0–100-ish) |
| `bestSourceType` | string? | |
| `isSilentFilm` | bool? | authoritative multi-signal flag; overrides contentType check when present |
| `isAdult` | bool? | item-level adult flag (Decision 012); absent → not adult |
| `imdbRating` (double?), `imdbVotes` (int?), `contentRating` (string?), `synopsisSource` (string?) | | OMDb backfill |
| `colorMode` | string? | `"color"` / `"bw"` from frame analysis (Decision 025); nil = unclassified |
| `seriesID`, `yearEnd`, `seasonsCount`, `episodesCount`, `networks`, `creator` | | tv-series cards only; `archiveID` doubles as the series slug |

Pipeline-only keys present in the JSON that clients MUST ignore (the Swift
model has no properties for them): `excluded`, `rightsConfirmed`,
`rightsAudit`, `rightsEvidence`, `archiveLicense`, `archiveDate`,
`matchVerified`, `agentReviewHash`, `discoverySource`. (`excluded` items
never reach the DB anyway — see §3.)

Derived predicates clients should mirror (names from the Swift model):
`hasDesignedArtwork = hasRealArtwork ?? (artworkSource != "archive")`;
`hasProfessionalArtwork = hasDesignedArtwork && artworkSource != "generated"`
(Home hero/poster-led surfaces use the professional one);
`isSilent = isSilentFilm ?? (contentType == "silent-film")`;
`isBlackAndWhite = colorMode == "bw"`.

---

## 8. Video + artwork URL contracts

### Video

- `downloadURL` is the playable URL, **baked in at build time** — clients do
  no derivative selection at runtime. Canonical form:
  `https://archive.org/download/{identifier}/{file}` (e.g.
  `https://archive.org/download/House_On_Haunted_Hill.avi/The_House_on_Haunted_Hill.mp4`).
  Archive 302-redirects to a storage node; follow it.
- Progressive MP4 (H.264), highest-quality derivative by policy (Decision
  021 — do NOT add a bitrate ceiling).
- Archive resets idle connections; each platform needs a resilience layer
  that **resumes from the exact byte offset** instead of restarting/flushing
  (Apple: `ResilientStreamLoader`, Decision 021; Android: Media3 +
  `LoadErrorHandlingPolicy`; Web: `<video>` ranged GETs + reconnect-and-seek
  wrapper). `<video src>` needs no CORS.

### Artwork

Resolution order per item:

1. `posterURL` / `backdropURL` from the catalog (absolute; already the
   product of the enrichment cascade, Decision 008). Hosts include
   `image.tmdb.org` (`https://image.tmdb.org/t/p/{size}{path}`, e.g. `w500`),
   Wikimedia, TheTVDB, and the generated-cover host.
2. Generated frame-covers (Decision 023):
   `https://archive.org/download/archivewatch-covers/{slug}.{hash8}.jpg`,
   marked `artworkSource: "generated"`.
3. Final fallback when `posterURL` is null/broken: the Archive thumbnail
   service `https://archive.org/services/img/{archiveID}` (small, unstyled),
   or a procedural typographic card.
4. Episode `stillURL` (TVmaze/TVDB) and cast `profilePath` (TMDb `w185`
   prefix when bare) per §6.3/§7.

TMDb usage requires the verbatim attribution notice + logo on an About
screen (Decision 007) on every platform.

---

## 9. Versioning + integrity

- **Schema version**: `meta.schemaVersion` (currently `1`) and
  `catalog-manifest.json.schemaVersion`. A breaking DDL change bumps it; the
  published asset is a **rolling clobber** under the same URL, so a breaking
  change requires either a new asset name or clients that tolerate both —
  prefer additive columns/keys (the JSON-in-`item_json` design exists so most
  field additions need **no** schema change).
- **Download validation (every client, in order)** — from
  `CatalogRefreshService` + `CatalogDB.init`:
  1. ETag-conditional GET; on 304 or any failure, keep the cached DB.
  2. Inflate to a **staging file**, never over the live DB.
  3. Size floor: inflated size **≥ 10,000,000 bytes** (`minValidBytes`) or
     discard. (Decision 017 also recommends `PRAGMA integrity_check` + a
     row-count floor; the shipped tvOS client uses size-floor + the open
     probe below — do at least that much.)
  4. Atomic rename into place; store the new ETag only after the swap.
  5. Open read-only and probe `meta.itemCount` — if absent, treat the file
     as corrupt and fall back (bundled `seed.sqlite` is the floor state).
- **Pipeline side (context, not client work)**: catalog mutations are
  additive and shrink-guarded (Decision 020 — a rebuild merges into the
  fetched catalog and aborts if the result would shrink); rights hiding is a
  reversible flag, never a delete (Decision 027). Clients can therefore
  assume the published DB never silently loses the catalog, only grows or
  intentionally hides.
- **Freshness**: `meta.generatedAt` / manifest `generatedAt` identify the
  build. The daily publish runs at 04:30 UTC; clients should refresh
  opportunistically (launch/background), not on a tight timer.
