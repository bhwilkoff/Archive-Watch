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
