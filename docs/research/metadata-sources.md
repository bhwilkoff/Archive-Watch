# Metadata & Imagery Sources — Research Log

Archive.org alone is not sufficient for a first-class TV app. Its own
metadata is uneven and its thumbnail service is utilitarian at best. The
strategy below layers **TMDb** (primary enrichment), **Wikidata**
(identifier graph + fallback), **Wikimedia Commons** (public-domain
artwork), and **Library of Congress** (early-cinema gap filler) on top of
Archive.org's native metadata to produce a well-tagged, well-illustrated
catalog suitable for a cinematic 10-foot interface.

---

## The core insight: identifier chaining

Most Archive.org items in the `mediatype:movies` space carry an
`external-identifier` field that looks like:

```
urn:imdb:tt0032138
```

That IMDb ID is the key that unlocks the entire commercial metadata graph:

```
Archive.org item
  └─ external-identifier: urn:imdb:tt0032138
       └─ TMDb /find/tt0032138?external_source=imdb_id
            ├─ poster_path, backdrop_path
            ├─ overview, tagline, genres, runtime
            ├─ cast & crew (via /credits)
            ├─ content ratings, release dates
            └─ wikidata_id (via /external_ids)
                 └─ Wikidata Q-number
                      ├─ P18 (image) — Wikimedia Commons file
                      ├─ P724 (Internet Archive ID) — cross-check
                      └─ P345 (IMDb ID) — cross-check
```

**When the IMDb ID is missing,** the graph can still be traversed in
reverse: Wikidata stores the Internet Archive identifier as property
**P724**. A single SPARQL query returns every Wikidata item whose P724
matches our Archive ID, and from there we can pull an IMDb ID, an image,
or both.

This identifier chain is the backbone of the enrichment pipeline. The
derivative picker and artwork resolver both depend on it.

---

## Source-by-source evaluation

### Archive.org (base layer)

**Role:** Source of truth for the video file and the authoritative
identifier. Also the catalog we paginate for browse/search screens.

**Strengths**
- Free, unauthenticated read. No CORS on native clients.
- Scrape API paginates deeply via cursor; no 10k cap.
- Items ship h.264 MP4 derivatives that stream directly in AVPlayer.
- Rich collection taxonomy (`feature_films`, `classic_tv`,
  `prelinger`, `silent_films`, `classic_cartoons`, etc.).

**Weaknesses**
- Metadata quality is inconsistent: some items have full descriptions and
  subjects, others are near-empty.
- Thumbnails (`archive.org/services/img/{id}`) are often uploader-chosen
  frame grabs or low-res lobby-card scans. Aspect ratios vary.
- No standard genre taxonomy. `subject` is a free-text tag field.
- Uploaders sometimes miscategorize content (adult items drift into
  general collections).

**Key fields we actually use**
- `identifier` — primary key, stable
- `title`, `description`, `creator`, `date`, `year`, `runtime`
- `subject` (free-text tags; normalize into our own taxonomy)
- `collection` (array; drives shelf grouping)
- `external-identifier` (urn:imdb:tt... when present)
- `mediatype` (filter to `movies`)
- `files` (derivative list; pick h.264 MP4)
- `downloads`, `week`, `month` (proxies for popularity)

### TMDb (primary enrichment layer)

**Role:** Posters, backdrops, cast, genre, runtime, rating — the
metadata layer that makes a card look like a card and a detail page look
like a detail page.

**Key endpoints**
- `GET /3/find/{imdb_id}?external_source=imdb_id` — match by IMDb ID
- `GET /3/movie/{tmdb_id}` — full detail
- `GET /3/movie/{tmdb_id}/images` — all posters/backdrops with
  language tags and vote counts
- `GET /3/movie/{tmdb_id}/external_ids` — Wikidata Q-number
- `GET /3/search/movie?query=&year=` — fallback when no IMDb ID

**Free tier**
- Non-commercial use, no cost. Must display "This product uses the TMDB
  API but is not endorsed or certified by TMDB" and show the TMDB logo.
- ~40 req / 10s per IP. More than enough; we enrich lazily and cache
  aggressively.

**Image CDN**
- `https://image.tmdb.org/t/p/{size}/{path}` — `w500`, `w780`, `w1280`,
  `original`. We pick `w780` for grid posters and `w1280` for hero.

**Commercial note**
- Commercial use requires negotiated terms. For a public TestFlight or
  App Store release, we file the non-commercial use case or contact TMDb
  before App Store submission. This is a **Decision we must log** before
  shipping.

### Wikidata (fallback + identifier graph)

**Role:** The glue. When TMDb lookup fails, or the Archive item has no
IMDb ID, Wikidata gets us unstuck.

**Key queries**

Given an Archive identifier, find IMDb ID + image:

```sparql
SELECT ?item ?imdb ?image WHERE {
  ?item wdt:P724 "IDENTIFIER_HERE" .
  OPTIONAL { ?item wdt:P345 ?imdb. }
  OPTIONAL { ?item wdt:P18 ?image. }
}
```

Given a title + year, find films with Internet Archive IDs:

```sparql
SELECT ?item ?label ?archiveId ?image WHERE {
  ?item wdt:P31/wdt:P279* wd:Q11424.      # instance of film
  ?item wdt:P724 ?archiveId.
  ?item rdfs:label ?label.
  FILTER (LANG(?label) = "en")
  OPTIONAL { ?item wdt:P18 ?image. }
}
```

**Strengths**
- Public domain (CC0).
- Single endpoint: `https://query.wikidata.org/sparql`.
- Structured film/TV data with stable properties.
- Can return Commons image URLs directly.

**Weaknesses**
- Coverage is excellent for notable films, thin for obscure ephemera.
- SPARQL is powerful but fragile — queries must be simple and cached.
- Query service has its own rate limits. Batch and cache.

### Wikimedia Commons (artwork fallback)

**Role:** Filler artwork when TMDb lacks a poster — especially for very
old films, government films, and ephemeral industrial films that TMDb
doesn't track.

**Endpoints**
- MediaWiki API: `https://commons.wikimedia.org/w/api.php`
- Category browsing: `Category:Film_posters`,
  `Category:Films_in_the_public_domain`, subcategories by decade.
- SPARQL: can fetch `P18` image URLs resolved to actual file URLs.

**Strengths**
- 100M+ files, all free-license or public domain.
- Lobby cards, posters, production stills, title cards.

**Weaknesses**
- Not matched to identifiers — requires fuzzy title/year lookup.
- Image sizing: must pass through the thumb service
  (`commons.wikimedia.org/w/thumb.php?...`) to avoid downloading
  multi-MB originals.
- Attribution required. File license pages must be fetched to display
  the correct credit.

### Library of Congress (early cinema gap filler)

**Role:** Authoritative source for National Film Registry entries and
pre-1950 American cinema. Fills in where TMDb's poster coverage is
weakest.

**Endpoints**
- `https://www.loc.gov/search/?q=&fo=json` — generic search, JSON
  response (append `?fo=json` to any loc.gov URL).
- Prints & Photographs (PPOC) has posters for classic theaters and
  films.

**Strengths**
- Public domain. No auth. No attribution legally required (though polite).
- High-quality scans of period promotional material.

**Weaknesses**
- No identifier linkage to IMDb/TMDb.
- Title/year fuzzy matching only.
- Slower API than TMDb.

**Use case**
- Dedicated "National Film Registry" shelf — curated list of LoC
  identifiers we bundle with the app. Artwork comes straight from LoC.

### OMDb (explicitly rejected)

Considered and passed. Reasons:
- Poster access gated behind patron donation.
- 1000 req/day free tier is too tight for catalog enrichment.
- Data is a thinner subset of what TMDb provides for free.
- Nothing OMDb offers is unique once we have TMDb + Wikidata.

---

## The enrichment pipeline

This is how a single Archive item gets from raw metadata to a
polished card.

```
1. Fetch archive.org/metadata/{id}
     │
     ├─ Extract: title, year, description, subject[], collection[],
     │           runtime, external-identifier[]
     └─ Pick video file: files[] → prefer h.264 MP4 ≤ 1080p
                                   fallback 512Kb MPEG4
                                   fallback original

2. Resolve identifier
     ├─ IF external-identifier contains urn:imdb:ttNNNN → IMDb ID found
     └─ ELSE → Wikidata SPARQL by P724 → IMDb ID or nothing

3. Enrich via TMDb (if IMDb ID found)
     ├─ /find/ttNNNN → tmdb_id
     ├─ /movie/{tmdb_id}?append_to_response=credits,images,external_ids
     └─ Cache everything keyed by tmdb_id (365-day TTL; metadata rarely changes)

4. Resolve artwork (cascading fallbacks)
     ├─ TRY TMDb poster_path (best English poster, highest vote count)
     ├─ TRY Wikidata P18 (Commons image)
     ├─ TRY Commons category search by title + year
     ├─ TRY Library of Congress search (for pre-1950 films)
     └─ FALLBACK archive.org/services/img/{id}

5. Normalize to our schema
     └─ ContentItem { id, title, year, runtime, synopsis,
                      posterURL, backdropURL, genres[], cast[],
                      crew[], videoURL, derivatives[],
                      sourceAttribution }
```

**Caching contract**
- TMDb responses: 30 days on disk, refresh weekly for current/trending.
- Wikidata: 90 days.
- Commons/LoC lookups: 180 days.
- Archive.org metadata: 7 days.
- All artwork: persistent URLCache (500 MB disk per CLAUDE.md).

**Batch enrichment job**
Runs on-device in the background when the app is idle, walking the
SwiftData store and enriching items that are still at "Archive-only"
tier. Respects TMDb's 40-per-10s via an actor-gated semaphore.

---

## Building the catalog — tag taxonomy

Archive.org's `subject` field is free-text. We normalize onto a fixed
controlled vocabulary so the Browse screen has predictable facets:

**Content type** (from Archive collection + TMDb media type)
- Film — Feature
- Film — Short
- Film — Silent
- Film — Animation
- TV — Series Episode
- TV — Variety / Special
- Newsreel / Documentary
- Ephemeral / Industrial / Educational
- Home Movie / Amateur

**Decade** (derived from `year`)
- 1890s, 1900s, 1910s, ... 2020s

**Genre** (from TMDb genre IDs when available, else keyword-mapped
from Archive `subject`)
- Drama, Comedy, Horror, Sci-Fi, Western, Musical, Crime, Romance,
  War, Animation, Documentary, Family, Thriller

**Origin** (from TMDb `production_countries` or Archive `creator`
heuristics)
- US, UK, France, Italy, Japan, Soviet Union, Germany, Other

**Runtime buckets** (for Browse filtering)
- Under 10 min, 10–30, 30–60, 60–90, 90–120, 120+

**Content rating** (from TMDb; conservative unknown-defaults)
- G / PG / PG-13 / R / NR

This taxonomy lives in a single Swift file (`Taxonomy.swift`) and feeds
the Browse screen's facet panel, the Search filter chips, and SwiftData
indexed fields for fast local filtering.

---

## Schema sketch

```swift
@Model final class ContentItem {
    @Attribute(.unique) var archiveID: String
    var title: String
    var year: Int?
    var runtime: Int?           // seconds
    var synopsis: String?

    // Identifiers
    var imdbID: String?
    var tmdbID: Int?
    var wikidataQID: String?

    // Artwork
    var posterURL: URL?
    var backdropURL: URL?
    var artworkSource: ArtworkSource  // .tmdb, .wikidata, .commons, .loc, .archive

    // Classification
    var contentType: ContentType
    var decade: Int?
    var genres: [String]        // from normalized taxonomy
    var countries: [String]
    var contentRating: String?

    // Playback
    var videoURL: URL
    var videoFormat: String     // "h.264 MP4", "MPEG4 512Kb", etc.
    var fileSize: Int64?

    // Relationships
    var cast: [CastMember]      // capped to top 15
    var director: String?

    // Enrichment state
    var enrichmentTier: EnrichmentTier  // .archiveOnly, .imdbLinked, .fullyEnriched
    var lastEnrichedAt: Date?

    // User state
    var isFavorite: Bool = false
    var playbackPositionSeconds: Double = 0
    var isAdultContent: Bool = false
}
```

---

## Open questions / decisions to log

1. **TMDb commercial terms.** Must resolve before App Store submission.
   Likely path: file as non-commercial free app with proper attribution.
2. **Offline enrichment cache format.** JSON blob per item vs. normalized
   SwiftData relationships? Lean toward SwiftData for query speed.
3. **Update cadence for curated shelves.** Bundle `featured.json` with the
   app vs. fetch from the GitHub Pages web app? Lean toward GitHub Pages
   fetch — the web app becomes the editorial dashboard.
4. **"Editor's Picks" curation tooling.** Does this warrant a companion
   Mac tool, or is editing a JSON file by hand enough for v1? Probably
   the latter.
