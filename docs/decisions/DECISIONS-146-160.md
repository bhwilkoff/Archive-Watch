# Archive Watch — Decisions 146–160 (archived verbatim)

Moved from DECISIONS.md on 2026-10-27, unedited, when that file passed its
~50 KB ceiling. The index in DECISIONS.md still lists every title.

## 146 — The Creation Studio clips any title the apps show; fair use is its rule, not the broadcast tier
*Date: 2026-09-28*

Every title visible in the apps' catalog may be clipped, cut and exported in
the Creation Studio (`Catalog.Item.isClippable`: playable, and a rights status
of public domain, Creative Commons or absent). It does NOT take the Watch
Together Studio's broadcast tier (`isHeroRightsSafe`), and Publish is not
narrowed either.

**Why**: the owner, asked whether Publish should require the stricter tier
after the Mac loop found The Pink Panther (1963, no year in the catalog)
clippable: *"Since fair use is something we can use for the creation studio
that doesn't work for the Watch Together Studio, we can have far more loose
rules for what can be included. I think we can leave in all titles that are
included in the database for viewing within the apps."* A clip, a montage or
a supercut is transformative commentary; a live broadcast of a whole film is
not, which is why the two Studios answer differently.

**How to apply**: do not import the broadcast tier into the Creation Studio's
browser, Supercut index or Publish. The catalog's own gates (the rights audit,
takedowns, the mature filter) are the Creation Studio's gates. A title the
apps hide is not clippable; a title the apps show is.




## 147 — A film the system can caption plays through the loopback proxy, paced to twice its bitrate
*Date: 2026-09-28*

On iOS/iPadOS and macOS, a film with no subtitles of its own — the case that
played the plain archive.org URL so the OS 27 system could generate captions —
now plays `LocalMediaServer.proxyURL(for:durationSeconds:)` instead, and the
proxy paces each response (`ProxyPace`): the first 60 s of film at full speed,
then twice the film's bitrate (size ÷ the catalog's running time; a 12 Mbps
floor when the running time is unknown). Pacing happens BETWEEN origin chunk
requests, never inside one. The plain URL is the fallback when the listener
cannot start. tvOS is unchanged: it stays on segmented HLS (Decision 106). The
macOS app gains `com.apple.security.network.server`, without which its
loopback listener was refused by the sandbox ("Operation not permitted") —
the Mac proxy had never been able to run.

**Why**: the owner — *"I want to make sure all features are as responsive and
available as possible, so however we can optimize playback is to our benefit"*
— then *"keep direct, research a hybrid"*, and *"you need to check if the
generated captions work with hls on Mac, iPhone and Apple TV."* Measured
(Brute Force, no subtitle file, 10 minutes in; the first probes used a silent
film and a film WITH a subtitle file, both of which prove nothing about
generated captions and were discarded):

    generated captions      iPhone 15 Pro (iOS 27)   Apple TV (tvOS 27.2)
      direct                yes (seen + probe)       yes (probe)
      loopback proxy        yes (seen + probe)       yes (probe)
      segmented HLS         no track offered         no track offered

    bytes                   Mac (nettop)                   iPhone 12 (access log)
      direct                435 MB in 15 s, 1.08 GB/2 min  66 MB/2 min, startup 0.97 s
      proxy, unpaced        ~1.08 GB/2 min                 55 MB/2 min
      proxy, paced          126 MB/105 s                   36–37 MB/2 min x3, 0 stalls,
                                                           startup 0.59–0.77 s

Then, for shipping: the PACED proxy kept the captions on the iPhone 15 Pro
(probe: captionText=yes; 40 MB/2 min, 0 stalls, startup 0.80 s), and on a
simulated 1.2 Mbps link (`AW_LINK_MBPS`, coarse — per 8 MB chunk) paced and
unpaced were identical on the iPhone 12: 0 stalls, startup 0.73–0.76 s.

So segmented HLS bounds the bandwidth and loses the captions; the proxy keeps
the captions (AVFoundation still sees a plain MP4) and the pacing — which only
the proxy can do — bounds the bandwidth. The Mac is where it mattered most: its
player read a film at line rate. The Mac itself generated no captions on ANY
path during the research (its speech assets read "supported", not installed),
so its captions claim rests on the iPhone and Apple TV.

**How to apply**: keep the proxy on the paths the system captions; pace in
`StreamPump` between requests (pacing inside a response let the origin read
idle past its 12 s timeout — every paced chunk ended in -1001 until moved).
AirPlay is unaffected: the receiver is handed the origin URL
(`AirPlayRouting`), never 127.0.0.1. DEBUG doors for the next measurement:
`AW_PLAY_PATH=direct|proxy|hls` (forces the source, probes the system caption
track), `AW_PACE=off|AW_PACE_X`, `AW_LINK_MBPS` (slow-link simulation),
`AW_AUTOPLAY_AT`, `AW_MUTE=quiet` (0.1% volume — `isMuted` may stop the audio
path the captions listen to).

**Consequences**: Decision 082's intermittent proxy failures were tvOS's
`mediaserverd` hop; on the iPhone the proxy started 3/3 runs, faster than
direct. Open, separately: the Mac's OWN caption engine, which takes over when
the system does not caption, reads ~3 minutes of film ahead at line rate
(~580 MB on Brute Force) — the next bandwidth item, not addressed here.


## 148 — Older Apple TVs are served by the tvOS 26 floor, not a second app; the floor is held below 27
*Date: 2026-09-28*

The tvOS app keeps `TVOS_DEPLOYMENT_TARGET = 26.x`, which already installs on
every Apple TV that can run an App Store app: the Apple TV HD (2015, A8, 2 GB)
and the Apple TV 4K 1st gen (2017, A10X), whose last system is tvOS 26, plus
the 4K 2nd and 3rd gen on 27. `tools/test_tvos_floor.py` refuses a target of 27
or above, and `appstore-build.yml` runs it before archiving. tvOS 27 features go
behind `#available`. No separate "classic" app and no lower floor.

**Why**: the owner asked *"if it is possible for making a version of the app
functional on older apple tv hardware ... not full parity ... but rather a fully
functional experience in the same way that we have been able to manage on old
Roku and Android hardware."* Measured: tvOS 27 dropped the HD and 4K 1st gen;
the Apple TV 3rd gen and earlier have no App Store at all. So the old boxes that
CAN run apps are on tvOS 26, which is our floor already. Roku and Android needed
legacy tiers because old OS versions there cannot update; any Apple TV on 17/18
can update to 26 for free, and tvOS cannot be downgraded, so a lower floor would
be untestable on real hardware and would serve nobody. Test builds at 18.0 and
17.0 fail in 4 and 7 files (Liquid Glass, SpeechAnalyzer, the tab API, `Mutex`).
The risk that remained was invisible: moving the floor to 27 in some future
cleanup would cut both boxes off with no error anywhere.

**How to apply**: never raise the tvOS floor to 27 while the HD and 4K 1st gen
are supported; that is an owner decision, taken with this entry, not a build
setting. Put new tvOS 27 APIs behind `#available(tvOS 27, *)` with a tvOS 26
path. What the old boxes still lack is VERIFICATION: nobody has run the app on
an A8 (no HEVC decoder, 2 GB, the ~148 MB catalog DB to open), and this project
tests on real hardware only.


## 149 — Propaganda is never recommended and always findable; "true propaganda" is the Nazi state's, on evidence a reader can open
*Date: 2026-09-28*

A film flagged `noRecommend` is never CHOSEN for the viewer — no Home shelf,
hero, community or Top Rated row, Hidden Gems, More Like This, channel, Top
Shelf, Tonight, Surprise pick, Party/Cartoon/screensaver lineup, user channel
or social post — and stays reachable by Search, Detail, Browse grids and
archive.org's own Collections. `remediate_catalog.flag_propaganda` sets it every
build from `shared/editorial/propaganda.json`: a Vorbehaltsfilm (Germany's own
restricted list, title + year), a German-language 1933-45 film the data tags
propaganda (genre, keyword or archive.org subject), a Nazi-party producer, or a
sourced `add` entry; `not` names exceptions. It is an items column
(`noRecommend`), a catalog-index column (18, schema 15) and `Catalog.Item`
/`CatalogItem` field; every client picker gates on it.

**Why**: the owner, 2026-09-28 — *"All true propaganda should be hidden from
recommendations, but avaialble via search."* The word needed a boundary before
it could be a rule. Measured on the live catalog: a plain "propaganda" tag sits
on 200 visible items — Battleship Potemkin, Why We Fight, the Disney and Warner
war cartoons, Reefer Madness, Night Train to Munich — and hiding those from
every shelf would gut the archive's history of cinema on a keyword. The case
that raised the question was *Juden ohne Maske* (1937), an antisemitic film of
the Nazi party's own propaganda office, which no tag caught at all. So "true
propaganda" is the regime's: Germany restricts its worst films itself (the
Vorbehaltsfilme), the party's producer credit is in the data, and the rest is
the catalog's own tags inside the right country and years. Measured: 60 visible
items (27 Vorbehaltsfilme, 22 by data, 9 by producer, 2 by source). One
false positive was found and named — *Death Mills* (1945), the US War
Department's film of the liberated camps, caught only through its
German-language version.

**How to apply**: never widen the rule on a keyword; add evidence to
`propaganda.json` with a source a reader can open, and it takes effect at the
next publish (the flag is recomputed, so removing evidence clears it). A new
surface that picks films for the viewer must skip `noRecommend` (Apple
`isRecommendable`/`noRecAnd`, Android `noRecAnd`/`browse(recommendOnly)`, web
`Data.rec`, Roku `noRec()`); a surface the viewer drives (search, a browse
filter, a collection) must not. The title-marker rule above it
(`exclude_hate_propaganda`) is different in kind — modern Holocaust-denial and
CSAM uploads that are not films, several with fabricated years — and stays an
exclusion. `tools/test_propaganda_no_recommend.py` holds the rule and every
pipeline gate, each with an unflagged control.


## 150 — A cleared match leaves nothing it filled unless something independent vouches for it
*Date: 2026-09-28*

When an item's external match has been cleared and no new identity replaced
it (`remediate_catalog.is_cleared_match`: a `cleared*` verdict,
`modernPosterCleared` or `matchResidueCleared`, and no imdbID/tmdbID), every
build runs `scrub_cleared_match`: the year, director and genres that match
filled are removed unless something independent vouches for them, the decade
and silent flag follow the year, and a `silent-film` whose year no longer
makes it one is re-typed by `content_type.classify`. What changed is recorded
on the item (`scrubbedFields`, `yearWas`, `contentTypeWas`).

**Why**: the owner — *"All inaccurate information should be scrubbed from the
database. Unless it is somehow verified, keeping bad info on "junk uploads"
doesn't seem helpful to anyone."* Enrichment fills identity fields only where
the Archive item had none (`omdb_lib.apply_identity`), so a value still
standing after its match was cleared came from somebody else's film unless
something says otherwise. `_clear_wrong_artwork` already dropped the match's
art, ids, ratings and credits, and deliberately kept year, director and
genres, because they can also arrive from the Archive or Wikidata. That left
a two-minute cable-outage clip dated 1916 on the silent-era shelves, a *Bleach*
recap and a game-trailer dated 1919-21, and *Robin Hood* episodes credited to
Mikhail Romm.

**What counts as vouching** (each measured against a real over-scrub before
it was added): the Archive item's OWN metadata — its `date`/`year`, a year its
title, id or description states, its `director`/`creator` (by surname: the
Archive wrote "Vincent Minnelli"), its subjects for genres, its animation
typing for "Animation"; a Wikidata identity anchored by Internet Archive id;
an independent `yearSource`; and **another copy of the same film whose match
is live** (`sibling_index`), which is checked BEFORE the Archive's own date
because uploaders' dates are wrong too (*Father's Little Dividend*'s upload
says 1941; the film and its matched sibling say 1951). The Archive's metadata
is cached in `shared/editorial/archive_own_meta.json` by
`tools/fetch_archive_own_meta.py` — the build has no network — and an item
not in the cache is left alone: unknown is not wrong.

**Measured on the live catalog** (593 of 594 visible cleared items judged):
60 visible items change — 36 years (34 to none, 2 to the Archive's own), 28
directors, 17 genre sets; 16 leave the silent era and 35 change decade.
**It removes true facts too**, as the rule asks: *The Chinese Room* (1968),
*The Barber of Seville* (1944) and *Send for Paul Temple*'s director are right
and unvouched by anything in the Archive's record or a live sibling.

**How to apply**: never make a scrub guess — add a WITNESS. A true fact lost
here comes back by evidence the build can read (a sibling with a live match,
an entry in `year_corrections.json` / `title_corrections.json`, a Wikidata
link), not by weakening the rule. Run `tools/fetch_archive_own_meta.py` after
a pass that clears new matches; 1,320 hidden cleared items are still
unfetched and therefore untouched. `tools/test_scrub_cleared_match.py` holds
the cases with two controls (a no-op scrub; a scrub without siblings, which
would null D.O.A.'s 1949 and set Father's Little Dividend to 1941), and a
second full `remediate` pass must scrub nothing.


## 151 — A title leaves the catalog on a copyright claim a reader can open; not knowing is not a claim
*Date: 2026-09-28*

`tools/corroborate_copyright.py` (rights-audit, after the licence step) looks
for evidence that a title the audit KEEPS is still under US copyright, and
records it as `copyrightClaimEvidence` (the record's URL, the registration,
the claimant); `audit_rights` hides such a title as `copyright_claim_evidence`
until its year passes the age line. Two sources count: a Copyright Office
**renewal** (class RE) of a **motion picture** whose title is this title and
whose original registration is within a year of this title's year; and a
Wikidata "copyrighted" statement with a reference that applies to the US,
where the same item carries no US public-domain status and no licence. A title
with no claim found is left alone.

**Why**: the owner — *"If we have verifiable copyright claims on movies or TV
shows, we should work to remove those items from the database. If we truly
don't know about the copyright status, then they can stay because of that
ambiguity."* The audit's `presumed_pd` and renewal-zone buckets keep 1930-77
films on the absence of evidence either way, which is right for the unknown
and wrong for the films whose renewal is a public record. Measured
2026-09-28 over 16,390 kept titles: **943 Copyright Office renewals and 4
Wikidata claims** (947 items, 765 distinct films; 742 features, 160 cartoons —
Columbia's Magoos, Famous Studios' Noveltoons — 41 shorts, 4 TV specials),
13,905 with no claim, 7 unreachable. They include The Killing, The Night of the
Hunter, The Manchurian Candidate, Invasion of the Body Snatchers, Yojimbo and
Jason and the Argonauts, several of which had been on the marquee.

**What does NOT count**, each seen that day: a post-1978 PA registration (it
registers NEW material — Plan 9 from Outer Space's trailer and a 2007
colorized version are registered, and Plan 9 is public domain); a renewal of
a SONG from the film (Charade's); a renewal of another work with the same
title in another year; a Wikidata "copyrighted" on a pre-1930 film (stale:
Rival Romeos, 1928). Before shipping, 0 of 20 public-domain canon films
(Night of the Living Dead, Charade, Carnival of Souls, McLintock!...) matched,
and 3 of 3 known renewals did. Renewals of works before 1950 were filed before
1978 and are not in the online records, so the 1930s and 1940s are checked by
Wikidata alone.

**How to apply**: a wrong match is cleared by a person, in
`shared/editorial/copyright_evidence_overrides.json` ({archiveID: reason}),
never by loosening the match. The hide lifts on its own when a title's year
passes the age line (Decision 137). Checked titles are re-checked after 90
days; a first run is the long one (~70 minutes locally). Television episodes
in series spines are not catalog items and are judged by `audit_tv_rights`,
not here. `tools/test_copyright_evidence.py` holds the match rules with the
PA, song and wrong-year controls.


## 152 — Sourced evidence of a free licence outranks the popularity check
*Date: 2026-09-29*

A title whose archive.org licence is free-culture (CC0, CC BY, CC BY-SA) and
which carries `rightsCorroborated` (Wikidata P275/P6216 on the item whose
Internet Archive ID is this archiveID, or a `licence_evidence.json` entry with
a source a reader can open) is kept as `safe_archive_license`, however many
IMDb votes it has. `corroborate_licences.py` now also looks for evidence on
popular free-culture titles, which it skipped before. NC/ND licences are not
freed, and `uploader_cannot_dedicate` still runs first.

**Why**: the owner, 2026-09-29 — *"Yes on letting sourced Creative Commons
evidence beat the popularity check."* Decision 114's commercial-votes gate is
right about uploads (a popular film wearing CC0 is usually a pirate copy:
Lady Vengeance, Nayakan, Virus), and Decision 140 asked for evidence on the
unpopular ones — but the popular ones were never ASKED, so a creator's own
release could not come back whatever proved it. *Sita Sings the Blues* (Nina
Paley, CC BY-SA 2009, CC0 2013, 5,022 votes) was hidden as copyrighted.
Measured: of 25 popular free-culture titles, Sita alone has evidence — her
site, and Wikidata's Q739285 naming two of its uploads — and the pirate
uploads have none and stay hidden.

**How to apply**: never loosen the vote gate itself; free a popular title by
adding evidence. `test_audit_rights.py` holds the case with two controls (the
same film without evidence; an NC licence with evidence).


## 153 — A work made with Archive Watch claims Creative Commons or fair use, never public domain
*Date: 2026-09-29*

Every clip, GIF, montage and supercut exported from Archive Watch (Clip Studio on
Android and iOS, the Mac Creation Studio) burns "archivewatch.org · Creative
Commons" when its source is a Creative Commons work and "archivewatch.org · Fair
use" otherwise; a Mac project of several sources says fair use. The file's
description reads "Source: <archive.org link> · Clipped with Archive Watch",
with no "Public-domain source". No surface says a clip carries a public-domain
credit.

**Why**: the owner, 2026-09-29 — *"I think that we can probably only claim
creative commons or fair use for created works with Archive Watch. Public domain
is not something we will be able to do because many of the videos people will
clip will not be of public domain videos."* Decision 146 lets the Creation Studio
clip any title the apps show on fair use, including the 1964-77 titles the rights
audit keeps on uncertainty, while the credit line said "Public Domain" for every
title not marked Creative Commons — a claim the app could not stand behind.

**How to apply**: never print "Public Domain" on or about a created work, even
for a title that is public domain by age; the credit describes what the clip IS
(a CC derivative or a fair-use excerpt), not the source's status. The rights
language for BROADCASTS (Watch Together's provenance line) is unaffected: a
broadcast is limited to the guaranteed tier and says what that tier proves.


## 154 — The Android floor is a floor, not a ceiling: modern devices get modern features, gated by OS version
*Date: 2026-09-29*

Android keeps its install floor at Android 6 (Decision 141), and a device above
it gets every capability its OS offers: a feature that needs a newer Android
ships behind a `Build.VERSION.SDK_INT` check (PiP auto-enter from 12, typed
foreground services from 11), never withheld from everyone because old devices
lack it. What the floor may hold back is a LIBRARY that raises its own minSdk;
such a library is pinned with the reason written beside it, and anything it
was built against is pinned strictly with it.

**Why**: the owner, during the dependency pass — *"Remember, you are trying to
keep the floor low for Android, but we aren't trying to hamstring modern
devices that are capable of doing many more things. If you have to make it so
that certain features can only be utilized on more modern devices, that is
okay."* The same pass showed what a pin costs when it is half-done: material3
was held at 1.5.0-alpha19 for the floor while a newer Coil dragged Compose
foundation to 1.12.0 stable, and the Google TV crashed at runtime
(`AbstractMethodError` in `CustomStyle.applyStyle`) on a build that compiled
cleanly on both flavors.

**How to apply**: gate a platform capability, never a whole app, on the OS
version. When a library that everything draws through (the UI toolkit) needs a
higher floor and its newer version brings something users would notice, that
is the moment to ask the owner about splitting the Play build (a modern build
above a legacy one, as Roku and Fire TV already have) — not before, and never
by raising the floor quietly. Keep the strict `compose-foundation` constraint in
`app/build.gradle.kts` for as long as material3 is held: it turns the skew into
a failed build (its control: Coil 3.6.3 refuses to resolve).


## 155 — The iPhone/iPad floor is iOS 18: the XS and XR come back, iOS 26 features are gated, and iOS 12 is the website's job
*Date: 2026-09-29*

The iOS app's deployment target drops from 26.0 to **18.0** (app, widgets, UI
tests). The only iOS 26-only code on the path — live captions' SpeechTranscriber
and the Core Image composition in clip export and the Clip Studio preview — sits
behind `#available(iOS 26, *)` with the older AVFoundation path for 18-25;
captions stay an iOS 26 feature (Decision 154). `tools/test_ios_floor.py`, run in
appstore-build, refuses an iOS target above 18.x.

**Why**: the owner — *"The current native app requires ios 26, but we are
investigating if we can make it work on older hardware"* — then, offered the
measurements, chose "Native floor to iOS 18". Measured
(docs/research/IOS-FLOOR.md): the installed SDK's minimum is iOS 15, so nothing
native reaches iOS 12 (the iPhone 6 Plus that prompted this); below 17 the data
layer fails (SwiftData, Observation — 428 errors); 18 needed two files. iOS 17
and 18 run on the same phones, and iOS 26 is what dropped the iPhone XS, XS Max
and XR, so 18 is the floor that buys hardware.

**How to apply**: a new API above iOS 18 goes behind `#available` with a
working 18 path, or is a feature that is simply absent below it — never a
reason to raise the floor. A stored property cannot carry an availability gate:
store it untyped and expose a gated accessor (LiveCaptions' `continuationBox`).

**Consequences**: the 18-25 paths are compiled (iOS, tvOS and macOS Release, zero
warnings) but UNVERIFIED on the glass — the bench has no iOS 18 device (iPhone 12
on 26.6.1, iPhone 15 Pro and iPad Pro on 27.2), the same gap Decision 148 names
for the Apple TV HD. An iPhone on 12 is served by the website, which Safari 12
cannot run today (IOS-FLOOR.md lists why).



## 156 — A foreign film URAA restored is never recommended and always findable
*Date: 2026-09-29*

A film published after the public-domain-by-age line (Decision 137) whose
production country is not the United States — or, with no country known, whose
original language is not English — carries `noRecommend` with the reason
"URAA — made in DE" (or "original language spa"), set by remediate's
`uraa_restored` every build. It leaves every surface that picks films for the
viewer and stays reachable by search, browse and collections: the Decision 149
mechanism, with a second reason. US co-productions, government works and titles
with corroborated free licences are exempt. Measured on the live catalog: 3,306
served titles (Argentina 632, Germany 499, Britain 443, Italy 119, Japan 106;
M, Viridiana, Les Diaboliques, The First of the Few).

**Why**: the Uruguay Round Agreements Act restored US copyright, from 1996, to
foreign works still protected at home that had fallen into the US public domain
only through a missed formality (notice, renewal). So the renewal rules the
audit applies to 1931-77 films say nothing about a foreign film: Fritz Lang's M
(1931) is under US copyright until 2027. The owner, shown the measurement and
three options (hide, never recommend, keep), chose "Recommend never, keep
findable".

**How to apply**: origin is evidence, not a guess — TMDb production countries
by the stored tmdbID, cached in `shared/editorial/origin_cache.json` by
`tools/fetch_origin_countries.py` (weekly in resource-posters, committed so the
networkless build can read it), then the item's language. A film URAA did NOT
restore (already public domain at home on 1 January 1996, or first published in
the US) comes back by evidence — a `licence_evidence.json`-style entry — never
by loosening the rule. `tools/test_uraa_no_recommend.py` holds the cases with
US, government, licence and age controls; the propaganda test now asserts its
own reason, since both reasons share the flag.


## 157 — Pre-1950 renewals are read from the printed Catalog of Copyright Entries
*Date: 2026-09-29*

`tools/fetch_cce_renewals.py` parses the motion-picture renewal registrations
printed in the Catalog of Copyright Entries, 1950-1977 (28 annual volumes,
scanned with OCR on archive.org), into `shared/editorial/cce_renewals.json`:
11,579 renewals with title, original year and registration, renewal number and
claimant. `corroborate_copyright.py` matches a kept pre-1950 title against it
exactly as it matches the Copyright Office's online records (normalized title,
original year within one), and records the volume's archive.org URL as the
evidence; Decision 151's `copyright_claim_evidence` hide then applies.

**Why**: Decision 151 said it in its own words — "Renewals of works before 1950
were filed before 1978 and are not in the online records, so the 1930s and
1940s are checked by Wikidata alone." That left Frankenstein (1931, renewed by
Universal in 1959 as R243591), The Invisible Man and Bride of Frankenstein
served as presumed public domain. The printed catalog is the record the online
search replaced, and a reader can open the page. Measured: 983 served 1930-49
titles have a printed renewal (486 features, 445 cartoons — Terrytoons renewed
by CBS Films, Columbia's by Columbia); 0 of 25 public-domain canon films
(His Girl Friday, Detour, It's a Wonderful Life, D.O.A....) match.

**How to apply**: a wrong match is cleared in
`copyright_evidence_overrides.json`, never by loosening the match — OCR noise
only ever causes a miss, since a title must match exactly. The CCE_RULE bump
re-asks every pre-1950 title once. `tools/test_cce_renewals.py` holds the
known renewals, ten canon controls and both printed formats (the 1950s
section, the 1970s interleaved list); it runs in the pipeline gate.


## 158 — A colorized copy is a version of its black-and-white film, never the default
*Date: 2026-09-30*

An upload that states it is colorized (`build_sqlite._colorized_upload`: its id
or title says colorized/colourised, DeOldify, or "in color") merges into its
film's card when imdb, year and runtime say it is the same film, and it never
wins the card: `dedupe_by_imdb` and `merge_film_duplicates` both rank a
colorization below every other copy. It stays reachable through the versions
picker, which reads `item_aliases`. A colorization with no black-and-white copy
served remains its own card, since there is nothing else to default to.

**Why**: the owner, asked how 293 served colorized copies should be treated —
*"The colorized versions should be available via the versions options on a
given title, but should never be the default one offered. The original black
and white should be what the title offers by default but an individual user
should be able to select the color versions if they wish."* Until now a stated
colorization was the opposite: a separate card, because B&W versus color was
read as two works (Decision 084), so Dracula had three cards, one of them
colorized. Measured on the live catalog: 187 of 291 colorized copies fold into
their film; 104 remain their own card.

**How to apply**: never let a colorization outrank an original on video quality,
captions or votes; the colorized flag is the first term of both rankings. A
color REMAKE is not a colorization and stays apart on its own imdb id and year.
`tools/test_colorized_versions.py` holds the merge and the default with a remake
control; `test_color_guard.py`'s two colorization cases now expect a merge.


## 159 — An undated upload a reviewer judged modern is hidden until it is identified
*Date: 2026-10-01*

An undated title listed in `shared/editorial/likely_modern.json` ({archiveID:
reason}) is `likely_modern_unidentified`, a HIDE bucket in `audit_rights.bucket`,
instead of `unknown_year` (keep). A year found later is judged normally, and
deleting the entry lifts the hide. Six titles to start (an undated "Popeye", a
mid-2000s mockumentary, an unidentified modern feature, three numbered uploads
from an uploader whose other ~80 items are modern).

**Why**: the owner, offered "hide until identified" or "keep showing" for
undated non-government uploads that reviewers believe are modern but cannot
date — *"Hide until identified"*. Decision 151 keeps a title when "we truly
don't know", and that stands for the genuinely unknown; but a pass over the 98
served undated non-government titles found 17 modern works (Hong Kong features
of 1981-83, a 1986 Cannon film, 2000s studio trailers) dressed by wrong matches
as silent films — about one in six. A reviewer's reasoned "modern" is not "we
don't know".

**How to apply**: add an entry only with a reason a reader can check (what
the reviewer saw); never on a hunch about an uploader alone — two of the same
uploader's titled uploads were checked against their own records (a 100- and a
78-minute film matching their titles) and kept. `tools/test_likely_modern.py`
holds the hide, the unlisted control, and that a found year is judged normally.
The host's refusal sentence exists on Apple and Android (§8 rights coverage).


## 160 — Every sound is held to the age of its own picture, and the audio clock is the wall clock
*Date: 2026-10-02*

Every Studio capture buffer carries its capture time on the host clock
(`StudioCaptureClock`): the camera's and the microphone's from their capture
sessions' `synchronizationClock`, a shared window's from ScreenCaptureKit, a
call's from its IOProc. The engine measures how old the host-seat camera's frame
is when it is composited, and each call window's, and the mixer holds the
microphone and each call to the age of its own picture — silence inserted or the
oldest audio dropped, a few milliseconds at a time, only while that voice is
quiet unless it is more than 80 ms off. The mixer's timer makes every packet that
is due (up to eight a tick) rather than one per fire.

**Why**: the owner, after the first full show: *"The audio from my microphone did
not (for the most part) line up perfectly with my video."* Nothing aligned them:
the microphone reached the mix in milliseconds and sat in its ring at whatever
depth it settled to when the show began, the camera took the camera's latency,
and a `DispatchSourceTimer` that could not run on time merged its missed fires,
losing a 23 ms packet each time and drifting the audio behind a picture that
renders late frames back to back. Measured on the Mac: the voice +40 to +65 ms
late unaligned, +2 to +13 ms aligned. The film's own sound and picture were
already aligned (§D21, the AWMACSYNC trim), so a mic sample read at the same
instant as the camera frame it belongs with is in sync on the wire too.

**How to apply**: a new audio source writes its ring with `capturedAt:` and the
engine sets its `syncTargetAge` from the picture it belongs with; never add a
fixed delay constant in its place — latency differs by device (a borrowed iPhone's
camera is hundreds of milliseconds). `AW_STUDIO_SYNC=off` is the control. The
`AWSHOW` line (every build, every ten seconds) carries `camAgeMs`, `micSyncMs`,
`callSyncMs` and `mixCatchUp`, so a real show can be read afterwards. Still
unproven with a physical flash and beep (`tools/studio_flashbeep.swift`): the
bench camera faces a bright window.
