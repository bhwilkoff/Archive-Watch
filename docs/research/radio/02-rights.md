# Radio rights research: old-time radio, radio plays, public-domain audio

*2026-10-17 · research track 02 (RIGHTS) for the proposed sister app · nothing built*

## Verdict

1. **"Old-time radio is public domain" is, under current US law, false for nearly every network-era RECORDING.** Since 11 Oct 2018, 17 U.S.C. §1401 (Music Modernization Act, Title II) federally protects every sound recording fixed before 15 Feb 1972. Free so far: recordings *first published* before 1923 (since 1 Jan 2022), and those published 1923-1925 (100-year band, so **1925 is the newest free year in 2026**). Every recording NOT first published in 1923-1956, **including every unpublished one, runs to 15 Feb 2067** (§1401(a)(2)(B)(iv), quoted below). The Copyright Office's own 2011 report says radio programs "have been, and still are, considered 'unpublished' under copyright law because, with rare exceptions, they were not distributed in copies."
2. **The film model breaks here.** Archive Watch frees films through 1909-Act formalities (no notice, no renewal). Pre-1972 recordings never had formalities. They are "not subject to copyright under this title" (§301(c)) but are protected by §1401's separate prohibition. So "never registered" (OTRR's argument) proves nothing about a recording. For audio, "not knowing" means "protected, owner unknown", not "public domain".
3. **The SCRIPT is a second, independent claim, and it won the leading case.** *Lone Ranger Television v. Program Radio* (9th Cir. 1984) affirmed statutory damages and an injunction against a man who leased duplicated tapes of radio episodes. The court held the recordings were derivative works of the registered, renewed scripts. It also followed *Russell v. Price*: a derivative work in the public domain still infringes a script that is not. A script never registered has been under §303 since 1978 (a work made for hire runs to 120 years from creation). Distributing a phonorecord before 1978 did not publish it (§303(b); Compendium §2122.5(E)). A script registered (Class D) and **not renewed** is public domain. That is the one place the Catalog of Copyright Entries frees anything, and `tools/fetch_cce_renewals.py` is the pattern.
4. **Clean tiers are small:**
   - LibriVox ("all our recordings are public domain"; 183 dramatic-reading items on archive.org, measured)
   - US-government productions (§105), subject to a real open question in §5 about whether §105 reaches the §1401 right at all
   - Creative Commons drama with corroborated evidence (Decision 140)
   - commercial records published at or before the computed audio line (1925 in 2026)
5. **The noncommercial-use exception (§1401(c), 37 CFR 201.37) fits a free, ad-free app in principle, but is impractical at catalog scale.**
   - **One notice per recording**, unless the recordings share an album (broadcasts have none), at **$50 a notice** (37 CFR 201.3(c)(28)).
   - Each notice names a start and end date, applies **in the US only**, gives the owner a **90-day opt-out**, and needs our **own** search.
   - The search stops at the first find on Google/Bing, Spotify/Apple, licensed YouTube or new physical product on Amazon. A licensed Radio Spirits CD therefore closes it.
   - It never clears scripts or music. The Office says so: the composition "may require separate copyright clearance".
   - 10,000 episodes would cost about $500,000 in fees alone.
6. **The rights-owner schedules are machine-readable, and radio drama is absent from them.** The Copyright Office's pre-1972 schedule index answers a Solr proxy: **299,447 entries, measured 2026-10-17**. Record labels dominate. Sony scheduled CBS *news* broadcasts (93 Walter Cronkite, 4 Edward R. Murrow) and Tommy Dorsey radio broadcasts; UMG scheduled a Decca *Lone Ranger* record album (George W. Trendle). There were **zero hits** for The Shadow, Suspense, Fibber McGee, Command Performance or Lum and Abner. Absence from the schedules limits remedies (no statutory damages or fees, §1401(f)(5)), not rights.
7. **Recommendation:** a two-layer audit (recording and underlying work), hiding on any claim a reader can open. The large orphan middle is an **explicit owner decision** (Decision 027's reservation), not a code default. Strictly, the app is LibriVox + government + Creative Commons + pre-1926 records. As an OTR app it needs the owner to accept risk on unclaimed orphans.

> **Method note.** The first draft used only WebSearch. Network access then opened, and the statute (§§101, 105, 301(c), 303, 1401), 37 CFR 201.37 and 201.3, the Copyright Office's pre-1972 pages, Compendium III chapters 800/1900/2100, the 2011 report, the *Lone Ranger* opinion, OTRR's policy, LibriVox's policy and UK CDPA ss.13A/14 were read directly (quoted below). The schedules database and archive.org were measured. Still **UNVERIFIED** (secondary sources or general knowledge only): *Flo & Eddie* (N.Y. 2016), Canada and Australia terms, Superman/DC radio rights, the CBS Radio Mystery Theater rights holder, and *Dastar*.

> **The owner's question, 2026-10-17, and the answer.** *"How does the
> modernization act make it so that audio is copyrighted but not video. That
> doesn't make sense? These recordings aren't music. And clearly public domain
> recordings (by age) should still be available."*
> - "Sound recording" in 17 U.S.C. §101 is any fixation of sounds — speech and
>   drama included — except "the sounds accompanying a motion picture", which
>   belong to the film. The Act's name says music; its Title II does not.
> - The split is older than 2018. Films had federal copyright from 1912 and
>   with it notice and renewal formalities, so most fell into the public domain
>   by non-renewal. Recordings had NO federal copyright before 15 Feb 1972, only
>   state law with no formalities and no fixed end, which the 1976 Act left in
>   place until 2067. A 1940s broadcast never entered the federal system, so it
>   had no renewal to miss.
> - The MMA federalized that protection and SHORTENED it for older published
>   recordings (the table in §1.1).
> - **Yes: public domain by age stays in the app**, recomputed every 1 January
>   like Decision 137 (1925 and earlier published recordings in 2026, 1926 in
>   2027). The limits are that little radio drama survives from 1925 or earlier,
>   and that an unpublished recording (most broadcasts) is not freed by age
>   until 2067.

---

## 1. Federal protection of pre-1972 sound recordings (17 U.S.C. §1401)

### 1.1 The schedule (statute text, read 2026-10-17 at law.cornell.edu/uscode/text/17/1401)

§1401(a)(1): anyone who "without the consent of the rights owner, engages in covered activity with respect to a sound recording fixed before February 15, 1972, shall be subject to the remedies provided in sections 502 through 505 and 1203 to the same extent as an infringer of copyright." "Covered activity" (§1401(l)(1)) is anything the copyright owner of a post-1972 recording could control under §106 or §602: reproduction, distribution and digital audio transmission. Streaming in an app is covered.

§1401(a)(2)(A): the prohibition applies "(I) through December 31 of the year that is 95 years after the year of first publication; and (II) for a further transition period", and "(ii) shall not apply to any sound recording after February 15, 2067."

| §1401(a)(2)(B) | First published | Transition ends | Free from |
|---|---|---|---|
| (i) | before 1 Jan 1923 | 31 Dec 2021 ("3 years after the date of enactment") | 1 Jan 2022 |
| (ii) | 1923-1946 | "5 years after" the 95-year period (= 100 years) | 1 Jan of year + 101. **1925 freed 1 Jan 2026** |
| (iii) | 1947-1956 | "15 years after" (= 110 years) | 1 Jan of year + 111 (1947 freed 2058) |
| (iv) | "fixed before February 15, 1972, that is not described in clause (i), (ii), or (iii)" | **15 Feb 2067** | 15 Feb 2067 |

Clauses (i)-(iii) all say "first published", so **an unpublished recording of any age is in clause (iv)**.

**Computed age line** (Decision 137: never a literal): `AUDIO_PD_PUBLISHED_LAST = today.year - 101`, which is 1925 in 2026. It applies only to a recording with **evidence of publication**.

### 1.2 What "published" means for radio: read from the Copyright Office

- **Broadcast is not publication.** Compendium III §1908: "merely performing or displaying a work in public does not constitute publication… 'no matter how many people are exposed to the work'". Its first example is "Performing a song at a concert or on television or radio, regardless of the size of the audience."
- **The 2011 report** (copyright.gov/docs/sound/pre-72-report.pdf):
  - p. 7: "There are also recordings of old radio broadcasts, which were publicly disseminated by virtue of the broadcast, but in many cases are technically unpublished under the standards of the U.S. Copyright Act."
  - pp. 52-53: "radio programs have been, and still are, considered 'unpublished' under copyright law because, with rare exceptions, they were not distributed in copies… because they were not distributed in copies, radio broadcasts are comparatively ill-represented in the nation's libraries and archives."
- **Syndicated transcription discs are the genuinely open question.**
  - The 1976 Act definition (§101; Compendium §1906.1, which covers post-1978 works only) says "offering to distribute copies or phonorecords to a group of persons for purposes of further distribution, public performance… constitutes publication", e.g. offers to "broadcasters".
  - For pre-1978 *motion pictures*, Compendium §2122.6(A) says publication occurred on distribution "to film exchanges, film distributors, exhibitors, or broadcasters under a lease or similar arrangement. The U.S. Copyright Office generally considers syndication to be publication."
  - Against that, the courts' **limited publication** doctrine (Compendium §1905, citing *White v. Kimmell*): distribution "to a definitely selected group and for a limited purpose, and without the right of diffusion, reproduction, distribution or sale" is not publication. Transcriptions went only to stations, under lease, "not for sale to the public" (NYPL and classicradiogallery, per search).
  - No court has applied either rule to transcription discs (none found). **Practical effect is nil today:** even if a 1940 Ziv or AFRS syndication published the recording, clause (ii) frees it in 2041, not now.
- **Commercial phonograph records** are published. Under the 1909 Act the record published the *recording* but "did not constitute a publication of the recorded literary, musical, or dramatic work" (Compendium §2122.5(E), citing §303(b)).
- **LP and cassette reissues** (1960s-90s) of broadcasts: a first publication after 1956 still lands in clause (iv), 2067. 37 CFR 201.37(b)(2): a post-1972 remaster with only "mechanical contributions or contributions that are too minimal to be copyrightable" remains a pre-1972 recording.

**Consequence:** no network-era radio broadcast is public domain by age before 2041 at the very earliest, and 2067 in the ordinary case. An audio "age" bucket holds only pre-1926 commercial records.

### 1.3 Remedies and the rights-owner schedules

§1401(f)(5)(A)(i): statutory damages or attorney's fees "may be made… only if (I) the rights owner has filed with the Copyright Office a schedule that specifies the title, artist, and rights owner of the sound recording… and (II) the use occurs after the end of the 90-day period beginning on the date on which the information… is indexed." Without a schedule, the owner still has actual damages and injunctions (§§502-504). §1401(f)(1) applies fair use (§107) and the library and archive exceptions (§108). §1401(f)(3) applies the DMCA §512 safe harbor.

**Measured 2026-10-17.** The schedule search page (copyright.gov/music-modernization/pre1972-soundrecordings/search-soundrecordings.html) queries a Solr core through `proxy.php`. The fields are `title`, `alt_title`, `artist`, `alt_artist`, `rights_owner`, `album`, `label`, `isrc` and `index_date`.

| Query | Hits | Notes |
|---|---|---|
| all entries | **299,447** | |
| `title:"radio broadcast"` | 7 | Tommy Dorsey 1940-41 broadcasts (Arista/Sony) |
| `artist:cronkite` | 93 | Sony Music Entertainment, indexed 2019-06-20 |
| `artist:murrow` | 4 | Sony, incl. "Ed Murrow On The Retreat From Dunkirk, June 1940" |
| `artist:Trendle` | 6 | UMG, indexed 2021-07-08: "He Becomes The Lone Ranger", "He Finds Silver": a record album, not the broadcasts |
| `artist:welles` | 13 | UMG spoken-word records (Pericles, Donne…), not Mercury Theatre |
| `album:radio` | 69 | Alan Watts "Early Radio Talks" (rights owner Mark Watts) |
| Shadow / Suspense / "Command Performance" / "Fibber McGee" / "Lum" / "Inner Sanctum" / `rights_owner:radio`, `spirits`, `CBS`, `NBC`, `Conde` | **0** relevant | The "Gunsmoke" and "Dragnet" hits are the TV/film theme *records* |

**Reading:** the people who claim OTR drama (Radio Spirits, estates, Condé Nast) have not filed schedules. That lowers their remedies; it does not free the recordings. **CBS News broadcasts are scheduled by Sony**, so news and actuality audio (Murrow, Cronkite) must be hidden as `rec_schedule_claim`. This is a usable, machine-readable claim source.

### 1.4 The noncommercial-use exception (§1401(c); 37 CFR 201.37; read directly)

Statute, §1401(c)(1): "Noncommercial use of a sound recording fixed before February 15, 1972, that is not being commercially exploited by or under the authority of the rights owner shall not violate subsection (a) if" the user:
- (A) "makes a good faith, reasonable search for, but does not find, the sound recording (i) in the records of schedules filed in the Copyright Office… and (ii) on services offering a comprehensive set of sound recordings for sale or streaming";
- (B) "files a notice identifying the sound recording and the nature of the use"; and
- (C) the rights owner does not opt out "during the 90-day period beginning on the date on which the notice… is indexed".

§1401(c)(2)(A): "merely recovering costs of production and distribution… does not itself necessarily constitute a commercial use". §1401(c)(2)(B): "the fact that a person… also engages in commercial activities does not itself necessarily render the use commercial." §1401(c)(4)(A) is the safe harbor for a user who "made a good faith, reasonable search… without finding commercial exploitation."

The regulation (37 CFR 201.37):
- **Search order** ((c)(1)): the Office's schedules; **then** Google, Yahoo! or Bing (for sale as a download or "a new (not resale) physical product", or streaming); **then** one of Amazon Music Unlimited, Apple Music, Spotify or TIDAL; **then** YouTube "to determine whether [it] is offered under license by the sound recording rights owner"; **then** SoundExchange ISRC; **then** Amazon.com. "If the user finds the sound recording in a search category, the user need not search the subsequent search categories." Title AND featured artist are required. Search-engine results are read "until two consecutive pages return no such suggestive links." The search must fall within 90 days of filing. A **third party's search or notice cannot be relied on** ((c)(4)). Keep documentation three years ((c)(5)).
- **Notice content** ((d)(2)): legal name; title and featured artist; "the start and end dates of the use, and where the proposed use will occur (i.e., the U.S.-based territory of the use)". At the end date, "the user must cease noncommercial use" or re-search and re-file ((d)(6)(ii)).
- **US only** ((d)(3)): "Noncommercial use of a pre-1972 recording under this section is limited to use within the United States."
- **One recording per notice** ((d)(4)): "A notice of noncommercial use may not include proposed use for more than one pre-1972 sound recording unless all of the sound recordings include the same featured artist(s) and were released on the same pre-1972 album or other unit of publication." Unpublished broadcasts have no album, so it is **one episode per notice**.
- **Fee**: "$50" for a notice and "$50" for an opt-out (37 CFR 201.3(c)(28)-(29), read 2026-10-17).
- **After an opt-out**, the user "must wait one year" before re-filing ((e)(4)). False filings are penalized up to $1,000 per instance ((f)).
- The NNU filing page adds: "other copyrighted works embodied in the Pre-1972 Sound Recording… such as the musical composition, may require separate copyright clearance". It also tells users to "proceed cautiously" with foreign recordings (URAA, Circular 38B).
- The public NNU database page (search-NNUs.html) still reads "Once the Office beings indexing NNUs, the Office will make them publicly available on this webpage", and rendered no rows to a non-JavaScript fetch. **Whether any NNUs are indexed is unmeasured** (probe below).

**Can a free, no-ads, no-accounts app use it?**
- **Legally, plausibly.** Nothing in the statute or rule defines "noncommercial" further. Cost recovery and donations are expressly not "necessarily" commercial. App-store distribution is untested. **Ask counsel.**
- **Practically, only for a curated program**, not a catalog. One notice per episode at $50, re-filed when the stated end date passes, closed by any licensed CD on Amazon or licensed YouTube upload (the series people know are sold), US-only (geo-gate), and silent on scripts and music.
- A **curated NCU program** (e.g. 100-300 unexploited episodes whose scripts are lapsed, governmental or PD-sourced) costs $5,000-15,000 in fees. That is the defensible use.

### 1.5 §301(c): pre-1972 recordings are not "copyright", and why that matters

§301(c) (read directly): "Notwithstanding the provisions of section 303, and in accordance with chapter 14, no sound recording fixed before February 15, 1972, shall be subject to copyright under this title." §1401 is a *prohibition with copyright remedies*, owned by "the person that has the exclusive right to reproduce a sound recording under the laws of any State, as of the day before the date of enactment" (§1401(l)(2)). Consequences:
- the owner is whoever held state common-law rights in 2018, usually the producer, network, sponsor or packager, or its successor;
- the §105 government-work question in §5 below.

---

## 2. State law before 2018, and what §1401(e) actually preempts

- ***Capitol Records v. Naxos of America*, 4 N.Y.3d 540 (N.Y. 2005)** (nycourts.gov, Cornell LII, per search): New York common-law copyright protected pre-1972 recordings, even ones public domain abroad and remastered.
- ***Flo & Eddie v. Sirius XM* (N.Y. 2016)**: no public-performance right under New York common law. **UNVERIFIED**; Wikipedia's characterization only.
- **Correction to the first draft:** §1401(e) is "Preemption With Respect to Certain Past Acts". It preempts state common-law claims "arising from a digital audio transmission or reproduction that is made before the date of enactment" only where the transmitter would have qualified for the §114 statutory licence and paid royalties or settled. Forward-looking preemption is in §301(c): "the preemptive provisions of subsection (a) shall apply to activities that are commenced on and after the date of enactment of the Classics Protection and Access Act."
- **Relevance:** history plus one lesson. "Sound recordings weren't copyrightable before 1972, so they're PD" was wrong under state law before 2018 and is wrong under §1401 since. *Lone Ranger* itself awarded **state-law conversion** damages for the tapes (CA law) alongside the federal script claim. The 2011 report (fn. 130) reads it as "copies of radio broadcasts are not eligible for common law copyright protection but may still be protected pursuant to a conversion or unfair competition claim".

---

## 3. Underlying works: scripts, music, adaptations

### 3.1 Scripts

Compendium §804.4(E): "A radio play is a script prepared for broadcast on radio" (a dramatic work).

| Script status | Term | How to tell |
|---|---|---|
| Unpublished, never registered | §303(a): federal from 1 Jan 1978 with §302 terms: life + 70, or for a work made for hire the shorter of 95 years from publication / **120 years from creation**; never before 31 Dec 2002 | Default for network drama: a 1945 staff script runs to about 2065 |
| Registered as unpublished dramatic work (Class D, 1909 Act) and **renewed** | 95 years from registration | CCE "Dramas and Works Prepared for Oral Delivery" renewals (printed 1950-77); Copyright Office online records (1978+) |
| Registered (Class D), **not renewed** | expired after 28 years: **public domain** | CCE registration found, no renewal in year +27/+28 |
| Published with notice (script books, magazines) | 1909 rules; Decision 137's age line | CCE book and periodical renewals |

- **§303(b)** (Justia/Cornell, read via search; Compendium §2122.5(E) repeats it): "The distribution before January 1, 1978, of a phonorecord shall not for any purpose constitute a publication of any musical work, dramatic work, or literary work embodied therein." Transcription discs and LP reissues never published the scripts.
- ***Lone Ranger Television v. Program Radio Corp.*, 740 F.2d 718 (9th Cir. 1984)** (full opinion read at law.resource.org):
  - "By 1954 the company held federal copyrights in all fifteen scripts… The copyrights in all fifteen scripts remained valid, either in their original term or by renewal."
  - The defendant "bought reel-to-reel copies of the tapes from some collectors and re-mixed the recordings onto broadcast cartridges for radio play." The district court rejected "public domain" among other defenses and awarded "federal statutory damages, damages for state law conversion, attorney's fees", and the Ninth Circuit affirmed.
  - The holding: "Lone Ranger TV's valid copyrights in the underlying scripts secure to it… the right to produce derivative works from them. Program Radio has infringed this right… the contribution of independent expression by the actors… effectively created a new work". Quoting *Russell v. Price*: "although the derivative work may enter the public domain, the matter contained therein which derives from a work still covered by statutory copyright is not dedicated to the public."
  - **This is the controlling logic for the app:** a free recording of a protected script is not free.
- **Renewal rates are low:** about 780 Class D renewals in 1959, roughly 13% (Online Books Page blog, everybodyslibraries.com, 2009, per search snippet). **UNVERIFIED:** how many network scripts were ever registered (probe below). If few were, most scripts sit under §303's 120-year term.
- **The industry's view:** "most radio programs from the radio network era are copyrighted as unpublished scripts through 2050" (*Retailing Radio*, UC Press *Resonance*, per search snippet).

### 3.2 Music

Themes, bridges and songs are separate works. Published compositions follow the 1909 rules and Decision 137's line (1930 and earlier are free in 2026). Commissioned cues are unpublished works (§303). Variety shows (Benny, Kraft Music Hall, Command Performance) are full of then-current songs. **NCU explicitly does not clear compositions** (NNU instructions, quoted §1.4). Record `musicRisk` per series: `none | stock | popular_songs`.

### 3.3 Adaptations

- **Lux Radio Theatre (1934-55), Screen Guild, Academy Award Theater, Screen Directors Playhouse:** radio scripts derived from studio films and their sources. Under *Russell* and *Lone Ranger*, an episode adapting a still-protected film infringes the film's (or novel's) copyright. Archive holders warn researchers to obtain "all necessary rights" (OAC/Herrick, per search). Archive Watch's `shared/editorial/cce_renewals.json` (11,579 motion-picture renewals) and `corroborate_copyright.py` can match a Lux episode's adapted title and year against film renewals. A hit is a claim a reader can open.
- **X Minus One (NBC 1955-58), Dimension X:** adaptations of Asimov, Heinlein, Bradbury and others from *Astounding* and *Galaxy* (Open Culture, scifimike.com, per search). Each story is a separate, likely renewed, work. The series is also sold under licence (Blackstone/Hollywood 360, per search), so NCU is closed.
- **Adaptations of PD literature** (Poe; pre-1931 Doyle; Dickens): the source is free, but the radio script is a new work (§3.1).

---

## 4. Post-1972 recordings

A recording fixed on or after 15 Feb 1972 is ordinary federal copyright. Compendium §2122.5: only recordings "fixed and published" with notice between 1972 and 1977 were registrable then. Unpublished 1972-77 recordings came under §303 in 1978, and post-1978 ones under §302. *CBS Radio Mystery Theater* (1974-82), *Sears Radio Theater*, *Mutual Radio Theater* and NPR drama have no age route this century. **Hide unless licensed.** The CBSRMT rights holder (Himan Brown's estate or a licensee) is **UNVERIFIED**.

Measured: 123 `oldtimeradio` items have "Mystery Theater" in the title. Some may be *Molle Mystery Theater* (1940s).

---

## 5. US government works

§105(a) (read directly): "Copyright protection under this title is not available for any work of the United States Government." §101: "A 'work of the United States Government' is a work prepared by an officer or employee of the United States Government as part of that person's official duties."

- **AFRS original productions** (*Command Performance*, *Mail Call*, *G.I. Journal*, *Jubilee*):
  - War Department productions. *Jubilee* was exempt from the 1942-43 recording ban because of its War Department status; *Command Performance* was produced under the aegis of the Office of War Information (Wikipedia, per search).
  - On archive.org they carry uploaders' Public Domain Marks (`AfrsJubilee`, `AFRS-7/12/17/21`).
  - Measured: 238 `oldtimeradio` items mention AFRS or Armed Forces Radio; 24 have "Command Performance", 4 "Mail Call" and 5 "Jubilee" in the title.
- **A real open question nobody has litigated (found):** §105 bars "copyright protection **under this title**", and §301(c) says pre-1972 recordings are not "subject to copyright under this title"; they are protected by §1401's prohibition. A §1401 claim belongs to the holder of *state-law* rights as of 2018. Whether the federal government (or a performer, packager or network) held state common-law rights in an AFRS recording, and whether §105's policy reaches a §1401 claim, is **unresolved** (lawyer question). The practical risk is low, because the government does not sue over AFRS discs. But it is not the clean §105 answer the film side enjoys.
- **Caveats that do not depend on that question:**
  1. Civilian stars were not federal employees. Their performances are arguably not "prepared by" an employee.
  2. Songs keep their own copyrights.
  3. **AFRS rebroadcasts of network programs** (Benny, Fibber McGee, Bob Hope with commercials removed) are the network's and sponsor's works, not the government's. Judge them as the network series.
  4. The Library of Congress AFRTS collection: "restrictions may exist on copying, quoting, or publishing material" (per search).
  Dennis M. Spragg's AFRS history (dennismspragg.com) is the reference for telling originals from rebroadcasts.
- **Treasury** (*Treasury Star Parade*), **OWI**, **VOA**, **USDA**, **NASA**: §105 for employee-made material, with the same caveats. Municipal stations (WNYC) are not §105.

---

## 6. Commonly claimed "PD" series: the evidence

| Series | Claim found | Source | `oldtimeradio` items (title match, measured) | Proposed bucket |
|---|---|---|---|---|
| The Shadow | "trademarked and copyrighted property of Advance Magazine Publishers d.b.a. Condé Nast"; Radio Spirits licensed; 2017 CD set | Radio Spirits release via Wikipedia, thepulp.net (search) | 109 | `rec_rights_holder_claim` |
| The Lone Ranger | Scripts registered and renewed; infringement and statutory damages affirmed 1984; exclusive radio-leasing licensee (Charles Michelson Inc.) since 1965; trademark held by Classic Media (record last updated 2018); UMG schedules the Decca record album | 740 F.2d 718 (read); trademarkregistration.app; schedules DB | 16 | `work_script_renewed` + `rec_rights_holder_claim` |
| Lum and Abner | Radio Spirits takedown notices to archive.org as the Chester Lauck estate's agent (2010 blog) | randsesotericotr.podbean.com (search) | 7 | `rec_takedown` |
| X Minus One / Dimension X | Adaptations of copyrighted stories; licensed audiobooks | Open Culture; Blackstone (search) | 34 / 25 | `work_adapted_renewed` + `rec_commercially_exploited` |
| Lux / Screen Guild | Film adaptations; archive rights warnings | OAC, Temple (search) | 80 / 13 | per-episode match against `cce_renewals.json` |
| CBS news and actuality (Murrow, Cronkite) | **Schedules filed by Sony Music Entertainment** | schedules DB (measured) | n/m | `rec_schedule_claim` |
| Jack Benny, Gunsmoke, Dragnet, Suspense, Johnny Dollar, Fibber McGee | **No specific claim found.** WRVO: "most of the shows we air are in the public domain, or we have agreements with certain copyright holders" | wrvo.org (search) | 229, 19, 22, 105, 38, 32 | `rec_orphan_unclaimed` (owner tier) until a claim appears; the network successors and Mark VII are plausible claimants (UNVERIFIED) |
| Superman | Not researched. Character from *Action Comics* #1 (1938) frees 1 Jan 2034 by Decision 137's arithmetic; DC trademark (UNVERIFIED) | — | 23 | `work_character_mark` (report) + recording to 2067 |
| BBC productions | — | — | 48 | `rec_foreign_origin` |

The title-match counts above sum to about 1,000 of 8,952 items, around 11%. These are ITEMS (often whole-series sets), not episodes, and overlap is possible.

**Radio Spirits and Carl Amari:**
- Amari says he licensed "more than 60,000 original radio programs from the estates of the creators" (letter and hubpages, per search).
- Radio Spirits' archive.org notices covered "exclusive license for particular series, but also claims on images, likenesses and recordings of particular personalities" (2010 blog, per search).
- Critics dispute them (archive.org forum "Radio Sprits scam"). No court ruling was found.

Under Decision 151's temperament, a specific takedown or published licence is a claim a reader can open; "we own everything" is not.

**Trademark is not copyright.** A trademark does not stop playing a free work. It stops branding that suggests endorsement (*Dastar v. Twentieth Century Fox*, 539 U.S. 23 (2003), **UNVERIFIED** details). Design rule: show the title as data; never use a character's logo or trade dress as art; never name a channel after a mark.

---

## 7. Outside the US

- **UK** (CDPA, read at legislation.gov.uk):
  - s.13A(2): a sound recording "expires (a) at the end of the period of 50 years from the end of the calendar year in which the recording is made, or (b) if during that period the recording is published, 70 years from… first published, or (c) if during that period the recording is not published but is made available to the public by being played in public or communicated to the public, 70 years from… first so made available".
  - s.14(2): "Copyright in a broadcast… expires at the end of the period of 50 years from the end of the calendar year in which the broadcast was made".
  - s.13A(4): a non-UK author gets the term of their own country, capped at the UK term.
  - BBC scripts and music are life + 70, and the BBC licenses its archive commercially.
  - Whether the 2013 extension revived pre-1963 recordings is **UNVERIFIED**.
- **Canada, Australia, South Africa:** **UNVERIFIED**. Canada's 2015 amendment gives 70 years from publication; Australia's pre-1955 recordings are generally out of copyright there; Grace Gibson (Australia) still sells its catalog.
- **Rule for the app:** judge under US law, and **hide non-US-origin productions unless licensed**. This is a stricter cousin of Decision 156, because foreign broadcasters actively license. If NCU is used, geo-gate to the US (37 CFR 201.37(d)(3)).

---

## 8. Clear-PD categories

1. **LibriVox** (librivox.org/pages/public-domain, read): "LibriVox records only texts that are in the public domain (in the USA…), and all our recordings are public domain (definitely in the USA, and maybe in your country as well…). This means anyone can use all our recordings however they wish (even to sell them)." Measured: 21,891 items in `librivoxaudio`, 183 of them "dramatic reading".
2. **Commercial records published at or before the audio line** (1925 in 2026): dramatic sketches, comedy, recitations. Sources to probe: UCSB DAHR and the Cylinder Audio Archive, LoC National Jukebox (licences UNVERIFIED). Very few radio broadcasts before 1926 survive, and those are unpublished.
3. **Government works**, with §5's caveats and open question.
4. **Creative Commons drama**, under Decision 140's rule: the licence must be corroborated.
   - **Measured:** 272+144+122+106+67 `oldtimeradio` items carry **CC BY-NC-ND** licences, and 33 CC BY-ND. Uploaders cannot license a 1940s network show. This is the `uploader_cannot_dedicate` class, and it must hide, not rescue.
   - 916 carry the retired `licenses/publicdomain/` and 434 the PD Mark: uploader assertions, evidence of nothing.
   - 6,636 of 8,952 (74%) carry no licence.
5. **Rights-holder dedications** with a public statement: none found. This is a `licence_evidence.json` slot.

---

## 9. How distributors handle it

- **Internet Archive:** uploader marks as measured above; honors takedowns (Radio Spirits 2010, per blog).
- **OTRR** (otrr.org/OTRRLibrary/copyright.html, read): "We believe that the copyrights have expired, or that the shows are in the public domain because they were never copyrighted… we will remove any recording from our site that is shown to violate a copyright."
  - Its main argument relays a claimed Library of Congress staff statement that pre-1978 recordings "are generally in the public domain, as sound recordings were not allowed under the previous copyright law". It also asserts a 1978-79 "window" for reinstatement "in the Congressional Record". No such mechanism appears in §§301-303 or the Compendium; the claim is unsupported.
  - The same page reprints a law librarian's correction (Steve Dhuey, University of Toledo) pointing to state and common-law protection and Circular 56.
  - **Treat "OTRR Certified" as a cataloging-quality mark, never a rights finding.** OTRR's argument predates §1401 and is wrong under it.
- **Podcast directories:** feeds titled "Certified Public Domain Collection" (Lux, Lone Ranger, per search) rely on notice-and-takedown.
- **Licensed outlets** (When Radio Was, SiriusXM Radio Classics; UNVERIFIED for SiriusXM): their existence makes a series "commercially exploited", which closes NCU.
- **worldradiohistory.com** publishes a removal-on-request policy. That is a model for the app's `takedowns.json` path.

---

## 10. PROPOSAL: the audio rights audit (`audit_audio_rights.py`)

Two layers, each a `bucket()`-style ordered function: hides before rescues, first match wins, as in `tools/audit_rights.py`. **Final = hide if either layer hides; keep only if both keep; owner-tier buckets surface as their own state**, never silently as keep (Decision 108).

### 10.1 Recording layer (`recBucket`)

| # | Bucket | Evidence (machine-readable?) | Action |
|---|---|---|---|
| 1 | `rec_takedown` | `takedowns.json` entry, or a darkened archive.org item (yes: metadata API) | hide |
| 2 | `rec_schedule_claim` | Title + artist (or series/host) found in the pre-1972 schedules (**yes**: Solr proxy, §1.3) | hide |
| 3 | `rec_rights_holder_claim` | `audio_claims.json` series claim with a source URL (curated) | hide |
| 4 | `rec_post_1972` | Fixed ≥ 1972-02-15 (series dates) (yes) | hide unless `licence_evidence` |
| 5 | `rec_foreign_origin` | BBC, CBC, ABC Australia, Grace Gibson, Springbok… (curated list) | hide unless licensed |
| 6 | `rec_uploader_cannot_license` | NC/ND or other CC licence on a network-era broadcast (yes) | hide (as `uploader_cannot_dedicate`) |
| 7 | `rec_gov_work` | Government collection, or AFRS/OWI/Treasury/VOA/NASA producer in the item's own metadata, AND not in `afrs_rebroadcast_series.json` | **keep** (flag `govWorkOpenQuestion`, §5) |
| 8 | `rec_afrs_rebroadcast` | AFRS disc of a network series | fall through as that series |
| 9 | `rec_librivox` | `collection:librivoxaudio` (yes) | **keep** |
| 10 | `rec_cc_corroborated` | Free-culture licence + `rightsCorroborated` (Decisions 140/152) | **keep** |
| 11 | `rec_uploader_licence_only` | PD/CC mark, no corroboration | hide (Decision 140) |
| 12 | `rec_pd_published_age` | Publication evidence (label + catalog number, DAHR) with year ≤ `today.year - 101` | **keep** |
| 13 | `rec_commercially_exploited` | Authorized release found (Radio Spirits, licensed audiobook, licensed YouTube) with URL; i.e. the 37 CFR 201.37(c) search found it | hide, or owner tier (Q3) |
| 14 | `rec_ncu_cleared` | Our NNU indexed, 90 days passed, no opt-out, within its stated end date, US viewer | keep (only if Q2 = yes) |
| 15 | `rec_orphan_unclaimed` | Pre-1972, unpublished or unknown, nothing found by 1-6 or 13 | **OWNER CALL (Q1)** |
| 16 | `rec_no_evidence` | No date, no series identification | hide (as `no_evidence`) |

### 10.2 Underlying-work layer (`workBucket`)

| Bucket | Evidence | Action |
|---|---|---|
| `work_script_renewed` | CCE Dramas Class D renewal (1950-77 printed), or Copyright Office renewal (1978+); series + episode title, year ±1 | hide |
| `work_adapted_renewed` | Adapted film in `cce_renewals.json` or online renewals; source story or book renewed | hide (per episode) |
| `work_wikidata_claim` | Wikidata "copyrighted" with a US reference (Decision 151) | hide |
| `work_script_lapsed` | CCE Class D **registration** found and no renewal at year +27/+28 | **keep** (the one evidence-based script rescue) |
| `work_gov` | Government-employee script | keep |
| `work_pd_source` | Reading of a PD text (LibriVox) | keep |
| `work_unregistered_script` | Network script, no registration found | **OWNER CALL (Q4)**: §303-protected in law, unenforced in practice unless claimed |
| `work_music_risk` | `musicRisk = popular_songs` | report; owner call (Q5) |
| `work_character_mark` | Trademarked character | report + design rule (§6) |

### 10.3 Machine-readable sources, by value

1. **Pre-1972 schedules (Solr proxy)**: 299,447 entries; per-series and per-host queries. A new `fetch_p72_schedules.py`.
2. **CCE Dramas volumes** on archive.org: Class D registrations and renewals. A new parser beside `fetch_cce_renewals.py`.
3. **`cce_renewals.json`**: already built; reuse for Lux and Screen Guild.
4. **Copyright Office public records** (publicrecords.copyright.gov): 1978+ renewals and registrations, including post-1972 radio drama if registered.
5. **The NNU index** (search-NNUs.html, same Solr pattern; whether populated is unmeasured): others' filings and opt-outs reveal owners.
6. **archive.org** darkened items; `takedowns.json`.
7. **Wikidata** P6216/P275 on radio programs (sparse; probe first).
8. Curated files, each entry with a source a reader can open: `audio_claims.json`, `afrs_rebroadcast_series.json`, `audio_foreign_producers.json`, `licence_evidence.json`, `copyright_evidence_overrides.json`.

### 10.4 What survives each tier: ESTIMATE, labeled

Measured inputs:
- 8,952 `oldtimeradio` items; 74% carry no licence; about 1,000 CC-NC/ND uploader licences;
- about 11% of items title-match a series with a known claim or adaptation risk;
- 238 AFRS items (about 2.7%); 183 LibriVox dramatic readings.

The shares below are **reasoned guesses over those inputs, not measurements of episodes.**

| Tier | Contents | Est. share of a typical archive.org OTR corpus |
|---|---|---|
| A. Strict keep (gov, LibriVox, CC-corroborated, pre-1926 records) | AFRS originals, Treasury/OWI, LibriVox plays | **~3-8%** |
| B. A + a curated NCU program | A few hundred unexploited episodes with lapsed, governmental or PD-source scripts | **+1-5%** (fees and the one-per-notice rule cap it) |
| C. Risk tier: unclaimed orphans kept (Q1 = keep) | Everything not hidden on evidence | **~55-75%** |
| Hidden on evidence | Claimed series, schedules (CBS news), takedowns, post-1972, foreign, renewed adaptations, NC/ND uploader licences | **~25-40%**, disproportionately the famous series |

---

## 11. Questions for the owner (exact wording)

1. **Orphans.** "Federal law protects almost every pre-1972 radio recording until 2067, and most unregistered scripts for decades. The people who claim the famous series have not filed the Copyright Office schedules, and for most episodes no claim a reader can open exists. Do we (a) show only Tier A (government, LibriVox, Creative Commons, pre-1926 records), (b) show an unclaimed episode and hide it the moment a claim appears, or (c) show only a curated set cleared through noncommercial-use notices?" Option (b) is Archive Watch's film temperament. For audio the law's default is *protected*, but §1401(f)(5) limits an owner who never filed a schedule to actual damages, so (b) is a defensible risk posture rather than a public-domain claim — see §12. That is why this is yours.
2. **NCU.** "Will we file Notices of Noncommercial Use: one per episode, $50 each, US-only, re-filed when the stated end date passes? And should a lawyer first confirm that a free app in Apple's and Google's stores, with no ads, is a noncommercial use?"
3. **Commercially sold series.** "When a licensee sells a series (Radio Spirits CDs, licensed audiobooks) but has sent no takedown, do we hide it?"
4. **Unregistered scripts.** "Treat an unregistered network script as protected (hide unless the recording is a government or LibriVox work), or as unenforced (follow Q1)?"
5. **Music.** "Do variety and music shows full of popular songs get the drama rule or a stricter one?"
6. **AFRS.** "Keep AFRS originals as government works despite the open §105/§1401 question and the civilian stars, or keep only those without commercial performers?"
7. **Non-US.** "Hide all non-US-origin productions unless licensed (proposed)?"
8. **Takedowns.** "On a general claim that names no episodes, hide the whole series (proposed: yes, with the letter kept in `takedowns.json`)?"
9. **News and actuality.** "Confirm: CBS news broadcasts that Sony has scheduled are hidden, and news audio is out of scope for a drama app anyway?"
10. **Post-1972.** "Confirm: CBS Radio Mystery Theater and other post-1972 series are hidden unless licensed?"

## 12. The practical posture, and the laws that improve it (owner question, 2026-10-17)

Owner: *"There is something wonky about your understanding of audio rights. If
this site is being used to host these audio files and making them freely
available, it seems as though in practice the same rules that apply for public
domain Video seem to apply for public domain audio, even if the 2018 law
theoretically makes a different case. Are there any fair use or other laws that
could put us in better standing for utilizing a more expensive rights permission
structure?"*

**The owner is right about the practice, and the statute supports it more than
§§1-11 above conveyed.** Those sections answer "is it public domain?" (almost
never). The owner's question is "what is the exposure of a free app that plays
unclaimed recordings and removes them on a claim?" — and §1401 itself answers
that one. Read from law.cornell.edu/uscode/text/17/1401 on 2026-10-17:

1. **No statutory damages or attorney's fees unless the owner filed a schedule.**
   §1401(f)(5)(A)(i): statutory damages or fees "may be made with respect to an
   unauthorized use of a sound recording under subsection (a) only if — (I) the
   rights owner has filed with the Copyright Office a schedule that specifies the
   title, artist, and rights owner of the sound recording ... and (II) the use
   occurs after the end of the 90-day period" after it is indexed. Without
   statutory damages and fees, an owner who never filed can recover only ACTUAL
   damages and an injunction (§1401(f)(4), equity). For a free, ad-free app
   playing a recording nobody sells, actual damages are close to nothing, and a
   lawsuit costs the owner more than it can win. **This is the legal reason
   RadioEchoes, archive.org and the OTR podcasts operate on notice and takedown,
   and why it works.** The schedules are searchable (§1.3, 299,447 entries, no
   hits for the famous drama series), so "filed or not" is a machine-readable
   test — already bucket `rec_schedule_claim`.
2. **The DMCA safe harbors apply.** §1401(f)(3): "Section 512 shall apply to a
   claim under subsection (a)". The app does not host; archive.org does. Linking
   from a directory is §512(d) ("information location tools"). Protection needs
   a registered DMCA agent (Copyright Office, $6), expeditious removal on notice,
   and no "red flag" knowledge. The weak point: a curated catalog is closer to
   knowledge than a search engine, so the audit's hides-on-evidence are what keep
   the harbor (we remove what we know is claimed before anyone writes).
3. **Fair use applies** (§1401(f)(1)(A) applies §§107-110 and 112(f)). Honestly
   weighed: streaming whole episodes for listening is a WEAK fair use —
   *Hachette v. Internet Archive* (2d Cir. 2024) rejected whole-work lending by a
   nonprofit. It is STRONG for: full-text search over transcripts that shows
   snippets (*Authors Guild v. Google*, 2d Cir. 2015), short excerpts in
   historical context, and scholarship. Use fair use for search and clips, not as
   the basis for playback.
4. **Libraries get more** (§1401(f)(1)(B)): §108(h)'s "last 20 years of term"
   window is construed as "at any time after the date of enactment" for pre-1972
   recordings, so a library or archive may reproduce, distribute and PERFORM a
   PUBLISHED pre-1972 recording that is not commercially exploited, for
   preservation, scholarship or research. The app is not a library and most
   broadcasts are unpublished, so this is a partnership avenue (a university
   library or archive.org as the performing institution), not a rule for us.
   UNVERIFIED how far it stretches; a lawyer's question.
5. **The paid route that exists: the statutory webcasting license.** §1401(b):
   a digital audio transmission of a pre-1972 recording is "considered to be
   authorized" if it meets §114(d)(2) statutory-license conditions and pays the
   §114(f) royalty. That is a SoundExchange license — no negotiation, no owner to
   find. Rates (Copyright Royalty Judges, Web VI, Federal Register 2026-03-10, per
   search): commercial webcasters $1,100 per channel minimum in 2026 plus
   per-performance fees; noncommercial EDUCATIONAL webcasters $800 per channel
   (2026) covering up to 160,000 listener-hours a month per channel; the general
   noncommercial-webcaster figure is UNVERIFIED (Web V was $1,000 per channel
   up to 159,140 hours). **It covers only NONINTERACTIVE transmission** — the
   Radio tab's channels and "Tonight in 1947", never on-demand episodes — and
   carries conditions that bind the design: no advance program schedule naming
   the specific recordings (§114(j)(13); a guide that lists tonight's episodes in
   advance would breach it — UNVERIFIED how this applies to a historical
   recreation), the "sound recording performance complement" limits per artist,
   limited skipping, and archived-program rules. It licenses the RECORDING only,
   never the script or the music.
6. **Direct licensing** from the claimants (Radio Spirits for The Shadow and its
   catalog; series estates) is the expensive route for the famous titles the
   audit hides. Worth one inquiry for a small headline set; not a catalog plan.

**Recommended structure (replaces the framing of Q1 above, does not remove it):**

| Layer | What it plays | Legal basis | Cost |
|---|---|---|---|
| 1. Clean | Government, LibriVox, corroborated CC, published ≤ today−101 | Public domain / license | none |
| 2. Unclaimed, on demand | Pre-1972 broadcasts with no schedule filing, no takedown, no known claimant, no renewed script or source | Notice and takedown under §512, with §1401(f)(5) capping exposure at actual damages; hide the moment a claim a reader can open appears | DMCA agent $6; the audit |
| 3. Licensed channels | Noninteractive Radio channels, including recordings an owner HAS scheduled | §1401(b) + §114 statutory license via SoundExchange | ~$800-1,100 per channel per year at our scale |
| 4. Never | Scheduled recordings on demand; claimed series; post-1972; renewed scripts and sources (*Lone Ranger*: script claims carry full statutory damages, because scripts are ordinary registered works) | — | — |

The app must not CALL layer 2 public domain (the Decision 153 lesson): its rights
line says what is true — "no rights claim known; removed on request" — and the
takedown path is on the website.

---

## To measure

```bash
P=https://www.copyright.gov/music-modernization/pre1972-soundrecordings/proxy.php
# 1. Schedules: verified working 2026-10-17. Query per series title, host and network successor.
curl -sS -X POST --data-urlencode 'query=q=*:*&rows=0&wt=json' $P            # numFound 299447
curl -sS -X POST --data-urlencode 'query=q=artist:cronkite&rows=100&wt=json' $P
#    Run every series in the OTR catalog through title:/album:/artist: and record hits with index_date.
#    Also try rights_owner:paramount, rights_owner:comcast, rights_owner:"Sony Music" AND album:radio.

# 2. NNU index: does the same proxy serve NNUs (different core/param)? Inspect the browser network
#    tab on search-NNUs.html, or try:
curl -sS -X POST --data-urlencode 'query=q=*:*&rows=5&wt=json&core=nnu' $P | head -c 800

# 3. CCE Dramas volumes (Class D registrations + renewals) on archive.org.
curl -sS 'https://archive.org/advancedsearch.php?q=title%3A%28%22catalog+of+copyright+entries%22%29+AND+title%3A%28dramas%29&fl%5B%5D=identifier&fl%5B%5D=year&rows=300&output=json'
#    For a 1940s registration volume: grep its _djvu.txt for "radio", "broadcast" and series names,
#    to size how many radio scripts were ever registered (decides Q4's real scope).

# 4. Episode-level composition (items are often whole-series sets): count audio files per item.
curl -sS 'https://archive.org/metadata/AfrsJubilee' | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for f in d["files"] if f["name"].endswith(".mp3")))'

# 5. Darkened OTR items (takedown signal) over a sample of identifiers.
#    curl -sS https://archive.org/metadata/<id> | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(d.get("is_dark"))'

# 6. Remaining UNVERIFIED law: Flo & Eddie (N.Y. 2016) opinion; Canada Copyright Act s.23 (laws-lois.justice.gc.ca);
#    Australia Copyright Act 1968 s.93 + 2005 transitional provisions; Dastar 539 U.S. 23.
```

```sparql
# 7. Wikidata: radio programs with a copyright status or licence.
SELECT ?p ?pLabel ?status ?statusLabel ?lic ?licLabel WHERE {
  ?p wdt:P31/wdt:P279* wd:Q1555508 .
  OPTIONAL { ?p wdt:P6216 ?status } OPTIONAL { ?p wdt:P275 ?lic }
  FILTER(BOUND(?status) || BOUND(?lic))
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} LIMIT 500
```

---

## Sources

Read directly (2026-10-17)
- https://www.law.cornell.edu/uscode/text/17/1401
- https://www.law.cornell.edu/uscode/text/17/301
- https://www.law.cornell.edu/uscode/text/17/105
- https://www.law.cornell.edu/uscode/text/17/101
- https://www.copyright.gov/title37/201/37cfr201-37.html
- https://www.copyright.gov/title37/201/37cfr201-3.html
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/search-soundrecordings.html (and its `proxy.php`)
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/search-NNUs.html
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/NNUfiling-instructions.html
- https://www.copyright.gov/js/mma-search.js
- https://www.copyright.gov/comp3/chap1900/ch1900-publication.pdf
- https://www.copyright.gov/comp3/chap2100/ch2100-renewal-registration.pdf
- https://www.copyright.gov/comp3/chap800/ch800-performing-arts.pdf
- https://www.copyright.gov/circs/circ56.pdf
- https://www.copyright.gov/docs/sound/pre-72-report.pdf
- https://law.resource.org/pub/us/case/reporter/F2/740/740.F2d.718.82-4690.html
- https://www.otrr.org/OTRRLibrary/copyright.html
- https://librivox.org/pages/public-domain/
- https://www.legislation.gov.uk/ukpga/1988/48/section/13A
- https://www.legislation.gov.uk/ukpga/1988/48/section/14
- https://archive.org/advancedsearch.php (measurements in §§5, 6, 8)

Via search results only
- https://www.govinfo.gov/content/pkg/USCODE-2023-title17/html/USCODE-2023-title17-chap14.htm
- https://public-inspection.federalregister.gov/2019-06883.pdf
- https://www.govinfo.gov/link/fr/84/14255
- https://law.justia.com/codes/us/title-17/chapter-3/sec-303/
- https://www.authorsalliance.org/2024/12/29/public-domain-day-a-diversion-to-sound-recordings/
- https://commons.wikipedia.com/wiki/Template:PD-US-record-expired
- https://www.loc.gov/static/programs/national-recording-preservation-plan/publications-and-reports/documents/pub144.pdf
- https://www.nycourts.gov/REPORTER/3dseries/2005/2005_02570.htm
- https://en.wikipedia.org/wiki/Capitol_Records,_Inc._v._Naxos_of_America,_Inc.
- https://everybodyslibraries.com/2009/07/14/for-those-wanting-more-drama-in-their-lives/
- https://www.ibiblio.org/ccer/1923d1.htm
- https://www.archive.org/download/catalogofcop196732134libr/catalogofcop196732134libr.pdf
- https://online.ucpress.edu/res/article/6/1/64/208432/Retailing-RadioThe-Industrial-Afterlife-of-Classic
- https://archive.org/details/AfrsJubilee · https://archive.org/details/AFRS-17
- https://hdl.loc.gov/loc.mbrsrs/eadmbrs.rs019006.3
- https://archives.nypl.org/rha/20439
- https://en.wikipedia.org/wiki/Command_Performance_(radio_series)
- https://en.wikipedia.org/wiki/Jubilee_(radio_program)
- https://www.dennismspragg.com/wp-content/uploads/2025/03/THE-ARMED-FORCES-RADIO-SERVICE.pdf
- https://www.classicradiogallery.com/transcriptions/
- https://en.wikipedia.org/wiki/The_Shadow
- https://thepulp.net/thatspulp/2017/07/14/lost-shadow-radio-shows-found/
- https://trademarkregistration.app/Trademark/Details/74639802
- https://randsesotericotr.podbean.com/category/radio-spirits-removals
- https://archive.org/post/334595/radio-sprits-scam
- https://groups.google.com/g/alt.radio.oldtime/c/OYxmpHeT43M
- https://hubpages.com/entertainment/Radio-Spirits
- https://en.wikipedia.org/wiki/When_Radio_Was
- https://www.openculture.com/2014/06/x-minus-one.html
- https://www.scifimike.com/sf-radio-x-minus-one-1.html
- https://www.blackstonelibrary.com/x-minus-one-vol-1
- https://www.oac.cdlib.org/findaid/ark:/13030/c8v126g4/
- https://library.temple.edu/finding_aids/lux-radio-theatre-scripts
- https://www.wrvo.org/tuned-to-yesterday
- https://worldradiohistory.com/American-Radio-History-Take-Down.htm
- https://www.greatdetectives.net/detectives/about/copyright-questions/

Archive Watch (the model extended)
- /home/user/Archive-Watch/tools/audit_rights.py (`bucket()`, `HIDE_BUCKETS`)
- /home/user/Archive-Watch/tools/fetch_cce_renewals.py
- /home/user/Archive-Watch/shared/editorial/cce_renewals.json
- Decisions 137, 140 (docs/decisions/DECISIONS-127-145.md); 151, 152, 156, 157 (DECISIONS.md)
