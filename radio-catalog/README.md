# radio-catalog — the rights-designated catalog for the radio drama app

Owner, 2026-10-17: *"Can you start work on building out a full database with each
of the rights designations considered."* Research: `../docs/research/RADIO-DRAMA.md`.
Self-contained so it can move to the radio app's own repository unchanged
(stdlib Python only; it reads one Archive Watch file, `shared/editorial/cce_renewals.json`).

## Run

    python3 tools/harvest_ia.py --workers 4      # archive.org: ~12,171 items, ~3-4 h
    python3 tools/harvest_librivox.py            # 640 dramatic works, ~1 min
    python3 tools/fetch_p72_schedules.py         # 299,447 schedule rows, ~5 min
    python3 tools/harvest_radioechoes.py         # the spine: 5,069 pages at 10 s = ~14 h, resumable
    python3 tools/build_db.py                    # -> out/radio-catalog.sqlite + out/build_report.json
    python3 tests/test_audio_rights.py && python3 tests/test_otr_parse.py

Caches live in `.cache/` and outputs in `out/` (both gitignored; the database is
never committed, as Archive Watch Decisions 017/018). Every harvester exits
non-zero when it read nothing, and records what it could not read.

## The rights states (`tools/audit_audio_rights.py`, DECISIONS 001-002)

| State | Buckets | Client |
|---|---|---|
| `keep_clean` | `rec_gov_work`, `rec_librivox`, `rec_cc_corroborated`, `rec_pd_published_age` | plays |
| `keep_unclaimed` | `rec_orphan_unclaimed` | plays; rights line "no claim known; removed on request", never "public domain" |
| `hide_claim` | `rec_takedown`, `rec_schedule_claim`, `rec_rights_holder_claim`, `rec_post_1972`, `rec_foreign_origin`, `work_script_claim`, `work_adapted_renewed` | hidden |
| `hide_unidentified` | `rec_no_evidence` | hidden: no series and date to check a claim against |

Order: hides before rescues, first match wins; the stricter of the recording and
underlying-work layers wins. Every row's `evidence` lists what decided it, each
with a source a reader can open.

**Defaults applied where the owner has not ruled** (02-rights §11): non-US
productions hidden (Q7); post-1972 hidden; AFRS rebroadcasts of network series
judged as that series; government series kept with the §105/§1401 question noted
(Q6); music and variety judged like drama (Q5); unregistered scripts unclaimed
unless a claim is found (Q4). **Not yet checked**: script renewals in the printed
Catalog of Copyright Entries drama volumes (the parser is still to write), and
film renewals after 1949 (Lux episodes adapting 1950s films read `work_none_found`
only because that index is not built).

## Editorial (each entry needs a source a reader can open)

`audio_claims.json` (claimants), `takedowns.json`, `gov_series.json`,
`series_aliases.json`, `licence_evidence.json`, `published_records.json`.

## Tests

`tests/test_audio_rights.py` (17 cases) and `tests/test_otr_parse.py` (15).
Broken controls, 2026-10-17, each run against a mutated copy:

    orphan reads as clean              15/17     no post-1972 rule             16/17
    bare ABC counts as foreign         16/17     age line off by one           16/17
    AFRS copy counts as government     16/17     rescue before hide            16/17
    adaptation window open-ended       16/17     uploader licence rescues      16/17
    parser: no leading-track strip     14/15
