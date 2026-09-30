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

## Queue

- B. The 52 year disagreements (e.g. White Oak: 1924 here, 1921 at TMDb): which
  side is wrong, per title.
- C. Impossible years (10) and file-name titles (22) into the correction tables.
- D. `.mp4.~1~` backup files and .mov as the playable file.
- E. The 2,593 unreviewed uploader synopses (metadata_review.py, popularity first).
- F. 2,902 empty synopses: which have a source to fill from.
- G. 3,115 archive-thumbnail posters: any professional source.
- H. Playback verification staleness (8,320 unchecked since August).
- I. Rights: renewal_zone / commercial_keep / unknown_year spot audits.
- J. Workflow health across every catalog writer; the wants pipeline.
