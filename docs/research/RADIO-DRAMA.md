# A public-domain radio drama app — research (2026-10-17)

> **STATUS: RESEARCH COMPLETE, NOTHING BUILT.** The owner will build it in a
> future session from an updated Universal App Template. This file is the
> synthesis and the starting point; the evidence is in seven detail files under
> `docs/research/radio/`. Every external claim there carries a source URL, and
> anything not confirmed from a primary source is marked UNVERIFIED. The early
> drafts were search-only (the environment's network policy blocked direct
> fetches); the owner opened access mid-session, and the facts marked
> **MEASURED 2026-10-17** were then checked with the command printed beside them.

Owner, 2026-10-17: *"I'd really like to develop a new app in a similar vein to
Archive Watch, but instead of leveraging public domain video, I'd like to have a
public domain audio app that is specifically focused upon radio dramas, plays
and other public domain radio shows. ... you need to conduct extensive research
on what is available in repositories around the web and any metadata that is
easily usable for this new app. ... The result of this loop should be all of the
design, metadata, and content research necessary to start working on the app in
a future session. It should have all of the methods well documented for
immediate use."*

| File | Covers |
|---|---|
| `radio/01-content-sources.md` | Every repository holding radio drama, ranked: what, access, terms, rights posture, role. §0 has 22 measured facts |
| `radio/02-rights.md` | US law for pre-1972 recordings and scripts, read from the statute; the proposed two-layer audio rights audit; ten owner questions |
| `radio/03-metadata-sources.md` | The radio equivalents of TMDb/TVmaze/Wikidata: episode logs, Wikidata classes, newspaper listings, artwork, scripts; the enrichment cascade |
| `radio/04-audio-platform-engineering.md` | Per-platform audio engineering (Apple incl. CarPlay/Watch, Android incl. Auto/TV, Roku, web, speakers), the audio pipeline, review pitfalls |
| `radio/05-design-research.md` | Precedent teardown, 697 measured App Store reviews, the episodic model, "Tonight in 1947", IA, 21 proposed binding rules, twelve owner questions |
| `radio/06-archive-watch-reuse.md` | Every Archive Watch tool, workflow and decision judged reuse / adapt / replace for audio; transferable lessons; the new repo's layout |
| `radio/07-archive-org-ingest.md` | The archive.org corpus in depth: item and file structure, filename grammar, APIs, the ingest algorithm and dedupe |
| `tools/probe_otr_corpus.py` | Stdlib-only probe of the archive.org corpus (counts, formats, filename hit rates, hours, duplicates) |

---

## 1. The verdict in one paragraph

The content exists in quantity and the engineering is well understood. **The
rights are the whole question.** archive.org's `oldtimeradio` collection holds
8,952 items (MEASURED), mostly whole series with hundreds of MP3s each; the Old
Time Radio Researchers (OTRR) sets inside it are well dated and titled; the
APIs are the ones Archive Watch already calls. But under current US law nearly
every network-era radio recording is still protected: sound recordings had no
federal copyright before 1972, so they never had a renewal to miss, and the
2018 Music Modernization Act gives most broadcasts federal protection until
**15 February 2067** (§3). The film model that built Archive Watch's catalog,
public domain by non-renewal, does not carry over. What is clean is narrow:
LibriVox's dramatic recordings (640 projects, MEASURED, dedicated to the public
domain), programs the US government made itself, Creative Commons drama with
evidence, and published recordings old enough to have aged out (1925 and earlier
in 2026, one more year every January). **Whether the app also carries the large
middle — unclaimed orphan broadcasts with no claim a reader can open — is the
owner's first decision (§7, Q1), and it decides whether this is a LibriVox-and-
government app or an old-time radio app.** Everything else in this file is
ready either way.

---

## 2. What is out there (content)

Ranked from `radio/01-content-sources.md` §"Sources to build on":

| Source | Role | Measured / key fact |
|---|---|---|
| **archive.org `oldtimeradio`** | Primary corpus | 8,952 items (8,808 audio); 7,276 have no year field; an item is usually a series or set |
| **OTRR sets** (`OTRR_*`, collection `lumedwards`) | Spine of the corpus; best-copy ranking | 526 `OTRR_*` items, 692 in `lumedwards`; "Certified Accurate" 83, "Certified Complete" 63, "Maintained Set" 33 (from descriptions) |
| **LibriVox** (`api/feed/audiobooks`) | The clean full-cast drama pool | 640 distinct drama projects (Dramatic Readings 266, Plays 271, Drama 394 genres), 574 English; 64 kbps MP3 per section on archive.org; API `limit` capped at 500; Python's default User-Agent gets 403 |
| **US government** (AFRS, Treasury, OWI, VOA) | Second clean pool, with caveats | 238 AFRS items in `oldtimeradio`; NARA's 1,216 OWI MP3s are labeled "Restricted - Possibly: Copyright" (downgraded); AFRS rebroadcasts of network shows are NOT government works |
| **American Archive of Public Broadcasting** | Small supplement | `api.json` answers with no key; 214 online items match "radio drama" |
| **Creative Commons modern audio drama** | Admitted one show at a time | Only with corroborated evidence (Decision 140) |
| **Commercial sellers** (Radio Spirits, OTRCAT, RUSC) | **Never a source** | Useful as a list of rights CLAIMS (a licensed CD closes the noncommercial-use route) |
| **RadioEchoes** (5,069 series, 129,158 episodes) | **The series/episode spine** (owner, 2026-10-17); never the audio source | Human genre tags; dated episode pages; audio on its own S3; no API or terms |
| **Institutional archives** (LOC NBC collection, UMKC Marr, Paley, WNYC, UMD) | Evidence and metadata only | Reading rooms, not feeds |
| **Europeana** | Dropped | 95 radio-drama sound items, none openly licensed |

**License tags on archive.org OTR are noise** (MEASURED): 74% carry none; about
1,000 carry CC BY-NC-ND or BY-ND tags that uploaders had no standing to grant on
1940s network shows; 916 carry the retired public-domain license and 434 the PD
Mark, all assertions. `licenseurl` may neither admit nor exclude an item.

---

## 3. Rights: why audio is not video, and what survives

The owner asked, 2026-10-17: *"How does the modernization act make it so that
audio is copyrighted but not video. That doesn't make sense? These recordings
aren't music. And clearly public domain recordings (by age) should still be
available."* The answer, in `radio/02-rights.md` (top) with the statute quoted:

- **"Sound recording" is any recorded sound**, drama and speech included, except
  a film's soundtrack, which belongs to the film (17 U.S.C. §101). The Act's name
  says music; its Title II covers everything.
- **The split predates 2018.** Films had federal copyright from 1912, with notice
  and renewal; most never renewed and fell into the public domain. Recordings had
  **no federal copyright before 15 Feb 1972**, only state law with no formalities
  and no end, which the 1976 Act preserved until 2067. A 1940s broadcast never
  entered the federal system, so it had no renewal to miss.
- **The 2018 Act federalized that protection and SHORTENED it** for older
  published recordings: pre-1923 free since 2022; 1923-46 free 100 years after
  publication (1925 freed 1 Jan 2026; 1926 frees 1 Jan 2027); 1947-56 after 110
  years; everything else, **including every unpublished recording**, 15 Feb 2067.
- **Public domain by age stays in**, recomputed each January (Decision 137's
  calendar rule; the audio line is `today.year - 101`). Its limits: little radio
  drama survives from 1925 or earlier, and a broadcast is not a publication —
  the Copyright Office's 2011 report says radio programs "have been, and still
  are, considered 'unpublished'".

Two further layers (`02-rights.md` §§3, 5, 1.4):

- **The script is a separate copyright and won the leading case.** *Lone Ranger
  Television v. Program Radio* (9th Cir. 1984): duplicated radio tapes infringed
  the registered, renewed scripts. A script **registered and not renewed** is
  public domain — the one evidence-based rescue, found in the Catalog of Copyright
  Entries' drama volumes (the `tools/fetch_cce_renewals.py` pattern).
- **The noncommercial-use route** (§1401(c), 37 CFR 201.37) suits a free, ad-free
  app in principle: a documented search, a notice ($50 each, one per recording),
  90 days without an objection, US only, and it never clears scripts or music.
  Realistic for a curated few hundred episodes, not a catalog. Whether an app in
  Apple's and Google's stores counts as noncommercial is a lawyer's question.
- **The rights owners' claims database is machine-readable** (MEASURED): the
  Copyright Office's pre-1972 schedules, 299,447 entries; Sony has claimed CBS
  news broadcasts and Tommy Dorsey broadcasts; no hits for The Shadow, Suspense,
  Fibber McGee, Command Performance or Lum and Abner. Known claims elsewhere: The
  Shadow (Condé Nast, licensed to Radio Spirits), The Lone Ranger (the 1984 case),
  Lum and Abner (takedowns), X Minus One (copyrighted source stories), Lux and
  Screen Guild (studio film adaptations — matchable against Archive Watch's
  existing `cce_renewals.json`).

**Estimate, labeled as reasoning over measured item counts, not a per-episode
measurement:** a strict tier (government, LibriVox, corroborated CC, pre-1926
records) is ~3-8% of the corpus; a curated noncommercial-use program adds ~1-5%;
keeping unclaimed orphans brings it to ~55-75%; ~25-40% hides on evidence, and
those are disproportionately the famous series.

The proposed audit is in `02-rights.md` §10: `audit_audio_rights.py`, a
recording layer and an underlying-work layer, each an ordered `bucket()` as in
`tools/audit_rights.py` (hides before rescues, first match wins), the stricter
layer wins, and owner-tier buckets surface as their own state, never silently as
keep.

---

## 4. The data model

Old-time radio does not have the shape of a film catalog, nor quite of TV:

- **The episode is the catalog row; the archive.org item is provenance.** An
  item usually holds a whole series, year or set (`radio/07` §1). An episode is
  identified by item + file, then by its natural key.
- **The natural key is (series, broadcast date).** It is in the filenames:
  OTRR's canonical `Series_YY-MM-DD_epNNN_Title[_aka_Alt][_epAFRTS]`, `xx` for
  unknown parts, and at least five other date spellings (`radio/07` §2, with a
  real example of each and the regexes).
- **Script → broadcast → recording.** A script is performed more than once
  ("Sorry, Wrong Number" aired on Suspense eight times, 1943-60; X Minus One's
  first fifteen re-performed Dimension X scripts); a broadcast survives as several
  recordings (network copy, AFRS disc with the commercials removed and sometimes a
  new title, East/West coast repeats, many transfers). Recordings fold into one
  broadcast card as versions (Decisions 040/143/158); performances of one script
  link to each other.
- **Duplicates** are grouped on series + date, confirmed by duration within
  max(90 s, 5%) and md5; a same-date group whose durations disagree is two things
  (partial, AFRS cut, coast repeat). Titles alone are never a key.
- **A series is a list of dated runs, and each run has a kind**: anthology,
  continuing character, serial (arcs, cliffhangers), daily strip/soap,
  comedy-variety, news, broadcast day. Shows changed kind mid-life (Johnny
  Dollar's five-part stories of 1955-56). Kind decides queueing (`radio/05` §2).
- **Every field carries its source** (Decision 124), and every date has its
  witness, because the logs disagree.

---

## 5. Methods, for immediate use

These are the recipes a build session can run. Each points at the section with
the commands or code.

### 5.1 Enumerate and split the corpus
1. Run `python3 tools/probe_otr_corpus.py` (stdlib only) for today's counts,
   formats, filename hit rates and duplicate rate (`radio/07` §"To measure").
2. Enumerate items with the Scrape API (cursor paging) over
   `collection:oldtimeradio`, `collection:lumedwards`, `identifier:OTRR_*` and
   `collection:librivoxaudio` with the drama genres; fetch `/metadata/{id}` for
   `files[]` (name, format, size, length, md5, track/title tags).
3. Split each item into episodes; parse filenames with the regex families in
   `radio/07` §2; fall back to ID3 tags (the measured 128 kbps Suspense upload
   carries the air date in clean tags); record `(series, date, number, title)`
   and provenance.
4. Pick one playable file per recording with `pick_audio` (Archive Watch's
   `archive_lib.pick_video` adapted: keep the private-file and old-revision
   guards, Decision 104; rank MP3 by MEASURED bitrate, not the format label —
   archive.org labeled a 32 kbps file "64Kbps MP3").
5. Dedupe (§4) and keep forwarding aliases for merged ids (Decision 085).
6. Be polite: honest User-Agent, sequential with backoff, only 404/410 means
   gone; email info@archive.org before the first full harvest.

### 5.2 Enrich (the cascade, `radio/03` §"Recommended cascade")
1. Filename + ID3 → the natural key.
2. Series → Wikidata (CC0; `radio series` Q14623351; Suspense is Q1548940 with
   P1113 = 946 episodes), checked against years and network. SPARQL in
   `radio/03` "To measure". Few episodes exist on Wikidata; there is no
   RadioGOLDINdex property — proposing one is a contribution back.
3. **The spine is RadioEchoes** (owner, 2026-10-17: *"Can we use radioechoes as
   the spine and archive.org as the content source?"* — yes; `radio/03`
   addendum): 5,069 human-genred series, each a page of dated episodes with
   title, length and a `series_YYYY-MM-DD_title.mp3` key (Suspense: 917,
   MEASURED). No API or stated terms; robots allows all at a 10-second crawl
   delay. Its audio stays on its own S3 and is never played; archive.org is the
   content source, and a spine episode with no archive.org match is a "wants"
   entry. It lacks cast, credits and network, so:
4. Episode facts from independent witnesses: RadioGOLDINdex
   (radiogoldin.library.umkc.edu, ~123,000 programs, the best credits and the
   date tie-breaker), OTRR logs, Wikipedia episode lists, Digital Deli Too,
   Jerry Haendiges. **Facts are free to take** (*Feist v. Rural*, 1991; the owner
   asked, 2026-10-17, *"If Google can index the Goldin's index, why would we need
   special permission to do so?"* — we do not, for facts); prose descriptions are
   not. Scrape slowly with credit and a link back on every episode, and ask
   Goldin/UMKC, OTRR and RadioEchoes for exports in parallel. MEASURED: the UMKC host has no
   robots.txt and states no terms.
5. Confirm dates against newspaper listings: JJ's Newspaper Radio Logs (45,000+,
   1930-60), Chronicling America on loc.gov (keyless JSON), Radio Guide / Radio
   Mirror scans on WorldRadioHistory.
6. Art last: typographic cards by default; Wikimedia Commons publicity photos
   only where the file page shows the no-notice/non-renewal evidence; never
   uploader art.
7. Verify every match against the item's own signals, runtime included
   (Decision 026); when a match is cleared, remove what it filled (Decision 150).

### 5.3 Judge rights
Implement `audit_audio_rights.py` from `radio/02` §10 with its machine-readable
claim sources, in this order of value: the pre-1972 schedules (new
`fetch_p72_schedules.py`, Solr proxy measured), CCE drama volumes (a parser
beside `fetch_cce_renewals.py`), `cce_renewals.json` for Lux/Screen Guild, the
Copyright Office's online records for 1978+, archive.org darkened items and
`takedowns.json`. Each test carries a control that fails (ENGINEERING-PROCESS §3).

### 5.4 Prepare the audio
Measure loudness in CI with ffmpeg's `ebur128` filter (~10 s per 30-minute file,
against ~53 s for `loudnorm`), store the gain in the catalog, apply it at
playback; never re-encode or re-host (`radio/04` §8). The two measured Suspense
uploads read -18.85 and -18.39 LUFS; confirm a playback target near -18 LUFS on a
200-file sample. Never trim silence; chapter the commercials, never skip them.
Transcripts: whisper.cpp with voice-activity detection, a hallucination gate and
a human sample per series, for search first and labeled automatic where shown
(Decision 039b's lesson still binds: organ stings and hiss make it invent words).

### 5.5 Publish
The Archive Watch data plane carries over: catalog source and SQLite on a GitHub
Release (`catalog_release.py`, `sqlite_publish_guard.py`, `merge_catalogs.py`,
`catalog_delta.py` as-is), a Pages index for the web, editorial JSON, the
workflow-health auditor. The new repo's full `tools/` and workflow layout, and
the do-not-copy list, are `radio/06` §5.

---

## 6. Design and platforms

From `radio/05` (design) and `radio/04` (engineering):

- **The existing OTR apps are weak** (697 US App Store reviews of nine apps,
  MEASURED): billing is the top complaint (90), then crashes (50), no resume, no
  continuous play, ads (16), unlabeled controls that shut out blind listeners,
  wrong descriptions and duplicates. Free, no ads, clean data and accessibility
  are already a differentiator.
- **Bedtime and the car are the uses.** 47 reviews describe falling asleep to the
  app, 24 mention the car. The worst failure is a player that "NEVER turns off so
  it wakes you"; the most praised fades out. Rule R20: a sleep timer that offers
  "end of this episode" first and fades.
- **Tonight in 1947** best passes the learning test: a real network evening
  rebuilt from newspaper listings, played on Archive Watch's one-clock channels
  (Decision 144), with a stated gap where no recording survives (rule R9 — never
  a substitute). Precedent: WJSV's complete broadcast day of 21 Sept 1939, on the
  National Recording Registry.
- **Cross-links to Archive Watch films are real**: the catalog index holds
  *Sorry, Wrong Number* (1948) and *The 39 Steps* (1935), whose radio versions are
  sourced; about ten other Lux-adapted films are present, with a probe to join a
  Lux log. Each side is judged on its own rights (R19).
- **IA**: Listen · Series · Radio · Search · Library; four car tabs (Continue,
  Radio, Series, Downloads), lists not grids; typographic cards; genres take the
  semantic accents and chrome never does. 21 proposed binding rules (R1-R21) in
  `radio/05` §9, each with its reason.
- **Platform rules that change the build** (`radio/04`, read on primary pages
  2026-10):
  - CarPlay needs the `com.apple.developer.carplay-audio` entitlement (request at
    developer.apple.com/contact/carplay); at most 4 tabs and 5 screens deep; no
    lyrics, read as no transcripts, on the car screen; manual signing, so it goes
    into the cloud signing pipeline.
  - Android Auto: Gemini/Assistant voice, no autoplay at start, content within
    10 s; every update waits on a manual car review, so never prototype on the
    production track.
  - Android TV REVERSES Archive Watch: background audio must show a Now Playing
    card (TV-NP); keep the media session on.
  - Roku: play through a Video node with `disableScreenSaver` only while playing.
  - Web: archive.org storage nodes now answer ranged GETs on MP3 with
    `access-control-allow-origin: *` (MEASURED 3/3), which contradicts
    `docs/CATALOG-CONTRACT.md` (measured 2026-06-09 for video). Re-check an MP4
    before amending Archive Watch's contract. iPhone home-screen web apps still
    cannot be relied on for background audio: send iPhone listeners to the app.
  - App Store 4.3(a) "Don't create multiple Bundle IDs of the same app" is the new
    risk for a second app from the same template; 4.2.2 exempts "catalogs";
    the 5.2.3 response needs a radio version, and the app must never export MP3s.

---

## 7. Decisions reserved for the owner

Consolidated from `radio/02` §11 and `radio/05` §10; the exact wording of each is
there. Ordered by what they unblock.

| # | Question | Blocks |
|---|---|---|
| Q1 | **Orphans**: show only the strict tier; show unclaimed broadcasts and hide on the first claim; or a curated noncommercial-use set? | The size and identity of the catalog |
| Q2 | **A separate app, or a Radio section in Archive Watch?** (App Store 4.3(a) bears on it; the people/works graph is shared either way) | Repo, bundle id, template choice |
| Q3 | File noncommercial-use notices ($50 each), after a lawyer confirms a free store app is noncommercial? | Tier B |
| Q4 | Unregistered network scripts: protected (hide) or follow Q1? | The underlying-work layer |
| Q5 | Commercially sold series with no takedown: hide? | `rec_commercially_exploited` |
| Q6 | AFRS originals with civilian stars and songs: keep as government work? | The government pool |
| Q7 | Music and variety shows: the drama rule or stricter? Non-US productions hidden unless licensed? Post-1972 series hidden unless licensed? General takedowns hide the whole series? | Remaining buckets |
| Q8 | WWII propaganda broadcasts under Decision 149's "never recommended, always findable"? | Recommendation gates |
| Q9 | Default copy when both a domestic network recording and an AFRS disc survive: the domestic copy with its commercials? | Version ranking |
| Q10 | Broadcast seasons ("1949-50") or calendar years; how "Tonight in [year]" picks its date and whether partly surviving evenings are offered | Series pages, the Radio tab |
| Q11 | Genre accents: reuse three Archive Watch hues with new meanings, or new hues; horror its own color? | The design system |
| Q12 | Generated transcripts where no script survives; smart speakers core or side door; Listen Together in v1? | Scope of v1 |

---

## 8. The first build session, in order

1. Owner answers Q1 and Q2 (the rest can follow).
2. Run `tools/probe_otr_corpus.py` and the LibriVox drama enumeration; record the
   numbers as MEASURED with the date.
3. Stand up the new repo from the template with the `radio/06` §5 pipeline
   layout; copy the plumbing as-is; write `CATALOG-CONTRACT.md` for episodes
   first.
4. Build ingest (§5.1) against the clean pools first (LibriVox, government) so
   there is a lawful catalog on day one, whatever Q1 decides.
5. Build `audit_audio_rights.py` (§5.3) with its controls before any OTR item is
   published.
6. Enrichment (§5.2), loudness (§5.4), then the clients, CarPlay entitlement
   requested on day one because Apple's review of it is slow.
7. Send the outreach in parallel: RadioEchoes, Goldin/UMKC and OTRR (exports, and how OTRR's
   NC-ND applies), and info@archive.org before the first full harvest.

---

## 9. Found along the way, outside this research

- **A live Archive Watch defect** (`radio/06` §4): `discover_archive_collections.
  scrape_query` stops with a bare `return` on a failed response and
  `archive_lib.adv_search` returns `[]`, so a throttled call reads as "nothing
  found" — ENGINEERING-PROCESS §1's "absence is not evidence". Not fixed here.
- **archive.org CORS** on audio storage nodes (§6) contradicts
  `docs/CATALOG-CONTRACT.md`; it may have changed for video too. Not amended here.
