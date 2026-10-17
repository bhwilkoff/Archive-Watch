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
unless a claim is found (Q4). **Not yet checked by the audit**: script renewals in
the printed Catalog of Copyright Entries drama volumes (parsed, below, not yet wired
in), and film renewals after 1949 (Lux episodes adapting 1950s films read `work_none_found`
only because that index is not built).

## Script renewals in print (`tools/fetch_cce_drama_renewals.py`)

    python3 tools/fetch_cce_drama_renewals.py            # ~41 MB of OCR, ~6 min first run; then cached
    python3 tools/fetch_cce_drama_renewals.py --offline  # re-parse .cache/cce_drama/ only
    python3 tests/test_cce_drama_renewals.py

This reads the RENEWAL entries in the Catalog of Copyright Entries' "Dramas and
Works Prepared for Oral Delivery" volumes, the claim source 02-rights §3.1 names
for scripts registered 1923-1950 (renewals filed 1951-1977; from 1978 the
Copyright Office's online records take over). It writes
`.cache/cce_drama_renewals.json.gz`, one row per original registration:
title, episode, series, author, claimant, D/C registration and date, renewal
number and date, volume, line and a `src` link that opens the scan at a search
for the renewal number. It is not yet wired into the audit.

**Measured 2026-10-17.** `title:("catalog of copyright entries") AND
title:(dramas)` returns all 31 Third Series volumes, 1947-1977, one a year (plus
14 New Series 1915-26 volumes with no relevant renewals). 1947-1950 print no
renewals (those years' are in Part 14A, Literature/Art/Film, not read). The
other 27 volumes give **11,166 renewals** (original registrations 1922-1950),
**679 flagged radio**, 110 in Class C (lectures and recording scripts), and 213
whose renewal number the OCR mangled. Those rows are kept with `r: null` and the
printed text in `r_printed`: the entry is a renewal, but its number is not
guessed. Four printed layouts are read: 1951-53 under the author with the
renewal number first; 1954-57 under the author with the claimant first; 1958-70
under the title in capitals, where a series lists every registration against one
renewal range; and 1971-77 in renewal-number order with the series in
parentheses. A row needs a © date, a D/C registration, a renewal number and a
renewal date 26-29 years later, so OCR damage causes misses (roughly a quarter to
a third of entries in the worst 1970s volumes), not false matches.

**Validation**, by series (rows; original years; claimant):

| Series | Rows | Registered | Renewed by |
|---|---|---|---|
| The Lone Ranger | 271 (258 by claimant) | 1934-49 | The Lone Ranger Inc., Wrather Corp., Lone Ranger Television (e.g. R300173-5, 1962) |
| Nick Carter | 146 | 1943-50 | Condé Nast (Street & Smith) |
| The Shadow | 71 | 1940-50 | Condé Nast (first: R420827, 1967) |
| Arch Oboler | 47 | 1939-49 | Arch Oboler |
| Green Hornet | 48 (42 by claimant) | 1936-44 | Green Hornet, Inc. (R336319, 1964) |
| The Greatest Story Ever Told | 29 | 1947-50 | Henry Denker |
| Vic and Sade | 15 | 1938-43 | the Rhymer family |
| Let's Pretend | 11 | 1934-49 | CBS, Inc. (R577542-6, 1974) |
| Norman Corwin | 5 | 1942-44 | Corwin, Lucille Fletcher |
| Fibber McGee and Molly | 4 | 1935-44 | Don Quinn's family (R296914, 1962) |
| Cavalcade of America | 4 | 1945-47 | Du Pont |
| The Witch's Tale | 1 | 1933 | Alonzo Deen Cole (R273162, 1961) |
| Suspense, Gunsmoke, Johnny Dollar, Dragnet, Lux, Inner Sanctum | 0 | | |

The raw OCR confirms the zeros: none of those names appears in a block that
carries a renewal number. Inner Sanctum and Lux were registered (Inner Sanctum
lists Tepperman scripts in one volume) and never renewed in print. Gunsmoke,
Dragnet and Johnny Dollar (1949-52) would renew in 1977-80, mostly in the online
records. The "Jack Benny" and "Lights Out" hits are stage plays with those
words in their titles, not the radio series.

## Editorial (each entry needs a source a reader can open)

`audio_claims.json` (claimants), `takedowns.json`, `gov_series.json`,
`series_aliases.json`, `licence_evidence.json`, `published_records.json`.

## Tests

`tests/test_audio_rights.py` (21 cases), `tests/test_otr_parse.py` (15) and
`tests/test_cce_drama_renewals.py` (13; its broken controls are in its docstring).
Broken controls, 2026-10-17, each run against a mutated copy:

    orphan reads as clean              15/17     no post-1972 rule             16/17
    bare ABC counts as foreign         16/17     age line off by one           16/17
    AFRS copy counts as government     16/17     rescue before hide            16/17
    adaptation window open-ended       16/17     uploader licence rescues      16/17
    script date window open-ended      19/21     series renewal floor of 1     19/21
    script renewals never expire       20/21     script renewal not a hide     19/21
    parser: no leading-track strip     14/15

The "script renewal not a hide" control first PASSED 21/21: the new cases checked
which bucket fired but not the state. They now assert both.

**Schedule matching, measured on the first build**: matching a series to a
performer's name hid 1,318 episodes, nearly all of them radio shows of
performers whose COMMERCIAL RECORDS a label scheduled (Phil Harris 241, Delmore
Brothers 160, Gene Autry 74). A schedule protects the recording it lists, so a
series-level match now needs a scheduled row that is itself a broadcast, and an
episode-level match needs the whole artist name, not a shared first name.

**Script renewals** (`work_script_renewed`, `work_series_renewals`): a broadcast
whose script registration is within 30 days of its air date, or whose title and
year match, is hidden until registration year + 96. A series with 10 or more
live renewals is claimed as a series — a default for the owner, because the
printed catalogs lose a quarter to a third of entries to OCR.
