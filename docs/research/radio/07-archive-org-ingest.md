# 07 — The Internet Archive OTR corpus, and how to ingest it (2026-10-17)

Research track 7 of the radio sister-app study. Written in a container whose
network policy blocks archive.org; every archive.org fact below comes from
**web search results/snippets** (marked "per search snippet"), from Archive
Watch's own working code (which was verified live when it was written), or
is marked **UNVERIFIED**. Nothing here was measured against a live endpoint
in this session. The "To measure" section holds the probes, including a
complete stdlib script ready to save as `tools/probe_otr_corpus.py`.

Also note: this session's shared web-search budget ran out before searches
for Inner Sanctum, Lights Out, the Joe Hehn collection and a few other items
could run. Those gaps are named where they fall.

## Verdict

1. **The unit of content is the FILE, not the item.** Archive Watch's film
   model (one item = one film, `pick_video` picks one derivative) does not
   carry over. An OTR item is usually a whole series, a season, a year, or an
   alphabet range ("Singles and Doubles T-Z"), with tens to hundreds of MP3s
   inside; episodes are rows in `files[]` of `/metadata/{id}`. There is also a
   minority of one-episode-per-item uploads (`TSP420617`,
   `xminusone19550424nocontact001`, `JackBennyProgram481017SorryWrongNumber`),
   so the ingest must handle both shapes and treat them as the same broadcast.
2. **OTRR (Old Time Radio Researchers) is the spine.** Its uploads
   (`OTRR_<Series>_Singles`, `OTRR_Certified_<Series>`, per-year and
   per-season splits such as `OTRR_Suspense_Singles_By_Year_1942`,
   `OTRR_Lux_Radio_Theatre_Season_13_Singles`) carry the closest thing the
   hobby has to edited episode identity: `Series_YY-MM-DD_epNNN_Title.mp3`
   filenames, with `xx` placeholders where unknown. The index is
   `archive.org/details/OTRR_Home_Page`.
3. **Episode identity = (series, broadcast date), corroborated by duration
   and md5.** Filenames are the main carrier; file-level `title`/`track`
   tags are a second witness when present (UNVERIFIED how often they are).
   Dates come in at least five spellings (YY-MM-DD, YYMMDD, YYYY-MM-DD,
   "YYYY MM DD", MMDDYYYY); the 1942-06-17 premiere of Suspense is
   "The Burning Court" (`TSP420617`), which shows how a date key unifies
   uploads with different titles.
4. **OTRR items carry Creative Commons BY-NC-ND licences** (per search
   snippets: X Minus One 3.0, Escape 3.0, Lux 4.0). That is a claim over
   OTRR's compilation and restoration. It is not evidence the recordings are
   public domain, and the NC/ND terms bind any redistribution we do (Decision
   140's "an uploader's word is not enough" applies in both directions). The
   rights track owns the verdict; ingest only records `licenseurl` per item as
   provenance.
5. **APIs needed are the ones Archive Watch already uses**: the Scrape API
   (`/services/search/v1/scrape`, cursor, `count` up to 5,000 in our own
   working code), `/metadata/{id}` for `files[]` and `reviews[]`,
   advancedsearch fields `downloads`/`num_favorites`/`avg_rating`/
   `num_reviews`, the be-api views service, and member lists
   (`/services/users/@{user}/lists`). The new parts are the file-level
   parser, a per-file playable picker for audio, and a cross-item dedupe.
6. **Corpus size is unknown from here.** No search result gave a count for
   `collection:oldtimeradio`. One sub-collection (`lumedwards`, "Old Time Radio
   Researchers Collection") shows "collection size 676" per search snippet.
   OTRR's Suspense Singles is ~32.2 GB and its Lux Singles ~31.3 GB (snippets).
   The probe script measures all of this in one run.

---

## 1. Where OTR lives on archive.org

### 1.1 Collections and families (identifiers as seen in search results)

| Id / family | What it is | Evidence | Status |
|---|---|---|---|
| `oldtimeradio` | The main "Old Time Radio" collection; a 2006 IA blog post calls it "our Old Time Radio collection" while describing a user uploading hundreds of Superman episodes into it | blog.archive.org 2006-10-24; library.missouri.edu tip 2016 | count UNVERIFIED |
| `lumedwards` | "Old Time Radio Researchers Collection", parent `oldtimeradio`, "collection size 676" | per search snippet of archive.org/details/lumedwards | snippet only |
| `OTRR_*` items, uploader **OTRRArchive** | OTRR's own sets: `OTRR_<Series>_Singles` (sampler, "Single Episodes Page"), `OTRR_Certified_<Series>` (older certified sets), `..._By_Year_YYYY`, `..._Season_NN_Singles` | many snippets (Suspense, Gunsmoke, Lux, X Minus One, Dimension X, Escape, Jack Benny, Johnny Dollar, Whistler, Box 13, Hallmark...) | structure from snippets |
| `OTRR_Home_Page` | OTRR's alphabetical index of every series page, updated 2020-01-11 per snippet | archive.org/details/OTRR_Home_Page | snippet |
| `Singles_And_Doubles_Singles_A-C` ... `_T-Z` | OTRR's set for series with one or two surviving episodes, split by alphabet | archive.org/details/Singles_And_Doubles_Singles_T-Z | snippet |
| `radioprograms` | cited by a forum post as "a huge collection of old time radio shows" | rblind.com post 2421891 | existence UNVERIFIED |
| "The Joe Hehn Memorial Collection" (e.g. `Suspense1JHMC`, `OTRCatalogs`) | collector-sourced sets; also holds 1960s-70s collector catalogs | snippets of archive.org/details/Suspense1JHMC, /OTRCatalogs | snippet |
| "The Suspense Project" (`TSP420617`, `TSP420902`, `80thAnnivSuspenseMarathon`) | one item per Suspense broadcast, id `TSP` + YYMMDD | snippets | snippet |
| Misc. user sets | `ClassicRadioShows`, `oldtimeyradioshowscollection`, `USA-Golden-Age-of-Radio`, `UniqueOldTimeRadioEpisodes`, `SUSPENSE_Radio_Digitally_Restored_Collection`, `JackBenny1` ("Jack Benny 143 Eps", 2.0 GB), `FibberMcgeeMolly1930s` ("63 Eps"), `XMinus1_A`, `XMinus1B`, `SUSPENSE2`, `Dimension-X`, `RkoOrsonWelles-TheShadow-RadioRecodings` (33 recordings, 1937-38) | snippets | snippet |
| `librivoxaudio` | LibriVox audiobooks. Not radio drama; relevant only as a separate shelf (LibriVox's "dramatic works" are modern readings, PD by dedication) | not searched this session | UNVERIFIED |
| Radio news (2016+), TV news | IA's broadcast-news collections; out of scope (modern, not OTR) | uark libguide | out of scope |

**mediatype.** Archive Watch filters films on `mediatype:movies`. OTR items
should be `mediatype:audio`. Whether a distinct `radio` mediatype exists (and
what holds it) could not be confirmed: the one search on it returned nothing
relevant. **UNVERIFIED** — the probe counts both.

### 1.2 OTRR's tiers (what an `OTRR_*` item claims to be)

Per search snippets of OTRR item pages (Hallmark, Box 13, Case Dismissed,
Hollywood Spotlight, Suspense):

- **Single Episodes Page** (`*_Singles`): "provided in case you want to
  sample the shows"; "The Certified Set includes extras not found here."
  Despite the name it is the near-complete run as individual files (Suspense
  Singles: "approximately 895" episodes, ~32.2 GB, split per year).
- **Maintained Set**: "all known episodes in the best available audio
  condition with the most accurate dates and titles known to be in general
  circulation"; replaces the older **Certified Accurate** / **Certified
  Complete** labels (pre-2019 items still carry those).
- **Non-Maintained Set**: not through OTRR's maintenance process.
- **Curated Set** (e.g. `OTRR_Curated_Hollywood_Spotlight`): "below the level
  of our Maintained sets but above most of the library".
- Items are tagged with subjects like "OTRR Set", "OTRR Single Episodes" and a
  release code "OTRR - YYYY-MM"; versions are replaced in place ("updated with
  Version 2 files (01-Jan-2020)", Box 13; "Version 3 files (14-May-2011)",
  X Minus One).
- **"In many cases, file names have been modified from the original OTRR
  names to conform to archive.org naming requirements."** So the regexes must
  tolerate underscores-for-spaces, dropped apostrophes and similar.

Use of the tier in ranking: OTRR Maintained/Certified > OTRR Singles > OTRR
Curated > Joe Hehn / Suspense Project style dedicated collections > generic
user uploads. This is a provenance signal for choosing the default copy, the
radio analogue of Decision 040's best-copy score — not a rights signal.

### 1.3 Named series, what the snippets reveal (all NEED MEASUREMENT)

| Series | Item ids seen | Structure as described in snippets |
|---|---|---|
| Suspense | `OTRR_Suspense_Singles` (~32.2 GB, ~895 eps, per-year pages e.g. `OTRR_Suspense_Singles_By_Year_1942`); `OTRR_Certified_Suspense` (2012-12, ~22.4 GB); `TSP420617` (1942-06-17 The Burning Court, VBR MP3); `TSP420902`, `SuspenseTheHitchHiker09021942` (three versions: studio recording, broadcast aircheck...); `Suspense1JHMC`; `SUSPENSE2`; `SUSPENSE_Radio_Digitally_Restored_Collection` | series-set, per-year sets AND one-item-per-episode, all for the same broadcasts: the dedupe case in miniature |
| Lux Radio Theatre | `OTRR_Lux_Radio_Theater_Singles` (Aug 2015, CC BY-NC-ND 4.0, ~31.3 GB); `OTRR_Lux_Radio_Theatre_Season_13_Singles` (2015-08-10, ~1.9 GB); seasons 2-21 on the home page | per-season split; note "Theater" vs "Theatre" in ids |
| X Minus One | `OTRR_X_Minus_One_Singles` (v3 2011-05-14, CC BY-NC-ND 3.0 US); `XMinus1_A` (file `xminusone_550424_NoContact.mp3` 12.7M + .ogg); `XMinus1B`; `xminusone19550424nocontact001` (27.3M, title "X Minus One 1955 04 24 No Contact ( 001)") | 124 eps + pilot per Wikipedia; SFFaudio commenter counts 126 with 12 doubled (Dimension X rebroadcasts) — a same-title-different-date case |
| Dimension X | `OTRR_Dimension_X_Singles` (2006, tagged 1950, 1951); `Dimension-X` (2005, "public domain", per-episode MP3) | the two items disagree on licence |
| The Shadow | `RkoOrsonWelles-TheShadow-RadioRecodings` (33 Welles recordings 1937-38, Blue Coal + Goodrich) | OTRR item not found in this session's searches |
| Gunsmoke | `OTRR_Gunsmoke_Singles`; `OTRR_Certified_Gunsmoke` (2015) | 1952 has partial/missing episodes per OTRR log (e.g. 1952-05-03 Ben Thompson, first 7:43 survives) — a *partial* flag is needed |
| Yours Truly, Johnny Dollar | `OTRR_YoursTrulyJohnnyDollar_Singles` (~5M views per snippet; v2 Jan 2020) | ids are not uniformly underscored (`YoursTrulyJohnnyDollar`) |
| Jack Benny | `OTRR_Jack_Benny_Singles` (season pages 1932-34 ... 1954-55); `JackBenny1` (143 eps, 2.0 GB, "public domain"); `JackBennyProgram481017SorryWrongNumber` (one episode, ~13 MB MP3 + OGG) | the YYMMDD-in-CamelCase id pattern |
| Fibber McGee and Molly | `FibberMcgeeMolly1930s` (63 eps) | OTRR item not found this session |
| The Whistler | `OTRR_Whistler_Singles`; filename `Whistler_xx-xx-xx_epxxx_Kaleidoscope_epAFRTS.mp3` | AFRTS versions marked in the filename |
| Escape | `OTRR_Escape_Singles` (2012-02-14, ~6.5 GB, CC BY-NC-ND 3.0) | |
| Lights Out | none found | Wikipedia: many recordings lost, titles changed often. Search budget ran out |
| Mercury Theatre ("War of the Worlds") | `WarOfTheWorlds1938RadioBroadcast256kbps` (from a Nostr post, UNVERIFIED) | OTRR log lists 1938-10-30 as available; Mercury became Campbell Playhouse 1938-12-09 — one programme, two series names |
| Inner Sanctum | OTRR home page lists "Inner Sanctum Mysteries - Single Episodes" | id not seen |
| Dragnet | none found on archive.org in searches | podcast re-hosts cite OTRR |
| Command Performance | none found on archive.org in searches | AFRS numbering (#1-#400+) is the identity, not dates |
| Ranger Bill (filename example) | `OTRR_Ranger_Bill_Singles`: `Ranger_Bill_54-04-25_ep145_Tony's_Place_aka_Standing_Firm_For_What's_Right` | canonical OTRR pattern with `aka` alternate title |

---

## 2. How episode identity is carried

### 2.1 Filename families (the primary witness)

From the examples above plus the OTRR convention ("uniformly named using the
OTRR program otter", per OTR Daily via search). Regexes are written against
the file's basename with extension removed and `_` normalized to space only
after the first pass (OTRR uses `_` as a field separator).

| Family | Example (real, from snippets) | Fields |
|---|---|---|
| **F1 OTRR** | `Ranger_Bill_54-04-25_ep145_Tony's_Place_aka_Standing_Firm_For_What's_Right`; `Whistler_xx-xx-xx_epxxx_Kaleidoscope_epAFRTS` | series, YY-MM-DD (or xx), epNNN (or xxx), title, optional `aka`, optional version tag (`epAFRTS`) |
| **F2 compact YYMMDD** | `xminusone_550424_NoContact`; ids `TSP420617`, `JackBennyProgram481017SorryWrongNumber` | series, YYMMDD, CamelCase title |
| **F3 full date, spaced** | title "X Minus One 1955 04 24 No Contact ( 001)"; "The Suspense Project: 1942-06-17 The Burning Court" | series, YYYY MM DD, title, (NNN) |
| **F4 US order** | `SuspenseTheHitchHiker09021942`; title "Suspense: The Hitch-Hiker 09-02-1942" | series, title, MM-DD-YYYY |
| **F5 number only** | (common in user sets; e.g. "Dimension X 11 Zero Hour" style — exact spelling UNVERIFIED) | series, NNN, title |
| **F6 none** | anything else | fall back to file `title` tag, then to item title |

Date normalization rules:
- Two-digit years map to 19YY (OTR window 1920-1975). A YY outside the
  series' run (from the series log) demotes the parse to "unconfirmed".
- `aa-bb-cc`: if `aa > 12` it is YY-MM-DD; if `cc > 31` impossible; if
  `aa <= 12` and `cc` within run years, it may be MM-DD-YY — resolve by
  majority order across the item (an item uses one convention).
- `xx` in any field means unknown, never zero.
- A date must be a real calendar day; Feb 30 is a parse failure, logged.

### 2.2 File-level metadata (the secondary witness)

`/metadata/{id}` returns `files[]`; each entry carries `name`, `source`
(`original` | `derivative` | `metadata`), `format`, `size`, `md5`, `crc32`,
`sha1`, `mtime`, and for media often `length` (per the Metadata API docs and
the 2013 IA blog post on video duration fields; that `length` is present on
audio files is **UNVERIFIED** but Archive Watch's `runtime_from_file` already
parses both `HH:MM:SS` and seconds forms). For MP3 originals with ID3 tags,
archive.org commonly exposes `title`, `track`, `album`, `creator`/`artist`,
`genre` per file — **UNVERIFIED**; measured by the probe (`tag_hit_rate`).
Derivatives carry `original: <source filename>`, which is how a VBR MP3 or
Ogg derivative is tied back to its upload.

Formats to expect (archive.org format reference via search): **VBR MP3**,
**Ogg Vorbis** (derivative), **64Kbps MP3** (old derivative: IA stopped
making 64 kb MP3s for new derivatives in 2009 but kept existing ones),
"128Kbps MP3", "Flac", "WAVE", plus non-audio noise: "Spectrogram", "PNG",
"Item Tile", "Metadata", "Archive BitTorrent", "Columbia Peaks" (exact names
**UNVERIFIED**; the probe prints the distribution).

### 2.3 Item-level metadata

`metadata.identifier`, `title`, `creator`, `date`/`year`, `subject` (OTRR
release tags live here), `collection` (list), `description` (HTML, often the
OTRR boilerplate plus a series log), `licenseurl`, `uploader`, `publicdate`,
`addeddate`. Search-side fields: `downloads`, `week`, `month`,
`num_favorites`, `avg_rating`, `num_reviews`, `item_size`, `files_count`
(Archive Watch's `harvest_community_signals.py` reads the first six live).

---

## 3. APIs (what each is for, with what we already know works)

| API | URL | Use | Notes |
|---|---|---|---|
| Scrape | `https://archive.org/services/search/v1/scrape?q=&fields=&sorts=&count=&cursor=` | enumerate every candidate item | cursor paging; `count` minimum 100 per IA help; Archive Watch uses 5,000 in `discover_archive_collections.py`; `total_only=true` for counts; if `identifier` is in `sorts` it must be last; returns `items`, `count`, `total`, `cursor` |
| Advanced Search | `https://archive.org/advancedsearch.php?q=&fl[]=&rows=&output=json` | batched signal reads (`identifier:(a OR b ...)`) | sorted paging capped at 10,000 — use Scrape for enumeration |
| Metadata | `https://archive.org/metadata/{id}` (sub-paths `/metadata`, `/files`, `/reviews`?) | `files[]` (episodes), `metadata`, `reviews[]` | `reviews[]` entries have `reviewtitle`, `reviewbody`, `stars`, `reviewer`, `reviewdate` (Archive Watch's `harvest_reviews.py` + `comment_fit.py` consume these) |
| Download | `https://archive.org/download/{id}/{urlquoted filename}` | the playable URL | 302 to a storage node (`ia8xxxxx.us.archive.org/...`); keep the `/download/` form in the catalog and let the client follow the redirect (Decision 031/034's node pinning and failover apply to audio too). Range requests supported (Decision 029's CORS/Range matrix covers it for the web) |
| Views | `https://be-api.us.archive.org/views/v1/short/{id1},{id2},...` | all-time/30d/7d views | item-level only. A view = play press or file download, once per user per day (archive.org/developers/views.html). **Per-file (per-episode) counts do not exist** — popularity of an episode must come from elsewhere (item views spread over files, reviews mentioning titles, member lists) |
| Member lists | `https://archive.org/services/users/@{user}/lists` | human lists (Decision 041, owner's "no AI lists" rule) | as `harvest_member_lists.py` |
| Full-text search | IA's FTS indexes OCR text; for audio it is of little use, except for scanned scripts, logs and the Joe Hehn collector catalogs | not measured | low priority |

**Etiquette.** IA publishes no fixed quota. Its 2023 post asks bulk users to
"start slowly, and ramp up", to email info@archive.org before a large
project, and, if blocked, to reach out rather than retry; the block page
names Aitratelimit@archive.org. A September 2026 secondary report says
Wayback (not the item APIs) now answers HTTP 429 under bot load. Rules for
our ingest: a descriptive User-Agent (the existing `A.UA`), one metadata
request at a time at <= 1-2 req/s, exponential backoff on 429/5xx, resume
from a checkpoint, and an email to info@archive.org before the first full
harvest.

---

## 4. Ingest algorithm

### 4.1 Data model produced (per episode)

```
Episode {
  seriesKey      "suspense"                       normalized series
  airDate        "1942-06-17" | null              ISO, day precision or null
  airDateQuality "parsed" | "item-majority" | "log-confirmed" | "unknown"
  epNumber       1 | null                         series episode number (OTRR epNNN, AFRS #)
  title          "The Burning Court"
  altTitles      ["..."]                          aka, other uploads' titles
  variant        "AFRS" | "rehearsal" | "aircheck" | "partial" | null
  durationSec    1782
  copies [ Copy{archiveID, file, format, bitrate, sizeBytes, md5, durationSec,
                source(original|derivative), tier, licenseurl, parsedBy(F1..F6)} ]
  defaultCopy    index into copies
}
```

The episode, not the item, is the catalog row. Items become provenance and
"collections" (OTRR set = a shelf from data). This mirrors Archive Watch's
versions picker (`item_aliases`, Decisions 040/143/158): a broadcast has many
copies, one default.

### 4.2 Pseudocode (Python)

```python
SCRAPE = "https://archive.org/services/search/v1/scrape"
META   = "https://archive.org/metadata/"

SEED_QUERIES = [
    'collection:oldtimeradio',
    'collection:radioprograms',
    'identifier:OTRR_*',
    'subject:"old time radio" AND mediatype:audio',
    'subject:"otrr"',
]

def enumerate_items(session):
    seen = set()
    for q in SEED_QUERIES:
        cursor = None
        while True:
            p = {"q": q, "count": 5000,
                 "fields": "identifier,title,mediatype,collection,downloads,"
                           "item_size,files_count,subject,licenseurl,publicdate"}
            if cursor: p["cursor"] = cursor
            data = get_json(session, SCRAPE, p)
            for it in data.get("items", []):
                if it["identifier"] not in seen:
                    seen.add(it["identifier"]); yield it
            cursor = data.get("cursor")
            if not cursor: break
            sleep(0.5)

AUDIO_EXT = (".mp3", ".ogg", ".flac", ".wav", ".m4a", ".opus")
FORMAT_RANK = [  # lower is better; MP3 first because every client (Roku, Tizen 2022) plays it
    lambda f: is_mp3(f) and f["source"] == "original",      # the upload itself; no re-encode loss
    lambda f: f["format"] == "VBR MP3",                       # derivative of a lossless original
    lambda f: is_mp3(f),                                      # 128Kbps / 64Kbps derivatives
    lambda f: f["format"] == "Ogg Vorbis",
    lambda f: f["format"] in ("Flac", "WAVE"),                # too large to stream as default
]

def episodes_of(item_meta):
    files = [f for f in item_meta["files"]
             if f["name"].lower().endswith(AUDIO_EXT)
             and str(f.get("private", "")).lower() != "true"        # archive_lib lesson
             and not re.search(r"(^|/)history/|\.~\d+~$", f["name"])]  # replaced revisions
    by_work = group_by(files, key=lambda f: stem(f.get("original") or f["name"]))
    order = item_date_order(files)          # majority YY-MM-DD vs MM-DD-YY across the item
    for stem_key, group in by_work.items():
        best = min(group, key=lambda f: (rank(f, FORMAT_RANK), -int(f.get("size") or 0)))
        parsed = parse_name(stem_key, order) or parse_tags(best) or parse_item_title(item_meta)
        yield Candidate(series=normalize_series(parsed.series or item_series(item_meta)),
                        date=parsed.date, num=parsed.num, title=parsed.title,
                        variant=parsed.variant, file=best,
                        duration=runtime(best.get("length")),
                        md5=best.get("md5"), parsed_by=parsed.family,
                        archive_id=item_meta["metadata"]["identifier"],
                        licenseurl=item_meta["metadata"].get("licenseurl"),
                        tier=otrr_tier(item_meta))

def dedupe(cands):
    # exact file: same md5 anywhere => same copy (re-uploads of one file)
    # same broadcast: (series, date) equal AND durations agree
    groups = defaultdict(list)
    for c in cands:
        key = (c.series, c.date) if c.date else (c.series, "n", c.num) if c.num \
              else (c.series, "t", norm_title(c.title))
        groups[key].append(c)
    for key, cs in groups.items():
        for cluster in cluster_by_duration(cs, tol=lambda d: max(90, 0.05 * d)):
            # a same-date cluster that splits on duration is TWO things:
            # a partial recording, an AFRS cut, or an East/West repeat
            yield Episode.from_copies(cluster, default=best_copy(cluster))

def best_copy(cluster):
    return min(cluster, key=lambda c: (
        c.variant is not None,          # the broadcast before AFRS/rehearsal cuts
        TIER_ORDER[c.tier],             # OTRR maintained > singles > curated > dedicated > user
        -(c.duration or 0) if c.variant == "partial" else 0,
        -bitrate(c.file)))
```

Rules carried from Archive Watch:
- **Additive, merge-guarded writes** (Decision 020): an ingest run adds and
  updates episodes; it never replaces the episode table with a smaller one,
  and a run that produced nothing goes red (Decisions 093/107).
- **A replaced or private file is never a copy** (`archive_lib.pick_video`'s
  two filters, both reused above).
- **Merged-away keys forward** (Decision 085): when two episode keys are
  later found to be one broadcast, the losing key forwards to the survivor
  so favorites and history do not vanish.
- **Record the evidence** (Decision 084): store `parsedBy`, the raw
  filename, and the md5/duration that justified a merge.
- **Same title is not same broadcast**: X Minus One reran Dimension X scripts;
  Lux, Suspense and Escape reused scripts. The key is the date, never the
  title alone; a title-only key is used only for undated files and is marked
  low confidence.

### 4.3 Regex families (concrete)

```python
YMD2 = r"(?P<yy>\d{2}|xx)-(?P<mm>\d{2}|xx)-(?P<dd>\d{2}|xx)"
F1 = re.compile(rf"^(?P<series>.+?)_{YMD2}_(?:ep)?(?P<num>\d{{1,4}}|x+)_(?P<title>.+?)"
                r"(?:_aka_(?P<aka>.+?))?(?:_ep(?P<variant>AFRTS|AFRS|Rehearsal|Audition))?$", re.I)
F2 = re.compile(r"^(?P<series>[A-Za-z][A-Za-z_ ]*?)[_ -]?(?P<yy>[1-7]\d)(?P<mm>0[1-9]|1[0-2])"
                r"(?P<dd>0[1-9]|[12]\d|3[01])[_ -]?(?P<title>[A-Za-z].*)?$")
F3 = re.compile(r"^(?P<series>.+?)[ _-]+(?P<yyyy>19[2-7]\d)[ ._-](?P<mm>\d{2})[ ._-](?P<dd>\d{2})"
                r"[ _-]*(?P<title>.*?)(?:\(\s*(?P<num>\d{1,4})\s*\))?$")
F4 = re.compile(r"^(?P<head>.+?)[ _-]*(?P<mm>0[1-9]|1[0-2])[-_ ]?(?P<dd>[0-3]\d)"
                r"[-_ ]?(?P<yyyy>19[2-7]\d)$")
F5 = re.compile(r"^(?P<series>.+?)[ _-]+(?:#|ep\.?|no\.?\s*)?(?P<num>\d{1,4})[ _-]+(?P<title>[A-Za-z].+)$", re.I)
```

Order of attempts: F1, F3, F4, F2, F5. F2 is tried late because six digits in
a CamelCase id can be a catalogue number; it requires the YY to fall in the
series' run when a run is known.

---

## 5. Open structural questions (answered by the probe)

1. Share of OTR files that sit in multi-episode items versus one-file items.
2. Hit rate of F1-F5 over all audio files, and over OTRR files alone.
3. Whether `title`/`track`/`album` tags are present on originals, and how
   often they agree with the filename parse.
4. Format distribution, and whether OTRR originals are already MP3 (so no
   VBR derivative exists and the original is what plays).
5. Total hours (sum of `length`) and duplicate rate (md5 collisions; same
   series+date across items).
6. Top series by file count, to pick the first shelves.
7. `mediatype` distribution (audio versus anything else) under each seed.

---

## To measure

### A. One-liners

```bash
# Collection totals (Scrape API total_only)
for q in 'collection:oldtimeradio' 'collection:radioprograms' 'identifier:OTRR_*' \
         'subject:"old time radio"' 'collection:lumedwards' 'mediatype:radio'; do
  printf '%s\t' "$q"
  curl -sG https://archive.org/services/search/v1/scrape \
       --data-urlencode "q=$q" --data-urlencode total_only=true | python3 -c 'import sys,json;print(json.load(sys.stdin).get("total"))'
done

# One OTRR item's file shape
curl -s https://archive.org/metadata/OTRR_Suspense_Singles_By_Year_1942 | \
  python3 -c 'import sys,json;d=json.load(sys.stdin);[print(f.get("format"),f.get("source"),f.get("length"),f.get("title"),f.get("track"),f["name"]) for f in d["files"][:40]]'

# Does a /download/ URL redirect to a storage node and accept Range?
curl -sI -r 0-1023 "https://archive.org/download/TSP420617/" | head -5
```

### B. `tools/probe_otr_corpus.py` (Python 3 stdlib only, save verbatim)

```python
#!/usr/bin/env python3
"""
probe_otr_corpus.py — measure the archive.org old-time-radio corpus for the
radio sister app (docs/research/radio/07-archive-org-ingest.md).

Read-only. Stdlib only. Polite: one request at a time, a pause between
requests, backoff on 429/5xx, resumable cache of metadata responses.

Outputs (in --out, default ./otr_probe):
  items.jsonl     one line per enumerated item (search fields + seed)
  meta/<id>.json  cached /metadata responses (sampled items)
  files.jsonl     one line per audio file with its parse
  report.json     the numbers
  report.txt      the same, readable

Usage:
  python3 tools/probe_otr_corpus.py                    # enumerate all, sample 400 items' metadata
  python3 tools/probe_otr_corpus.py --sample 0         # enumerate + count only
  python3 tools/probe_otr_corpus.py --sample all       # every item's metadata (slow: hours)
  python3 tools/probe_otr_corpus.py --pause 1.5 --out /tmp/otr
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

UA = "ArchiveWatch-OTRProbe/1.0 (https://archivewatch.org; research, read-only)"
SCRAPE = "https://archive.org/services/search/v1/scrape"
META = "https://archive.org/metadata/"

SEEDS = {
    "oldtimeradio": "collection:oldtimeradio",
    "radioprograms": "collection:radioprograms",
    "otrr_ids": "identifier:OTRR_*",
    "subject_otr": 'subject:"old time radio"',
    "subject_otrr": 'subject:"otrr"',
    "lumedwards": "collection:lumedwards",
    "mediatype_radio": "mediatype:radio",
}
FIELDS = ("identifier,title,mediatype,collection,downloads,item_size,"
          "files_count,subject,licenseurl,publicdate,uploader")

AUDIO_EXT = (".mp3", ".ogg", ".flac", ".wav", ".m4a", ".opus", ".aiff", ".wma")

YMD2 = r"(?P<yy>\d{2}|xx)-(?P<mm>\d{2}|xx)-(?P<dd>\d{2}|xx)"
PATTERNS = [
    ("F1_otrr", re.compile(
        rf"^(?P<series>.+?)_{YMD2}_(?:ep)?(?P<num>\d{{1,4}}|x+)_(?P<title>.+?)"
        r"(?:_aka_(?P<aka>.+?))?(?:_ep(?P<variant>AFRTS|AFRS|Rehearsal|Audition))?$", re.I)),
    ("F1b_otrr_spaced", re.compile(
        rf"^(?P<series>.+?)[ _]+{YMD2}[ _]+(?:ep|#)?(?P<num>\d{{1,4}}|x+)?[ _]*(?P<title>.*)$", re.I)),
    ("F3_iso", re.compile(
        r"^(?P<series>.+?)[ _-]+(?P<yyyy>19[2-7]\d)[ ._-](?P<mm>\d{2})[ ._-](?P<dd>\d{2})"
        r"[ _-]*(?P<title>.*?)(?:\(\s*(?P<num>\d{1,4})\s*\))?$")),
    ("F4_us", re.compile(
        r"^(?P<head>.+?)[ _-]*(?P<mm>0[1-9]|1[0-2])[-_ ]?(?P<dd>[0-3]\d)"
        r"[-_ ]?(?P<yyyy>19[2-7]\d)$")),
    ("F2_yymmdd", re.compile(
        r"^(?P<series>[A-Za-z][A-Za-z_ ]*?)[_ -]?(?P<yy>[1-7]\d)(?P<mm>0[1-9]|1[0-2])"
        r"(?P<dd>0[1-9]|[12]\d|3[01])(?:[_ -]?(?P<title>[A-Za-z].*))?$")),
    ("F5_number", re.compile(
        r"^(?P<series>.+?)[ _-]+(?:#|ep\.?|no\.?\s*)?(?P<num>\d{1,4})[ _-]+(?P<title>[A-Za-z].+)$", re.I)),
]


def get_json(url, params=None, *, pause, tries=6):
    if params:
        url = url + "?" + urllib.parse.urlencode(params)
    delay = max(pause, 1.0)
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                data = json.load(r)
            time.sleep(pause)
            return data
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(delay); delay *= 2; continue
            print(f"HTTP {e.code} {url}", file=sys.stderr)
            return None
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as e:
            print(f"retry {attempt}: {e} {url}", file=sys.stderr)
            time.sleep(delay); delay *= 2
    return None


def scrape(q, *, pause, count=5000):
    total = None
    cursor = None
    while True:
        p = {"q": q, "fields": FIELDS, "count": count}
        if cursor:
            p["cursor"] = cursor
        d = get_json(SCRAPE, p, pause=pause)
        if d is None:
            return total
        if total is None:
            total = d.get("total")
        for it in d.get("items", []):
            yield it
        cursor = d.get("cursor")
        if not cursor:
            return total


def seconds(length):
    if length in (None, ""):
        return None
    parts = str(length).split(":")
    try:
        if len(parts) == 3:
            return int(parts[0]) * 3600 + int(parts[1]) * 60 + float(parts[2])
        if len(parts) == 2:
            return int(parts[0]) * 60 + float(parts[1])
        return float(parts[0])
    except ValueError:
        return None


def stem(name):
    base = name.rsplit("/", 1)[-1]
    return re.sub(r"\.[A-Za-z0-9]{2,4}$", "", base)


def valid_date(y, m, d):
    try:
        y, m, d = int(y), int(m), int(d)
    except (TypeError, ValueError):
        return False
    if not (1920 <= y <= 1979 and 1 <= m <= 12 and 1 <= d <= 31):
        return False
    import datetime
    try:
        datetime.date(y, m, d)
        return True
    except ValueError:
        return False


def parse(name):
    s = stem(name)
    for fam, rx in PATTERNS:
        m = rx.match(s)
        if not m:
            continue
        g = m.groupdict()
        yyyy = g.get("yyyy")
        if not yyyy and g.get("yy") and g["yy"].lower() != "xx":
            yyyy = "19" + g["yy"]
        date = None
        if yyyy and g.get("mm") and g.get("dd") and "x" not in (g["mm"] + g["dd"]).lower():
            if valid_date(yyyy, g["mm"], g["dd"]):
                date = f"{yyyy}-{g['mm']}-{g['dd']}"
            elif fam.startswith("F1") and valid_date("19" + g["dd"], g["yy"], g["mm"]):
                date = f"19{g['dd']}-{g['yy']}-{g['mm']}"   # MM-DD-YY written in the YY-MM-DD slot
                fam += "_mdy"
            elif fam in ("F2_yymmdd",):
                continue                                     # six digits that are not a date
        if g.get("head") is not None:          # F4: "Series: Title" or a bare CamelCase run
            head = re.sub(r"[_]+", " ", g["head"]).strip(" -")
            ser, _, ttl = head.partition(":") if ":" in head else ("", "", head)
            g = dict(g, series=ser.strip(), title=ttl.strip())
        series = re.sub(r"[_]+", " ", g.get("series") or "").strip()
        num = g.get("num")
        return {"family": fam, "series": series,
                "date": date, "num": None if not num or "x" in num.lower() else int(num),
                "title": re.sub(r"[_]+", " ", g.get("title") or "").strip() or None,
                "aka": re.sub(r"[_]+", " ", g.get("aka") or "").strip() or None,
                "variant": g.get("variant")}
    return {"family": "F6_none", "series": None, "date": None, "num": None,
            "title": None, "aka": None, "variant": None}


def norm_series(s):
    s = (s or "").lower()
    s = re.sub(r"^(otrr|the)\s+", "", s)
    s = re.sub(r"theatre", "theater", s)
    return re.sub(r"[^a-z0-9]", "", s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="otr_probe")
    ap.add_argument("--sample", default="400", help="items whose metadata to fetch: N, 0 or all")
    ap.add_argument("--pause", type=float, default=1.0, help="seconds between requests")
    ap.add_argument("--seed", type=int, default=17)
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, "meta"), exist_ok=True)

    report = {"seeds": {}, "date": time.strftime("%Y-%m-%d")}
    items = {}
    for key, q in SEEDS.items():
        n = 0
        gen = scrape(q, pause=a.pause)
        try:
            while True:
                it = next(gen)
                n += 1
                rec = items.setdefault(it["identifier"], dict(it, seeds=[]))
                rec["seeds"].append(key)
        except StopIteration as stop:
            total = stop.value
        report["seeds"][key] = {"query": q, "reported_total": total, "read": n}
        print(f"{key:16} total={total} read={n}", file=sys.stderr)

    with open(os.path.join(a.out, "items.jsonl"), "w") as fh:
        for it in items.values():
            fh.write(json.dumps(it) + "\n")

    mt = collections.Counter(str(it.get("mediatype")) for it in items.values())
    report["unique_items"] = len(items)
    report["mediatype"] = dict(mt.most_common())
    report["otrr_items"] = sum(1 for i in items if i.startswith("OTRR_"))
    lic = collections.Counter(str(it.get("licenseurl") or "none") for it in items.values())
    report["licenseurl_top"] = lic.most_common(15)
    fc = [int(it.get("files_count") or 0) for it in items.values() if it.get("files_count")]
    if fc:
        fc.sort()
        report["files_count_per_item"] = {"median": fc[len(fc) // 2], "p90": fc[int(len(fc) * .9)],
                                          "max": fc[-1], "sum": sum(fc)}
    report["item_bytes_sum"] = sum(int(it.get("item_size") or 0) for it in items.values())

    ids = sorted(items)
    if a.sample == "all":
        pick = ids
    else:
        k = int(a.sample)
        random.Random(a.seed).shuffle(ids)
        otrr = [i for i in ids if i.startswith("OTRR_")]
        pick = (otrr[: k // 2] + [i for i in ids if not i.startswith("OTRR_")])[:k] if k else []

    fam = collections.Counter(); fam_otrr = collections.Counter()
    fmt = collections.Counter(); src = collections.Counter()
    tags = collections.Counter(); series_files = collections.Counter()
    per_item_audio = []
    md5s = collections.Counter(); bcast = collections.defaultdict(set)
    secs_total = 0.0; secs_known = 0; audio_files = 0
    with open(os.path.join(a.out, "files.jsonl"), "w") as fh:
        for n, iaid in enumerate(pick, 1):
            path = os.path.join(a.out, "meta", iaid.replace("/", "_") + ".json")
            if os.path.exists(path):
                with open(path) as f:
                    meta = json.load(f)
            else:
                meta = get_json(META + urllib.parse.quote(iaid), pause=a.pause)
                if not meta:
                    continue
                with open(path, "w") as f:
                    json.dump(meta, f)
            if n % 25 == 0:
                print(f"meta {n}/{len(pick)}", file=sys.stderr)
            files = meta.get("files") or []
            for f in files:
                fmt[str(f.get("format"))] += 1
            audio = [f for f in files if (f.get("name") or "").lower().endswith(AUDIO_EXT)
                     and str(f.get("private", "")).lower() != "true"
                     and not re.search(r"(^|/)history/|\.~\d+~$", f.get("name") or "")]
            # one row per WORK: an original plus its derivatives count once
            works = {}
            for f in audio:
                works.setdefault(stem(f.get("original") or f["name"]), []).append(f)
            per_item_audio.append(len(works))
            for wk, group in works.items():
                audio_files += 1
                orig = next((g for g in group if g.get("source") == "original"), group[0])
                src[str(orig.get("source"))] += 1
                p = parse(orig["name"])
                fam[p["family"]] += 1
                if iaid.startswith("OTRR_"):
                    fam_otrr[p["family"]] += 1
                for t in ("title", "track", "album", "creator", "artist", "genre"):
                    if orig.get(t):
                        tags[t] += 1
                s = seconds(orig.get("length"))
                if s:
                    secs_total += s; secs_known += 1
                if orig.get("md5"):
                    md5s[orig["md5"]] += 1
                ser = norm_series(p["series"] or (meta.get("metadata") or {}).get("title"))
                series_files[ser] += 1
                if p["date"]:
                    bcast[(ser, p["date"])].add(iaid)
                fh.write(json.dumps({"id": iaid, "name": orig["name"], "format": orig.get("format"),
                                     "source": orig.get("source"), "length": orig.get("length"),
                                     "size": orig.get("size"), "md5": orig.get("md5"),
                                     "tag_title": orig.get("title"), "tag_track": orig.get("track"),
                                     **p}) + "\n")

    if pick:
        per_item_audio.sort()
        report["sampled_items"] = len(per_item_audio)
        report["audio_works_in_sample"] = audio_files
        report["audio_works_per_item"] = {
            "median": per_item_audio[len(per_item_audio) // 2] if per_item_audio else 0,
            "single_episode_items": sum(1 for x in per_item_audio if x == 1),
            "multi_episode_items": sum(1 for x in per_item_audio if x > 1),
            "max": per_item_audio[-1] if per_item_audio else 0}
        report["filename_family"] = {k: [v, round(v / max(audio_files, 1), 3)] for k, v in fam.most_common()}
        report["filename_family_otrr"] = dict(fam_otrr.most_common())
        report["format_all_files"] = fmt.most_common(30)
        report["audio_source"] = dict(src)
        report["tag_hit_rate"] = {k: round(v / max(audio_files, 1), 3) for k, v in tags.items()}
        report["hours_in_sample"] = round(secs_total / 3600, 1)
        report["length_known_rate"] = round(secs_known / max(audio_files, 1), 3)
        report["md5_duplicates"] = sum(v - 1 for v in md5s.values() if v > 1)
        report["broadcasts_in_several_items"] = sum(1 for v in bcast.values() if len(v) > 1)
        report["distinct_dated_broadcasts"] = len(bcast)
        report["top_series_by_files"] = series_files.most_common(40)
        if a.sample != "all" and report.get("files_count_per_item"):
            report["note"] = ("sample-based numbers; scale by unique_items/sampled_items "
                              "only as a rough estimate")

    with open(os.path.join(a.out, "report.json"), "w") as fh:
        json.dump(report, fh, indent=2)
    with open(os.path.join(a.out, "report.txt"), "w") as fh:
        for k, v in report.items():
            fh.write(f"{k}: {json.dumps(v)}\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
```

What to read in the report:
- `seeds.*.reported_total` — the counts this document could not give.
- `audio_works_per_item.multi_episode_items` vs `single_episode_items` —
  confirms (or refutes) the "episodes are files" premise.
- `filename_family` — if `F6_none` exceeds ~20%, invest in tag-based and
  description-log-based identity before shipping shelves.
- `format_all_files` and `audio_source` — confirms whether OTRR originals are
  MP3 and whether VBR MP3 derivatives exist for them.
- `broadcasts_in_several_items` and `md5_duplicates` — sizes the dedupe.

### C. Further probes

- Reviews on an OTRR set: `curl -s https://archive.org/metadata/OTRR_X_Minus_One_Singles | python3 -c 'import sys,json;r=json.load(sys.stdin).get("reviews",[]);print(len(r));[print(x.get("stars"),x.get("reviewtitle")) for x in r[:10]]'` — reviews are per ITEM, so for a series set they are about the set; check whether reviewers name episodes (a data source for an episode shelf that is not AI-written).
- Views: `curl -s https://be-api.us.archive.org/views/v1/short/OTRR_Suspense_Singles,TSP420617`.
- Whether `mediatype:radio` exists: `curl -sG https://archive.org/services/search/v1/scrape --data-urlencode 'q=mediatype:radio' --data-urlencode total_only=true`.
- Description logs: OTRR descriptions often embed a dated episode list; `curl -s https://archive.org/metadata/OTRR_Escape_Singles/metadata/description` and test whether lines parse as `MM-DD-YY Title` — a third identity witness.
- Searches this session could not run (budget exhausted): OTRR item ids for Inner Sanctum, Lights Out, Dragnet, Fibber McGee, The Shadow, Mercury Theatre; whether `WarOfTheWorlds1938RadioBroadcast256kbps` exists; Joe Hehn Memorial Collection id and size; `librivoxaudio` total.

---

## Sources

Archive.org items and pages (seen via search results only):
- https://archive.org/details/OTRR_Home_Page
- https://archive.org/details/lumedwards
- https://archive.org/details/OTRCatalogs
- https://archive.org/details/OTRR_Suspense_Singles
- https://archive.org/details/OTRR_Suspense_Singles_By_Year_1942
- https://archive.org/details/OTRR_Certified_Suspense
- https://archive.org/details/TSP420617
- https://archive.org/details/TSP420902
- https://archive.org/details/SuspenseTheHitchHiker09021942
- https://archive.org/details/80thAnnivSuspenseMarathon
- https://archive.org/details/Suspense1JHMC
- https://archive.org/details/SUSPENSE2
- https://archive.org/details/SUSPENSE_Radio_Digitally_Restored_Collection
- https://archive.org/details/OTRR_Lux_Radio_Theater_Singles
- https://archive.org/details/OTRR_Lux_Radio_Theatre_Season_13_Singles
- https://archive.org/details/OTRR_X_Minus_One_Singles
- https://archive.org/details/xminusone19550424nocontact001
- https://ia-petabox.archive.org/details/XMinus1_A
- https://archive.org/details/XMinus1B
- https://archive.org/details/OTRR_Dimension_X_Singles/
- https://archive.org/details/Dimension-X
- https://archive.org/details/RkoOrsonWelles-TheShadow-RadioRecodings
- https://archive.org/details/OTRR_Gunsmoke_Singles
- https://archive.org/details/OTRR_Certified_Gunsmoke
- https://archive.org/details/OTRR_YoursTrulyJohnnyDollar_Singles
- https://archive.org/details/JackBenny1
- https://archive.org/details/OTRR_Jack_Benny_Singles
- https://archive.org/download/JackBennyProgram481017SorryWrongNumber
- https://archive.org/details/FibberMcgeeMolly1930s
- https://archive.org/details/OTRR_Escape_Singles
- https://archive.org/details/OTRR_Whistler_Singles
- https://archive.org/details/OTRR_Ranger_Bill_Singles
- https://archive.org/details/OTRR_Line_Up_Singles
- https://archive.org/details/OTRR_CBS_Radio_Workshop_Singles
- https://archive.org/details/OTRR_Academy_Award_Theater_Singles
- https://archive.org/details/OTRR_Hallmark_Single_Episodes
- https://archive.org/details/OTRR_Box_13_Singles
- https://archive.org/details/OTRR_Case_Dismissed_Singles
- https://archive.org/details/OTRR_Curated_Hollywood_Spotlight
- https://archive.org/details/Singles_And_Doubles_Singles_A-C
- https://archive.org/details/Singles_And_Doubles_Singles_O-S
- https://archive.org/details/Singles_And_Doubles_Singles_T-Z/
- https://archive.org/details/tales-of-the-texas-rangers-1952-06-22-83-knock-out
- https://archive.org/details/ClassicRadioShows
- https://archive.org/details/oldtimeyradioshowscollection
- https://archive.org/details/USA-Golden-Age-of-Radio
- https://archive.org/details/UniqueOldTimeRadioEpisodes
- https://archive.org/download/OjosDeOriental30102018 (example of _files.xml/_meta.xml beside mp3/ogg)

Archive.org documentation and blog:
- https://archive.org/help/aboutsearch.htm
- https://doc-tools.readthedocs.io/en/ia-test-gsod/item-search-apis.html
- https://doc-tools.readthedocs.io/en/ia-test-gsod/md-read.html
- https://doc-tools.readthedocs.io/en/ia-test-gsod/md-record.html
- https://archive.org/developers/metadata-schema/index.html
- https://archive.org/developers/views.html
- https://help.archive.org/help/internet-archive-statistics/
- https://help.archive.org/help/files-formats-and-derivatives-file-definitions-2/
- https://blog.archive.org/2009/04/14/audio-and-video-improvements/
- https://blog.archive.org/2013/02/09/files-xml-and-metadata-api-now-showing-video-files-width-height-and-duration/
- https://blog.archive.org/2015/01/26/archive-org-download-counts-of-collections-of-items-updates-and-fixes/
- https://blog.archive.org/2023/05/29/let-us-serve-you-but-dont-bring-us-down/
- https://blog.archive.org/2006/10/24/superman-arrives-in-the-old-time-radio-collection/
- https://blog.archive.org/2009/03/09/kick-back-with-old-time-radio-shows/
- https://github.com/ArchiveLabs/api.archive.org/blob/master/swagger/search.json
- https://hrbrmstr.github.io/wayback/reference/ia_scrape.html
- https://github.com/fuzheado/Internet-Archive-AI-Skills/blob/main/.claude/skills/internet-archive-api/SKILL.md

Other:
- https://otrr.org/pg01b_ms.htm (OTRR mission statement: "many MP3 files are incorrectly named or poorly encoded")
- https://www.otrr.org/FILES/Synopsis_txt/M_Series/Mercury_Theater_Of_The_Air.txt
- https://otrr.org/FILES/Synopsis_txt/G_Series/Gunsmoke.txt
- https://en.wikipedia.org/wiki/X_Minus_One
- https://en.wikipedia.org/wiki/Dimension_X_(radio_program)
- https://en.wikipedia.org/wiki/List_of_Gunsmoke_(radio_series)_episodes
- https://en.wikipedia.org/wiki/List_of_Lux_Radio_Theatre_episodes
- https://en.wikipedia.org/wiki/List_of_Lights_Out_episodes
- https://en.wikipedia.org/wiki/The_Mercury_Theatre_on_the_Air
- https://www.sffaudio.com/dimension-x-and-x-minus-1-otr-available-from-the-internet-archive/
- https://tvcrit.com/sitcom/2016/06/01/lots-of-old-time-radio-are-online
- https://library.missouri.edu/muse/web-tip-of-the-week-jan-18-2016/
- https://rblind.com/post/2421891 (cites archive.org/details/radioprograms)
- https://www.kunalganglani.com/blog/wayback-machine-rate-limiting-mini-wayback.md (secondary, 2026 Wayback 429s)
- https://orsonwelles.indiana.edu/collections/show/3

Archive Watch code this builds on (verified live when written):
`tools/archive_lib.py` (`pick_video` private/history filters, `runtime_from_file`),
`tools/discover_archive_collections.py` (Scrape API, count 5000, cursor),
`tools/harvest_community_signals.py` (advancedsearch signals, be-api views),
`tools/harvest_reviews.py` + `tools/comment_fit.py` (metadata `reviews[]`),
`tools/harvest_member_lists.py` (`/services/users/@{user}/lists`),
`tools/backfill_tv_episodes.py` + `tools/build_canonical_tv.py` (title-search
episode backfill — the pattern NOT to repeat: it applied no rights test, see
SCRATCHPAD's television rights section).
