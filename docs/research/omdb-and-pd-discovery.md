# OMDb fields + Public-Domain content discovery — research

*Researched 2026-06-01. Probed the live OMDb API with our key and ran a
multi-source web research pass. The goal: (a) what OMDb fields can bolster
our schema, and (b) how to find NEW public-domain movies/TV/video to add.*

---

## TL;DR

1. **OMDb cannot discover content or filter by public-domain status.** It
   is a *lookup* over IMDb data — by IMDb ID (`i=`) or title (`t=`/`s=`).
   No rights field, no enumeration. Keep it as the IMDb-keyed *enrichment*
   leg only. (Confirmed against the API docs + live probes.)
2. **OMDb DOES carry richer fields than we currently capture** — ratings,
   content rating, full plot, writer, awards, box office, and
   **episode-level TV data**. Several are worth adding to our schema.
3. **Discovery of new PD content is a JOIN problem**, not an OMDb problem.
   No single source does discover + confirm-rights + playable-file +
   IMDb-join. The pipeline must stitch: **Wikidata SPARQL / curated PD
   lists** (discover) → **copyright-renewal datasets** (confirm rights) →
   **Internet Archive / LoC / NARA** (playable file) → **TMDb + OMDb**
   (enrich, our existing path).

---

## Part 1 — OMDb fields we are NOT yet capturing

`tools/omdb_backfill.py` currently reads **only `Poster`**. A full OMDb
record (live example: `?i=tt0063350` = Night of the Living Dead) returns:

| OMDb field | Example | Our schema? | Worth adding? |
|---|---|---|---|
| `Poster` | m.media-amazon.com/… | ✅ used | — |
| `imdbRating` | `"7.8"` | ❌ | **Yes** — a real popularity/quality signal; we only have a derived `popularityScore`/`qualityScore` |
| `imdbVotes` | `"148,892"` | ❌ | **Yes** — vote count is a strong "is this a notable title" signal for shelf ranking |
| `Rated` | `"R"` / `"TV-PG"` | ❌ | **Yes** — content rating; complements the Decision-012 adult filter with a real MPAA/TV signal |
| `Ratings[]` | RT 95%, Metacritic 89 | ❌ | Maybe — RT/Metacritic for a "critically acclaimed" shelf |
| `Plot` (`&plot=full`) | full paragraph | partial | **Yes for thin items** — many Archive synopses are weak; OMDb full plot is a good fallback |
| `Writer` | "John A. Russo…" | ❌ | Maybe — enables a writer-credit line / "more by this writer" |
| `Awards` | "7 wins total" | ❌ | Low priority |
| `BoxOffice` | "$236,452" | ❌ | Low priority (often N/A for PD-era films) |
| `Country` | "United States" | ✅ have `countries` | OMDb fills gaps |
| `Released` | "04 Oct 1968" | partial (we have `year`) | Maybe — exact release date |
| `Rated` `Production`/`Website`/`DVD` | mostly N/A | ❌ | Skip — usually empty for our era |

**Episode-level TV (big opportunity).** OMDb supports:
- `?t={series}&Season=N` → returns an `Episodes[]` array (title, released,
  episode #, imdbRating, **per-episode imdbID**).
- `?t={series}&Season=N&Episode=M` → full per-episode record (plot,
  director, writer, runtime, rating, poster, `seriesID`).

Our `series/*.json` episode objects (`archiveID, seasonNumber,
episodeNumber, title, overview, stillURL, airDate, runtimeSeconds,
videoFile, downloadURL`) currently have **no IMDb rating, no per-episode
imdbID, and often thin overviews**. OMDb's season/episode endpoints can
fill all three — keyed off the series' `imdbID` we already store.

### Recommended schema additions (additive, all optional — old catalogs still decode)

```
imdbRating: Double?       // e.g. 7.8
imdbVotes: Int?           // e.g. 148892  (parse OMDb's comma string)
contentRating: String?    // OMDb "Rated": R, TV-PG, NOT RATED, …
omdbPlot: String?         // full-plot fallback when synopsis is thin
```
Plus per-episode in `series/*.json`: `imdbID`, `imdbRating`.

These ride the **same daily OMDb backfill** — one extra parse of the
response we already fetch, near-zero added quota cost (we're already
spending the request on the poster).

---

## Part 2 — Discovering NEW public-domain content

### Why OMDb is out for discovery
- `s=` is a title-substring search, 10 results/page, **page 1–100 max →
  ~1,000 results/query ceiling**, no rights filter. It cannot enumerate
  IMDb or filter by PD. Free tier 1,000 req/day.

### The discovery sources that actually work (ranked)

**1. Wikidata SPARQL — best automated discovery + join (carries IMDb + IA IDs).**
Endpoint `https://query.wikidata.org/sparql` (JSON, real API). Key props:
`P31=Q11424` (film), `P6216=Q19652` (copyright status = public domain),
`P345` (IMDb ID), `P724` (Internet Archive ID), `P577` (publication date).

Lead with **P724 presence** (already-playable + often IMDb-keyed), since
P6216 is sparsely populated for films:
```sparql
SELECT ?film ?filmLabel ?imdb ?iaid WHERE {
  ?film wdt:P31 wd:Q11424 ; wdt:P724 ?iaid .
  OPTIONAL { ?film wdt:P345 ?imdb. }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
```
This is the single highest-value lead: structured, joinable, and every row
is already tied to an Internet Archive item we can play.

**2. Public Domain Day annual lists — best FRESH discovery, yearly.**
Duke CSPD (`web.law.duke.edu/cspd/publicdomainday/2026/`) + the matching
Internet Archive PDD collection (`blog.archive.org/public-domain-day-2026/`,
items already playable on IA). 2025 = 1929 works; 2026 = 1930 works
(All Quiet on the Western Front, Anna Christie, The Big Trail, Betty Boop).
HTML, no IMDb IDs — small, high-signal, scrape annually. Wikipedia
"2026 in public domain" is more list-structured.

**3. Curated PD lists (title/year seeds; re-verify + resolve IMDb).**
- Wikipedia "List of films in the public domain in the United States"
  (~100+ vetted films; HTML table; no IMDb links; conservative/reliable).
- Wikipedia Category:Public domain films (broader, less vetted).
- `publicdomainmovie.net` (~940 titles, HTML-only, stale, unsystematic
  IDs — **flag: scrape as candidates, re-verify everything**).

**4. Internet Archive sub-collections we may under-mine** (we already have
the scrape + metadata API plumbing — near-free to add):
- **Prelinger** (`collection:prelinger`): ~60k ephemeral films, ~2k cleared
  for unrestricted reuse. Mostly no IMDb IDs → enrich via Archive/Wikidata.
- `collection:classic_tv` and sibling TV collections for PD television.

**5. Library of Congress National Screening Room — real JSON API, MP4.**
`loc.gov/collections/national-screening-room/?fo=json`. Library-attested
PD, downloadable MP4 + ProRes. No IMDb IDs → join by title/year. Hundreds–
low-thousands of titles. Be polite (it throttles crawls).

**6. NARA (US National Archives) — REST API, all federal works PD.**
`catalog.archives.gov/api/v2/` (JSON; 10k queries/month/key). Historical /
government film. No IMDb IDs.

**7. NASA** `images-api.nasa.gov` (JSON) — footage, not titled films;
already partly mirrored on IA. Lower priority for a "films & TV" app.

Skip / v2: **Wikimedia Commons video** is OGV/WebM — **AVPlayer can't play
VP8/VP9/Theora natively**, so it needs transcoding; keep Commons as an
*artwork* source (as we do), not playable video. **PBS** = licensed, not
PD. **Europeana/EUscreen** = structured + `REUSABILITY=open` filter, but
rights are EU-framed, rarely US-PD, almost never IMDb-keyed → stretch.

### Public-domain TV (1950s–60s non-renewal)
No official/comprehensive list exists — PD is often per-EPISODE, by
operation of law. Best catalogs:
- **RerunCentury** (`reruncentury.com/ia/`) — community catalog of PD TV
  mapped to **Internet Archive items** (playable). Most pipeline-friendly;
  crowd-attested → re-verify.
- **Television Obscurities** (`tvobscurities.com`) — reliable editorial on
  TV copyright status (HTML, no API).
- IA `collection:classic_tv` direct.
Enrich episodes via OMDb `type=series`/`type=episode`. IMDb-join is
episode-level messy.

### Rights confirmation (the load-bearing, legally serious step)
- **Pre-1929 publication (→ pre-1930 in 2026)**: auto-PD, cleanest floor.
- **1929–1963**: PD **only if copyright not renewed** (28-yr renewal was
  mandatory). Query renewal datasets:
  - **NYPL `cce-renewals`** (GitHub, tab-delimited bulk data) — most
    pipeline-friendly; ingest + query offline. Also `NYPL/bardo-copyright-db`.
  - **Stanford Copyright Renewal Database** (renewals 1950–93 for works
    1923–63; bulk downloadable) — gold-standard method, **book-focused**;
    for FILM ensure you use the **Motion Pictures** CCE class.
- **1964+**: assume copyrighted unless an explicit free license.
- **Caveat from the sources:** "no renewal found" is **strong evidence,
  not proof** — title variants + studio-name registration + film-specific
  renewal quirks mean close calls need a human spot-check. Films were often
  renewed under the studio, not the title.

---

## Recommended pipeline shape (discover → confirm → play → enrich)

1. **Discover** from three feeds: (a) Wikidata SPARQL `P31=Q11424 + P724`
   (playable + often IMDb-keyed); (b) annual Duke/IA Public Domain Day
   lists; (c) curated seeds (Wikipedia PD-films table; RerunCentury for TV).
2. **Confirm rights**: pre-cutoff year → PASS; else check title/year vs
   NYPL `cce-renewals` / Stanford → "no renewal" = PASS (flag close calls).
3. **Find playable file**: prefer the Wikidata-supplied IA ID; else IA
   scrape by title/year; else LoC (`?fo=json`, MP4) or NARA.
4. **Enrich**: TMDb (via IMDb P345) + OMDb (`i=`/`t=`) — our current path,
   now also pulling the Part-1 fields. OMDb stays enrichment-only.

The first three discovery feeds are independent and can be added
incrementally; the Wikidata `P724` query alone would likely surface
hundreds of playable PD films we don't yet have, at near-zero cost.

---

## Status — what's now BUILT (2026-06-01)

The first two legs of the pipeline are implemented and verified
end-to-end on the simulator + against live APIs:

- **Rich OMDb enrichment** — `tools/omdb_lib.py` (shared fetch/apply) +
  rewritten `tools/omdb_backfill.py`. Now captures **imdbRating,
  imdbVotes, contentRating, full-plot fallback, runtime** for EVERY
  IMDb-keyed item (cache schema v2; v1 poster-only entries get a one-time
  rich re-fetch). Guard rails: never overwrites designed art or a good
  synopsis. Swift `Catalog.Item` gained `imdbRating/imdbVotes/
  contentRating/synopsisSource` (+ `imdbRatingDisplay`/`imdbVotesDisplay`
  helpers); DetailView shows an IMDb gold-star rating chip + content-rating
  badge.
- **Discovery** — `tools/discover_wikidata_pd.py`: SPARQL feeds A (films
  with Internet Archive ID P724) + B (films flagged PD, P6216=Q19652),
  diffed against our catalogs. First run found **7,582 new candidates**
  (6,831 high rights-confidence). Adds a `rightsConfidence` (high =
  PD-flagged or pre-1930; low = incidental recent upload) so low-confidence
  uploads sort to the back and are skipped by default.
- **Ingest** — `tools/ingest_candidates.py`: drains the candidate queue
  daily-capped, **validates each against live Archive metadata** (stale
  Wikidata IA IDs → skipped, never retried), picks a playable derivative,
  classifies, enriches via OMDb, appends to both catalogs. Verified: 6/8
  test candidates produced fully-formed playable items; 2 correctly
  rejected as no-video.
- **Workflow** — `.github/workflows/discover-content.yml` runs both stages
  daily (03:42 UTC, after the OMDb backfill) and commits additively.

### Sourcing — now multi-source (2026-06-01 update)

Discovery is no longer Wikidata-only. The daily `discover-content` workflow
now runs these feeds, all verified live:

- **Wikidata** (`discover_wikidata_pd.py`) — PD-flagged + Archive-id films.
- **Internet Archive collections** (`discover_archive_collections.py`) —
  mines `feature_films` (28k), `silent_films` (3.5k), `classic_tv` (11k),
  `prelinger` (10k), animation, film_noir, etc. Every hit is already a
  playable Archive item. ~32% of `feature_films` were new to us.
- **Title+year → Archive resolver** (`archive_lib.resolve_title`, used by
  `ingest_candidates.py --resolve-limit`) — the previously-documented
  highest-leverage unlock. Matches the ~6,800 PD-flagged Wikidata films
  that lack a P724 id to a playable Archive item by title+year, scored
  with a confidence floor + clip/YouTube penalties. Verified 9–10/10 on
  famous PD films (Metropolis, Nosferatu, Caligari, Detour, Plan 9…).
- **Library of Congress National Screening Room** (`discover_loc.py`) —
  ~1,294 US-gov PD films served as downloadable MP4 from loc.gov, generally
  NOT on the Internet Archive. Self-contained items (one call → MP4 +
  duration + poster). archiveID namespaced `loc:{id}`. Verified the MP4 is
  directly playable (HTTP 200, video/mp4).

TV episode sourcing now uses a **canonical wants queue**
(`build_episode_wants.py` → `episode_wants.json`): each series is resolved
to its OMDb canonical episode list, the gap is queued, and
`backfill_tv_episodes.py` searches Archive **per wanted episode** (by
SxxExx and by episode title) in addition to the broad series search —
reaching differently-named uploads the broad search misses, and marking
wants fulfilled.

Shared Archive logic (metadata, derivative picker, search, resolver) lives
in `tools/archive_lib.py`; OMDb logic in `tools/omdb_lib.py`.

### Still open / future

- **NYPL `cce-renewals` rights evidence** — stamp `rightsStatus` with
  copyright-renewal evidence for 1929–1963 titles (deprioritised: current
  feeds are already rights-conservative — PD-flagged, pre-1930, or curated
  PD collections). Finds no new content, only firms up provenance.
- **RerunCentury (TV)** + **annual Public Domain Day** lists as extra feeds.
- A **TMDb bearer-token secret** would let `build_episode_wants` resolve
  canonical lists for shows OMDb lacks, and pull episode stills/overviews.

*Source list lives in this session's research notes; key URLs inline above.*
