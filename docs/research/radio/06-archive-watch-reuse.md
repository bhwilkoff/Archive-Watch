# 06 — What a radio app can reuse from Archive Watch

*Date: 2026-10-17*

This maps the Archive Watch repo (`/home/user/Archive-Watch`) for a sister app:
public-domain old-time radio (OTR) and radio drama. It would be audio-first and
episodic, use the same Internet Archive source, and ship on the same set of
platforms. Nothing has been built. A future session will build it from a
"Universal App Template". This doc covers what to copy, what to change, what to
throw away, and which hard lessons carry over.

**Method.** I read `CLAUDE.md`, `docs/ENGINEERING-PROCESS.md`,
`docs/CATALOG-CONTRACT.md`, `DECISIONS.md` (the index and entries 146-165 in
full), entries 016-144 in `docs/decisions/*.md`, PARITY §9, the docstrings and
function lists of the pipeline tools, `publish-db.yml`, `deploy-pages.yml`,
`workflow-health.yml` and `discover-content.yml`, one `series/*.json` file, and
the client data layers. Anything about OTR on archive.org that I did not measure
is marked **(unverified)**. Discipline 5 applies: measure those points before
building on them.

---

## 1. The data plane as it exists

```
                         SOURCES (network, CI only)
  archive.org advancedsearch / scrape / metadata / be-api views
  Wikidata SPARQL · TMDb · OMDb · TVmaze · TVDB · Wikimedia · loc.gov
                                   │
          ┌────────────────────────┴───────────────────────────────┐
          │  DISCOVERY  (discover-content.yml, 03:42 UTC daily)     │
          │  tools/discover_wikidata_pd.py      ─┐                  │
          │  tools/discover_pd_wants.py          │→ shared/editorial/discovery_candidates.json
          │  tools/discover_archive_collections.py (scrape API, cursor)
          │  tools/discover_commercials.py      ─┘                  │
          │  tools/discover_tv_shows.py  → shared/editorial/tv_discovery.json
          │  tools/ingest_candidates.py  (drains queue; archive_lib.pick_video,
          │                               content_type.classify, resolve_title)
          │  tools/discover_loc.py       (self-contained loc: items)
          │  tools/build_episode_wants.py → episode_wants.json
          │  tools/backfill_tv_episodes.py → series/*.json (grows spines)
          └────────────────────────┬───────────────────────────────┘
                                   │  every writer:  catalog_release.py fetch
                                   │                 …mutate ./catalog.json…
                                   │                 catalog_release.py publish
                                   ▼
   GitHub Release "catalog-source":  catalog.json.gz  (~20 MB gz, ~95-143 MB raw)
   (pipeline-internal, never read by clients, never in git; Decision 018)
                                   ▲
          ┌────────────────────────┴───────────────────────────────┐
          │  ENRICHERS / AUDITORS  (~38 cron workflows, concurrency │
          │  group `catalog-writers`; compute-then-delta split via  │
          │  tools/catalog_delta.py, Decision 066)                  │
          │  tmdb-enrich, omdb-backfill, metadata-enrich, wikidata- │
          │  posters, resource-posters(-secondary), validate-posters│
          │  community-signals (harvest_community_signals.py),      │
          │  member-lists (harvest_member_lists.py), rights-audit   │
          │  (audit_rights.py --confirm, corroborate_*.py),         │
          │  check-liveness, verify-matches, tv-canonical           │
          │  (build_canonical_tv.py, audit_tv_rights.py), subtitles…│
          └────────────────────────┬───────────────────────────────┘
                                   │
          ┌────────────────────────┴───────────────────────────────┐
          │  PUBLISH  (publish-db.yml, 04:30 UTC + series/** push)  │
          │  run_pipeline_tests.sh  (a red test means no publish)   │
          │  catalog_release fetch → remediate_catalog.py →         │
          │  audit_title_identity → link_orphan_episodes →          │
          │  dedupe_orphan_episodes → bake_fallbacks →              │
          │  audit_rights --apply → catalog_release publish         │
          │  --if-unchanged (exit 3 = release moved: re-fetch,      │
          │  re-apply, publish) → build_sqlite.py → upload          │
          └───────┬───────────────────────────────┬────────────────┘
                  │                               │
                  ▼                               ▼
  Release "catalog-db" (rolling clobber)    Generated web artifacts, COMMITTED [skip ci]:
   catalog.sqlite.zz  (raw DEFLATE, ~33 MB)  catalog-index.json (build_catalog_index.py)
   catalog.sqlite     (~124 MB, legacy)      details/*.json (256 shards, build_web_details.py)
   catalog-manifest.json                     episodes-index.json, people.json, aliases.json,
   seed.sqlite → committed into the app      channel-pools.json, channel-schedule.json
     bundle (ArchiveWatch/ArchiveWatch/        (build_channel_schedule.py), topshelf.json,
     seed.sqlite)                              tonight.json, ops/image-dims.json
                  │                               │  then gh_dispatch.sh deploy-pages.yml
                  │                               ▼
                  │                deploy-pages.yml → GitHub Pages (archivewatch.org)
                  │                 repo tree minus tools/docs/android/app source
                  │                 + /subs (subtitle-assets release tarball)
                  │                 + generated /item/<id> share pages, /feeds/,
                  │                 /roku-search/, /mcp/, /vetting/ (built in-artifact,
                  │                 never committed; floor guards refuse a shrunken build)
                  │                 + editorial JSON: featured.json, series/*.json,
                  │                 shared/editorial/collection_metadata.json
                  ▼                               ▼
  CLIENTS (consumers only. Decision 028: no client re-derives rights, adult, matches or spines)
   Apple  ArchiveWatch/ArchiveWatch/Store/CatalogDB.swift (query verbs) +
          Services/CatalogRefreshService.swift (ETag GET .zz → inflate to staging →
          10 MB floor → atomic swap → probe meta.itemCount) + Models/Catalog.swift
          (Catalog.Item Codable; unknown keys ignored) + Services/SeriesStore.swift
          (series/{slug}.json lazily from Pages) + Networking/ResilientStreamLoader.swift
   Android android/app/src/main/java/app/archivewatch/android/data/CatalogDatabase.kt
          (Kotlin port of the verbs; BundledSQLiteDriver) + CatalogRepository.kt
          (ZZ_URL, MIN_VALID_BYTES = 10_000_000, Inflater(nowrap), seed copy, stale TTL)
          + EditorialRepository.kt + Models.kt
   Web    watch.js `Data` (catalog-index.json + details/ shards + episodes-index.json
          + series/*.json from Pages; it does NOT range-query the SQLite) ;
          js/api.js is the CURATOR dashboard's archive.org client (metadata + scrape)
   Roku   roku/ BrightScript reads the same Pages JSON
   All    play `downloadURL` straight from archive.org/download/{id}/{file} (302 to a node)
```

The rules that hold this together come from the contract
(`docs/CATALOG-CONTRACT.md`):
- `item_json` holds the whole canonical record. `items` holds lean scalar
  columns for WHERE and ORDER BY.
- Every field added later is optional, and clients ignore keys they don't know.
- `excluded` items never reach the DB.
- Dedupe happens at build time.
- Anything computed (`hiddenGem`, `item_related`, `item_shelves` rotation,
  `director_rank`) is computed in the pipeline and never restated in a client
  (Decision 050).

---

## 2. Tool, workflow and decision verdicts for an audio app

Verdicts: **REUSE AS-IS**, **ADAPT**, **REPLACE**, **N/A**.

### 2.1 Core library and catalog plumbing

| Item | Verdict | Why, and what changes for audio |
|---|---|---|
| `tools/archive_lib.py` `archive_meta`, `adv_search`, `download_url`, `runtime_from_file`, `is_adult` | REUSE AS-IS (change `UA`) | Generic archive.org calls. Change the `UA` string to name the new app and its contact. archive.org treats clients that send no UA differently (see §4). |
| `archive_lib.pick_video` | REPLACE with `pick_audio` | Keep its structure: drop `private` files (Decision 104), drop `history/` and `.~N~` revisions, use `title_files` to choose within multi-work items, then rank by tier with the largest file winning inside a tier. New tiers: `VBR MP3` derivative → `128Kbps MP3` → `64Kbps MP3` → `MP3` original → `Ogg Vorbis` → `Flac`/`Apple Lossless` (too heavy to stream as default) → anything audio. Formats to match: `VBR MP3`, `128Kbps MP3`, `64Kbps MP3`, `Ogg Vorbis`, `Flac`, `WAVE`, `Apple Lossless Audio` (**unverified** for OTR items; list the real `format` strings with a census first). "Largest wins" is wrong for audio. A 30-minute episode as WAV or FLAC is 100+ MB, so prefer the MP3 derivative and keep FLAC as a "high quality" alternate. |
| `archive_lib.title_files`, `_stem_key` | ADAPT, and it becomes central | In film the multi-work item is the exception (studio shorts in one item). In OTR it is the norm **(unverified, but OTRR sets and `oldtimeradio` uploads are typically one item per series or per batch holding dozens to hundreds of MP3s)**. So **the episode key is `(archiveID, fileName)`, not `archiveID`.** That is the single biggest schema difference. `_stem_key` must group a file's derivatives together (`.mp3`, `_64kb.mp3`, `.ogg`, `_spectrogram.png`). |
| `archive_lib.resolve_title` | ADAPT | Swap `mediatype:movies` for `mediatype:audio`. Rewrite the `_NOISE` and `_BENIGN_WORD` vocabularies: drop film words, add `otrr`, `certified`, `kbps`, `mono`, `afrs`, `transcription`, `aircheck`, `audition`. Keep the two-way stray-word logic and the `>= 90` confidence floor; they came from 1,200 wrong matches. |
| `tools/content_type.py` `classify` | REPLACE (keep the import-free one-classifier rule) | New vocabulary for format and genre. For example: `drama-anthology`, `mystery-detective`, `western`, `sci-fi`, `horror-suspense`, `comedy-sitcom`, `variety-music`, `juvenile-serial`, `soap`, `news-actuality`, `afrs`, `audition`, `commercial-spot`. The rule from its docstring (one dependency-free classifier, so ingest and remediate cannot drift apart) is the part to keep. |
| `tools/catalog_release.py` (`fetch`, `publish`, `--if-unchanged` exit 3, `_merge_onto_newer`) | REUSE AS-IS | Format-agnostic. Change the repo slug and release tags (`catalog-source`). |
| `tools/merge_catalogs.py` | REUSE AS-IS | Decision 020. It exists because a from-scratch rebuild once shrank the catalog from 30k to 1.1k. |
| `tools/catalog_delta.py` (`snapshot`/`extract`/`apply`) | REUSE AS-IS | Decision 066. Field-level deltas that let writers compute without holding the lock. Copy this pattern from day one. Don't wait until the lock is oversubscribed. |
| `tools/sqlite_publish_guard.py` | REUSE AS-IS | Decision 089. Use it for any appended index: the catalog DB, and later a transcript or word index. |
| `tools/gh_retry.sh`, `tools/gh_dispatch.sh` | REUSE AS-IS | `gh_retry.sh` refuses to retry a deterministic 422 (the 2 GiB asset limit). |
| `tools/run_pipeline_tests.sh` | ADAPT | Keep the "a red test blocks publish" gate. Replace the test list. |
| `tools/remediate_catalog.py` (4,350 lines) | ADAPT selectively; do not copy whole | Worth porting: `sanitize_title` and its `_strip_*` family (uploader cruft and bitrate tails apply to audio titles too), `sanitize_synopsis`/`_strip_rights_assertions`, `is_junk`, `exclude_takedowns`, `exclude_not_films` (→ `exclude_not_radio`), `flag_propaganda`'s *mechanism* (`noRecommend` + evidence file), `encode_download_urls`, `report_unknown_editorial_ids`, and `_load_*_corrections` (a human override file per field). Not worth porting: everything keyed to TMDb/OMDb matches, frame colour, trailers, posters, and URAA (a foreign-recording question needs its own research). Year logic: OTR dates live in filenames, so a `source_year` / `title_year` analogue must parse the OTR `YY-MM-DD` airdate convention **(unverified convention; census first)**. |
| `tools/build_sqlite.py` | ADAPT heavily | Keep: the `items` + `item_json` + FTS5 + join-table design, `meta`, the raw-DEFLATE `.zz` (`zlib.compressobj(9, DEFLATED, -15)`), the manifest, `select_seed_items`, `_rotated_shelf_positions`, `item_aliases` and `_chase_aliases` (Decision 085), `populate_related`, and `_pop_score`'s shape. Change: `dedupe_by_imdb` → dedupe by **broadcast identity** (series + airdate + episode title or log number). `merge_film_duplicates`'s union-find over `_same_film` maps directly onto "the same broadcast uploaded by five different collections", with runtime tolerance and a `_video_quality` → `_audio_quality` survivor ranking (bitrate, sample rate, OTRR-certified, file completeness). Remove `hiddenGem`'s IMDb terms; use a community-signal percentile instead. `episodes` becomes the main table, not an appendix (§2.3). |
| `tools/build_related.py` `compute_related` | ADAPT | The IDF-weighted shared-attribute ranking with a named reason carries over. New attributes: cast/voice actor, announcer, sponsor, network, writer/producer, series, archive.org subject. Keep the `KEYWORD_DF_CAP` and `MIN_SCORE` "faint signals never admit" rules. |
| `tools/coverage_report.py` | REUSE AS-IS pattern | A report, never a gate. Lists the checks each served title still owes. |
| `tools/synopsis_provenance.py` | ADAPT | Every synopsis carries a `synopsisSource`, and the client says where it came from (Decision 124). For audio the sources would be an episode-log database, Wikipedia, or the uploader. Respect the owner's "no AI copy" rule. |
| `tools/comment_fit.py` + `harvest_reviews.py` | ADAPT | Same problem, different vocabulary. Reviews about the file ("hiss", "64kbps", "skips at 12:00", "can someone upload the 1948 version") must be dropped as upload talk, not shown as reviews. |
| `tools/build-catalog.mjs`, `build-imdb-index.mjs` | N/A | Film bootstrap. |

### 2.2 Discovery and ingest

| Item | Verdict | Why / audio change |
|---|---|---|
| `discover_archive_collections.py` (`scrape_query`, `scrape_collection`) | ADAPT | Cursor-paginated scrape (`count: 5000`, `sorts: downloads desc`) with the `is_new` cap fix (the cap counts *accepted* items, not items read). Set `mediatype:audio` and change the collection list. Candidates **(unverified, census first)**: `oldtimeradio`, `otrr`, `radioprograms`, `audio_bookspoetry` (no), and the OTRR certified sets. **Bug to fix when copying:** `if not r.ok: return` ends the walk silently. That is discipline 1 broken: a 429 reads as "collection exhausted". |
| `discover_tv_shows.py` | ADAPT → `discover_radio_series.py` | Mines collections for series candidates and accumulates them in a discovery file the spine builder reads. |
| `discover_wikidata_pd.py` | ADAPT, low yield | Wikidata has radio-program items (P31 radio program) and P724 IA ids on some. Expect far fewer than the ~5,000 films **(unverified)**. Still useful for series identity, cast and dates. |
| `discover_pd_wants.py` | REPLACE or skip | There is no "List of radio programs in the public domain" counterpart to the Wikipedia film list. The title-first idea survives if a spine source (episode logs) defines the wants. |
| `discover_commercials.py` | N/A at first | Radio commercials are usually embedded in the episode. |
| `discover_loc.py` | REPLACE / research | LoC holds radio collections, but whether any of them are streamable and public domain is **unverified**. loc.gov blocks datacenter IPs (see its 403 branch), so ingest from Actions may be impossible. |
| `ingest_candidates.py` | ADAPT | The queue-drain → metadata → pick → classify → stamp flow is reusable. The per-file episode explosion is new. |

### 2.3 Series, episodes and TV-shaped tools (the closest analogue to radio)

| Item | Verdict | Why / audio change |
|---|---|---|
| Decision 016 + `build_canonical_tv.py` | ADAPT the architecture, REPLACE the source | The idea maps exactly: a **canonical series → season → episode spine** from an authority, with archive files mapped onto canonical episodes, extras never given an invented number, and `canonicalEpisodesCount` versus what we have giving the "X of Y" count. TVmaze does not cover radio. Candidate authorities, all **unverified** for API/terms/licence: RadioGOLDINdex (radiogoldindex.com), Jerry Haendiges' logs, the OTRR's own logs and OTRRpedia, Wikipedia episode lists, Wikidata. Radio has no seasons. Model it as `seasons: [{seasonNumber: <year or null>}]`, or add a `runs` / `broadcastYear` grouping. `parse_sxe` / `parse_epnum` → `parse_airdate` + log-number parsing. `map_items_to_canonical` matches on airdate first, then log number, then fuzzy title. |
| `series/*.json` v2 shape | ADAPT | Keep `seriesID`, `title`, `yearStart`/`yearEnd`, `overview`, `posterURL`, `genres`, `networks`, `creator`, `cast`, `episodesCount`, `canonicalEpisodesCount`. Each episode gains `fileName`, `audioFile {name, format, sizeBytes, bitrate, tier}`, `airDate` as the primary key field, `logNumber`, `sponsor`, `network`, and per-episode `cast`. `videoFile` → `audioFile`. Keep non-ASCII slugs percent-encoded (a real iOS 404, CATALOG-CONTRACT §6.3). |
| Decision 045 (episodes are first-class items, materialized in `build_sqlite.populate_series` as `tv-episode`) | ADAPT; becomes THE model | In the radio app almost everything is an episode. Make the episode the primary item from the start, with id `archiveID/fileName` or a stable hash. Favorites, playlists, sharing, history and search then work per episode with no special cases. The series card is the derived row. |
| `backfill_tv_episodes.py` (`parse_se`, `search_term`, `per_want_search`, `regroup_seasons`, daily-capped `--max-series`) | ADAPT | Same job: OTR uploads split one show across many items. Note its own lesson: it applied **no rights test**, which is how 1,920 TV items reached users unaudited (Decision 027 addendum, `audit_tv_rights.py`). In the new app, rights-gate at ingest from day one. |
| `build_episode_wants.py` | ADAPT | Missing-episode queue against the canonical log. |
| `audit_series_episodes.py` | ADAPT | Its `wrong_show`, `review_content` and `scrape_mirror` classes all recur in audio: podcast "reviews" of a show, a different show in the same batch, re-encodes. |
| `link_orphan_episodes.py`, `dedupe_orphan_episodes.py` (Decision 035) | ADAPT | Orphan uploads of an already-mapped broadcast must fold in or be hidden as duplicates. |
| `reconcile_tv_catalog.py` | ADAPT | Rebuilds series cards from the spines. |
| `audit_tv_rights.py` | REPLACE (§2.5) | It applies the film rules to TV. Radio needs its own rules. |
| Decision 036 (TV never in Movies) | Lesson only | A one-off special or audition must not leak into series browsing, and series must not leak into "single plays". |
| Decision 087 (era contradicts collection) | REUSE rule | A match whose era contradicts the item's own collection is cleared. |

### 2.4 Community, editorial and recommendation

| Item | Verdict | Why / audio change |
|---|---|---|
| `harvest_community_signals.py` (Decision 041) | REUSE nearly as-is | Uses batched `advancedsearch` `identifier:(a OR b …)` for downloads/week/month/num_favorites/avg_rating/num_reviews, plus `be-api.us.archive.org/views/v1/short/{ids}`. **Catch:** signals are **per item, and in OTR an item is often a whole series or batch**. Per-episode popularity is not available from these endpoints **(unverified whether views/downloads are file-level anywhere)**. Use item signals for series ranking only, and do not pretend an episode is popular. |
| `harvest_member_lists.py` | REUSE nearly as-is | Members' own lists and `fav-<name>` collections fit the owner's "no AI lists" rule. Change `MIN_SHARE`, so that "a list that is mostly radio" counts and "mostly films" is rejected. |
| `harvest_reviews.py` + `comment_fit.py` | ADAPT | See §2.1. |
| `build_sqlite._pop_score` | ADAPT | Drop `imdbVotes`. Keep the Bayesian rating with a vote floor and log-scaled downloads. |
| Decision 050 (computed shelves) | REUSE rule | Percentile thresholds recomputed every build, published in `meta`. |
| Decision 149 (`noRecommend`: never recommended, always findable) | REUSE mechanism | OTR has a large body of racist and propagandistic material (minstrel-format comedy, WWII propaganda). Discipline 7: popularity is not editorial judgement. Reuse the evidence-file pattern (`propaganda.json`), not its contents. |
| `featured.json`, `collection_metadata.json` shapes | ADAPT | Same schema. New categories with semantic accents. Don't reuse film brand colours for content meaning (Decision 013 split). |
| `build_channel_schedule.py` (Decision 144) | REUSE nearly as-is → **stations** | One UTC timeline per station, `[id, seconds]` slots, a fixed `gap`, days held stable once published, a removed program swapped in place for one of similar length. Shorter `gap` (seconds, not 120). Slots are 15- or 30-minute episodes. A station that keeps period order ("Thursday night on NBC, 1948") is a strong audio product. Program ids become episode ids. |
| `build_channel_pools.py` | ADAPT | Station pools by genre, network or era. |
| `build_film_feeds.py` (IPTV M3U/XMLTV/Xtream) | ADAPT → podcast RSS / OPML per series | The natural "side door" for audio is podcast apps. The owner's **"Side doors stay out of the way"** rule applies: documented on the website, never a button in the app. |
| `tonight.json`, `topshelf.json` (Decision 049) | ADAPT later | "Tonight" becomes "on the air now". Top Shelf on tvOS still applies. |
| `social_select.py` (sourced fragments, no prose) | ADAPT later | Decision 120 and discipline 7 apply as they are. |

### 2.5 Rights (must be rebuilt)

| Item | Verdict | Why |
|---|---|---|
| `audit_rights.py` `bucket()` | REPLACE the rules, REUSE the frame | Keep the frame: buckets with actions `keep/fix/hide/report/confirm`, `HIDE_BUCKETS`, a reversible `excluded` flag with a reason, the network `confirm_pass` reading the item's own `licenseurl`, `write_rejected_report`, `copyright_overrides`, the `FOREIGN` marker list (Decision 083), and the calendar-computed age line (Decision 137). **The film rules don't transfer.** US sound recordings fixed before 15 Feb 1972 fall under the Music Modernization Act / CLASSICS Act (2018), not the 95-year film rule. My understanding, to be confirmed by research: recordings published before 1923 entered the US public domain on 1 Jan 2022; those published 1923-1946 get 100 years from publication; 1947-1956 get 110 years; everything else fixed before 1972 is protected until 15 Feb 2067. On top of that, the *underlying works* (scripts, music cues, theme songs) carry their own copyrights. Many broadcasts were never "published" in the legal sense. AFRS transcriptions raise the question of US-government authorship. So **"an uploader put it in `oldtimeradio`" is not evidence**: Decision 140's "an uploader's word is not enough" binds harder here than it did for film. This is a Decision-027-class owner call. Treat it as the first research doc, before any surface is built. |
| `corroborate_licences.py` (Wikidata P275/P6216 on the P724 item, `licence_evidence.json`) | REUSE | Same evidence model. |
| `corroborate_copyright.py`, `fetch_cce_renewals.py` (Decisions 151/157) | REPLACE / research | Film renewals don't apply. The Catalog of Copyright Entries has drama and music sections where scripts and themes might appear **(unverified usefulness)**. |
| `rights_evidence.py` | ADAPT | Stamps *why* an item is kept. Same idea with radio-specific evidence names. |
| `likely_modern.json` pattern (Decision 159) | REUSE | Modern "radio drama" podcasts uploaded into OTR collections are the audio version of modern films dressed as silents. |
| `takedowns.json` + `exclude_takedowns` | REUSE | |

### 2.6 Liveness, playback and quality

| Item | Verdict | Why / audio change |
|---|---|---|
| `check_liveness.py` (`probe_playable`, `PROBE_BYTES = 1024`, `PLAYBACK_DEAD_CODES = {404, 410}`, `CONTAINER_SIGS`, `RUNTIME_DRIFT`) | ADAPT | Add audio signatures: MP3 = `ID3` or a frame sync `0xFFE`; Ogg = `OggS`; FLAC = `fLaC`; WAV = `RIFF…WAVE`. Keep "only 404/410 is definitive; 403/429/5xx are transient". Keep the visibility-tiered TTL (Decision 056). |
| `audit_codecs.py` (ffprobe the actual codec) | ADAPT | For audio: actual codec, sample rate, channels, true duration (truncated MP3s are common in OTR). The `fileRuntimeSeconds` vs canonical runtime check from Decision 052 becomes "a 4-minute file against a 30-minute log entry is a fragment". |
| `repair_derivatives.py` | ADAPT | archive.org derives asynchronously. An item ingested before its MP3 derivative existed should be re-picked later. |
| `bake_fallbacks.py` (Decision 077) | ADAPT | Fallback = the `64Kbps MP3` derivative when the VBR or original file won't start. Audio needs a start budget of a few seconds, not 25. |
| `validate_posters.py` (Decision 088) | ADAPT | There is far less artwork (no TMDb), but whatever image URLs we keep still rot. |
| `verify_external_match.py` (Decision 026) | ADAPT later | Only relevant once there is an external match to verify. The principle (verify against the item's *own* signals) is what to keep. |
| `cover-generation`, `color-classify`, `faststart-*`, `detect-trailers`, `roku-bifs`, `verify-playback-strict` (AVFoundation moov checks) | N/A | Video only. Generated covers become a typographic card (series title plus network and year). Don't extract frames from spectrograms. |
| Subtitles chain (`enrich_subtitles.py`, `free_subtitles.py`, `subtitle-*`, Decisions 039-073) | N/A as built; REVISIT as transcripts | Transcripts matter for accessibility and search in an audio app. Decision 039b (Whisper abandoned) and 043 (archive ASR dropped) are about *caption quality on film*. Re-decide for audio from measurement. Respect "no AI copy": a transcript is a different thing from copy, but say so in a decision. |
| Studio, Creation Studio, stock/word index | N/A | |

### 2.7 Fleet health, workflows and ops

| Workflow / tool | Verdict | Note |
|---|---|---|
| `publish-db.yml` | ADAPT | Keep the order: tests → fetch → remediate → audits → `publish --if-unchanged` with the exit-3 re-fetch loop → build → upload with `if: always()` *first* → build the web index (failure is fatal) → commit the index (non-fatal, `pull --rebase -X theirs`, 5 retries) → `gh_dispatch.sh deploy-pages.yml` (because `[skip ci]` suppresses the push-triggered deploy). Keep "stage then `git diff --cached`" (`git diff --quiet` cannot see untracked files). |
| `deploy-pages.yml` | ADAPT | Keep: the rsync excluding app source; artifacts generated in place and never committed (share pages); **floor guards** that refuse to deploy a shrunken build (`n -lt 20000` share pages); and "if the release exists its tarball MUST restore". Remove: subs, Roku legacy zip, Roku search feed, MCP, vetting. |
| `workflow-health.yml` + `audit_workflow_health.py` + `report_workflow_health.py` + `check_workflow_gates.py` | REUSE AS-IS | BROKEN/DROPPED/KILLED/DRAINED/SILENT/STALE, judged against each workflow's own cadence (Decision 090). Findings go to an issue, never a red X (Decision 107). Every writer must print a **yield line** or it reads SILENT. |
| `retry-infra-failures.yml` + `retry_infra_failures.py` | REUSE AS-IS | Decisions 048/057/095. |
| `discover-content.yml` | ADAPT | Same daily shape. |
| `rights-audit.yml`, `check-liveness.yml`, `community-signals.yml`, `member-lists.yml`, `validate-posters.yml`, `tv-canonical.yml` (→ `series-canonical.yml`) | ADAPT | |
| `pulse.yml` + `pulse_collect.py` (Decisions 108/123) | ADAPT later | Copy the rules (isolated sources, "could not read" written out, never a zero), not the 3,160-line collector. |
| `appstore-*.yml`, `play-release.yml` | ADAPT later | Decisions 101/110: build in CI and promote the same artifact. One version number in `AppVersion.xcconfig`. |
| The other ~25 enrichment/video workflows | N/A | `tmdb-enrich`, `omdb-backfill`, `tvdb-movies`, `wikidata-posters`, `resource-posters*`, `cast-images`, `stock-*`, `word-index`, `subtitle-*`, `auto-captions`, `social-*`, `youtube-unlisted-upload`, `probe-*`, `play-bucket-probe`. |

### 2.8 Client data layers

| File | Verdict | Note |
|---|---|---|
| `Store/CatalogDB.swift` (verbs `shelf`, `browse`/`browseCount`/`browsePageJSON`, `search` + `ftsQuery`, `item`, `itemsByIDs` + `resolveAliases`, `byPerson` column-scoped FTS, `byCollection`, `random*`, `decadeCounts`, `metaInt`) | ADAPT | The verb set and the four filter clauses (`adultAnd`, `typeAnd`, `homeAnd`, `notCommercial`) carry over. Add episode verbs (`episodes(series:)`, `nextEpisode(after:)`, `onThisDay(month:day:)` since airdates are rich). `homeAnd` becomes the radio rights tier. Keep the search ranking (title exact or prefix first, then art, then popularity, then FTS rank) and its cross-platform parity test (`test_search_rank_parity.py`). |
| `Services/CatalogRefreshService.swift` | REUSE AS-IS | ETag, staging inflate, size floor, atomic swap, probe. The ~64 KB `compression_stream` chunk bug (stable buffer; never re-bind `src_ptr`) is documented in CATALOG-CONTRACT §4. |
| `Models/Catalog.swift` `Catalog.Item` | ADAPT | Additive-optional decoding is the rule. `videoFile` → `audioFile`. Remove film-only predicates. |
| `Networking/ResilientStreamLoader.swift` (Decisions 021/031/034) | ADAPT, likely simpler | Range resume, node pinning, and node failover via `metadata.server` + `alternate_locations.workable` all still apply. Files are small (~7-30 MB per half hour at 32-128 kbps), so stalls are rarer but not absent. Measure before porting. Background audio, `MPNowPlayingInfoCenter`, remote commands, CarPlay and Android Auto are new work, with no Archive Watch precedent. |
| `Networking/DerivativePicker.swift` and `js/api.js` `pickVideo` | REPLACE | They mirror `pick_video`. Keep them mirrored with a test, but the pipeline bakes `downloadURL`, so clients should not pick at runtime (CATALOG-CONTRACT §8). |
| Android `CatalogDatabase.kt` / `CatalogRepository.kt` | ADAPT | Same port. Media3 is already audio-capable. |
| `watch.js` `Data` + `build_catalog_index.py` / `build_web_details.py` / `build_episode_index.py` / `build_people_index.py` | ADAPT | A positional-tuple index on Pages plus 256 detail shards. For audio the episode index is the main index. Keep `test_details_contract.py` (Decision 116: a contract is a test). |
| Sync (Decisions 009/022/078/102) | ADAPT | No accounts. Per-ecosystem sync on the user's own cloud. Listening history is a durable union-merged record, and "completed" stays sticky. That is essential for episodic listening. |

---

## 3. The eleven disciplines, and the decisions whose lessons transfer

### 3.1 Disciplines (`docs/ENGINEERING-PROCESS.md`)

1. **Absence is not evidence.** A reader that could not read says so. Audio
   example: a per-item signal "0 downloads" on a file-level episode is "unknown",
   not zero.
2. **A green run is not a working run.** Assert the yield (rows written, files
   present). Copy `sqlite_publish_guard.py` and `audit_workflow_health.py` on
   day one.
3. **A test is not a test until you have seen it fail.** Record the failure
   count of the broken control.
4. **Verify on the glass, in the shipping environment.** Release builds on real
   devices. Background audio and lock-screen controls only behave truthfully
   there.
5. **Measure before theorising; record what you ruled out, with an expiry.**
   This applies to every **(unverified)** in this doc.
6. **A number needs a comparison; a chart needs a reason.** Pulse rules.
7. **Popularity is not editorial judgement.** OTR's racist and propaganda
   material is the radio counterpart of *The Birth of a Nation*.
8. **The owner's machine is not a build server.** Bound every loop. ffmpeg
   through `ffmpeg_limits.py`. Builds in CI.
9. **A red X means THIS run could not do its job.** Auditors never fail; a
   partial success is a warning.
10. **Search the decision log for the MECHANISM, not the symptom.** Keep a full
    index in `DECISIONS.md` (Decision 092).
11. **The instrument is the first suspect.** Run the opposite-verdict control.
    Diagnostics go to stderr. Count pass, skip and fail separately.

### 3.2 Decisions whose lessons transfer (one line each)

- **009** No accounts; all state local. Keeps privacy and App Review simple.
- **012 / 105** Mature filtering is one predicate, default on, baked by the pipeline.
- **013** Brand colours are for chrome, semantic colours for content meaning. Never mix them.
- **016** Use a canonical spine from an authority; map files onto it; never invent an episode number.
- **017 / 019** Ship a prebuilt SQLite DB with FTS5, raw-DEFLATE compressed, queried on disk, never held in memory.
- **018** The generated catalog lives on a Release, never in git (git reached 600 MB).
- **020** Rebuilds are additive and merge-guarded; abort on shrink.
- **026** Verify an external match against the item's own signals.
- **027** Rights hides are a reversible flag with a reason, confirmed by the item's own `licenseurl`; the owner decides hides.
- **028** One data plane; native UI per platform; feature parity, not design consistency.
- **029** Browsers can't fetch Release assets (no CORS), so serve a Pages index.
- **031 / 034** Pin the storage node after the 302; on a hard failure, fail over to `alternate_locations.workable`.
- **035 / 036** Duplicate episode uploads fold in or hide; series never leak into single-item browsing.
- **040 / 040a** Collapse re-uploads by corroborated identity (union-find, with contradiction veto). Precision over recall.
- **041** Harvest archive.org community signals; use them for sort and for best-copy selection.
- **044** Enforce quality gates on every build, not once.
- **045** Episodes are first-class items.
- **048 / 057 / 095** Re-run work that GitHub never started or that the concurrency queue displaced.
- **050** Anything computed from an internal score is computed in the pipeline, as a percentile; clients never restate the threshold.
- **052 / 163** Judge fragments by runtime evidence; let archive.org's own collections speak.
- **053** First paint comes from the cached catalog; the bundled seed is for first launch only.
- **055** "Already attempted" markers are per source, or a second source never runs.
- **056 / 088** Verification freshness has a TTL tiered by visibility.
- **066** Writers compute without the lock and take it only to merge a delta.
- **077** Startup budget plus an immediate vetted fallback.
- **078** History is a durable union-merged record; "completed" is sticky.
- **083** `excluded` is shared state; every writer registers its marker.
- **085** A merged-away id forwards to its survivor (favorites must not vanish).
- **089** A shared index publishes only what it can prove did not shrink; a missing asset is an emergency, not a first run.
- **090** Judge each workflow against its own cadence.
- **092** Keep the decision log small in context: full index plus recent entries, older ones archived verbatim.
- **093 / 107** A red X is reserved for broken; auditors report through an issue.
- **101 / 110** One version number; release builds come from CI and are promoted, never rebuilt.
- **104** A `private` file is never a playable copy; guard it in the picker.
- **108 / 123** One dashboard; a reader that cannot read says so.
- **116** A data contract is a test.
- **124** Synopsis provenance is recorded and shown.
- **130 / 133** Prove a rule on the product path, where the value lands.
- **137** "PD by age" is computed from the calendar, never a literal year (more important under the MMA's sliding terms).
- **140** An uploader's word is not enough.
- **141 / 148 / 155 / 165** Platform floors are explicit, held by build gates, and changed only as owner decisions.
- **144** Stations run on one published UTC clock, shown in local time.
- **149** Never recommended, always findable, on evidence a reader can open.
- **151** A hide needs a claim a reader can open; not knowing is not a claim.

---

## 4. Gotchas an audio app will hit again

**archive.org APIs**
- `advancedsearch.php` is used for small batched `identifier:(…)` lookups and
  title search (`archive_lib.adv_search`, `rows=`). Bulk enumeration uses the
  **scrape API** `services/search/v1/scrape` with `cursor`, `count` up to 5000
  and `sorts`. The repo walks collections only through scrape.
- `adv_search` returns `[]` on a non-OK response, and `scrape_query` `return`s.
  **Both make a throttled call look like "nothing found"** (discipline 1). In the
  new copy, distinguish the two.
- `/metadata/{id}` **sends CORS** but sometimes hangs for minutes or 404s for
  items that play fine. Bound it (`js/api.js` uses a 20 s `AbortSignal.timeout`;
  `archive_meta` uses 40 s). Bake `downloadURL` and don't re-derive at runtime
  (`build_web_details.py` docstring).
- `download/` storage nodes support range requests and send **no CORS**. That
  is fine for `<audio src>`, but it **blocks Web Audio / MediaSource / waveform
  analysis** in the browser. This is a new constraint for audio. Release
  assets: no CORS, 302 to `objects.githubusercontent.com`. Pages: CORS `*` and
  206 on ranged GET (the "200 not 206" result was a HEAD artifact).
- **Datacenter clients are treated differently.** Without a User-Agent, ffmpeg
  got 403/401/5xx on nearly every file (`build_stock_index.py`,
  `build_word_index.py`). archive.org refuses image downloads to some
  datacenter fetchers (Roku's validator; `build_roku_search_feed.py`). loc.gov
  blocks GitHub Actions IPs (`discover_loc.py`). Wikimedia sends 429 to spoofed
  UAs (`audit_workflow_health.py` docstring). Always send an honest UA with a
  contact.
- 403/429/5xx/timeouts are **transient**. Only 404/410 is definitive
  (`check_liveness.py`). Never hide on a failed fetch.
- Archive derives files asynchronously: a fresh upload may have no MP3 or OGG
  derivative yet (`repair_derivatives.py`).
- `private: true` files fail with 401/403 forever on every node (Decision 104).
  `history/files/*.~N~` are old revisions.
- Multi-work items: the largest file is not the right file (`title_files`
  docstring: April Maze played "Felix Finds Out"). For OTR this is the common
  case.
- Thumbnails: `archive.org/services/img/{id}` is the last-resort art.
  archive.org also auto-generates spectrogram PNGs for audio **(unverified)**.
  Don't mistake one for cover art.
- Community signals and reviews are **per item**, not per file.
- Idle connections are dropped mid-file. Resume from the exact byte offset
  (Decision 021). For ffmpeg, pass `-reconnect 1 -reconnect_streamed 1`.

**GitHub**
- **Scheduled runs start 4-5 hours late** on this repo (SCRATCHPAD; the Pulse
  cron was moved to 08:17 UTC for it). Don't chain workflows by clock time
  alone; chain with `workflow_run` or dispatch.
- Only **one pending run per concurrency group**. A newer arrival cancels the
  older pending one (Decisions 057/095). Long jobs must not hold the lock
  (Decision 066).
- 360-minute job cap: a job that hits it skips its publish steps. Use
  `if: always()` on publish and `--max-minutes` budgets.
- **Release asset limit is 2 GiB** (`size must be less than 2147483648`, a 422
  that must not be retried). `gh release upload --clobber` **deletes before
  uploading**, so a failed upload loses the asset. That is how 702,148 word
  timings were destroyed. Never `|| echo "first run"` on a restore.
- A `[skip ci]` commit suppresses the push-triggered Pages deploy. Dispatch it
  explicitly, or the site freezes (it was 8 days stale once).
- Pages: 1 GB site budget and roughly 100 GB/month bandwidth (comments in
  `deploy-pages.yml`/`publish-db.yml`). That is why the DB lives on a Release.
- Pages serves `404.html` with HTTP 200 for missing paths under some setups:
  "subtitles" that were an HTML page. Floor-guard generated trees.
- `git diff --quiet` can't see untracked files (a new artifact silently never
  committed).
- Concurrent writers race on the generated-index commit. Use
  `pull --rebase -X theirs` with retries, and make it non-fatal.
- An empty repo secret is green (`omdb-backfill`). Assert that secrets are
  present.

**Clients**
- Raw DEFLATE only under `.zz`. A gzip there fails the shipped inflater.
- Non-ASCII slugs must be percent-encoded.
- The service worker at root scope cached `/pulse` (`test_sw_bypass.mjs`). An
  audio PWA's service worker must never cache MP3 range responses by accident.
- R8 stripped a Room constructor only in release builds. Test the release
  artifact on a device.
- Decision 106 (tvOS 27 drops the audio of non-fragmented MP4) is a risk only
  if AAC is served in MP4/M4A. MP3 is untested; measure on tvOS first.

---

## 5. Proposed pipeline layout for the new app

```
<radio-repo>/
  tools/
    audio_lib.py                 ← archive_lib.py   (pick_audio, title_files, resolve_title, UA)
    content_type.py              ← rewritten vocabulary, still import-free
    catalog_release.py           ← as-is (tags: catalog-source, catalog-db)
    catalog_delta.py             ← as-is
    merge_catalogs.py            ← as-is
    sqlite_publish_guard.py      ← as-is
    gh_retry.sh, gh_dispatch.sh  ← as-is
    discover_collections.py      ← discover_archive_collections.py (mediatype:audio; fix silent return)
    discover_series.py           ← discover_tv_shows.py
    discover_wikidata.py         ← discover_wikidata_pd.py (radio-program classes)
    ingest_candidates.py         ← adapted (one item → many episode records)
    build_series_spine.py        ← build_canonical_tv.py (episode-log authority instead of TVmaze)
    backfill_episodes.py         ← backfill_tv_episodes.py (rights-gated at ingest)
    build_episode_wants.py       ← adapted
    audit_series_episodes.py     ← adapted
    link_orphan_episodes.py, dedupe_orphan_episodes.py, reconcile_series_catalog.py ← adapted
    remediate_catalog.py         ← NEW file seeded from the title/synopsis sanitizers,
                                   takedowns, not-radio, noRecommend, corrections loaders
    audit_rights.py              ← NEW rules (sound-recording terms), same frame
    corroborate_licences.py, rights_evidence.py ← adapted
    check_liveness.py            ← audio CONTAINER_SIGS
    audit_codecs.py              ← audio ffprobe (codec, rate, true duration)
    repair_derivatives.py, bake_fallbacks.py ← audio tiers
    harvest_community_signals.py ← as-is (+UA)
    harvest_member_lists.py      ← MIN_SHARE for radio
    harvest_reviews.py, comment_fit.py ← audio vocabulary
    synopsis_provenance.py, coverage_report.py ← adapted
    build_related.py             ← new attributes (voice cast, sponsor, network, writer)
    build_sqlite.py              ← episodes-primary schema, broadcast dedupe, aliases, .zz
    build_catalog_index.py, build_web_details.py, build_episode_index.py,
    build_people_index.py, build_share_pages.py ← adapted
    build_station_pools.py       ← build_channel_pools.py
    build_station_schedule.py    ← build_channel_schedule.py
    build_podcast_feeds.py       ← build_film_feeds.py (RSS/OPML; website only)
    audit_workflow_health.py, report_workflow_health.py,
    check_workflow_gates.py, retry_infra_failures.py ← as-is
    ffmpeg_limits.py, dev_cleanup.sh ← as-is
    run_pipeline_tests.sh + test_*.py ← new list, each with a broken control
  shared/editorial/              ← EMPTY versions of: takedowns.json, licence_evidence.json,
                                   likely_modern.json, title_corrections.json, year_corrections.json,
                                   type_corrections.json, match_rejects.json, no_recommend.json,
                                   collection_metadata.json, discovery_candidates.json
  series/*.json                  ← generated spines (git + Pages)
  featured.json
  .github/workflows/
    discover-content.yml, publish-db.yml, deploy-pages.yml, rights-audit.yml,
    check-liveness.yml, community-signals.yml, member-lists.yml,
    series-canonical.yml, workflow-health.yml, retry-infra-failures.yml
  docs/ CATALOG-CONTRACT.md (rewritten for episodes), ENGINEERING-PROCESS.md (copy),
        DECISIONS.md (fresh, with a "lessons inherited from Archive Watch" entry
        citing the decision numbers above)
```

**Do not copy:**
- Any data file from `shared/editorial/`. The caches (`omdb_cache`,
  `tmdb_*_cache`, `origin_cache`, `archive_own_meta`, `cce_renewals`,
  `movie_enrich_cache`), the decisions (`propaganda.json`,
  `copyright_evidence_overrides.json`, `tv_rights_*`) and the film lists are all
  film-specific. Copy the shapes only.
- `catalog.json`, `catalog-index.json`, `details/`, `aliases.json`,
  `people.json`, `channel-*.json`, `episodes-index.json`, `topshelf.json`,
  `tonight.json`, `seed.sqlite`. These are generated.
- TMDb/OMDb/TVDB/fanart/Wikidata-poster enrichers, `verify_external_match.py`
  (until there is a matcher), `audit_title_identity.py`, the `_clear_wrong_artwork`
  family, `scrub_cleared_match`, URAA, colour, covers, faststart, trailers,
  Roku BIFs, `verify_playback_strict`, the subtitle chain, stock/word/subtitle
  indices, the Studio and Creation Studio code, `social_*`, YouTube/Twitch
  OAuth, `worker/` (unless rooms are wanted later; `together.js` would be the
  starting point), the MCP endpoint, the Roku search feed, the store-screenshot
  tools, and `pulse_collect.py` (rewrite small).
- `Secrets.xcconfig`, any signing key (the Roku key in particular is never
  regenerated and never shared), Google verification files, `CNAME`.
- `remediate_catalog.py` as a whole. 4,350 lines of film-specific repairs would
  import film assumptions silently.

---

## Summary

1. The data plane transfers almost unchanged: Release-hosted `catalog.json` →
   remediate and audit → `build_sqlite.py` → `catalog.sqlite.zz` on a rolling
   Release, plus a Pages index, shards and editorial JSON. Clients only consume.
2. The plumbing can be reused as-is: `catalog_release.py`, `merge_catalogs.py`,
   `catalog_delta.py`, `sqlite_publish_guard.py`, `gh_retry.sh`, and the health,
   retry and gates tools.
3. The biggest schema change is that OTR items usually hold many episodes, so
   the episode key is `(archiveID, fileName)` and episodes are the primary
   items (Decision 045 taken to its end).
4. `pick_video` becomes `pick_audio`. Keep the private/history/title-file
   guards, but prefer MP3 derivatives over "largest file".
5. The TV spine architecture (Decision 016) maps onto radio series, but TVmaze
   must be replaced by an episode-log authority (all unverified), keyed on
   airdate.
6. Dedupe (Decisions 040/040a/085) maps onto the same broadcast uploaded many
   times. Rank survivors by audio quality.
7. Channels (Decision 144) become stations almost verbatim. IPTV feeds become
   podcast RSS, website-only.
8. Community signals and member lists transfer, but archive.org's signals are
   per item, not per episode.
9. The rights audit must be rebuilt: pre-1972 sound recordings follow the
   MMA/CLASSICS Act terms, with separate script and music rights. This is an
   owner call and the first research doc.
10. Video tooling (colour, covers, faststart, trailers, subtitles, Studio, BIFs)
    and all film enrichers and caches are not applicable.
11. Gotchas that will recur: silent `return` on a throttled search; per-node
    failover; private files; no CORS on download nodes (which blocks Web Audio);
    the UA requirement for datacenter clients; cron runs 4-5 hours late; one
    pending run per concurrency group; the 2 GiB asset limit; `--clobber`
    deleting before upload; `[skip ci]` suppressing deploys.
12. The eleven disciplines carry over verbatim. The key ones: absence is not
    evidence, assert the yield, break every test, verify on device, red X only
    for broken.
13. Section 5 gives a concrete copy, rename and do-not-copy list for the new
    repo's `tools/`, `shared/editorial/` and workflows.
