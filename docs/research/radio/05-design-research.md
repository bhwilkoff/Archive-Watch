# 05 — Product and interaction design for an audio-first old-time radio app

*Research date: 2026-10-17. Track: product and interaction design. Status: research, nothing built.*

> **How to read this file.** The container's network policy blocked direct page
> fetches, so every external fact below comes from **web-search result
> summaries**, not from opening the page. Each claim names the URL the search
> surfaced it from. A claim marked **UNVERIFIED** is from general knowledge and
> was not confirmed by any search result in this session. The session's shared
> web-search budget (200 calls) ran out part-way through this track, so several
> planned checks (script libraries, WCAG wording, Library of Congress script
> holdings, CarPlay's official limits) are listed under **To measure** instead of
> answered. Facts about Archive Watch itself were read from this repository.

---

## Verdict

1. **The existing OTR apps are a weak field.** They compete on episode counts
   ("15,000 episodes", "40,000+ shows") and lose on the basics: ads, crashes and
   network failures, no continuous playback, no sleep timer, subscription
   confusion, Bluetooth crashes (§1.3). None shows evidence of verified
   metadata, rights review, de-duplication or broadcast-date ordering. The
   opportunity is Archive Watch's own method applied to sound: **one checked
   card per broadcast, ordered by the date it aired, with its rights stated.**
2. **The episodic model is the design problem, not the player.** OTR has at
   least seven series shapes (anthology, continuing character, multi-part serial,
   daily strip and soap, comedy and variety, news and actuality, the "broadcast
   day"). Each needs its own ordering, queue and "what plays next" rule (§2).
   Podcast apps' newest-first/serial split (Apple's `itunes:type`) is too coarse.
3. **A broadcast is a performance of a script, and copies of it are versions.**
   The same script aired many times (Suspense's "Sorry, Wrong Number" eight times,
   1943-1960; X Minus One's first 15 episodes re-performed Dimension X scripts),
   AFRS rebroadcasts were retitled and stripped of commercials (Lux became
   "Hollywood Radio Theater"), and collector files are mislabeled and duplicated
   across the web. The data model needs Work (script) → Broadcast (performance,
   dated) → Recording (copy) — the radio form of Decisions 040/143/158.
4. **The "radio evening" is the feature that passes the learning test best.**
   A real night's network lineup, reconstructed from newspaper radio logs
   (JJ's Newspaper Radio Logs: 45,000+ logs from four national papers,
   1930-1960) and played on Archive Watch's one-clock channel machinery
   (Decision 144), with gaps for what does not survive. The precedent is
   WJSV's complete broadcast day of 1939-09-21, recorded with the National
   Archives and on the National Recording Registry.
5. **The bridge to Archive Watch is real and checkable.** The local
   `catalog-index.json` holds the 1948 film *Sorry, Wrong Number* and *The 39
   Steps* (1935), both with documented radio counterparts (Suspense, Lux), and
   many other films that Lux adapted — UNVERIFIED per title until the Lux log is
   joined (§5.2).
6. **The audience is not only old.** One OTR podcast's self-selected survey
   found 47% of listeners under 45; Spotify data for two OTR shows skews under 35;
   broad radio research shows an average respondent of 58.4. Design for large type
   and simple control without designing "for seniors" (§7).
7. **The car is a first-class surface.** CarPlay and Android Auto are where
   long-form audio is heard; their templates (lists, few tabs, shallow stacks)
   should shape the information architecture from day one, not be ported later.
8. **Do not borrow podcast apps' silence trimming.** Overcast's Smart Speed
   shortens silences; in drama a pause is the performance. Loudness
   normalization (Voice Boost's other half) is the right borrowing, done once in
   the pipeline because OTR transfers vary wildly.

---

## §1 — Precedent teardown

### 1.1 General audio apps (what the category has taught listeners to expect)

| App | Pattern worth taking | Pattern to refuse | Source |
|---|---|---|---|
| **Apple Podcasts** | Two show types: *episodic* (newest first, default) and *serial* (oldest first; episode numbers required; seasons shown newest-season-first, episodes in sequence inside). Automatic, searchable transcripts since iOS 17.4 (2024): read along, search a phrase, tap a line to play from there; reachable from Now Playing. | Season-newest-first makes no sense for a 1940s anthology; a binary type is too coarse for OTR (§2). | [podcasters.apple.com numbering](https://podcasters.apple.com/864-best-practices-for-episode-numbering), [itunespartner order](https://itunespartner.apple.com/podcasts/whats-new/100002561), [Thurrott, transcripts](https://www.thurrott.com/apple/296763/apple-podcasts-will-provide-automatic-transcripts-on-ios-17-4), [pxlnv](https://pxlnv.com/linklog/apple-podcasts-transcripts/), [ppc.land](https://ppc.land/apple-podcasts-gets-more-accessible-with-automatic-transcripts) |
| **Overcast** | *Voice Boost*: dynamic compression + EQ that normalizes volume across shows (helpful in cars); settings app-wide with per-show override. | *Smart Speed*: shortens silences (~10% shorter per an early review). Drama's pauses, sound-effect beats and music cues are content — refuse. | [Macworld, Overcast 2.5](https://www.macworld.com/article/227600/overcast-25-review-patron-backed-podcast-app-gets-more-efficient-and-adds-exclusive-features.html), [Laughing Squid](https://laughingsquid.com/?p=409004) |
| **Pocket Casts** | Per-podcast "Sort Episodes: oldest first" + autoplay to play in release order; Smart Playlists (filters) with sort and "Play All" replacing Up Next. | A forum thread shows "sequential order" is still a request, i.e. a workaround rather than a model; filters are absent on web/desktop. | [Smart Playlists](https://support.pocketcasts.com/knowledge-base/episode-filters/), [queue help](https://support.pocketcasts.com/knowledge-base/playing-episodes-and-managing-your-queue/), [forum: sequential order](https://forums.pocketcasts.com/forums/topic/listen-to-episodes-in-sequential-order), [duplicate episodes](https://support.pocketcasts.com/knowledge-base/duplicate-episodes-2) |
| **Castro** | Inbox → Queue → Archive triage; per-show rules send new episodes to the top/bottom of the queue. One single playlist. | Reviewers note the Inbox/Queue difference confuses new users; gesture-heavy. An archive of 1940s radio has no "new episodes" stream to triage. | [Six Colors, Castro 2](https://sixcolors.com/post/2016/08/castro-2-inbox-triage-for-podcast-episodes/), [MacStories, Castro 3](https://www.macstories.net/reviews/castro-3-review-the-castro-youve-always-wanted/), [screensdesign](https://screensdesign.com/showcase/podcast-player-app-castro) |
| **Audible** | Sleep timer on the player itself, with **End of Chapter**; "shake to extend". Bookmarks and notes. | — | [Android Authority](https://www.androidauthority.com/audible-listening-settings-3667303/), [AppleVis](https://www.applevis.com/comment/44471) |
| **Libby** | Speed 0.6-3.0x; sleep timer presets (off, end of chapter, 15/30/60 min, slider); swipe to skip. | Reviews call the UI "convoluted", with hidden or unlabeled buttons and a Back that goes to the main page — the accessibility failure to avoid. | [App Store listing](https://apps.apple.com/app/libby-by-overdrive-labs/id1076402606), [Aurora PL blog](https://aurorapl.ca/blogs/post/get-to-know-libby/) |
| **Spotify** | Chapters listed by scrolling down Now Playing; transcripts followable full screen from Now Playing; desktop puts description + transcript in a right-hand panel. | No 2025 source found on how its audiobook player differs from podcasts (gap). | [Siasat, transcripts and chapters](https://www.siasat.com/spotify-to-roll-out-auto-generated-transcripts-to-millions-of-podcasts-2708393/), [RouteNote, desktop](https://routenote.com/blog/spotify-updates-desktop-apps/), [Spotify community](https://community.spotify.com:443/t5/Implemented-Ideas/All-Platforms-Bookmark-Position-in-an-Audiobook-or-Podcast/idc-p/1203821) |
| **BBC Sounds / Radio 4 Extra** | The closest institutional precedent: a station whose whole schedule is the spoken-word archive (comedy, drama, documentary repeats); *Drama on 4* and Radio 4 Extra's *Whodunnits* ranked in the top ten on-demand radio programs (Q4 2024 report). Proves archive drama sustains a scheduled channel. | The BBC announced in May 2022 that Radio 4 Extra would stop as a broadcast station "after the next few years", to be supplanted by Sounds; whether it continues as a Sounds stream was not confirmed. Sounds closed to non-UK users from 2025-07-21. No search confirmed a "Sounds Mixes" drama stream. | [Wikipedia, Radio 4 Extra](https://en.wikipedia.org/wiki/BBC_Radio_4_Extra), [Chortle 2022](https://www.chortle.co.uk/news/2022/05/26/50864/bbc_to_axe_radio_4_extra), [RadioToday 2025](https://radiotoday.co.uk/2025/07/bbc-sounds-to-close-for-international-users-from-21-july-2025/), [hiresaudio Q4 2024](https://www.hiresaudio.online/?p=10285), [Broadcast, box sets](https://www.broadcastnow.co.uk/bbc/bbc-sounds-launches-christmas-box-sets/5135090.article) |
| **LibriVox apps** | Not researched — search budget exhausted. UNVERIFIED expectation: third-party LibriVox players expose book → section ordering, the closest analog to multi-part serials. | — | To measure |

### 1.2 Existing OTR apps and streams

| Product | What it is (per search summaries) | Source |
|---|---|---|
| **Vintage Radio / Vintage Radio Lite** (iOS) | Lite: 1,000+ episodes from 100 programs, "no annoying ads". Full: 4,000 free episodes, subscription for 40,000+ across 550 programs ($1.99/mo, $10.99/6 mo, $19.99/yr). 4.4 stars from 162 ratings. AppGoblin estimates ~749 monthly active users. AppleVis users (2012) found Lite fully VoiceOver-accessible. | [App Store](https://apps.apple.com/us/app/-/id455577974), [Lite](https://apps.apple.com/us/app/-/id324517232), [AppGoblin](https://appgoblin.info/apps/455577974), [Engadget 2012](https://www.engadget.com/2012-01-26-daily-iphone-app-vintage-radio.html), [AppleVis](https://applevis.com/comment/1737) |
| **Old Time Radio Shows** (iOS, Taha Maddam) | 710+ shows, playlists, speed control; 3.6 stars from 99 ratings; "collects no data". | [App Store](https://apps.apple.com/us/app/old-time-radio-shows/id1438072504) |
| **OTR Player** | 15,000+ episodes from 130+ shows, free; Google Play 4.1 from 588 reviews (per Grand Screen); "ads can get old", basic interface. | [App Store](https://apps.apple.com/app/id1493221239), [Grand Screen](https://grand-screen.com/apps/old-time-radio-player/) |
| **Old Time Radio Streamer** (Oddsock, iOS/Mac) | Free, ad-free; developer has not declared accessibility support. AppleVis covered a separate "OTR Streamer" (2015, 5,000+ episodes, streaming only). | [App Store](https://apps.apple.com/app/id889955088), [AppleVis podcast](https://applevis.com/podcasts/enjoy-taste-old-time-radio-otr-streamer-ios) |
| **Dumb.com — Old Radio Shows** | 2.9 stars from 111 ratings. | [App Store](https://apps.apple.com/app/id567195102) |
| **Radio Spirits** (iOS/Android) | Commercial rights-holder/licensor. Free tier carries *When Radio Was* (host Greg Bell) and recent shows; 1/3/6/12-month subscriptions for on-demand library and downloads; listing not updated since 2022. | [App Store](https://apps.apple.com/us/app/id389211220), [AppGoblin](https://appgoblin.info/apps/389211220), [Consumer Cellular](https://www.consumercellular.com/blog/smartphone-apps-of-the-month-november-edition/) |
| **SiriusXM Radio Classics** (ch. 148) | Greg Bell, program director/host since 2002; restored dramas, comedies, westerns, anthologies; **two-hour blocks rotated across time slots during the week**; XM and Sirius channels merged 2009-02-01. | [Wikipedia](https://en.wikipedia.org/wiki/Radio_Classics), [SiriusXM schedule](https://www.siriusxm.com/radioclassics/weeklyschedule) |
| **When Radio Was** | Syndicated Radio Spirits program; Bell its fourth national host from 2007-10-08. | [Wikipedia](https://en.wikipedia.org/wiki/When_Radio_Was) |
| **Yesterday USA** (Richardson, TX) | "America's oldest streaming site playing old time radio, since 1983"; 24/7; Red and Blue feeds; a 2009 post says stream only, no on-demand. | [Streema Red](https://streema.com/radios/Yesterday_USA_Red), [Streema Blue](https://streema.com/radios/Yesterday_USA_Radio), [Cadenhead clipping](https://workbench.cadenhead.org/clippings/yusa.shtml), [ARSC list 2009](https://cool.culturalheritage.org/byform/mailing-lists/arsclist/2009/01/msg00009.html) |
| **Old Time Radio USA / WOTR** | Stream that runs *Classic Radio Rewind*; airs "WJSV: A Day In Radio History" starting at the original 5:58 am ET sign-on; anniversary specials (D-Day coverage). | [Classic Radio Rewind episodes](https://play.cdnstream1.com/s/WOTR/classic-radio-rewind-old-2937a9/episode-25-august-20th-2-ea98db), [D-Day special](https://play.cdnstream1.com/s/WOTR/classic-radio-rewind/d-day-remembrance-specia-9ce7d3), [myTuner](https://mytuner-radio.com/radio/old-time-radio-usa-469299/) |
| **RadioEchoes** | A 2018 directory listing: 95,000+ programs free to stream or download, 21 genres, accepts MP3 donations. Current state unconfirmed. | [informationnow](https://www.informationnow.org.uk/organisation/radioechoes-com/) |
| **Tuned to Yesterday** (WRVO) | Public-radio OTR program with a "TTY Dialer" companion podcast of "date-specific stories". | [WRVO](https://www.wrvo.org/tuned-to-yesterday), [TTY Dialer](https://www.wrvo.org/tuned-to-yesterday/2017-05-20/tty-dialer-podcast-30) |
| **"OTR Plus", "Radio Once More"** | Not found by search under those names. UNVERIFIED that they exist as named. | — |

### 1.3 What users love and hate (the evidence available)

The search tools could not read review pages, so this is what review
**summaries** say, not a corpus analysis.

- **Love: the size and quality of the library.** "The selection is really
  amazing" (Engadget on Vintage Radio); "excellent sound quality and a large,
  growing catalog" (aggregator on Radio Spirits); audio "better than expected"
  (Grand Screen on OTR Player).
- **Hate: ads** (OTR Player, Grand Screen).
- **Hate: reliability** — "network errors/crashes" (Radio Spirits), crashes and
  download failures (OTR Player, per a chrome-stats summary of uncertain
  accuracy), a crash when pausing for a phone call over Bluetooth and when
  switching Bluetooth devices (Vintage Radio App Store review).
- **Hate: missing basics** — "continuous playback, skip controls, sleep timer"
  (Radio Spirits aggregator summary).
- **Hate: money confusion** — "pricing very confusing ... not entirely clear
  which shows are paid or free" (Engadget 2012); a subscriber repeatedly told
  their subscription had expired (Vintage Radio).
- **The problem none of the apps addresses: bad files.** Collectors document it
  in their own words:
  - a *Chandu the Magician* file ("Aug 24, 1948: Letter Arrives") is a duplicate
    of the previous episode, and "everyone they checked on the internet had the
    same duplicate error", including archive.org copies
    ([macinmind journal 2019](https://radio.macinmind.com/journal-2019.php));
  - *Our Miss Brooks* downloads with "misnamed episodes ... many files that
    turned out to be bogus" ([archive.org OurMissBrooks](https://archive.org/details/OurMissBrooks));
  - three 1940 Jack Benny files with different titles are the same show, "an
    occupational hazard in OTR collecting" ([jackbenny.org forum](https://jackbenny.org/phpBB3/viewtopic.php?p=250));
  - vendors sold *Inner Sanctum* duplicates under alternate titles, and AFRS
    rebroadcasts had their titles removed ([OTRR newsletter, 2012](https://www.otrr.org/FILES/Times_Archive_pdf/2012_05-06MayJun.pdf)).

**Design consequence**: the product's credibility is its catalog hygiene. A
listener who hits the same episode twice under two titles has learned the app
does not know its own content. That is the radio form of Archive Watch's
dedup (Decision 040) and the "an uploader's word is not enough" rule (Decision
140), and it must be visible: a card says when it is a known duplicate,
retitling or AFRS version (§2.3).

---

## §2 — The episodic model unique to OTR

### 2.1 Series shapes (each a value of a `seriesKind` field)

| Kind | Examples (sourced) | Unit a listener chooses | Order inside the series | What "play next" means |
|---|---|---|---|---|
| **Anthology** | *Suspense*, *Lux Radio Theatre* (1934-10-14 to 1955-06-07; 926 or 927 episodes by source), *Escape*, *X Minus One* (NBC 1955-04-24 to 1958-01-09, 126 episodes) | the story | broadcast date, but any entry point is valid | the next broadcast, or another story sharing a person/author (Decision 139 "says why") |
| **Continuing character** | *Yours Truly, Johnny Dollar* (half-hour years), *Dragnet* | the episode, but the listener follows the character | broadcast date; resume per series | the next broadcast |
| **Multi-part serial** | *Johnny Dollar* from October 1955: 15 minutes, Monday-Friday, five-part stories (e.g. "The Laughing Matter", 1956-06-11 to 06-15; one nine-part story in 1956); *The Adventures of Superman* (syndicated on WOR from 1940-02-12; Mutual 15-minute serial 1942-08-31 to 1949-02-04; 2,088 episodes overall) | the **story arc** | strict part order | the next part, always; at the arc's end, stop or offer the next arc |
| **Daily strip / soap** | *Ma Perkins* (1933-08-14 to 1960-11-25, 15 minutes daily, 7,065 broadcasts, Virginia Payne throughout; survival of early episodes "very rare") | a week or a story line | strict date order | the next weekday's episode; gaps are normal |
| **Comedy / variety** | *The Jack Benny Program* (AFRS: "The Lucky Strike Program" became "The Jack Benny Program") | the episode | broadcast date by season; running gags reward order but do not require it | next broadcast |
| **News / actuality** | CBS's D-Day coverage of 1944-06-06 (aired as an anniversary special by Classic Radio Rewind) | the event | clock time within the day | the next piece of the same day's coverage |
| **Broadcast day** | WJSV, Washington, 1939-09-21, sign-on to sign-off (soaps, Godfrey, FDR's address to Congress, baseball, *Amos 'n' Andy*, station breaks and commercials) | the day, or an hour of it | clock time | the next thing that aired |

Sources: [Lux](https://en.wikipedia.org/wiki/Lux_Radio_Theatre),
[X Minus One](https://en.wikipedia.org/wiki/X_Minus_One),
[Johnny Dollar](https://en.wikipedia.org/wiki/Yours_Truly,_Johnny_Dollar),
[Radio Archives JD vol. 2](https://www.radioarchives.com/Yours_Truly_Johnny_Dollar_Volume_2_p/ra124.htm),
[Superman](https://en.wikipedia.org/wiki/The_Adventures_of_Superman_(radio_series)),
[Ma Perkins](https://en.wikipedia.org/wiki/Ma_Perkins),
[rand's esoteric otr](https://randsesotericotr.podbean.com/e/ma-perkins-pgm-423/),
[AFRS retitling](https://www.museum.tv/radio-encyclopedia/armed-forces-radio-service),
[D-Day special](https://play.cdnstream1.com/s/WOTR/classic-radio-rewind/d-day-remembrance-specia-9ce7d3),
[WJSV](https://en.wikipedia.org/wiki/WJSV_broadcast_day),
[NARA 2004 press release](https://www.archives.gov/press/press-releases/2004/nr04-39).

**Series change kind over their life.** Johnny Dollar is half-hour weekly,
then a five-part strip (1955-56), then half-hour again; Superman is a 15-minute
serial, then half-hour (per the search summary). So `seriesKind` belongs to a
**run** (a dated span of a series), not to the series. A series page is a list
of runs.

### 2.2 Seasons: years, or broadcast seasons?

- Network radio planned by **season** (fall to early summer, with summer
  replacements). Shapiro's *Radio Network Prime Time Programming, 1926-1967*
  organizes its grids month by month per network and night, and Jim Ramsburg's
  *Gold Time Radio* writes a profile per season (e.g. 1946-1947) with a Top 50
  by Crosley, Hooper or Nielsen rating ([McFarland](https://mcfarlandbooks.com/?p=17759),
  [Gold Time 1946-47](https://www.worldradiohistory.com/OUTSIDE-SITES/Jim-Ramsburg/Gold-Time-1946-1947.htm)).
- **Recommendation**: group episodes by **broadcast season** ("1949-50") where a
  log gives the dates, labeled as such; fall back to calendar year only where the
  series ran in calendar terms (soaps run continuously; a "season" there is noise).
  Never invent "Season 1, Season 2" numbering — it is not in the data and would
  imply an order the broadcasters never used. Owner question Q3.
- Oldest first within a season, always. Unlike Apple's serial type, **seasons
  also run oldest first**: nobody approaches the 1950s Suspense before the 1940s
  because it is "newer".

### 2.3 The things podcast models do not have

| Phenomenon | Evidence | Model |
|---|---|---|
| **Repeat performances of one script** | "Sorry, Wrong Number" on Suspense 8 times, 1943-05-25 to 1960-02-14, Agnes Moorehead each time ([Wikipedia](https://en.wikipedia.org/wiki/Sorry,_Wrong_Number), [Stars on Suspense](https://starsonsuspense.libsyn.com/bonus-eighty-years-of-wrong-numbers)); X Minus One's first 15 episodes were new performances of Dimension X scripts ([Wikipedia](https://en.wikipedia.org/wiki/X_Minus_One), [SFE](https://sf-encyclopedia.com/entry/x_minus_one)) | A **Work** (script/story) with several **Broadcasts**. A broadcast's Detail lists "other performances" as a fact, and comparing two performances is a learning feature in its own right (§5). |
| **Rebroadcast / retitled versions** | AFRS "decommercialized" network shows; Lux became *Hollywood Radio Theater* and, per the Jimmy Stewart site, *Broadway Playhouse*; *High Adventure* reported as *Radio Novel* (single site) ([museum.tv](https://www.museum.tv/radio-encyclopedia/armed-forces-radio-service), [OTRCAT](https://otrcat.com/p/hollywood-radio-theater), [jimmystewartontheair](https://jimmystewartontheair.com/broadway-playhouse), [VRS](https://vintageradioshows.com/shows/radio-novel)); Mackenzie's *Directory of the AFRS Series* (Greenwood) is the reference | An AFRS disc is a **Recording of the same Broadcast** (or a separate dated rebroadcast). It belongs in the versions picker, never as its own card. Default to the domestic network copy with its commercials when it survives (the ads are history, §5.4). |
| **East/West or network/local double airings** | A comparison of four logs found all agree on 1947-08-17 except one (08-18), because the script listed both a network airing and a WOR airing ([quietplease.org forum](https://www.quietplease.org/forum/general/-logs-compared-and-the-results-352.html)) | `broadcastDate` carries a source and a precision; disagreeing logs are recorded, not averaged. |
| **Auditions (pilots)** | Recorded for sponsors/networks, with placeholder commercials such as the fictitious "Klean Soap"; the 1952 *I Love Lucy* radio audition was never broadcast ([OTRR, Klean Soap](https://www.otrr.org/FILES/Articles/Danny_Goodwin_Articles/Klean%20Soap.pdf), [DAHR Victor auditions](https://adpprod1.library.ucsb.edu/index.php/matrix/refer/800040201), [Down These Mean Streets](https://downthesemeanstreetspodcast.libsyn.com/bonus-five-favorites-auditions)) | `broadcastKind = audition`; sorted first in a series (before the premiere), labeled AUDITION, never counted as an episode number. |
| **Missing episodes** | Ma Perkins' 7,065 broadcasts against a handful of surviving early recordings; Haendiges logs mark "*na*" for "not available" ([otrsite log sample](https://otrsite.com/logs/loga1031.htm)) | A log row with no recording is a **gap**. Shown in a serial (a missing Part 3 is a warning the listener needs), collapsed in an anthology (a gap there is not a decision). |
| **Duplicates and mislabels** | §1.3 | Pipeline: audio fingerprint dedup (separate data track) + human correction file, exactly like `title_corrections.json`. The UI states a merge only through the versions picker. |

### 2.4 Queueing rules by kind (proposed)

- **Anthology**: tapping play plays that story. At its end, continue to the next
  broadcast in date order (the original listener's experience) — but the end card
  also offers a thread with its reason: "Also with Agnes Moorehead", "Another
  Lucille Fletcher script" (Decision 139's pattern).
- **Continuing character**: resume the series where the listener left it; "next"
  is the next broadcast.
- **Serial**: the arc is the unit. Starting Part 3 asks nothing but shows "Part 3
  of 5" on the player; the queue plays to the arc's end and **stops**, with the
  next arc offered. A missing part shows in the arc list as a gap and the player
  says so before skipping it (a WARNING the listener would not otherwise know).
- **Strip / soap**: an optional **"On its schedule"** mode — one episode
  unlocks per real day on the weekday it aired. Novel, learning-oriented (it
  recreates the cliffhanger's wait and the habit soaps were designed around),
  and opt-in. Owner question Q6.
- **News / broadcast day**: plays in clock order; the player shows the original
  wall-clock time ("2:41 pm ET, 21 September 1939").

---

## §3 — Audio-first browsing with no posters

### 3.1 What artwork exists (and what must not be used)

- **Series art** is the scarce asset. Candidates, each needing its own rights
  check by the rights track: network publicity photographs of casts at the
  microphone, sponsor print advertisements in period magazines, and radio-guide
  covers. *Radio Guide* (weekly 1931-02/1943, monthly to November 1943, up to 14
  regional editions; predecessor of TV Guide) is scanned at worldradiohistory.com
  ([master page](https://www.worldradiohistory.com/Radio_Guide_Master_Page.htm)).
  The Media History Digital Library (Lantern) has OCR-searchable *Radio Mirror*
  (1934-1963), *Radio Digest*, *Radio Annual*, *Sponsor* (1946-1964) per a 2013
  launch list ([infodocket](https://www.infodocket.com/2013/08/12/reference-media-history-old-film-journals-and-mags-now-searchable-for-everyone-via-lantern-database-over-800000-pages-available/), [MHDL how-to](https://mediahist.org/about/howto.php)).
  Copyright status of these magazines per year is **UNVERIFIED** here (rights track).
- **Do not** use modern collector-label artwork (the CD/MP3-set covers on
  archive.org items) as if it were the show's art: it is the radio form of "never
  ship a modern poster on a vintage title" (iOS-DESIGN §1.6).
- **Do not** reshape any photograph: fit at its own aspect over an ambient wash
  (Decision 097).
- Episodes almost never have art of their own; the design must look complete
  without it.

### 3.2 Typography-first cards

Most cards will carry no image. That is a strength if the type does the work
(the density rule: "density comes from removing chrome").

- **Series card**: series title in the display weight; one meta line
  (`CBS · 1942-1962`); a thin genre accent rule along one edge (§3.3); a
  period photograph only when one exists and has passed rights. No image →
  no placeholder graphic, no microphone clip-art.
- **Episode row** (a list, not a grid — the same guidance Android gives for
  car screens: lists where the text describes the content, grids where art
  identifies it, [Android Developers Blog](https://android-developers.googleblog.com/2018/12/improve-media-and-messaging-app.html)):
  `1943-05-25 · Sorry, Wrong Number · Agnes Moorehead` with duration and a
  progress mark. Date first, because in radio the date is the identity.
- **Six levels only** (three weights × two sizes, CLAUDE.md). Concretely:
  series title, episode title, people (body), date and network (caption),
  section heading, eyebrow (ON NOW / AUDITION / PART 3 OF 5). A seventh is a
  refactor.
- **The date is set in tabular figures** so a column of broadcast dates aligns.

### 3.3 Semantic accents for radio genres

Archive Watch's split is binding: brand colors for chrome, semantic colors for
content meaning only (Decision 013). Proposed mapping, reusing an existing
accent wherever the meaning is the same so the two apps read as one family:

| Radio genre | Accent | Reasoning |
|---|---|---|
| Drama / anthology | `#FF5C35` (Feature Film) | the "feature" of radio; Lux is literally films |
| Mystery / detective / crime | `#2D5BFF` (Classic TV) | the series form; continuing-character shows |
| Science fiction & fantasy | `#7C5BBA` (Ephemeral's violet) | NEW meaning on an old hue — owner call |
| Western | `#C9A66B` (Silent Era's gold) | NEW meaning — owner call |
| Comedy / variety | `#FF4D8D` (Animation's pink) | NEW meaning — owner call |
| News / wartime / actuality | `#8A8F98` (Newsreel) | same meaning |
| Documentary / education / public affairs | `#3FA796` (Documentary) | same meaning |
| Serials & soaps (15-minute strips) | `#E8A317` (Short Film) | short form |
| Horror / supernatural (*Lights Out*, *Inner Sanctum*) | would be a ninth color | refuse a ninth; fold into Mystery, owner call Q8 |

The rule to keep: genre from **data** (archive.org subjects, Wikidata genre,
log genre fields), never from a model's reading of the title (CLAUDE.md, "No
AI-written lists").

### 3.4 The Now Playing screen without a poster

- Large series title, episode title, date, network, and the **cast and
  credits list as text** — in radio, the people are the picture.
- If a transcript or script exists: the current line, large (§7).
- Optional period photograph of the series behind it, fitted, dimmed. No fake
  waveform animation: it is decoration that says nothing (density rule).

---

## §4 — The "radio station": evenings on one clock

### 4.1 Precedents

- **WJSV, 1939-09-21**: the first comprehensive recording of a station's
  broadcast day, made with the National Archives; discs donated to NARA; added
  to the National Recording Registry in its second annual list (2004)
  ([Wikipedia](https://en.wikipedia.org/wiki/WJSV_broadcast_day),
  [NARA 2004](https://www.archives.gov/press/press-releases/2004/nr04-39)). Sources
  differ on sign-on (6:00 vs 6:30 am; WOTR uses 5:58 am ET). A commercial
  remaster exists ([Blackstone](https://www.blackstonelibrary.com/one-day-in-1939)),
  so rights of specific transfers need the rights track.
- **SiriusXM Radio Classics** rotates two-hour blocks across time slots
  ([Wikipedia](https://en.wikipedia.org/wiki/Radio_Classics)) — a curated
  schedule, but not a historical one.
- **WOTR** replays WJSV in real time from its original sign-on clock, and airs
  anniversary specials such as D-Day coverage (§1.2).

### 4.2 Sources to reconstruct a real evening

| Source | What it gives | Source URL |
|---|---|---|
| **JJ's Newspaper Radio Logs** | 45,000+ newspaper radio logs from the NYT, Washington Post, Chicago Daily Tribune and LA Times, 1930-1960, per-date pages, OCR text search ("results may vary") | [jjonz.us/RadioLogs](https://www.jjonz.us/RadioLogs/) |
| *Radio Guide* scans | weekly listings 1931-1943, regional editions | [worldradiohistory](https://www.worldradiohistory.com/Radio_Guide_Master_Page.htm) |
| Lantern / MHDL | *Radio Daily*-family annuals, *Variety Radio Directory* (1940), *Radio Annual* (1942) | [Variety Radio Directory 1940](https://lantern.mediahist.org/catalog/varietyradiod19401941vari_0035), [Radio Annual 1942](https://lantern.mediahist.org/catalog/radioannual194200radi_0870), [Radio Daily 1949](https://lantern.mediahist.org/catalog/radiodailyoctdec49unse_0005) |
| Shapiro, *Radio Network Prime Time Programming 1926-1967* | month-by-month prime-time grids per network and night | [McFarland](https://mcfarlandbooks.com/?p=17759) (print; a reference to check against, not a feed) |
| Keith D. Lee, *Los Angeles Old-Time Radio Schedule Book* vol. 2 (1938-1945) | local schedule reference | [BearManor](https://www.bearmanormedia.com/products/the-los-angeles-old-time-radio-schedule-book-volume-2-1938-1945-by-keith-d-lee) |
| Episode logs (Haendiges, radioGOLDINdex) | per-episode air dates for the surviving recordings | [otrsite.com](https://otrsite.com/), [Great Detectives' research list](https://www.greatdetectives.net/detectives/my-favorite-old-radio-research-resources/) |

Chronicling America's coverage of 1940s listings was not confirmed (search gap).

### 4.3 The feature, stated as data

**"Tonight in 1947"** — a channel whose evening is a real network's evening:

1. Pick a date (rule over data: e.g. the same weekday N years ago, or a date
   whose surviving coverage is highest — owner question Q4).
2. From a newspaper log, the network's slots for that evening (time, program).
3. For each slot, the recording of **that program's broadcast on that date**
   if it survives (episode log join). A different date's episode in that slot
   is **refused**: it would be a fabricated evening.
4. A slot with no surviving recording plays as an honest gap: a short station
   card ("*Mr. District Attorney* aired here; no recording is known to
   survive.") and moves on — or the evening is only offered where coverage
   exceeds a floor. Publishing only what survives is the "not knowing is not a
   claim" discipline turned to programming.
5. Published by the pipeline as one UTC timeline in `channel-schedule.json`
   form (Decision 144), drawn in the listener's local time, with the
   original Eastern time shown as the fact it is ("aired 9:00 pm ET").

**"This day in radio"** — broadcasts whose air date is today's month and day,
any year; a shelf, computed in the pipeline (Decision 050), hidden under the
platform's shelf floor. It needs `broadcastDate` with day precision, so its
size is an open measurement (To measure §M4).

### 4.4 The learning-orientation test

The `learning-orientation-design` skill was not available in this container,
so the test below uses CLAUDE.md's own wording.

| Question (CLAUDE.md "Why we build") | Tonight in 1947 | This day in radio | Autoplay forever |
|---|---|---|---|
| Invites fuller engagement? | Yes: the listener hears what a family heard in sequence — the news, the commercial, the comedy that followed the war bulletin | Yes: a date is a door to an event | No |
| Invites critical thinking? | Yes: the era's advertising, its assumptions, wartime messaging in context (the propaganda question returns — Decision 149's reasoning applies to WWII radio, owner Q9) | Partly | No |
| Connects more meaningfully? | Yes: shared clock means two people hear the same evening (Listen Together) | Yes: anniversaries are shareable | No |
| Makes the person more passive? | It is lean-back — but bounded (an evening ends at sign-off) and every slot opens its context | No | Yes |

Verdict: **passes**, provided the evening is real (step 3's refusal) and each
slot has the lean-in affordance (tvOS-DESIGN §9.0(c): "now playing / what is
this / more like this").

---

## §5 — Learning orientation: making listening active

### 5.1 The tension

Radio was designed to be lean-back, and so is a car. The reconciliation is
the one tvOS-DESIGN §9.0 already states: a lean-back mode is allowed if it has
a visible exit, honors Back, and offers **one lean-in affordance**. For audio:

- Lean-back is **bounded**: a serial arc ends; an evening ends at sign-off; a
  sleep timer can end at the end of an episode (Audible/Libby precedent).
  There is no infinite autoplay of unrelated content.
- Lean-in is **one tap away**: who is this, what is this script, where else
  did this actor work, what else aired that night.

### 5.2 Cross-links to Archive Watch films

Lux Radio Theatre adapted current films with their stars where it could
(paying ~$5,000 an appearance; Hollywood era from 1936-06-01, DeMille host
to 1945-01-22) ([Wikipedia](https://en.wikipedia.org/wiki/Lux_Radio_Theatre)).
The Criterion Channel itself pairs films with their Lux adaptations
([*The Lady Eve*](https://criterionchannel.com/videos/the-lady-eve-on-lux-radio-theatre),
[*The 39 Steps*](https://criterionchannel.com/videos/the-39-steps-lux-radio-theatre-adaptation))
— external validation that the pairing is something viewers value.

Checked against this repo's `catalog-index.json` (35,290 rows, schema 15):

| Film in Archive Watch's index | Radio counterpart | Status |
|---|---|---|
| *Sorry, Wrong Number* (1948) | Suspense, 8 performances 1943-1960; Fletcher adapted it for the film | radio link SOURCED (above) |
| *The 39 Steps* (1935) | Lux Radio Theatre adaptation | SOURCED (Criterion page) |
| *My Man Godfrey* (1936), *Meet John Doe* (1941), *Nothing Sacred* (1937), *A Star Is Born* (1937), *Penny Serenade* (1941), *Made for Each Other* (1939), *Of Human Bondage* (1934), *Algiers* (1938), *The Stranger* (1946), *Angel and the Badman* (1947), *Little Lord Fauntleroy* (1936) | believed to have Lux (or Screen Guild) adaptations | in the index; radio link **UNVERIFIED** — join against a Lux log (§M5) |
| *It's a Wonderful Life* (1946) | Lux 1947 adaptation (UNVERIFIED) | **not** in the local index (absent or hidden) |

Rule: a link is made by a log join (title + year window + shared cast), never
by a model, and it says why ("Lux adaptation, with Barbara Stanwyck"), like
Decision 139. The radio broadcast's rights are judged on its own; a public
domain film does not make its radio adaptation public domain (or vice versa).

### 5.3 People pages

An actor's radio and film work together (Agnes Moorehead on Suspense and in
films; Bud Collyer as radio Superman, in the Fleischer cartoons and as a TV
game-show host, [Wikipedia](https://en.wikipedia.org/wiki/Bud_Collyer)).
Keyed on Wikidata person ids so both apps share one identity. Writers and
directors matter more in radio than posters do (Lucille Fletcher; Ernest
Kinoy and George Lefferts wrote most of X Minus One's later episodes).

### 5.4 Other active-listening features (data only)

- **Scripts alongside audio** where a script survives and its rights allow
  (the script-library question is for the sources track; not searched here).
- **Source stories**: X Minus One adapted Astounding and Galaxy stories
  (Sheckley, Bradbury, Heinlein) — link the story's own public-domain text
  where it exists.
- **Other performances of this script** (§2.3) — compare Moorehead in 1943
  and 1960.
- **The commercials are content.** Do not offer "skip ads" on a 1940s
  broadcast; offer a chapter list (program / commercial / station break) when
  the data has it. The sponsor is a fact on the card ("Sponsor: Roma Wines").
  Spotify and Apple already expose chapters on Now Playing (§1.1).
- **Era context** comes from data (the date's other broadcasts, the news
  that night), never from written blurbs.
- **Listen Together**: the radio form of a Watch Together room (Decisions
  143, SHAREPLAY §11): the host's copy, every guest plays that file, synced
  by archiveID and position. Radio is easier than film (no video sync), and
  the shared-clock evening is a room by construction.

---

## §6 — Surfaces per platform

| Surface | What it is for | Constraints found | Design response |
|---|---|---|---|
| **Phone** | browse, queue, listen anywhere | lock screen / Now Playing metadata | full chapter + progress metadata; sleep timer and speed on the player itself |
| **CarPlay** | the main listening place for long-form audio | Requires the audio entitlement (`com.apple.developer.carplay-audio`, request via developer.apple.com/contact/carplay); third-party guides say audio apps get max **4 tabs** in `CPTabBarTemplate`; stack depth is disputed (one source 5, a forum reply 2); metadata updates are throttled ("exceeded audio metadata throttle limit") — all from non-Apple pages, confirm in Apple's docs | four tabs: Continue · Radio · Series · Downloads. Lists, not grids. No transcript in the car. Minimize Now Playing updates. ([skills.sh](https://skills.sh/ios-agent/iosagent.dev/carplay), [Apple forum](https://developer.apple.com/forums/thread/813008)) |
| **Android Auto** | same | Browse tree from a media service; content styles set per root (`DESCRIPTION_EXTRAS_KEY_CONTENT_STYLE_BROWSABLE` / `_PLAYABLE`); lists for episodes, grids where art identifies ([content styles](https://developer.android.com/training/cars/media/create-media-browser/content-styles)) | same four roots as CarPlay; episodes as lists |
| **TV (tvOS, Google TV, Fire TV, Roku, web-TV)** | lean-back evenings, family listening | a big screen with no picture | Now Playing fills the screen with typography: series, episode, date, cast; the current transcript line large; the evening's schedule as a guide (Rule 9.1 machinery). Fitted period photograph if one exists. The TV is where "Tonight in 1947" is most natural. |
| **Watch** | runs, walks | Standalone streaming since watchOS 6: point `AVQueuePlayer` at an HLS audio feed; `WKAudioFilePlayer` only plays to Bluetooth headphones; a watchOS 27 route-change delay report ([WWDC19 716](https://developer.apple.com/videos/play/wwdc2019/716), [Apple forum](https://developer.apple.com/forums/thread/849255), [marco.org](https://marco.org/2017/09/24/what-watch-podcast-apps-need)) | Continue + downloaded episodes only; no browsing on the wrist |
| **Smart speakers** | "play Suspense" | Alexa's `AudioPlayer` interface is still documented ([Amazon](https://developer.amazon.com/docs/custom-skills/audioplayer-interface-reference.html)); Google's Conversational Actions were shut down 2023-06-13, Media Actions unaffected ([Google](https://developers.google.com/assistant/ca-sunset)) | a "side door" by CLAUDE.md's rule? Owner question Q10 |
| **Web** | the share target and the floor for old devices | vanilla JS, no build step (CLAUDE.md) | Media Session API for lock-screen controls (UNVERIFIED detail); the same IA |

---

## §7 — Accessibility and audience

### 7.1 Who listens

- **The Great Detectives of Old Time Radio** podcast survey (self-selected): 64%
  male; **47% under 45**, 96% under 65 ([Great Detectives](https://www.greatdetectives.net/detectives/whos-listening-to-our-podcast/), [listeners](https://www.greatdetectives.net/detectives/listeners)).
- Spotify data for two OTR shows: 81% of *Amazing World of Radio* listeners
  35 or younger (same source).
- Broad radio (not OTR): Jacobs Media Techsurvey — average respondent 58.4,
  one in three 65+ ([Jacobs PRTS 2024](https://jacobsmedia.com/public-radio-techsurvey-2024), [Radio Ink](https://radioink.com/?p=102771)).
- No audience data for SiriusXM Radio Classics was found.

Reading: the podcast-delivered OTR audience is younger than the stereotype;
the satellite/broadcast audience is probably older. Design for **both**: large
Dynamic Type that never truncates a title, generous targets, plain labels —
and no "senior mode", which is patronizing and splits the product.

### 7.2 Deaf and hard-of-hearing listeners

- An audio-only product without text excludes them entirely. Transcripts are
  the minimum (WCAG 2.x SC 1.2.1, audio-only prerecorded: provide an
  alternative — UNVERIFIED wording, search budget exhausted).
- Precedents: Apple Podcasts' searchable, tap-to-seek transcripts (§1.1);
  Spotify's full-screen transcript.
- **Human transcripts first**: surviving scripts, where they match the
  broadcast. Generated transcripts next, labeled as generated. Archive Watch's
  own history matters here: CI Whisper captioning was abandoned (Decision 039b)
  and on-device captioning is an economy (Decision 074); a radio app's transcript
  pipeline needs its own decision.
- A transcript also serves search ("the episode where he says 'expense
  account'") and learning (reading along with a 1940s idiom).

### 7.3 Low vision and motor

- VoiceOver/TalkBack: every control labeled — Libby's "hidden or unlabeled
  buttons" are the counter-example. Vintage Radio Lite was praised by AppleVis
  users as fully accessible, so the bar exists in this very category.
- Sleep timer, speed (0.6-3.0x as Libby), and skip ±15/30 s on the player
  surface, not in a menu.
- **Loudness normalization in the pipeline** (measured per file, applied as
  playback gain) rather than Overcast-style live compression: transfers from
  1930s discs and 1950s tape differ by many dB, and a listener with hearing
  loss should not ride the volume between episodes.

---

## §8 — Draft information architecture

**Phone and tablet (tab bar)**

1. **Listen** — Continue Listening; Tonight in *[year]* (the evening on the
   clock, when one is published); This Day in Radio; series shelves by rule
   (genre × decade, network, community signals as Decision 041 — vote floors
   apply); New to the app (`addedAt` window, as Archive Watch §5.1a).
2. **Series** — browse by genre (accent), network, decade, kind (anthology,
   serial...). Series page = runs → seasons → episodes; arcs collapsed under
   serials; auditions first; gaps per §2.4.
3. **Radio** — channels on one clock: real evenings, genre channels (all
   Suspense-era mysteries), each with a guide.
4. **Search** — titles, people, scripts/transcript text, dates ("1944-06-06").
5. **Library** — followed series, queue, downloads, history (union-merged
   history, Decision 078).

Depth ≤ 2 from a tab root (iOS-DESIGN §1.5): tab → series → episode; a run or
season is a segmented scope, not a push.

**Episode Detail**: date · network · sponsor · cast · writer/director;
play; Part n of m (serials); other performances of this script; versions
(AFRS, other transfers); "also aired that night"; the film it adapted (if in
Archive Watch); transcript; rights line.

**CarPlay / Android Auto**: Continue · Radio · Series · Downloads.

**TV**: Listen · Radio (guide) · Series · Search · Library, with Now
Playing as the typographic full screen.

---

## §9 — Proposed binding rules (style of the Archive Watch design docs)

R1 **The broadcast date is the identity.** Every episode row leads with its
air date; episodes sort oldest first in every series, every season, every
platform. *Why*: OTR has no publisher order — upload order and file names are
the collectors' disorder (§1.3); the date is the one fact logs agree on most.

R2 **A series is a list of runs, and a run has a kind.** `seriesKind` is
stored per dated run (anthology, character, serial, strip, comedy-variety,
news, broadcast-day). *Why*: Johnny Dollar and Superman changed shape mid-life
(§2.1); one kind per series would mis-queue half of them.

R3 **A serial plays to the end of its arc and stops.** No autoplay past an
arc into unrelated content; the next arc is offered, not started. *Why*:
bounded lean-back (§5.1); the cliffhanger is the form.

R4 **A missing part is a warning; a missing anthology episode is silence.**
Serial arcs show gaps and the player names a skipped part before skipping;
anthologies hide gaps. *Why*: CLAUDE.md "Only essential information" — a
gap in a story is a fact the listener cannot discover; a gap between
unrelated stories is not a decision anyone needs.

R5 **One broadcast, one card; copies are versions.** AFRS rebroadcasts,
retitlings and duplicate transfers fold into the broadcast's versions picker;
the default is the domestic network copy with its commercials. *Why*: §2.3 and
Decisions 040/158; the category's worst failure is duplicates under two names.

R6 **A script performed more than once says so.** Detail lists other
performances by date and lead. *Why*: §2.3; comparing performances is
learning, not clutter.

R7 **Auditions sort first and carry the AUDITION eyebrow; they are never
numbered.** *Why*: they precede the premiere and were not broadcast (§2.3).

R8 **Never skip the commercials; chapter them.** *Why*: the sponsor and the
pitch are the era's history (§5.4); "skip ads" would teach the opposite.

R9 **A historical evening plays only what aired that night.** A slot whose
recording does not survive is a stated gap, never a substitute episode from
another date. *Why*: a fabricated evening is a fabricated record (§4.3), the
programming form of Decision 151's "a claim a reader can open".

R10 **Channels and evenings run on the one published clock** and draw in
local time, with the original Eastern air time shown as a fact. *Why*:
Decision 144 verbatim; the original time is history, the local time is use.

R11 **Cards are typographic; art is optional and never invented.** No
placeholder graphics; a period photograph only after rights review, fitted at
its own aspect. *Why*: §3.1; Decision 097; density rule.

R12 **Genres take the semantic accents; chrome never does.** Eight accents
maximum, reusing Archive Watch's meanings where they match (§3.3). *Why*:
Decision 013's split, and two apps that read as one family.

R13 **Every list and link comes from data and says why.** Shelves by rule
over archive.org subjects, logs and Wikidata; cross-links by log join ("Lux
adaptation, with ..."). *Why*: CLAUDE.md "No AI-written lists"; Decision 139.

R14 **Lean-back is bounded.** Every continuous mode ends (arc end, sign-off,
sleep timer "end of episode") and offers one lean-in affordance. *Why*:
CLAUDE.md "If a feature makes a person more passive, reconsider it";
tvOS-DESIGN §9.0.

R15 **Silence is content.** No silence trimming; loudness normalized in the
pipeline. *Why*: §1.1 (Smart Speed) and §7.3.

R16 **Text is a peer of sound.** Every surface that plays an episode can show
its transcript or script when one exists, labeled human or generated. *Why*:
§7.2; an audio-only app otherwise excludes deaf listeners.

R17 **The car decides the top level.** The phone's top-level IA must reduce
to four car tabs without inventing new ones. *Why*: §6; designing for the
car last produced the category's bolt-on CarPlay screens (UNVERIFIED claim
about competitors — no review data).

R18 **Speed, sleep timer and skip live on the player, not in Settings.**
*Why*: Audible/Libby precedent; the OTR apps' reviews name their absence
(§1.3).

R19 **A radio adaptation and its film link both ways, and each is judged on
its own rights.** *Why*: §5.2; the film's status says nothing about the
broadcast's.

---

## §10 — Open owner questions

- **Q1** A separate app, or a "Radio" tab inside Archive Watch? (The
  preamble says sister app; the cross-links in §5.2 argue for one shared people
  and works graph either way.)
- **Q2** Default copy when both a domestic network recording and an AFRS
  transcription survive: the domestic copy with commercials (R5), even if the
  AFRS disc sounds better?
- **Q3** Broadcast seasons ("1949-50") or calendar years as the grouping?
- **Q4** How is the "Tonight in [year]" date chosen: same date N years ago, or
  the best-surviving evening for this weekday? And is a partly-surviving
  evening offered with gaps, or only above a coverage floor?
- **Q5** Does the historical evening include the news and the war bulletins
  exactly as aired?
- **Q6** "On its schedule" mode for serials and soaps (one episode a day):
  wanted?
- **Q7** The genre-accent reuse in §3.3 assigns new meanings to three Archive
  Watch hues (sci-fi violet, western gold, comedy pink). Acceptable, or new hues?
- **Q8** Horror: its own color (a ninth) or folded into Mystery?
- **Q9** WWII and Cold War propaganda broadcasts: apply Decision 149's
  "never recommended, always findable" rule, and with what evidence boundary
  for radio?
- **Q10** Smart speakers and voice: a core playback route, or a "side door"
  that is documented on the website only?
- **Q11** Generated transcripts: acceptable where no script survives, and on
  which pipeline (Archive Watch abandoned CI Whisper, Decision 039b)?
- **Q12** Listen Together: in v1, or after the catalog is proven?

---

## To measure (probes for a session with network access)

**M1 — OTR app reviews, real corpus.** Pull App Store reviews for the apps in
§1.2 and count complaint classes:
```
for id in 455577974 324517232 1438072504 1493221239 889955088 389211220 567195102; do
  curl -s "https://itunes.apple.com/us/rss/customerreviews/page=1/id=$id/sortby=mostrecent/json" > rev_$id.json
done
python3 -c "import json,glob,re,collections as C
k={'ads':r'\bads?\b|advert','crash':r'crash|freez','dup':r'duplicate|same episode|repeat','label':r'wrong|mislabel|title','resume':r'resume|where I left|position','sleep':r'sleep timer','carplay':r'carplay|android auto'}
c=C.Counter()
for f in glob.glob('rev_*.json'):
  for e in json.load(open(f)).get('feed',{}).get('entry',[])[1:]:
    t=(e['title']['label']+' '+e['content']['label']).lower()
    for n,p in k.items():
      if re.search(p,t): c[n]+=1
print(c)"
```
Do the same for Play listings (OTR Player, Radio Spirits) via a manual read.

**M2 — CarPlay/Android Auto limits from the primary docs.** Read Apple's
CarPlay App Programming Guide (audio category: tab count, template depth,
list item limits) and developer.android.com/training/cars/media; replace the
third-party numbers in §6.

**M3 — Evening coverage.** For 20 sample dates (1938-1955), take the NBC and
CBS evening slots from JJ's Newspaper Radio Logs and count how many slots have
a surviving recording dated that night in archive.org's `oldtimeradio`
collection:
```
curl -s "https://archive.org/advancedsearch.php?q=collection%3Aoldtimeradio&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=date&rows=10000&page=1&output=json" > otr_items.json
```
then per item list files (`/metadata/<id>`) and parse dates from filenames
(the data-model track owns the parser). The result decides Q4's coverage floor.

**M4 — "This day in radio" depth.** From the same parse, count episodes with
day-precision dates per calendar day; report min/median. Below Archive
Watch's shelf floor on many days → the shelf needs a wider window (week).

**M5 — Lux ↔ Archive Watch overlap.** Join a Lux Radio Theatre log (Haendiges
or radioGOLDINdex; title, date, stars) to `catalog-index.json` on normalized
title + film year within 0-3 years before the broadcast + one shared cast
name from TMDb credits. Report the count and the list; this replaces the
UNVERIFIED rows in §5.2.

**M6 — Loudness spread.** On 200 random OTR MP3s:
`ffmpeg -i f.mp3 -af ebur128=peak=true -f null - 2>&1 | grep -E "I:|LRA:"` —
report the integrated-loudness range; it sizes R15's normalization.

**M7 — Period art candidates.** Wikimedia Commons categories for radio
publicity photos (e.g. `Category:CBS Radio publicity photographs`, UNVERIFIED
name) via the API:
`curl -s "https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Old-time_radio&cmlimit=500&format=json"`
and count files with a PD license template; hand rights to the rights track.

**M8 — LibriVox apps and BBC Sounds' archive streams.** Not researched (search
budget). Teardown the LibriVox app's book/section ordering and current BBC
Sounds handling of Radio 4 Extra.

**M9 — WCAG wording.** Confirm SC 1.2.1 (audio-only, prerecorded) text at
w3.org/WAI/WCAG22/Understanding/audio-only-and-video-only-prerecorded.

**M10 — Script libraries.** Identify surviving-script sources (Generic Radio
Workshop, Library of Congress / Library of American Broadcasting at UMD —
whose Ma Perkins 1938 script holding was surfaced,
[UMD](https://archives.lib.umd.edu/repositories/2/top_containers/43016?&page=6))
and their rights; this gates R16's human transcripts.

---

## Sources

Precedent apps and services
- https://podcasters.apple.com/864-best-practices-for-episode-numbering
- https://itunespartner.apple.com/podcasts/whats-new/100002561
- https://www.thurrott.com/apple/296763/apple-podcasts-will-provide-automatic-transcripts-on-ios-17-4
- https://pxlnv.com/linklog/apple-podcasts-transcripts/
- https://ppc.land/apple-podcasts-gets-more-accessible-with-automatic-transcripts
- https://www.macworld.com/article/227600/overcast-25-review-patron-backed-podcast-app-gets-more-efficient-and-adds-exclusive-features.html
- https://laughingsquid.com/?p=409004
- https://support.pocketcasts.com/knowledge-base/episode-filters/
- https://support.pocketcasts.com/knowledge-base/playing-episodes-and-managing-your-queue/
- https://support.pocketcasts.com/knowledge-base/duplicate-episodes-2
- https://forums.pocketcasts.com/forums/topic/listen-to-episodes-in-sequential-order
- https://sixcolors.com/post/2016/08/castro-2-inbox-triage-for-podcast-episodes/
- https://www.macstories.net/reviews/castro-3-review-the-castro-youve-always-wanted/
- https://screensdesign.com/showcase/podcast-player-app-castro
- https://www.androidauthority.com/audible-listening-settings-3667303/
- https://www.applevis.com/comment/44471
- https://apps.apple.com/app/libby-by-overdrive-labs/id1076402606
- https://aurorapl.ca/blogs/post/get-to-know-libby/
- https://www.siasat.com/spotify-to-roll-out-auto-generated-transcripts-to-millions-of-podcasts-2708393/
- https://routenote.com/blog/spotify-updates-desktop-apps/
- https://community.spotify.com:443/t5/Implemented-Ideas/All-Platforms-Bookmark-Position-in-an-Audiobook-or-Podcast/idc-p/1203821
- https://en.wikipedia.org/wiki/BBC_Radio_4_Extra
- https://www.chortle.co.uk/news/2022/05/26/50864/bbc_to_axe_radio_4_extra
- https://radiotoday.co.uk/2025/07/bbc-sounds-to-close-for-international-users-from-21-july-2025/
- https://www.hiresaudio.online/?p=10285
- https://www.broadcastnow.co.uk/bbc/bbc-sounds-launches-christmas-box-sets/5135090.article

OTR apps and streams
- https://apps.apple.com/us/app/-/id455577974
- https://apps.apple.com/us/app/-/id324517232
- https://appgoblin.info/apps/455577974
- https://www.engadget.com/2012-01-26-daily-iphone-app-vintage-radio.html
- https://applevis.com/comment/1737
- https://apps.apple.com/us/app/old-time-radio-shows/id1438072504
- https://apps.apple.com/app/id1493221239
- https://grand-screen.com/apps/old-time-radio-player/
- https://chrome-stats.com/d/id1493221239
- https://apps.apple.com/app/id889955088
- https://applevis.com/podcasts/enjoy-taste-old-time-radio-otr-streamer-ios
- https://apps.apple.com/app/id567195102
- https://apps.apple.com/us/app/id389211220
- https://appgoblin.info/apps/389211220
- https://www.consumercellular.com/blog/smartphone-apps-of-the-month-november-edition/
- https://en.wikipedia.org/wiki/Radio_Classics
- https://www.siriusxm.com/radioclassics/weeklyschedule
- https://en.wikipedia.org/wiki/When_Radio_Was
- https://streema.com/radios/Yesterday_USA_Red
- https://streema.com/radios/Yesterday_USA_Radio
- https://workbench.cadenhead.org/clippings/yusa.shtml
- https://cool.culturalheritage.org/byform/mailing-lists/arsclist/2009/01/msg00009.html
- https://play.cdnstream1.com/s/WOTR/classic-radio-rewind-old-2937a9/episode-25-august-20th-2-ea98db
- https://play.cdnstream1.com/s/WOTR/classic-radio-rewind/d-day-remembrance-specia-9ce7d3
- https://mytuner-radio.com/radio/old-time-radio-usa-469299/
- https://www.informationnow.org.uk/organisation/radioechoes-com/
- https://www.wrvo.org/tuned-to-yesterday
- https://www.wrvo.org/tuned-to-yesterday/2017-05-20/tty-dialer-podcast-30
- https://metacast.app/podcast/the-radioscope/nFFuyhf3

Collector evidence on bad files
- https://radio.macinmind.com/journal-2019.php
- https://archive.org/details/OurMissBrooks
- https://jackbenny.org/phpBB3/viewtopic.php?p=250
- https://www.otrr.org/FILES/Times_Archive_pdf/2012_05-06MayJun.pdf

Series and episodic model
- https://en.wikipedia.org/wiki/Lux_Radio_Theatre
- https://criterionchannel.com/videos/the-lady-eve-on-lux-radio-theatre
- https://criterionchannel.com/videos/the-39-steps-lux-radio-theatre-adaptation
- https://en.wikipedia.org/wiki/X_Minus_One
- https://sf-encyclopedia.com/entry/x_minus_one
- https://en.wikipedia.org/wiki/Yours_Truly,_Johnny_Dollar
- https://www.radioarchives.com/Yours_Truly_Johnny_Dollar_Volume_2_p/ra124.htm
- https://en.wikipedia.org/wiki/The_Adventures_of_Superman_(radio_series)
- https://en.wikipedia.org/wiki/Bud_Collyer
- https://en.wikipedia.org/wiki/Ma_Perkins
- https://randsesotericotr.podbean.com/e/ma-perkins-pgm-423/
- https://archives.lib.umd.edu/repositories/2/top_containers/43016?&page=6
- https://en.wikipedia.org/wiki/Sorry,_Wrong_Number
- https://starsonsuspense.libsyn.com/bonus-eighty-years-of-wrong-numbers
- https://www.museum.tv/radio-encyclopedia/armed-forces-radio-service
- https://otrcat.com/p/hollywood-radio-theater
- https://jimmystewartontheair.com/broadway-playhouse
- https://vintageradioshows.com/shows/radio-novel
- https://www.otrr.org/FILES/Articles/Danny_Goodwin_Articles/Klean%20Soap.pdf
- https://adpprod1.library.ucsb.edu/index.php/matrix/refer/800040201
- https://downthesemeanstreetspodcast.libsyn.com/bonus-five-favorites-auditions
- https://otrsite.com/
- https://otrsite.com/logs/loga1031.htm
- https://www.quietplease.org/forum/general/-logs-compared-and-the-results-352.html
- https://www.greatdetectives.net/detectives/my-favorite-old-radio-research-resources/

Schedules, listings, broadcast day
- https://en.wikipedia.org/wiki/WJSV_broadcast_day
- https://www.archives.gov/press/press-releases/2004/nr04-39
- https://www.blackstonelibrary.com/one-day-in-1939
- https://www.jjonz.us/RadioLogs/
- https://www.worldradiohistory.com/Radio_Guide_Master_Page.htm
- https://www.worldradiohistory.com/OUTSIDE-SITES/Jim-Ramsburg/Gold-Time-1946-1947.htm
- https://mcfarlandbooks.com/?p=17759
- https://www.bearmanormedia.com/products/the-los-angeles-old-time-radio-schedule-book-volume-2-1938-1945-by-keith-d-lee
- https://lantern.mediahist.org/catalog/varietyradiod19401941vari_0035
- https://lantern.mediahist.org/catalog/radioannual194200radi_0870
- https://lantern.mediahist.org/catalog/radiodailyoctdec49unse_0005
- https://mediahist.org/about/howto.php
- https://www.infodocket.com/2013/08/12/reference-media-history-old-film-journals-and-mags-now-searchable-for-everyone-via-lantern-database-over-800000-pages-available/

Platforms
- https://skills.sh/ios-agent/iosagent.dev/carplay
- https://developer.apple.com/forums/thread/813008
- https://developer.android.com/training/cars/media/create-media-browser/content-styles
- https://android-developers.googleblog.com/2018/12/improve-media-and-messaging-app.html
- https://developer.apple.com/videos/play/wwdc2019/716
- https://developer.apple.com/forums/thread/849255
- https://marco.org/2017/09/24/what-watch-podcast-apps-need
- https://developer.amazon.com/docs/custom-skills/audioplayer-interface-reference.html
- https://developers.google.com/assistant/ca-sunset

Audience
- https://www.greatdetectives.net/detectives/whos-listening-to-our-podcast/
- https://www.greatdetectives.net/detectives/listeners
- https://jacobsmedia.com/public-radio-techsurvey-2024
- https://radioink.com/?p=102771

Repository (read directly)
- /home/user/Archive-Watch/CLAUDE.md, docs/iOS-DESIGN.md (§1, §5), docs/tvOS-DESIGN.md (§9),
  docs/decisions/DECISIONS-031-060.md (041), docs/decisions/DECISIONS-127-145.md (139, 144),
  DECISIONS.md (097, 149, 151, 158), catalog-index.json (schema 15, 35,290 rows; title checks in §5.2)
