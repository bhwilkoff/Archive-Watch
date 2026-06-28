# Metadata Expansion — binding plan

Status: ACTIVE (owner-approved 2026-06-27). Goal: pull the rich metadata our APIs already expose
INTO our database so users can **search, filter, and learn more** about films without a runtime API
call — without bloating the app download or slowing queries.

Quote this doc before adding a metadata field, a storage layer, or a search/filter surface. It is
the companion to `docs/CATALOG-CONTRACT.md` (the shared schema) and Decision 046.

---

## The load-bearing rule: tier every field by how it's used

Our shipped `catalog.sqlite` (~146 MB → ~24 MB `.zz` download, queried on-disk per Decision 017)
already splits data three ways. EVERY new field goes to the cheapest layer that supports its use —
this is what keeps size + query speed in budget.

| Layer | Use | Why it's cheap | New fields routed here |
|---|---|---|---|
| **`item_json` blob** (one column, decoded ONLY on Detail open) | "find out more" detail | zero query cost; JSON compresses well in the `.zz` | tagline, awards, full crew (writer/composer/cinematographer), studios, franchise, cast person IDs, full release date, Wikidata extras |
| **`items_fts` (FTS5)** | free-text SEARCH | inverted index — search stays O(matches) no matter how big | keywords, AKA + original titles, writer name |
| **small normalized join tables** (like the existing genre/collection tables: `(archiveID, value)` + index) | values users FILTER by | indexed; touched only when that filter runs | keyword facets, studio |

**NON-NEGOTIABLE:** no new hot-path or sort columns on `items` → browse/sort queries are unchanged.
Detail decode is one slightly larger row (negligible). Search adds terms to the index built for it.
If a field is "nice on Detail" only, it goes in the blob — never a column, never the FTS.

---

## Size & speed budget (the owner's gate)

- **Download budget: keep `catalog.sqlite.zz` ≤ ~35 MB** (today ~24 MB). Only ~49% of films carry a
  TMDb/IMDb match, so only they gain data; estimate is +4–8 MB, but **Phase 0 MEASURES it on a real
  build before we commit.** If one field blows the budget → demote to web-only or drop it.
- **Query budget:** the common queries (browse grid, sort, Home shelves, search, Detail) must show
  **no measurable regression**. Phase 0 runs `EXPLAIN QUERY PLAN` + timings before/after.
- Heavy text (keywords/AKA/crew) is only present for matched films; unmatched films cost nothing.

---

## Fields → source → layer → what it unlocks

Almost all of Tier 1+2 comes from ONE TMDb `/movie/{id}?append_to_response=keywords,alternative_titles,credits`
call — the same call enrichment already makes, so the backfill is cheap.

### Tier 1 — search/discovery
| Field | Source | Layer | Unlocks |
|---|---|---|---|
| `keywords[]` | TMDb `keywords` | FTS + keyword join table | thematic search + facets + shelves ("Heist", "Christmas", "based on a novel") |
| `originalTitle`, `akaTitles[]` | TMDb `original_title` + `alternative_titles` | FTS | find foreign/re-titled classics by their other names |
| `writer`, `composer`, `cinematographer` | TMDb `credits` (have the call) / OMDb `Writer` | blob (+ writer in FTS) | "by writer / scored by"; richer Detail |
| cast `tmdbPersonID` | TMDb `credits` (`id`) | blob (in each cast entry) | reliable "more by this actor"; unblocks Callsheet PERSON deep-links (Decision 038) |

### Tier 2 — filter/grouping
| Field | Source | Layer | Unlocks |
|---|---|---|---|
| `studios[]` | TMDb `production_companies` | blob + studio join table | filter by studio (RKO/Republic/Hammer/MGM) |
| `franchise` (name + tmdb collection id) | TMDb `belongs_to_collection` | blob | "part of the Universal Monsters / Sherlock Holmes series" |
| `awards` | OMDb `Awards` | blob | "Won 2 Oscars" badge + award-winners shelf/filter |

### Tier 3 — detail flavor
| Field | Source | Layer | Unlocks |
|---|---|---|---|
| `tagline` | TMDb `tagline` | blob | Detail flavor |
| `releaseDate` (full) | TMDb `release_date` | blob | "on this day"; precise sort |
| Wikidata extras (`basedOn`, narrative/filming location, movement e.g. "German Expressionism") | Wikidata (`wikidataQID`) | blob | cinephile discovery (sparse — last) |

---

## Phases (execute over several passes)

- **Phase 0 — MEASURE (gate).** Backfill a ~2k-film sample, build the DB with all fields routed per
  the table, compare `.zz` size + query timings vs today. Confirm against the budget. Owner sees the
  numbers before we proceed.
- **Phase 1 — Backfill the data.** `backfill_metadata.py` — one TMDb detail pass for all Tier 1+2
  fields (+ OMDb awards/writer; Wikidata extras last). Resumable (`metaSource` marker), same shape as
  `backfill_language.py`; daily workflow `metadata-enrich.yml`, `catalog-writers` concurrency,
  publishes + rebuilds the DB. (Folds in alongside the existing `backfill_language.py`.)
- **Phase 2 — Schema + `build_sqlite`.** Route each field to its layer; add `keyword`/`studio` join
  tables + indexes; extend `items_fts` `extra` with keywords/AKA/writer. Update `CATALOG-CONTRACT.md`
  + `build_catalog_index.py` (web).
- **Phase 3 — Consume per platform.** Apple (`CatalogDB`, tvOS/iOS/macOS): keyword + studio filters,
  keyword/AKA search, Detail surfaces (writer/studio/franchise/awards/tagline), cast person links.
  Android (Room) + Web (index) parity. Update each platform's DESIGN doc.
- **Phase 4 — Validate & ship.** Re-measure size/speed vs budget; bump version; log results in the
  Decision; PARITY.md updated.

## Title resolution (the unified, researched approach)

The display title is resolved in ONE ordered policy in `remediate.sanitize_title` (not ad-hoc rules):

1. **Matched film → adopt the authoritative `canonicalTitle`** (TMDb `title`, else OMDb `Title`,
   backfilled by `backfill_metadata.py`). Guard: adopt only when every significant word of the
   canonical appears in the uploader title (a wrong match can't inject a wrong title). This is the
   exact title for the ~55% of films with a match — e.g. "The Web Ella Raines, Edmond O'Brien, …"
   → "The Web". This is the PRIMARY fix; improving match coverage improves titles.
2. **Unmatched film → researched cleaning chain.** The single highest-value cleaner is
   `_truncate_at_year_field`: the item's OWN year is the title/cruft BOUNDARY — "Real Title YYYY
   <cruft>" → "Real Title" (handles ratings/CC/genre/cast appended after the year, the dominant
   uploader pattern; 2,400+ films). Guarded: only the item's own year, real text must precede it, a
   date-range or a phrase ending in a preposition/article ("… China in 1917 in color") is NOT
   truncated. Plus targeted strips: star ratings (★), CC markers ((CC)/[CC]/CC:), genre/quality/
   format tails, AKA/cast parentheticals, pipe-credits, director/credit clauses, the bare year forms.

Every strip runs behind `_keep_if_lettered` (never empties a title) and was dry-run-scanned on the
full catalog for false positives. Measured: ~6,500 titles cleaned by the chain + canonical adoption
on matched films.

## How to apply (for the next developer)
- New metadata field → put it in the lowest layer that serves its use (blob unless it's searched or
  filtered). Never add an `items` column for a detail-only field.
- One TMDb detail call feeds many fields — never add a per-field API pass when `append_to_response`
  can batch it.
- Re-measure the `.zz` size after any field addition; the ≤35 MB download budget is binding.
- Keep it additive (Decision 020): new JSON keys older clients ignore; new tables/FTS terms are
  backward-safe.
