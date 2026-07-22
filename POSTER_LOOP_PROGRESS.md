# Autonomous Loop — Professional Posters + Metadata Accuracy

Started 2026-07-22. Owner directive (verbatim):

> "Now that we have mostly solved for the titles and playability issues, I would
> like to make a concerted effort to source professionally made posters for each
> title rather than a significant number of title art that is simply a still from
> a frame in the video. There are some videos for which no professionally made
> poster exists, but there are far too many examples of movies that should have
> them where they are not showing correctly or have not been sourced correctly.
> We have access to multiple different sources (The Movie Database, etc.) and we
> can also search on Wikipedia and other places that are more likely to have the
> correct artwork. Please use an autonomous loop in order to source as many of
> these posters as possible, while ensuring that we are not matching old movies
> to modern posters and other easy to make errors when we are trying for 100%
> professional poster coverage for all of our films. As you are performing this
> audit, please also ensure that the metadata is accurate for each film. The goal
> is for every single movie to have the correct information and the correct poster
> that will show up on every single platform. Please make use of the right Claude
> model for each part of this work and make use of sequential agents rather than
> concurrent ones."

## Goal
Maximize PROFESSIONAL poster coverage for FILMS (replace frame-still `generated`
covers, Decision 023), STRICT match verification (no old→modern-poster errors,
Decision 026), verify metadata (title/year/director/cast/synopsis), land on ALL 5
platforms via the shared catalog, and make it ONGOING via cron.

## Guardrails carried in
- **Never match an old film to a modern/wrong poster** (Decision 026: anchor on Archive
  imdb id → Archive date/year → colorMode; Decision 025 B&W-vs-color).
- Frame-still `generated` covers are the FALLBACK when no professional poster exists —
  keep them where no real poster is sourceable; replace them where one is.
- Additive/reversible catalog mutations (Decision 020); posterURL is shared across all
  platforms (build_sqlite → apps, index + detail shards → web).
- Best model per scope; **sequential** agents (never concurrent) to preserve work.

---

## Tick log

### Tick 1 — 2026-07-22 — Recon
- Prior playback loop just completed + apps submitted (Apple 1.3.302/824 to ASC, Android
  vc13 production draft, web live). Now pivoting to poster/metadata quality.
- Dispatched read-only recon agent to map: (A) artwork data model + how posterURL reaches
  all 5 platforms, (B) the poster-sourcing tool fleet + their match-verification, (C)
  match-correctness guardrails + gaps, (D) real counts (professional vs generated vs dead
  vs none; how many non-professional are MATCHABLE via imdb/tmdb/year), (E) prior efforts
  + dead ends. Findings below.

**Recon findings (30,418 FILMS, excl. tv/commercial/excluded):**
- Professional poster **16,146 (53.1%)** · `generated` frame-still **10,315 (33.9%)** · `posterDead`
  **2,448 (8.0%)** · archive-thumb/none **1,509 (5.0%)**.
- `artworkSource` professional set = tmdb/omdb/commons/wikidata/fanart/tvdb/aapb/loc/external;
  `generated` = frame-still (Decision 023, real still but NOT professional; web index `pro=0`).
- All 5 platforms render the SAME `posterURL` from catalog.json → build_sqlite (apps) + index +
  detail shards (web). Fix once, lands everywhere.
- **Non-professional matchable:** imdbID **4,051** (posterDead 2,448 + generated ~1,987) · tmdbID 1,738
  · title+year 10,699. **All 2,448 posterDead carry an imdb/tmdb id → 100% re-sourceable.**
- **Guardrails (keep old films safe):** Decision 026 `verify_external_match` (anchor imdb→date→color),
  `remediate_catalog.fix_wrong_external_matches` (source-year ≥5yr older / vintage≥1990 / B&W×year≥1970
  → clear), `tmdb_verify_matches` (year gap≥5 AND sim<0.4), Decision 044 `validate_posters` (404→demote).
  DEAD END (do NOT resurrect): blunt "clear any shared poster" rule (would strip ~2,500 good foreign-AKA/
  serial posters). NEVER delete a `generated` cover — only UPGRADE it.
- **Gap:** no tool re-sources a poster via TMDb `/find/{imdbID}` for already-arted (dead/generated) films;
  omdb_backfill re-fetches rotting OMDb/Amazon; tmdb_fill only fills EMPTY fields. TMDB token is in CI
  (omdb-backfill.yml/tmdb-enrich.yml) + local Secrets.xcconfig.
- Metadata gaps: missing year 4,061 · director 9,801 · synopsis 955.

### Tick 2 — 2026-07-22 — Build the TMDb-imdbID poster re-sourcer (highest-leverage safe win)
- Dispatching one build agent: `tools/resource_posters_tmdb.py` — target films that are
  posterDead OR generated/archive/none AND carry imdbID(or tmdbID), NOT already higher-tier
  professional; query TMDb `/find/{imdbID}` (or `/movie/{tmdbID}`) → durable image.tmdb.org poster
  → set posterURL+artworkSource=tmdb+hasRealArtwork+clear posterDead (+ backdrop if missing).
  SAFE: id-anchored (Decision 026) + corroborate TMDb result year within ±2 of the film/Archive year
  (catches a wrong stored imdbID); NEVER overwrite a professional poster; KEEP the generated frame as
  fallback if TMDb has none (don't delete). Resumable, popularity-first, --limit/--dry-run. Validate on
  a real sample + wire a cron workflow (no schedule until reviewed). Lifts coverage 53%→~66%.

- **DONE:** `tools/resource_posters_tmdb.py` built + validated + committed `9f949acf` (v1.3.303/825).
  Dry-run 300: 152 upgraded (151 posterDead, 1 generated), 131 no_tmdb_poster, 13 no_tmdb_id,
  3 year-mismatch + 1 bw→modern skip. Concrete before/after year-corroborated, image.tmdb.org live.
  Target set 4,167 id-anchored non-pro (2,448 posterDead + 1,177 generated + 542 archive/none).
  Est. ~2,100 films gain durable posters catalog-wide (~44% no_tmdb_poster → need other sources).
  `resource-posters.yml` (workflow_dispatch, no schedule yet).

### Tick 3 — 2026-07-22 — Bounded re-source run + plan next sources
- Dispatched `resource-posters.yml -f limit=1500` → run **29959789641** (popularity-first, ~750
  upgrades; run → validate_posters → publish → publish-db). REVIEW upgraded posters for correctness
  before scaling (posters are highly visible).
- **Next workstreams queued (sequential):** (1) review + scale + schedule the TMDb re-sourcer; (2)
  the ~44% no_tmdb_poster id-anchored films → Wikidata/Commons P18 (resolve QID via imdbID SPARQL,
  then P18) + TVDB/fanart; (3) metadata accuracy sweep (tmdb_fill_metadata/backfill_metadata id-keyed
  on target films: year/director/synopsis); (4) the ~6,591 title+year-only no-id tail via
  match_unmatched (year-corroborated) + verify_external_match/tmdb_verify_matches/color sweeps; (5)
  raise classify_color coverage so the B&W×modern guard fires on the fuzzy tail.

### Tick 4 — 2026-07-22 — Bounded run RESULT + drain more + audit the no-id matcher
- Run 29959789641 SUCCESS: **601 upgraded** (578 posterDead→TMDb, 23 generated→TMDb) of 1500; all
  3000 tmdb posters verified LIVE (0 dead); safety skips firing (year-mismatch + B&W→modern);
  published to all platforms. Pro film coverage ~53%→~55%.
- Dispatched another bounded TMDb drain run (limit=2500) → keep the id-anchored push going (safe).
- **Dispatching one audit agent (diagnostic-first for the RISKY path):** the ~10,699 no-id
  (title+year-only) films are the biggest lever AND where old→modern wrong-match risk lives.
  `match_unmatched.py` (title+year, ±2yr + 0.6 sim, Decision 026) resolves id + sources poster in one
  shot. Before scaling it, run it in DRY-RUN/report on a no-id film sample, assess match quality +
  wrong-era false-positive rate (esp. old/silent films), flag risky matches, recommend stronger guards.

### Tick 5 — 2026-07-22 — Audit verdict: HARDEN the no-id matcher before scaling
- Second drain run 29961559531 SUCCESS (all 3000 posters live, published).
- **Audit verdict: match_unmatched NOT safe to scale as-is (~30% of matches wrong/questionable).**
  GOOD: old→modern is reliably blocked by ±2yr gate; colorMode 99%. BAD failure modes (outside the
  year gate): (1) OMDb path has NO similarity floor → wrong imdbID → delayed poster corruption; (2)
  generic-title/same-era collisions (14% are 1-2 word titles); (3) `_NOT_A_FILM` checks only title not
  archiveID slug → "complete-series"(TV)/"MovieTrailer" slip through; tv-special eligible (1,291,
  Decision 036); (4) CRITICAL — sets `matchVerified=True` on every accept → verify_external_match
  SKIPS it → the authoritative Decision-026 Archive-declared-imdb check NEVER runs (a real bug on
  existing matches too). No-id eligible set = 8,489 films (pre-1950: 3,283; pre-1930: 887).
- **Dispatching hardening agent** (small localized diffs): #1 consult Archive metadata FIRST — adopt
  the Archive-declared imdb id directly (skip fuzzy) + corroborate on Archive date, and STOP
  self-certifying (leave matchVerified unset for fuzzy so verify re-checks); #2 add ≥0.6 (≥0.8
  short/generic) OMDb similarity floor; #3 not-a-film on archiveID slug + serial/complete-series/
  trailer + exclude tv-special; #4 pre-1950 sim≥0.85 / 1-2-word require exact title+year or Archive id;
  #5 abstain when ≥2 TMDb candidates share the title in-window. Re-validate old-biased dry-run → confirm
  wrong rate near-zero. Then safe to scale the ~8.5k no-id tail.

### Tick 6 — 2026-07-22 — Matcher HARDENED (0% wrong); cleanup existing wrong matches
- Matcher hardened + committed `3eef0e5f` (v1.3.304/826). Re-validation: 120 pre-1950 films →
  7 matched / 113 abstained / **0 wrong** (was ~30%). Archetypes rejected (Kolchak TV, trailer,
  Assassination 0.59). Fix 1 = Decision-026 alignment (adopt Archive-declared imdb FIRST; fuzzy no
  longer self-certifies). Eligible no-id set tightened to 7,128 (colorMode-required + tv-special-excluded).
- 3rd TMDb drain run 29962531408: 89 upgraded (72 dead, 17 gen) — **TMDb id-anchored path SATURATING**
  (~1,866 total upgraded, ~59% pro coverage). Diminishing returns → shift to cleanup + matcher + other sources.
- **2,254 previously-self-certified fuzzy matches** are now re-checkable → dispatched the cleanup
  `verify-matches.yml refresh=true limit=8000` (Decision 026: re-check matched items vs Archive
  external-identifier/date/color, clear/re-resolve wrong ones = fixes existing wrong posters+identities+
  metadata). Review cleared count next tick, then scale the hardened matcher on the no-id tail.
