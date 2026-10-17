# Radio app research 01: content repositories for old-time radio and radio drama

*2026-10-17. Track: content repositories. Written for the session that will build the
public-domain audio sister app to Archive Watch.*

**How this was researched, and what that means for trust.** The container's network
policy blocked direct fetches of archive.org, otrr.org, librivox.org, loc.gov and the
rest, so every outside fact below comes from **web-search result snippets**. The shared
search budget (200 calls per turn across all research agents) ran out partway through
this track. So several sources have no search evidence this session (Paley Center,
Smithsonian, LAC/CBC, oldtimeradiodownloads.com, the National Recording Registry, the
LOC's OWI collection online status). They are listed with what is known from prior
knowledge and are marked **UNVERIFIED**. Every number is labeled with where it came from.
The "To measure" section has the probes that turn these into measurements.

**Update, same day: network access opened.** The claims below marked **MEASURED
2026-10-17** were checked directly with curl. §0 lists them with the exact command
used. Where a measurement contradicts a search snippet, the measurement wins and the
section text has been corrected.

---

## 0. Measured 2026-10-17 (curl from this container)

| # | Fact | Value | Command |
|---|---|---|---|
| M1 | Items in `collection:oldtimeradio` | **8,952** (8,808 `mediatype:audio`) | `curl -s -G https://archive.org/advancedsearch.php --data-urlencode 'q=collection:oldtimeradio' -d rows=0 -d output=json \| jq .response.numFound` |
| M2 | OTRR items (`identifier:OTRR_*`) | **526** | same, `q=identifier:OTRR_*` |
| M3 | Old Time Radio Researchers Collection (`collection:lumedwards`) | **692** items (the search snippet's "676" was stale) | same, `q=collection:lumedwards` |
| M4 | archive.org items with subject "old time radio" | **7,895** | same, `q=subject:"old time radio"` |
| M5 | LibriVox audio on archive.org (`collection:librivoxaudio`) | **21,891** items | same |
| M6 | OTRR tier labels inside `oldtimeradio` (description phrase match) | "Certified Accurate" 83, "Certified Complete" 63, "Maintained Set" 33 | same, `q=collection:oldtimeradio AND description:"Maintained Set"` etc. |
| M7 | `oldtimeradio` items carrying any `licenseurl` | **2,316 of 8,952**. Top values: CC publicdomain (retired tool) 916, PD Mark 1.0 411, **CC BY-NC-ND (2.5/3.0/4.0, all variants) ≥711**, CC0 121 | `... -d 'fl[]=licenseurl' -d rows=3000` and tally |
| M8 | `oldtimeradio` items by item `year` field | **7,276 of 8,952 have no year.** Of those dated: 1930s 34, 1940s 148, 1950s 137, 1960s 79, 1970s 116, 2000s 133, 2010s 514, 2020s 477. The post-2000 values are upload years | `... -d 'fl[]=year' -d rows=10000` and tally by decade |
| M9 | LibriVox drama, by API genre | "Dramatic Readings" 266, "Plays" 271, `^Drama` 394; **640 distinct projects** in the union. Languages: English 574, German 27, Spanish 10, Multilingual 10, Italian 6, French 5 | `curl -s 'https://librivox.org/api/feed/audiobooks?genre=Plays&format=json&limit=500&offset=0&fields[]=id'`, paged by offset and unioned by id |
| M10 | LibriVox API limit | **`limit` can no longer exceed 500** (went live about 2026-09-26). Larger requests return "Too many records requested." Page with `offset`, with a delay between requests | `curl -s https://librivox.org/api/info` |
| M11 | LibriVox record keys (`extended=1`) | `id, title, description, url_text_source, language, copyright_year, num_sections, url_rss, url_zip_file, url_project, url_librivox, url_other, totaltime, totaltimesecs, authors, url_iarchive, sections, genres, translators`. Section keys: `id, section_number, title, listen_url, language, playtime, file_name, readers[{reader_id, display_name}]`. `listen_url` is an archive.org `/download/.../*_64kb.mp3` | `curl -s 'https://librivox.org/api/feed/audiobooks?genre=Dramatic%20Readings&format=json&limit=1&extended=1'` |
| M12 | LibriVox HTTP | Python urllib's default User-Agent gets **403**; curl works. Send a real UA | (observed) |
| M13 | NARA OWI sound recordings online | **1,216** hits for "Office of War Information" + Sound Recordings + availableOnline. Each file is a direct MP3 (e.g. `https://catalog.archives.gov/medialz/mopix/208a/GENERALa/208-597a.mp3`). **The series record says `useRestriction: "Restricted - Possibly", specificUseRestrictions: ["Copyright"]`, with the note "Some or all of this material may be restricted by copyright"** | `curl -s 'https://catalog.archives.gov/proxy/records/search?q=%22Office%20of%20War%20Information%22&typeOfMaterials=Sound%20Recordings&availableOnline=true&limit=1'`. This is the catalog web app's proxy; the documented `/api/v2/` path needs an `x-api-key` and returned HTML without one |
| M14 | loc.gov audio JSON API | Works with no key. `q=radio` gives 1,021 audio results; `q=radio drama` 98 (Memovox radio transcriptions lead); `q="office of war information"` 9 | `curl -s 'https://www.loc.gov/audio/?q=radio&fo=json&c=1' \| jq .pagination.of` |
| M15 | AAPB has a public Solr API | `api.json` answers with no key. `q="radio drama"` gives 1,950; with `fq=access_types:online`, **214** | `curl -s 'https://americanarchive.org/api.json?q=%22radio%20drama%22&fq=access_types:online&rows=0'` |
| M16 | Europeana sound items matching hörspiel / "radio drama" / "radio play" | **95 total, 0 with `reusability=open`** | `curl -s 'https://api.europeana.eu/record/v2/search.json?wskey=api2demo&query=h%C3%B6rspiel%20OR%20%22radio%20drama%22%20OR%20%22radio%20play%22&qf=TYPE:SOUND&reusability=open&rows=0'` |
| M17 | RadioEchoes, home page | "21 Genres of shows, **5,069 Series**, for a total of **129,158 Episodes** ... play ... and download ... all for FREE!" No terms or rights statement on the page | `curl -sL -A '<browser UA>' https://www.radioechoes.com/` |
| M18 | Old Time Radio Downloads | Footer: "Copyright 2007-2026 Old Time Radio Downloads; Reproduction of text strictly prohibited," and the site promotes buying from **OTRCAT.com**. It is a sister site of a seller. With no User-Agent the site returns a database error | `curl -sL -A '<browser UA>' https://www.oldtimeradiodownloads.com/` |
| M19 | OTRR copyright policy (full text read) | "We do not own the copyrights ... We believe that the copyrights have expired, or that the shows are in the public domain because they were never copyrighted ... we will remove any recording ... shown to violate a copyright." The page then quotes RadioLovers' secondhand LOC-staff claim that pre-1978 recordings are "generally in the public domain." That claim predates the 2018 MMA | `curl -sL -A '<browser UA>' https://www.otrr.org/OTRRLibrary/copyright.html` (mod_security refuses requests with no UA) |
| M20 | Generic Radio Workshop ownership statement | "We make no claims to ownership of these materials; **they remain, as they should, the copyright of their respective owners**." Latest additions are dated 08/31/26 | `curl -sL -A '<browser UA>' https://genericradio.com/` |
| M21 | JFK Library | Cloudflare blocks the container ("Sorry, you have been blocked"). Its PD label remains **search-snippet only** | `curl -sL -A '<browser UA>' https://www.jfklibrary.org/node/437251` |
| M22 | Wikimedia Commons | `Category:Old-time_radio`, `Category:Radio_programs_of_the_United_States` and `Category:Audio_files_of_radio_programs` **do not exist** under those names (categoryinfo is null). The right category tree is still to be found | `curl -s -A '<project UA>' 'https://commons.wikimedia.org/w/api.php?action=query&prop=categoryinfo&titles=Category:Old-time_radio&format=json'` |

**What the measurements change:**
- The archive.org OTR corpus is **about 9,000 items**. An item is usually a series or a
  set, so this is not an episode count; episodes are files (another agent owns the
  file-level measurement).
- **About a third of the licensed OTR items carry a CC BY-NC-ND license an uploader put
  on a 1940s broadcast.** That is exactly the "uploader's word" of Decision 140. An
  uploader cannot license what it does not own, so an NC-ND tag is not evidence, and
  neither is a PD Mark. Do not let `licenseurl` admit or exclude an OTR item.
- **NARA does not call the OWI recordings public domain.** It marks the series
  "Restricted - Possibly: Copyright." So §10's ranking of OWI as "strong" is downgraded
  to **medium**: federal origin is likely, but the custodian itself warns. Admit OWI per
  item, with evidence that the item is a government production.
- **Europeana has no open radio drama.** Drop it from the plan.
- **AAPB and loc.gov both have keyless JSON APIs.** They are usable for metadata and
  provenance today.

---

## Verdict

1. **The Internet Archive is the only realistic primary corpus.** It has OTRR's
   researched series sets (`OTRR_*_Singles` items under the `oldtimeradio` collection),
   per-file MP3s at stable direct URLs, and the advancedsearch, scrape and metadata APIs
   that Archive Watch's pipeline already calls (`tools/probe_collections.py`,
   `tools/build-catalog.mjs`, `tools/fetch_archive_own_meta.py`). Nothing else has the
   size, the API and the permission to stream, all three.
2. **The big rights finding: "OTR is public domain" is folklore, and the 2018 Music
   Modernization Act contradicts it for US recordings.** Under the MMA (Title II,
   CLASSICS Act), pre-1972 sound recordings published 1923-1946 are protected for 100
   years and those published 1947-1956 for 110 years. The cutoff year is reported as 1923
   or 1924 depending on the source. Recordings from 1957 through 1972 are protected until
   2067. So most Golden Age broadcasts (1930-1962) are still protected as *recordings* by
   statute, whatever the scripts' status. OTRR's own copyright policy reads: *"believe
   the copyrights have expired or the shows were never copyrighted"*, and it removes a
   recording when shown a claim. That is belief, not evidence, and it is the "uploader's
   word" of Decision 140. The rights track has to settle this before anything ships.
3. **The genuinely free spine is narrow and well-defined:**
   (a) **LibriVox** recordings, including its ~500 Dramatic Works (full-cast plays). They
   are dedicated to the public domain, the texts are pre-1930 US PD, and the API is
   documented.
   (b) **US federal government productions**: OWI (NARA series 208-GENERALa, fully
   digitized; 1,216 online MP3s, but NARA marks the series "Restricted - Possibly:
   Copyright", M13), Treasury (Treasury Star Parade, Guest Star), FCDA (Stars for Defense),
   AFRS originals, and VOA/USIA (JFK Library labels its USIA items public domain). These
   fall under 17 U.S.C. §105, *but* donated performances, network dubs and music need
   per-series judgment.
   (c) **Creator-licensed modern audio drama** (CC BY / CC BY-SA). There are many shows
   and no central index.
   (d) **Recordings from 1925 and earlier**, which the MMA has released (very little of
   this is radio).
4. **Metadata comes from the community logs, and none of them has an API.** OTRR's OTTER
   database, Jerry Haendiges' logs (500+ series), Digital Deli Too, RadioGoldIndex
   (UMKC, 123,000+ programs) and the Generic Radio Workshop's scripts (1930-1960) all
   need scraping or a partnership. The logs disagree with each other on air dates, so
   treat a date as a claim with a source, as Decision 124 does for synopses.
5. **Institutional archives (LOC NBC, about 70,000 hours; UMKC Marr; Paley; AAPB) are
   reading rooms, not feeds.** They are good for evidence and context and almost never
   streamable. AAPB (about 12,000 programs online) is the exception worth probing.
6. **Commercial sellers (Radio Spirits, OTRCat, RUSC, Haendiges' shop) are never
   sources.** Radio Spirits stamps its releases "(P) Radio Spirits Inc." and is the party
   most likely to assert claims. Treat its catalog as a **claims list**, the Decision 151
   pattern: a title Radio Spirits sells under license is evidence of a claim.

---

## 1. Internet Archive (archive.org): primary corpus

### 1.1 What it holds
- **`oldtimeradio` collection.** This is the umbrella collection for OTR audio. It has a
  collection RSS at `https://archive.org/services/collection-rss.php?collection=oldtimeradio`
  (seen in search results). The search could not get a total item count. **To measure.**
- **OTRR uploads.** The Old Time Radio Researchers upload one item per series (or per set
  of single episodes). Examples seen in search results: `OTRR_Mel_Blanc_Singles`,
  `OTRR_Red_Horse_Ranch_Singles`, `OTRR_Hallmark_Single_Episodes`,
  `OTRR_All_Star_Western_Theatre_Singles`, `OTRR_Tarzan_Singles_TLotJ`,
  `OTRR_Case_Dismissed_Singles`, `OTRR_Line_Up_Singles`, `OTRR_Behind_The_Mike_Singles`,
  `Singles_And_Doubles_Singles_A-C` and `..._T-Z`, `OTRR_Home_Page` and
  `OTRR_Old_Radio_Times_Newsletters`. The Old Time Radio Researchers Collection page
  (`archive.org/details/lumedwards`) shows **collectionSize 676** in its metadata (per
  search snippet, undated); **MEASURED 2026-10-17: 692 items** (M3). That figure is the number of items, not episodes.
- **User-curated compilations.** For example `old-time-radio-collection` ("Señor Video"),
  `UniqueOldTimeRadioEpisodes` (L. Maupin), `ChristmasOTRCollection`,
  `oldtimeyradioshowscollection`, and `gang-busters-1955-04-02-...` (88 Gang Busters
  episodes). The provenance of these is weaker than OTRR's. Rank them below OTRR sets.
- **Related reference items.** `OTRCatalogs` (the Joe Hehn Memorial Collection,
  collector catalogs from the 1960s and 1970s) can serve as evidence for log
  reconciliation. `WWII_News_1939` is a news item marked public domain.
- **Podcaster uploads.** For example `RelicRadioShow`, uploaded by Relic Radio itself.
- **LibriVox's audio is also on archive.org.** Its API returns a `url_iarchive` field
  (prior knowledge, UNVERIFIED this session), so LibriVox plays through the same
  archive.org file plumbing.

### 1.2 OTRR's quality tiers, which make a usable quality signal
The terms below come from search snippets of the item pages.
- Before 2019, OTRR used two labels. **"Certified Accurate"** meant episodes were
  correctly identified and labeled, but the set might be incomplete. **"Certified
  Complete"** meant every circulating episode was included.
- From about 2019 the label is **"Maintained Set"**: all known episodes, best available
  audio, and the most accurate dates and titles known at release.
- Sets that have not been through this process are **"Non-certified."**
- OTRR's condition on its certified sets is that they may be shared but not sold, and
  must be passed on as prepared. That is a distribution term, not a rights claim.
- OTRR tags every page with an update keyword `OTRR - YYYY-MM`. You can search on it to
  find recently refreshed sets.
- **App use:** the certification tier is a data-derived "best copy" ranking signal, the
  analogue of Decision 040's best-copy rank. A Maintained or Certified set should beat a
  user compilation of the same series.

### 1.3 Access methods
These are the same endpoints Archive Watch uses today.
- **advancedsearch:** `https://archive.org/advancedsearch.php?q=...&fl[]=...&rows=..&output=json`.
  `numFound` is the reliable count. `tools/probe_collections.py` lines 70-71 record that
  the scrape API's `total` is *not* the collection size.
- **scrape (cursor paging):** `https://archive.org/services/search/v1/scrape?q=..&fields=..&count=..&cursor=..`.
  This is wrapped by `archiveScrape` in `tools/build-catalog.mjs`. Its minimum count is
  100.
- **metadata:** `https://archive.org/metadata/{identifier}`. It returns item metadata
  plus a `files[]` array. In standard archive.org schema each file entry has `name`,
  `format` (for example "VBR MP3", "64Kbps MP3", "Ogg Vorbis"), `size`, `length`,
  `md5`, and often ID3-derived `title`, `track`, `album` and `creator`. This is prior
  knowledge from the Archive Watch pipeline. Check it against an OTR item.
- **File URLs:** `https://archive.org/download/{identifier}/{filename}`. These are
  direct, Range-capable MP3 links, the same pattern the video apps stream today.
- **Item fields to expect** (archive.org metadata schema,
  `https://archive.org/developers/metadata-schema/index.html`): `identifier`, `title`,
  `creator`, `date`, `description`, `subject` (OTRR stores keywords here), `collection`,
  `mediatype=audio`, `licenseurl`, `rights`, `addeddate`, `publicdate`, `downloads`,
  `num_reviews`, `avg_rating`. **The episode-level data (air date, episode number,
  episode title) is in the file name, not in item fields.** OTRR names files roughly as
  `Series YY-MM-DD Ep### Title.mp3` (prior knowledge, UNVERIFIED). A file-name parser is
  therefore load-bearing, and so is reconciliation against the logs (§3).
- **Bitrates:** OTR circulates mostly as low-bitrate mono MP3 (commonly 32-64 kbps),
  transferred from transcription discs and tape. This is prior knowledge, UNVERIFIED this
  session; measure it with the file `format` and `size`/`length` fields (see "To
  measure").
- **Hotlinking and streaming:** Archive Watch already streams archive.org files to every
  platform under the same terms, so audio needs no new permission. Respect the
  User-Agent and rate norms the existing tools use.

### 1.4 Rights posture
- Item `licenseurl` is mostly empty for OTR (expected; measure it). Uploaders' "public
  domain" in the description is the uploader's word (Decision 140).
- OTRR's policy page (`https://www.otrr.org/OTRRLibrary/copyright.html`, per search
  snippet) says three things: OTRR does not own the copyrights, it believes the
  copyrights expired or never existed, and it will remove a recording shown to violate
  one.
- See §11 for why the MMA makes "expired" wrong for most 1923-1972 US recordings.

**App usefulness: 5/5 as corpus plumbing. Rights: unresolved for anything except the
free spine (§10).**

---

## 2. Old Time Radio Researchers (otrr.org): the library and the research behind the sets

- **Holds:** OTRR's own site says its database covers **over 2,030 series and more than
  192,000 episodes**, and describes its library as the largest and most accurate. This
  is self-description, per search snippet of otrr.org. A third-party database entry
  cites **over 70,000 episodes** freely available through its library. The two figures
  likely measure different things: logged episodes versus episodes held. OTRR's archive
  tracker reports "2314 Archives, 4356 Topics Loaded"
  (`https://otrr.org/archives.html`, per search snippet).
- **Access:** the OTRR library and its distribution run through archive.org (§1.2). The
  site also has log-submission pages (`otrr.org/pg02c_direct.htm`), help pages, the OTTER
  logs database (text logs from many contributors, which OTRR asks users to credit), the
  Old Radio Times newsletter PDFs, and articles. One of those articles,
  `otrr.org/FILES/Articles/Ryan_Ellett_Articles/The Script Library Final.pdf`, concerns
  OTRR's script library.
- **Metadata:** series-level episode logs (title, air date, episode number, sometimes
  cast). There is no API.
- **Rights:** see §1.4. OTRR asks that sets not be sold.
- **App role:** the **reference spine for series and episode identity**, through its
  archive.org items. Contact OTRR before bulk use of OTTER logs, and credit the log
  authors as OTRR asks.

**App usefulness: 5/5 (data quality), with no programmatic access beyond archive.org.**

---

## 3. Logs and research databases (metadata, never audio)

| Source | What (per search snippet) | Access | Notes |
|---|---|---|---|
| **Jerry Haendiges Vintage Radio Logs** (`otrsite.com`) | "well over 500 Logs of Episodic Listings for Several Thousand Old Radio Programs" from a personal collection of 80,000+ programs; each log gives catalog number, title, air date, running time and cast notes | Static HTML pages (for example `otrsite.com/logs/loga1031.htm`) | Every log carries a last-updated date. The logs advertise his paid recordings ("*na*" = not available). WorldCat records cite them. They are a commercial shop's logs: use them as facts, not as an audio source |
| **Digital Deli Too** | Logs and articles; often cites the newspaper each date came from | HTML | One reviewer says it is less frequently updated and sometimes uncharitable to others. Its newspaper citations are valuable as date evidence |
| **RadioGoldIndex** (J. David Goldin, now at UMKC) | A database of **over 123,000 radio programs** | Web search UI | The physical recordings are at UMKC Marr and need a request. It is the most complete program-level index |
| **JJ's Newspaper Radio Logs** (`jjonz.us/RadioLogs`) | **45,000+** daily newspaper radio listings, 1930-1960 (NYT, Washington Post, Chicago Tribune, LA Times) | HTML | The primary-source witness for an air date |
| **old-time.com logs** | Logs by Frank Passages, Stewart Wright and others | HTML | Some are old |
| **OTRR OTTER** | Contributor text logs | Download | Credit the contributors |

**Logs disagree.** A quietplease.org forum comparison of four logs (Haendiges, Paul's
guide, Gordon Payton, Digital Deli) found one episode dated August 17, 1947 by most logs
and August 18 by one. The script carried both a network date and a WOR date. **Store an
air date with its source and keep the alternatives**, as with Decision 124's synopsis
provenance.

---

## 4. Scripts: the Generic Radio Workshop (genericradio.com)

- **Holds:** in its own words, "the original and largest collection of radio scripts and
  transcripts from the Golden Age of Radio available on the Internet," covering about
  1930-1960. Series cited by third parties include The Witch's Tale, Columbia Workshop,
  Lights Out and Lux Radio Theatre. It is still being added to: August 2026 additions
  include *Screen Guild Theater* "Double Indemnity" (1950) and *The New Adventures of
  Nero Wolfe* (1951). It also sells RadioKits (Word and PDF scripts plus USB music and
  effects) for staged recreations. Larry Groebe is its archivist.
- **Rights (MEASURED 2026-10-17, M20):** "We make no claims to ownership of these
  materials; they remain, as they should, the copyright of their respective owners." So
  the site itself says the scripts are *not* free. The scripts are separate copyrights
  from the recordings. A script can be PD while its recording is not, and the reverse.
- **App role:** (a) script text as **metadata evidence**: cast, credits and the episode
  title as written; (b) a future "read along" or transcript feature if a script is shown
  PD; (c) a **rights witness**, since a registered script is a claim. Ask before scraping.
  There is no API.

**App usefulness: 3/5, metadata and evidence only.**

---

## 5. Free-listening OTR sites (secondary; not to build on)

| Site | What (per search snippet) | Rights posture | Role |
|---|---|---|---|
| **RadioEchoes** (radioechoes.com) | MEASURED (M17): 5,069 series, 129,158 episodes, 21 genres, free to play and download; accepts donated MP3s | No terms or rights statement on the home page | **Never** as a source: donated files, unknown provenance. Its catalog might serve to cross-check series names |
| **Old Time Radio Downloads** (oldtimeradiodownloads.com) | MEASURED (M18): free downloads with accounts and an RSS feed; promotes and links OTRCAT.com, i.e. a seller's sister site | "Copyright 2007-2026 ... Reproduction of text strictly prohibited" | **Never** |
| **cbsrmt.com** (CBS Radio Mystery Theater fan site) | All 1,399 episodes, free | CBSRMT is 1974-82, **post-1972 federal copyright**, CBS. Not PD | **Never** |
| **Relic Radio** (relicradio.com; podcast feeds; `archive.org/details/RelicRadioShow`) | Curated podcast feeds: The Relic Radio Show, Sci-Fi, The Horror!, Case Closed! | Apple Podcasts lists "Copyright© RelicRadio.com" (the curation, not the shows) | **Precedent** (§12): proves the episodic-feed model. Not a source |
| **OTR Player** (iOS app id1493221239) | "over 15,000 episodes from more than 130 shows, all free" | UNVERIFIED | A competitor / precedent |
| **Vintage Radio** (iOS app id455577974) | 4,000 free, with a subscription for about 34,000 more (2013 post) | Commercial | A competitor / precedent |

---

## 6. Commercial sellers (claims lists, never sources)

- **Radio Spirits** (radiospirits.com; trademarks owned by RSPT, LLC per Justia). In its
  own words it is the "leading publisher and marketer" of classic radio, with "tens of
  thousands" of programs from the 1930s to the 1960s. Gunsmoke releases carry "©2006
  Radio Spirits Inc. (P)2006 Radio Spirits Inc." Gunsmoke aired on CBS 1952-1961. The
  search could not establish whether Radio Spirits holds a CBS license.
  **Recommended role: a claims witness.** If Radio Spirits sells a series under license
  from a network or estate, that is a reader-openable claim (Decision 151 pattern). Do
  not treat it as proof the series is protected, but do not recommend it.
- **OTRCat** (otrcat.com). It sells MP3 volumes at $5-$60 and says reproduction is
  prohibited on its pages, for example `otrcat.com/p/command-performance` and
  `otrcat.com/p/stars-for-defense`. That is a notice on its own transfers. Its category
  pages (`otrcat.com/patriotic-old-time-radio`) are useful for discovering series. Role:
  **never** a source. Use it for discovery only.
- **RUSC** (rusc.com). A subscription service with "over 40,000" popular shows. Role:
  **never**.
- **Haendiges' shop.** Role: **never** as audio; his logs are §3.

---

## 7. Institutional archives

| Institution | What (per search snippet) | Online access | Rights | Role |
|---|---|---|---|---|
| **Library of Congress: NBC Radio Collection** | "over 70,000 hours," 1933-1971, the largest single US broadcast collection. A later LOC blog says "more than 40,000 hours" | **On-site only** (Recorded Sound Research Center). The SONIC catalog has records, no audio | NBC/Comcast and performers | **Metadata/evidence only.** SONIC records can corroborate air dates and titles |
| **LOC: National Jukebox** (`loc.gov/item/jukebox-*`) | Commercial discs (Sony/EMI), mostly music | Streamable on loc.gov "pursuant to permission from the rightsholders" | Each rights advisory restates the MMA schedule (pre-1923 PD from 2022-01-01; 1923-46 100 years; 1947-56 110 years) | **Never** for an app (permission is the LOC's, not ours). **It is the best primary statement of the MMA schedule to cite** |
| **LOC: OWI collection** | Over 8,000 OWI broadcast records, 1942-1945 (per NARA History Hub), separate from NARA's | UNVERIFIED (search budget ran out) | Federal work (§105), subject to the caveats in §10 | Probe it. A potential **primary** source of free government radio |
| **LOC: National Recording Registry** | Includes radio broadcasts (for example the 1938 *War of the Worlds* and *Fibber McGee*, from prior knowledge, UNVERIFIED) | List only | Registry status is **not** a rights statement | **Metadata/editorial:** a sourced "registry" badge, a human-chosen list the product may show (it is not AI copy) |
| **LOC: Radio Research Project manuscripts** (online 2021, per infodocket) | Manuscripts | Online | n/a | Context |
| **NARA** (catalog API v2) | RG 208 (OWI): 610 series, **801 items digitized** (History Hub, date unclear). Series **208-GENERALa**, OWI WWII sound recordings, is "fully digitized" (NARA 2022 user guide), transferred from reference tapes rather than the original discs | `https://catalog.archives.gov/api/v2/records/search` with `availableOnline`, `typeOfMaterials` and an API-key header (`archives.gov/research/catalog/help/api-getting-started`) | Federal records, generally §105 PD; NARA's own use restrictions per record | **Primary corpus** for government radio. It has an API |
| **American Archive of Public Broadcasting** (LOC + GBH) | About 40,000 hours digitized; **nearly 12,000 programs** in the Online Reading Room, 1940s onward | americanarchive.org reading room. API not confirmed (it is believed to exist from prior knowledge, UNVERIFIED) | Per-program, mostly station-owned. Not PD by default | **Metadata, plus probe for PD items** (for example federal or NAEB items). Not a primary corpus |
| **WNYC / NYC Municipal Archives** | The WNYC Collection: lacquer discs and tapes 1937-1970, "the largest non-commercial collection ... from an individual radio broadcaster"; a Preservica portal at `nycrecords.access.preservica.com` | Partly online. WNYC's archive page says it was under maintenance | City records. **The search found no rights statement.** A municipal work is not federal and §105 does not apply | Probe it. Possibly **candidates** if the City licenses openly. Default **never** |
| **U. Maryland Library of American Broadcasting / NPBA** | Westinghouse tapes (2,300+ news feeds 1957-82), NFCB archive (600+ programs, streamable), audiovisual series 1952-1982 | Partly streamable in UMD Digital Collections; holdings are non-circulating | Mixed, mostly copyrighted | **Metadata/context** |
| **UMKC Marr Sound Archives** | 350,000-400,000+ recordings in total (the sources disagree). The Goldin collection (27,000 reels, about 16,000 discs, 3,000 CDs per a UMKC announcement; another record says 10,000 items). KMBC radio from the 1930s-1950s; 445 hours digitized under a grant | On request (`soundarchives@umkc.edu`); some digital collections (Ted Malone) | Mixed | **Metadata** (RadioGoldIndex); a partner for provenance questions |
| **Paley Center** | UNVERIFIED (not searched): a large radio and TV collection, viewed on-site | On-site | Copyrighted | **Never** as audio |
| **Smithsonian** | UNVERIFIED (not searched). Smithsonian Folkways is commercial. NMAH holds broadcast artifacts | n/a | n/a | **Art/context at most.** Smithsonian Open Access (CC0) images may give period art (UNVERIFIED) |
| **JFK Library: USIA audio collection** | VOA programs 1958-1965 with downloadable audio, marked public domain as works of US officials | Direct "Download Audio File" pages | PD label with a per-item caveat | **Primary candidate** for VOA material: a federal source with a PD statement a reader can open |

---

## 8. LibriVox: the cleanest free drama source

- **Holds:** audiobooks read by volunteers, and **Dramatic Works**: plays where each
  reader takes a character, plus "dramatic readings." The wiki page
  `wiki.librivox.org/index.php/Dramatic_Readings_and_Plays` says it, and the 2020 DW
  stats sheet (`librivox.org/uploads/dlolso21/Librivox DW Stats 2020.pdf`) counts **492
  dramatic works**, a 2020 figure. The works are pre-1930 texts (Shakespeare, Shaw,
  Wilde, Chekhov, Ibsen; one-act play collections such as
  `librivox.org/one-act-play-collection-009/`).
- **Rights:** each recording is released under the **Creative Commons Public Domain
  Dedication** (creativecommons.org 2006 interview; Internet Archive's 2025 "Public
  Domain Spotlight: LibriVox"). CC has since retired that tool in favor of CC0. Its
  effect outside the US is less certain (Wikipedia's Template:LibriVox public domain).
  Readers certify that the text is PD in the US. **Strongest rights posture in this
  survey.** The caveat is territorial: a text PD in the US may not be PD in, for
  example, the EU.
- **API:** `https://librivox.org/api/feed/audiobooks` (documented at
  `librivox.org/api/info`). It takes `id`, `since` (a UNIX timestamp), `author`, `title`
  (a leading `^` anchors), `genre`, `extended=1`, `coverart=1`, `limit` (default 50) and
  `offset`. `format` is xml by default and can be json, jsonp, serialized or php. Fields
  are not listed on the info page. From prior knowledge (UNVERIFIED): `id`, `title`,
  `description`, `url_text_source`, `language`, `copyright_year`, `num_sections`,
  `url_rss` (a per-book podcast RSS), `url_zip_file`, `url_librivox`, `url_iarchive`,
  `totaltime`, `totaltimesecs`, `authors[]`, `genres[]`, `translators[]`, and with
  `extended=1`, `sections[]` with each section's `listen_url`, `playtime` and
  `readers[]`.
- **Formats:** MP3 at 64 kbps and 128 kbps, plus Ogg, on archive.org (prior knowledge,
  UNVERIFIED).
- **App role:** **primary corpus** for "radio plays / theater" shelves. Its genre data is
  human categorization (it is not AI copy). The audio rides the archive.org plumbing.

**App usefulness: 5/5 for drama. It is not "old-time radio," but it is the
rights-cleanest full-cast drama anywhere.**

---

## 9. Other free and open sources

- **Wikimedia Commons audio.** Commons hosts a work only if it is free in both the US and
  the source country (Commons policy, per search snippet). Example: the Weber & Fields
  "Baseball game" (1916) disc. Dutch wartime broadcasts (Radio Oranje, Radio Herrijzend
  Nederland) are public domain under Dutch law, are on Commons and the Commons API, and
  are in Beeld en Geluid's datasets (`data.beeldengeluid.nl/id/dataset/0006`, `/0007`).
  Role: a **small primary** (Commons' license templates are reader-openable evidence)
  and **art** (period photos, station logos).
- **Europeana Sounds.** 18 institutions in 12 countries, including "radio programs." The
  API and SPARQL endpoint have a reuse filter ("Yes - with attribution"). Sources are
  2015-2017. The search found no Hörspiel collection specifically. Role: **probe**, then
  maybe a small primary for European drama, filtered by `RIGHTS` (open only).
- **NFSA Australia.** The Radio Series collection has **over 35,000 titles**
  (transcription discs and/or scripts). Excerpts are online (for example *Dr Paul*
  c1963, *Marie Antoinette* 1939). No PD streaming was found. Australian copyright terms
  differ. Role: **metadata/context only**.
- **BBC Genome / Programme Index.** Radio Times listings 1923-2009, as metadata. The
  successor Programme Index links to iPlayer and Sounds. The audio is BBC-owned and not
  PD. Role: **metadata only** (BBC radio drama credits), **never** audio.
- **CBC / Library and Archives Canada.** UNVERIFIED (not searched). Canadian Crown
  copyright is not §105, and CBC audio is CBC-owned. Default **never**, pending probe.
- **Modern CC audio drama.** Examples: *When Sysadmins Ruled the Earth* (a full-cast
  adaptation of Cory Doctorow's CC story, QN Podcast, 2009; the adaptation's own license
  is unconfirmed), and Escape Pod (short fiction under CC; its spin-off Escape Pod X is
  all rights reserved). In German, the *Little Brother* Hörbuch is under CC (netzpolitik,
  2010). No central index was found. The pitfalls: ND licenses forbid derivatives, and
  some files are "download only." Role: **secondary primary, per-show admission only**,
  each with the license as stated in the show's own feed (`<copyright>` / CC RSS
  module), and NC or ND flagged.

---

## 10. Which series are best documented as genuinely free

These are ranked by strength of evidence a reader can open. Everything still needs
per-series verification by the rights track.

1. **LibriVox Dramatic Works.** The PD dedication is on every recording; the texts are
   pre-1930.
2. **OWI WWII sound recordings, NARA 208-GENERALa.** These are federal records, fully
   digitized, with an API. **Downgraded to medium (MEASURED 2026-10-17, M13):** NARA's
   own record says "Restricted - Possibly: Copyright." Some OWI programs used network
   talent and network facilities.
3. **VOA/USIA programs at the JFK Library.** Each is labeled PD as a work of US
   officials.
4. **Treasury Department series**: *Treasury Star Parade* (1942-44, "produced by the
   Treasury Department" for 800+ stations) and *Guest Star* (1947-1966, savings bonds).
   These are federal productions, but they carry donated star performances and
   commercial music. §105 covers the government's own authorship and does not clearly
   clear a performer's contribution or the music. **Medium.**
5. **FCDA's *Stars for Defense*** (1956-67). Same caveat. **Medium.**
6. **AFRS originals** (*Command Performance*, *Mail Call*, *G.I. Journal*, *Jubilee*).
   AFRS was a US government agency (est. 1942) and these were produced by it. But AFRS
   also **dubbed network shows** with the commercials removed. Those dubs are network
   programs, not government works. **Admit AFRS originals only, never AFRS rebroadcasts
   of network series.**
7. **Recordings published 1925 and earlier**, released by the MMA's 100-year rule. Very
   little radio survives from then.

Everything else (Suspense, The Shadow, Gunsmoke, Jack Benny, Lux Radio Theatre and so
on) is **unresolved**. Network-era recordings are likely protected by the MMA until 2031
or later. The scripts may or may not have been registered and renewed (a CCE check like
Decision 157's would find out).

---

## 11. The statute that reframes "public domain OTR"

Per search snippets of the CRS legal sidebar LSB10181 and LOC Jukebox rights advisories:
- The MMA Title II extended federal protection to pre-1972 sound recordings on
  essentially the same terms as later recordings.
- **The schedule.** Recordings published before 1923 entered PD on 2022-01-01. Those
  published 1923-1946 are protected 100 years after publication. Those published
  1947-1956 are protected 110 years. Those from 1957 through 1972-02-15 are protected
  until 2067-02-15. The sources disagree on whether the second band starts in 1923 or
  1924.
- **For the app (as of 2026):** a recording first published in 1925 or earlier is PD.
  One from 1930 is protected through 2030, one from 1946 through 2046, and one from 1950
  through 2060.
- **Open questions for the rights track** (UNVERIFIED, from prior knowledge of 17 U.S.C.
  §1401):
  - How the schedule applies to broadcasts never "published" in the copyright sense.
  - Whether a broadcast is publication.
  - §1401(c)'s non-commercial-use notice. A user may file a notice with the Copyright
    Office for a pre-1972 recording that is not being commercially exploited, and the
    rights owner has 90 days to object. A free, ad-free app might qualify. That is a
    mechanism worth researching, not assuming.
  - The 1972 boundary (recordings fixed after 1972-02-15 are under ordinary federal
    copyright, as with CBSRMT).
- **The forum folklore** (a secondhand quote of LOC staff saying OTR is "generally"
  public domain, in the OTRCat search results) predates or ignores the 2018 MMA. Do not
  cite it.

---

## 12. Distribution precedent (not sources)

The episodic-feed model works and is accepted on Apple Podcasts and Spotify: Relic Radio's
feeds, "The RUSC Guide to Old-Time Radio" podcast, OTR podcast listings on podnews and
podcastrex. Platforms do act on rights: the NMPA's 2025 takedown action against Spotify
targeted unlicensed music in podcasts. That is a warning, because **OTR episodes are full
of copyrighted music cues and commercial jingles**. Only the free spine of §10 avoids
the question.

---

## Sources to build on, in order

| # | Source | What | Access method | Rights posture | Metadata richness | Recommended role |
|---|---|---|---|---|---|---|
| 1 | Internet Archive: OTRR sets in `oldtimeradio` | Thousands of series, single-episode MP3s, Certified and Maintained tiers | advancedsearch / scrape / metadata APIs; direct `/download/` URLs (pipeline already exists) | Unproven: OTRR "believes" PD; the MMA says most 1923-72 recordings are protected | Medium: item fields plus parseable file names; tiers as a quality signal | **Primary corpus (plumbing)**; admission per series by the rights audit |
| 2 | LibriVox (incl. Dramatic Works) | ~500 full-cast plays (2020), plus readings | `api/feed/audiobooks` JSON; audio on archive.org | **Strong**: PD dedication, pre-1930 texts | High: authors, genres, readers, sections, durations | **Primary corpus** (drama shelves) |
| 3 | NARA catalog (RG 208 OWI, 208-GENERALa) | OWI WWII radio, 1,216 online MP3s (M13) | Catalog API v2 (key) / catalog proxy, direct MP3 | **Medium**: federal origin, but NARA marks the series "Restricted - Possibly: Copyright" | Medium: NARA descriptions plus paper finding aids | **Primary corpus** (government radio) |
| 4 | JFK Library USIA/VOA audio | VOA programs 1958-65 | Direct download pages | **Strong**: labeled PD per item | Medium | **Primary** (small) |
| 5 | Archive.org federal series (Treasury Star Parade, Guest Star, Stars for Defense, AFRS originals) | Government-produced series | Same IA APIs | **Medium**: §105 vs donated talent and music | Medium | **Primary candidates**, per series after review |
| 6 | Generic Radio Workshop | Scripts 1930-1960 | HTML; ask first | Scripts are their own copyrights | High (credits as written) | **Metadata / rights evidence** |
| 7 | OTRR logs / OTTER, Haendiges, Digital Deli, RadioGoldIndex, JJ's newspaper logs | Episode logs, air dates, cast | HTML / download; no APIs | n/a (facts) | High, but they disagree; keep sources | **Metadata** (with provenance) |
| 8 | LOC SONIC / NBC / National Recording Registry | Catalog records; registry list | Web catalog; loc.gov JSON (probe) | The audio is not ours | Medium | **Metadata / editorial badges** |
| 9 | AAPB | ~12,000 programs online; "radio drama" 1,950, 214 online (M15) | Keyless Solr `api.json` | Per-program, mostly protected | High | **Metadata**; probe for PD items |
| 10 | Wikimedia Commons | A few PD broadcasts; period images | Commons API | Strong (dual US/source PD templates) | Medium | **Small primary + art** |
| 11 | Europeana Sounds | 95 radio-drama sound items, 0 open (M16) | Europeana API | Nothing open | Medium | **Never** (nothing reusable) |
| 12 | Modern CC audio drama | Independent full-cast shows | Each show's RSS | Per feed (CC BY / BY-SA ok; NC/ND flagged) | Low to medium | **Secondary primary**, per-show admission |
| 13 | BBC Genome, NFSA, UMD LAB, UMKC Marr, WNYC, Paley | Listings and holdings | Web / on-site | Owned by others | Medium-high | **Metadata / context only** |
| 14 | Radio Spirits, OTRCat, RUSC, Haendiges' shop | Commercial catalogs | Web | Claims to their transfers / licenses | Medium | **Never** (Radio Spirits' license list as a **claims witness**) |
| 15 | RadioEchoes, oldtimeradiodownloads.com, cbsrmt.com, OTR apps | Free listening sites | Web | Unknown / donated / post-1972 | Low-medium | **Never** (precedent only) |

---

## To measure

Run these from CI (`probe-sources.yml`-style workflow_dispatch, like
`tools/probe_collections.py`), since the dev sandbox cannot reach these hosts.

```bash
# 1. Size of the OTR corpus on archive.org (numFound is reliable; scrape total is not)
curl -s 'https://archive.org/advancedsearch.php?q=collection:oldtimeradio+AND+mediatype:audio&rows=0&output=json' | jq .response.numFound
curl -s 'https://archive.org/advancedsearch.php?q=identifier:OTRR_*+AND+mediatype:audio&rows=0&output=json' | jq .response.numFound
curl -s 'https://archive.org/advancedsearch.php?q=subject:%22old+time+radio%22+AND+mediatype:audio&rows=0&output=json' | jq .response.numFound
curl -s 'https://archive.org/advancedsearch.php?q=collection:librivoxaudio&rows=0&output=json' | jq .response.numFound

# 2. Which fields OTR items actually carry (fill rates)
curl -s 'https://archive.org/services/search/v1/scrape?q=collection:oldtimeradio&fields=identifier,title,creator,date,subject,licenseurl,rights,description,downloads,addeddate&count=1000' > otr_page1.json
python3 -I -c "import json,sys,collections as c;d=json.load(open('otr_page1.json'))['items'];f=c.Counter(k for i in d for k in i);print(len(d),f.most_common())"

# 3. File-level shape of one OTRR set: formats, bitrates, durations, naming
curl -s https://archive.org/metadata/OTRR_Line_Up_Singles | jq '.metadata, [.files[] | select(.format|test("MP3")) | {name,format,length,size,title,track}] | .[0:10]'
#   bitrate check: size*8/length per file; tally format values across 50 OTRR items

# 4. Certification tier counts
curl -s 'https://archive.org/advancedsearch.php?q=collection:oldtimeradio+AND+(description:%22Certified+Complete%22+OR+description:%22Maintained+Set%22)&rows=0&output=json' | jq .response.numFound

# 5. LibriVox Dramatic Works: count and response shape
curl -s 'https://librivox.org/api/feed/audiobooks?genre=%5EDramatic%20Works&format=json&limit=1&extended=1' | jq '.books[0] | keys'
curl -s 'https://librivox.org/api/feed/audiobooks?genre=%5EDramatic%20Works&format=json&limit=1000&fields[]=id' | jq '.books|length'

# 6. NARA OWI digitized audio (needs an API key in x-api-key)
curl -s -H "x-api-key: $NARA_KEY" 'https://catalog.archives.gov/api/v2/records/search?q=%22Office%20of%20War%20Information%22&typeOfMaterials=Sound%20Recordings&availableOnline=true&limit=1' | jq '.body.hits.total'

# 7. loc.gov audio with radio subject (JSON API)
curl -s 'https://www.loc.gov/audio/?q=radio+broadcast&fo=json&c=1' | jq '.pagination.of, .results[0] | {title,date,rights:.rights}'
curl -s 'https://www.loc.gov/search/?q=office+of+war+information+radio&fa=online-format:audio&fo=json&c=1' | jq .pagination.of

# 8. AAPB: does a public API exist, and how many radio items are PD/online?
curl -sI 'https://americanarchive.org/api.json?q=radio+drama&rows=1'

# 9. Europeana open-licensed sound radio programs
curl -s "https://api.europeana.eu/record/v2/search.json?wskey=$EUROPEANA_KEY&query=h%C3%B6rspiel+OR+%22radio+drama%22&qf=TYPE:SOUND&reusability=open&rows=0" | jq .totalResults

# 10. Wikimedia Commons: radio audio files with PD templates
curl -s 'https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Radio_programs&cmtype=subcat&cmlimit=500&format=json' | jq '.query.categorymembers|length'
```

Also measure, by hand, for the rights track:
- the terms pages of radioechoes.com and oldtimeradiodownloads.com;
- whether Radio Spirits publishes a licensed-series list (the claims witness);
- the CCE / Copyright Office for radio **script** registrations and renewals of the top
  50 series (a Decision 157-style pass);
- the text of 17 U.S.C. §1401(a)(2) and (c) (the schedule; the non-commercial-use
  notice);
- the Paley, Smithsonian, LAC/CBC and LOC OWI online holdings (not searched this
  session).

---

## Sources

- https://archive.org/services/collection-rss.php?collection=oldtimeradio
- https://ia-petabox.archive.org/details/oldtimeradio?sort=titleSorter&and%5B%5D=mediatype:%22audio%22&and%5B%5D=firstTitle:P
- https://archive.org/details/OTRR_Home_Page
- https://archive.org/details/OTRR_Old_Radio_Times_Newsletters
- https://archive.org/details/OTRR_Line_Up_Singles
- https://archive.org/details/OTRR_Behind_The_Mike_Singles
- https://archive.org/details/OTRR_Mel_Blanc_Singles
- https://archive.org/details/OTRR_Red_Horse_Ranch_Singles
- https://archive.org/details/OTRR_Hallmark_Single_Episodes
- https://archive.org/details/OTRR_All_Star_Western_Theatre_Singles
- https://archive.org/details/OTRR_Tarzan_Singles_TLotJ
- https://archive.org/details/OTRR_Case_Dismissed_Singles
- https://archive.org/details/Singles_And_Doubles_Singles_A-C
- https://archive.org/details/Singles_And_Doubles_Singles_T-Z/
- https://archive.org/details/lumedwards
- https://archive.org/details/old-time-radio-collection
- https://archive.org/details/UniqueOldTimeRadioEpisodes
- https://archive.org/details/ChristmasOTRCollection
- https://archive.org/details/OTRCatalogs
- https://archive.org/details/oldtimeyradioshowscollection
- https://archive.org/details/gang-busters-1955-04-02-885-the-case-of-the-mistreated-lady
- https://archive.org/details/RelicRadioShow
- https://archive.org/details/WWII_News_1939
- https://archive.org/help/aboutsearch.htm
- https://archive.org/developers/metadata-schema/index.html
- https://blog.archive.org/?p=24455
- https://blog.archive.org/2025/03/10/public-domain-spotlight-librivox/
- https://tvcrit.com/sitcom/2016/06/01/lots-of-old-time-radio-are-online
- https://database.radiopreservation.org/catalog/collection_687
- https://otrr.org/public_html/Pages/index.htm
- https://otrr.org/pg01b_ms.htm
- https://otrr.org/pg01d_help.htm
- https://otrr.org/pg02c_direct.htm
- https://otrr.org/archives.html
- https://www.otrr.org/OTRRLibrary/copyright.html
- https://www.otrr.org/FILES/Articles/Ryan_Ellett_Articles/The Script Library Final.pdf
- https://librivox.org/api/info
- https://forum.librivox.org/viewtopic.php?p=937940
- https://wiki.librivox.org/index.php/Dramatic_Readings_and_Plays
- https://wiki.librivox.org/index.php/Information_on_coordinating_dramatic_readings
- https://librivox.org/uploads/dlolso21/Librivox%20DW%20Stats%202020.pdf
- https://forum.librivox.org/viewtopic.php?p=1214796
- https://github.com/ipfs-inactive/archives/issues/189
- https://creativecommons.org/2006/12/05/librivox/
- https://c.enwp.org/wiki/Template:LibriVox_public_domain
- https://genericradio.com/
- https://genericradio.com/workshop
- https://genericradio.com/radiokit
- https://www.bearmanormedia.com/products/lady-of-the-press-radios-lost-romantic-mystery-serial-edited-by-larry-groebe-of-the-generic-radio-workshop
- https://www.simplyscripts.com/2015/09/12/old-time-radio-script-saturday
- https://www.informationnow.org.uk/organisation/radioechoes-com/
- https://apps.apple.com/us/app/id1493221239
- https://apps.apple.com/us/app/-/id455577974
- https://www.cbsrmt.com/faq.html
- https://podcasts.apple.com/podcast/id256493656
- https://podnews.net/podcast/i4811
- https://podnews.net/podcast/i45rl
- https://podcastrex.com/shows/the-horror-old-time-radio
- https://hi.player.fm/series/rusc-guide-to-old-time-radio
- https://www.rfcafe.com/miscellany/factoids/rusc-r-u-sitting-comfortably.htm
- https://techlearning.com/resources/old-time-radio-library
- https://trademarks.justia.com/owners/rspt-llc-987513/index.html
- https://radioarchives.com/Gunsmoke_Volume_4_p/ra354d.htm
- https://shop.playaway.com/products/old-time-radio-best-of-the-west-gunsmoke-1191
- https://otrcat.com/p/command-performance
- https://www.otrcat.com/p/stars-for-defense
- https://otrcat.com/patriotic-old-time-radio
- https://www.greatdetectives.net/detectives/my-favorite-old-radio-research-resources/
- https://www.greatdetectives.net/detectives/about/copyright-questions/
- https://www.quietplease.org/forum/general/-logs-compared-and-the-results-352.html
- https://www.jjonz.us/RadioLogs/index.htm
- https://www.otrsite.com/articles/art1004.html
- https://otrsite.com/
- https://otrsite.com/logs/loga1031.htm
- https://search.worldcat.org/oclc/423622871
- https://tile.loc.gov/storage-services/service/gdc/gdcfindingaidpdfs/rs020003/rs020003.pdf
- https://database.radiopreservation.org/catalog/collection_1343
- https://www.infodocket.com/2021/05/06/radio-research-project-manuscript-collection-now-available-online-from-the-library-of-congress/
- https://www.loc.gov/item/jukebox-4635
- https://www.loc.gov/item/jukebox-127119/
- https://blogs.loc.gov/now-see-hear/2019/02/copyright-breakdown-the-music-modernization-act/
- https://www.everycrsreport.com/reports/LSB10181.html
- https://archive.techdirt.com/articles/20180917/17305440659/compromise-music-modernization-act-will-bring-old-sound-recordings-into-public-domain-tiptoe-towards-orphan-works-solution.shtml
- https://openvault.wgbh.org/collections/american-archive-of-public-broadcasting
- https://openvault.wgbh.org/about
- https://blog.americanarchive.org/wp-content/uploads/2018/12/aapb_librarycommunicationskit.pdf
- https://wnyc.org/digital-archives-collections
- https://wnyc.org/municipalcollection
- https://nycrecords.access.preservica.com/new-york-city-municipal-broadcasting-organizations
- https://www.archives.nyc/blog/2024/5/31/100-years-of-wnyc
- https://tvradiolibrary.org/about-the-library
- https://www.lib.umd.edu/NPBA
- https://digital.lib.umd.edu/node/37
- https://finding-aids.library.umkc.edu/repositories/2/resources/285
- https://library.umkc.edu/goldin-collection/
- https://database.radiopreservation.org/catalog/collection_715
- https://info.umkc.edu/specialcollections/about
- https://www.infodocket.com/2014/02/09/massive-marr-sound-archives-at-u-of-missouri-kansas-city-will-move-into-robotic-storage-unit/
- https://data.beeldengeluid.nl/id/dataset/0006
- https://data.beeldengeluid.nl/id/dataset/0007
- https://commons.wikipedia.com/wiki/File:Baseball_game_(1916,_Weber_%26_Fields).mp3
- https://pro.europeana.eu/index.php/post/music-heritage-resources-for-the-europeana-challenge
- https://library.assumption.edu/digitalmedia/audio
- https://projects.dharc.unibo.it/musow/view-1635268063-583946
- https://leuven2012.europeana.eu/post/new-interactive-player-europeana-radio-launches-as-an-outcome-of-europeana-sounds-project
- https://ivir.nl/nl/?p=19247
- https://www.nfsa.gov.au/collection/curated/nfsa-radio-series-collection-amended
- https://www.nfsa.gov.au/collection/curated/asset/82285-excerpt-dr-paul-radio-serial-1963
- https://www.nfsa.gov.au/collection/item/marie-antoinette-radio-serial-1939
- https://www.infodocket.com/2014/10/15/big-media-data-bbc-genome-now-live-data-about-every-radio-tv-programme-ever-broadcast-by-bbc/
- https://www.advanced-television.com/?p=178221
- https://www.dennismspragg.com/wp-content/uploads/2025/03/THE-ARMED-FORCES-RADIO-SERVICE.pdf
- https://archives.nypl.org/rha/20439
- https://www.nypl.org/research/research-catalog/bib/b11079575
- https://www.trumanlibrary.gov/print/pdf/node/142740
- https://www.archives.gov/research/catalog/help/api-getting-started
- https://unwritten-record.blogs.archives.gov/2022/08/23/a-users-guide-to-world-war-ii-era-radio-in-the-national-archives
- https://database.radiopreservation.org/catalog/collection_1347
- https://openhistoryhub.com/t/office-of-war-information-record-group-208/3822
- https://www.jfklibrary.org/node/437251
- https://jfklibrary.org/asset-viewer/archives/usiaau-041-r01
- https://en.wikipedia.org/wiki/Stars_for_Defense
- https://vintageradioshows.com/shows/guest-star-radio
- https://www.ortigasfoundationlibrary.com.ph/collections/library-holdings/treasury-star-parade
- https://craphound.com/news/2009/07/19/when-sysadmins-ruled-the-earth-full-cast-audio-drama/
- https://www.sffaudio.com/page/572
- https://netzpolitik.org/2010/little-brother-als-hoerbuch/
- https://www.uni-saarland.de/en/fachrichtung/geschichte/institut/fachdidaktik-geschichte/gudig-die-lernwerkstatt-geschichtsunterrichtdigital/der-grosse-gudig-werkzeugkasten/audio.html
- https://www.musicbusinessworldwide.com/nmpa-hits-spotify-with-extensive-takedown-action-over-unlicensed-songs-in-podcasts
- https://copyrightandtechnology.com/2019/04/27/podcasting-leaves-the-copyright-garden-of-eden/
- Internal precedent: /home/user/Archive-Watch/tools/probe_collections.py, /home/user/Archive-Watch/tools/build-catalog.mjs, /home/user/Archive-Watch/tools/fetch_archive_own_meta.py
