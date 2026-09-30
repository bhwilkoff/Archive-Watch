# Database audit loop (2026-09-29 →)

Owner, 2026-09-29 (/loop): *"a full audit of our database looking for the
following issues and fixing them or further enhancing them wherever they exist:
1. Malformed metadata ... 2. Non-professional posters or backdrops ... 3.
Incorrect copyright data ... 4. Archive.org links and other video files ... 5.
Issues with the database build process, the 'wanted titles' process, or any of
the other Github workers/actions that touch the database ... you are allowed to
rewrite copy if that is the only way that you can make the data work."*

Every fix lands where the next build re-applies it (remediate rules, editorial
tables, a scheduled workflow), never only in one published catalog.

## Baseline (live catalog-db, 2026-09-29, 22,557 served playable titles)

| Area | Measure | Count |
|---|---|---|
| 1 | synopsis empty | 2,902 |
| 1 | uploader synopsis never reviewed | 2,593 of 5,807 |
| 1 | synopsis unterminated / < 40 chars | 1,346 / 321 |
| 1 | uploader voice / all caps | 146 / 15 |
| 1 | year missing / impossible (<1888 or future) | 1,130 / 10 |
| 1 | title all caps / file-name junk | 18 / 22 |
| 2 | artwork not professional (archive thumb) | 3,115 (+8,079 generated stills) |
| 2 | no backdrop / of those with a TMDb id | 18,791 / 7,909 |
| 2 | poster marked dead | 426 |
| 3 | rights buckets | presumed_pd 9,429 · safe_pd_age 7,095 · safe_gov 3,519 · renewal_zone 2,036 · commercial_keep 427 · unknown_year 170 · archive licence 34 · cc 1 |
| 4 | playback last checked before 2026-08 | 8,320 |
| 4 | download not an mp4 (.mov, `.mp4.~1~` backups, .mpeg4) | 7 |

## Findings

- A. ✅ Backdrops. They were only written as a side effect of a poster change,
  so a film matched while its poster was already professional never asked TMDb
  for one. `tools/fill_backdrops_tmdb.py` (stored tmdbID only; year ±2 and
  B&W-vs-1970+ guards; image_rejects honored), now a step of the weekly
  resource-posters workflow. First run: 9,993 targets, **4,468 filled**, 5,454
  TMDb has none, 52 refused on a year disagreement (queued: B), 8 B&W-modern.

- B/C. ✅ **A borrowed silent-era year was a public-domain claim.** A year
  before 1930 is the whole case for "public domain by age", and Decision 114's
  id check only fired for ids naming 1978+. 356 items (60 visible) carried an
  old namesake's year while their own title/id/filename named a later one:
  The Court-Martial of Billy Mitchell (1955) as "Court Martial" 1928, Miracle
  of the White Stallions (1963) as 1919, Vengeance Is Mine (1979, a YTS rip) as
  1917, Sweet Bird of Youth, A Doll's House (1973), Dark Passage (dated 1881),
  Sirocco (1065), all typed silent and public domain. Remediate rule
  `fix_old_year_on_newer_upload` (the reverse of #20) takes the item's own year,
  clears the borrowed match and re-types it; reissue/restoration markers,
  camera file numbers, archive.org's `_YYYYMM` dedupe suffix and years that are
  part of a title are exempt (`test_old_year_on_newer_upload.py`, controls
  verified). The corrected titles now fall to the rights rules on their real
  year, and `corroborate_copyright` re-asks whenever title or year changes
  (`copyrightCheckedFor`) instead of waiting 90 days. Plus 25 original-release
  years where the item carried a US/reissue date (Nosferatu 1929 -> 1922, Häxan,
  The Hands of Orlac, Miracle of the Wolves...), 42 title fixes (file names,
  all caps), and two match rejects (a Berenstain Bears upload wearing an 1899
  bear film's year and synopsis; Sirocco's wrong IMDb id).
- K. ✅ **No pipeline test ran in CI.** Two had been failing unnoticed: the
  Studio's rights explanation had no sentence for Decision 151's
  `copyright_claim_evidence` (a host would read the raw name), and the Roku feed
  test's expected reason for a year of 1065. Both fixed;
  `tools/run_pipeline_tests.sh` (43 tests) is now publish-db's first step.

- D. ✅ **Backup revisions and records.** The shared picker (`archive_lib.pick_video`)
  could choose archive.org's `history/files/<name>.~N~` — a REPLACED file's old
  revision (Revelation 1924, an Expedition 68 docking). It now refuses them
  (test case in test_private_derivative), and the daily liveness check repoints
  any item still baked to one. `repick_derivatives.py` had never been scheduled;
  it now runs bounded in check-liveness. Found alongside: **44 Great 78 Project
  record transfers** (collection `78rpm`) served as feature films — 0 s long,
  their "video" a 4.8 KB label photograph. Remediate now excludes the collection
  as not a film.

- K2. ✅ **The rights reconcile re-showed titles while a question was open.** The
  borrowed-year fix moved Sybil (2007), Silas Marner (1988), two 1999 Sherlock
  Holmes VHS rips and ~30 more from `wrongmatch_idyear` (hide) to
  `modern_copyright_unconfirmed` (confirm), and the reconcile showed them until
  the network confirm pass could run — the 01:48 publish served four. A modern
  year with no licence is now hidden pending confirmation (the confirm pass
  selects by bucket, so it still rescues or re-dates them), and a fix/confirm
  bucket never re-shows an item already hidden. `wrongmatch_bw` no longer
  applies when the modern year is the item's own (Vengeance Is Mine's
  `1979.1080p...yts` id). Measured locally: 35 hidden, the 30 false un-hides gone.
- L. ✅ 20 compilation reels to not_films ("Filmography: Roger Corman",
  "01-judy-garland", Disney/Paramount UK VHS promo reels) — surfaced when their
  borrowed years were corrected.
- E1. ✅ Uploader synopses, batch 1 (60, popularity-first): 51 kept, 9 rewritten
  from their own facts where a critic's voice stood in for the plot (Chirurgie
  fin de siècle, Street of Forgotten Women, Wiggle Your Ears, Fandango, Rural
  Life in Maine); "in colour" -> US English; two titles' lost accents restored.

- N. ✅ **Unrelated uploads wearing a silent feature's identity.** 420 visible
  items run under a third of the film they are matched to. Most are right:
  serial chapters, 1920s Kodascope condensations, surviving reels, TCM clips.
  But among them, served as public domain by age: a stock clip of red dice as
  "Red Dice" (1926), a Sopranos clip as "Just Tony" (1922), four G4TV web clips,
  a Minecraft video, Teletubbies, a modern furniture ad as "French Dressing"
  (1927), a news clip as "Passers-By" (1920), songs and sermons. Their catalog
  titles had been overwritten by the match, so the runtime rule (which needs
  the item's title to disagree) could not see them. Judged by hand against
  archive.org's own title (now cached in archive_own_meta, `title`): 29 to
  not_films, 10 real films with the wrong match to match_rejects. A rule on the
  own title was tried and REVERTED — it would have cleared Nosferatu
  (`Nosferatu_DVD_quality`), Foolish Wives (its English title in parentheses)
  and Troopers Three (a cast list with no "starring"); uploaders' naming is too
  varied to judge by title alone, and clearing a real film is the worse error.

- L2. ✅ `exclude_not_films` skipped an item another rule had already hidden, so the
  20 reels never got their `not_a_film` marker and the next publish showed them
  once their corrected years left the rights hide. The marker is now always
  written (as takedowns do). Synopsis batch 2: 55 kept, 5 rewritten.

- E3. ✅ Synopsis batch 3 (70): 20 rewritten from their own facts (IMDb page dumps
  on Lumière films, "Re-upload!", "please be my guest to add comments",
  reviewer asides), 2 nulled (a Tonight Show pack's "better for everyone in
  bulk"; Emile Cohl's Automatic Moving Company carrying a Baltimore
  documentary's description), 48 kept. The batch also surfaced six more
  uploads wearing old films' identities (a Pokémon Showdown stream as The
  Showdown 1923, a Brahms recording, a Walgreens logo history dated 1901, a
  modern French thriller "film complet" as Feuillade's Le Poison 1911) — to
  not_films; a NASA SCI Files segment dated 1909 (year removed). New
  `type_corrections.json`: FedFlix files The Great Train Robbery under news, so
  it was typed a newsreel.

- P. ✅ **Collector titles.** 161 served titles were a collector's CAPITALS title
  followed by its credits ("A SAILOR MADE MAN Harold Lloyd Silent A Hal Roach
  Comedy", "FICKLE FLORA Our Gang Silent (9.5mm Footage ..."). sanitize_title
  now keeps the capitals, title-cased, when the tail is credits or format
  words (a lone trailing article and a person's initials go back to the
  credits); `test_caps_credit_title.py` with NASA/GMT/"EAST OF BORNEO"
  controls, in the CI gate. And 184 titles used two apostrophes as a quote
  mark (`''Lassie'' - The Tree House`). 492 titles change in all.

- P2. ✅ Uploader shelf labels on TV titles ("Fifties Television:", "Artistic
  Masterpiece:", "1950's Pop Culture:", "(Format: iPod)", "- Misc episode")
  stripped; show names ("Diver Dan:", "The Big Picture:") kept. Tested.
- Q (not a defect). The ~1,000 classic-TV items that stay `tv-special` are
  unmarked orphans; folding only episode-marked orphans into spines is the
  owner's recorded decision (Decision 036, `_orphan_is_episode`). They are on
  the TV tab's TV Specials, never in Movies.
- H (healthy). Playback: all 22,631 served titles `playbackVerified`, all
  checked within the 90-day liveness policy (14,201 in the last 30 days);
  22,626 pass the strict AVFoundation check, 5 not yet run.

- E4. ✅ Synopsis batch 4 (70): 29 rewritten — archival shot lists and timecodes
  ("10:16:50:14 MS 1920s young female teacher..."), NARA catalog boilerplate
  ("Department of Defense. Department of the Army... Reel 1 7 Reels"), a Ford
  legal fragment, "Listed as Public Domain by Wikipedia", and a Hands of Orlac
  summary that credited the wrong director; The Sawmill (Larry Semon) carried an
  Odyssey travelogue's text (nulled). 3 titles fixed.

- I1. ✅ **URAA (Decision 156).** No rule knew that URAA restored US copyright
  to foreign works: ~2,800 non-English post-1930 films (M 1931, Viridiana, 1930s
  German features) sat in presumed_pd. Owner, asked: "Recommend never, keep
  findable". Production countries fetched for all 11,754 matched films
  (`origin_cache.json`, weekly); `uraa_restored` flags 3,306 served titles
  (incl. 443 British), US co-productions / government / licensed exempt.

- R. ✅ **Summary ACCURACY, not just form** (owner, mid-loop: "what about the deep
  review of each summary/description? I want to make sure that info is accurate
  and not just that our data is well categorized"). Every served summary checked
  against the item's own facts: a Wikipedia lead states its film's year and
  director ("X is a 1953 American film directed by ..."), so 1,121 Wikipedia
  summaries were compared with the item's year, director and cast. 44
  contradictions, judged one by one, split both ways:
  - the summary described ANOTHER same-titled work (the Terrytoons cartoons
    Romance, What a Night and Happy Go Lucky wore a Garbo drama's, a British
    film's and a L'Herbier film's articles; Keaton's The Love Nest a German
    film's; Epstein's Coeur fidèle, Lubitsch's Madame Du Barry and Stiller's
    The Flame of Life likewise). New `synopsis_rejects.json`: remediate drops a
    rejected summary every build, or the title lookup restores it.
  - the CATALOG was wrong and the summary right: 12 years (The Wizard of Oz
    1925, The Shriek of Araby 1923, Gösta Berling 1924; "Wien" is Vienna 1910,
    a 1943 film) and 10 directors (Oh, Susanna! is Joseph Kane's, not its star
    Gene Autry's; Broken Blossoms was credited to Teruo Ishii). New
    `director_corrections.json`.
  A "starring" cross-check against cast lists found 16 more, nearly all partial
  cast lists rather than wrong summaries.

- R2. ✅ **Decision 124 had stopped running.** `synopsis_provenance.py` (TMDb's
  overview replaces an uploader's text on a matched film) ran once by hand on
  2026-09-16 and was never scheduled, so 1,045 titles matched since kept notes
  like "if you're like me", "a large ProRes file", a 1925 newspaper review, or
  "No bad reviews ... will be tolerated" where TMDb has the film's plot.
  Applied, and now a step of the TMDb enrich workflow.

- R3. ✅ **Accuracy against an independent source.** Uploader summaries set beside
  OMDb/TMDb plots: where both exist they mostly agree, so the uploader text's
  problem was form, not truth — and 267 served summaries were not in English
  at all (182 Spanish Wikipedia pastes on Argentine films, SVT Swedish, French,
  Portuguese). synopsis_provenance now falls back to OMDb's plot (the same
  checked tier) when TMDb has none: 274 titles. But OMDb and TMDb "plots" are
  sometimes a USER'S REVIEW ("The Terrytoons are oddly interesting", "This
  film is a treasure", "I could spend quite some time reflecting"): a review
  filter now guards both sources (`test_synopsis_review_filter.py`, in the
  gate), and 20 live review-summaries were removed by hand (a blanket revert
  on the filter was tried and abandoned — it removed plots that quote dialogue).

- T1. ✅ Translation batch 1 (30 of 204 non-English summaries): faithful English,
  without the reviewer asides and pasted cast lists. The batch also corrected:
  English titles on foreign-language copies ("Le Mécano De La Générale" -> The
  General, "Nanouk L'esquimau" -> Nanook of the North) — and, a RIGHTS point,
  Universal's Frankenstein (1931), The Invisible Man and Bride of Frankenstein
  were titled "... Doblada Al Español", which kept Decision 151's
  title-and-year renewal check from matching them; 25 Deutsche Wochenschau
  newsreels (the propaganda ministry's) added to propaganda.json one by one
  with a source; a 1925 erotic short marked mature ("erotic short" joins the
  adult synopsis markers, narrowly — "erotic film" would have caught Häxan).

- T2. ✅ Translation batch 2 (30 more; English titles for The Unknown, The Phantom
  Carriage, L'Âge d'Or, The Lodger, The Property Man, Get Carter...; "Das
  Kybalion" 1908 is a modern video about a book, to not_films).
- U. ✅ **The rights audit judged uncorrected titles.** title/year corrections are
  applied by remediate at build time; rights-audit read catalog.json raw, so
  the Copyright Office check (title + year) looked for "Frankenstein Doblada Al
  Español". rights-audit now runs remediate first.

- T3. ✅ Translation batch 3 (31; English titles for Night Owls, The Laurel-Hardy
  Murder Case, The Mystery of the Eiffel Tower, A Straightforward Boy, The Fall
  of Troy...; Max Linder's Three Must-Get-Theres carried a French Wikipedia
  biography of Linder; "Gebt mir 4 Jahre Zeit" (1937, NSDAP) to propaganda.json).
- U2. ✅ With remediate before it, the Copyright Office check found 1,249 claims
  (was 947). An item checked before `copyrightCheckedFor` existed is re-asked
  when a person corrected its title or year.

- V. ✅ **Decision 157.** The printed Catalog of Copyright Entries' 1950-77
  motion-picture renewals parsed (11,579); the copyright check reads them for
  pre-1950 titles. 983 served 1930-49 titles carry a printed renewal
  (Frankenstein R243591); 0 of 25 public-domain canon controls match.

- V2. ✅ The rights audit read the printed renewals: 969 kept titles now carry a
  Catalog of Copyright Entries claim (copyright_claim_evidence 1,249 -> 2,221),
  Frankenstein, The Invisible Man and Bride of Frankenstein among them.
- T4. ✅ Translation batch 4 (33; Battleship Potemkin, Detour, Hollow Triumph,
  Penny Serenade, The Man Who Laughs... under their English titles). A football
  club's anthem dated 1900 to not_films; UfA-Tonwoche to propaganda.json.

- T5. ✅ Translation batch 5 (39: mostly Argentine features, each from its own
  "Sinopsis" with director and stars; Go for Broke!, My Dear Secretary under
  their English titles). ~38 remain.

- T6. ✅ Translation complete: all 204 non-English served summaries now English
  (the last 37 include the Lumière films shot in Mexico in 1896, Cabiria,
  Different from the Others, Laborer's Love, The Navigator). A modern Italian
  political appeal dated 1922 to not_films. New non-English uploader text
  arrives with ingest, so it stays in the review queue.

- V3. ✅ Printed renewals live: served 22,523 -> 21,722; presumed_pd -790.
- W. ✅ **Credits.** remediate `tidy_credits` every build: a same-named
  aristocrat's Wikidata label on an actor stripped with his borrowed portrait
  ("Charles Middleton, 1st Baron Barham" in The Flying Deuces; 7), one actor
  named once with both roles (76), slash- and URL-joined director fields made
  names only (7). An Amiga 500 game longplay wearing a 1922 Fox western to
  not_films. `test_tidy_credits.py` (with "The Earl Carroll Girls" control), gated.

- E5. ✅ Review batch (55): 33 rewritten / 7 removed — the Bill Sprague
  Collection's rants at complainers ("a crazy doctor whose office is in a
  manhole"), a collector biography repeated on every Ellwood Hoffmann home
  movie, scene-release tags in titles ("A Girl In Every Port HANDJOB", "L'Argent
  .MX"). My own slip — decisions keyed on ids a listing had truncated — was
  caught and re-applied; remediate now warns on any editorial id not in the
  catalog.

- E6. ✅ Review batch (55): 26 rewritten, 1 removed (a disc-extraction how-to
  with emoji), 24 titles fixed; a crude summary on an Oswald cartoon rewritten.
  And the collector's rant is now a rule: the uploader-voice sanitizer drops
  sentences warning off complainers ("Please no bad reviews", "Complainers are
  whisked off to their nearest urgent care center") — 65 served summaries,
  every build; tested with a control (Pvt. Snafu complains).

- E7. ✅ Review batch (60): 21 rewritten, 1 removed, 17 titles. One uploader's
  "(Fanmade)" relabels put other studios' cartoons under Looney Tunes or
  Terrytoons (Disney's The Chain Gang and The Gorilla Mystery, Fleischer's Dizzy
  Dishes, Lantz's Oswald, Disney's 1922 Laugh-O-Gram Cinderella as "Bray"): 10
  given their real titles and studios. Four uploader compilations and modern
  Philippine TV airchecks dated 1930 to not_films.

- E8. ✅ Review batch (60): 18 rewritten, 1 removed, 20 titles. A read-aloud of
  Alfred Rosenberg's Nazi book Der Mythus to not_films; "Andy Hardy's movie
  (what i could find)" dated 1930 is Andy Hardy's Private Secretary (1941) —
  title and year corrected so the renewal check can judge it; two uploader
  compilations (Warner 1930-43, a Popeye DVD set) to not_films.

## Queue



- E-next. Review batches now judge ACCURACY: each uploader summary beside an independent source (TMDb overview, Wikipedia lead) where one exists; tmdb/omdb/wikipedia summaries of weakly matched items get the same look.


- N2. `01-rec-2024...` 1-2 minute recordings wearing The Last Command, The Navigator, Beggars of Life (hidden now, but the ingest keeps admitting such recordings).
- O. Wider compilation sweep ("... Collection", "PD Cartoon Collection", Our Gang collection) — each judged, not by keyword.
- M. Decade phrases contradicting the year ("1960s waves breaking" dated 1896).
- E. The 2,593 unreviewed uploader synopses (metadata_review.py, popularity first).
- F. 2,902 empty synopses: which have a source to fill from.
- G. 3,115 archive-thumbnail posters: any professional source.
- I. Rights: renewal_zone / commercial_keep / unknown_year spot audits.
- J. Workflow health across every catalog writer; the wants pipeline.

### O — the compilation sweep (2026-09-29)
Served titles matching collection words or running over 4 hours: 235, judged by
the FILE each one plays. 36 hidden (not_films): 1980s broadcast airchecks, eight
Dance Party USA tapes, cartoon "seasons" whose played file is a copyrighted short
(Get a Horse! 2013, Mother Pluto 1936, Topsy TV 1957, A Pain in the Pullman 1936),
a game walkthrough dated 1916, DVD-set discs. 10 collections retitled to the one
film they play (The Barn Dance, All Wet, Trolley Troubles, Sick Cylinders, The
Winged Scourge, Colonel Heeza Liar's African Hunt, Knock on Any Door 1949 — now
open to the renewal check); their collection summaries rejected. Faces of Death
dated 1978 (was 1900) and hidden pending confirm. Kept: serials, complete-series
TV (owner rule), real single-reel compilations (British WWII PIFs). Visibility
diffed: 0 un-hidden.

### E9 — review batch (2026-09-29)
40 summaries (1930-34): 24 rewritten — credit lists for Peacock Alley, 1933 newsreel narration with stray quotes and typos (Thanksfiving, frances, Paterson for Patterson LA), reviewer voice (Hash Shop, Betty Boop, Plant Life), a donation plea; 16 kept. Titles: The Hash Shop, Telephone Memories (Reel 1/2).

### E10 — review batch (2026-09-29)
40 summaries (1934-35 and the 1890s-1900s): 22 rewritten (all-caps Chevrolet reel, an AI-style home-movie blurb, uploader voice on Edison shorts, typos, Hauptmann-trial newsreels named properly), 15 kept. Out: a spam upload dated 1889, a 1990s Japanese TV segment and a helicopter safety briefing both dated 1900. Dated right and so hidden pending confirm: Cosmos (1980, was 1901), Lumière! (2016, was 1895). Alice's Wonderland is 1923 (was 1931 under the wrong title); the Wright brothers reel loses its 1903 (no film of the first flight exists).

### P — the 1900/1901 placeholder year (2026-09-29)
Uploaders to the open collections set date 1900 or 1901 on anything, and ingest
read it as the film's year: public domain BY AGE, typed silent-film. Two were
ingested this week (Disney's 2011 Jake and the Never Land Pirates pilot,
09-26; a 90s mall-music mix, 09-29). Of 44 served items whose 1900/1901 has
no witness (no Wikidata year, IMDb/TMDb id or year in the title/id), 20 were
modern media (Enya's Watermark, a Gladiator clip, a 2020 recitation, safety
videos, AI-animated photographs) — hidden as not-films — and 6 were undatable
(two 8mm films, a Clarke School film, a Bimbo dub): year cleared, so the audit
judges them on evidence (no_evidence). The rest are real turn-of-the-century
films in curated collections (Tetherball, The Cheese Mites, Pathé fragments).
Structural fix: ingest holds `held_placeholder_year` — 1900/1901 from the
uploader alone, in the open-upload collections (opensource_movies, community,
folksoundomy, musicvideobin). test_placeholder_year.py, with five controls, in
the pipeline gate (47/47).

### P2 — every unwitnessed pre-1931 year on an open upload (2026-09-29)
Widening P past 1900/1901: 325 served open-collection uploads carry a pre-1931
year that no id, Wikidata year, IMDb/TMDb match or title/id year backs. Read
title by title: 30 are modern media hidden as not-films (a Grappler Baki OVA
dated 1888, a 1989 safer-sex video dated 1905, 2018's Apocalypse dated 1918,
Jeeves and Wooster dated 1930, video-game recordings, a YouTube Poop, an
audiobook, music anthologies, two cartoon compilations); 4 undatable ones lose
the year (three now meet no_evidence). The rest are real silent-era films and
newsreels uploaded to the open collections (Mexican Lumière views of 1896,
Marey, Ruttmann's Opus films, Hal Roach shorts). No ingest rule covers the
other years yet: most carry a real film's year, so the signal is the title,
which the existing held_suspect_year already reads.

### Q — a multi-work item played its LONGEST work, not its own (2026-09-29)
`pick_video` ranks by format tier and then size, so an item holding a studio's
shorts played whichever ran longest: April Maze played Felix Finds Out,
Fiddlesticks played Molly Moo-Cow and the Indians, Arctic Antics played King
Neptune, A Tale of Two Kitties played Jungle Jitters, Greek Mirthology played
Insect to Injury — every one with its own file in the same item. And
check_liveness then wrote that file's length over the runtime. Fix:
`pick_video(files, title)` restricts a multi-work item to the files named for
the title (`title_files`); ingest, check_liveness and repick_derivatives pass
the title, and check_liveness repoints a baked file that is another work in
the item. test_title_file_pick.py (four controls) in the gate, 48/48. A
one-time scan of the 6,505 served titles whose file is not named for them
repoints the rest. Seventeen bundles whose collection title names no file are
hidden as not-films (3O's 0Ldies played That Touch of Mink, 1962; A Ghost
Story for Christmas played a 2013 episode).

### E11 — review batch (2026-09-29)
40 summaries (1906-13): 27 rewritten — archival shot lists in slashes and caps (earthquake, Panama Canal, Captain Lewis's Chinatown), a library rights notice, timecodes and mojibake (Buffalo Bill), "(?)" guesses, a reviewer's musing (Grandstand Crowd), multi-film Fantômas blurbs; 1 placeholder ("To be logged.") removed; 12 kept. Quo Vadis dated 1913; four titles cleaned.

### E12 — review batch (2026-09-29)
40 summaries (1913-17): 22 rewritten, 17 kept, 1 bundle out (Maurice Tourneur films in decorative lettering). Shot lists and "(?)" guesses cleaned; 16 titles lose archival can numbers and filename debris. Jack London's last footage dated 1916 (the summary said he died in 1915), the Joffre/Somme reel 1916, Chaplin's Shanghaied 1915.

### E13 — review batch (2026-09-29)
40 summaries (1917-22): 35 rewritten — timecoded shot lists, "to be logged" notes, a public-domain boilerplate, trolling ("all of the trolls can keep quiet ... ROFL"), a Polish Caligari summary, reviewer asides on the Lingerie films; 1 placeholder removed; 4 kept. 13 titles cleaned (Easy Street, Tarzan of the Apes, The Jack-Knife Man, The Cabinet of Dr. Caligari). The Arctic expedition film is 1922 (its own text says so).

### R — stock-footage shot logs, cleaned every build (2026-09-29)
The review batches kept meeting the same debris by hand: SMPTE timecodes
("06:40:55:18 CU sign ..."), shot codes (VS, CU, LS) and the footage house's
own notes ("Some excellent shots to be logged."). 137 served summaries carried
them. remediate's `_strip_shot_log` (uploader text only) keeps the summary that
precedes a timecoded log, or, when the log is all there is, keeps its words
without the codes; 131 summaries change. test_shot_log.py pins it with three
controls (a clock time in a plot, "vs" in a title, CU inside a word); gate 49/49.

### E14 — review batch (2026-09-29)
40 summaries, mostly Prelinger home movies and Gould cans: 19 rewritten (cataloguer notes: "Viewing notes state", "Container marked", "Time in:", "STOCK SHOTS:", "(good)"), 21 accurate shot lists kept. Years the footage itself contradicts: Earhart's Hawaii-Oakland flight is 1935 (was 1930), the Golden Gate Exposition marionettes 1939; four reels dated 1930 whose content is later (Huey Long monuments, a late-1940s reel, WWII captured Japanese film, late-1930s New York) lose the year. Visibility unchanged. Noted, owner-reserved: Voyage of the Damned (1976, 3,972 votes) sits in the 1964-77 band.

### S — B&W readings with no number behind them (2026-09-29)
colorMode is on 27,500 served items, colorSat (the saturation reading that lets
build_sqlite.color_confident judge it) on 4,506: every reading before
2026-08-18 is a bare verdict. Messiah of Evil (1973) and Voyage of the Damned
(1976), both color films, read B&W. classify_color only targeted items with no
colorMode, so those verdicts were final. It now also re-measures a B&W verdict
with no colorSat on a film from 1960 on (1,926 items; 1,200 a run, three runs a
day). Night of the Living Dead stays B&W on any reading.

### E15 — review batch (2026-09-29)
40 summaries (1920-21): 16 rewritten (a Polish review of Der müde Tod, a comment-section policy on Keaton's The Haunted House, "YAn interesting..." on The Golem, a numbered NARA shot list, mojibake, "(sic)"), 2 non-summaries removed ("Skeletal entry.", a film-library catalog code), 22 kept. 10 titles cleaned (The Golem, The Saphead, The Goat, The Haunted House twice, Destiny). Five Adult Film History Project stag films confirmed marked mature (archive.org's own subjects).

### T — star names welded onto titles (2026-09-29)
203 served titles carried a performer's name: `Charlie Chaplin's "The Rink"`,
`THE PALEFACE Buster Keaton`, `RAGGEDY ROSE Mabel Normand, Max Davidson, ...`,
`A Night In The Show A Charlie Chaplin Essanay Comedy`. A pattern proposed 197
corrections; each was read, 18 rejected because the name IS the title (Bela
Lugosi Meets a Brooklyn Gorilla, Life with Buster Keaton, The False Max
Linder, Intimate Interviews with Bela Lugosi) or the item is a bundle, and 43
corrected by hand to the film's real title (Kid Auto Races at Venice,
Tillie's Punctured Romance, Caught in a Cabaret, His Favorite Pastime, Too Many
Mammas, A Busy Day). 179 entries in title_corrections.json. Not a remediate
rule: the name-is-the-title cases are too many for a pattern to tell apart.
Knock-on: dup-merge (Decision 040) keys on the title, so several Chaplin and
Keaton copies now cluster at the next build.

### T2 — mixed-case caps titles (2026-09-29)
Pure-uppercase titles are already recased by remediate; 23 mixed ones remained ("D W Griffith's THE SEALED ROOM", "THE PHANTOM CHARIOT , Körkarlen", "ADVANCE INTO POLAND of 4)"). 13 fixed by hand; the rest are NASA/ISS mission codes and modern TV episode labels, left.

### E16 — review batch (2026-09-29)
40 summaries (1922-25): 21 rewritten, 19 kept. Two Polish reviews and a Spanish lead become summaries (The Last Laugh, Nosferatu); a false etymology removed ("Schreck ... meant Scream of Terror"); uploader asides ("old timers I talked to ... No kidding!", "No Rohauer trappings or crappings", "THIS FILM IS IN THE PUBLIC DOMAIN", "Archived by runner_up"). Die Nibelungen part one is 1924 (was 1922), The Electric House 1922 (was 1923). 18 titles cleaned.

### U — file-format debris and three rights misreadings in titles (2026-09-29)
69 served titles matched format/quality tokens (most were "Pal"). Real cases:
32 "Public Domain Animation" items, one per year 1929-60, each playing one
cartoon — retitled and dated from the played file (Hollywood Capers 1935,
Hell-Bent for Election 1944, A Is for Atom 1953); the "1960" item plays John
Hubley's Everybody Rides the Carousel (1976), now dated 1976 and in the owner's
1964-77 band. Metropolis (Giorgio Moroder Edition, 1984) and a 2023
colorization, both dated 1927 and so public domain BY AGE, now carry their own
years and are hidden pending confirm (modern_copyright_unconfirmed) — a
derivative's new music and color are not the 1927 film's. 22 more titles lose
"Blu Ray", "Hq", "VOSE FAC 6", "Restored Public Domain Horror Classic".

### V — Dracula (1931) was served: the printed renewal was OCR'd "3l1" (2026-09-29)
A 1931 film is under US copyright until 2027, and Universal renewed Dracula in
1958 (R227698). The Catalog of Copyright Entries prints it; the OCR reads the
original date "© 2Feb3l1; LP1947", and ORIG wanted two digits. fetch_cce_renewals
now reads l / I / | as 1 and O as 0 inside a date or number (and tolerates a
stray third year digit): 11,579 -> 11,791 renewals, the ten canon controls
still clear. 21 served titles newly carry a printed renewal — Dracula (3 copies,
one colorized), Stagecoach (2), The Invisible Man Returns, MGM's Escape (1940),
The Spider (1931), Ellery Queen, Terrytoons. CCE_RULE 3 -> 4 re-asks every
pre-1950 title; rights-audit dispatched. Wrong matches go in
copyright_evidence_overrides.json (Decision 157), never a looser rule.

Open, found on the way: 293 served items are COLORIZED copies (Dracula, His Girl
Friday, Stagecoach...), dated with the original film's year. A colorization is
a new work; whether a fan's AI colorization or a commercial one (Legend Films,
Hal Roach/CST) may be served is a rights call — asked of the owner.

### W — colorized copies become versions (2026-09-30, owner, Decision 158)
187 of 291 served colorized copies fold into their black-and-white film as a version and never win the card; 104 have no B&W copy served and stay their own card. test_colorized_versions.py in the gate (50/50).

### Q2 — the file scan's result, and a crash it exposed (2026-09-30)
The one-time scan of 6,505 served titles found 119 whose baked file is not the
one named for the title. Read one by one: 83 repointed, 36 left (series and
serial chapters, where a title match only means another episode — Flash Gordon
chapter 10 would have become chapter 9; and fragments like Destiny's 28-second
"Destiny.mp4"). The worst: silent features playing a one- or two-minute screen
recording ("1-REC-2023...ia.mp4") — Bardelys the Magnificent 110 s of 90 min,
Flesh and the Devil 110 s of 112, Beggars of Life 85 s of 82, Eternal Love 79 s
of 70, When a Man Loves, Old San Francisco; Baseball Bugs played an 80-minute
file. Each carries filePickedByTitle.

remediate crashed on a synopsis stored as a LIST (is_adult_signal read it with a
regex before sanitize_synopsis joined it): publish-db failed at 12:20 UTC and the
subtitle apply after it. Fixed with _synopsis_text; test_list_synopsis.py in the
gate (51/51).

### X — a publish over a moved release now MERGES (2026-09-30)
Review batch E16 was published at ~05:45 UTC and gone by midday; its titles
survived only because they live in title_corrections.json. 24 workflows publish
the whole catalog they fetched, so anything published after their fetch and
before their publish was reverted silently. The catalog-writers lock only
serializes workflows with each other. catalog_release now keeps the fetched file
(.catalog_base.json.gz) and, when the release moved, publishes a field-level
three-way merge: this run's changes onto the newer catalog, everything else
theirs. --if-unchanged keeps refusing (exit 3). test_catalog_merge.py holds the
E16 case with a no-base control; gate 52/52.

### Y — Prelinger's standing no longer outranks a printed renewal (2026-09-30)
After the CCE fix, seven served titles matching a renewal stayed visible: all in
"prelinger", which audit_rights kept as safe_gov before any claim, and which
corroborate_copyright never even checked. Read one by one: six real — MGM's
Escape (1940) reel, Warner's Boulder Dam (1936, renewed by United Artists
Associated), Monogram's Junior Prom (1946), Castle's News Parade of 1945, ERPI's
Sound Waves and Their Sources (1933, University of Chicago), Make Mine Freedom
(1948, MGM) — and one false: Prelinger's Free and Easy is a gearshift industrial,
not MGM's 1941 feature (copyright_evidence_overrides.json). A title only in the
Prelinger collections now gets the claim check first; a government collection
stays first, since a government work cannot be copyrighted.
test_prelinger_claim.py (four controls) in the gate, 53/53.

### E17 — review batch (2026-09-30)
40 summaries (1925-27): 24 rewritten, 16 kept. A Polish review of Faust, a broken What Price Glory ("In 1917, W.W. Of course"), shot logs and "Great shot" notes, an uploader leering at swimmers, "Great!". The Graf Zeppelin's arrival at Lakehurst is 1928 (was 1926); The Sensation Seekers 1927. Lindbergh spelled right in three titles, and the ticker-tape parade loses a wrong "Washington D.C.". 12 titles cleaned.

### Z — today's discovery run did nothing, twice over (2026-09-30)
discover-content failed at 09:59 UTC: one candidate in the wants queue carries a
LIST title (archive.org repeats a field as a list), and norm_title called .lower()
on it, so no wants were discovered today. norm_title now takes the first string.
The same run's commit was then rejected five times in a row ("fetch first"):
main was moving fast (this loop commits every few minutes), and the retry loop
slept 2-6 s. discover-content, omdb-backfill and tv-canonical now retry ten
times with a growing backoff. Posters checked the same tick: of 1,004 matched
titles without a designed poster, a 30-title sample found TMDb holds none for
any of them; the pipeline's verdicts stand.
