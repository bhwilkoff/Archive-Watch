# Radio rights research — old-time radio, radio plays, public-domain audio

*2026-10-17 · research track 02 (RIGHTS) for the proposed sister app · nothing built*

## Verdict

1. **"Old-time radio is public domain" is, under current US law, mostly false for the RECORDING.** Since the Music Modernization Act (2018), Title II (the Classics Protection and Access Act, 17 U.S.C. §1401), every sound recording fixed before 15 Feb 1972 is federally protected. A recording first PUBLISHED before 1923 is free since 1 Jan 2022. One published 1923-1946 gets 100 years, one published 1947-1956 gets 110 years, and **everything else, including every UNPUBLISHED recording, runs to 15 Feb 2067**. A network broadcast was disseminated but was "in many cases technically unpublished" (Copyright Office 2011 report, per search snippet). So the AGE route that frees films (Decision 137) frees almost no radio drama until 2067.
2. **Formalities can't free a recording.** Films become public domain through 1909-Act defects: no notice, no renewal. Recordings never had federal registration, so "never registered, never renewed" (OTRR's stated argument) proves nothing about the recording. **The Archive Watch film model doesn't carry over.** Here, not knowing means "protected, owner unknown", not "public domain".
3. **The SCRIPT is a second, separate copyright.** If it was never registered, §303 has protected it federally since 1978 (a work made for hire runs 120 years from creation, so a 1945 script runs to about 2065). Distributing transcription discs to stations did NOT publish the script (§303(b), amended 2010 to cover dramatic and literary works). A script that WAS registered (Class D) and NOT renewed is public domain. That is the one place the Catalog of Copyright Entries frees anything, and Archive Watch already has the parser pattern for it (`tools/fetch_cce_renewals.py`). *Lone Ranger Television v. Program Radio* (9th Cir. 1984) affirmed infringement by someone who duplicated tapes of radio episodes whose scripts were registered and renewed.
4. **Clean tiers are small:** US-government productions (17 U.S.C. §105: the original AFRS shows, Treasury and OWI programs, but NOT network shows AFRS rebroadcast), LibriVox dramatic readings, Creative Commons drama with corroborated evidence (the Decision 140 rule), and commercial phonograph sketches published before the computed audio age line (1925 is the newest free year in 2026).
5. **The noncommercial-use safe harbor (§1401(c), 37 CFR 201.37) is real and fits a free, ad-free app better than anything else.** It works per recording: a documented good-faith search, a notice filed with the Copyright Office, and 90 days with no opt-out. It covers only recordings NOT commercially exploited by the rights owner, and only the RECORDING layer. It never clears a script, music or an underlying story.
6. **The marquee series are where the claims live:** The Shadow (Condé Nast trademark and copyright, licensed to Radio Spirits), The Lone Ranger (Classic Media trademark; scripts litigated in 1984), Lum and Abner (Radio Spirits takedowns for the Lauck estate, per a 2010 blog), X Minus One (adaptations of copyrighted SF stories; sold commercially), Lux Radio Theatre and Screen Guild (adaptations of studio films, many renewed).
7. **The recommendation is a two-layer audit** (recording and underlying work), plus an owner-reserved middle tier for orphans. Without an owner decision, the defensible app is small: government, LibriVox, Creative Commons and pre-1926 records. With the NCU route, or a risk call on orphans, it becomes a real OTR app. **This is the owner's decision to make, not a code default** (Decision 027's reservation).

> **Research limit (stated plainly):** this container could only use WebSearch, and the shared search budget ran out partway through the track. The statute, the NCU rule, §303(b), the Copyright Office report snippet, the Shadow, Lone Ranger, AFRS and OTRR facts come from search results, cited below. The non-US terms, the Superman/DC status, CBS Radio Mystery Theater ownership, LibriVox's dedication wording, the *Dastar* holding and the NCU rule's specific search list come from general legal knowledge and are marked **UNVERIFIED**. A future session should confirm them using the probes in "To measure".

---

## 1. Federal protection of pre-1972 sound recordings (17 U.S.C. §1401)

### 1.1 The schedule (statute text via search; copyright.gov, Cornell LII, govinfo)

§1401(a) bars unauthorized reproduction, distribution and digital public performance of a pre-1972 recording. The term is "95 years after first publication" plus a transition period (§1401(a)(2)):

| First published | Ends | Effective term | Free from |
|---|---|---|---|
| before 1923 | 31 Dec 2021 | — | 1 Jan 2022 |
| 1923-1946 | 95 years + 5 | 100 years | 1 Jan of (year + 101); **1925 became free 1 Jan 2026** |
| 1947-1956 | 95 years + 15 | 110 years | 1 Jan of (year + 111); 1947 becomes free 2058 |
| 1957 - 14 Feb 1972, **and anything not in the rows above, including unpublished** | 15 Feb 2067 | — | 15 Feb 2067 |

The catch-all is clause (iv), "not described in clause (i), (ii), or (iii)". The statute text was confirmed by search on govinfo and Cornell. Clauses (i)-(iii) are all keyed to FIRST PUBLICATION, so an unpublished recording of any age falls into (iv) and runs to 2067. §1401(a)(2)(A)(ii) also says no protection survives past 15 Feb 2067. The Wikipedia/Commons template `PD-US-record-expired` starts the first band at 1924; the statute says 1923, and the statute controls.

**Computed age line** (Decision 137: never a literal): `AUDIO_PD_PUBLISHED_LAST = today.year - 101` (1925 in 2026), and it applies only to a recording with evidence of PUBLICATION. Authors Alliance's annual "Public Domain Day — A Diversion to Sound Recordings" post (2024-12-29) applies the same arithmetic.

### 1.2 What "published" means for radio

- **A broadcast is a public performance, not a publication.** The Library of Congress study on unpublished recordings (pub144, per search snippet) says a broadcast "is a public performance, even if each member of the audience listens to it in the privacy of her own home". The Copyright Office's 2011 pre-1972 report says old radio broadcasts "were publicly disseminated by virtue of the broadcast, but in many cases are technically unpublished" (per the search-result summary of copyright.gov/docs/sound/pre-72-report.pdf; the exact page was not opened).
- **Transcription discs** (syndicated shows, AFRS discs) "were distributed only to radio stations for the purpose of broadcast, and not for sale to the public" (search snippet, NYPL and classicradiogallery.com). Distribution to a limited, defined group for a limited purpose is the classic **limited publication**, which is not publication. No case applying this to transcription discs was found. **UNVERIFIED: treat syndicated transcriptions as unpublished** (2067) unless a court or the Office says otherwise.
- **Commercially sold phonograph records** (Victor and Columbia dramatic sketches, comedy monologues, cylinders) are published. These are the only "radio-like" drama that §1401's age line frees today.
- **Later LP and cassette reissues** (Radio Spirits, Mark 56, Nostalgia Lane, 1960s-80s): the *first publication* may be the reissue. A 1940s broadcast first published on a 1974 LP falls into clause (iv) and runs to 2067 either way. A post-1972 remaster may also carry its own new copyright in restoration choices (UNVERIFIED). Either way, publication cannot shorten the term below 2067 for anything first published after 1956.

**Consequence:** for practical purposes, **no network-era radio broadcast recording is public domain by age before 2067.** An "age" bucket for audio is nearly empty, and the owner should hear that in those words.

### 1.3 Unpublished recordings

They are covered by the clause (iv) catch-all and protected until 15 Feb 2067 (statute via search; the Copyright Office's summary page lists the tiers). The 2011 report's recommendation of "120 years from fixation" for unpublished recordings was NOT enacted. The original CLASSICS Act's blanket 2067 term was amended into the tiers above for published recordings, but unpublished ones kept 2067.

### 1.4 Remedies, and the schedules owners file

- To recover **statutory damages or attorney's fees**, a rights owner generally must have filed a **Schedule of Pre-1972 Sound Recordings** with the Copyright Office, and the use must come after the schedule is indexed (§1401(f)(5); 37 CFR 201.35; copyright.gov schedule pages, per search). Without a schedule, the owner can still sue for actual damages and an injunction. This changes the *risk* of a use, not its legality.
- The schedules are **searchable** at copyright.gov/music-modernization/pre1972-soundrecordings/search-soundrecordings.html. Each entry carries rights owner, title and featured artist. The probe in "To measure" asks whether any radio programs appear in them. **This is a machine-readable claim source:** a recording listed in a schedule is a claim a reader can open (Decision 151).

### 1.5 The noncommercial-use safe harbor (§1401(c); 37 CFR 201.37)

From the statute and the final rule (Docket 2018-8; Federal Register 2019-06883), per search:

- It applies to **noncommercial use** of a pre-1972 recording that is **not being commercially exploited by or under the authority of the rights owner**.
- The user must make a **good-faith, reasonable search** of the Copyright Office schedules and of services offering a comprehensive set of recordings, and find nothing. The Office says following its "specific, reasonable steps" satisfies the requirement even if the recording later turns out to be exploited. It advises keeping the search record (screenshots, search terms) for at least three years.
- The user files a **Notice of Noncommercial Use** with the Office. The rights owner may **opt out within 90 days** of the notice being indexed into the public records.
- The statute says "merely recovering costs of production and distribution does not itself necessarily constitute a commercial use", and that a user who also engages in commercial activities is not necessarily making a commercial use.

**Could a free, no-ads, no-accounts app use it?** It is the closest fit in the statute: no revenue, no ads, and Archive Watch's posture is non-commercial. Limits a builder must respect:
1. **It works one recording at a time.** Each episode needs its own search and notice. **UNVERIFIED:** how many recordings one notice may list, and whether a fee applies. Check 37 CFR 201.37 directly.
2. **It doesn't cover a commercially exploited recording.** The series people know best are sold (Radio Spirits sets; Hollywood 360/Blackstone's licensed X Minus One audiobooks, per search). Those episodes fail the test. Whether an *unauthorized* commercial bootleg counts as exploitation: the statute says "by or under the authority of the rights owner", so a bootleg should not count (UNVERIFIED reading).
3. **It covers only the RECORDING layer.** Scripts, music and source stories are untouched (§3 below). An episode cleared under NCU with an unpublished work-made-for-hire script is still infringing as to the script.
4. **US only.**
5. **"Noncommercial" in an app store.** A free app with no in-app purchases is arguably noncommercial. Whether distribution through Apple's and Google's stores, or a donation link, changes that has no authority found. **UNVERIFIED; ask counsel** before relying on it.

**This route deserves an owner decision and probably a lawyer's hour.** It is the only path in the statute that turns "orphan" into "lawfully usable" for the recording, and it leaves a public record a reader can open (the indexed notice). That matches the Decision 151 temperament from the other direction.

---

## 2. State law before 2018: why "no federal copyright" was always wrong

- ***Capitol Records v. Naxos of America*, 4 N.Y.3d 540 (N.Y. 2005):** New York common-law copyright protected pre-1972 recordings. Copying 1930s recordings infringed even though they were public domain abroad, remastered, and in little demand. No bad faith was required (nycourts.gov, Cornell LII, per search).
- ***Flo & Eddie v. Sirius XM* (N.Y. 2016):** New York common law gives **no public-performance right** in pre-1972 recordings. Per Wikipedia's summary only; the opinion itself was not read. California and Florida had parallel Flo & Eddie litigation (UNVERIFIED details).
- **Relevance now:** §1401(e) preempts state-law claims for conduct after the MMA's enactment (11 Oct 2018). **UNVERIFIED** wording; read §1401(e). So state law matters only for pre-2018 conduct and as history. Its lesson is the one that matters: OTR collectors' standard argument ("sound recordings weren't copyrightable before 1972, so they're PD") was legally wrong under state law before 2018 and is wrong under federal law since. OTRR's policy page still makes that argument, citing a secondhand Library of Congress statement (§9).

---

## 3. Underlying works: scripts, music, adaptations

### 3.1 Scripts

| Script status | Term | How to tell |
|---|---|---|
| Unpublished, never registered | §303(a): brought into federal copyright on 1 Jan 1978 with §302 terms: life + 70, or, for a work made for hire, the shorter of 95 years from publication or **120 years from creation**; never earlier than 31 Dec 2002 (statute via search: Cornell, copyright.gov ch. 3) | Default for network drama. A staff-written 1940 script is protected to about 2060. |
| Registered as an unpublished dramatic work (Class D) under the 1909 Act, **renewed** | 28 + 67 = 95 years from registration | CCE "Dramas and Works Prepared for Oral Delivery" renewal lists (printed 1950-77); Copyright Office online records (renewals 1978+) |
| Registered (Class D), **not renewed** | Expired after 28 years; **public domain** | A registration found in CCE with no renewal 27-28 years later |
| Published (sold script books, magazines) with notice | 1909 rules: renew or lose; the same age line as films | CCE books/periodicals renewals; Stanford Copyright Renewal Database (books, UNVERIFIED URL) |

- **§303(b)** (statute via search, Justia/Cornell): "The distribution before January 1, 1978, of a phonorecord shall not for any purpose constitute a publication of any musical work, dramatic work, or literary work embodied therein." "Dramatic work" was added in 2010 (Pub. L. 111-295). **Transcription discs and LP reissues did not publish the scripts.**
- **Renewal rates are low:** about 780 Class D renewals in 1959, roughly 13% (Penn/Online Books blog "everybodyslibraries.com", 2009, per search snippet). If radio scripts were registered at all, most lapsed. But most network scripts were probably **never registered** (UNVERIFIED; measure it), which leaves them under §303's 120-year term. *Lone Ranger Television v. Program Radio Corp.*, 740 F.2d 718 (9th Cir. 1984), is the counter-case: all fifteen scripts were registered, and copyrights in all fifteen "remained valid, either in their original term or by renewal". The defendant had duplicated tapes of the recorded episodes, and summary judgment for the owner on copyright infringement and state-law conversion was affirmed (law.resource.org, per search; only the opening of the opinion was visible).
- **Academic view:** "most radio programs from the radio network era are copyrighted as unpublished scripts through 2050" (*Retailing Radio*, UC Press, Resonance journal, per search snippet). That is also the position Carl Amari and Radio Spirits take.

**Machine-readable:** the CCE *Dramas* volumes are scanned on archive.org (e.g. `catalogofcop196732134libr`, "Dramas and Works Prepared for Oral Delivery, Jan-Jun 1967"). ibiblio's CCER transcribes Class D renewals for 1923 and 1925. A `fetch_cce_dramas.py` modeled on `fetch_cce_renewals.py` could extract both **registrations** (to prove a script was registered, which makes non-renewal meaningful) and **renewals** (a claim).

### 3.2 Music

Theme music, bridges and songs are separate copyrights. Published music follows the 1909 rules and the same age line as films (free if published in 1930 or earlier, as of 2026). A drama with a commissioned score has a further unpublished-music claim. A variety show (Benny, Kraft Music Hall, Command Performance) is full of popular songs whose compositions may still be protected. **The recording layer's NCU route does not clear the songs.** An app should record `musicRisk` per series: none (no music), library or stock, popular songs.

### 3.3 Adaptations

- **Lux Radio Theatre (1934-55), Screen Guild Theater, Academy Award Theater, Screen Directors Playhouse:** radio adaptations of studio films. The script is a derivative of the film (and its source novel). The search found no legal analysis. Archival holders (Margaret Herrick Library, Temple University) warn that researchers must obtain all rights. Podcast feeds call Lux "OTRR.org - Certified Public Domain Collection" (search) — a distributor's label, not evidence.
  **Machine-readable and already built:** Archive Watch's `shared/editorial/cce_renewals.json` (11,579 motion-picture renewals) and `corroborate_copyright.py` can match a Lux episode's adapted title and year against film renewals. An episode adapting a renewed film carries a claim a reader can open: the renewal record.
- **X Minus One (NBC 1955-58), Dimension X:** adapted stories by Asimov, Heinlein, Bradbury and others, mostly from *Astounding* and *Galaxy* (Open Culture, scifimike.com, per search). Every source story is a separately copyrighted, probably renewed, work. The series is also sold commercially (Hollywood 360/Blackstone, per search), so NCU is closed.
- **Adaptations of PD literature** (Poe; Doyle's pre-1928 Holmes; Dickens) make the source free, but the radio script is still a new work under §3.1.

---

## 4. Post-1972 recordings

Anything fixed on or after 15 Feb 1972 is under ordinary federal copyright (17 U.S.C. §§102, 302): *CBS Radio Mystery Theater* (1974-82), *Sears Radio Theater*, *Mutual Radio Theater*, *Heartbeat Theatre*, NPR's *Star Wars*, the BBC's *Hitchhiker's Guide*. No age route exists before roughly 2070. **Default: hide unless licensed**, the same as Archive Watch's `modern_copyright_*`. Who controls CBSRMT (Himan Brown's estate or a licensee) is **UNVERIFIED**; the search budget ran out. Archive.org hosts it widely and podcasts carry it, but that is not evidence.

---

## 5. US government works

17 U.S.C. §105: there is no copyright in a work of the US Government, meaning one "prepared by an officer or employee... as part of that person's official duties" (§101). Applied to radio:

- **AFRS original productions** (*Command Performance*, *Mail Call*, *G.I. Journal*, *Jubilee*, *Personal Album*, *Melody Roundup*): produced by the War Department's Armed Forces Radio Service. *Jubilee* was exempt from the 1942-43 recording ban because of its War Department status (Wikipedia, per search). *Command Performance* was produced under the aegis of the Office of War Information (Wikipedia, per search). Archive.org carries them under the Public Domain Mark (`AfrsJubilee`, `AFRS-7`, `AFRS-12`, `AFRS-17`, `AFRS-21`, per search) — an uploader's mark.
  **Caveats, each real:**
  1. Civilian stars performed without pay but were not federal employees. Whether their performances are "prepared by" an employee is unsettled. No case was found (UNVERIFIED).
  2. **Songs** in these shows keep their own copyrights (§3.2).
  3. **AFRS rebroadcasts of network programs** (the "denatured" Benny, Fibber McGee and Bob Hope shows with commercials removed) are NOT government works. The network's and sponsor's rights survive; only the disc was made by AFRS. Judge these as the underlying network show. The AFRS program number series (e.g. "AFRS Program No. ...") and the title tell them apart (UNVERIFIED details; Dennis M. Spragg's AFRS history, dennismspragg.com, is the reference to read).
  4. The Library of Congress AFRTS collection says "restrictions may exist on copying, quoting, or publishing material" (hdl.loc.gov/loc.mbrsrs/eadmbrs.rs019006.3, per search).
- **Treasury programs** (*Treasury Star Parade*, *Treasury Salute*, bond drives), **OWI** (*This Is Our Cause*, etc.), **Voice of America**, Department of Agriculture farm programs, **NASA**: §105 applies to employee-produced material, with the same caveats about contracted talent and music. VOA's former bar on domestic distribution (Smith-Mundt) was relaxed in 2013 (**UNVERIFIED**). It was a distribution rule, not copyright.
- **State and municipal radio** (e.g. WNYC as a city station) is NOT covered by §105 (UNVERIFIED that any item turns on this; listed so a builder doesn't extend `safe_gov` to it).

Proposed evidence: an archive.org government collection (as Archive Watch's `GOV` set), or an AFRS or federal producer named in the item's own metadata, AND the title is not a known network series. **This is the largest honestly clean pool** in a typical OTR corpus.

---

## 6. Commonly claimed "PD" series: the evidence found

| Series | Claim found | Source | Proposed bucket |
|---|---|---|---|
| The Shadow (1937-54) | "a trademarked and copyrighted property of Advance Magazine Publishers d.b.a. Condé Nast"; Radio Spirits licensed to distribute; 18-episode CD set (2017) with 11 newly found shows | Radio Spirits press release via Wikipedia/thepulp.net (search) | `rights_holder_claim` (hide) |
| The Lone Ranger (1933-54) | Scripts registered and renewed; infringement affirmed 1984; trademark held by Classic Media/DreamWorks Classics (trademark record last updated 2018); Charles Michelson Inc. exclusive radio-leasing licensee since 1965 (as of 1984); Radio Spirits license (blog) | 740 F.2d 718; trademarkregistration.app (search) | `script_renewal_evidence` + `rights_holder_claim` (hide) |
| Lum and Abner | Radio Spirits takedown notices to archive.org as the Chester Lauck estate's exclusive agent (2010 blog) | randsesotericotr.podbean.com "radio-spirits-removals" (search) | `takedown_history` (hide) |
| X Minus One | Adaptations of copyrighted stories; licensed commercial audiobooks | Open Culture; Blackstone Library (search) | `adapted_work_claim` + `commercially_exploited` (hide) |
| Lux Radio Theatre / Screen Guild | Adaptations of studio films; archive rights warnings | OAC/Herrick; Temple finding aid (search) | per-episode `adapted_work_claim` via `cce_renewals.json` |
| Jack Benny, Gunsmoke, Dragnet, Suspense, Yours Truly Johnny Dollar | **No claim found in search.** WRVO's *Tuned to Yesterday* airs Benny and Gunsmoke and says "most of the shows we air are in the public domain, or we have agreements with certain copyright holders" | wrvo.org (search) | `orphan_unclaimed` (owner tier) **until a claim is found**; network successors (CBS/Paramount, NBC/Comcast) and Mark VII/Webb are plausible claimants, UNVERIFIED |
| Superman (1940-51) | Not searched (budget). Character from *Action Comics* #1 (1938); character copyright free 1 Jan 2034 by Decision 137's arithmetic; DC trademark (UNVERIFIED) | — | `character_trademark` (report) + recording layer to 2067 |

**Radio Spirits and Carl Amari:** Amari says he spent 20 years licensing more than 60,000 original radio programs from creators' estates (hubpages and Google Groups letter, per search). Radio Spirits has sent takedowns to archive.org "concerning claims they have on particular series and shows... exclusive license for particular series, but also claims on images, likenesses and recordings of particular personalities" (2010 blog, per search). Critics (hubpages, archive.org forum post "Radio Sprits scam") dispute the claims. **No court ruling on those takedowns was found.** Under Decision 151's temperament, a *specific* takedown or a published license is a claim a reader can open. A general "we own everything" is not.

**Trademark vs. copyright.** A trademark (The Shadow, The Lone Ranger, Superman) does not stop anyone from *playing a work that is free*. It stops using the mark as a brand or in a way that suggests endorsement. *Dastar v. Twentieth Century Fox* (2003) held the Lanham Act can't be used to create a "mutant copyright" over public-domain material (**UNVERIFIED citation detail**). For the app this means:
- show the title as data;
- never use a character's logo or trade dress as shelf or channel art;
- never name a Party or Channel after the mark.

That is a design rule, not a hide.

---

## 7. Outside the US (all UNVERIFIED: no searches remained)

- **UK:** sound recordings, 70 years from publication (the 2013 extension) or 50 years from making if unpublished; broadcasts, 50 years from first broadcast; scripts and music, life + 70. The BBC actively licenses its archive (BBC Sounds, Audible, BBC Audiobooks). **BBC drama is not public domain anywhere.** Radio Spirits claimed BBC shows too, per an archive.org forum poster (search).
- **Canada:** since 2015, a sound recording is protected 70 years from publication if published within 50 years of fixation, otherwise 50 years from fixation. CBC is a Crown corporation, but Crown copyright still applies (Canada has no §105 equivalent).
- **Australia:** the 2005 extension to 70 years did not revive recordings that had already expired. Recordings made before 1955 are generally out of copyright there, but the scripts are not. Australian syndicated drama (Grace Gibson Productions, the Australian *Shadow*) is sold by its owners today.
- **South Africa (Springbok Radio)** and others: unknown.
- **Why geography matters:** the app is distributed worldwide. A file free in Australia can be protected in the US and vice versa. Safe rule: **judge everything under US law, and hide non-US-origin productions unless licensed.** That is a stricter cousin of Decision 156 (URAA). Hide rather than noRecommend, because foreign national broadcasters license their archives actively.

---

## 8. Clear-PD categories

1. **LibriVox** dramatic works: amateur readings of public-domain plays, dedicated to the public domain by the readers (**UNVERIFIED** wording; LibriVox's FAQ says its recordings are public domain). The source play must itself be PD by age: LibriVox checks this under US rules (UNVERIFIED).
2. **Commercial phonograph records published at or before the computed audio line** (1925 in 2026): dramatic sketches, comedy (Cal Stewart's "Uncle Josh", "Cohen on the Telephone" 1913), recitations, early broadcast souvenirs. Sources: UCSB's Discography of American Historical Recordings and the Cylinder Audio Archive, and the Library of Congress National Jukebox (**UNVERIFIED** availability and licenses). Radio itself began in 1920 (KDKA). Very few broadcast recordings before 1926 survive, and the few that do are mostly unpublished, so they run to 2067.
3. **US government works** (§5, with its caveats).
4. **Creative Commons modern audio drama**, under Decision 140's rule as is: the licence must be corroborated (Wikidata P275 or the creator's own page); an uploader's tag is not enough.
5. **Recordings dedicated by a rights holder**, with a public statement a reader can open. None was found in search; this is a `licence_evidence.json` slot.

---

## 9. How distributors handle it

- **Internet Archive:** OTR items carry uploader-applied "Public Domain Mark" tags (e.g. the AFRS items). Archive.org honors takedowns: Radio Spirits notices in 2010 per the blog, and a forum thread disputing them. **Probe:** items that went dark (`is_dark`, or metadata calls returning 403) in OTR collections are a measurable takedown signal.
- **OTRR (otrr.org / otrrlibrary.org):** its policy page argues the recordings are PD because they were "not registered for copyright protection when broadcast and were not filed for reinstatement in the late-1970s window", and "quotes Library of Congress statements" (per search). It also separates script copyright from recording copyright, conceding that one can be PD while the other is not. **"OTRR Certified" is a cataloging-quality mark, not a rights finding.** The registration argument has no force after 2018 (§1.2). Treat OTRR as an excellent *metadata* source and no *rights* source.
- **Podcast directories (Spotify, Apple, Audible podcasts):** many feeds say "Certified Public Domain Collection" (Lux, Lone Ranger, per search). They rely on DMCA notice-and-takedown, not clearance. Their presence is not evidence.
- **SiriusXM Radio Classics, WRVO, When Radio Was:** licensed or mixed. *When Radio Was* is hosted and licensed through Amari (Wikipedia, per search). Their existence shows that the series they carry are **commercially exploited**, which closes NCU for those episodes.
- **worldradiohistory.com:** publishes an explicit removal-on-request policy (search). That is a model for the app's own takedown path (Archive Watch's `takedowns.json`).

---

## 10. PROPOSAL: the audio rights audit (`audit_audio_rights.py`)

Two layers, judged separately and combined by the stricter result. In each list below, ordering is by precedence: the first hide wins, as in `audit_rights.bucket()`, where hides run before any rescue.

### 10.1 Recording layer (`recBucket`)

| Order | Bucket | Evidence required (machine-readable?) | Action |
|---|---|---|---|
| 1 | `rec_takedown` | `takedowns.json` entry, or a darkened archive.org item (yes: metadata API) | hide |
| 2 | `rec_schedule_claim` | Title/artist found in the Copyright Office **pre-1972 schedules** (yes: search page; scrape or probe) | hide |
| 3 | `rec_rights_holder_claim` | `audio_claims.json`: a series-level claim with a source URL (Condé Nast/Shadow, Lauck estate, Lone Ranger…) (curated) | hide |
| 4 | `rec_post_1972` | Fixed on or after 1972-02-15 (series dates) (yes) | hide unless `licence_evidence` |
| 5 | `rec_foreign_origin` | Producer or broadcaster is BBC, CBC, ABC (Aus), Grace Gibson, Springbok, etc. (curated `audio_foreign_producers.json`) | hide unless licensed |
| 6 | `rec_gov_work` | Government collection, or AFRS/OWI/Treasury/VOA/NASA producer in the item's own metadata, AND title not in `afrs_rebroadcast_series.json` (yes plus curated) | **keep** |
| 7 | `rec_afrs_rebroadcast` | AFRS disc of a network series | fall through, judged as that series |
| 8 | `rec_librivox` | `collection:librivoxaudio` (yes) | **keep** |
| 9 | `rec_cc_corroborated` | Free-culture licence + `rightsCorroborated` (Decision 140/152 machinery) (yes) | **keep** |
| 10 | `rec_uploader_licence_only` | CC or PD mark with no corroboration | hide (Decision 140 as is) |
| 11 | `rec_pd_published_age` | Evidence of PUBLICATION (DAHR/discography: label and catalog number) with year ≤ `today.year - 101` (partly: DAHR) | **keep** |
| 12 | `rec_commercially_exploited` | An authorized commercial release (Radio Spirits catalog, licensed audiobook) with a URL (curated; searchable) | hide, or owner tier (Q3) |
| 13 | `rec_ncu_cleared` | NCU notice filed, indexed, 90 days passed, no opt-out (yes: Copyright Office record) | keep (**if** the owner adopts NCU, Q2) |
| 14 | `rec_orphan_unpublished` | Pre-1972, no claim found by 1-5 or 12 | **OWNER CALL (Q1)** |
| 15 | `rec_no_evidence` | No date, no series identification | hide (as `no_evidence`) |

### 10.2 Underlying-work layer (`workBucket`)

| Bucket | Evidence | Action |
|---|---|---|
| `work_script_renewed` | CCE *Dramas* Class D renewal (printed 1950-77), or a Copyright Office renewal (1978+), matching series and episode title and year ±1 | hide |
| `work_adapted_renewed` | Adapted film found in `cce_renewals.json` or online renewals; adapted story or book renewed (Stanford/NYPL CCE book renewals) | hide (per episode) |
| `work_wikidata_claim` | Wikidata "copyrighted" with a US reference (Decision 151 rule) | hide |
| `work_script_lapsed` | CCE Class D **registration** found AND no renewal in year +27/+28 | **keep** (the one evidence-based script rescue) |
| `work_gov` | Script by a government employee (with `rec_gov_work`) | keep |
| `work_pd_source` | Reading of a PD text (LibriVox) | keep |
| `work_unpublished_unknown` | Network script, no registration found | **OWNER CALL (Q1)**: legally §303-protected; practically unenforced unless claimed |
| `work_music_risk` | Variety or music series with popular songs (series-level flag) | report; owner call (Q5) |
| `work_character_mark` | Trademarked character series | report; design rule: no logos (§6) |

**Combination:** final = hide if either layer hides; keep if both keep. The owner-tier buckets show as their own state in Pulse-style reports, never silently as keep (Decision 108: "a reader that cannot read says so").

### 10.3 Machine-readable sources, ranked by value

1. Copyright Office **pre-1972 schedules** (recording claims, indexed): new.
2. **CCE Dramas volumes** on archive.org (Class D registrations and renewals, 1950-77): a new parser beside `fetch_cce_renewals.py`.
3. **`shared/editorial/cce_renewals.json`**: already built; reuse for Lux and Screen Guild adaptations.
4. Copyright Office **online public records** (1978+ renewals and registrations; post-1972 radio registrations, e.g. CBSRMT, if registered).
5. **NCU notices** indexed by the Office: both our own filings and others' (UNVERIFIED that a public list exists; probe below).
6. Archive.org **darkened items** and `takedowns.json`.
7. **Wikidata** P6216 (copyright status) and P275 on radio-series and episode items: sparse; probe first.
8. Curated: `audio_claims.json`, `afrs_rebroadcast_series.json`, `audio_foreign_producers.json`, `licence_evidence.json`, `copyright_evidence_overrides.json`. Each entry needs a source a reader can open.

### 10.4 What fraction survives each tier: ESTIMATE, not measured

Basis: reasoning over the composition of the archive.org OTR collections as described in search results and general knowledge of the corpus. **No count was measured.** The probes below replace these numbers.

| Tier | Contents | Est. share of a typical archive.org OTR corpus |
|---|---|---|
| A. Strict-legal keep (gov, LibriVox, CC-corroborated, pre-1926 published) | AFRS originals, Treasury/OWI, LibriVox plays, a handful of records | **~3-10%** (AFRS-heavy; LibriVox drama is small) |
| B. A + NCU-cleared orphans | Unexploited, unscheduled, unclaimed episodes after filing | **+20-45%**, limited by filing effort and by how much is commercially exploited |
| C. Risk tier: all orphans with no claim (Q1 = keep) | Everything not hidden on evidence | **~55-75%** |
| Hidden on evidence (claims, takedowns, post-1972, foreign, renewed adaptations) | Shadow, Lone Ranger, Lum and Abner, X Minus One, renewed Lux episodes, CBSRMT, BBC | **~25-45%**, and **disproportionately the famous, most-listened series** |

The last row is the uncomfortable one. Archive Watch's film catalog loses a long tail of studio titles to renewals. A strict audio catalog would lose much of its marquee.

---

## 11. Questions for the owner (exact wording to put to them)

1. **Orphans.** "Federal law protects almost every pre-1972 radio recording until 2067, and most unregistered scripts for decades. Nobody is enforcing most of them, and no claim a reader can open exists. Do we (a) show only Tier A (government, LibriVox, Creative Commons, pre-1926 records), (b) show an episode with no claim found, hiding the moment a claim appears, or (c) show it only after a noncommercial-use notice has cleared 90 days?" Option (b) is Archive Watch's film temperament; for audio it means relying on a "not knowing" that the law does not support. That is why it is the owner's call.
2. **The NCU route.** "Will we file Notices of Noncommercial Use with the Copyright Office, recording by recording, as a free app with no ads? Should a lawyer confirm first that app-store distribution and a donate link don't make it commercial?"
3. **Commercially sold series.** "Where a series is sold by a licensee (Radio Spirits, licensed audiobooks), do we hide it even when no takedown or specific claim exists?" (NCU is closed for those episodes either way.)
4. **Scripts with no registration.** "Do we treat an unregistered network script as protected (hide unless the recording layer is a government or LibriVox work) or as unenforced (follow Q1)?"
5. **Music.** "Do variety and music shows full of popular songs get the same treatment as dramas, or a stricter one?"
6. **AFRS performers.** "Do AFRS originals with civilian stars count as government works (keep), or do we exclude episodes whose value is a commercial star's performance?"
7. **Non-US.** "Hide all non-US-origin productions unless licensed (proposed), or apply each country's terms?"
8. **Takedowns.** "If a licensee sends a takedown with a general claim (not naming episodes), do we hide the whole series (proposed: yes, recorded in `takedowns.json` with the letter) or ask for specifics?"
9. **Post-1972.** "Confirm: CBS Radio Mystery Theater and other post-1972 series are hidden unless we hold a licence."

---

## To measure (probes for a session with network access)

```bash
# 1. Does any radio program appear in the Copyright Office pre-1972 schedules?
#    (Open the search page; record whether it has a query API or only a form.)
curl -sS 'https://copyright.gov/music-modernization/pre1972-soundrecordings/search-soundrecordings.html' | head -200
#    Then search: "Shadow", "Lone Ranger", "Jack Benny", "Lux", "Suspense", "Gunsmoke",
#    "Dragnet", "Radio Spirits", "CBS", "NBC", "Condé Nast", "Lauck".

# 2. Read the NCU rule and the statute directly (notice size, fees, which services to search).
curl -sS https://www.copyright.gov/title37/201/37cfr201-37.html > /tmp/ncu.html
curl -sS https://www.govinfo.gov/content/pkg/USCODE-2023-title17/html/USCODE-2023-title17-chap14.htm > /tmp/1401.html
grep -n -i 'commercially exploited\|preempt\|(e)\|2067' /tmp/1401.html | head -50

# 3. The 2011 report's exact wording on radio and publication.
curl -sS -o /tmp/pre72.pdf https://www.copyright.gov/docs/sound/pre-72-report.pdf
pdftotext /tmp/pre72.pdf - | grep -n -i -B2 -A4 'radio\|transcription\|technically unpublished'

# 4. Lone Ranger v. Program Radio: the holding.
curl -sS https://law.resource.org/pub/us/case/reporter/F2/740/740.F2d.718.82-4690.html | sed 's/<[^>]*>//g' | less

# 5. CCE Dramas volumes on archive.org (registrations + renewals of Class D).
curl -sS 'https://archive.org/advancedsearch.php?q=title%3A%28%22catalog+of+copyright+entries%22%29+AND+title%3A%28dramas%29&fl%5B%5D=identifier&fl%5B%5D=year&rows=200&output=json'
#    Then grep the _djvu.txt of a 1940s registration volume for radio series names:
#    curl -sSL https://archive.org/download/<id>/<id>_djvu.txt | grep -i -n 'radio\|broadcast\|script' | head

# 6. How much of the OTR corpus is AFRS / government / LibriVox drama (sizes Tier A).
curl -sS 'https://archive.org/advancedsearch.php?q=collection%3Aoldtimeradio&fl%5B%5D=identifier&rows=0&output=json'
curl -sS 'https://archive.org/advancedsearch.php?q=collection%3Aoldtimeradio+AND+%28title%3AAFRS+OR+subject%3AAFRS+OR+title%3A%22armed+forces+radio%22%29&rows=0&output=json'
curl -sS 'https://archive.org/advancedsearch.php?q=collection%3Alibrivoxaudio+AND+subject%3A%28dramatic+reading%29&rows=0&output=json'
curl -sS 'https://archive.org/advancedsearch.php?q=collection%3Aoldtimeradio&fl%5B%5D=licenseurl&rows=2000&output=json' \
  | python3 -c 'import json,sys,collections; d=json.load(sys.stdin)["response"]["docs"]; print(collections.Counter(x.get("licenseurl") for x in d).most_common(10))'

# 7. Takedown signal: OTR items that are dark.
#    For a sample of identifiers from probe 6:
#    curl -sS https://archive.org/metadata/<id> | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("is_dark"), d.get("metadata",{}).get("title"))'
```

```sparql
# 8. Wikidata: radio programs carrying a copyright status (P6216) or licence (P275).
SELECT ?p ?pLabel ?status ?statusLabel ?lic ?licLabel WHERE {
  ?p wdt:P31/wdt:P279* wd:Q1555508 .          # radio program
  OPTIONAL { ?p wdt:P6216 ?status }
  OPTIONAL { ?p wdt:P275 ?lic }
  FILTER(BOUND(?status) || BOUND(?lic))
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
} LIMIT 500
```

Also confirm (UNVERIFIED above): the Flo & Eddie N.Y. 2016 opinion; §1401(e) preemption text; *Dastar* (539 U.S. 23, 2003); UK/Canada/Australia terms (legislation.gov.uk CDPA ss.13A, 14; Canada Copyright Act s.23; Australia Copyright Act s.93 + 2005 FTA amendments); LibriVox's PD dedication page; CBS Radio Mystery Theater rights holder; Superman radio rights (DC); the specific search list in 37 CFR 201.37.

---

## Sources

Statute and Copyright Office
- https://www.law.cornell.edu/uscode/text/17/1401
- https://www.govinfo.gov/content/pkg/USCODE-2023-title17/html/USCODE-2023-title17-chap14.htm
- https://copyright.gov/title17/92chap14.html
- https://www.copyright.gov/title17/chapter14.pdf
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/
- https://copyright.gov/music-modernization/pre1972-soundrecordings/search-soundrecordings.html
- https://www.copyright.gov/music-modernization/pre1972-soundrecordings/schedulefiling-instructions.html
- https://copyright.gov/title37/201/37cfr201-35.html
- https://www.copyright.gov/title37/201/37cfr201-37.html
- https://www.law.cornell.edu/cfr/text/37/201.37
- https://public-inspection.federalregister.gov/2019-06883.pdf
- https://www.govinfo.gov/link/fr/84/14255
- https://www.govinfo.gov/link/fr/84/1673
- https://www.copyright.gov/docs/sound/pre-72-report.pdf
- https://copyright.gov/newsnet/2011/446.html
- https://www.loc.gov/static/programs/national-recording-preservation-plan/publications-and-reports/documents/pub144.pdf
- https://law.justia.com/codes/us/title-17/chapter-3/sec-303/
- https://www.law.cornell.edu/uscode/text/17/303
- https://copyright.gov/title17/chapter3.pdf
- https://www.everycrsreport.com/reports/LSB10181.html
- https://www.authorsalliance.org/2024/12/29/public-domain-day-a-diversion-to-sound-recordings/
- https://commons.wikipedia.com/wiki/Template:PD-US-record-expired
- https://arsc-audio.org/blog/category/copyright/page/4

Cases
- https://www.nycourts.gov/REPORTER/3dseries/2005/2005_02570.htm (Capitol v. Naxos)
- https://www.law.cornell.edu/nyctap/I05_0027.htm
- https://en.wikipedia.org/wiki/Capitol_Records,_Inc._v._Naxos_of_America,_Inc. (Flo & Eddie 2016 characterization)
- https://law.resource.org/pub/us/case/reporter/F2/740/740.F2d.718.82-4690.html (Lone Ranger Television v. Program Radio)

CCE / scripts
- https://everybodyslibraries.com/2009/07/14/for-those-wanting-more-drama-in-their-lives/
- https://www.ibiblio.org/ccer/1923d1.htm
- https://www.ibiblio.org/ccer/1925d1.htm
- https://www.archive.org/download/catalogofcop196732134libr/catalogofcop196732134libr.pdf
- https://online.ucpress.edu/res/article/6/1/64/208432/Retailing-RadioThe-Industrial-Afterlife-of-Classic

Government works / AFRS
- https://archive.org/details/AfrsJubilee
- https://archive.org/details/AFRS-17
- https://hdl.loc.gov/loc.mbrsrs/eadmbrs.rs019006.3
- https://archives.nypl.org/rha/20439
- https://en.wikipedia.org/wiki/Command_Performance_(radio_series)
- https://en.wikipedia.org/wiki/Jubilee_(radio_program)
- https://en.wikipedia.org/wiki/Mail_Call_(radio_program)
- https://www.dennismspragg.com/wp-content/uploads/2025/03/THE-ARMED-FORCES-RADIO-SERVICE.pdf
- https://www.classicradiogallery.com/transcriptions/

Series claims, distributors
- https://en.wikipedia.org/wiki/The_Shadow
- https://thepulp.net/thatspulp/2017/07/14/lost-shadow-radio-shows-found/
- https://trademarkregistration.app/Trademark/Details/74639802
- https://b-westerns.com/triolost.htm
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
- https://www.otrr.org/OTRRLibrary/copyright.html
- https://otrrlibrary.org/copyright.html
- https://www.greatdetectives.net/detectives/about/copyright-questions/
- https://www.otrcat.com/otrcat-copyright-notice
- https://worldradiohistory.com/American-Radio-History-Take-Down.htm
- https://www.nitrateville.com/viewtopic.php?t=33137
- https://www.thefedoralounge.com/threads/vintage-or-modern-radio-drama-recommendations.54117/post-1175059

Archive Watch (internal, for the model being extended)
- /home/user/Archive-Watch/tools/audit_rights.py (`bucket()`, `HIDE_BUCKETS`)
- /home/user/Archive-Watch/tools/fetch_cce_renewals.py
- /home/user/Archive-Watch/shared/editorial/cce_renewals.json
- DECISIONS 137 (docs/decisions/DECISIONS-127-145.md), 140 (same), 151, 156, 157 (DECISIONS.md)
