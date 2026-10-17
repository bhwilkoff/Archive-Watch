# Radio Metadata Sources — the TMDb/TVmaze/Wikidata of old-time radio (2026-10-17)

Research track 03 for the public-domain radio sister app. Mirrors the
evaluation style of `docs/research/metadata-sources.md` and
`docs/research/tv-metadata-sources.md`: role, entities, access, license,
identifiers, quality, then the enrichment cascade.

**Method and its limit.** Direct fetches were blocked in this container;
only WebSearch worked, and the shared per-turn search budget ran out partway
through (so BBC Genome terms, the Chronicling America query shape, the Media
History Digital Library, and Discogs listings could not be searched at all).
Every fact below either cites the URL a search result came from ("per search
snippet") or is marked **UNVERIFIED**. Anything numeric that needs a real
count is in "To measure".

---

## Verdict

1. **There is no TMDb for radio.** No source offers a free, licensed, keyed
   API with episode-level credits. The best episode data (RadioGOLDINdex,
   ~123,000 programs) is an HTML-only database at a university, with no
   published API and no stated reuse license. Its FACTS (dates, titles,
   credits) are not copyrightable (*Feist v. Rural*, 1991), so plan for
   **polite scraping with credit and a link back on every episode, and ask
   Goldin/UMKC for an export in parallel**, not an API key. (Owner question,
   2026-10-17: "If Google can index the Goldin's index, why would we need
   special permission to do so?" — we don't for facts; see §1.1 Access.)
2. **Wikidata is the only open (CC0) graph**, and it is thin below the series
   level: `radio series` (Q14623351) and `radio series episode` classes exist,
   `Suspense` (Q1548940) carries 946 episodes as a number (P1113), but only a
   handful of episodes exist as items. **No Wikidata external-ID property was
   found for RadioGOLDINdex, OTRRpedia, Digital Deli or Haendiges** — the
   identifier chain that carries Archive Watch (IMDb -> TMDb -> Wikidata P724)
   does not exist for radio. IMDb explicitly excludes radio shows.
3. **The natural key is (series, broadcast date)**, not an id. OTR uploads
   already encode it in filenames (`Dimension_X_1950-04-08__01_OuterLimit.mp3`,
   OTRR sets). The pipeline mints its own series id and matches every source
   on `series + date (+ episode number + title)`.
4. **Dates are the hard part and have independent witnesses**: RadioGOLDINdex
   (often from the transcription disc itself), OTRR "certified Accurate" logs,
   Digital Deli Too logs (each date tied to a named newspaper listing), and the
   Library of Congress's newspaper pages (Chronicling America, keyless JSON,
   coverage to 1963). This is the radio analogue of Decision 026: a date is
   kept when the item's own signals and an independent witness agree.
5. **Facts are free, prose and compilations are not.** Air dates, titles and
   cast lists are facts; Digital Deli states "copyright, all rights reserved"
   on every log, OTR Plot Spot's summaries are its own prose, Wikipedia text is
   CC BY-SA. Ingest facts with provenance; never republish someone's log or
   synopsis text without permission. "No AI-written copy" means synopses come
   only from sources that wrote them, with provenance (Decision 124).
6. **Artwork has no poster layer.** The legitimate sources are Wikimedia
   Commons network publicity photos (tagged PD for no notice / not renewed —
   with evidence quality that varies), period magazine scans, sponsor ads, and
   LOC Prints & Photographs. Uploader cover art on archive.org (often a
   vendor's CD art) fails "an uploader's word is not enough". Plan for a
   designed typographic series card as the default, with a photo only where a
   rights-checked one exists.
7. **Scripts are metadata, not content we can show.** Generic Radio Workshop
   is the largest free script library and disclaims ownership; scripts of
   broadcast-only shows may be *unpublished* works with long terms (rights
   track to confirm). Use them for search/credits evidence, not display.

---

## 1. Source-by-source evaluation

### 1.1 RadioGOLDINdex (J. David Goldin) — the episode-level authority

**Role**: the closest thing to an episode database with credits.

- **Where it lives now**: hosted by University of Missouri-Kansas City
  Libraries at `https://radiogoldin.library.umkc.edu/` (contact page lists
  corrections to Contact@RadioGoldindex.com). The old `radiogoldindex.com`
  is superseded; a 2021 blog post says the UMKC hosting "has helped ensure
  it's always up" (greatdetectives.net). Tied to UMKC's Marr Sound Archives,
  which also holds Goldin's own recordings — "nearly 15,000 radio programs on
  lacquer and vinyl transcription discs" broadcast 1930s-1950s (UMKC finding
  aid) — requests at soundarchives@umkc.edu.
- **Coverage**: "over 123,000 radio programs" (UMKC news page, per search
  snippet of library.umkc.edu/goldin-collection/).
- **Entities**: searchable by series title, performer, or date (Adam Graham,
  greatdetectives.net). Entries are known (UNVERIFIED in this session, from
  general OTR knowledge) to carry broadcast date, network/station, sponsor,
  cast, announcer, writer, director, a plot description, and running time,
  plus the source of the recording (disc, AFRS, etc.). Confirm field list by
  probe.
- **Access**: HTML only. No API, no dataset, no license statement found.
  MEASURED 2026-10-17: `radiogoldin.library.umkc.edu/robots.txt` is a 404 (no
  robots file) and the home page states no terms of use. Facts are free to
  take (*Feist*); permission is NOT a legal prerequisite for dates, titles and
  credits. Ask anyway, at the same time as building: an export beats scraping
  an old HTML front end, it is a university server hosting one man's life
  work, and the OTR community is small. Scrape slowly (sequential, cached,
  honest User-Agent), credit Goldin and link each episode to its entry.
- **Identifiers**: UNVERIFIED whether pages carry a stable program id in the
  URL. If they do, it is the best episode id available anywhere; record it.
- **Quality**: Graham "prefer[s] its dates when they conflict with other
  sources" because entries often rest on examination of the transcription
  discs; he also warns "the listings aren't 100 percent accurate and the
  search by artist and search by programs aren't perfectly synced."
- **Use**: primary source for episode credits and the date tie-breaker; its
  plot descriptions are Goldin's prose (copyrightable expression, unlike the
  facts) — permission required before displaying them verbatim.

### 1.2 OTRR (Old Time Radio Researchers) — logs, OTTER, OTRRpedia, certified sets

**Role**: the community's curated, dated, titled episode sets, and the files
most archive.org OTR items are built from.

- **Library**: "over 80,000 episodes in hundreds of series ... to download
  FREE" (otrr.org/pg01b_ms.htm, per snippet). Condition: "the sets are not to
  be sold, and ... passed on exactly as they were prepared."
- **Certification**: a series is certified **Accurate** when "the episodes in
  the series are all correctly dated and titled", and **Complete** when all
  available episodes are included (otrr.org/pg01b_ms.htm). On archive.org the
  glossary also defines a **Maintained** set: "all known episodes in the best
  available audio condition, with the most accurate dates and titles known at
  release" (archive.org/details/OTRR_Certified_Suspense, per snippet).
  Versions since 2019 are named by year+month (`v1906` = June 2019).
- **OTRRpedia**: "a database of many thousands of series with information on
  the stars, number of available episodes, links to other sites and articles"
  (otrr.org, per snippet). Series-level only. Access/API: UNVERIFIED.
- **OTTER**: OTRR's log database tool; its how-to names Jay Hickerson's
  *The Ultimate History of Network Radio Programming and Guide to All
  Circulating Shows* as "the textbook" for compiling a log
  (otrr.org/Files_Reference/HowToCompileASeriesLog.htm). Logs are submitted
  with the original compiler's name (otrr.org/pg02c_direct.htm). Whether the
  OTTER database is downloadable as a file: UNVERIFIED — this is the single
  highest-value question to put to OTRR (a bulk log export would be the radio
  "TVmaze").
- **Naming convention**: observed file name
  `Dimension_X_1950-04-08__01_OuterLimit.mp3` (series, ISO date, episode
  number, title). The classic OTRR pattern `Series yy-mm-dd (ep#) Title.mp3`
  is from memory and **UNVERIFIED**. OTRR's own page warns archive.org file
  names "have been modified from the original OTRR names" to fit archive.org
  rules — so parse both forms.
- **License of the archive.org items**: OTRR items carry
  **Attribution-NonCommercial-NoDerivs** as their usage license (Box 13
  singles page, per snippet). That is a license *claim on the set*, not proof
  of the audio's rights (rights track), and ND matters if we transcode or
  re-tag.
- **ID3 tags**: no documentation of OTRR's tag conventions was found.
  UNVERIFIED (from general knowledge): Title = episode title, Artist/Album =
  series, Year, Comment = OTRR set/version. Measure with the probe below.

### 1.3 Digital Deli Too (digitaldeliftp.com) — newspaper-witnessed logs

- **Pages**: "The Definitive <Series> Radio Log" at
  `http://www.digitaldeliftp.com/DigitalDeliToo/dd2jb-<Series>.html`
  (Hall of Fantasy, Black Mass, Obsession, 2000 Plus, The Falcon, Weird
  Circle, This Is My Best, Calling All Detectives...).
- **Entities**: broadcast date, episode number, title, availability marker,
  and **the newspaper listing that confirmed the broadcast** (e.g. Chicago
  Daily Tribune with time and station), plus cast in the page title, and
  sometimes reprinted period articles (per snippets; greatdetectives.net notes
  it "shows which old newspapers it got information from").
- **License**: each page states copyright The Digital Deli Online, all rights
  reserved. Facts (a date, a title) are not copyrightable, but the log as a
  compilation is theirs: use as a **witness** (record "DD2 cites Chicago Daily
  Tribune 1953-xx-xx"), never mirror pages.
- **Quality caution**: "not as updated as often as it used to be"; reviewer
  warns of uncharitable/political commentary — irrelevant to dates, relevant
  if any prose were ever quoted (it should not be).
- **Identifiers**: none beyond the page slug.

### 1.4 Jerry Haendiges Vintage Radio Logs (otrsite.com)

- `https://otrsite.com/logs/` — "well over 500 Logs of Episodic Listings for
  Several Thousand Old Radio Programs" drawn from his personal collection
  (otrsite.com homepage, per snippet). Catalog numbers for shows he sells;
  "na" = not available. Each log carries a post/modify date (e.g. "February
  23, 05") — useful for staleness.
- Commercial vendor (sells CDs/MP3s); logs are free to read; no license, no
  API, no ids beyond the URL (`loga1031.htm`). Graham: "program logs here that
  are just not available anywhere else."
- **Use**: secondary witness for series with no OTRR/Goldin coverage.

### 1.5 Other logs seen in passing

- **Old Time Radio Program logs** (Frank Passage, Stewart Wright and others) —
  recommended by Graham; some logs dated. URL not confirmed (UNVERIFIED).
- **JJ's Newspaper Radio Logs** `https://www.jjonz.us/RadioLogs/` — "over
  45,000 newspaper radio logs" from the New York Times, Washington Post,
  Chicago Daily Tribune and Los Angeles Times, 1930-1960, searchable by show
  name (per snippet). A ready-made schedule witness; transcriptions of
  copyrighted papers, so facts only.
- **OTR Plot Spot** `https://otrplotspot.com/` — "plot summaries of over 2,200
  episodes from nearly 100 different radio series" (sci-fi, horror, adventure).
  Its own prose: synopsis source **only with permission**, with provenance.
- **Old Time Radio Downloads** (oldtimeradiodownloads.com) — no page from the
  domain came back in search; its structure and terms are **UNVERIFIED**.
  Treat as a downstream re-host of OTRR/archive.org data, not a primary
  source, until a probe shows otherwise.
- **OTRCAT.com** — vendor catalog with episode counts and volume numbers;
  commercial, not a metadata source we should depend on.
- **Radio Preservation Task Force collections directory**
  `https://database.radiopreservation.org/` — a directory of archival radio
  *collections* (not episodes), a static GitHub Pages site maintained by MITH
  (University of Maryland); no API documented. Useful for finding holding
  institutions, not for enrichment.

### 1.6 Wikidata — the open graph (CC0)

**Classes** (verified from wikidata.org pages in search results):
- `radio series` **Q14623351** — "recurring show on radio"; subclass of
  *radio program* and *serial*; "has parts of the class" *radio series
  episode* (Q-id of the episode class not shown in the snippet — measure).
- `radio program` — believed **Q1555508** (the task brief's id; search did not
  confirm the label). UNVERIFIED.
- `Suspense` **Q1548940** — instance of **radio drama series** (a separate
  class; Q-id not shown), country US, English, production company CBS Radio
  Network, 1942-1962, **946 episodes** (P1113), Commons category
  "Suspense (radio series)".
- Episode example: *The House in Cypress Canyon* **Q16746144** — instance of
  *radio series episode*, part of the series Suspense.
- `old-time radio` **Q4353903** — a topic item; only a Freebase id.
- `Category:Lists of radio series episodes` Q8598297 — the Wikipedia
  category of episode-list pages, a crawl seed.

**Properties** to use: P31 instance of, P279 subclass of, P449 original
broadcaster, P580/P582 start/end time, P161 cast member, P1113 number of
episodes (description explicitly covers radio series), P179 part of the
series, P577 publication date, P1545 series ordinal, P155/P156 follows /
followed by, P162 producer, P58 screenwriter, P57 director, P859 sponsor,
P18 image, P373 Commons category, P724 Internet Archive ID (the same bridge
property Archive Watch uses). P449/P161/P179/P1545 on radio items: assumed
from general Wikidata modeling, UNVERIFIED on live data.

**External ids**: a search of wikidata.org for RadioGOLDINdex, OTRRpedia and
Radio Echoes properties found **none** (only Radio France, radio.net,
Audio+ show ID etc.). So: (a) there is no Wikidata chain to a radio database
today; (b) proposing a "RadioGOLDINdex program ID" property is a contribution
the project could make (only once UMKC ids are confirmed stable).

**Coverage**: notable series yes; episodes rarely. Expect series-level
enrichment (description via sitelinked Wikipedia, years, network, Commons
category, image) for the top few hundred series, almost nothing per episode.

SPARQL queries (run at `https://query.wikidata.org/sparql`):

```sparql
# A. Every radio series (any subclass of radio program), with counts
SELECT ?class ?classLabel (COUNT(DISTINCT ?s) AS ?n) WHERE {
  ?class wdt:P279* wd:Q1555508 .            # radio program (verify id)
  ?s wdt:P31 ?class .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?class ?classLabel ORDER BY DESC(?n)
```

```sparql
# B. US radio series with network, years, episode count, IA id, image, enwiki
SELECT ?s ?sLabel ?netLabel ?start ?end ?eps ?ia ?img ?commons ?enwiki WHERE {
  ?s wdt:P31/wdt:P279* wd:Q14623351 .
  ?s wdt:P495 wd:Q30 .
  OPTIONAL { ?s wdt:P449 ?net }
  OPTIONAL { ?s wdt:P580 ?start }  OPTIONAL { ?s wdt:P582 ?end }
  OPTIONAL { ?s wdt:P1113 ?eps }   OPTIONAL { ?s wdt:P724 ?ia }
  OPTIONAL { ?s wdt:P18 ?img }     OPTIONAL { ?s wdt:P373 ?commons }
  OPTIONAL { ?enwiki schema:about ?s ; schema:isPartOf <https://en.wikipedia.org/> }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
```

```sparql
# C. Radio episodes per series (how deep does Wikidata go?)
SELECT ?series ?seriesLabel (COUNT(?ep) AS ?episodes) WHERE {
  ?ep wdt:P31/wdt:P279* ?epClass ; wdt:P179 ?series .
  ?epClass rdfs:label "radio series episode"@en .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} GROUP BY ?series ?seriesLabel ORDER BY DESC(?episodes)
```

```sparql
# D. The bridge: radio items carrying an Internet Archive id
SELECT ?item ?itemLabel ?ia WHERE {
  ?item wdt:P724 ?ia ; wdt:P31/wdt:P279* wd:Q1555508 .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
```

```sparql
# E. Cast of a series (Suspense) — people, for "more with this voice"
SELECT ?p ?pLabel WHERE { wd:Q1548940 wdt:P161 ?p .
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } }
```

### 1.7 Wikipedia — episode-list pages

- **Exist**: `List of X Minus One episodes` (number, title, air date,
  author; includes rebroadcasts), `List of Lux Radio Theatre episodes` (by
  year: first broadcast date, title, stars, notes; 1934-1955). No standalone
  *List of Suspense episodes* came back; the Suspense article says
  "approximately 945 episodes were broadcast ... more than 900 still exist".
  Escape: not searched (budget). Seed more via Q8598297.
- **License**: text CC BY-SA. Tables of dates/titles are facts; a synopsis
  column is prose (attribution + share-alike if displayed). Prefer the
  Wikipedia lead paragraph as a *series* synopsis with provenance, as Archive
  Watch does for films (Decision 124).
- **Access**: MediaWiki API / Parsoid HTML; tables need per-page parsing (the
  same "messy, last resort" grade tv-metadata-sources.md gave it).

### 1.8 IMDb — out

IMDb's title eligibility table lists **"Radio shows (unless released as a
podcast)" as ineligible** (help.imdb.com title-eligibility). OTR appears only
as modern podcast compilations (e.g. *The Great Detectives of Old Time
Radio*, tt7661656, a Podcast Series). No IMDb or TMDb layer exists for radio;
both are useful only for **people** (an actor's IMDb/Wikidata id for photos
and cross-links to Archive Watch films).

### 1.9 MusicBrainz — a convention, not a dataset

MusicBrainz has a style guideline for broadcast programs covering
"reissues or collections of recordings originally created for broadcast";
release-group type **Broadcast**, secondary types **Audio Drama** /
**Spokenword** / **Live** (wiki.musicbrainz.org, per snippet; older mirror).
Its talk page cites the OTRR database as the useful reference and notes most
radio shows "did not have an 'official' release". Coverage of OTR in MB is
UNVERIFIED and expected sparse. Data is CC0 (core) — fine if present. Value:
a schema precedent (series / episode number / title over performers) and
MBIDs for commercial CD reissues, which also flag rights risk.

### 1.10 Discogs — transcription discs

No Discogs page came back (budget). Context found instead: AFRS distributed
programs on 16-inch electrical transcription discs, 1942-1960s, produced
"under special licensing agreements ... the music would never be sold or
played on commercial airwaves" (army.mil). AFRS numbers (e.g. "AFRS Jubilee"
numbered programs, UNT catalog) are a second episode-numbering system that
must not be confused with the network episode number. Discogs data is CC0
(general knowledge, UNVERIFIED here); value is disc labels/matrix numbers as
date evidence for a few series. Low priority.

### 1.11 Library of Congress — Chronicling America and SONIC

- **Chronicling America** (newspaper pages): searchable by keyword, date
  range, state and title; coverage "late 1700s through 1963"; the loc.gov site
  returns JSON with no key, and the legacy `chroniclingamerica.loc.gov` host is
  deprecated in favor of loc.gov (per snippets of API directories; exact
  parameters UNVERIFIED — see probe). OCR quality varies. This is how the app
  can answer **"what aired tonight in 1942"**: find the radio column on a
  given date and match series names. Coverage of big-city dailies in the
  1930s-50s is thin (Chronicling America favors smaller papers whose rights
  are clear) — measure.
- **SONIC** (Sound Online Inventory and Catalog): LOC's catalog of its
  recorded-sound holdings, with a radio-broadcast search screen; NBC
  Collection ~150,000 16-inch lacquer discs 1930s-1980s; in 2006 "only the
  re-formatted NBC discs are in Sonic"; listening in-house only (ARSCLIST 2006;
  loc.gov collection overview PDF). A date/existence witness for NBC
  programs, not an API.

### 1.12 BBC Genome — context, not content

Every Radio Times 1923-2009 scanned and OCR'd into listings: title, time,
synopsis, contributors; "each broadcast has its own page with a unique,
stable identifier"; succeeded by the BBC Programme Index (~10 million
listings) (thenextweb 2014, BSHS, Staffordshire libguide). BBC radio audio is
not public domain, so Genome matters only for (a) US shows rebroadcast on the
BBC and (b) a model of what a listings database looks like. Terms/API: not
found (budget) — UNVERIFIED; do not scrape without reading them.

### 1.13 WorldRadioHistory.com — magazines, schedules, photos

Scans of *Radio Guide* (weekly Oct 1931-Feb 1943, then monthly to Nov 1943),
*Radio Mirror* (monthly from Nov 1933, retitled several times, to 1977),
*Broadcasting* (1931-2001), *What's On The Air* (1929) and many more, as PDFs
(worldradiohistory.com master pages). Content: weekly schedules, program
photos, sponsor ads. Rights: the site's terms were not found; LOC's blog notes
that about a million pages of public-domain media periodicals such as *Radio
and TV Mirror* were digitized via the Media History Digital Library
(blogs.loc.gov 2014). Per-issue status = the magazine's notice + renewal
(1931-63 needs a renewal check, Decision 157 method). Schedules here are a
date witness; photos are art candidates only after that check.

### 1.14 John Dunning, *On the Air* (Oxford UP, 1998)

~1,500 shows, 822 pp., alphabetical; each entry: broadcast history (time
slot, network, sponsors), cast, announcers, producers, directors, writers,
sound-effects people, theme (library catalog / publisher blurbs). Copyrighted
book: a **human reference** for editors resolving conflicts, never ingested.
Also Hickerson's *Ultimate History ... Guide to All Circulating Shows* (3rd
rev. ed., OCLC 186968159; "over 6,000 network shows" per OTRR) — same role.

### 1.15 Internet Archive item metadata — the base layer

- Collections: `oldtimeradio` (the umbrella; RSS
  `archive.org/services/collection-rss.php?collection=oldtimeradio`), OTRR
  items with prefixes `OTRR_Certified_`, `OTRR_Maintained_`, `OTRR_Curated_`,
  `OTRR_..._Singles`, and "Singles and Doubles" for series with one or two
  known episodes.
- Fields seen on OTRR items: publication date (often the set date, e.g.
  2020-01-01, **not** the broadcast date), usage license (BY-NC-ND), and
  `subject` topics carrying genre, cast, producers, decade and OTRR set name.
- Title/filename conventions to parse: `Series YYYY-MM-DD Title`,
  `Series_YYYY-MM-DD__NN_Title.mp3`, `Series yy-mm-dd (NN) Title.mp3`
  (UNVERIFIED), plus junk uploads with no date. Like Archive Watch's
  `external-identifier`, the filename **is** the identifier chain here.
- Known trap: one archive.org item holds a whole series (hundreds of files);
  the episode, not the item, is the catalog unit. `date`/`year` on the item
  describe the upload or set, not the episodes.

### 1.16 ID3 tags inside the MP3s

The only metadata that travels with the file. No OTRR spec found. Read
TIT2/TPE1/TALB/TYER/TDRC/COMM/TRCK from the first bytes over HTTP Range (no
full download) and treat them as another self-signal to cross-check the
filename, never as authority.

---

## 2. Artwork — there are no posters

| Source | What | Rights assessment |
|---|---|---|
| Wikimedia Commons publicity photos | NBC/CBS/Mutual press photos of stars and casts (e.g. File:Connee_Boswell_1941.JPG, Cliff_Arquette_1941.JPG, Eddie_anderson_1947.JPG, Rod_Serling_photo_portrait_1959.JPG) | Tagged "published 1929/1923-1977 without notice" or `PD-US-not renewed` (1931-1963). Good files show the print's back and the press-release stamp. Commons editors themselves note many "no notice" tags have no evidence and that a claim needs "a reliable and verifiable external source". Some CBS files note permission was "for editorial uses only" (a usage restriction, not copyright, but flag). US-only PD (rule of the shorter term warning). **Accept only files whose page shows the evidence; record the template and evidence URL.** |
| Commons `PD-US-no notice advertisement` | Sponsor ads in periodicals 1931-1977 lacking an ad-specific notice | A named Commons template; the ad is judged separately from the magazine. Good for series art (Lux soap ads for Lux Radio Theatre). Same evidence bar. |
| WorldRadioHistory magazine scans | Covers, program photos, schedules, ads | Per issue: notice + renewal. Pre-1931 issues PD by age (Decision 137 calendar rule); 1931-63 need a renewal check. Site terms UNVERIFIED. |
| LOC Prints & Photographs | Press photos, studios, performers | Per-item rights statement on loc.gov ("no known restrictions" vs restricted); keyless JSON (`?fo=json`). Same as Archive Watch's LoC layer. |
| archive.org item images | Uploader thumbnails, often vendor CD art or OTRR set art | Uploader's word only — **reject by default** (Decision 140 spirit). OTRR set art falls under the set's BY-NC-ND claim. |
| Wikidata P18 / P373 | Series/person image and Commons category | Leads to Commons; same evidence bar applies. |

Default art: a designed card from data (series name, years, network, category
color) — no AI imagery. A person photo (the star) is the second-best series
art and the most available.

---

## 3. Transcripts and scripts as metadata

- **Generic Radio Workshop** `https://genericradio.com/` — "the original and
  largest collection of radio scripts and transcripts from the Golden Age of
  Radio available on the Internet"; it "makes no claims to ownership ... rights
  remain with the original copyright holders"; still adding scripts (late
  August 2026 additions). Also sells RadioKits. Use: credits/title evidence and
  full-text search **indexes** (search a script, land on the episode), not
  display — the site itself disclaims rights.
- **Scripts' rights**: a broadcast is generally not "publication" under US
  law, so a never-printed script may be an unpublished work with a long term.
  This is a legal question for the rights track (02), UNVERIFIED here.
- **McFarland, *Radio Series Scripts, 1930-2001*** — a catalog of where
  surviving scripts are held (mcfarlandbooks.com); editor reference.
- **ASR**: archive.org has experimented with Whisper on 78rpm records
  (ebookfriendly.com, undated); Middlebury transcribed 423 historic radio
  recordings with Whisper (~10 min per hour of audio). Archive Watch dropped
  archive.org auto-ASR captions for quality (Decision 043) and abandoned CI
  Whisper (Decision 039b) — so generated transcripts are a captions/search
  feature to research on its own, never a metadata source and never shown as
  synopsis (no AI copy).

---

## 4. Recommended enrichment cascade

Archive Watch's chain (Decision 008) starts from an id the item already
carries. Radio has none, so the chain starts from a **parsed natural key**.

```
1. archive.org item + files[]                    (base, every episode)
   ├─ per audio file: parse filename -> {series, date, epNo, title}
   ├─ ID3 (Range read)           -> second self-signal
   ├─ item title/subject/collection (OTRR set name, cast tags)
   └─ duration from files[].length
   => candidate key K = (seriesKey, broadcastDate[, epNo])

2. Series identity  (mint our own seriesID; aliases table)
   ├─ Wikidata: label/alias match within radio-program subclasses,
   │   checked by years (P580/P582) and network (P449) -> QID
   │   └─ QID -> enwiki lead (series synopsis, provenance), P373, P18,
   │            P1113 (expected episode count), P161 (cast)
   └─ OTRRpedia series record (stars, episode count) [access TBD]

3. Episode facts  (each source a witness, keyed by K)
   ├─ RadioGOLDINdex  -> cast, writer, director, announcer, sponsor,
   │                     network, runtime, disc source  [permission]
   ├─ OTRR log (OTTER) -> certified date + title           [ask for export]
   ├─ Wikipedia episode list -> date, title, stars/author
   ├─ Digital Deli Too -> date + named newspaper citation  [facts only]
   └─ Haendiges log    -> date + title (staleness = log's modify date)

4. Independent date witness
   └─ Chronicling America / JJ's logs / WorldRadioHistory schedules:
      series name present in that day's radio column

5. Art: Commons (P18 / P373 / category search, evidence-checked)
      -> LOC P&P -> magazine scan (renewal-checked) -> data-drawn card
```

**Matching keys.** Series by normalized title + alias table (Suspense /
"Suspense!", Lux Radio Theatre / Lux Radio Theater, AFRS retitles). Episode by
**(seriesID, broadcastDate)** first; then episode number; then title fuzzy
match as a confirmer, never alone (anthologies reuse titles: Suspense redid
"Sorry, Wrong Number" many times). Date variants are real and must be modeled,
not collapsed: East/West Coast repeats the same night, rehearsal recordings,
AFRS rebroadcasts with their own numbers and later dates, and syndicated
transcriptions with no single air date. Store `airDate`, `airDatePrecision`
(day/month/year/unknown), `airingVariant`, and `dateWitnesses[]`.

**Verification against the item's own signals (Decision 026 for radio).**
- A source's date is kept when it agrees with the filename/ID3 date or, when
  the file has none, with **two** independent witnesses (Goldin + a newspaper
  column, or OTRR certified + DD2).
- Runtime sanity: a 30-minute slot yields ~25-30 min; a 60-minute Lux episode
  under 40 min is a fragment or a different program.
- A match that conflicts with the item (wrong decade for the series' run per
  Wikidata P580/P582, a cast list naming someone who never worked the series)
  is cleared, and what it filled is scrubbed (Decision 150).
- Provenance on every field (`dateSource`, `castSource`, `synopsisSource`),
  as Decision 124 requires for synopses.
- Prefer Goldin on date conflicts (Graham), but record the disagreement; a
  date only one compilation asserts is "unverified" in the data, not hidden.

**What not to build**: no AI-written synopses or shelves; no mirrored log
pages; no IMDb/TMDb dependency; no reliance on archive.org's item-level `date`
as a broadcast date.

---

## 5. Open questions for the owner / outreach

1. Write to J. David Goldin and UMKC Marr Sound Archives: may we index
   RadioGOLDINdex facts (and display plot descriptions with credit)? Is there
   an export?
2. Write to OTRR: is the OTTER log database available as a file, and what do
   they want in attribution? How do they read their NC-ND on a free app?
3. Propose a Wikidata "RadioGOLDINdex program ID" property once ids are
   confirmed stable — contributes the missing chain back to the commons.

---

## To measure (for a session with network access)

```bash
# RadioGOLDINdex: page shape, ids in URLs, fields, robots/terms
curl -sI https://radiogoldin.library.umkc.edu/
curl -s  https://radiogoldin.library.umkc.edu/robots.txt
curl -s  'https://radiogoldin.library.umkc.edu/' | grep -oE 'href="[^"]+"' | sort -u | head -50
# then open one Suspense program page and list its labeled fields

# archive.org: how many OTR items, which OTRR prefixes, filename patterns
curl -s 'https://archive.org/advancedsearch.php?q=collection%3Aoldtimeradio&fl%5B%5D=identifier&rows=0&output=json' | python3 -c 'import sys,json;print(json.load(sys.stdin)["response"]["numFound"])'
curl -s 'https://archive.org/advancedsearch.php?q=identifier%3AOTRR_*&fl%5B%5D=identifier&rows=2000&output=json' > otrr_ids.json
curl -s https://archive.org/metadata/OTRR_Certified_Suspense | python3 -c '
import sys,json,re,collections
d=json.load(sys.stdin); c=collections.Counter()
for f in d["files"]:
  n=f["name"]
  if n.endswith(".mp3"):
    c["iso" if re.search(r"\d{4}-\d{2}-\d{2}",n) else "yy" if re.search(r"\b\d{2}-\d{2}-\d{2}\b",n) else "none"]+=1
print(d["metadata"].get("licenseurl"), d["metadata"].get("subject")); print(c)'

# ID3 of one OTRR file without downloading it (first 64 KB)
curl -s -r 0-65535 -L 'https://archive.org/download/OTRR_Certified_Suspense/<file>.mp3' -o head.mp3 && python3 -m mutagen.easyid3 head.mp3 2>/dev/null || ffprobe -hide_banner head.mp3

# Wikidata: confirm class ids, then run queries A-E above
curl -s 'https://www.wikidata.org/wiki/Special:EntityData/Q1555508.json' | python3 -c 'import sys,json;e=list(json.load(sys.stdin)["entities"].values())[0];print(e["labels"]["en"]["value"])'
curl -s 'https://www.wikidata.org/w/api.php?action=wbsearchentities&search=radio%20series%20episode&language=en&format=json'
curl -s 'https://www.wikidata.org/w/api.php?action=wbsearchentities&search=radio%20drama%20series&language=en&format=json'
curl -s 'https://www.wikidata.org/w/api.php?action=query&list=search&srnamespace=120&srsearch=radio%20program%20ID&format=json'   # any OTR external-id properties

# Chronicling America via loc.gov: a radio column on a date
curl -s 'https://www.loc.gov/collections/chronicling-america/?q=%22radio+programs%22+suspense&dates=1943-01-01/1943-12-31&fo=json&c=50' | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["pagination"]);[print(r.get("date"),r.get("partof_title") or r.get("title"),r.get("url")) for r in d["results"][:20]]'
# measure: how many 1935-1955 pages mention "WABC" or "WEAF" (network flagships) per year

# Wikipedia episode lists: enumerate and test table parse
curl -s 'https://en.wikipedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Lists_of_radio_series_episodes&cmlimit=500&format=json'
curl -s 'https://en.wikipedia.org/api/rest_v1/page/html/List_of_X_Minus_One_episodes' | grep -c '<tr'

# MusicBrainz: any Broadcast + Audio Drama release groups for OTR
curl -s -A 'ArchiveWatchResearch/0.1 (ben@learningischange.com)' 'https://musicbrainz.org/ws/2/release-group?query=secondarytype:%22audio%20drama%22%20AND%20primarytype:broadcast&fmt=json&limit=5'

# Commons: count radio publicity photos and their license templates
curl -s 'https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Suspense_(radio_series)&cmlimit=500&format=json'
curl -s 'https://commons.wikimedia.org/w/api.php?action=query&list=embeddedin&eititle=Template:PD-US-no_notice&eilimit=1&format=json'

# Pages whose terms must be read before any use
for u in https://www.digitaldeliftp.com/ https://otrsite.com/ https://worldradiohistory.com/ \
         https://genome.ch.bbc.co.uk/ https://www.otrr.org/ https://www.oldtimeradiodownloads.com/ \
         https://www.jjonz.us/RadioLogs/ https://otrplotspot.com/; do curl -sI "$u" | head -1; curl -s "${u}robots.txt" | head -5; done
```

Searches that could not be run (budget exhausted) and should be next:
BBC Genome / Programme Index reuse terms; loc.gov newspaper API parameters;
Media History Digital Library (Lantern) radio holdings; Discogs AFRS/
transcription listings; Old Time Radio Downloads site structure; Wikipedia
lists for Escape and Suspense; Commons `Template:PD-US-no_notice` page text;
OTRR ID3 conventions; whether RadioGOLDINdex URLs carry stable ids.

---

## Sources

- https://library.umkc.edu/goldin-collection/
- https://radiogoldin.library.umkc.edu/Home/Contact
- https://finding-aids.library.umkc.edu/repositories/2/resources/320
- https://finding-aids.library.umkc.edu/agents/people/73
- https://www.greatdetectives.net/detectives/my-favorite-old-radio-research-resources/
- https://www.greatdetectives.net/detectives/gold-standard-radio-research/
- https://otrsite.com/
- https://otrsite.com/logs/loga1031.htm
- https://www.otrsite.com/articles/art1004.html
- http://www.digitaldeliftp.com/DigitalDeliToo/dd2jb-Hall-of-Fantasy.html
- http://www.digitaldeliftp.com/DigitalDeliToo/dd2jb-Black-Mass.html
- http://www.digitaldeliftp.com/DigitalDeliToo/dd2jb-Adv-of-The-Falcon.html
- http://www.digitaldeliftp.com/DigitalDeliToo/dd2jb-2000-Plus.html
- https://www.otrr.org/pg01b_ms.htm
- https://otrr.org/Files_Reference/HowToCompileASeriesLog.htm
- https://otrr.org/pg02c_direct.htm
- https://archive.org/details/OTRR_Certified_Suspense
- https://archive.org/details/OTRR_Dimension_X_Singles
- https://archive.org/details/OTRR_Box_13_Singles
- https://archive.org/details/OTRR_Singles_And_Doubles_vol_2_Singles
- https://archive.org/services/collection-rss.php?collection=oldtimeradio
- https://www.jjonz.us/RadioLogs/
- https://otrplotspot.com/
- https://database.radiopreservation.org/about/
- https://www.wikidata.org/wiki/Q14623351
- https://www.wikidata.org/wiki/Q1548940
- https://www.wikidata.org/wiki/Q16746144
- https://www.wikidata.org/wiki/Q4353903
- https://www.wikidata.org/wiki/Q8598297
- https://m.wikidata.org/wiki/Property:P1113
- https://en.wikipedia.org/wiki/List_of_X_Minus_One_episodes
- https://en.wikipedia.org/wiki/List_of_Lux_Radio_Theatre_episodes
- https://en.wikipedia.org/wiki/Suspense_(radio_drama)
- https://help.imdb.com/article/contribution/titles/title-eligibility/G9V8J6AXTQ292S5W
- https://www.imdb.com/title/tt7661656/reference
- https://wiki.musicbrainz.org/podcast
- https://wiki.musicbrainz.org/Talk:Podcast
- https://www.army.mil/article/70660/Lost_vinyl_collection_returned_to_AFN_home
- https://discover.library.unt.edu/catalog/b4270540
- https://publicapis.io/chronicling-america-api
- https://cool.culturalheritage.org/byform/mailing-lists/arsclist/2006/11/msg00118.html
- https://loc.gov/acq/devpol/colloverviews/sound.pdf
- https://www.thenextweb.com/news/bbc-debuts-genome-database-covering-radio-times-listings-1923-2009
- https://bshs.org.uk/using-the-bbc-genome-project-for-cultural-history/
- https://libguides.staffs.ac.uk/az/bbc-radio-times-1923-2009-genome-project
- https://www.worldradiohistory.com/Radio_Guide_Master_Page.htm
- https://worldradiohistory.com/Mirror-Page-Range-Guide.htm
- https://blogs.loc.gov/now-see-hear/2014/06/audio-archaeology/
- https://catalog.nypl.org/search/i9780195076783
- https://search.worldcat.org/oclc/186968159
- https://commons.wikimedia.org/wiki/Template:PD-US-not_renewed
- https://commons.wikimedia.org/wiki/Template:PD-US-no_notice_advertisement
- https://commons.wikimedia.org/wiki/File:Bergman_Notorious_Publicity_Photo.jpg
- https://commons.wikimedia.org/wiki/Commons:Village_pump/Copyright/Archive/2011/12
- https://c.enwp.org/wiki/File:Connee_Boswell_1941.JPG
- https://c.enwp.org/wiki/File:Cliff_Arquette_1941.JPG
- https://c.enwp.org/wiki/File:Rod_Serling_photo_portrait_1959.JPG
- https://genericradio.com/
- https://mcfarlandbooks.com/?p=16579
- https://ebookfriendly.com/internet-archive-ai-extract-words-from-100-year-old-records/
- https://www.middlebury.edu/library/node/1689

---

## Addendum: RadioEchoes as the spine (owner question, 2026-10-17)

Owner: *"Can we use radioechoes as the spine and archive.org as the content
source?"* **Yes — as the series-and-episode list (TVmaze's role in Decision 016),
not as the only witness for dates, and never as the audio source.** Measured from
this container on 2026-10-17 (browser User-Agent; the default curl agent gets
403):

| Fact | Value | How |
|---|---|---|
| Series | **5,069**, each tagged with one of 21 genres (Variety 1,546, Drama 818, Comedy 708, Miscellaneous 357, Detective 339, Historical 167, Quiz 155, Thriller 148, Adventure 132, Soap 103, News 103, SciFi 98, Mystery 63, Sports 62, Western 60, Kids 60, WW2 43, Religion 43, Talk 40, Patriotic 14, Espanol 10) | links on `?page=series_all` |
| One series page | Suspense: **917** episodes, 1940-1962, each with title, "Original Broadcast Date" (YYYY.MM.DD), length (mm:ss), file name and size; the 1940 "Forecast" audition is included | `?page=series&genre=OTR-Thriller&series=Suspense` |
| What it lacks | No cast, writer, director, network, sponsor or description; no episode numbers; no stable id other than series name + file name | same page |
| Where its audio lives | Its own S3 bucket (`s3.amazonaws.com/RE-Warehouse/s/suspense_1942-06-17_the_burning_court.mp3`) — its bandwidth, not ours | `?page=play_download&mode=play...` |
| Terms | robots.txt: `Disallow:` (nothing blocked except admin paths) with `Crawl-delay: 10`; the FAQ and footer state no terms or license; no API | `/robots.txt`, `?page=faqs` |

**Why it fits the spine.** It is the one source that is (a) organized as series
→ dated episodes, (b) large (5,069 series against OTRR's library of ~80,000
episodes), (c) machine-readable without an API (one page per series, stable
`dl_file` names of the form `series_YYYY-MM-DD_title.mp3`, the same key archive.org
filenames carry), and (d) categorized by people rather than by a model, which
satisfies "no AI-written lists". Its genre tags can seed the browse taxonomy.
It lists what SURVIVES, not what aired, which is the right population for a
playable catalog and makes gaps against a log visible.

**What it must not be.**
- **Not the only date witness.** It repeats collectors' file dates (Suspense lists
  "The Burning Court" on both 1942-06-17 and 1945-06-14 — correct, it was
  re-performed, but the same shape is how a mis-dated copy would look). Cross-check
  against OTRR logs and RadioGOLDINdex as independent witnesses (Decision 026);
  record each date's source (Decision 124).
- **Not the audio source.** Playing its S3 files would put our listeners on its
  bill and its uptime. archive.org is the content source; a RadioEchoes episode
  with no archive.org match is a "wants" entry (Decision 032's pattern), not a
  playable row.
- **Not a rights finding.** Being listed there says nothing about rights; the
  audit (`02-rights.md` §10) runs on every episode regardless.

**Method.** Scrape `series_all`, then each series page at the stated 10-second
crawl delay (5,069 pages ≈ 14 hours — one CI run in the 360-minute job cap needs
sharding across ~3 jobs, or a resumable cursor; thereafter only `?page=recent`).
Parse each episode to `(series, date, title, length_s, re_file)`; match to
archive.org files on normalized series + date; length only flags a partial copy,
never blocks a match (`07-archive-org-ingest.md`: independent uploads of one
Suspense date differ by 33-43 s at the median and up to 357 s). Facts are free to take
(*Feist*); credit RadioEchoes and write to support@radioechoes.com in parallel
asking for an export — they invite collection contributions in their FAQ, so a
data partnership is a natural ask.
